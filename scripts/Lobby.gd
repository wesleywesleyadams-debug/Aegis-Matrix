extends Control
## Pre-match setup screen. Race/Item/Map/AI are single-option placeholders
## for now -- this prototype only has one race's worth of units, one map,
## and no item or AI systems yet -- but they're wired up as real
## OptionButtons so adding more options later is just adding entries, not
## restructuring the screen. Starting Units and Play As are the controls
## that actually change anything about the match right now.

const MAX_STARTING_UNITS: int = 8
## Faded look for the not-currently-chosen Play As button, so its team
## color reads as "available" rather than "active" -- the active one stays
## at full opacity.
const UNSELECTED_MODULATE := Color(1, 1, 1, 0.45)

@onready var starting_units_spinbox: SpinBox = $VBox/StartingUnitsRow/SpinBox
@onready var player1_button: Button = $VBox/PlayersRow/Player1Button
@onready var player2_button: Button = $VBox/PlayersRow/Player2Button
@onready var start_button: Button = $VBox/ButtonRow/StartButton
@onready var back_button: Button = $VBox/ButtonRow/BackButton
@onready var options_button: Button = $VBox/OptionsButton

## Starts from whatever was last saved (see GameState.save_settings())
## rather than always defaulting to Player 1, so a chosen "Play As" side
## survives quitting and relaunching the game.
var _human_player_id: int = GameState.human_player_id

func _ready() -> void:
	Music.play_track(Music.LOBBY_TRACK)
	starting_units_spinbox.min_value = 1
	starting_units_spinbox.max_value = MAX_STARTING_UNITS
	starting_units_spinbox.value = GameState.starting_unit_count

	starting_units_spinbox.value_changed.connect(_on_starting_units_changed)
	player1_button.pressed.connect(_on_player1_pressed)
	player2_button.pressed.connect(_on_player2_pressed)
	options_button.pressed.connect(OptionsMenu.open)
	_update_play_as_visuals()

	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)

## Every lobby control saves immediately on change (not just when Start is
## pressed) so whatever was last set is still there even if the player
## quits straight from the lobby instead of actually starting a match.
func _on_starting_units_changed(value: float) -> void:
	GameState.starting_unit_count = int(value)
	GameState.save_settings()

func _on_player1_pressed() -> void:
	_human_player_id = 1
	GameState.human_player_id = 1
	GameState.save_settings()
	_update_play_as_visuals()

func _on_player2_pressed() -> void:
	_human_player_id = 2
	GameState.human_player_id = 2
	GameState.save_settings()
	_update_play_as_visuals()

## Keeps the two Play As buttons acting like a single toggle (exactly one
## pressed) and fades whichever isn't currently chosen, so the chosen
## button's team-colored text reads as the active pick.
func _update_play_as_visuals() -> void:
	player1_button.button_pressed = _human_player_id == 1
	player2_button.button_pressed = _human_player_id == 2
	player1_button.modulate = Color.WHITE if _human_player_id == 1 else UNSELECTED_MODULATE
	player2_button.modulate = Color.WHITE if _human_player_id == 2 else UNSELECTED_MODULATE

func _on_start_pressed() -> void:
	GameState.starting_unit_count = int(starting_units_spinbox.value)
	GameState.human_player_id = _human_player_id
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/TitleMenu.tscn")
