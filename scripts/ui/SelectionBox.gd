extends Control
## Draws the drag-select rectangle. RTSController toggles visibility and
## updates start/end each frame while dragging.

var drag_start: Vector2 = Vector2.ZERO
var drag_end: Vector2 = Vector2.ZERO

func get_rect_bounds() -> Rect2:
	var top_left := Vector2(min(drag_start.x, drag_end.x), min(drag_start.y, drag_end.y))
	var size := (drag_end - drag_start).abs()
	return Rect2(top_left, size)

func _draw() -> void:
	if not visible:
		return
	var rect := get_rect_bounds()
	draw_rect(rect, Color(0.4, 0.9, 0.5, 0.18), true)
	draw_rect(rect, Color(0.4, 0.9, 0.5, 0.9), false, 2.0)
