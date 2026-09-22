class_name Star
extends Sprite2D
## The system's sun. Selectable for info, but not habitable or mineable
## (a future tech may harvest its energy). It bathes nearby space in
## radiation: anything inside RADIATION_RADIUS takes damage that climbs
## steeply toward the core, maxing out on contact with the surface.

@export var star_name: String = "Orion"
## Radius of the glowing core (px) and the outer edge of the danger zone.
const CORE_RADIUS := 34.0
const RADIATION_RADIUS := 180.0
## Damage per second at contact with the surface.
const MAX_DPS := 60.0
const TICK := 0.25

var radius: float = CORE_RADIUS
var focused: bool = false:
	set(v):
		focused = v
		queue_redraw()
var _timer: float = 0.0

func _ready() -> void:
	add_to_group("stars")
	queue_redraw()

## Damage per second at distance `d` from the center for an object of
## radius `r`: 0 at the zone edge, MAX_DPS once it touches the core.
static func dps_at(d: float, r: float) -> float:
	var gap := d - r - CORE_RADIUS
	if gap <= 0.0:
		return MAX_DPS
	var span := RADIATION_RADIUS - CORE_RADIUS
	if gap >= span:
		return 0.0
	var t := 1.0 - gap / span
	return MAX_DPS * t * t

func _process(delta: float) -> void:
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
	var span := RADIATION_RADIUS - CORE_RADIUS
	var steps := 24
	var w := span / steps
	for k in steps:
		var t := 1.0 - (k + 0.5) / steps
		draw_arc(Vector2.ZERO, CORE_RADIUS + (k + 0.5) * w, 0.0, TAU, 96, Color(1, 0.3, 0.2, 0.22 * t * t), w + 0.5)
	var edge := Color(1, 0.35, 0.3, 0.75 if focused else 0.4)
	var dashes := 48
	for i in dashes:
		var a0 := TAU * i / dashes
		draw_arc(Vector2.ZERO, RADIATION_RADIUS, a0, a0 + TAU / dashes * 0.55, 6, edge, 1.5)
	if not focused:
		return
	# Selection ring on the surface.
	var n := 96
	for i in n:
		var a := TAU * i / n
		draw_rect(Rect2(Vector2.from_angle(a) * (CORE_RADIUS + 6.0) - Vector2(0.5, 0.5), Vector2(1, 1)), Color(1, 0.85, 0.5))
