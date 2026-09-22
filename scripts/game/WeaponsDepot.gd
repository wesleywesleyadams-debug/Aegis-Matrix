class_name WeaponsDepot
extends SpaceEntity
## Weapons Depot (Defs.WEAPONS_DEPOT): a Constructor builds it as a site paid
## over time, like a starbase. Every depot is built for one variant
## (Defs.VARIANTS): a Plasma Depot refits generalists into Plasma ships, a Slip
## Depot into Slip ships, and so on.
##
## Ships tasked to a depot fly in and dock (Defs.WEAPONS_DEPOT.capacity at a
## time). A docked ship is hidden and safe inside, and is refitted
## automatically as minerals allow — each hull has its own cost and time
## (Defs.SHIPS[type].refit). The refit is permanent. Doesn't count as a
## starbase for winning or losing.

## Which variant this depot fits (a key of Defs.VARIANTS).
var variant: String = "plasma"
var under_construction: bool = true
var construct_progress: float = 0.0
var build_stalled: bool = false
## Ships inside: [{ship, left (seconds of refit to go)}].
var bays: Array = []
var _hull: Sprite2D
var _team: Sprite2D

func _ready() -> void:
	super._ready()
	add_to_group("depots")
	radius = Defs.WEAPONS_DEPOT["radius"]
	_hull = Sprite2D.new()
	_hull.texture = Defs.tex("ship_depot_" + variant)
	_hull.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hull.scale = Vector2(2, 2)
	add_child(_hull)
	_team = Sprite2D.new()
	_team.texture = Defs.tex("ship_depot_" + variant + "_team")
	_team.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_team.scale = Vector2(2, 2)
	_team.modulate = Defs.team_color(owner_id)
	add_child(_team)
	refresh_stats()
	if under_construction:
		hp = max_hp * 0.1
		shield = 0.0
		armor = 0.0
	else:
		hp = max_hp
		shield = max_shield
		armor = max_armor
	_update_look()

func label() -> String:
	return "%s Depot" % Defs.VARIANTS[variant]["label"]

func color() -> Color:
	return Defs.VARIANTS[variant]["color"]

func refresh_stats() -> void:
	var g := Game.instance
	var d: Dictionary = Defs.WEAPONS_DEPOT
	var hp_frac := hp / max_hp if max_hp > 0.0 else 1.0
	var ar_frac := armor / max_armor if max_armor > 0.0 else 1.0
	max_hp = d["hp"] * g.mod(owner_id, "hull")
	max_armor = d["armor"] * g.mod(owner_id, "armor")
	max_shield = d["shield"] * g.mod(owner_id, "shield")
	hp = max_hp * hp_frac
	armor = max_armor * ar_frac
	shield = minf(shield, max_shield)
	display_name = (label() + " (under construction)") if under_construction else label()

func has_room() -> bool:
	return not under_construction and is_alive() and bays.size() < int(Defs.WEAPONS_DEPOT["capacity"])

## Takes a docked ship in: it disappears inside until its refit is done.
func dock(s: Ship) -> void:
	if not has_room() or not s.can_refit(variant):
		return
	bays.append({"ship": s, "left": float(s.def["refit"]["time"])})
	s.enter_depot(self)
	if owner_id == Game.instance.player_id:
		Game.instance.selection_changed.emit()

func _physics_process(delta: float) -> void:
	if under_construction:
		_construct(delta)
		return
	_regen_shields(delta)
	_refit(delta)

## Refits every docked ship, paying its minerals over its refit time. A ship
## whose owner can't pay simply waits.
func _refit(delta: float) -> void:
	if bays.is_empty():
		return
	var g := Game.instance
	for i in range(bays.size() - 1, -1, -1):
		var bay: Dictionary = bays[i]
		# Untyped until checked: a docked ship can be freed by a save load.
		var ship = bay["ship"]
		if not is_instance_valid(ship) or not ship.is_alive():
			bays.remove_at(i)
			continue
		var s: Ship = ship
		var r: Dictionary = s.def["refit"]
		var per_sec := {}
		for k in r:
			if k != "time":
				per_sec[k] = r[k] / float(r["time"])
		var f := g.pay_over_time(owner_id, per_sec, delta)
		bay["left"] -= delta * f
		if bay["left"] <= 0.0:
			bays.remove_at(i)
			s.leave_depot(self)
			s._become("%s_%s" % [variant, s.ship_type])
	if owner_id == g.player_id and selected:
		queue_redraw()

func _construct(delta: float) -> void:
	var g := Game.instance
	var d: Dictionary = Defs.WEAPONS_DEPOT
	var total: float = d["build_time"]
	var per_sec := {}
	for k in d["cost"]:
		per_sec[k] = d["cost"][k] / total
	var f := g.pay_over_time(owner_id, per_sec, delta)
	build_stalled = f < 0.999
	construct_progress += delta * f
	hp = minf(max_hp, hp + max_hp * 0.9 * delta * f / total)
	_update_look()
	if construct_progress >= total:
		under_construction = false
		armor = max_armor
		shield = max_shield
		refresh_stats()
		_update_look()
		if owner_id == g.player_id:
			g.notify("%s complete: send generalist warships here to refit them." % label(), "note_starbase", global_position)
		g.selection_changed.emit()

func _update_look() -> void:
	modulate = Color(1, 1, 1, 0.45 + 0.55 * construct_progress / Defs.WEAPONS_DEPOT["build_time"]) if under_construction else Color.WHITE
	queue_redraw()

func _draw() -> void:
	super._draw()
	if under_construction:
		return
	# Bay lights: one pip per docked ship, in this depot's variant color.
	var cap := int(Defs.WEAPONS_DEPOT["capacity"])
	var w := 3.0
	var total := cap * w * 1.6
	for i in cap:
		var x := -total / 2.0 + i * w * 1.6
		var lit: bool = i < bays.size()
		draw_rect(Rect2(x, radius + 6.0, w, 3.0), color() if lit else Color(color(), 0.25))

## Cancels a docked ship's refit: it leaves the depot as it went in, a
## generalist (minerals already spent are not refunded).
func cancel(s: Ship) -> void:
	for i in bays.size():
		if bays[i]["ship"] == s:
			bays.remove_at(i)
			if is_instance_valid(s):
				s.leave_depot(self)
			queue_redraw()
			return

func cancel_all() -> void:
	for bay in bays.duplicate():
		cancel(bay["ship"])

## Destroyed with ships inside: every docked ship is thrown clear and takes
## 60% of its shields, armor and hull in the blast. Some won't survive it.
func _die() -> void:
	for bay in bays.duplicate():
		var ship = bay["ship"]
		if is_instance_valid(ship) and ship.is_alive():
			var s: Ship = ship
			s.leave_depot(self)
			s.shield = maxf(0.0, s.shield - s.max_shield * 0.6)
			s.armor = maxf(0.0, s.armor - s.max_armor * 0.6)
			s.take_damage(s.max_hp * 0.6, null)
			if is_instance_valid(s) and s.is_alive():
				s.queue_redraw()
	bays.clear()
	if owner_id == Game.instance.player_id:
		Game.instance.alert("%s destroyed! Ships inside were thrown clear." % label(), "alert_starbase_lost", true, global_position)
	super._die()
