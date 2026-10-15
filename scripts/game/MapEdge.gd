class_name MapEdge
extends Node2D
## The edge of the system (Game.MAP_RECT): space beyond it is shaded off, and
## a dashed boundary line with corner brackets marks where the playable area
## ends. The camera may look past the edge, so without this the background
## simply carried on and nothing said the map had stopped.

const SHADE := Color(0.0, 0.0, 0.02, 0.62)
const LINE := Color(0.55, 0.65, 0.95, 0.55)
## How far the shade reaches past the edge: further than any zoom can show.
const BEYOND := 4000.0
const DASH := 28.0
const CORNER := 90.0

func _ready() -> void:
	# Over the backdrop and nebulae, under everything that moves.
	z_index = 5

func _draw() -> void:
	var r := Game.MAP_RECT
	# Four bands around the map, darkening everything outside it.
	draw_rect(Rect2(r.position.x - BEYOND, r.position.y - BEYOND, r.size.x + BEYOND * 2.0, BEYOND), SHADE)
	draw_rect(Rect2(r.position.x - BEYOND, r.end.y, r.size.x + BEYOND * 2.0, BEYOND), SHADE)
	draw_rect(Rect2(r.position.x - BEYOND, r.position.y, BEYOND, r.size.y), SHADE)
	draw_rect(Rect2(r.end.x, r.position.y, BEYOND, r.size.y), SHADE)
	# A dashed line along the edge itself.
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var t := 0.0
		while t < length:
			draw_line(a + dir * t, a + dir * minf(t + DASH, length), LINE, 3.0)
			t += DASH * 2.0
	# Solid brackets at the corners, so the corners read even when zoomed in.
	for i in 4:
		var c: Vector2 = corners[i]
		var to_next: Vector2 = (corners[(i + 1) % 4] - c).normalized()
		var to_prev: Vector2 = (corners[(i + 3) % 4] - c).normalized()
		draw_line(c, c + to_next * CORNER, Color(LINE, 0.9), 5.0)
		draw_line(c, c + to_prev * CORNER, Color(LINE, 0.9), 5.0)
