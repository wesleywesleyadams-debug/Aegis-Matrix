class_name MiningStation
extends SpaceEntity
## Mining Station (Defs.MINING_STATION): a cheap outpost a Constructor builds
## on site, paid over time like a starbase. Harvesters drop their loads here
## as well as at a starbase, so a far belt stops costing a long haul home.
##
## It builds no ships, holds no queue and carries a token gun. Losing one
## costs you the drop-off and nothing else — it is not a starbase for
## winning or losing.

var under_construction: bool = true
var construct_progress: float = 0.0
var build_stalled: bool = false
var _hull: Sprite2D
var _team: Sprite2D

func _ready() -> void:
	super._ready()
	add_to_group("mining_stations")
	radius = Defs.MINING_STATION["radius"]
	_hull = Sprite2D.new()
	_hull.texture = Defs.tex("ship_mining_station")
	_hull.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hull.scale = Vector2.ONE * 2.0 / Defs.ART_SCALE
	add_child(_hull)
	_team = Sprite2D.new()
	_team.texture = Defs.tex("ship_mining_station_team")
	_team.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_team.scale = Vector2.ONE * 2.0 / Defs.ART_SCALE
	_team.modulate = Defs.team_color(owner_id)
	add_child(_team)
	refresh_stats()
	if under_construction:
		hp = max_hp * Game.instance.construct_start_frac(owner_id)
		construct_progress = maxf(construct_progress, float(Defs.MINING_STATION["build_time"]) * Game.instance.construct_start_progress(owner_id))
		shield = 0.0
		armor = 0.0
	else:
		hp = max_hp
		shield = max_shield
		armor = max_armor
	_update_look()

func label() -> String:
	return Defs.MINING_STATION["name"]

func refresh_stats() -> void:
	var g := Game.instance
	var d: Dictionary = Defs.MINING_STATION
	var hp_frac := hp / max_hp if max_hp > 0.0 else 1.0
	var ar_frac := armor / max_armor if max_armor > 0.0 else 1.0
	var tot: float = d["hp"] + d["armor"] + d["shield"]
	max_hp = (d["hp"] * g.mod(owner_id, "hull") + g.layer_bonus(owner_id, "hull", tot)) * g.mod(owner_id, "structure")
	max_armor = (d["armor"] * g.mod(owner_id, "armor") + g.layer_bonus(owner_id, "armor", tot)) * g.mod(owner_id, "structure")
	max_shield = (d["shield"] * g.mod(owner_id, "shield") + g.layer_bonus(owner_id, "shield", tot)) * g.mod(owner_id, "structure_shield")
	hp = max_hp * hp_frac
	armor = max_armor * ar_frac
	shield = minf(shield, max_shield)
	display_name = (label() + " (under construction)") if under_construction else label()

## Ready to take deliveries.
func is_open() -> bool:
	return not under_construction and is_alive()

func _physics_process(delta: float) -> void:
	if under_construction:
		_construct(delta)
		return
	_regen_shields(delta)

func _construct(delta: float) -> void:
	var g := Game.instance
	var d: Dictionary = Defs.MINING_STATION
	var total: float = d["build_time"]
	var per_sec := {}
	for k in d["cost"]:
		per_sec[k] = d["cost"][k] / total
	# Modular frames (Constructs) raise the pace a site is assembled at; the
	# cost is paid at the same pace, so the total bill is unchanged.
	var cs: float = g.mod(owner_id, "construct_speed")
	for k2 in per_sec:
		per_sec[k2] *= cs
	var f := g.pay_over_time(owner_id, per_sec, delta) * cs
	build_stalled = f < cs - 0.001
	if build_stalled:
		queue_redraw()   # keeps the insufficient-funds tag pulsing
	construct_progress += delta * f
	hp = minf(max_hp, hp + max_hp * Game.instance.construct_hp_rate(owner_id) * delta * f / total)
	_update_look()
	if construct_progress >= total:
		under_construction = false
		armor = max_armor
		shield = max_shield
		refresh_stats()
		_update_look()
		if owner_id == g.player_id:
			g.notify("%s complete: harvesters can unload here." % label(), "note_starbase", global_position)
		g.selection_changed.emit()

func _update_look() -> void:
	modulate = Color(1, 1, 1, 0.45 + 0.55 * construct_progress / Defs.MINING_STATION["build_time"]) if under_construction else Color.WHITE
	queue_redraw()

func _die() -> void:
	if owner_id == Game.instance.player_id:
		Game.instance.alert("%s destroyed." % label(), "alert_starbase_lost", true, global_position)
	super._die()

func _draw() -> void:
	super._draw()
	if under_construction:
		var frac: float = construct_progress / Defs.MINING_STATION["build_time"]
		draw_arc(Vector2.ZERO, radius + 7.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 40, Color("ffd46b") if not build_stalled else Color("ff6a5a"), 2.0)
		if build_stalled:
			_draw_stall_notice()
