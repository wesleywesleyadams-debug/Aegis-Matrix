extends Control

@onready var play_button: Button = $VBox/PlayButton
@onready var load_button: Button = $VBox/LoadButton
@onready var account_button: Button = $VBox/AccountButton
@onready var options_button: Button = $VBox/OptionsButton
@onready var editor_button: Button = $VBox/EditorButton
@onready var quit_button: Button = $VBox/QuitButton
@onready var vbox: VBoxContainer = $VBox
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
	editor_button.pressed.connect(_on_editor_pressed)
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

	# Nudge a not-signed-in player straight to the Account panel the moment
	# they land on the title screen (whether that's the game's very first
	# launch, or just coming back here not signed in) -- already signed in
	# (e.g. "Stay signed in" restored a session) skips this entirely.
	# Account options live right under the main menu (no pop-up). Wait a
	# frame so the menu has its final size.
	await get_tree().process_frame
	var account_bottom: float = AccountMenu.dock(vbox.get_global_rect().end.y + 24.0)
	# Order: New Game, Load Game, Options, account section, Quit.
	var quit_width := quit_button.size.x
	vbox.remove_child(quit_button)
	add_child(quit_button)
	quit_button.size = Vector2(quit_width, quit_button.get_combined_minimum_size().y)
	quit_button.position = Vector2((size.x - quit_width) / 2.0, account_bottom + 24.0)
	tree_exiting.connect(AccountMenu.undock)
	# The corner Sign In link would duplicate the options shown here.
	SignedInLabel.visible = false
	tree_exiting.connect(func(): SignedInLabel.visible = true)

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

func _on_editor_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MapEditor.tscn")

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

## Dev aid: SL_TITLE_SHOT=1 saves user://title.png after a moment and quits.
func _notification(what: int) -> void:
	if what == NOTIFICATION_READY and OS.get_environment("SL_TITLE_SHOT") != "":
		await get_tree().create_timer(1.0).timeout
		if OS.get_environment("SL_TITLE_SHOT") == "create":
			AccountMenu._on_create_account_pressed()
			await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://title.png")
		get_tree().quit()
