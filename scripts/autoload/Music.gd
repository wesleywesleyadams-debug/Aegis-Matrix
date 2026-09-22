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
	["game", "Star Lords Synth: In-Game"],
	["title", "Star Lords Synth: Title"],
	["lobby", "Star Lords Synth: Lobby"],
]
## Imported songs live here; their track id is "user:<file name>".
const USER_DIR := "user://music"
const IMPORT_EXTENSIONS := ["ogg", "mp3", "wav"]

## Per-track loudness trim (dB) so tracks sit at the same level (measured
## integrated loudness; the procedural loops are about -22 LUFS). Recordings
## are left untouched and turned down here instead.
const TRACK_TRIM := {"through_space": -3.0, "spacelife": -3.0, "magic_space": -8.5, "deus_ex_tempus": -11.0, "hero_immortal": -9.5}

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
	player.finished.connect(_on_finished)
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
	_start_playlist()

func _start_playlist() -> void:
	_in_game = true
	var pl: Array = GameState.music_playlist.filter(func(id): return _in_rotation(id) and _stream(id) != null)
	if pl.is_empty():
		_playlist = []
		player.stop()
		_current = ""
		return
	_playlist = pl
	_playlist_index = randi() % pl.size()
	_play_playlist_item()

func _play_playlist_item() -> void:
	var id: String = _playlist[_playlist_index]
	var stream := _stream(id)
	# A single-song playlist just loops; otherwise each song plays once.
	_set_loop(stream, _playlist.size() == 1)
	_start(id, stream)

func _on_finished() -> void:
	if previewing != "" or _playlist.is_empty():
		return
	_playlist_index = _next_index()
	_play_playlist_item()

func _start(id: String, stream: AudioStream) -> void:
	_current = id
	player.stream = stream
	apply_volume()
	player.play()
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
	player.volume_db = GameState.music_volume_db + TRACK_TRIM.get(_current, 0.0)

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
