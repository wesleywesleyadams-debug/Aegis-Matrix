extends Control
## Static placeholder icon for a unit/building portrait slot -- no
## per-type art exists yet, so every type draws the exact same simple
## head-and-shoulders silhouette rather than paying for a live 3D camera
## capture per type (see git history for the older IconCapture/
## PortraitCamera-based version this replaced). Scales with whatever
## size this Control is actually given, so the same script serves a
## small selection-tray slot and a bigger portrait/training-panel slot
## alike.
##
## Tinted to whatever entity it's currently showing owns -- see
## set_player_id -- the same PLAYER_COLORS every other team-colored
## visual (health bars, tabards, selection rings) already uses, so a
## portrait reads as "this is Player 2's" at a glance the same way those
## do. Defaults to DEFAULT_COLOR (this same blue) until set_player_id is
## called, so an icon shown before any subject is known doesn't draw an
## uninitialized color.

const REFERENCE_SIZE: float = 80.0
const MARGIN: float = 4.0
const DEFAULT_COLOR: Color = Color(0.2, 0.45, 0.9, 1.0)

var _color: Color = DEFAULT_COLOR

## Recolors this icon to match player_id's team color (Entity.
## PLAYER_COLORS), or DEFAULT_COLOR for an id with no defined color (e.g.
## null/no owner). Call whenever the subject this icon represents
## changes; a no-op call (same id as already set) still safely
## redraws.
func set_player_id(player_id: Variant) -> void:
	_color = Entity.PLAYER_COLORS.get(player_id, DEFAULT_COLOR)
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size).grow(-MARGIN)
	var scale_factor: float = rect.size.x / REFERENCE_SIZE
	draw_rect(rect, Color(0.82, 0.71, 0.55, 1.0), true)
	draw_rect(rect, Color(0.35, 0.22, 0.12, 1.0), false, 3.0 * scale_factor)
	var center := rect.get_center()
	draw_circle(center + Vector2(0, 14) * scale_factor, 22.0 * scale_factor, _color)
	draw_circle(center + Vector2(0, -10) * scale_factor, 17.0 * scale_factor, _color)
