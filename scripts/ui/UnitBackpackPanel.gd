extends Panel
## Full 4-slot inventory view for whichever unit is selected -- one
## ItemSlotButton per Unit.BACKPACK_SLOTS entry, always shown in the same
## order (armor, right_hand, left_hand, accessory) whether or not that
## slot is actually occupied, so the layout doesn't jump around as items
## are equipped/removed. Hidden entirely when no unit is selected.
## EquipmentPanel (beside the portrait) is a quick-glance shortcut to just
## the right_hand slot; this is the complete picture. Same division of
## responsibility as the other HUD panels -- this only displays and
## reports the interaction, RTSController owns the actual unequip/drop/
## transfer logic.

signal item_right_clicked(item_type: String, source_slot: String)
signal item_hovered(item_type: String)
signal item_unhovered()

@onready var list: VBoxContainer = $Slots

## `unit` may be null (nothing selected, or a building/World object is).
func refresh(unit: Unit) -> void:
	for child in list.get_children():
		child.queue_free()
	visible = unit != null
	if not visible:
		return
	for slot in Unit.BACKPACK_SLOTS:
		var item_type: String = unit.backpack[slot]
		var button := ItemSlotButton.new()
		button.source_slot = slot
		button.source_unit = unit
		button.custom_minimum_size = Vector2(0, 26)
		if item_type.is_empty():
			button.text = slot.capitalize() + ": (empty)"
			button.disabled = true
		else:
			button.item_type = item_type
			button.text = slot.capitalize() + ": " + item_type.capitalize()
			button.right_clicked.connect(func(t: String, s: String) -> void: item_right_clicked.emit(t, s))
			button.hovered.connect(func(t: String) -> void: item_hovered.emit(t))
			button.unhovered.connect(func() -> void: item_unhovered.emit())
		list.add_child(button)
