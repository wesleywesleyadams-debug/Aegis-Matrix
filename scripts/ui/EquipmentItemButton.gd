extends Button
class_name EquipmentItemButton
## One equipped-item slot in EquipmentPanel -- right-click drops it on the
## ground at the unit's feet (see _gui_input()); dragging it out lets the
## player place it wherever they choose, or hand it straight to another
## unit (see _get_drag_data() / RTSController.handle_equipment_item_drop,
## the actual drop target). Plain left-click still fires the ordinary
## `pressed` signal, same as a regular Button.

signal right_clicked(item_type: String)

var item_type: String = ""
## Which unit this item is currently equipped on -- set by
## EquipmentPanel.refresh() each time it rebuilds the panel. Carried along
## in the drag payload so the drop handler knows who to unequip from,
## without having to re-derive "the selected unit" at drop time (selection
## could have changed mid-drag).
var source_unit: Unit = null

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		accept_event()
		right_clicked.emit(item_type)

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_type.is_empty() or not is_instance_valid(source_unit):
		return null
	var preview := Label.new()
	preview.text = item_type.capitalize()
	preview.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	preview.modulate.a = 0.85
	set_drag_preview(preview)
	return {"item_type": item_type, "source_unit": source_unit}
