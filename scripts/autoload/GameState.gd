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

## Local user accounts (see TitleMenu's Account/NewAccount/SignIn panels) --
## one dict per account: {"name": String, "password_hash": String}. This is
## a purely local, single-player profile switcher, not real authentication
## against any server, so the "password" is just a locally-checked
## SHA-256 hash (see TitleMenu._hash_password) rather than anything sent
## anywhere -- enough to stop someone else picking your name, not meant to
## be actual account security. Capped at MAX_ACCOUNTS the same way the
## lobby caps player slots at 8: a fixed, small limit rather than an
## unbounded list.
const MAX_ACCOUNTS: int = 5
var accounts: Array = []
## Which account is currently signed in for this session, or "" for none.
## Cleared on every fresh launch unless stay_signed_in restores it (see
## load_settings()) -- signing in is a per-session thing by default, the
## same as the Steam/Windows-account pattern "stay signed in" is modeled
## after.
var active_account: String = ""
## Whether to auto-restore `remembered_account` as active_account on the
## next launch -- set from the Sign In / Create Account panels' "Stay
## signed in" checkbox.
var stay_signed_in: bool = false
## Which account to auto-sign-in as on launch when stay_signed_in is true.
## Kept separate from active_account so signing out mid-session doesn't
## silently change what a future "stay signed in" launch would restore.
var remembered_account: String = ""

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
## Independent on/off switches, separate from the volume sliders above --
## OptionsMenu's Audio tab checkboxes (see _apply_audio_enabled/
## _apply_music_enabled) mute the Master bus / pause Music.player rather
## than touching these dB values, so turning audio back on restores
## whatever volume was set before, instead of forgetting it.
var audio_enabled: bool = true
var music_enabled: bool = true

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
	config.set_value("audio", "audio_enabled", audio_enabled)
	config.set_value("audio", "music_enabled", music_enabled)
	config.set_value("visuals", "show_debug_grid", show_debug_grid)
	config.set_value("visuals", "ui_font", ui_font)
	config.set_value("lobby", "starting_unit_count", starting_unit_count)
	config.set_value("lobby", "human_player_id", human_player_id)
	config.set_value("lobby", "player_slots", player_slots)
	config.set_value("accounts", "list", accounts)
	config.set_value("accounts", "stay_signed_in", stay_signed_in)
	config.set_value("accounts", "remembered_account", remembered_account)
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
	audio_enabled = config.get_value("audio", "audio_enabled", audio_enabled)
	music_enabled = config.get_value("audio", "music_enabled", music_enabled)
	show_debug_grid = config.get_value("visuals", "show_debug_grid", show_debug_grid)
	ui_font = config.get_value("visuals", "ui_font", ui_font)
	starting_unit_count = config.get_value("lobby", "starting_unit_count", starting_unit_count)
	human_player_id = config.get_value("lobby", "human_player_id", human_player_id)
	player_slots = config.get_value("lobby", "player_slots", player_slots)
	accounts = config.get_value("accounts", "list", accounts)
	stay_signed_in = config.get_value("accounts", "stay_signed_in", stay_signed_in)
	remembered_account = config.get_value("accounts", "remembered_account", remembered_account)
	## Auto-restore whoever "Stay signed in" remembered, same as a browser
	## or Steam staying logged in across a restart -- active_account is
	## otherwise session-only (see its own doc comment), so without this a
	## stay-signed-in player would still have to re-enter their password
	## every single launch, defeating the point of the checkbox.
	if stay_signed_in and not remembered_account.is_empty():
		for account in accounts:
			if account["name"] == remembered_account:
				active_account = remembered_account
				break
