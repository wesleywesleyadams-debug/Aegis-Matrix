extends Control
## Bottom-left panel showing a live 3D render of the first currently
## selected unit (see PortraitCamera) -- an actual view of that specific
## unit, not a generic icon. Hidden entirely when nothing is selected.

@onready var portrait_viewport: SubViewport = $PortraitViewport
@onready var texture_rect: TextureRect = $TextureRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.texture = portrait_viewport.get_texture()
	visible = false

## Called by RTSController whenever selection changes. `unit` is
## _selected_units[0] (whichever was selected first), or null if the
## selection is empty.
func set_subject(unit: Node3D) -> void:
	visible = unit != null
	portrait_viewport.get_node("PortraitCamera").set_target(unit)
