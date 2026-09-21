extends Control
## Row of small buttons at the bottom of the screen, in the gap between
## the selection panel and the minimap (see Main.tscn's own placement) --
## one per currently-assigned control group (RTSController._control_groups,
## set via Ctrl+<number>/Ctrl+0), left-aligned and in ascending group-number
## order. No dedicated per-unit-type art exists yet (see
## UnitIconPlaceholder's own doc comment), so each button just reuses that
## same silhouette (tinted to the group's own player color) plus a number
## badge for the group's own digit -- no text label (the user's own call:
## icon + number only, nothing spelling out the type). Clicking a button
## recalls that group, the same as pressing its number key.

signal group_clicked(number: int)

const BUTTON_SIZE: float = 34.0
const SPACING: float = 4.0

## Rebuilds every button from scratch each call -- cheap, short-lived UI
## state, same "throw away and redraw" pattern MultiSelectIcons/TaskPanel's
## queue icons use rather than diffed in place. `entries` is an Array of
## {"number": int, "label": String, "player_id": int} dictionaries, already
## resolved by RTSController (see its own _refresh_control_group_bar) so
## this script never needs to know what a Unit/Building/World even is --
## `label` is carried through unused here (kept in RTSController's own
## entry shape in case a future tooltip wants it) rather than dropped from
## the dictionary entirely.
func refresh(entries: Array) -> void:
	for child in get_children():
		child.queue_free()
	var x := 0.0
	for entry in entries:
		var button := _build_button(entry)
		button.position = Vector2(x, 0)
		add_child(button)
		x += BUTTON_SIZE + SPACING

func _build_button(entry: Dictionary) -> Control:
	# Plain Control/Button nodes (not Containers) never auto-apply
	# custom_minimum_size to their actual rect the way a child of an
	# HBoxContainer/VBoxContainer would -- without also setting `.size`
	# directly, every node built below stays at its (0, 0) default and
	# draws nothing at all, even though it exists in the tree with the
	# right script/text/color already set.
	var button := Button.new()
	button.size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	button.custom_minimum_size = button.size
	button.flat = true
	button.pressed.connect(func(): group_clicked.emit(entry["number"]))

	var icon := Control.new()
	icon.set_script(preload("res://scripts/ui/UnitIconPlaceholder.gd"))
	icon.size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_player_id(entry["player_id"])
	button.add_child(icon)

	var number_label := Label.new()
	number_label.text = str(entry["number"])
	number_label.position = Vector2(2, 0)
	number_label.size = Vector2(BUTTON_SIZE - 4, 18)
	number_label.add_theme_font_size_override("font_size", 13)
	number_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	number_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	number_label.add_theme_constant_override("outline_size", 3)
	number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(number_label)

	return button
