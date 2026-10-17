class_name RouteOverlay
extends Node2D
## The shift-queued route of the current selection, drawn once for the group
## instead of once per ship: formation gives every ship its own slot, so one
## line per ship turned a queued fleet into a web of dashes. Stop i is the
## centre of every selected ship's i-th queued point.

const COLOR := Color(1, 1, 1, 0.5)
const DASH := 14.0

func _ready() -> void:
	z_index = 40

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var g := Game.instance
	if g == null:
		return
	var ships: Array = g.selection.filter(func(s): return is_instance_valid(s) and s is Ship and s.owner_id == g.player_id and not s.order_queue.is_empty())
	if ships.is_empty():
		return
	# Where the group is headed now, then each queued stop in turn.
	var start := Vector2.ZERO
	for s in ships:
		start += s.move_goal if s.state != Ship.State.IDLE else s.global_position
	start /= ships.size()
	var stops: Array = []
	var i := 0
	while true:
		var sum := Vector2.ZERO
		var n := 0
		for s in ships:
			var pts: PackedVector2Array = s.queued_points()
			if i < pts.size():
				sum += pts[i]
				n += 1
		if n == 0:
			break
		stops.append(sum / n)
		i += 1
	# Lines stay one screen pixel wide whatever the zoom.
	var px := 1.0 / maxf(g.camera.zoom.x, 0.01)
	var from := start
	for p in stops:
		_dashed(from, p, px)
		draw_circle(p, 4.0 * px, COLOR)
		from = p

func _dashed(a: Vector2, b: Vector2, px: float) -> void:
	var d := b - a
	var len := d.length()
	if len < 1.0:
		return
	var dir := d / len
	var t := 0.0
	var dash := DASH * px
	while t < len:
		draw_line(a + dir * t, a + dir * minf(t + dash, len), COLOR, 1.5 * px)
		t += dash * 2.0
