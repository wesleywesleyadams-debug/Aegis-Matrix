class_name Shockwave
extends Node2D
## The blast of an exploding gas giant or an imploding world: a white-hot
## flash and an orange shock ring that sweeps out to the blast radius (where
## its damage reaches 0), then fades. Frees itself.

var radius: float = 450.0
var life: float = 1.6
var _t: float = 0.0

func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var k := clampf(_t / life, 0.0, 1.0)
	var grow := 1.0 - pow(1.0 - k, 3.0)
	var r := radius * grow
	var a := 1.0 - k
	# Flash: a hot core that fades fast.
	var fa := clampf(1.0 - k * 2.5, 0.0, 1.0)
	if fa > 0.0:
		draw_circle(Vector2.ZERO, radius * 0.35 * (0.6 + grow), Color(1.0, 0.95, 0.8, 0.55 * fa))
	# The damaging area, tinted while the ring passes.
	draw_circle(Vector2.ZERO, r, Color(1.0, 0.45, 0.15, 0.12 * a))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Color(1.0, 0.6, 0.25, 0.9 * a), 6.0)
	draw_arc(Vector2.ZERO, r * 0.82, 0.0, TAU, 96, Color(1.0, 0.85, 0.5, 0.5 * a), 3.0)
