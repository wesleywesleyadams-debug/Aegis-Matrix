extends Control

@onready var play_button: Button = $VBox/PlayButton
@onready var load_button: Button = $VBox/LoadButton
@onready var account_button: Button = $VBox/AccountButton
@onready var options_button: Button = $VBox/OptionsButton
@onready var quit_button: Button = $VBox/QuitButton
@onready var dim: ColorRect = $Dim
@onready var load_list_panel: Panel = $LoadListPanel
@onready var saves_list: VBoxContainer = $LoadListPanel/OuterVBox/ScrollContainer/SavesList
@onready var close_button: Button = $LoadListPanel/OuterVBox/CloseButton

func _ready() -> void:
	Music.play_track(Music.TITLE_TRACK)
	play_button.pressed.connect(_on_play_pressed)
	load_button.pressed.connect(_on_load_pressed)
	account_button.pressed.connect(AccountMenu.open)
	options_button.pressed.connect(OptionsMenu.open)
	quit_button.pressed.connect(_on_quit_pressed)
	close_button.pressed.connect(_on_close_load_list_pressed)
	load_list_panel.visible = false
	load_button.disabled = _list_saves().is_empty()

	# Dim is only for LoadListPanel now -- Account/Options are their own
	# autoloads with their own full-screen dim (see AccountMenu/
	## OptionsMenu's own Background ColorRect).
	load_list_panel.visibility_changed.connect(_update_dim)
	_update_dim()

	# Which saves exist (and which are even visible in the open load list)
	# depends on who's signed in -- see GameState.saves_dir() -- so refresh
	# both whenever the active account changes mid-session.
	GameState.active_account_changed.connect(_on_active_account_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and load_list_panel.visible:
		_on_close_load_list_pressed()
		get_viewport().set_input_as_handled()

func _update_dim() -> void:
	dim.visible = load_list_panel.visible

func _on_active_account_changed() -> void:
	load_button.disabled = _list_saves().is_empty()
	if load_list_panel.visible:
		_on_load_pressed()

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

## Returns {"path": String, "name": String, "timestamp": float} for every
## save file, newest first.
func _list_saves() -> Array:
	var saves: Array = []
	var saves_dir := GameState.saves_dir()
	var dir := DirAccess.open(saves_dir)
	if dir == null:
		return saves
	for file_name in DirAccess.get_files_at(saves_dir):
		if not file_name.ends_with(".json"):
			continue
		var path := "%s/%s" % [saves_dir, file_name]
		var file := FileAccess.open(path, FileAccess.READ)
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed == null or not parsed.has("units"):
			continue
		saves.append({
			"path": path,
			"name": parsed.get("name", "Save"),
			"timestamp": parsed.get("timestamp", 0.0),
		})
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["timestamp"] > b["timestamp"]
	)
	return saves

func _on_load_pressed() -> void:
	for child in saves_list.get_children():
		child.queue_free()

	for save in _list_saves():
		var button := Button.new()
		var date_str := Time.get_datetime_string_from_unix_time(int(save["timestamp"]), true)
		button.text = "%s  —  %s" % [save["name"], date_str]
		button.pressed.connect(_on_save_entry_pressed.bind(save["path"]))
		saves_list.add_child(button)

	load_list_panel.visible = true

func _on_save_entry_pressed(path: String) -> void:
	GameState.load_on_start = true
	GameState.load_save_path = path
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_close_load_list_pressed() -> void:
	load_list_panel.visible = false

func _on_quit_pressed() -> void:
	get_tree().quit()
