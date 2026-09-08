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
## should now be shown, or null if nothing is.
func set_subject(unit: Node3D) -> void:
	visible = unit != null
	portrait_viewport.get_node("PortraitCamera").set_target(unit)
	name_label.text = _display_name(unit) if unit != null else ""

## A node's own name isn't reliably its display name -- Godot silently
## appends a number to keep sibling names unique (Main.tscn has two
## Dwellings, so the second is actually named "Dwelling2"), which would
## otherwise show up as if it were a different, numbered thing. Strips a
## trailing run of digits -- Godot's own uniquification pattern -- off
## any node name for display, for any kind of object alike, rather than
## trusting the raw name outright.
static var _trailing_digits := RegEx.create_from_string("\\d+$")

func _display_name(unit: Node3D) -> String:
	var stripped := _trailing_digits.sub(unit.name, "")
	return stripped if not stripped.is_empty() else unit.name
