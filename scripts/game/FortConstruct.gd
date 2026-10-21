class_name FortConstruct
extends SpaceEntity
## Shared base of the Constructs-tree forts (Frontier Outpost, Warp Gate): a
## site a Constructor founds and pays for over time, like a Mining Station.
## Unlike depots and Mining Stations, forts sit in Game.fort_list, so enemy
## ships auto-target them the way they target starbases.
##
## Subclasses give def() and sprite_name(); everything else is common.

var under_construction: bool = true
var construct_progress: float = 0.0
var build_stalled: bool = false
var _hull: Sprite2D
var _team: Sprite2D

func def() -> Dictionary:
	return {}

func sprite_name() -> String:
	return ""

func _ready() -> void:
	super._ready()
	add_to_group("forts")
	radius = def()["radius"]
	_hull = Sprite2D.new()
	_hull.texture = Defs.tex(sprite_name())
	_hull.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hull.scale = Vector2.ONE * 2.0 / Defs.ART_SCALE
	add_child(_hull)
	_team = Sprite2D.new()
	_team.texture = Defs.tex(sprite_name() + "_team")
	_team.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_team.scale = Vector2.ONE * 2.0 / Defs.ART_SCALE
	_team.modulate = Defs.team_color(owner_id)
	add_child(_team)
	refresh_stats()
	if under_construction:
		hp = max_hp * Game.instance.construct_start_frac(owner_id)
		shield = 0.0
		armor = 0.0
	else:
		construct_progress = def()["build_time"]
		hp = max_hp
		shield = max_shield
		armor = max_armor
	_update_look()

func label() -> String:
	return def()["name"]

func refresh_stats() -> void:
	var g := Game.instance
	var d: Dictionary = def()
	var hp_frac := hp / max_hp if max_hp > 0.0 else 1.0
	var ar_frac := armor / max_armor if max_armor > 0.0 else 1.0
	max_hp = d["hp"] * g.mod(owner_id, "hull") * g.mod(owner_id, "structure")
	max_armor = d["armor"] * g.mod(owner_id, "armor") * g.mod(owner_id, "structure")
	max_shield = d["shield"] * g.mod(owner_id, "shield") * g.mod(owner_id, "structure_shield")
	hp = max_hp * hp_frac
	armor = max_armor * ar_frac
	shield = minf(shield, max_shield)
	display_name = (label() + " (under construction)") if under_construction else label()

func _physics_process(delta: float) -> void:
	if under_construction:
		_construct(delta)
		return
	_regen_shields(delta)
	_operate(delta)

## A finished fort's own job, every tick (the outpost's gun, the gate's
## cooldown).
func _operate(_delta: float) -> void:
	pass

## Said to the owner when the site is done.
func _done_note() -> String:
	return "%s complete." % label()

func _construct(delta: float) -> void:
	var g := Game.instance
	var d: Dictionary = def()
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
	hp = minf(max_hp, hp + max_hp * 0.9 * delta * f / total)
	_update_look()
	if construct_progress >= total:
		under_construction = false
		armor = max_armor
		shield = max_shield
		refresh_stats()
		_update_look()
		if owner_id == g.player_id:
			g.notify(_done_note(), "note_starbase", global_position)
		g.selection_changed.emit()

func _update_look() -> void:
	modulate = Color(1, 1, 1, 0.45 + 0.55 * construct_progress / def()["build_time"]) if under_construction else Color.WHITE
	queue_redraw()

func _die() -> void:
	if owner_id == Game.instance.player_id:
		Game.instance.alert("%s destroyed." % label(), "alert_starbase_lost", true, global_position)
	super._die()

func _draw() -> void:
	super._draw()
	if under_construction:
		var frac: float = construct_progress / def()["build_time"]
		draw_arc(Vector2.ZERO, radius + 7.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 40, Color("ffd46b") if not build_stalled else Color("ff6a5a"), 2.0)
		if build_stalled:
			_draw_stall_notice()
