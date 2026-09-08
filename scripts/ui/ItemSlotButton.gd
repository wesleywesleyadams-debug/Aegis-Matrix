extends Button
class_name ItemSlotButton
## One item-holding slot button, shared by EquipmentPanel (a unit's single
## equipped weapon) and BuildingStoragePanel (one row per stored item).
## Right-click drops it on the ground where its owner is standing; dragging
## it out lets the player place it anywhere in the world, hand it to a
## unit, or store it in a building (see ItemDropTarget/
## RTSController.handle_item_drag_drop, the actual drop target/logic).

signal right_clicked(item_type: String, source_slot: String)
## For ItemStatsPanel -- see RTSController._on_item_slot_hovered/
## _on_item_slot_unhovered. Only emitted for a non-empty slot (an empty
## one has nothing to show stats for).
signal hovered(item_type: String)
signal unhovered()

func _ready() -> void:
	mouse_entered.connect(func() -> void:
		if not item_type.is_empty():
			hovered.emit(item_type)
	)
	mouse_exited.connect(func() -> void: unhovered.emit())

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
