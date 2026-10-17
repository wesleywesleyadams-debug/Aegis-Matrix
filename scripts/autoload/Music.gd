extends Node
## Autoload -- background music that keeps playing across scene changes.
## Tracks are loops in assets/audio/: music_<name>.ogg (licensed recordings,
## see CREDITS.md) or music_<name>.wav (procedural, baked by
## tools/gen_audio.gd). Screens pick one via play_track(); matches play the
## player's in-game playlist (GameState.music_playlist) via
## play_game_playlist(). Players can import their own songs (Options >
## Audio > In-Game Music), which are copied into USER_DIR.

const TITLE_TRACK: String = "title"
const LOBBY_TRACK: String = "lobby"
const IN_GAME_TRACK: String = "through_space"

## Built-in songs offered for the in-game playlist: [id, display name].
const BUILTIN_TRACKS := [
	["through_space", "Through Space (Maxstack)"],
	["spacelife", "Space Life No. 14 (YD)"],
	["magic_space", "Magic Space (CodeManu)"],
	["deus_ex_tempus", "Deus Ex Tempus (Trevor Lentz)"],
	["hero_immortal", "Hero Immortal (Trevor Lentz)"],
	["galactic_temple", "Galactic Temple (yd)"],
	["sector", "Sector (SRG774)"],
	["airy", "Airy (SRG774)"],
	["pulse", "Pulse (SRG774)"],
	["determined_pursuit", "Determined Pursuit (Emma_MA)"],
	["spacedman", "Spacedman (Shane Ivers)"],
	["space_graveyard", "Space Graveyard (TinyWorlds)"],
	["deep_space_array", "Deep Space Array (Tozan)"],
	["surreal_truth", "The Surreal Truth (Joth)"],
	["infestation", "Infestation in the Control Room (Joth)"],
	["captains_log", "Final Captain's Log (Joth)"],
	["depths_of_hell", "The Depths of Hell (Joth)"],
	["cage_of_the_cryptid", "Cage of the Cryptid (Joth)"],
	["unexpected_trouble", "Unexpected Trouble (section31)"],
	["sentry", "Sentry (section31)"],
	["game", "Stardust Dominion Synth: In-Game"],
	["title", "Stardust Dominion Synth: Title"],
	["lobby", "Stardust Dominion Synth: Lobby"],
]
## Imported songs live here; their track id is "user:<file name>".
const USER_DIR := "user://music"
const IMPORT_EXTENSIONS := ["ogg", "mp3", "wav"]

## Per-track loudness trim (dB) so tracks sit at the same level (measured
## integrated loudness; the procedural loops are about -22 LUFS). Recordings
## are left untouched and turned down here instead.
const TRACK_TRIM := {"through_space": -3.0, "spacelife": -3.0, "magic_space": -8.5, "deus_ex_tempus": -11.0, "hero_immortal": -9.5, "galactic_temple": 2.0, "sector": -10.0, "airy": -8.5, "pulse": -3.5, "determined_pursuit": -9.2, "spacedman": -2.3}

signal tracks_changed

@onready var player: AudioStreamPlayer = $Player

var _current: String = ""
## Playlist mode: the ids being played in order and where we are.
var _playlist: Array = []
var _playlist_index: int = 0
## True while the in-game playlist is in charge (a match), so enabling or
## disabling songs takes effect straight away.
var _in_game := false
## The title or lobby screen's own song (TITLE_TRACK / LOBBY_TRACK) while on
## that screen, else "". See play_screen().
var _screen_track := ""
## Preview (Options menu): the id being previewed and what to return to.
var previewing: String = ""
var _before_preview := {}

func _ready() -> void:
	player.volume_db = GameState.music_volume_db
	# Keeps running while the game is paused (pause menu buttons flick too).
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_environment("SL_HOVER_TEST") != "":
		_hover_test.call_deferred()
	player.finished.connect(_on_finished)
	_cue_ui = AudioStreamPlayer.new()
	add_child(_cue_ui)
	_fader = AudioStreamPlayer.new()
	_fader.bus = player.bus
	add_child(_fader)
	play_screen(TITLE_TRACK)
	if OS.get_environment("SL_MUSIC_LIVE_TEST") != "":
		_live_test.call_deferred()
	if OS.get_environment("SL_MUSIC_TEST") != "":
		_self_test.call_deferred(OS.get_environment("SL_MUSIC_TEST"))

# ---------------------------------------------------------------- tracks

## Every song that can go in the in-game playlist: [{id, name, user}].
func available_tracks() -> Array:
	var out: Array = []
	for t in BUILTIN_TRACKS:
		if _builtin_path(t[0]) != "":
			out.append({"id": t[0], "name": t[1], "user": false})
	var dir := DirAccess.open(USER_DIR)
	if dir:
		var files := Array(dir.get_files())
		files.sort()
		for f in files:
			if f.get_extension().to_lower() in IMPORT_EXTENSIONS:
				out.append({"id": "user:" + f, "name": f.get_basename(), "user": true})
	return out

func _builtin_path(id: String) -> String:
	for ext in ["ogg", "mp3", "wav"]:
		var p := "res://assets/audio/music_%s.%s" % [id, ext]
		if ResourceLoader.exists(p):
			return p
	return ""

## Loads a track as a stream (imported files are read from disk).
func _stream(id: String) -> AudioStream:
	if id.begins_with("cue:"):
		return _cue_stream(id.substr(4))
	if id.begins_with("user:"):
		var path := USER_DIR + "/" + id.substr(5)
		if not FileAccess.file_exists(path):
			return null
		match path.get_extension().to_lower():
			"ogg":
				return AudioStreamOggVorbis.load_from_file(path)
			"wav":
				return AudioStreamWAV.load_from_file(path)
			"mp3":
				var mp3 := AudioStreamMP3.new()
				mp3.data = FileAccess.get_file_as_bytes(path)
				return mp3
		return null
	var p := _builtin_path(id)
	return load(p) if p != "" else null

static func _set_loop(stream: AudioStream, on: bool) -> void:
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = on
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if on else AudioStreamWAV.LOOP_DISABLED
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)

## Copies a song from anywhere on disk into USER_DIR and adds it to the
## playlist. Returns its track id, or "" if the file can't be used.
func import_file(src: String) -> String:
	if not src.get_extension().to_lower() in IMPORT_EXTENSIONS:
		return ""
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var name := src.get_file()
	var n := 2
	while FileAccess.file_exists(USER_DIR + "/" + name):
		name = "%s (%d).%s" % [src.get_file().get_basename(), n, src.get_extension()]
		n += 1
	if DirAccess.copy_absolute(src, ProjectSettings.globalize_path(USER_DIR + "/" + name)) != OK:
		return ""
	var id := "user:" + name
	if _stream(id) == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_DIR + "/" + name))
		return ""
	set_in_playlist(id, true)
	tracks_changed.emit()
	return id

func set_in_playlist(id: String, on: bool) -> void:
	var pl: Array = GameState.music_playlist
	if on and not pl.has(id):
		pl.append(id)
	elif not on:
		pl.erase(id)
	GameState.save_settings()
	if previewing != "":
		return   # stop_preview() catches up
	if _screen_track != "" and id == _screen_track:
		play_screen(_screen_track)
	elif _in_game:
		_playlist_changed(id, on)

# ---------------------------------------------------------------- playback

## Title and lobby music: the screen's own synth song if it's enabled in the
## song list, otherwise the enabled songs (silence if none). Enabling or
## disabling songs switches straight away.
func play_screen(track: String) -> void:
	_screen_track = track
	_cue = ""
	# The main screen has its own menu loop from the cue library.
	if track == TITLE_TRACK and _cue_stream("title") != null:
		_playlist = []
		_in_game = false
		var ts := _cue_stream("title")
		_set_loop(ts, true)
		_start("cue:title", ts)
		return
	if GameState.music_playlist.has(track) and _stream(track) != null:
		play_track(track)
	elif not _in_game:
		_start_playlist()

## The Title and Lobby songs only ever play on their own screens (see
## play_screen), never in the match / fallback playlist.
func _in_rotation(id: String) -> bool:
	return id != TITLE_TRACK and id != LOBBY_TRACK

## Switches to a track, looping. A no-op if it's already playing, so a
## scene reload doesn't restart it.
func play_track(name: String) -> void:
	if name == _current and player.playing and _playlist.is_empty():
		return
	_playlist = []
	_in_game = false
	var stream := _stream(name)
	if stream == null:
		return
	_set_loop(stream, true)
	_start(name, stream)

## In-game music: the player's playlist in order (starting at a random song),
## moving on when each ends. Every song, Through Space included, can be
## disabled: an empty playlist means no in-game music.
func play_game_playlist() -> void:
	_screen_track = ""
	_cue = ""
	mood = "calm"
	_mood_seen = {}
	_calm_index = -1
	_start_playlist()

func _start_playlist() -> void:
	_in_game = true
	var pl: Array = GameState.music_playlist.filter(func(id): return _in_rotation(id) and _stream(id) != null)
	if pl.is_empty():
		_playlist = []
		player.stop()
		_current = ""
		return
	# Adaptive music: only this mood's songs (calm ones if the mood has none
	# enabled; everything if calm has none either).
	if GameState.adaptive_music:
		var m := pl.filter(func(id): return mood_of(id) == mood)
		if mood == "siege":
			m.append("cue:urgent")
		if m.is_empty() and mood == "siege":
			m = pl.filter(func(id): return mood_of(id) == "battle")
		if m.is_empty():
			m = pl.filter(func(id): return mood_of(id) == "calm")
		if not m.is_empty():
			pl = m
	_playlist = pl
	# Calm picks up where it left off; other moods start on a random song.
	if mood == "calm" and _calm_index >= 0:
		_playlist_index = (_calm_index + 1) % pl.size()
	else:
		_playlist_index = randi() % pl.size()
	_play_playlist_item()

func _play_playlist_item() -> void:
	var id: String = _playlist[_playlist_index]
	if mood == "calm":
		_calm_index = _playlist_index
	var stream := _stream(id)
	# A single-song playlist just loops; otherwise each song plays once.
	_set_loop(stream, _playlist.size() == 1)
	_start(id, stream)

func _on_finished() -> void:
	if previewing != "" or _playlist.is_empty() or _cue != "":
		return
	_playlist_index = _next_index()
	_play_playlist_item()

func _start(id: String, stream: AudioStream) -> void:
	# Crossfade from whatever was playing (adaptive mood changes); the old
	# song fades on its own player so `player` is always the current one.
	if _fade_next and player.playing:
		_fader.stream = player.stream
		_fader.volume_db = player.volume_db
		_fader.play(player.get_playback_position())
		var tw := create_tween()
		tw.tween_property(_fader, "volume_db", -60.0, CROSSFADE)
		tw.tween_callback(_fader.stop)
	var fade_in := _fade_next
	_fade_next = false
	_current = id
	player.stream = stream
	apply_volume()
	player.play()
	if fade_in:
		var target := player.volume_db
		player.volume_db = -40.0
		create_tween().tween_property(player, "volume_db", target, CROSSFADE)
	if OS.get_environment("SL_MUSIC_DEBUG") != "":
		print("MUSIC %s: volume %.1f dB playing=%s" % [id, player.volume_db, str(player.playing)])

## Plays a song so the player can hear it (Options menu), remembering what
## was playing so stop_preview() can go back to it.
func preview(id: String) -> void:
	var stream := _stream(id)
	if stream == null:
		return
	if previewing == "":
		_before_preview = {"stream": player.stream, "id": _current, "pos": player.get_playback_position(),
			"playlist": _playlist.duplicate(), "index": _playlist_index}
	previewing = id
	_set_loop(stream, true)
	_start(id, stream)

func stop_preview() -> void:
	if previewing == "":
		return
	previewing = ""
	if _before_preview.is_empty() or _before_preview["stream"] == null:
		player.stop()
		return
	_playlist = _before_preview["playlist"]
	_playlist_index = _before_preview["index"]
	_current = _before_preview["id"]
	player.stream = _before_preview["stream"]
	apply_volume()
	player.play(_before_preview["pos"])
	_before_preview = {}
	if _screen_track != "" and GameState.music_playlist.has(_screen_track) != (_current == _screen_track and not _in_game):
		play_screen(_screen_track)
		return
	# Songs may have been enabled/disabled while previewing.
	if _in_game:
		var was := _current
		_playlist = _playlist.filter(func(t): return GameState.music_playlist.has(t))
		for t in GameState.music_playlist:
			if not _playlist.has(t) and _in_rotation(t) and _stream(t) != null:
				_playlist.append(t)
		if _playlist.is_empty():
			player.stop()
			_current = ""
		elif not _playlist.has(was):
			_playlist_index = _playlist_index % _playlist.size()
			_play_playlist_item()
		else:
			_playlist_index = _playlist.find(was)
			_set_loop(player.stream, _playlist.size() == 1)

## Player volume = the Options music volume plus this track's trim.
func apply_volume() -> void:
	player.volume_db = GameState.music_volume_db + TRACK_TRIM.get(_current, CUE_TRIM.get(_current.trim_prefix("cue:"), 0.0))

func restart_current_track() -> void:
	player.seek(0.0)

## Dev aid: SL_MUSIC_TEST=<path to a song> imports it, previews it, stops
## the preview, plays the playlist, disables and re-enables it (then deletes
## the test copy), printing each step.
func _self_test(src: String) -> void:
	var saved: Array = GameState.music_playlist.duplicate()
	print("TEST tracks: ", available_tracks().map(func(t): return t["id"]))
	var id := import_file(src)
	print("TEST imported: '%s'  in playlist: %s  tracks now %d" % [id, str(GameState.music_playlist.has(id)), available_tracks().size()])
	print("TEST before preview: current=%s playing=%s" % [_current, str(player.playing)])
	preview(id)
	await get_tree().create_timer(0.5).timeout
	print("TEST previewing=%s current=%s playing=%s pos=%.2f" % [previewing, _current, str(player.playing), player.get_playback_position()])
	stop_preview()
	print("TEST after stop: current=%s playing=%s" % [_current, str(player.playing)])
	play_game_playlist()
	print("TEST playlist %s -> now playing %s (loop %s)" % [str(_playlist), _current, str(_playlist.size() == 1)])
	set_in_playlist(id, false)
	print("TEST disabled: still listed %s, in playlist %s" % [str(available_tracks().any(func(t): return t["id"] == id)), str(GameState.music_playlist.has(id))])
	set_in_playlist(id, true)
	print("TEST re-enabled: in playlist %s" % str(GameState.music_playlist.has(id)))
	# Test clean-up only: delete the imported copy.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_DIR + "/" + id.substr(5)))
	GameState.music_playlist = saved
	GameState.save_settings()
	get_tree().quit()

## A song was enabled/disabled mid-match: drop it from (or add it to) the
## running playlist; if the song playing now was disabled, move on to the
## next one, or go silent if none are left.
func _playlist_changed(id: String, on: bool) -> void:
	if not _in_rotation(id):
		return
	if on:
		if not _playlist.has(id) and _stream(id) != null:
			_playlist.append(id)
			if _playlist.size() == 1 and previewing == "":
				_playlist_index = 0
				_play_playlist_item()
			elif _playlist.size() == 2 and previewing == "":
				_set_loop(player.stream, false)   # no longer the only song
		return
	var i := _playlist.find(id)
	if i == -1:
		return
	_playlist.remove_at(i)
	if i < _playlist_index:
		_playlist_index -= 1
	var was_playing := _current == id and previewing == ""
	if _playlist.is_empty():
		if was_playing:
			player.stop()
			_current = ""
		return
	_playlist_index %= _playlist.size()
	if was_playing:
		_play_playlist_item()
	elif _playlist.size() == 1:
		_set_loop(player.stream, true)

## Dev aid: SL_MUSIC_LIVE_TEST=1 plays a two-song match playlist, then
## disables songs one at a time (and re-enables one), printing what plays.
func _live_test() -> void:
	var saved: Array = GameState.music_playlist.duplicate()
	GameState.music_playlist = ["through_space", "spacelife"]
	play_game_playlist()
	print("LIVE start: ", _current, " playing=", player.playing)
	set_in_playlist(_current, false)
	print("LIVE disabled current -> ", _current, " playing=", player.playing, " list=", _playlist)
	set_in_playlist(_current, false)
	print("LIVE disabled last -> '", _current, "' playing=", player.playing)
	set_in_playlist("through_space", true)
	print("LIVE re-enabled through_space -> ", _current, " playing=", player.playing)
	preview("magic_space")
	set_in_playlist("through_space", false)
	stop_preview()
	print("LIVE disabled during preview -> '", _current, "' playing=", player.playing)
	# Title screen.
	GameState.music_playlist = ["title", "spacelife"]
	play_screen(TITLE_TRACK)
	print("LIVE title screen, title enabled -> ", _current)
	set_in_playlist("title", false)
	print("LIVE title disabled -> ", _current, " playing=", player.playing)
	set_in_playlist("title", true)
	print("LIVE title re-enabled -> ", _current)
	set_in_playlist("title", false)
	set_in_playlist("spacelife", false)
	print("LIVE all disabled -> '", _current, "' playing=", player.playing)
	play_screen(LOBBY_TRACK)
	print("LIVE lobby, nothing enabled -> '", _current, "' playing=", player.playing)
	set_in_playlist("lobby", true)
	print("LIVE lobby enabled -> ", _current, " playing=", player.playing)
	preview("hero_immortal")
	set_in_playlist("lobby", false)
	stop_preview()
	print("LIVE lobby disabled during preview -> '", _current, "' playing=", player.playing)
	GameState.music_playlist = ["title", "lobby", "spacelife"]
	play_game_playlist()
	print("LIVE match with title+lobby+spacelife -> ", _playlist)
	set_in_playlist("title", false)
	set_in_playlist("title", true)
	print("LIVE match after toggling title -> ", _playlist, " ", _current)
	play_screen(TITLE_TRACK)
	print("LIVE title screen -> ", _current)
	set_in_playlist("title", false)
	print("LIVE title screen, title off -> ", _current)
	play_screen(LOBBY_TRACK)
	print("LIVE lobby screen -> ", _current)
	GameState.music_playlist = ["through_space", "spacelife", "magic_space", "deus_ex_tempus", "hero_immortal"]
	play_game_playlist()
	for s in [false, true]:
		GameState.music_shuffle = s
		var seq := []
		for k in 12:
			_on_finished()
			seq.append(_playlist_index)
		print("LIVE shuffle=", s, " order: ", seq)
	GameState.music_shuffle = false
	GameState.music_playlist = saved
	GameState.save_settings()
	get_tree().quit()

## The next song: the following one in list order, or with shuffle on a
## random one (never the song that just played, if there's a choice).
func _next_index() -> int:
	if not GameState.music_shuffle or _playlist.size() < 2:
		return (_playlist_index + 1) % _playlist.size()
	var i := randi() % (_playlist.size() - 1)
	return i + 1 if i >= _playlist_index else i

# ---------------------------------------------------------------- cues
# A hidden library of musical cues (assets/audio/cues/cue_<name>.ogg, from
# the Dark Sci-Fi Audio Pack, see CREDITS.md). They are never offered as
# soundtrack songs: each plays for one purpose -
#   title        the main screen's menu loop (play_screen)
#   victory      the win sound (Sfx plays it)
#   transmission the end-of-match theme after a win (play_cue, looping)
#   defeat_1-2   defeat stings; defeat_song_1-4 the end theme after a loss
#   urgent       high-stakes music while our worlds or starbases are under
#                attack (urgent_ping), handing back to the playlist after
#                attack, as the "siege" mood (see moods below)

const CUE_DIR := "res://assets/audio/cues/cue_%s.ogg"
## Loudness trims (dB) so the cues sit with the soundtrack.
const CUE_TRIM := {"title": -2.0, "transmission": -9.0, "urgent": -2.4}
## Button hover: a short, quiet flick (synthesised: filtered noise + a tiny
## falling chirp, 22 ms).
const HOVER_SOUND := "res://assets/audio/sfx_hover_flick.wav"
const HOVER_DB := -10.0
var _hover_stream: AudioStream
var _hover_ui: AudioStreamPlayer
## Seconds of calm after the last attack before urgent music hands back.

var _cue := ""
var _cue_ui: AudioStreamPlayer

func _cue_stream(name: String) -> AudioStream:
	var p := CUE_DIR % name
	return load(p) if ResourceLoader.exists(p) else null

## Replaces the music with a cue until play_game_playlist / play_screen.
func play_cue(name: String, loop: bool = true) -> void:
	var s := _cue_stream(name)
	if s == null:
		return
	_cue = name
	_set_loop(s, loop)
	_start("cue:" + name, s)

## Called whenever our worlds or starbases are attacked: the siege mood.
func urgent_ping() -> void:
	report_mood("siege")

# ---------------------------------------------------------------- moods
# Adaptive music (GameState.adaptive_music): in a match, the game reports
# what is happening once a second (Game._report_music_mood) and the songs
# follow. Moods rise at once and only fall back after MOOD_HOLD seconds
# without the higher one being reported, so the music doesn't flicker.

const MOODS := {
	"galactic_temple": "calm", "airy": "calm", "sector": "calm", "spacelife": "calm",
	"magic_space": "calm", "spacedman": "calm", "through_space": "calm",
	"pulse": "tension", "space_graveyard": "tension", "deep_space_array": "tension", "surreal_truth": "tension",
	"infestation": "tension", "captains_log": "tension", "depths_of_hell": "tension", "cage_of_the_cryptid": "tension",
	"unexpected_trouble": "siege", "sentry": "siege",
	"determined_pursuit": "battle", "deus_ex_tempus": "battle", "hero_immortal": "battle",
}
const MOOD_RANK := {"calm": 0, "tension": 1, "battle": 2, "siege": 3}
const MOOD_HOLD := 25.0
const CROSSFADE := 2.0

var mood := "calm"
var _mood_seen := {}
var _calm_index := -1
var _fade_next := false
var _fader: AudioStreamPlayer

## The mood a song belongs to (imported and unlisted songs count as calm).
func mood_of(id: String) -> String:
	return MOODS.get(id, "calm")

func report_mood(m: String) -> void:
	if not _in_game or not GameState.adaptive_music or (_cue != "" and _cue != "urgent") or previewing != "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	_mood_seen[m] = now
	if MOOD_RANK[m] > MOOD_RANK[mood]:
		_set_mood(m)

func _process(_delta: float) -> void:
	_check_hover()
	if not _in_game or not GameState.adaptive_music or mood == "calm":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _mood_seen.get(mood, 0.0) < MOOD_HOLD:
		return
	# Fall to the highest mood still recently reported.
	var best := "calm"
	for m in MOOD_RANK:
		if MOOD_RANK[m] < MOOD_RANK[mood] and MOOD_RANK[m] > MOOD_RANK[best] and now - _mood_seen.get(m, -INF) < MOOD_HOLD:
			best = m
	_set_mood(best)

## The Options toggle: switch between mood songs and the plain playlist now.
func set_adaptive(_on: bool) -> void:
	if not _in_game or previewing != "":
		return
	mood = "calm"
	_mood_seen = {}
	if _cue == "urgent":
		_cue = ""
	if _cue == "":
		_fade_next = true
		_start_playlist()

func _set_mood(m: String) -> void:
	if m == mood:
		return
	var was_battle := mood == "battle" or mood == "siege"
	mood = m
	if OS.get_environment("SL_MUSIC_DEBUG") != "":
		print("MUSIC mood -> ", m)
	_fade_next = true
	_cue = ""
	# Battle to battle-fallback (siege ending) keeps a battle song going.
	if m == "battle" and was_battle and mood_of(_current) == "battle":
		_fade_next = false
		return
	_start_playlist()

## A one-shot cue on its own player, so it doesn't interrupt the music.
func play_cue_sfx(name: String, volume_db: float = 0.0) -> void:
	var s := _cue_stream(name)
	if s == null:
		return
	_set_loop(s, false)
	_cue_ui.stream = s
	_cue_ui.volume_db = volume_db
	_cue_ui.pitch_scale = 1.0
	_cue_ui.play()

## Button hover: checked every frame from what the mouse is actually over,
## so every button - in any menu, created at any time, with children or not -
## flicks once when the pointer moves onto it.
var _hovered_button: BaseButton

func _check_hover() -> void:
	var c := get_viewport().gui_get_hovered_control()
	while c != null and not (c is BaseButton):
		c = c.get_parent() as Control
	var b := c as BaseButton
	if b == _hovered_button:
		return
	_hovered_button = b
	if b == null or b.disabled or not b.is_visible_in_tree():
		return
	_on_button_hover()

func _on_button_hover() -> void:
	_hover_plays += 1
	if _hover_stream == null:
		_hover_stream = load(HOVER_SOUND)
	# Its own player, so a hover never cuts off a victory or defeat sting.
	if _hover_ui == null:
		_hover_ui = AudioStreamPlayer.new()
		add_child(_hover_ui)
	_hover_ui.stream = _hover_stream
	_hover_ui.volume_db = HOVER_DB
	_hover_ui.pitch_scale = randf_range(0.94, 1.06)
	_hover_ui.play()

## Dev: SL_HOVER_TEST=1 moves the mouse over every visible button on the
## title screen and prints how many flicks played.
var _hover_plays := 0

func _hover_test() -> void:
	await get_tree().create_timer(float(OS.get_environment("SL_HOVER_WAIT")) if OS.get_environment("SL_HOVER_WAIT") != "" else 1.5).timeout
	var phases := ["screen"]
	if Game.instance:
		phases = ["research panel", "task panel"]
	for ph in phases:
		if ph == "research panel":
			Game.instance.hud.toggle_research()
		elif ph == "task panel":
			Game.instance.hud.toggle_research()
			Game.instance._set_selection([Game.instance.nearest_starbase(Game.instance.player_id, Vector2.ZERO)], false)
		for i in 6:
			await get_tree().process_frame
		var n := 0
		var before := _hover_plays
		for b in get_tree().root.find_children("*", "BaseButton", true, false):
			if not b.is_visible_in_tree() or b.disabled or not get_viewport().get_visible_rect().has_point(b.get_global_rect().get_center()):
				continue
			get_viewport().warp_mouse(b.get_global_rect().get_center())
			for i in 4:
				await get_tree().process_frame
			# Only buttons the pointer can actually reach (not under a panel).
			if _hovered_button == b:
				n += 1
			else:
				var top := get_viewport().gui_get_hovered_control()
				print("  covered: %s under %s" % [b.text if b is Button else b.name, top.name if top else "nothing"])
		print("HOVER TEST %s: buttons %d flicks %d" % [ph, n, _hover_plays - before])
	get_tree().quit()
