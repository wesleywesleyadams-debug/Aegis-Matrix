extends Control
## Bottom HUD panel showing whichever (single) selected unit's right-hand
## weapon slot, if occupied -- a quick-glance view of the "main hand" item
## sitting right beside the portrait. The full 4-slot inventory (armor/
## right_hand/left_hand/accessory) lives in UnitBackpackPanel above it;
## this is just a shortcut to the one slot players look at most, not a
## separate inventory of its own. Right-clicking the item drops it on the
## ground; dragging it out (see ItemSlotButton) lets the player place it
## anywhere in the world, hand it to another unit, or store it in a
## building. Same division of responsibility as the other HUD panels --
## this only displays and reports the interaction, RTSController owns the
## actual unequip/drop/transfer logic. Hidden entirely unless the selected
## unit's right hand is actually occupied, same as BuildingStoragePanel.

signal item_right_clicked(item_type: String, source_slot: String)
signal item_hovered(item_type: String)
signal item_unhovered()

@onready var list: VBoxContainer = $VBox

## `unit` may be null (nothing selected, or a building/World object is)
## -- either way the panel just goes empty and hides.
func refresh(unit: Unit) -> void:
	for child in list.get_children():
		child.queue_free()
	var item_type: String = unit.backpack["right_hand"] if unit != null else ""
	visible = not item_type.is_empty()
	if not visible:
		return
	var button := ItemSlotButton.new()
	button.item_type = item_type
	button.source_slot = "right_hand"
	button.source_unit = unit
	button.text = item_type.capitalize()
	button.right_clicked.connect(func(t: String, s: String) -> void: item_right_clicked.emit(t, s))
	button.hovered.connect(func(t: String) -> void: item_hovered.emit(t))
	button.unhovered.connect(func() -> void: item_unhovered.emit())
	list.add_child(button)
