@tool
class_name Starbase
extends SpaceEntity
## Home station: builds ships, receives mined minerals, defends itself.
## Losing every starbase loses the match.

const MAX_QUEUE := 5

var queue: Array[String] = []
var build_progress: float = 0.0
var rally_point: Vector2
var has_rally: bool = false

var _cooldown: float = 0.0

@onready var base_sprite: Sprite2D = $Base
@onready var team_sprite: Sprite2D = $Team

func _ready() -> void:
	team_sprite.modulate = Defs.team_color(owner_id)
	if Engine.is_editor_hint():
		return
	super._ready()
	add_to_group("starbases")
	display_name = Defs.STARBASE["name"]
	max_hp = Defs.STARBASE["hp"]
	hp = max_hp
	max_shield = Defs.STARBASE["shield"]
	shield = max_shield
	radius = Defs.STARBASE["radius"]

func can_queue(ship_type: String) -> String:
	## Returns "" if allowed, otherwise a player-facing reason.
	if queue.size() >= MAX_QUEUE:
		return "Build queue full"
	var d: Dictionary = Defs.SHIPS[ship_type]
	if Game.instance.supply_used(owner_id) + d["supply"] > Defs.FLEET_CAP:
		return "Fleet capacity reached"
	if not Game.instance.can_afford(owner_id, d["cost"]):
		return "Not enough resources"
	return ""

func enqueue(ship_type: String) -> String:
	var why := can_queue(ship_type)
	if why != "":
		return why
	Game.instance.spend(owner_id, Defs.SHIPS[ship_type]["cost"])
	queue.append(ship_type)
	return ""

func cancel(index: int) -> void:
	if index < 0 or index >= queue.size():
		return
	Game.instance.add_resources(owner_id, Defs.SHIPS[queue[index]]["cost"])
	queue.remove_at(index)
	if index == 0:
		build_progress = 0.0

func set_rally(pos: Vector2) -> void:
	rally_point = pos
	has_rally = true
	queue_redraw()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_regen_shields(delta)
	Game.instance.add_resources(owner_id, {"minerals": Defs.STARBASE_MINERALS_PER_SEC * delta})

	if not queue.is_empty():
		build_progress += delta
		if build_progress >= Defs.SHIPS[queue[0]]["build_time"]:
			_launch(queue.pop_front())
			build_progress = 0.0

	_cooldown -= delta
	if _cooldown <= 0.0:
		var e := Game.instance.nearest_enemy(self, Defs.STARBASE["range"])
		if e:
			Game.instance.fire(self, e, Defs.STARBASE["weapon"], Defs.STARBASE["damage"])
			_cooldown = Defs.STARBASE["cooldown"]
		else:
			_cooldown = 0.2

func _launch(ship_type: String) -> void:
	var dir := (rally_point - global_position).normalized() if has_rally else Vector2.from_angle(randf() * TAU)
	var ship := Game.instance.spawn_ship(ship_type, owner_id, global_position + dir * (radius + 6.0))
	ship.rotation = dir.angle()
	if ship.is_miner():
		var rock := Game.instance.nearest_asteroid(has_rally_or(global_position), 900.0)
		if rock:
			ship.order_mine(rock)
			return
	ship.order_move(has_rally_or(global_position + dir * (radius + 30.0)))

func has_rally_or(fallback: Vector2) -> Vector2:
	return rally_point if has_rally else fallback

func _draw() -> void:
	if Engine.is_editor_hint():
		return
	super._draw()
	if selected and has_rally:
		var to := to_local(rally_point)
		draw_dashed_line(Vector2.ZERO, to, Color(Defs.team_color(owner_id), 0.5), 1.0, 4.0)
		draw_rect(Rect2(to - Vector2(2, 2), Vector2(4, 4)), Defs.team_color(owner_id))
