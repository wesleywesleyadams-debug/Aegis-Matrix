extends Button
class_name EquipmentItemButton
## One equipped-item slot in EquipmentPanel -- right-click drops it on the
## ground (see _gui_input()). Plain left-click still fires the ordinary
## `pressed` signal, same as a regular Button.

signal right_clicked(item_type: String)

var item_type: String = ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		accept_event()
		right_clicked.emit(item_type)
