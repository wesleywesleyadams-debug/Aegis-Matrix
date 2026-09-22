extends CanvasLayer
## Autoload -- the one Options menu shared by TitleMenu, Lobby, and Main
## (see each screen's Options button). Being an autoload rather than a
## scene instanced separately in all three means there's genuinely only
## one of these, matching "they all go to the same menu" -- not three
## copies that happen to look alike.

@onready var background: Control = $Background
@onready var panel: Panel = $Background/Panel
@onready var close_button: Button = $Background/Panel/VBox/CloseButtonRow/CloseButton
@onready var master_slider: HSlider = $Background/Panel/VBox/TabContainer/Audio/MasterVolumeRow/MasterSlider
@onready var music_slider: HSlider = $Background/Panel/VBox/TabContainer/Audio/MusicVolumeRow/MusicSlider
@onready var audio_enabled_checkbox: CheckBox = $Background/Panel/VBox/TabContainer/Audio/ToggleRow/AudioEnabledCheckBox
@onready var music_enabled_checkbox: CheckBox = $Background/Panel/VBox/TabContainer/Audio/ToggleRow/MusicEnabledCheckBox
@onready var show_grid_checkbox: CheckBox = $Background/Panel/VBox/TabContainer/Visuals/ShowGridCheckBox
@onready var font_option: OptionButton = $Background/Panel/VBox/TabContainer/Visuals/FontRow/FontOption

var _master_bus_index: int = 0

## UI font choices for the Visuals tab's Font dropdown -- key (see
## GameState.ui_font) -> [display name, font resource]. null means "Default"
## (falls back to Godot's own built-in font instead of overriding it).
const FONT_OPTIONS: Dictionary = {
	"console": ["Console (pixel)", preload("res://themes/console_font.tres")],
	"default": ["Default", null],
}
## Insertion order of FONT_OPTIONS' keys -- Dictionary iteration order in
## GDScript matches insertion order, but this makes that assumption explicit
## and gives _populate_font_options/index<->key lookups something to zip
## against, rather than relying on it silently.
const FONT_OPTION_KEYS: Array = ["console", "default"]

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	background.visible = false
	_master_bus_index = AudioServer.get_bus_index("Master")
	# Mix bus safety: pull the whole mix down 3 dB (a big battle measured
	# -15 LUFS, a touch hot) and hard-limit peaks at -1.5 dB so 50 ships
	# firing at once can never clip. Independent of the player's volume slider.
	var limiter := AudioEffectHardLimiter.new()
	limiter.pre_gain_db = -3.0
	limiter.ceiling_db = -1.5
	AudioServer.add_bus_effect(_master_bus_index, limiter)

	_build_music_section()
	MenuStyle.button(close_button)
	close_button.pressed.connect(close)
	master_slider.value_changed.connect(_on_master_slider_changed)
	music_slider.value_changed.connect(_on_music_slider_changed)
	audio_enabled_checkbox.toggled.connect(_on_audio_enabled_toggled)
	music_enabled_checkbox.toggled.connect(_on_music_enabled_toggled)
	show_grid_checkbox.toggled.connect(_on_show_grid_toggled)
	_populate_font_options()
	font_option.item_selected.connect(_on_font_selected)
	_build_hotkeys_tab()
	_build_visuals_tab()

	apply_current_settings()

## Pushes every GameState audio/visuals setting onto both the live systems
## (audio bus, music player, shared theme font, debug grid) and this
## panel's own controls (sliders/checkboxes/dropdown) -- called at startup
## and again by AccountMenu whenever the signed-in account changes, so
## switching accounts actually takes effect immediately instead of only on
## next launch.
func apply_current_settings() -> void:
	AudioServer.set_bus_volume_db(_master_bus_index, GameState.master_volume_db)
	master_slider.value = GameState.master_volume_db
	Music.apply_volume()
	music_slider.value = GameState.music_volume_db

	audio_enabled_checkbox.button_pressed = GameState.audio_enabled
	_apply_audio_enabled(GameState.audio_enabled)
	music_enabled_checkbox.button_pressed = GameState.music_enabled
	_apply_music_enabled(GameState.music_enabled)

	show_grid_checkbox.button_pressed = GameState.show_debug_grid
	_apply_show_debug_grid(GameState.show_debug_grid)

	font_option.selected = maxi(FONT_OPTION_KEYS.find(GameState.ui_font), 0)
	_apply_font(GameState.ui_font)

func _unhandled_input(event: InputEvent) -> void:
	if background.visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func open() -> void:
	_refresh_tracks()
	background.visible = true

func close() -> void:
	Music.stop_preview()
	background.visible = false

func _on_master_slider_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(_master_bus_index, value)
	GameState.master_volume_db = value
	GameState.save_settings()

func _on_music_slider_changed(value: float) -> void:
	GameState.music_volume_db = value
	Music.apply_volume()
	GameState.save_settings()

func _on_audio_enabled_toggled(pressed: bool) -> void:
	GameState.audio_enabled = pressed
	_apply_audio_enabled(pressed)
	GameState.save_settings()

func _on_music_enabled_toggled(pressed: bool) -> void:
	GameState.music_enabled = pressed
	_apply_music_enabled(pressed)
	GameState.save_settings()

## Mutes the whole Master bus -- everything routes through it (see
## Music.player.bus), so this is a hard "all game audio off" switch,
## independent of (and layered on top of) the master volume slider's dB
## value, which stays untouched and takes effect again once unmuted.
func _apply_audio_enabled(enabled: bool) -> void:
	AudioServer.set_bus_mute(_master_bus_index, not enabled)

## Pauses/resumes just the music player rather than touching the Master
## bus -- so Music On/Off doesn't also silence the (not yet used) SFX this
## bus will eventually carry.
func _apply_music_enabled(enabled: bool) -> void:
	Music.player.stream_paused = not enabled

func _on_show_grid_toggled(pressed: bool) -> void:
	GameState.show_debug_grid = pressed
	GameState.save_settings()
	_apply_show_debug_grid(pressed)

## If the current scene actually has a debug grid to show/hide (only true
## in Main -- the title screen and lobby don't have one), updates it live
## too instead of only taking effect the next time Main loads.
func _apply_show_debug_grid(pressed: bool) -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_node("DebugGrid"):
		scene.get_node("DebugGrid").visible = pressed

func _populate_font_options() -> void:
	for key in FONT_OPTION_KEYS:
		font_option.add_item(FONT_OPTIONS[key][0])

func _on_font_selected(index: int) -> void:
	var key: String = FONT_OPTION_KEYS[index]
	GameState.ui_font = key
	GameState.save_settings()
	_apply_font(key)

## Swaps the shared theme's default_font -- every Control using
## res://themes/hud_theme.tres (the whole UI, see project.godot's
## gui/theme/custom) picks this up live via Theme's theme_changed signal,
## no per-scene work needed.
func _apply_font(key: String) -> void:
	var hud_theme: Theme = load("res://themes/hud_theme.tres")
	hud_theme.default_font = FONT_OPTIONS[key][1]

# ---------------------------------------------------------------- music tracks

const ENABLED_COLOR := Color("3fd6b0")   # teal
const DISABLED_COLOR := Color("ff9a2e")  # orange

var _enabled_list: VBoxContainer
var _disabled_list: VBoxContainer
var _enabled_title: Label
var _disabled_title: Label
var _track_status: Label
var _file_dialog: FileDialog

## Audio tab as three panels side by side:
##   1. Audio: the volume sliders and Audio / Music toggles (moved in from the
##      scene as they are);
##   2. Playlist: enabled songs (teal) with Preview / Disable, and Add Song...;
##   3. Disabled: disabled songs (orange) with Preview / Enable.
## Songs are never deleted here, only moved between the two lists.
func _build_music_section() -> void:
	var audio: Control = $Background/Panel/VBox/TabContainer/Audio
	var cols := HBoxContainer.new()
	cols.set_anchors_preset(Control.PRESET_FULL_RECT)
	cols.offset_left = 10
	cols.offset_top = 10
	cols.offset_right = -10
	cols.offset_bottom = -10
	cols.add_theme_constant_override("separation", 10)
	audio.add_child(cols)

	# 1. Audio settings.
	var settings := _column(cols, "Audio", Color.WHITE, 0.8)
	for path in ["MasterVolumeRow", "MusicVolumeRow", "ToggleRow"]:
		var n: Control = audio.get_node(path)
		audio.remove_child(n)
		settings.add_child(n)
	var toggles: HBoxContainer = settings.get_node("ToggleRow")
	toggles.alignment = BoxContainer.ALIGNMENT_BEGIN
	toggles.add_theme_constant_override("separation", 16)
	for c in [audio_enabled_checkbox, music_enabled_checkbox]:
		c.custom_minimum_size = Vector2(0, 40)

	# 2. Playlist.
	var pl := _column(cols, "Playlist", ENABLED_COLOR, 1.1)
	_enabled_title = pl.get_child(0)
	_enabled_list = _scroll_list(pl)
	var hint := Label.new()
	hint.text = "These play during matches, one after another."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pl.add_child(hint)
	var add := Button.new()
	add.text = "Add Song..."
	add.pressed.connect(func(): _file_dialog.popup_centered_ratio(0.7))
	pl.add_child(add)
	_track_status = Label.new()
	_track_status.add_theme_font_size_override("font_size", 13)
	_track_status.clip_text = true
	pl.add_child(_track_status)

	# 3. Disabled.
	var dis := _column(cols, "Disabled", DISABLED_COLOR, 1.1)
	_disabled_title = dis.get_child(0)
	_disabled_list = _scroll_list(dis)

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.title = "Add songs to the in-game music"
	_file_dialog.filters = PackedStringArray(["*.ogg, *.mp3, *.wav ; Music files"])
	_file_dialog.files_selected.connect(_on_songs_selected)
	add_child(_file_dialog)
	Music.tracks_changed.connect(_refresh_tracks)
	_refresh_tracks()

## A bordered panel column with a colored heading; returns its content box.
func _column(parent: Control, heading: String, color: Color, stretch: float) -> VBoxContainer:
	var panel_box := PanelContainer.new()
	panel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_box.size_flags_stretch_ratio = stretch
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.12, 0.9)
	st.border_color = Color(color, 0.55)
	st.set_border_width_all(2)
	st.set_content_margin_all(12)
	panel_box.add_theme_stylebox_override("panel", st)
	parent.add_child(panel_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel_box.add_child(v)
	var title := Label.new()
	title.text = heading
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", color)
	v.add_child(title)
	return v

func _scroll_list(parent: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list

## Fills the Playlist (teal) and Disabled (orange) panels.
func _refresh_tracks() -> void:
	if _enabled_list == null:
		return
	for list in [_enabled_list, _disabled_list]:
		for c in list.get_children():
			c.queue_free()
	var tracks := Music.available_tracks()
	var enabled := tracks.filter(func(t): return GameState.music_playlist.has(t["id"]))
	var disabled := tracks.filter(func(t): return not GameState.music_playlist.has(t["id"]))
	_enabled_title.text = "Playlist (%d)" % enabled.size()
	_disabled_title.text = "Disabled (%d)" % disabled.size()
	if enabled.is_empty():
		_enabled_list.add_child(_list_note("Empty: matches will play Through Space."))
	for t in enabled:
		_enabled_list.add_child(_track_row(t, true))
	if disabled.is_empty():
		_disabled_list.add_child(_list_note("No disabled songs."))
	for t in disabled:
		_disabled_list.add_child(_track_row(t, false))

func _list_note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.6, 0.63, 0.75))
	return l

## One song: its name (teal if enabled, orange if disabled) with Preview/Stop
## and Disable or Enable underneath.
func _track_row(t: Dictionary, enabled: bool) -> VBoxContainer:
	var id: String = t["id"]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var name := Label.new()
	name.text = t["name"]
	name.tooltip_text = t["name"]
	name.mouse_filter = Control.MOUSE_FILTER_PASS
	name.clip_text = true
	name.add_theme_color_override("font_color", ENABLED_COLOR if enabled else DISABLED_COLOR)
	box.add_child(name)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var play := Button.new()
	play.text = "Stop" if Music.previewing == id else "Preview"
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.pressed.connect(func():
		if Music.previewing == id:
			Music.stop_preview()
		else:
			Music.preview(id)
		_refresh_tracks())
	row.add_child(play)
	var toggle := Button.new()
	toggle.text = "Disable" if enabled else "Enable"
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.pressed.connect(func():
		Music.set_in_playlist(id, not enabled)
		_track_status.text = ("Disabled %s." if enabled else "Enabled %s.") % t["name"]
		_refresh_tracks())
	row.add_child(toggle)
	return box

func _on_songs_selected(paths: PackedStringArray) -> void:
	var added := 0
	var failed := 0
	for p in paths:
		if Music.import_file(p) != "":
			added += 1
		else:
			failed += 1
	_track_status.text = "Added %d song%s%s." % [added, "" if added == 1 else "s", (", %d couldn't be read" % failed) if failed > 0 else ""]

# ---------------------------------------------------------------- other tabs

const KEY_COLOR := Color("ffd166")

## A full-tab row of panel columns, laid out like the Audio tab.
func _tab_columns(tab: Control) -> HBoxContainer:
	var cols := HBoxContainer.new()
	cols.set_anchors_preset(Control.PRESET_FULL_RECT)
	cols.offset_left = 10
	cols.offset_top = 10
	cols.offset_right = -10
	cols.offset_bottom = -10
	cols.add_theme_constant_override("separation", 10)
	tab.add_child(cols)
	return cols

## Hotkeys tab: Star Lords' controls in three panels (action -> key).
func _build_hotkeys_tab() -> void:
	var cols := _tab_columns($Background/Panel/VBox/TabContainer/Hotkeys)
	var groups := [
		["Mouse", Color("7fb2ff"), [
			["Select", "Left click"], ["Box select", "Left drag"],
			["Select all of a class on screen", "Double-click"],
			["Move / attack / mine / colonize", "Right click"],
			["Attack-move", "Ctrl + Right click"],
			["Pan camera", "Middle drag / WASD / edges"], ["Zoom", "Mouse wheel"]]],
		["Orders & Selection", ENABLED_COLOR, [
			["Stop", "T"], ["Select warships", "Tab"], ["Camera to home", "H"],
			["Research", "R"], ["Found starbase (Constructor)", "F"],
			["Set control group", "Ctrl + 1-9"],
			["Select control group", "1-9"], ["Centre on group", "1-9 twice"]]],
		["Game & Build", DISABLED_COLOR, [
			["Pause / play", "Space"], ["Slower / faster", "- / ="],
			["Normal speed", "Backspace"], ["Menu", "Esc"],
			["Mining Barge", "Z"], ["Gas Skimmer", "M"], ["Colony Ship", "X"],
			["Constructor", "C"], ["Corvette", "V"], ["Destroyer", "B"], ["Cruiser", "N"]]],
	]
	for g in groups:
		var col := _column(cols, g[0], g[1], 1.0)
		var list := _scroll_list(col)
		for row in g[2]:
			var h := HBoxContainer.new()
			var action := Label.new()
			action.text = row[0]
			action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var key := Label.new()
			key.text = row[1]
			key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			key.add_theme_color_override("font_color", KEY_COLOR)
			h.add_child(action)
			h.add_child(key)
			list.add_child(h)

## Visuals tab: the scene's controls moved into Display / Interface panels.
func _build_visuals_tab() -> void:
	var tab: Control = $Background/Panel/VBox/TabContainer/Visuals
	var cols := _tab_columns(tab)
	for pair in [["Display", "ShowGridCheckBox"], ["Interface", "FontRow"]]:
		var col := _column(cols, pair[0], Color.WHITE, 1.0)
		var n: Control = tab.get_node(pair[1])
		tab.remove_child(n)
		col.add_child(n)
