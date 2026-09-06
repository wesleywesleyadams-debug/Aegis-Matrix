extends Control
## Bottom-of-screen tray showing one slot per currently selected UNIT --
## e.g. 4 selected peasants show 4 separate peasant-icon slots, not one
## icon with a count badge. RTSController pushes updates via
## set_selected_units() whenever selection changes (select, deselect,
## drag-select, clear). Each icon is a real captured snapshot of that
## unit's type (see IconCapture) -- its actual 3D model or sprite, not a
## generic shape -- falling back to a simple placeholder while still being
## captured (capture takes a couple of frames) or if it never resolves.

const SLOT_SIZE := 56.0
const SLOT_SPACING := 8.0
const MAX_VISIBLE_SLOTS := 12
const BOTTOM_MARGIN := 14.0
const HEALTH_BAR_HEIGHT := 5.0
const HEALTH_BAR_GAP := 3.0
## Health bars only need to look reasonably live, not literally 60fps --
## redrawing at this rate instead of every _process() frame cuts the
## per-frame _draw() cost (a rect/circle/text draw per visible slot) by
## most of that, with no visible difference for a UI element like this.
const HEALTH_REDRAW_INTERVAL := 0.1

@export var icon_capture_path: NodePath
@onready var icon_capture = get_node_or_null(icon_capture_path)

## The currently selected units, in first-encountered order -- one slot is
## drawn per entry, not per distinct type.
var _selected_units: Array = []
## type_id -> ImageTexture. Icons are captured once per unit TYPE (not per
## unit -- every unit of a type looks the same) and persist across
## selection changes so a type already captured doesn't need to be
## re-rendered next time it's selected; entries for types no longer present
## are pruned so this can't grow unbounded (though with a small, fixed
## roster it barely matters).
var _icon_cache: Dictionary = {}
## type_ids still waiting for an icon, each paired with a specific unit
## instance to render from, processed one at a time (see
## _process_capture_queue) -- icon_capture is a single shared
## camera/viewport, so capturing more than one concurrently would have
## them race over its position and the frame it renders.
var _capture_queue: Array[Dictionary] = []
var _capturing: bool = false
var _redraw_elapsed: float = 0.0

func _ready() -> void:
	# Never intercept clicks -- selection/move-order input is handled by
	# RTSController via raycasts against the 3D scene, not this overlay.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Health can change (combat) without this panel being told directly, so
## keep redrawing each icon's health bar live while anything is selected
## rather than only on selection-change events.
func _process(delta: float) -> void:
	if _selected_units.is_empty():
		return
	_redraw_elapsed += delta
	if _redraw_elapsed >= HEALTH_REDRAW_INTERVAL:
		_redraw_elapsed = 0.0
		queue_redraw()

func set_selected_units(units: Array) -> void:
	_selected_units = units.duplicate()
	queue_redraw()

	var present_types: Dictionary = {}
	var representative_by_type: Dictionary = {}
	for unit in _selected_units:
		var type_id: String = unit.unit_type_id
		if not present_types.has(type_id):
			present_types[type_id] = true
			representative_by_type[type_id] = unit

	# Drop cached/queued icons for types no longer present in any current
	# selection.
	for cached_type in _icon_cache.keys():
		if not present_types.has(cached_type):
			_icon_cache.erase(cached_type)
	for i in range(_capture_queue.size() - 1, -1, -1):
		if not present_types.has(_capture_queue[i]["type_id"]):
			_capture_queue.remove_at(i)

	if icon_capture == null:
		return
	for type_id in present_types.keys():
		if not _icon_cache.has(type_id):
			# Reserve immediately (null placeholder) so a second selection
			# change landing before this capture finishes doesn't queue a
			# duplicate for the same type.
			_icon_cache[type_id] = null
			_capture_queue.append({"type_id": type_id, "unit": representative_by_type[type_id]})
	if not _capturing:
		_process_capture_queue()

## Works through _capture_queue strictly one type at a time, since
## icon_capture's camera and viewport are shared -- capturing type B
## before type A's render has landed would have A's icon show whatever B
## (or neither) actually looked like.
func _process_capture_queue() -> void:
	_capturing = true
	while not _capture_queue.is_empty():
		var entry: Dictionary = _capture_queue.pop_front()
		var type_id: String = entry["type_id"]
		var unit: Node3D = entry["unit"]
		if not is_instance_valid(unit):
			continue
		var texture: ImageTexture = await icon_capture.capture_icon(unit)
		if _icon_cache.has(type_id):
			_icon_cache[type_id] = texture
			queue_redraw()
	_capturing = false

func _draw() -> void:
	var count := _selected_units.size()
	if count == 0:
		return

	var visible_count: int = mini(count, MAX_VISIBLE_SLOTS)
	var total_width := visible_count * SLOT_SIZE + (visible_count - 1) * SLOT_SPACING
	var start_x := (size.x - total_width) / 2.0
	var y := size.y - SLOT_SIZE - BOTTOM_MARGIN

	var font := ThemeDB.fallback_font

	for i in visible_count:
		var unit = _selected_units[i]
		var x := start_x + i * (SLOT_SIZE + SLOT_SPACING)
		var rect := Rect2(x, y, SLOT_SIZE, SLOT_SIZE)
		draw_rect(rect, Color(0.82, 0.71, 0.55, 1.0), true)
		draw_rect(rect, Color(0.35, 0.22, 0.12, 1.0), false, 3.0)

		var icon: ImageTexture = _icon_cache.get(unit.unit_type_id)
		if icon != null:
			var inset := 4.0
			var icon_rect := Rect2(rect.position + Vector2(inset, inset), rect.size - Vector2(inset * 2, inset * 2))
			draw_texture_rect(icon, icon_rect, false)
		else:
			# Still being captured, or no icon_capture wired up -- a
			# simple placeholder so the slot isn't blank in the meantime.
			var center := rect.get_center()
			draw_circle(center + Vector2(0, 8), 15.0, Color(0.2, 0.45, 0.9, 1.0))
			draw_circle(center + Vector2(0, -6), 12.0, Color(0.2, 0.45, 0.9, 1.0))

		# Mini health bar directly below the icon -- neutral dark background
		# (health lost) and a fill colored to match the unit's player/team,
		# same convention as the in-world floating health bars.
		var bar_rect := Rect2(rect.position.x, rect.end.y + HEALTH_BAR_GAP, SLOT_SIZE, HEALTH_BAR_HEIGHT)
		draw_rect(bar_rect, Color(0.08, 0.08, 0.08, 0.95), true)
		var fraction: float = clampf(unit.current_health / unit.max_health, 0.0, 1.0)
		if fraction > 0.0:
			var fill_rect := Rect2(bar_rect.position, Vector2(bar_rect.size.x * fraction, bar_rect.size.y))
			draw_rect(fill_rect, Entity.PLAYER_COLORS.get(unit.player_id, Color.WHITE), true)

	if count > MAX_VISIBLE_SLOTS:
		var overflow_text := "+%d more" % (count - MAX_VISIBLE_SLOTS)
		var overflow_x := start_x + total_width + 12.0
		draw_string(font, Vector2(overflow_x, y + SLOT_SIZE / 2.0 + 5.0), overflow_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
