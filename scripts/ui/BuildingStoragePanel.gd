extends Control
## HUD panel showing a selected building's stored items (see
## Building.stored_items) -- one row per item, up to
## Building.MAX_STORAGE_SLOTS. Right-clicking a row drops it on the
## ground at the building; dragging it out (see ItemSlotButton) lets the
## player hand it to a unit or place it elsewhere. Hidden entirely
## when no building is selected -- same idea EquipmentPanel uses for a
## unit with nothing equipped.

signal item_right_clicked(item_type: String, source_slot: String)
signal item_hovered(item_type: String)
signal item_unhovered()

@onready var list: VBoxContainer = $ScrollContainer/VBox
@onready var title_label: Label = $TitleLabel

## `building` may be null (nothing selected, or a unit/World object is).
func refresh(building: Building) -> void:
	for child in list.get_children():
		child.queue_free()
	visible = building != null
	if building == null:
		return
	title_label.text = "Storage (%d/%d)" % [building.stored_items.size(), Building.MAX_STORAGE_SLOTS]
	for item_type in building.stored_items:
		var button := ItemSlotButton.new()
		button.source_building = building
		button.set_item(item_type)
		button.right_clicked.connect(func(t: String, s: String) -> void: item_right_clicked.emit(t, s))
		button.hovered.connect(func(t: String) -> void: item_hovered.emit(t))
		button.unhovered.connect(func() -> void: item_unhovered.emit())
		list.add_child(button)
