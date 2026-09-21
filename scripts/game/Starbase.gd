@tool
class_name Starbase
extends SpaceEntity
## Station: builds ships, receives mined cargo, defends itself, and runs
## reactors/refineries for a little energy and minerals. Ship costs are
## paid over the build time; a stalled build waits for resources (spice
## fills gaps automatically). A Constructor founds a new starbase as an
## under_construction site that is likewise paid over time.
## Losing every finished starbase loses the match.

const MAX_QUEUE := 5

var queue: Array[String] = []
var build_progress: float = 0.0
var build_stalled: bool = false
var rally_point: Vector2
var has_rally: bool = false
var under_construction: bool = false
var construct_progress: float = 0.0

var _cooldown: float = 0.0
var _last_alert: float = -100.0

@onready var base_sprite: Sprite2D = $Base
@onready var team_sprite: Sprite2D = $Team

func _ready() -> void:
	team_sprite.modulate = Defs.team_color(owner_id)
	if Engine.is_editor_hint():
		return
	super._ready()
	add_to_group("starbases")
	radius = Defs.STARBASE["radius"]
	refresh_stats()
	hp = max_hp * (0.1 if under_construction else 1.0)
	shield = 0.0 if under_construction else max_shield
	_update_site_look()

func refresh_stats() -> void:
	var g := Game.instance
	var hp_frac := hp / max_hp if max_hp > 0.0 else 1.0
	max_hp = Defs.STARBASE["hp"] * g.mod(owner_id, "hull")
	max_shield = Defs.STARBASE["shield"] * g.mod(owner_id, "shield")
	hp = max_hp * hp_frac
	shield = minf(shield, max_shield)
	display_name = "Starbase (under construction)" if under_construction else Defs.STARBASE["name"]

func _update_site_look() -> void:
	modulate = Color(1, 1, 1, 0.45 + 0.55 * construct_progress / Defs.STARBASE["build_time"]) if under_construction else Color.WHITE

## "" if allowed, otherwise a player-facing reason. Costs are paid while
## building, so affordability isn't checked here.
func can_queue(ship_type: String) -> String:
	if under_construction:
		return "Starbase is still under construction"
	if queue.size() >= MAX_QUEUE:
		return "Build queue full"
	var d: Dictionary = Defs.SHIPS[ship_type]
	if d.has("requires") and not Game.instance.has_tech(owner_id, d["requires"]):
		return "Requires " + Defs.TECHS[d["requires"]]["name"]
	return ""

func enqueue(ship_type: String) -> String:
	var why := can_queue(ship_type)
	if why == "":
		queue.append(ship_type)
	return why

## Cancelling refunds whatever share of the cost was already paid.
func cancel(index: int) -> void:
	if index < 0 or index >= queue.size():
		return
	if index == 0 and build_progress > 0.0:
		var d: Dictionary = Defs.SHIPS[queue[0]]
		var frac: float = build_progress / d["build_time"]
		var refund := {}
		for k in d["cost"]:
			refund[k] = d["cost"][k] * frac
		Game.instance.add_resources(owner_id, refund)
		build_progress = 0.0
	queue.remove_at(index)

func set_rally(pos: Vector2) -> void:
	rally_point = pos
	has_rally = true
	queue_redraw()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var g := Game.instance
	if under_construction:
		_construct(delta)
		return
	_regen_shields(delta)
	g.add_resources(owner_id, {
		"energy": Defs.STARBASE["energy_per_sec"] * g.mod(owner_id, "energy") * delta,
		"minerals": Defs.STARBASE["minerals_per_sec"] * delta,
	})

	build_stalled = false
	if not queue.is_empty():
		var d: Dictionary = Defs.SHIPS[queue[0]]
		var per_sec := {}
		for k in d["cost"]:
			per_sec[k] = d["cost"][k] / d["build_time"]
		var f := g.pay_over_time(owner_id, per_sec, delta)
		build_stalled = f < 0.999
		build_progress += delta * f
		if build_progress >= d["build_time"]:
			_launch(queue.pop_front())
			build_progress = 0.0

	_cooldown -= delta
	if _cooldown <= 0.0:
		var e := g.nearest_enemy(self, Defs.STARBASE["range"])
		if e:
			g.fire(self, e, Defs.STARBASE["weapon"], Defs.STARBASE["damage"])
			_cooldown = Defs.STARBASE["cooldown"]
		else:
			_cooldown = 0.2

func _construct(delta: float) -> void:
	var g := Game.instance
	var total: float = Defs.STARBASE["build_time"]
	var per_sec := {}
	for k in Defs.STARBASE["cost"]:
		per_sec[k] = Defs.STARBASE["cost"][k] / total
	var f := g.pay_over_time(owner_id, per_sec, delta)
	build_stalled = f < 0.999
	construct_progress += delta * f
	hp = minf(max_hp, hp + max_hp * 0.9 * delta * f / total)
	_update_site_look()
	queue_redraw()
	if construct_progress >= total:
		under_construction = false
		shield = max_shield
		refresh_stats()
		_update_site_look()
		if owner_id == g.player_id:
			g.message.emit("Starbase complete.", Defs.team_color(owner_id))
			g.sfx.play_ui("build")
		g.selection_changed.emit()

func _launch(ship_type: String) -> void:
	var g := Game.instance
	var dir := (rally_point - global_position).normalized() if has_rally else Vector2.from_angle(randf() * TAU)
	var ship := g.spawn_ship(ship_type, owner_id, global_position + dir * (radius + 6.0))
	if owner_id == g.player_id:
		g.sfx.play_ui("build")
	ship.rotation = dir.angle()
	if ship.def["role"] == "skimmer":
		var giant := g.nearest_gas_giant(global_position, 4000.0)
		if giant:
			ship.order_mine(giant)
			return
	if ship.is_miner():
		var rock := g.nearest_asteroid(has_rally_or(global_position), 900.0)
		if rock:
			ship.order_mine(rock)
			return
	ship.order_move(has_rally_or(global_position + dir * (radius + 30.0)))

func has_rally_or(fallback: Vector2) -> Vector2:
	return rally_point if has_rally else fallback

func take_damage(amount: float, from: SpaceEntity = null) -> void:
	super.take_damage(amount, from)
	var g := Game.instance
	if owner_id == g.player_id and hp > 0.0 and Game.now() - _last_alert > 15.0:
		_last_alert = Game.now()
		g.message.emit("Your starbase is under attack!", Color("ff6a5a"))
		g.sfx.play_ui("alert")

func _draw() -> void:
	if Engine.is_editor_hint():
		return
	super._draw()
	if under_construction:
		# Scaffold progress arc.
		var frac: float = construct_progress / Defs.STARBASE["build_time"]
		draw_arc(Vector2.ZERO, radius + 8.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 48, Color("ffd46b") if not build_stalled else Color("ff6a5a"), 2.0)
	if selected and has_rally:
		var to := to_local(rally_point)
		draw_dashed_line(Vector2.ZERO, to, Color(Defs.team_color(owner_id), 0.5), 1.0, 4.0)
		draw_rect(Rect2(to - Vector2(2, 2), Vector2(4, 4)), Defs.team_color(owner_id))
