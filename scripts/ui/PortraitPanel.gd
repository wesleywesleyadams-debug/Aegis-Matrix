extends Control
## Bottom-left panel showing a live 3D render of the first currently
## selected unit (see PortraitCamera) -- an actual view of that specific
## unit, not a generic icon. Hidden entirely when nothing is selected.

@onready var portrait_viewport: SubViewport = $PortraitViewport
@onready var texture_rect: TextureRect = $TextureRect
@onready var name_label: Label = $NameLabel

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.texture = portrait_viewport.get_texture()
	visible = false

## Called by RTSController whenever selection (or, for a unit/building
## not owned by the player, read-only inspection -- see
## RTSController._inspect_foreign) changes. `unit` is whichever entity
## should now be shown, or null if nothing is. The name label reads the
## entity's own node name (e.g. "Wall", "Human") rather than
## unit_type_id, which for a unit is currently always the generic
## "peasant" regardless of race -- the node name is already the specific,
## human-readable one the selection tray/save data etc. don't have.
func set_subject(unit: Node3D) -> void:
	visible = unit != null
	portrait_viewport.get_node("PortraitCamera").set_target(unit)
	name_label.text = unit.name if unit != null else ""
