extends Control

@onready var play_button: Button = $VBox/PlayButton
@onready var load_button: Button = $VBox/LoadButton
@onready var account_button: Button = $VBox/AccountButton
@onready var options_button: Button = $VBox/OptionsButton
@onready var editor_button: Button = $VBox/EditorButton
@onready var quit_button: Button = $VBox/QuitButton
@onready var vbox: VBoxContainer = $VBox
@onready var dim: ColorRect = $Dim
## The Load Game screen (built in code; see _build_load_screen).
var load_list_panel: Control
@onready var saves_list: VBoxContainer = $LoadListPanel/OuterVBox/ScrollContainer/SavesList
@onready var close_button: Button = $LoadListPanel/OuterVBox/CloseButton

func _ready() -> void:
	Music.play_track(Music.TITLE_TRACK)
	_build_new_game_page()
	$LoadListPanel.visible = false
	load_list_panel = _build_load_screen()
	play_button.pressed.connect(_on_play_pressed)
	load_button.pressed.connect(_on_load_pressed)
	account_button.pressed.connect(AccountMenu.open)
	options_button.pressed.connect(OptionsMenu.open)
	editor_button.pressed.connect(_on_editor_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	close_button.pressed.connect(_on_close_load_list_pressed)
	load_list_panel.visible = false

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
	if event.is_action_pressed("ui_cancel") and _new_game_page.visible:
		_show_new_game_page(false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and load_list_panel.visible:
		_on_close_load_list_pressed()
		get_viewport().set_input_as_handled()

func _update_dim() -> void:
	dim.visible = load_list_panel.visible

func _on_active_account_changed() -> void:
	if load_list_panel.visible:
		_on_load_pressed()

## New Game opens a second page: Single-Player, Multi-Player, Campaign.
func _on_play_pressed() -> void:
	_show_new_game_page(true)

var _new_game_page: VBoxContainer

func _build_new_game_page() -> void:
	_new_game_page = VBoxContainer.new()
	_new_game_page.add_theme_constant_override("separation", 12)
	_new_game_page.visible = false
	add_child(_new_game_page)
	for spec in [
		["Single-Player", func(): _open_lobby("single"), ""],
		["Multi-Player", func(): _open_lobby("multi"), ""],
		["Campaign", Callable(), "Coming soon"],
		["Back", func(): _show_new_game_page(false), ""],
	]:
		var b := Button.new()
		b.text = spec[0]
		if spec[1].is_valid():
			b.pressed.connect(spec[1])
		else:
			b.disabled = true
			b.tooltip_text = spec[2]
		_new_game_page.add_child(b)

## Both modes use the lobby; the chosen mode is kept on GameState.
func _open_lobby(mode: String) -> void:
	GameState.game_mode = mode
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

## Swaps the main menu (and the account section and Quit under it) for the
## New Game page, or back.
func _show_new_game_page(on: bool) -> void:
	vbox.visible = not on
	quit_button.visible = not on
	AccountMenu.background.visible = not on
	_new_game_page.visible = on
	if on:
		_new_game_page.size = Vector2(vbox.size.x, 0)
		_new_game_page.position = vbox.position

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
		if not parsed is Dictionary:
			continue
		saves.append({
			"mode": parsed.get("mode", "single"),
			"path": path,
			"name": parsed.get("name", "Save"),
			"timestamp": parsed.get("timestamp", 0.0),
		})
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["timestamp"] > b["timestamp"]
	)
	return saves

const SAVE_MODES := [["multi", "Multi-Player"], ["single", "Single-Player"], ["campaign", "Campaign"]]
var _save_lists := {}

## Load Game: three side-by-side panels (Multi-Player, Single-Player,
## Campaign), each listing that mode's saves, newest first.
func _build_load_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.visible = false
	add_child(screen)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	center.add_child(v)
	var title := Label.new()
	title.text = "Load Game"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	v.add_child(row)
	for pair in SAVE_MODES:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(380, 520)
		row.add_child(panel)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		panel.add_child(col)
		var head := Label.new()
		head.text = pair[1]
		head.add_theme_font_size_override("font_size", 22)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(head)
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		col.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 6)
		scroll.add_child(list)
		_save_lists[pair[0]] = list
	var close := Button.new()
	close.text = "Back"
	close.custom_minimum_size = Vector2(220, 0)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_on_close_load_list_pressed)
	v.add_child(close)
	return screen

func _on_load_pressed() -> void:
	for mode in _save_lists:
		for child in _save_lists[mode].get_children():
			child.queue_free()
	var counts := {}
	for save in _list_saves():
		var mode: String = save["mode"] if _save_lists.has(save["mode"]) else "single"
		var button := Button.new()
		var date_str := Time.get_datetime_string_from_unix_time(int(save["timestamp"]), true)
		button.text = "%s
%s" % [save["name"], date_str.replace("T", "  ")]
		button.pressed.connect(_on_save_entry_pressed.bind(save["path"], mode, save["name"]))
		_save_lists[mode].add_child(button)
		counts[mode] = counts.get(mode, 0) + 1
	for mode in _save_lists:
		if counts.get(mode, 0) == 0:
			var empty := Label.new()
			empty.text = "No saves yet"
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.modulate = Color(1, 1, 1, 0.5)
			_save_lists[mode].add_child(empty)
	# The main menu and account section step aside while this is open.
	vbox.visible = false
	quit_button.visible = false
	AccountMenu.background.visible = false
	load_list_panel.visible = true

## Single-player and campaign saves resume straight into the match; a
## multi-player save goes to the multi-player lobby first so players can
## gather, and Start Match there resumes it.
func _on_save_entry_pressed(path: String, mode: String, save_name: String) -> void:
	GameState.load_on_start = true
	GameState.load_save_path = path
	GameState.load_save_name = save_name
	GameState.game_mode = mode
	if mode == "multi":
		get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_close_load_list_pressed() -> void:
	load_list_panel.visible = false
	vbox.visible = true
	quit_button.visible = true
	AccountMenu.background.visible = true

func _on_quit_pressed() -> void:
	get_tree().quit()

## Dev aid: SL_TITLE_SHOT=1 saves user://title.png after a moment and quits.
func _notification(what: int) -> void:
	if what == NOTIFICATION_READY and OS.get_environment("SL_TITLE_SHOT") != "":
		await get_tree().create_timer(1.0).timeout
		if OS.get_environment("SL_TITLE_SHOT") == "loadmulti":
			for s in _list_saves():
				if s["mode"] == "multi":
					_on_save_entry_pressed(s["path"], "multi", s["name"])
					return
		if OS.get_environment("SL_TITLE_SHOT") == "load":
			_on_load_pressed()
			await get_tree().process_frame
		if OS.get_environment("SL_TITLE_SHOT") == "new":
			_on_play_pressed()
			await get_tree().process_frame
		if OS.get_environment("SL_TITLE_SHOT") == "create":
			AccountMenu._on_create_account_pressed()
			await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://title.png")
		get_tree().quit()
