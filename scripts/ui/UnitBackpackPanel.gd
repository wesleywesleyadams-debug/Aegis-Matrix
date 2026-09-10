extends Panel
## Full 4-slot inventory view for whichever unit is selected -- one
## ItemSlotButton per Unit.BACKPACK_SLOTS entry, arranged in a cross/
## paper-doll layout (Armor top-center, Accessory bottom-center,
## Right Hand/Left Hand straddling the seam between them on either side --
## matching how a worn-equipment screen conventionally reads) rather than
## a plain stacked list, always in the same positions whether or not that
## slot is actually occupied so the layout doesn't jump around as items
## are equipped/removed. Hidden entirely when no unit is selected.
## EquipmentPanel (beside the portrait) is a quick-glance shortcut to just
## the right_hand slot; this is the complete picture. Same division of
## responsibility as the other HUD panels -- this only displays and
## reports the interaction, RTSController owns the actual unequip/drop/
## transfer logic.

signal item_right_clicked(item_type: String, source_slot: String)
signal item_hovered(item_type: String)
signal item_unhovered()

## Every slot cell is a perfect SLOT_SIZE x SLOT_SIZE square, laid out on
## a grid with a consistent SLOT_GAP between columns -- armor/accessory
## share the center column (top/bottom), left_hand/right_hand sit in the
## outer columns, vertically straddling the seam between armor and
## accessory by design (a conventional worn-equipment/paper-doll layout:
## hands read as "worn between chest and waist" rather than a plain 2x2
## grid). SLOT_SIZE is sized to comfortably clear this button theme's own
## natural minimum (~52px tall) rather than fighting it with a smaller
## custom_minimum_size, which the theme would just override anyway.
const SLOT_SIZE: int = 104
const SLOT_GAP: int = 16
const SLOT_RECTS: Dictionary = {
	"armor": Rect2(SLOT_SIZE + SLOT_GAP, 0, SLOT_SIZE, SLOT_SIZE),
	"left_hand": Rect2(0, SLOT_SIZE / 2.0 + SLOT_GAP / 2.0, SLOT_SIZE, SLOT_SIZE),
	"right_hand": Rect2(2 * (SLOT_SIZE + SLOT_GAP), SLOT_SIZE / 2.0 + SLOT_GAP / 2.0, SLOT_SIZE, SLOT_SIZE),
	"accessory": Rect2(SLOT_SIZE + SLOT_GAP, SLOT_SIZE + SLOT_GAP, SLOT_SIZE, SLOT_SIZE),
}
const SLOT_FONT_SIZE: int = 22

@onready var slots_root: Control = $Slots

## `unit` may be null (nothing selected, or a building/World object is).
func refresh(unit: Unit) -> void:
	for child in slots_root.get_children():
		child.queue_free()
	visible = unit != null
	if not visible:
		return
	for slot in Unit.BACKPACK_SLOTS:
		var item_type: String = unit.backpack[slot]
		var button := ItemSlotButton.new()
		button.source_slot = slot
		button.source_unit = unit
		var rect: Rect2 = SLOT_RECTS[slot]
		button.position = rect.position
		button.size = rect.size
		button.clip_text = true
		button.add_theme_font_size_override("font_size", SLOT_FONT_SIZE)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.set_item(item_type, slot.capitalize())
		if not item_type.is_empty():
			button.right_clicked.connect(func(t: String, s: String) -> void: item_right_clicked.emit(t, s))
			button.hovered.connect(func(t: String) -> void: item_hovered.emit(t))
			button.unhovered.connect(func() -> void: item_unhovered.emit())
		slots_root.add_child(button)
