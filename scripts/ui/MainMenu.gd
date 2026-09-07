extends Control
## Top-right main menu button: opens a small panel with pause/resume,
## save, restart, surrender and quit. Runs with PROCESS_MODE_ALWAYS (see
## the node's process_mode in Main.tscn) so its own buttons keep working
## even while the game tree is paused -- otherwise a paused SceneTree
## would freeze the very button that's supposed to unpause it.

const SAVES_DIR := "user://saves"

@onready var dim: ColorRect = $Dim
@onready var menu_button: Button = $MenuButton
@onready var menu_panel: Panel = $MenuPanel
@onready var pause_button: Button = $MenuPanel/VBox/PauseButton
@onready var save_button: Button = $MenuPanel/VBox/SaveButton
@onready var options_button: Button = $MenuPanel/VBox/OptionsButton
@onready var restart_button: Button = $MenuPanel/VBox/RestartButton
@onready var surrender_button: Button = $MenuPanel/VBox/SurrenderButton
@onready var quit_button: Button = $MenuPanel/VBox/QuitButton
@onready var save_confirm_label: Label = $SaveConfirmLabel
@onready var save_name_panel: Panel = $SaveNamePanel
@onready var name_input: LineEdit = $SaveNamePanel/VBox/NameInput
@onready var confirm_save_button: Button = $SaveNamePanel/VBox/ButtonRow/ConfirmSaveButton
@onready var cancel_save_button: Button = $SaveNamePanel/VBox/ButtonRow/CancelSaveButton
@onready var paused_panel: Panel = $PausedPanel
@onready var end_state_panel: Panel = $EndStatePanel
@onready var end_state_label: Label = $EndStatePanel/VBox/EndStateLabel
@onready var end_state_restart_button: Button = $EndStatePanel/VBox/RestartButton
@onready var end_state_quit_button: Button = $EndStatePanel/VBox/QuitButton
@onready var game_timer: Label = $"../GameTimer"

var _save_confirm_timer: SceneTreeTimer
## Whether the tree was already paused (via the Pause button/F5) when the
## save-name popup opened -- restored when the popup closes, rather than
## always unpausing, so this doesn't silently resume a game the player
## had deliberately paused before opening Save.
var _was_paused_before_save: bool = false

func _ready() -> void:
	menu_button.pressed.connect(_on_menu_button_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	save_button.pressed.connect(_on_save_pressed)
	options_button.pressed.connect(OptionsMenu.open)
	confirm_save_button.pressed.connect(_on_confirm_save_pressed)
	cancel_save_button.pressed.connect(_on_cancel_save_pressed)
	name_input.text_submitted.connect(func(_text: String) -> void: _on_confirm_save_pressed())
	restart_button.pressed.connect(_on_restart_pressed)
	surrender_button.pressed.connect(_on_surrender_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	end_state_restart_button.pressed.connect(_on_restart_pressed)
	end_state_quit_button.pressed.connect(_on_quit_pressed)
	menu_panel.visible = false
	save_confirm_label.visible = false
	save_name_panel.visible = false
	paused_panel.visible = false
	end_state_panel.visible = false

	# One dim overlay shared by every popup panel (not PausedPanel/
	## save_confirm_label -- those are small status indicators, not modal
	## popups) -- driven by visibility_changed so it can't drift out of
	## sync with what's actually toggling menu_panel/save_name_panel/
	## end_state_panel across this script's several call sites.
	menu_panel.visibility_changed.connect(_update_dim)
	save_name_panel.visibility_changed.connect(_update_dim)
	end_state_panel.visibility_changed.connect(_update_dim)
	_update_dim()

func _update_dim() -> void:
	dim.visible = menu_panel.visible or save_name_panel.visible or end_state_panel.visible

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and save_name_panel.visible:
		_on_cancel_save_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and end_state_panel.visible == false:
		_on_menu_button_pressed()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		if end_state_panel.visible == false:
			_on_pause_pressed()
			get_viewport().set_input_as_handled()

func _on_menu_button_pressed() -> void:
	menu_panel.visible = not menu_panel.visible

func _on_pause_pressed() -> void:
	get_tree().paused = not get_tree().paused
	pause_button.text = "Resume" if get_tree().paused else "Pause"
	paused_panel.visible = get_tree().paused

func _on_save_pressed() -> void:
	menu_panel.visible = false
	name_input.text = ""
	save_name_panel.visible = true
	name_input.grab_focus()

	_was_paused_before_save = get_tree().paused
	get_tree().paused = true

func _on_cancel_save_pressed() -> void:
	save_name_panel.visible = false
	get_tree().paused = _was_paused_before_save

func _on_confirm_save_pressed() -> void:
	var save_name := name_input.text.strip_edges()
	if save_name.is_empty():
		save_name = "Save"
	save_name_panel.visible = false
	get_tree().paused = _was_paused_before_save

	var units_data: Array = []
	for unit in get_tree().get_nodes_in_group("units"):
		units_data.append({
			"type_id": unit.unit_type_id,
			"position": [unit.global_position.x, unit.global_position.y, unit.global_position.z],
			"current_health": unit.current_health,
			"max_health": unit.max_health,
		})
	var timestamp := Time.get_unix_time_from_system()
	var save_data := {
		"name": save_name,
		"timestamp": timestamp,
		"elapsed_time": game_timer.get_elapsed(),
		"units": units_data,
	}

	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
	var save_path := "%s/save_%d.json" % [SAVES_DIR, int(timestamp * 1000)]
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data))
	file.close()

	_show_confirm("Saved as \"%s\"" % save_name)

func _show_confirm(text: String) -> void:
	save_confirm_label.text = text
	save_confirm_label.visible = true
	if _save_confirm_timer != null:
		_save_confirm_timer.timeout.disconnect(_hide_save_confirm)
	_save_confirm_timer = get_tree().create_timer(1.5, true, false, true)
	_save_confirm_timer.timeout.connect(_hide_save_confirm)

func _hide_save_confirm() -> void:
	save_confirm_label.visible = false

func _on_restart_pressed() -> void:
	get_tree().paused = false
	Music.restart_current_track()
	get_tree().reload_current_scene()

func _on_surrender_pressed() -> void:
	menu_panel.visible = false
	paused_panel.visible = false
	get_tree().paused = true
	end_state_label.text = "You Surrendered"
	end_state_panel.visible = true

func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/TitleMenu.tscn")
