extends Button
## Toggles GameState.show_grip_points -- every Unit already on the field
## picks this up live via GameState's own grip_points_visibility_changed
## signal (see Unit._ready()), so this button only needs to flip the flag
## and persist it, not reach into the scene tree itself.

func _ready() -> void:
	_update_text()
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	GameState.show_grip_points = not GameState.show_grip_points
	GameState.save_settings()
	_update_text()

func _update_text() -> void:
	text = "Grip Points: %s" % ("On" if GameState.show_grip_points else "Off")
