extends Control
## HUD panel showing a selected building's stored items (see
## Building.stored_items) -- one row per item. Right-clicking a row drops
## it on the ground at the building; dragging it out (see ItemSlotButton)
## lets the player hand it to a unit or place it elsewhere. Hidden entirely
## when no building is selected -- same idea EquipmentPanel uses for a
## unit with nothing equipped.

signal item_right_clicked(item_type: String)

@onready var list: VBoxContainer = $ScrollContainer/VBox

## `building` may be null (nothing selected, or a unit/World object is).
func refresh(building: Building) -> void:
	for child in list.get_children():
		child.queue_free()
	visible = building != null
	if building == null:
		return
	for item_type in building.stored_items:
		var button := ItemSlotButton.new()
		button.item_type = item_type
		button.source_building = building
		button.text = item_type.capitalize()
		button.right_clicked.connect(func(t: String) -> void: item_right_clicked.emit(t))
		list.add_child(button)
