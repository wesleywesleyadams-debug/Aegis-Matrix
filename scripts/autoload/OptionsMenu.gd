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

	if _shuffle_checkbox:
		_shuffle_checkbox.set_pressed_no_signal(GameState.music_shuffle)
		_shuffle_checkbox.get_child(0).queue_redraw()
		_update_shuffle_label()
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
const SCREEN_ON_COLOR := Color("6aff8a")   # green: title/lobby song, enabled
const SCREEN_OFF_COLOR := Color("ffe14d")  # yellow: title/lobby song, disabled

var _enabled_list: VBoxContainer
var _disabled_list: VBoxContainer
var _enabled_title: Label
var _disabled_title: Label
var _track_status: Label
var _file_dialog: FileDialog
var _shuffle_checkbox: Button
var _shuffle_label: Label

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
	hint.text = "These play during matches in this order (random with Shuffle). Title and Lobby synths (green) only play on their own screens."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pl.add_child(hint)
	# Shuffle toggle: an icon button to the right of the "Playlist" heading.
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 12)
	pl.add_child(head)
	pl.move_child(head, 0)
	pl.remove_child(_enabled_title)
	head.add_child(_enabled_title)
	_shuffle_checkbox = _shuffle_button()
	head.add_child(_shuffle_checkbox)
	_shuffle_label = Label.new()
	_shuffle_label.add_theme_font_size_override("font_size", 12)
	head.add_child(_shuffle_label)
	_update_shuffle_label()
	_shuffle_checkbox.toggled.connect(func(_on): _update_shuffle_label())
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
	# Enabled songs in the order they were enabled (newest at the bottom),
	# which is also the order they play in.
	var enabled: Array = []
	for id in GameState.music_playlist:
		for t in tracks:
			if t["id"] == id:
				enabled.append(t)
	var disabled := tracks.filter(func(t): return not GameState.music_playlist.has(t["id"]))
	_enabled_title.text = "Playlist (%d)" % enabled.size()
	_disabled_title.text = "Disabled (%d)" % disabled.size()
	if enabled.is_empty():
		_enabled_list.add_child(_list_note("Empty: no music will play."))
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

## One song on one line: its name (teal if enabled, orange if disabled), then
## small Preview/Stop and Disable/Enable buttons.
func _track_row(t: Dictionary, enabled: bool) -> HBoxContainer:
	var id: String = t["id"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name := Label.new()
	name.text = t["name"]
	name.tooltip_text = t["name"]
	name.mouse_filter = Control.MOUSE_FILTER_PASS
	name.clip_text = true
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The title/lobby screen songs stand out: green when enabled, yellow when not.
	var screen := id in [Music.TITLE_TRACK, Music.LOBBY_TRACK]
	var color := (SCREEN_ON_COLOR if enabled else SCREEN_OFF_COLOR) if screen else (ENABLED_COLOR if enabled else DISABLED_COLOR)
	name.add_theme_color_override("font_color", color)
	row.add_child(name)
	var play := _small_button("Stop" if Music.previewing == id else "Play")
	play.pressed.connect(func():
		if Music.previewing == id:
			Music.stop_preview()
		else:
			Music.preview(id)
		_refresh_tracks())
	row.add_child(play)
	var toggle := _small_button("Disable" if enabled else "Enable")
	toggle.pressed.connect(func():
		Music.set_in_playlist(id, not enabled)
		_track_status.text = ("Disabled %s." if enabled else "Enabled %s.") % t["name"]
		_refresh_tracks())
	row.add_child(toggle)
	return row

func _small_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(84, 0)
	b.add_theme_font_size_override("font_size", 13)
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBox = b.get_theme_stylebox(st).duplicate()
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		b.add_theme_stylebox_override(st, sb)
	return b

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

## Hotkeys tab: the fixed mouse controls, and every rebindable key (see
## Defs.HOTKEYS) as a button — click it, press the new key. Esc cancels,
## Backspace-on-a-row is just another key, and taking a key from another
## action clears that one. "Reset to defaults" puts them all back.
var _rebinding: String = ""
var _rebind_button: Button
var _hotkey_buttons := {}

func _build_hotkeys_tab() -> void:
	var cols := _tab_columns($Background/Panel/VBox/TabContainer/Hotkeys)
	_hotkey_buttons.clear()

	var mouse := _column(cols, "Mouse & camera", Color("7fb2ff"), 1.0)
	var mlist := _scroll_list(mouse)
	for row in [["Select", "Left click"], ["Box select", "Left drag"],
			["Select all of a class on screen", "Double-click"],
			["Move / attack / mine / colonize / refit", "Right click"],
			["Attack-move", "Ctrl + Right click"],
			["Pan camera", "Arrows / screen edge / middle drag"],
			["Zoom", "Mouse wheel"],
			["Set control group", "Ctrl + 1-9"],
			["Select control group", "1-9"],
			["Centre on group", "1-9 twice"],
			["Menu / cancel", "Esc"]]:
		var h := HBoxContainer.new()
		var a := Label.new()
		a.text = row[0]
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var kk := Label.new()
		kk.text = row[1]
		kk.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		kk.add_theme_color_override("font_color", KEY_COLOR)
		h.add_child(a)
		h.add_child(kk)
		mlist.add_child(h)

	var panel := _column(cols, "Panel grid", ENABLED_COLOR, 1.0)
	var plist := _scroll_list(panel)
	plist.add_child(_hint("The bottom-left panel's buttons, in order: the letter is drawn on each button. With no starbase selected, these same keys select every ship of that class."))
	for i in 12:
		plist.add_child(_hotkey_row("panel%d" % (i + 1), "Panel button %d" % (i + 1)))

	var game_col := _column(cols, "Orders & game", DISABLED_COLOR, 1.0)
	var glist := _scroll_list(game_col)
	for h in Defs.HOTKEYS:
		if not String(h[0]).begins_with("panel"):
			glist.add_child(_hotkey_row(h[0], h[1]))
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(func():
		GameState.hotkeys = {}
		GameState.save_settings()
		_refresh_hotkey_buttons())
	glist.add_child(reset)

func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.6, 0.63, 0.75))
	return l

## One rebindable row: action name, and a button showing its key.
func _hotkey_row(id: String, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var a := Label.new()
	a.text = label
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.add_theme_font_size_override("font_size", 14)
	h.add_child(a)
	var b := Button.new()
	b.custom_minimum_size = Vector2(104, 28)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", KEY_COLOR)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): _start_rebind(id, b))
	h.add_child(b)
	_hotkey_buttons[id] = b
	_set_hotkey_button(id)
	return h

func _set_hotkey_button(id: String) -> void:
	var b: Button = _hotkey_buttons.get(id)
	if b:
		b.text = OS.get_keycode_string(Defs.key_for(id))

func _refresh_hotkey_buttons() -> void:
	for id in _hotkey_buttons:
		_set_hotkey_button(id)

func _start_rebind(id: String, b: Button) -> void:
	if _rebinding != "":
		_set_hotkey_button(_rebinding)
	_rebinding = id
	_rebind_button = b
	b.text = "press a key"

## While waiting for a new binding, the next key press takes it (Esc cancels).
func _input(event: InputEvent) -> void:
	if _rebinding == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var id := _rebinding
	_rebinding = ""
	if event.keycode == KEY_ESCAPE:
		_set_hotkey_button(id)
		return
	var keys: Dictionary = GameState.hotkeys.duplicate()
	if keys.is_empty():
		keys = Defs.default_hotkeys()
	# One key, one action: whoever had it loses it.
	for other in keys.keys():
		if other != id and int(keys[other]) == int(event.keycode):
			keys[other] = KEY_NONE
	keys[id] = event.keycode
	GameState.hotkeys = keys
	GameState.save_settings()
	_refresh_hotkey_buttons()

func _build_visuals_tab() -> void:
	var tab: Control = $Background/Panel/VBox/TabContainer/Visuals
	var cols := _tab_columns(tab)
	for pair in [["Display", "ShowGridCheckBox"], ["Interface", "FontRow"]]:
		var col := _column(cols, pair[0], Color.WHITE, 1.0)
		var n: Control = tab.get_node(pair[1])
		tab.remove_child(n)
		col.add_child(n)

## A toggle button showing the shuffle icon (two crossing arrows), lit teal
## when shuffle is on.
func _shuffle_button() -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = GameState.music_shuffle
	b.tooltip_text = "Shuffle: play songs in random order"
	b.custom_minimum_size = Vector2(38, 30)
	var icon := Control.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	icon.draw.connect(func():
		var c := ENABLED_COLOR if b.button_pressed else Color(0.55, 0.58, 0.7)
		var o := (icon.size - Vector2(24, 16)) / 2.0
		var w := 2.0
		# Two paths that cross in the middle, each ending in an arrowhead.
		for pts in [[Vector2(0, 2), Vector2(7, 2), Vector2(15, 14), Vector2(22, 14)],
				[Vector2(0, 14), Vector2(7, 14), Vector2(15, 2), Vector2(22, 2)]]:
			var p := PackedVector2Array()
			for v in pts:
				p.append(o + v)
			icon.draw_polyline(p, c, w)
			var tip: Vector2 = o + pts[3] + Vector2(2, 0)
			icon.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-6, -4), tip + Vector2(-6, 4)]), c))
	b.toggled.connect(func(on):
		GameState.music_shuffle = on
		GameState.save_settings()
		icon.queue_redraw())
	return b

func _update_shuffle_label() -> void:
	var on := GameState.music_shuffle
	_shuffle_label.text = "shuffle on" if on else "shuffle off"
	_shuffle_label.add_theme_color_override("font_color", ENABLED_COLOR if on else Color(0.55, 0.58, 0.7))
