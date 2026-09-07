extends Button
class_name ItemSlotButton
## One item-holding slot button, shared by EquipmentPanel (a unit's single
## equipped weapon) and BuildingStoragePanel (one row per stored item).
## Right-click drops it on the ground where its owner is standing; dragging
## it out lets the player place it anywhere in the world, hand it to a
## unit, or store it in a building (see ItemDropTarget/
## RTSController.handle_item_drag_drop, the actual drop target/logic).

signal right_clicked(item_type: String)

var item_type: String = ""
## Exactly one of these is set, depending on which panel built this button
## -- carried along in the drag payload so the drop handler knows where to
## remove the item from, without having to re-derive "the selected unit/
## building" at drop time (selection could have changed mid-drag).
var source_unit: Unit = null
var source_building: Building = null

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		accept_event()
		right_clicked.emit(item_type)

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
	return {"item_type": item_type, "source_unit": source_unit, "source_building": source_building}
