class_name Beacon
extends Node2D
## A Scout's sensor beacon (Deep Sensors job, Q): watches a spot for its
## owner until it expires. Counts as a sensor in Vision.

var owner_id: int = 0
var expires: float = 0.0

func _ready() -> void:
	add_to_group("beacons")
	z_index = 5

func sensor_range() -> float:
	return Abilities.BEACON_SENSOR

func _process(_delta: float) -> void:
	if Game.now() >= expires:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var c: Color = Defs.JOBS["beacon"]["color"]
	var left := clampf((expires - Game.now()) / float(Defs.JOBS["beacon"]["duration"]), 0.0, 1.0)
	# A small cyan buoy with a slow sonar ping and a ring showing time left.
	var ph := fmod(Time.get_ticks_msec() / 1600.0, 1.0)
	draw_arc(Vector2.ZERO, 6.0 + ph * 40.0, 0.0, TAU, 32, Color(c, 0.5 * (1.0 - ph)), 1.5)
	draw_circle(Vector2.ZERO, 3.0, c)
	draw_circle(Vector2.ZERO, 1.5, Color.WHITE)
	draw_arc(Vector2.ZERO, 8.0, -PI / 2.0, -PI / 2.0 + TAU * left, 24, Color(c, 0.8), 1.5)
