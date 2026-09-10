extends Button
## Toggles GameState.show_combat_hitboxes -- every Entity already on the
## field picks this up live via GameState's own
## combat_hitboxes_visibility_changed signal (see Entity._ready()), so
## this button only needs to flip the flag and persist it, not reach into
## the scene tree itself.

func _ready() -> void:
	_update_text()
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	GameState.show_combat_hitboxes = not GameState.show_combat_hitboxes
	GameState.save_settings()
	_update_text()

func _update_text() -> void:
	text = "Hitboxes: %s" % ("On" if GameState.show_combat_hitboxes else "Off")
