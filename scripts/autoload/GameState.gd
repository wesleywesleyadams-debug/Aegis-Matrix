extends Node
## Autoload -- carries "load this save" across the TitleMenu -> Main scene
## change, since change_scene_to_file() gives the new scene no way to
## receive an argument directly.

var load_on_start: bool = false
## Which save file to load, e.g. "user://saves/save_1234567890.json".
## Only meaningful when load_on_start is true.
var load_save_path: String = ""

## Lobby selection carried into a freshly started (non-loaded) match.
## Race/item/map/AI have only one option each right now, so only this
## actually changes anything about the match Main.tscn starts with.
var starting_unit_count: int = 8

## Player 3 -- "Nature" (see Entity.PLAYER_NAMES) -- is a neutral,
## world-owned faction, not a playable one. There's simply no lobby control
## that offers it as a Play As choice (only Player 1/Player 2 exist).
const NATURE_PLAYER_ID: int = 3
## Player 4 -- "Mob" (see Entity.PLAYER_NAMES) -- same deal as Nature: a
## non-playable faction with no lobby control offering it.
const MOB_PLAYER_ID: int = 4

## Which player the human controls -- 1 or 2. RTSController checks this
## instead of hardcoding "player 1" for what can be selected/ordered. Kept
## in sync with player_slots (see below) by Lobby -- whichever slot is set
## to "human" there is mirrored into this, since RTSController/Entity's
## actual match logic only knows about a single human-controlled player id,
## not the full per-slot lobby setup.
var human_player_id: int = 1

## Up to 8 pre-match player slots (see Lobby.gd's Players panel), one dict
## per slot: {"slot_type": "human"/"ai"/"open", "race": String, "team": int
## (1-4, or 0 for "No Team")}. Purely lobby-captured intent right now --
## there's no AI opponent, race-differentiated units, or team-alliance
## combat system yet for anything beyond the single human player (slot 1 by
## default) and the one enemy side the match actually spawns (see
## RTSController._assign_players), the same "wired up for real, not
## implemented yet" placeholder status the old Race/AI Opponents fields had.
const MAX_PLAYER_SLOTS: int = 8
var player_slots: Array = _default_player_slots()

static func _default_player_slots() -> Array:
	var slots: Array = []
	for i in MAX_PLAYER_SLOTS:
		var slot_type := "human" if i == 0 else ("ai" if i == 1 else "open")
		slots.append({"slot_type": slot_type, "race": "human", "team": 0})
	return slots

## Persists across matches/scenes -- OptionsMenu's Visuals tab checkbox and
## RTSController's debug_grid (both the 'G' hotkey and its own _ready()
## initial state) read/write this so the setting sticks between games
## rather than always resetting to visible.
var show_debug_grid: bool = true

## Which UI font is applied to the shared theme (see OptionsMenu._apply_font)
## -- one of OptionsMenu.FONT_OPTIONS' keys.
var ui_font: String = "medieval"

## Audio settings -- authoritative values OptionsMenu's sliders and Music.gd
## read at startup and write back on every change (see save_settings()
## callers). Kept here rather than read directly off AudioServer/the music
## player so there's one obvious place holding "what the user chose",
## independent of whichever bus/player object happens to represent it.
var master_volume_db: float = 0.0
var music_volume_db: float = -8.0

## Where user-chosen settings (this whole section, above) survive to disk --
## everything here is meant to still be true the next time the game is
## launched, not just the next time a scene loads within one run.
const SETTINGS_PATH: String = "user://settings.cfg"

func _ready() -> void:
	load_settings()

## Writes every persisted setting to disk immediately. Called right after
## each individual setting changes (a slider drag, a lobby selection, ...)
## rather than once at some "on quit" hook, so it survives a force-quit or
## crash the same as a clean exit -- there's no window where a change is
## only in memory and not yet safe on disk.
func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume_db", master_volume_db)
	config.set_value("audio", "music_volume_db", music_volume_db)
	config.set_value("visuals", "show_debug_grid", show_debug_grid)
	config.set_value("visuals", "ui_font", ui_font)
	config.set_value("lobby", "starting_unit_count", starting_unit_count)
	config.set_value("lobby", "human_player_id", human_player_id)
	config.set_value("lobby", "player_slots", player_slots)
	config.save(SETTINGS_PATH)

## Loads whatever was saved last, leaving each var's already-declared
## default in place for anything missing (first run, or an older save
## missing a newer key).
func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	master_volume_db = config.get_value("audio", "master_volume_db", master_volume_db)
	music_volume_db = config.get_value("audio", "music_volume_db", music_volume_db)
	show_debug_grid = config.get_value("visuals", "show_debug_grid", show_debug_grid)
	ui_font = config.get_value("visuals", "ui_font", ui_font)
	starting_unit_count = config.get_value("lobby", "starting_unit_count", starting_unit_count)
	human_player_id = config.get_value("lobby", "human_player_id", human_player_id)
	player_slots = config.get_value("lobby", "player_slots", player_slots)
