extends Control
## Row of tiny icon+health-bar slots for every currently selected unit --
## e.g. 4 selected peasants show 4 separate slots, not one icon with a
## count badge. Shown inside SelectedObjectsPanel only while MORE THAN
## ONE unit is selected (see PortraitPanel.set_selection) -- a single
## selection shows that one object's portrait+stats instead (no per-unit
## health/type tray needed when there's only one). Sized to fit within
## SelectedObjectsPanel's own (smaller-than-full-screen) bounds, unlike
## this script's predecessor (SelectionPanel.gd, a full-width bottom-of-
## screen tray) -- smaller slot size and a lower visible cap accordingly.

const SLOT_SIZE := 32.0
const SLOT_SPACING := 6.0
const MAX_VISIBLE_SLOTS := 10
const TOP_MARGIN := 8.0
const HEALTH_BAR_HEIGHT := 3.0
const HEALTH_BAR_GAP := 2.0
## Health bars only need to look reasonably live, not literally 60fps --
## redrawing at this rate instead of every _process() frame cuts the
## per-frame _draw() cost (a rect/circle/text draw per visible slot) by
## most of that, with no visible difference for a UI element like this.
const HEALTH_REDRAW_INTERVAL := 0.1

## The currently selected units, in first-encountered order -- one slot is
## drawn per entry, not per distinct type.
var _selected_units: Array = []
var _redraw_elapsed: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Health can change (combat) without this being told directly, so keep
## redrawing each icon's health bar live while shown, rather than only on
## selection-change events.
func _process(delta: float) -> void:
	if not visible or _selected_units.is_empty():
		return
	_redraw_elapsed += delta
	if _redraw_elapsed >= HEALTH_REDRAW_INTERVAL:
		_redraw_elapsed = 0.0
		queue_redraw()

func set_selected_units(units: Array) -> void:
	_selected_units = units.filter(is_instance_valid)
	queue_redraw()

func _draw() -> void:
	# Defensive: RTSController prunes freed units out of the array it feeds
	# this every frame (see RTSController._prune_selected_units), but this
	# redraws on its own timer independent of that, so guard here too
	# rather than assume the two always run in a safe order.
	var live_units: Array = _selected_units.filter(is_instance_valid)

	var count := live_units.size()
	if count == 0:
		return

	var visible_count: int = mini(count, MAX_VISIBLE_SLOTS)
	var total_width := visible_count * SLOT_SIZE + (visible_count - 1) * SLOT_SPACING
	var start_x := (size.x - total_width) / 2.0
	var y := TOP_MARGIN

	for i in visible_count:
		var unit = live_units[i]
		var x := start_x + i * (SLOT_SIZE + SLOT_SPACING)
		var rect := Rect2(x, y, SLOT_SIZE, SLOT_SIZE)
		draw_rect(rect, Color(0.82, 0.71, 0.55, 1.0), true)
		draw_rect(rect, Color(0.35, 0.22, 0.12, 1.0), false, 2.0)
		var center := rect.get_center()
		draw_circle(center + Vector2(0, 5), 9.0, Color(0.2, 0.45, 0.9, 1.0))
		draw_circle(center + Vector2(0, -4), 7.0, Color(0.2, 0.45, 0.9, 1.0))

		# Mini health bar directly below the icon -- neutral dark background
		# (health lost) and a fill colored to match the unit's player/team,
		# same convention as the in-world floating health bars.
		var bar_rect := Rect2(rect.position.x, rect.end.y + HEALTH_BAR_GAP, SLOT_SIZE, HEALTH_BAR_HEIGHT)
		draw_rect(bar_rect, Color(0.08, 0.08, 0.08, 0.95), true)
		var fraction: float = clampf(unit.current_health / unit.max_health, 0.0, 1.0)
		if fraction > 0.0:
			var fill_rect := Rect2(bar_rect.position, Vector2(bar_rect.size.x * fraction, bar_rect.size.y))
			draw_rect(fill_rect, Entity.PLAYER_COLORS.get(unit.player_id, Color.WHITE), true)
