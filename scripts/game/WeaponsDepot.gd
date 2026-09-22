class_name WeaponsDepot
extends SpaceEntity
## Weapons Depot (Defs.WEAPONS_DEPOT): a Constructor builds it as a site paid
## over time, like a starbase. Generalist warships dock here to be refitted
## into a specialist variant (Ship.order_refit); the ships run the refit
## themselves, the depot just has to be finished and alive. Doesn't count
## as a starbase for winning or losing.

var under_construction: bool = true
var construct_progress: float = 0.0
var build_stalled: bool = false
var _hull: Sprite2D
var _team: Sprite2D

func _ready() -> void:
	super._ready()
	add_to_group("depots")
	radius = Defs.WEAPONS_DEPOT["radius"]
	display_name = Defs.WEAPONS_DEPOT["name"]
	_hull = Sprite2D.new()
	_hull.texture = Defs.tex("ship_depot")
	_hull.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hull.scale = Vector2(2, 2)
	add_child(_hull)
	_team = Sprite2D.new()
	_team.texture = Defs.tex("ship_depot_team")
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
	display_name = (d["name"] + " (under construction)") if under_construction else d["name"]

func _physics_process(delta: float) -> void:
	if under_construction:
		_construct(delta)
		return
	_regen_shields(delta)

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
			g.notify("Weapons Depot complete: select generalist warships to refit them.", "note_starbase", global_position)
		g.selection_changed.emit()

func _update_look() -> void:
	modulate = Color(1, 1, 1, 0.45 + 0.55 * construct_progress / Defs.WEAPONS_DEPOT["build_time"]) if under_construction else Color.WHITE
	queue_redraw()
