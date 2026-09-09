extends Control
## HUD panel showing a selected building's stored items (see
## Building.stored_items) as a 2-row-by-3-column grid of square icon
## slots -- MAX_STORAGE_SLOTS(5) always fits with room to spare, so
## there's no need to scroll. Right-clicking a slot drops it on the
## ground at the building; dragging it out (see ItemSlotButton) lets the
## player hand it to a unit or place it elsewhere. Hidden entirely when
## no building is selected.

signal item_right_clicked(item_type: String, source_slot: String)
signal item_hovered(item_type: String)
signal item_unhovered()

## Square cell size -- same as UnitBackpackPanel's SLOT_RECTS cells, so a
## storage slot and a backpack slot read as the same visual unit. 3
## columns * this fits inside the shared 416px-wide slot area with room
## on both sides to center it (see refresh()'s GRID_MARGIN).
const CELL_SIZE: float = 104.0
const GRID_COLUMNS: int = 3
## Horizontal inset centering the (CELL_SIZE * GRID_COLUMNS)-wide grid
## within the panel's full slot-area width (matches UnitBackpackPanel's
## Slots control width) -- see Main.tscn's Grid node offsets.

@onready var grid: GridContainer = $Grid
@onready var title_label: Label = $TitleLabel

## `building` may be null (nothing selected, or a unit/World object is).
func refresh(building: Building) -> void:
	for child in grid.get_children():
		child.queue_free()
	visible = building != null
	if building == null:
		return
	title_label.text = "Storage (%d/%d)" % [building.stored_items.size(), Building.MAX_STORAGE_SLOTS]
	for item_type in building.stored_items:
		var button := ItemSlotButton.new()
		button.source_building = building
		button.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.set_item(item_type)
		button.right_clicked.connect(func(t: String, s: String) -> void: item_right_clicked.emit(t, s))
		button.hovered.connect(func(t: String) -> void: item_hovered.emit(t))
		button.unhovered.connect(func() -> void: item_unhovered.emit())
		grid.add_child(button)
