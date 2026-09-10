extends Panel
## Full 5-slot inventory view for whichever unit is selected -- one
## ItemSlotButton per Unit.BACKPACK_SLOTS entry, arranged as a plain 2x2
## grid (Right Hand/Left Hand on top, Armor/Accessory on bottom) plus a
## tall "Two-Hand" slot to their right, spanning both rows, rather than
## a stacked list, always in the same positions whether or not that slot
## is actually occupied so the layout doesn't jump around as items are
## equipped/removed. Hidden entirely when no unit is selected.
## Right Hand/Left Hand show as unusable (a red X, see
## ItemSlotButton.set_blocked) whenever "Two-Hand" holds a strictly
## two-handed weapon (both hands are genuinely committed to it), but as
## plain empty while it holds a re-grippable hybrid_hand one -- see
## Unit.BACKPACK_SLOTS' doc comment for the underlying invariant this
## reflects rather than enforces. Same division of responsibility as the
## other HUD panels -- this only displays and reports the interaction,
## RTSController owns the actual unequip/drop/transfer logic.

signal item_right_clicked(item_type: String, source_slot: String)
signal item_hovered(item_type: String)
signal item_unhovered()

## Every slot cell is a perfect SLOT_SIZE x SLOT_SIZE square, laid out on
## a plain 2x2 grid with a consistent SLOT_GAP between columns/rows;
## "two_hand" is the same width, but spans both rows' combined height.
## SLOT_SIZE is sized to comfortably clear this button theme's own
## natural minimum (~52px tall) rather than fighting it with a smaller
## custom_minimum_size, which the theme would just override anyway.
const SLOT_SIZE: int = 116
const SLOT_GAP: int = 16
const GRID_SPAN: int = SLOT_SIZE * 2 + SLOT_GAP
const SLOT_RECTS: Dictionary = {
	"right_hand": Rect2(0, 0, SLOT_SIZE, SLOT_SIZE),
	"left_hand": Rect2(SLOT_SIZE + SLOT_GAP, 0, SLOT_SIZE, SLOT_SIZE),
	"armor": Rect2(0, SLOT_SIZE + SLOT_GAP, SLOT_SIZE, SLOT_SIZE),
	"accessory": Rect2(SLOT_SIZE + SLOT_GAP, SLOT_SIZE + SLOT_GAP, SLOT_SIZE, SLOT_SIZE),
	"two_hand": Rect2(GRID_SPAN + SLOT_GAP, 0, SLOT_SIZE, GRID_SPAN),
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
	# Both hands are genuinely committed only when "two_hand" holds a
	# strictly two-handed item -- a re-grippable hybrid_hand one there
	# leaves right_hand/left_hand free to take another weapon at any time
	# (see Unit.equip_item/_vacate_two_hand_slot), so they read as plain
	# empty instead of blocked.
	var two_hand_item: String = unit.backpack["two_hand"]
	var both_hands_committed := not two_hand_item.is_empty() and ItemDefs.get_slot_kind(two_hand_item) == "two_hand"
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
		if both_hands_committed and (slot == "right_hand" or slot == "left_hand"):
			button.set_blocked()
		else:
			button.set_item(item_type, slot.capitalize())
			if not item_type.is_empty():
				button.right_clicked.connect(func(t: String, s: String) -> void: item_right_clicked.emit(t, s))
				button.hovered.connect(func(t: String) -> void: item_hovered.emit(t))
				button.unhovered.connect(func() -> void: item_unhovered.emit())
		slots_root.add_child(button)
