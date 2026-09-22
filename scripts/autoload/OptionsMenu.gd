extends CanvasLayer
## Autoload -- the one Options menu shared by TitleMenu, Lobby, and Main
## (see each screen's Options button). Being an autoload rather than a
## scene instanced separately in all three means there's genuinely only
## one of these, matching "they all go to the same menu" -- not three
## copies that happen to look alike.

## Actions (from project.godot's InputMap) worth showing on the Hotkeys
## tab, paired with a human label -- deliberately not every InputMap
## action (e.g. UI-navigation ones aren't interesting here).
const LISTED_ACTIONS: Array = [
	["select", "Select / Drag-Select"],
	["command", "Move / Attack / Task Order"],
	["cam_up", "Pan Camera Up"],
	["cam_down", "Pan Camera Down"],
	["cam_left", "Pan Camera Left"],
	["cam_right", "Pan Camera Right"],
	["cam_zoom_in", "Zoom In"],
	["cam_zoom_out", "Zoom Out"],
]
## Hotkeys hardcoded in scripts rather than routed through the InputMap
## (see RTSController._unhandled_input / MainMenu._unhandled_input), so
## they're not discoverable via InputMap.action_get_events -- listed here
## by hand instead.
const HARDCODED_HOTKEYS: Array = [
	["H", "Halt Selected Units"],
	["Shift (hold)", "Queue Order / Add to Selection"],
	["F5", "Pause / Resume"],
]

@onready var background: Control = $Background
@onready var panel: Panel = $Background/Panel
@onready var close_button: Button = $Background/Panel/VBox/CloseButtonRow/CloseButton
@onready var master_slider: HSlider = $Background/Panel/VBox/TabContainer/Audio/MasterVolumeRow/MasterSlider
@onready var music_slider: HSlider = $Background/Panel/VBox/TabContainer/Audio/MusicVolumeRow/MusicSlider
@onready var audio_enabled_checkbox: CheckBox = $Background/Panel/VBox/TabContainer/Audio/ToggleRow/AudioEnabledCheckBox
@onready var music_enabled_checkbox: CheckBox = $Background/Panel/VBox/TabContainer/Audio/ToggleRow/MusicEnabledCheckBox
@onready var hotkeys_list: GridContainer = $Background/Panel/VBox/TabContainer/Hotkeys/HotkeysList
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

	close_button.pressed.connect(close)
	master_slider.value_changed.connect(_on_master_slider_changed)
	music_slider.value_changed.connect(_on_music_slider_changed)
	audio_enabled_checkbox.toggled.connect(_on_audio_enabled_toggled)
	music_enabled_checkbox.toggled.connect(_on_music_enabled_toggled)
	show_grid_checkbox.toggled.connect(_on_show_grid_toggled)
	_populate_font_options()
	font_option.item_selected.connect(_on_font_selected)
	_populate_hotkeys()

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
	Music.player.volume_db = GameState.music_volume_db
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
	background.visible = true

func close() -> void:
	background.visible = false

func _on_master_slider_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(_master_bus_index, value)
	GameState.master_volume_db = value
	GameState.save_settings()

func _on_music_slider_changed(value: float) -> void:
	Music.player.volume_db = value
	GameState.music_volume_db = value
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

func _populate_hotkeys() -> void:
	for pair in LISTED_ACTIONS:
		var action: String = pair[0]
		var label_text: String = pair[1]
		var events := InputMap.action_get_events(action)
		var key_text := events[0].as_text() if not events.is_empty() else "(unbound)"
		_add_hotkey_row(label_text, key_text)
	for pair in HARDCODED_HOTKEYS:
		_add_hotkey_row(pair[1], pair[0])

## Adds one row to the Hotkeys GridContainer -- two cells (action, key),
## since GridContainer lays out its direct children in row-major order
## rather than taking pre-built row nodes.
func _add_hotkey_row(label_text: String, key_text: String) -> void:
	var action_label := Label.new()
	action_label.text = label_text
	action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var key_label := Label.new()
	key_label.text = key_text
	key_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2, 1))
	hotkeys_list.add_child(action_label)
	hotkeys_list.add_child(key_label)
