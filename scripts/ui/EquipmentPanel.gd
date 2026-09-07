extends Control
## Bottom HUD panel showing whichever (single) selected unit's equipped
## weapon, if any. Right-clicking the item drops it on the ground; dragging
## it out (see ItemSlotButton) lets the player place it anywhere in the
## world, hand it to another unit, or store it in a building. Same
## division of responsibility as the other HUD panels -- this only
## displays and reports the interaction, RTSController owns the actual
## unequip/drop/transfer logic.

signal item_right_clicked(item_type: String)

@onready var list: VBoxContainer = $VBox

## `unit` may be null (nothing selected, or a building/World object is)
## -- either way the panel just goes empty.
func refresh(unit: Unit) -> void:
	for child in list.get_children():
		child.queue_free()
	if unit == null or unit.equipped_weapon.is_empty():
		return
	var item_type := unit.equipped_weapon
	var button := ItemSlotButton.new()
	button.item_type = item_type
	button.source_unit = unit
	button.text = item_type.capitalize()
	button.right_clicked.connect(func(t: String) -> void: item_right_clicked.emit(t))
	list.add_child(button)
