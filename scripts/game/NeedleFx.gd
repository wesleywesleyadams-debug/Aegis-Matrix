class_name NeedleFx
extends Node2D
## Point-Defense Lattice: one sliver-thin needle that flies along a path,
## bending at each point where it strikes something, and calls `on_hit(i)`
## as it reaches point i (point 0 is the muzzle).

const SPEED := 650.0    # px/s along the path
const LENGTH := 60.0    # how long the needle is, measured along the path
var _pts: PackedVector2Array
var _cum: PackedFloat32Array   # distance along the path to each point
var _d := 0.0
var _next := 1
var _col := Color("ffe14a")
var on_hit: Callable

func setup(points: PackedVector2Array, col: Color, hit: Callable) -> void:
	_pts = points
	_col = col
	on_hit = hit
	z_index = 5
	_cum.append(0.0)
	for i in range(1, _pts.size()):
		_cum.append(_cum[i - 1] + _pts[i - 1].distance_to(_pts[i]))

func _process(delta: float) -> void:
	_d += SPEED * delta
	while _next < _pts.size() and _d >= _cum[_next]:
		if on_hit.is_valid():
			on_hit.call(_next)
		_next += 1
	if _d - LENGTH >= _cum[_cum.size() - 1]:
		queue_free()
		return
	queue_redraw()

## The point `d` along the path.
func _at(d: float) -> Vector2:
	d = clampf(d, 0.0, _cum[_cum.size() - 1])
	for i in range(1, _pts.size()):
		if d <= _cum[i]:
			var seg := _cum[i] - _cum[i - 1]
			return _pts[i - 1].lerp(_pts[i], 0.0 if seg <= 0.0 else (d - _cum[i - 1]) / seg)
	return _pts[_pts.size() - 1]

func _draw() -> void:
	# The needle from its tail to its head, bending through any corner it spans.
	var tail := maxf(_d - LENGTH, 0.0)
	var head := minf(_d, _cum[_cum.size() - 1])
	var line := PackedVector2Array([to_local(_at(tail))])
	for i in range(1, _pts.size()):
		if _cum[i] > tail and _cum[i] < head:
			line.append(to_local(_pts[i]))
	line.append(to_local(_at(head)))
	if line.size() >= 2:
		draw_polyline(line, Color(_col, 0.9), 2.4)
		draw_polyline(line, Color(1, 1, 0.85, 1.0), 1.0)
