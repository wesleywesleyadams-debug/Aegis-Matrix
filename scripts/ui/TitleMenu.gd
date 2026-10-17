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

## The background: a real match between the two AIs, played out live behind
## the menu and restarted on a fresh system each time one ends (see
## Game.demo_mode and DemoDirector). The static picture stays underneath as
## a fallback for the first frame.
const DEMO_SPEED := 2.0
const MAIN_SCENE := preload("res://scenes/Main.tscn")
var _demo_view: SubViewport
var _demo_game: Node
var _demo_round := 0

func _start_demo_backdrop() -> void:
	var box := SubViewportContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.stretch = true
	# Purely a picture: clicks go to the menu, never into the match.
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	move_child(box, get_node("Background").get_index() + 1)
	_demo_view = SubViewport.new()
	_demo_view.handle_input_locally = false
	_demo_view.gui_disable_input = true
	box.add_child(_demo_view)
	# A light veil so the title and buttons stay the thing you read.
	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.02, 0.05, 0.35)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	move_child(veil, box.get_index() + 1)
	_next_demo_match()

## Throws away the finished match (if any) and starts another on a different
## system. The lobby's own system choice is put back untouched.
func _next_demo_match() -> void:
	if is_instance_valid(_demo_game):
		_demo_game.queue_free()
		await get_tree().process_frame
	if not is_inside_tree():
		return
	var keep_id: String = GameState.system_id
	var keep_seed: int = GameState.system_seed
	var named: Array = SystemGen.SYSTEMS.filter(func(x): return x["id"] != "random")
	_demo_round += 1
	# Mostly the named systems in turn, with a random one every third match.
	if _demo_round % 3 == 0:
		GameState.system_id = "random"
		GameState.system_seed = randi()
	else:
		var sys: Dictionary = named[randi() % named.size()]
		GameState.system_id = sys["id"]
		GameState.system_seed = int(sys.get("seed", 0))
	GameState.demo_mode = true
	if OS.get_environment("SL_DEMO_MAX") != "":
		print("DEMO match %d on %s" % [_demo_round, GameState.system_id])
	_demo_game = MAIN_SCENE.instantiate()
	_demo_view.add_child(_demo_game)
	GameState.demo_mode = false
	GameState.system_id = keep_id
	GameState.system_seed = keep_seed
	Engine.time_scale = DEMO_SPEED
	for c in _demo_game.get_children():
		if c is DemoDirector:
			c.finished.connect(_next_demo_match)

func _exit_tree() -> void:
	# Whatever comes next sets its own pace.
	Engine.time_scale = 1.0

func _ready() -> void:
	Music.play_screen(Music.TITLE_TRACK)
	_start_demo_backdrop()
	_build_credits()
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

	# Order: New Game, Load Game, Options, Account, Quit. Account opens the
	# account panel as a pop-up (AccountMenu.open).
	vbox.move_child(account_button, options_button.get_index())
	# Bigger buttons; the menu is centered on screen (see TitleMenu.tscn).
	for b in vbox.get_children():
		if b is Button:
			MenuStyle.button(b)
	# New Game green (like the lobby's Start Match), Quit red.
	_tint(play_button, [Color("1a5a2a"), Color("247a38"), Color("103a1a")], Color("6aff8a"), Color("d6ffe0"))
	MenuStyle.leave(quit_button)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _credits.visible:
		_credits.visible = false
		get_viewport().set_input_as_handled()
		return
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
	_new_game_page.add_theme_constant_override("separation", 16)
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
		MenuStyle.button(b)
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
	if on:
		AccountMenu.close()
	_new_game_page.visible = on
	if on:
		# Centered on screen, like the main menu.
		_new_game_page.reset_size()
		_new_game_page.position = (size - _new_game_page.size) / 2.0

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
	MenuStyle.button(close)
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
	$TitleLabel.visible = false
	AccountMenu.close()
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
	$TitleLabel.visible = true
	vbox.visible = true
	quit_button.visible = true

func _on_quit_pressed() -> void:
	get_tree().quit()

## Dev aid: SL_TITLE_SHOT=1 saves user://title.png after a moment and quits.
func _notification(what: int) -> void:
	if what == NOTIFICATION_READY and OS.get_environment("SL_TITLE_SHOT") != "":
		# SL_TITLE_WAIT=<real seconds> lets the background match get going first.
		await get_tree().create_timer(float(OS.get_environment("SL_TITLE_WAIT")) if OS.get_environment("SL_TITLE_WAIT") != "" else 1.0, true, false, true).timeout
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
		if OS.get_environment("SL_TITLE_SHOT") == "account":
			# In-memory only (never saved): a second account to show both row states.
			GameState.accounts.append({"name": "Guest", "password_hash": ""})
			account_button.pressed.emit()
			await get_tree().process_frame
		if OS.get_environment("SL_TITLE_SHOT") == "options":
			OptionsMenu.open()
			var tab := OS.get_environment("SL_OPTIONS_TAB")
			if tab != "":
				OptionsMenu.get_node("Background/Panel/VBox/TabContainer").current_tab = int(tab)
			await get_tree().process_frame
		if OS.get_environment("SL_TITLE_SHOT") == "credits":
			_credits.visible = true
		if OS.get_environment("SL_TITLE_SHOT") == "create":
			AccountMenu._on_create_account_pressed()
			await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://title.png")
		get_tree().quit()

# ---------------------------------------------------------------- credits

## Music: [title, artist, license, page]. Keep in step with CREDITS.md
## (CC BY-SA tracks must be credited in-game).
const MUSIC_CREDITS := [
	["Through Space", "Maxstack", "CC BY-SA 3.0", "maxstack.googlepages.com"],
	["Space Life No. 14", "yd", "CC0", "opengameart.org/content/spacelife-14"],
	["Magic Space", "CodeManu", "CC0", "opengameart.org/content/magic-space"],
	["Deus Ex Tempus", "Trevor Lentz", "CC BY-SA 3.0", "opengameart.org/content/deus-ex-tempus"],
	["Hero Immortal", "Trevor Lentz", "CC BY-SA 3.0", "opengameart.org/content/hero-immortal"],
	["Galactic Temple", "yd", "CC0", "opengameart.org/content/galactic-temple"],
	["Dark Sci-Fi Audio Pack", "SRG774", "CC0", "opengameart.org/content/dark-sci-fi-audio-pack"],
	["Determined Pursuit", "Emma_MA", "CC0", "opengameart.org/content/determined-pursuit-epic-orchestra-loop"],
	["Spacedman", "Shane Ivers", "CC BY 4.0", "www.silvermansound.com"],
]

var _credits: Control

## A Credits button under Quit, opening a full-screen Credits window with a
## panel per area (Music, Art, Sound & AI, Engine & Development), laid out
## like the Options menu (same panel columns: OptionsMenu._column).
func _build_credits() -> void:
	var codex := Button.new()
	codex.text = "Codex"
	codex.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Codex.tscn"))
	vbox.add_child(codex)
	vbox.move_child(codex, options_button.get_index() + 1)
	MenuStyle.button(codex)

	var btn := Button.new()
	btn.text = "Credits"
	vbox.add_child(btn)
	vbox.move_child(btn, quit_button.get_index() + 1)
	btn.pressed.connect(func(): _credits.visible = true)

	_credits = ColorRect.new()
	_credits.color = Color(0, 0, 0, 0.6)
	_credits.set_anchors_preset(Control.PRESET_FULL_RECT)
	_credits.visible = false
	add_child(_credits)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		panel.set("offset_" + ["left", "top", "right", "bottom"][side], 60 if side in [SIDE_LEFT, SIDE_TOP] else -60)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.12, 0.96)
	st.border_color = Color(0.4, 0.5, 0.8, 0.7)
	st.set_border_width_all(2)
	st.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", st)
	_credits.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var title := Label.new()
	title.text = "Credits"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	v.add_child(title)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 10)
	v.add_child(cols)

	# Music.
	var music := _credit_list(cols, "Music", Color("3fd6b0"))
	for c in MUSIC_CREDITS:
		_credit_entry(music, "\"%s\"" % c[0], "by " + c[1], "%s\n%s" % [c[2], c[3]])
	_credit_entry(music, "Stardust Dominion Synth (Title, Lobby, In-Game)", "Original", "Generated for Stardust Dominion")
	_credit_entry(music, "", "", "CC BY-SA 3.0: creativecommons.org/licenses/by-sa/3.0")

	# Art.
	var art := _credit_list(cols, "Art", Color("ffd166"))
	_credit_entry(art, "Ships, starbases & planets", "Original pixel art", "Generated procedurally for Stardust Dominion (tools/gen_art.gd)")
	_credit_entry(art, "Stars, nebulae, debris rings & ion storms", "Original", "Drawn procedurally in-game")
	_credit_entry(art, "Space backgrounds", "Original", "Generated procedurally per star system")
	_credit_entry(art, "Interface", "Original", "Built for Stardust Dominion")
	_credit_entry(art, "Font", "Consolas / system monospace", "Supplied by your operating system")

	# Sound & AI.
	var sai := _credit_list(cols, "Sound & AI", Color("ff9a2e"))
	_credit_entry(sai, "Sound effects", "Original", "Synthesised for Stardust Dominion (tools/gen_audio.gd): lasers, explosions, alerts, notifications")
	_credit_entry(sai, "Scripted AI opponent", "Original", "Expand / build up / attack / recover strategy")
	_credit_entry(sai, "Neural AI opponent", "Original", "A small neural network trained by evolution strategies over thousands of AI-vs-AI matches, including self-play")

	# Engine & Development.
	var dev := _credit_list(cols, "Engine & Development", Color("7fb2ff"))
	_credit_entry(dev, "Game design & direction", "Wesley Adams", "")
	_credit_entry(dev, "Programming", "Wesley Adams with Claude (Anthropic)", "")
	_credit_entry(dev, "Godot Engine", "godotengine.org", "MIT License. Portions of this software are copyright (c) the Godot Engine contributors.")
	var lic := Label.new()
	# Reflow the hard-wrapped license text (keep paragraph breaks).
	lic.text = RegEx.create_from_string("(?<!\n)\n(?!\n)").sub(Engine.get_license_text(), " ", true)
	lic.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lic.add_theme_font_size_override("font_size", 12)
	lic.add_theme_color_override("font_color", Color(0.55, 0.58, 0.7))
	dev.add_child(lic)

	var close := Button.new()
	close.text = "Close"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size = Vector2(320, 0)
	MenuStyle.button(close)
	close.pressed.connect(func(): _credits.visible = false)
	v.add_child(close)

## A credits panel column with a scrolling list inside; returns the list.
func _credit_list(cols: Control, heading: String, color: Color) -> VBoxContainer:
	return OptionsMenu._scroll_list(OptionsMenu._column(cols, heading, color, 1.0))

## One credit: what (white), who (gold), details (dim, wrapped).
func _credit_entry(list: VBoxContainer, what: String, who: String, details: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	for part in [[what, Color.WHITE, 16], [who, Color("ffd166"), 15], [details, Color(0.65, 0.7, 0.85), 13]]:
		if part[0] == "":
			continue
		var l := Label.new()
		l.text = part[0]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", part[1])
		l.add_theme_font_size_override("font_size", part[2])
		box.add_child(l)
	list.add_child(box)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	list.add_child(gap)

## Colors a menu button: backgrounds for normal/hover/pressed, border, text.
func _tint(b: Button, bg: Array, border: Color, font: Color) -> void:
	for i in 3:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg[i]
		sb.border_color = border
		sb.set_border_width_all(2)
		sb.set_content_margin_all(12)
		b.add_theme_stylebox_override(["normal", "hover", "pressed"][i], sb)
	b.add_theme_color_override("font_color", font)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
