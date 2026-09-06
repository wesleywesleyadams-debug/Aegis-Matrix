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
@onready var hotkeys_list: GridContainer = $Background/Panel/VBox/TabContainer/Hotkeys/HotkeysList
@onready var show_grid_checkbox: CheckBox = $Background/Panel/VBox/TabContainer/Visuals/ShowGridCheckBox

var _master_bus_index: int = 0

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	background.visible = false

	_master_bus_index = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(_master_bus_index, GameState.master_volume_db)

	close_button.pressed.connect(close)
	master_slider.value = GameState.master_volume_db
	master_slider.value_changed.connect(_on_master_slider_changed)
	music_slider.value = GameState.music_volume_db
	music_slider.value_changed.connect(_on_music_slider_changed)

	show_grid_checkbox.button_pressed = GameState.show_debug_grid
	show_grid_checkbox.toggled.connect(_on_show_grid_toggled)

	_populate_hotkeys()

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

## Persists the setting (see GameState.show_debug_grid) and, if the current
## scene actually has a debug grid to show/hide (only true in Main -- the
## title screen and lobby don't have one), updates it live too instead of
## only taking effect the next time Main loads.
func _on_show_grid_toggled(pressed: bool) -> void:
	GameState.show_debug_grid = pressed
	GameState.save_settings()
	var scene := get_tree().current_scene
	if scene != null and scene.has_node("DebugGrid"):
		scene.get_node("DebugGrid").visible = pressed

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
