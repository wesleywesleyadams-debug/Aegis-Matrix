class_name ArcFx
extends Node2D
## Arc Emitters: a jagged bolt from the shooter through each target it jumps
## to, flickering out in a fraction of a second.

const LIFE := 0.18
var _pts: PackedVector2Array
var _col := Color.WHITE
var _t := 0.0

func setup(points: PackedVector2Array, _variant: bool, col: Color) -> void:
	_pts = points
	_col = col
	z_index = 5

func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var a := 1.0 - _t / LIFE
	for i in _pts.size() - 1:
		var p0: Vector2 = _pts[i]
		var p1: Vector2 = _pts[i + 1]
		var line := PackedVector2Array([p0])
		var n := 6
		var side := (p1 - p0).orthogonal().normalized()
		for k in range(1, n):
			line.append(p0.lerp(p1, float(k) / n) + side * randf_range(-6.0, 6.0))
		line.append(p1)
		draw_polyline(line, Color(_col, 0.45 * a), 4.0)
		draw_polyline(line, Color(Color.WHITE, 0.9 * a), 1.5)
