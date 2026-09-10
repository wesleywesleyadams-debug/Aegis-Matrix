extends Button
class_name ItemSlotButton
## One item-holding slot button, shared by BuildingStoragePanel (one row
## per stored item) and UnitBackpackPanel (the 4-slot cross layout).
## Right-click drops it on the ground where its owner is standing;
## dragging it out lets the player place it anywhere in the world, hand
## it to a unit, or store it in a building (see ItemDropTarget/
## RTSController.handle_item_drag_drop, the actual drop target/logic).

signal right_clicked(item_type: String, source_slot: String)
## For ItemTooltipPanel -- see RTSController._on_item_slot_hovered/
## _on_item_slot_unhovered. Only emitted for a non-empty slot (an empty
## one has nothing to show stats for).
signal hovered(item_type: String)
signal unhovered()

## Icon fills the whole button in place of a text label -- set once the
## item's real visual has been captured (see ItemIconCapture); text stays
## as the item's capitalized name in the meantime as a placeholder, so the
## slot never sits blank while the capture is pending. Built in _init()
## rather than as @onready -- every caller (see UnitBackpackPanel/
## BuildingStoragePanel) calls set_item() right after ItemSlotButton.new(),
## before add_child()'ing it into the tree, and @onready wouldn't run
## until _ready() fires on that add_child.
var icon_rect: TextureRect

## Plain black in every state -- item icons are lit/glowing 3D renders on
## a transparent background (see ItemIconCapture), so a plain dark slot
## behind them reads far better than this theme's usual button styling
## would (which is designed around text labels, not full-bleed images).
## The border (this theme's brown) is what actually separates one slot
## from the next when slots sit flush with no gap between them (see
## BuildingStoragePanel's 3x2 grid) -- without it, adjacent black slots
## have nothing to distinguish where one ends and the next begins.
static func _make_black_stylebox() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 1)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.55, 0.4, 0.25, 1)
	return style

## Minimum row height for a slot with no fixed size of its own (see
## BuildingStoragePanel, whose VBoxContainer sizes each button entirely
## from its own minimum size -- UnitBackpackPanel's fixed per-slot Rect2s
## aren't affected by this, they set position/size directly regardless).
## The plain black stylebox above has no content margins to fall back on
## the way this theme's normal button stylebox does, and an occupied
## slot's text is empty (the icon shows instead) so there's no text
## height to fall back on either -- without this, a stored item's row
## collapses to 0 height and becomes unclickable despite still "showing"
## its icon (the icon just renders at zero size along with it).
const MIN_ROW_HEIGHT: float = 52.0

func _init() -> void:
	var black_style := _make_black_stylebox()
	add_theme_stylebox_override("normal", black_style)
	add_theme_stylebox_override("hover", black_style)
	add_theme_stylebox_override("pressed", black_style)
	add_theme_stylebox_override("disabled", black_style)
	add_theme_stylebox_override("focus", black_style)
	custom_minimum_size.y = MIN_ROW_HEIGHT

	icon_rect = TextureRect.new()
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_rect.hide()
	add_child(icon_rect)

func _ready() -> void:
	mouse_entered.connect(func() -> void:
		if not item_type.is_empty():
			hovered.emit(item_type)
	)
	mouse_exited.connect(func() -> void: unhovered.emit())

## Sets this slot to show `type` -- its real captured icon in place of a
## text label (fetched async; the icon simply pops in once ready, with the
## capitalized item name shown as a placeholder until then). Pass "" to
## show an empty/unoccupied slot instead, labeled with `empty_label`
## (e.g. the slot's own name, "Armor") and disabled.
func set_item(type: String, empty_label: String = "") -> void:
	item_type = type
	if type.is_empty():
		text = empty_label
		disabled = true
		icon_rect.hide()
		return
	text = type.capitalize()
	disabled = false
	icon_rect.hide()
	ItemIcons.request_icon(type, func(tex: Texture2D) -> void:
		if is_instance_valid(self) and item_type == type and tex != null:
			icon_rect.texture = tex
			icon_rect.show()
			text = ""
	)

var item_type: String = ""
## Which of source_unit's Unit.BACKPACK_SLOTS this button represents --
## "" for a BuildingStoragePanel button, which has no slot concept (just
## a flat list of stored items). Needed so the drop/right-click handlers
## know exactly which slot to clear rather than guessing from item_type
## alone, which stops being unique once two different slots could hold
## the same item_type (e.g. a two-handed item occupies both hands at
## once -- see Unit.equip_item).
var source_slot: String = ""
## Exactly one of these is set, depending on which panel built this button
## -- carried along in the drag payload so the drop handler knows where to
## remove the item from, without having to re-derive "the selected unit/
## building" at drop time (selection could have changed mid-drag).
var source_unit: Unit = null
var source_building: Building = null

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		accept_event()
		right_clicked.emit(item_type, source_slot)

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_type.is_empty():
		return null
	if not is_instance_valid(source_unit) and not is_instance_valid(source_building):
		return null
	var preview := Label.new()
	preview.text = item_type.capitalize()
	preview.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	preview.modulate.a = 0.85
	set_drag_preview(preview)
	return {"item_type": item_type, "source_slot": source_slot, "source_unit": source_unit, "source_building": source_building}
