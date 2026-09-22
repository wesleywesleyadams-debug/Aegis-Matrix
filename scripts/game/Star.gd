class_name Star
extends Sprite2D
## The system's sun. Selectable for info, but not habitable or mineable
## (a future tech may harvest its energy). It bathes nearby space in
## radiation: anything inside radiation_radius takes damage that climbs
## steeply toward the core, maxing out on contact with the surface. Each star
## type (set per system) has its own art, size, zone and damage.

@export var star_name: String = "Orion"

## Star types live in Defs.STAR_TYPES.
var star_type: String = "yellow"
var core_radius: float = 34.0
var radiation_radius: float = 180.0
var max_dps: float = 60.0
var tint: Color = Color("ffb347")
const TICK := 0.25

var radius: float = 34.0
var focused: bool = false:
	set(v):
		focused = v
		queue_redraw()
var _timer: float = 0.0

func _ready() -> void:
	add_to_group("stars")
	queue_redraw()

## Switches to one of Defs.STAR_TYPES (art, size, zone, damage).
func set_type(t: String) -> void:
	var d: Dictionary = Defs.STAR_TYPES.get(t, Defs.STAR_TYPES["yellow"])
	star_type = t if Defs.STAR_TYPES.has(t) else "yellow"
	texture = Defs.tex(d["tex"])
	core_radius = d["core"]
	radiation_radius = d["zone"]
	max_dps = d["dps"]
	tint = d["tint"]
	radius = core_radius
	queue_redraw()

func type_label() -> String:
	return Defs.STAR_TYPES[star_type]["label"]

## Damage per second at distance `d` from the center for an object of
## radius `r`: 0 at the zone edge, max_dps once it touches the core.
func dps_at(d: float, r: float) -> float:
	var gap := d - r - core_radius
	if gap <= 0.0:
		return max_dps
	var span := radiation_radius - core_radius
	if gap >= span:
		return 0.0
	var t := 1.0 - gap / span
	return max_dps * t * t

## Binary systems: the star circles the system center (0, 0). Position comes
## from the match clock, so saves and reloads line up.
var orbit_radius: float = 0.0
var orbit_phase: float = 0.0
var orbit_speed: float = 0.0

func orbit_position(t: float) -> Vector2:
	return Vector2.from_angle(orbit_phase + t * orbit_speed) * orbit_radius

func _process(delta: float) -> void:
	if orbit_radius > 0.0:
		position = orbit_position(Game.now())
	_timer += delta
	if _timer < TICK:
		return
	var dt := _timer
	_timer = 0.0
	for e in get_tree().get_nodes_in_group("entities"):
		if not e.is_alive():
			continue
		var dps := dps_at(global_position.distance_to(e.global_position), e.radius)
		if dps > 0.0:
			e.take_damage(dps * dt, null)
			if e.owner_id == Game.instance.player_id:
				Game.instance.alert("Your ships are taking radiation damage from %s!" % star_name, "alert_ships", false, e.global_position)

func _draw() -> void:
	# Radiation zone, always shown: a red haze that thickens toward the core
	# (matching the damage curve) and a dashed line at its outer edge.
	var span := radiation_radius - core_radius
	var steps := 24
	var w := span / steps
	for k in steps:
		var t := 1.0 - (k + 0.5) / steps
		draw_arc(Vector2.ZERO, core_radius + (k + 0.5) * w, 0.0, TAU, 96, Color(1, 0.3, 0.2, 0.22 * t * t), w + 0.5)
	var edge := Color(1, 0.35, 0.3, 0.75 if focused else 0.4)
	var dashes := 48
	for i in dashes:
		var a0 := TAU * i / dashes
		draw_arc(Vector2.ZERO, radiation_radius, a0, a0 + TAU / dashes * 0.55, 6, edge, 1.5)
	if not focused:
		return
	# Selection ring on the surface.
	var n := 96
	for i in n:
		var a := TAU * i / n
		draw_rect(Rect2(Vector2.from_angle(a) * (core_radius + 6.0) - Vector2(0.5, 0.5), Vector2(1, 1)), Color(1, 0.85, 0.5))
