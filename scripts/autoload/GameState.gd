extends Node
## Autoload -- carries "load this save" across the TitleMenu -> Main scene
## change, since change_scene_to_file() gives the new scene no way to
## receive an argument directly.

## Fired whenever active_account changes -- SignedInLabel (shown top-right
## on every scene) listens for this instead of polling every frame.
signal active_account_changed

var load_on_start: bool = false
## Set by the title screen while it builds its background match (see
## Game.demo_mode); cleared as soon as that match exists.
var demo_mode: bool = false
## Which save file to load, e.g. "user://saves/save_1234567890.json".
## Only meaningful when load_on_start is true.
var load_save_path: String = ""
## Display name of that save (shown in the lobby when resuming).
var load_save_name: String = ""

## Same "carry an argument across change_scene_to_file" pattern as
## load_on_start/load_save_path above, but for a map-editor-authored
## custom map (see scripts/MapEditorController.gd) being loaded into
## Main.tscn for a real playtest rather than a mid-match save being
## resumed -- RTSController._ready() checks this separately from
## load_on_start, since a custom map replaces the whole starting
## roster/buildings rather than restoring position/health onto an
## already-existing one.
var load_map_on_start: bool = false
## Which map file to load, e.g. "user://maps/my_map.json". Only
## meaningful when load_map_on_start is true.
var load_map_path: String = ""

## Player 9 -- "Gaia" (see Entity.PLAYER_NAMES) -- is a neutral,
## world-owned faction, not a playable one. There's simply no lobby control
## that offers it as a Play As choice (only Player 1/Player 2 exist). Kept
## well past Player 1/2/Mob's own ids (unlike AoE2's own Gaia, which is
## player 0) so a real playable Player 3+ could exist someday without
## colliding with this reserved id.
const NATURE_PLAYER_ID: int = 9
## Player 4 -- "Mob" (see Entity.PLAYER_NAMES) -- same deal as Gaia: a
## non-playable faction with no lobby control offering it.
const MOB_PLAYER_ID: int = 4

## Which player the human controls -- 1 or 2. RTSController checks this
## instead of hardcoding "player 1" for what can be selected/ordered. Kept
## in sync with player_slots (see below) by Lobby -- whichever slot is set
## to "human" there is mirrored into this, since RTSController/Entity's
## actual match logic only knows about a single human-controlled player id,
## not the full per-slot lobby setup.
var human_player_id: int = 1

## Which New Game option started this match setup: "single" or "multi"
## (both use the same lobby for now; networking isn't implemented yet).
var game_mode: String = "single"
## AI opponents use the trained neural commander (res://ai/commander.json).
var neural_ai: bool = false
## Deathmatch: both sides open with Defs.START_DEATHMATCH of every resource
## instead of Defs.START, so a match is fought rather than built up to.
var deathmatch: bool = false
## Which star system the next match uses (SystemGen.SYSTEMS id) and, for
## generated ones, the seed it was built from (set when the match starts).
var system_id: String = "orion_reach"
var system_seed: int = 0

## The human player's own Paths progress -- see PathState/PathDefs' own
## doc comments for the actual mechanics. Lives here (not owned by
## PathsPanel, which only holds a reference) so gameplay code anywhere
## (Entity/Unit/Building/ResourceHUD -- see PathPerks.gd) can check
## "does the human player currently have path X" without depending on a
## UI node existing. Reset at the start of every match (see
## RTSController._ready()) so perks from a previous match never carry
## over -- an autoload persists for the whole app session, unlike
## ResourceHUD's own per-match economy dict, which is scene-owned and
## naturally starts fresh each match.


## Up to 8 pre-match player slots (see Lobby.gd's Players panel), one dict
## per slot: {"slot_type": "human"/"ai"/"neural"/"open", "race": String, "team": int
## (1-4, or 0 for "No Team")}. Purely lobby-captured intent right now --
## there's no AI opponent, race-differentiated units, or team-alliance
## combat system yet for anything beyond the single human player (slot 1 by
## default) and the one enemy side the match actually spawns (see
## RTSController._assign_players), the same "wired up for real, not
## implemented yet" placeholder status the old Race/AI Opponents fields had.
const MAX_PLAYER_SLOTS: int = 8
## The match the lobby started: one entry per filled slot, in slot order,
## {"pid": 1.., "type": "human"/"ai"/"neural", "team": 0 (none) or 1-4}.
## Empty means the classic 1-vs-1 (human 1 vs AI 2), which sims and old
## saves use.
var match_players: Array = []
var player_slots: Array = _default_player_slots()

static func _default_player_slots() -> Array:
	var slots: Array = []
	for i in MAX_PLAYER_SLOTS:
		var slot_type := "human" if i == 0 else ("ai" if i == 1 else "open")
		slots.append({"slot_type": slot_type, "race": "terran", "team": 0})
	return slots

## Local user accounts (see AccountMenu.gd) -- one dict per account:
## {"name": String, "password_hash": String, "steam_id": int (optional,
## omitted/0 for a local password account)}. A password account is purely
## local profile switching, not real authentication against any server, so
## "password_hash" is just a locally-checked SHA-256 hash (see
## AccountMenu._hash_password) rather than anything sent anywhere -- enough
## to stop someone else picking your name, not meant to be actual account
## security. A Steam-linked account (steam_id set) has no password at all --
## SteamService/the real Steam client is the authentication, see
## AccountMenu._on_steam_pressed. Capped at MAX_ACCOUNTS the same way the
## lobby caps player slots at 8: a fixed, small limit rather than an
## unbounded list.
const MAX_ACCOUNTS: int = 5
var accounts: Array = []
## Which account is currently signed in for this session, or "" for none.
## Cleared on every fresh launch unless stay_signed_in restores it (see
## load_settings()) -- signing in is a per-session thing by default, the
## same as the Steam/Windows-account pattern "stay signed in" is modeled
## after.
var active_account: String = "":
	set(value):
		if value == active_account:
			return
		active_account = value
		active_account_changed.emit()
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

## Whether every Entity's hitbox (the yellow swing-reach indicator) and
## hurtbox (the white body-hit-radius indicator) are shown -- off by
## default, since these are combat-tuning/debugging aids, not something a
## normal match should show. HitboxToggleButton (see Main.tscn's UI) flips
## this; entities listen for the change so it applies live to units
## already on the field, not just ones spawned after.
signal combat_hitboxes_visibility_changed(visible_now: bool)
var show_combat_hitboxes: bool = false:
	set(value):
		if value == show_combat_hitboxes:
			return
		show_combat_hitboxes = value
		combat_hitboxes_visibility_changed.emit(value)

## Whether every equipped item's GripMarker (the red sphere authored onto
## its GripPoint node -- see e.g. IronGreatsword.tscn) is shown. Off by
## default, same reasoning as show_combat_hitboxes: a grip-alignment
## debugging aid, not something a normal match should show.
## GripPointsToggleButton (see Main.tscn's UI) flips this; Unit listens for
## the change so it applies live to whatever's already equipped, not just
## items equipped after.
signal grip_points_visibility_changed(visible_now: bool)
var show_grip_points: bool = false:
	set(value):
		if value == show_grip_points:
			return
		show_grip_points = value
		grip_points_visibility_changed.emit(value)

## Which UI font is applied to the shared theme (see OptionsMenu._apply_font)
## -- one of OptionsMenu.FONT_OPTIONS' keys.
var ui_font: String = "console"

## Audio settings -- authoritative values OptionsMenu's sliders and Music.gd
## read at startup and write back on every change (see save_settings()
## callers). Kept here rather than read directly off AudioServer/the music
## player so there's one obvious place holding "what the user chose",
## independent of whichever bus/player object happens to represent it.
var master_volume_db: float = 0.0
var music_volume_db: float = -8.0
## In-game music playlist: track ids (see Music.available_tracks()).
var music_playlist: Array = default_playlist()

## Every built-in song, enabled (the default playlist).
static func default_playlist() -> Array:
	return preload("res://scripts/autoload/Music.gd").BUILTIN_TRACKS.map(func(t): return t[0])
## Shuffle: play the in-game songs in random order instead of list order.
var music_shuffle: bool = false
## Adaptive music: in a match, songs follow what is happening (Music.MOODS).
var adaptive_music: bool = true

## Rebindable controls: action id -> keycode (see Defs.HOTKEYS). Empty means
## "all defaults".
var hotkeys: Dictionary = {}
## Independent on/off switches, separate from the volume sliders above --
## OptionsMenu's Audio tab checkboxes (see _apply_audio_enabled/
## _apply_music_enabled) mute the Master bus / pause Music.player rather
## than touching these dB values, so turning audio back on restores
## whatever volume was set before, instead of forgetting it.
var audio_enabled: bool = true
var music_enabled: bool = true

## Root folder every account's saves live under -- see saves_dir().
const SAVES_ROOT: String = "user://saves"
## Subfolder saves_dir() falls back to when nobody's signed in, rather than
## blocking Save/Load entirely just because there's no account active.
const GUEST_SAVES_KEY: String = "_guest"

## Which folder to read/write save files in for whoever is currently
## signed in (see AccountMenu) -- each account gets its own subfolder so
## accounts don't see each other's saves. TitleMenu/MainMenu both call this
## instead of hardcoding "user://saves" so they can't drift out of sync
## with each other on where a save actually lives.
func saves_dir() -> String:
	var key := _sanitize_for_path(active_account) if not active_account.is_empty() else GUEST_SAVES_KEY
	return "%s/%s" % [SAVES_ROOT, key]

## Root folder every account's map-editor-authored maps live under -- same
## per-account split as saves_dir(), same reasoning (MapEditorController/
## TitleMenu both call this rather than hardcoding "user://maps").
const MAPS_ROOT: String = "user://maps"

func maps_dir() -> String:
	var key := _sanitize_for_path(active_account) if not active_account.is_empty() else GUEST_SAVES_KEY
	return "%s/%s" % [MAPS_ROOT, key]

## Account names are free-form user text (spaces, unicode, ...) but folder
## names can't contain path separators or the handful of characters
## Windows forbids -- swap those out rather than letting DirAccess silently
## fail to create/find the folder.
func _sanitize_for_path(value: String) -> String:
	var result := value
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		result = result.replace(ch, "_")
	return result

## Where account bookkeeping (the account list itself, stay-signed-in)
## survives to disk -- global, not per-account, since you need to know who
## the accounts even are before any per-account file could be picked.
const GLOBAL_SETTINGS_PATH: String = "user://settings.cfg"

## Where the *currently active* account's own preferences (audio, visuals,
## lobby setup) survive to disk -- one file per account (see saves_dir()
## for the same per-account-folder idea applied to save games), so signing
## in as a different account gets that account's own volume/font/lobby
## setup back, not whoever last touched the settings.
func account_settings_path() -> String:
	var key := _sanitize_for_path(active_account) if not active_account.is_empty() else GUEST_SAVES_KEY
	return "user://accounts/%s/settings.cfg" % key

func _ready() -> void:
	load_settings()
	_enforce_fullscreen()
	# Paint the tech icons on a worker thread now, so the match's research
	# screen and the Codex find them ready instead of stalling ~2 s.
	if DisplayServer.get_name() != "headless":
		TechIcons.warm_up()

## Re-asserts borderless fullscreen in code, on top of the [display]
## project settings (window/size/mode=3, window/size/borderless=true) --
## belt-and-suspenders against the Windows taskbar staying visible, which
## can happen if the OS ever hands the window a size that isn't pixel-
## exact with the monitor's real resolution (multi-monitor setups, a
## display added/removed since launch, some DPI-scaling configurations).
## Exclusive fullscreen (mode 4) hides the taskbar more reliably but was
## reverted project-wide because combining it with borderless=true caused
## HUD elements to render partially off-screen -- see project.godot's
## [display] section.
func _enforce_fullscreen() -> void:
	var window := get_window()
	window.mode = Window.MODE_FULLSCREEN
	window.borderless = true

## Writes both the global (account bookkeeping) and the active account's own
## settings file. Called right after each individual setting changes (a
## slider drag, a lobby selection, ...) rather than once at some "on quit"
## hook, so it survives a force-quit or crash the same as a clean exit --
## there's no window where a change is only in memory and not yet safe on
## disk.
## Dev and test runs (screenshots, sims, duels, training) never write the
## player's settings: they only read them.
static func _dev_run() -> bool:
	for k in ["SL_SHOT", "SL_SIM", "SL_DUEL", "SL_TITLE_SHOT", "SL_LOBBY_SHOT", "SL_CODEX_SHOT", "SL_OPTIONS_TAB", "SL_NN_WEIGHTS", "SL_HOVER_TEST", "SL_MIXVARIANTS", "SL_PLAYTEST"]:
		if OS.get_environment(k) != "":
			return true
	return false

## Quitting saves too, so the next launch starts exactly as you left it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_settings()

func save_settings() -> void:
	save_global_settings()
	save_account_settings()

func save_global_settings() -> void:
	if _dev_run():
		return
	var config := ConfigFile.new()
	config.set_value("accounts", "list", accounts)
	config.set_value("accounts", "stay_signed_in", stay_signed_in)
	config.set_value("accounts", "remembered_account", remembered_account)
	config.save(GLOBAL_SETTINGS_PATH)

func save_account_settings() -> void:
	if _dev_run():
		return
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume_db", master_volume_db)
	config.set_value("audio", "music_volume_db", music_volume_db)
	config.set_value("audio", "audio_enabled", audio_enabled)
	config.set_value("audio", "music_enabled", music_enabled)
	config.set_value("audio", "music_playlist", music_playlist)
	config.set_value("audio", "music_shuffle", music_shuffle)
	config.set_value("audio", "adaptive_music", adaptive_music)
	config.set_value("controls", "hotkeys", hotkeys)
	config.set_value("visuals", "show_debug_grid", show_debug_grid)
	config.set_value("visuals", "show_combat_hitboxes", show_combat_hitboxes)
	config.set_value("visuals", "show_grip_points", show_grip_points)
	config.set_value("visuals", "ui_font", ui_font)
	config.set_value("lobby", "human_player_id", human_player_id)
	config.set_value("lobby", "deathmatch", deathmatch)
	config.set_value("lobby", "player_slots", player_slots)
	var path := account_settings_path()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	config.save(path)

## Loads whatever was saved last, leaving each var's already-declared
## default in place for anything missing (first run, or an older save
## missing a newer key). Global bookkeeping first (so we know who's
## signed in), then that account's own settings.
func load_settings() -> void:
	load_global_settings()
	load_account_settings()

func load_global_settings() -> void:
	var config := ConfigFile.new()
	if config.load(GLOBAL_SETTINGS_PATH) != OK:
		return
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

## Loads whichever account is currently active's own settings (falling
## back to the shared guest file if nobody's signed in). Called again by
## AccountMenu every time active_account changes mid-session -- not just
## at startup -- so switching accounts actually picks up that account's
## own audio/visuals/lobby setup live, instead of only on next launch.
func load_account_settings() -> void:
	_reset_account_settings_to_defaults()
	var config := ConfigFile.new()
	if config.load(account_settings_path()) != OK:
		return
	master_volume_db = config.get_value("audio", "master_volume_db", master_volume_db)
	music_volume_db = config.get_value("audio", "music_volume_db", music_volume_db)
	audio_enabled = config.get_value("audio", "audio_enabled", audio_enabled)
	music_enabled = config.get_value("audio", "music_enabled", music_enabled)
	music_playlist = config.get_value("audio", "music_playlist", music_playlist)
	music_shuffle = config.get_value("audio", "music_shuffle", music_shuffle)
	adaptive_music = config.get_value("audio", "adaptive_music", adaptive_music)
	hotkeys = config.get_value("controls", "hotkeys", {})
	show_debug_grid = config.get_value("visuals", "show_debug_grid", show_debug_grid)
	show_combat_hitboxes = config.get_value("visuals", "show_combat_hitboxes", show_combat_hitboxes)
	show_grip_points = config.get_value("visuals", "show_grip_points", show_grip_points)
	ui_font = config.get_value("visuals", "ui_font", ui_font)
	if ui_font not in ["console", "default"]:
		ui_font = "console"
	human_player_id = config.get_value("lobby", "human_player_id", human_player_id)
	deathmatch = config.get_value("lobby", "deathmatch", deathmatch)
	player_slots = config.get_value("lobby", "player_slots", player_slots)

## Resets every per-account field to this class's own declared defaults --
## called before loading a (possibly nonexistent) account settings file so
## a brand-new account starts clean instead of inheriting whatever the
## previously-active account happened to have in memory.
func _reset_account_settings_to_defaults() -> void:
	show_debug_grid = true
	show_combat_hitboxes = false
	show_grip_points = false
	ui_font = "console"
	master_volume_db = 0.0
	music_volume_db = -8.0
	audio_enabled = true
	music_enabled = true
	music_playlist = default_playlist()
	music_shuffle = false
	adaptive_music = true
	hotkeys = {}
	human_player_id = 1
	player_slots = _default_player_slots()
