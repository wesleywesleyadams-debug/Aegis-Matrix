extends Control
## Pre-match setup screen. Two panels: Players (left) lists up to
## MAX_PLAYER_SLOTS pre-match slots, each with a slot-type/race/team choice
## (see GameState.player_slots); Match Settings (right) holds the
## match-wide options (Starting Item/Map/Starting Units are single-option
## placeholders for now, same "wired up as real OptionButtons so adding
## more options later is just adding entries" status the old Race/AI
## Opponents fields had).
##
## Only slot 1 (the player) and slot 2 (the one opposing side the match
## actually spawns -- see RTSController._assign_players) do anything right
## now; slots 3-8's race/team/AI choices are captured here for a future
## multi-opponent/team-combat system that doesn't exist yet, same as
## Starting Item/Map already were placeholders.

const RACE_OPTIONS: Array = [["human", "Human"], ["elf", "Elf"], ["orc", "Orc"], ["undead", "Undead"]]
## Index i's team value; "No Team" is stored as team 0.
const TEAM_OPTIONS: Array = [["1", 1], ["2", 2], ["3", 3], ["4", 4], ["No Team", 0]]
## Purely a visual accent for each slot's player-number badge -- distinct
## from Entity.PLAYER_COLORS (which only defines real gameplay colors for
## players 1/2, plus the fixed Nature/Mob neutral factions) since slots
## 3-8 here don't correspond to any actual in-match faction yet.
const BADGE_COLORS: Array = [
	Color(0.2, 0.45, 0.9), Color(0.85, 0.2, 0.2), Color(0.2, 0.7, 0.3), Color(0.85, 0.75, 0.2),
	Color(0.6, 0.35, 0.8), Color(0.9, 0.55, 0.15), Color(0.3, 0.75, 0.75), Color(0.8, 0.4, 0.65),
]
## Dimmed badge color for a slot currently set to Open -- same "available,
## not active" language as the old Play As buttons' UNSELECTED_MODULATE.
const OPEN_BADGE_COLOR := Color(0.5, 0.45, 0.4)

const MAX_STARTING_UNITS: int = 8

@onready var players_grid: GridContainer = $MainHBox/PlayersPanel/PlayersVBox/PlayersGrid
@onready var starting_units_spinbox: SpinBox = $MainHBox/SettingsPanel/SettingsVBox/StartingUnitsRow/SpinBox
@onready var start_button: Button = $MainHBox/SettingsPanel/SettingsVBox/ButtonRow/StartButton
@onready var back_button: Button = $MainHBox/SettingsPanel/SettingsVBox/ButtonRow/BackButton
@onready var options_button: Button = $MainHBox/SettingsPanel/SettingsVBox/OptionsButton

## The local player's OS username, shown as the slot-dropdown option for
## "this slot is me" -- falls back to "Player" if the OS doesn't report one
## (e.g. some non-Windows/Linux environments).
var _username: String = ""

## One entry per slot: {"badge": Label, "slot": OptionButton, "race":
## OptionButton, "team": OptionButton}, in slot order -- built by
## _populate_players_grid(), read back by _on_slot_selected/_save_slot.
var _slot_rows: Array = []

func _ready() -> void:
	Music.play_track(Music.LOBBY_TRACK)
	_username = OS.get_environment("USERNAME")
	if _username.is_empty():
		_username = OS.get_environment("USER")
	if _username.is_empty():
		_username = "Player"

	starting_units_spinbox.min_value = 1
	starting_units_spinbox.max_value = MAX_STARTING_UNITS
	starting_units_spinbox.value = GameState.starting_unit_count
	starting_units_spinbox.value_changed.connect(_on_starting_units_changed)

	options_button.pressed.connect(OptionsMenu.open)
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)

	_populate_players_grid()

## Every lobby control saves immediately on change (not just when Start is
## pressed) so whatever was last set is still there even if the player
## quits straight from the lobby instead of actually starting a match.
func _on_starting_units_changed(value: float) -> void:
	GameState.starting_unit_count = int(value)
	GameState.save_settings()

## Builds one row per slot in GameState.player_slots, below the header row
## already in the scene -- GridContainer lays out direct children in
## row-major order, so this just keeps appending cells.
func _populate_players_grid() -> void:
	for i in GameState.player_slots.size():
		var slot: Dictionary = GameState.player_slots[i]

		var badge := Label.new()
		badge.text = str(i + 1)
		badge.custom_minimum_size = Vector2(50, 0)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_color_override("font_color", BADGE_COLORS[i % BADGE_COLORS.size()])
		players_grid.add_child(badge)

		var slot_option := OptionButton.new()
		slot_option.custom_minimum_size = Vector2(210, 0)
		slot_option.add_item(_username)
		slot_option.add_item("AI")
		slot_option.add_item("Open")
		slot_option.selected = _slot_type_index(slot["slot_type"])
		players_grid.add_child(slot_option)

		var race_option := OptionButton.new()
		race_option.custom_minimum_size = Vector2(140, 0)
		for pair in RACE_OPTIONS:
			race_option.add_item(pair[1])
		race_option.selected = _race_index(slot["race"])
		players_grid.add_child(race_option)

		var team_option := OptionButton.new()
		team_option.custom_minimum_size = Vector2(90, 0)
		for pair in TEAM_OPTIONS:
			team_option.add_item(pair[0])
		team_option.selected = _team_index(slot["team"])
		players_grid.add_child(team_option)

		var row := {"badge": badge, "slot": slot_option, "race": race_option, "team": team_option}
		_slot_rows.append(row)
		_update_row_visuals(i)

		slot_option.item_selected.connect(_on_slot_selected.bind(i))
		race_option.item_selected.connect(_on_race_selected.bind(i))
		team_option.item_selected.connect(_on_team_selected.bind(i))

func _slot_type_index(slot_type: String) -> int:
	match slot_type:
		"human": return 0
		"ai": return 1
		_: return 2

func _race_index(race: String) -> int:
	for i in RACE_OPTIONS.size():
		if RACE_OPTIONS[i][0] == race:
			return i
	return 0

func _team_index(team: int) -> int:
	for i in TEAM_OPTIONS.size():
		if TEAM_OPTIONS[i][1] == team:
			return i
	return TEAM_OPTIONS.size() - 1

func _on_slot_selected(index: int, slot_index: int) -> void:
	var slot_type: String = ["human", "ai", "open"][index]
	GameState.player_slots[slot_index]["slot_type"] = slot_type
	_sync_human_player_id()
	_update_row_visuals(slot_index)
	GameState.save_settings()

func _on_race_selected(index: int, slot_index: int) -> void:
	GameState.player_slots[slot_index]["race"] = RACE_OPTIONS[index][0]
	GameState.save_settings()

func _on_team_selected(index: int, slot_index: int) -> void:
	GameState.player_slots[slot_index]["team"] = TEAM_OPTIONS[index][1]
	GameState.save_settings()

## Dims (rather than hides -- GridContainer drops invisible children from
## the grid flow entirely, which would shift every following row's cells
## left by one column) a slot's race/team dropdowns and badge once it's set
## to Open, since there's nothing meaningful to configure for an empty slot.
func _update_row_visuals(slot_index: int) -> void:
	var row: Dictionary = _slot_rows[slot_index]
	var is_open: bool = GameState.player_slots[slot_index]["slot_type"] == "open"
	row["race"].disabled = is_open
	row["race"].modulate.a = 0.4 if is_open else 1.0
	row["team"].disabled = is_open
	row["team"].modulate.a = 0.4 if is_open else 1.0
	row["badge"].add_theme_color_override(
		"font_color", OPEN_BADGE_COLOR if is_open else BADGE_COLORS[slot_index % BADGE_COLORS.size()]
	)

## RTSController/Entity only know about a single human_player_id (1 or 2)
## -- the two sides an actual match spawns (see
## RTSController._assign_players) -- not the full 8-slot setup. Mirror
## whichever of *those two* slots is "human" into it so match-start keeps
## working exactly as before; slots 3-8 have no matching in-match faction
## to control yet, so a "human" pick there is captured but doesn't change
## who you actually play as.
func _sync_human_player_id() -> void:
	for i in range(mini(2, GameState.player_slots.size())):
		if GameState.player_slots[i]["slot_type"] == "human":
			GameState.human_player_id = i + 1
			return

func _on_start_pressed() -> void:
	GameState.starting_unit_count = int(starting_units_spinbox.value)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/TitleMenu.tscn")
