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
const TRACK_TRIM := {"through_space": -3.0}

signal tracks_changed

@onready var player: AudioStreamPlayer = $Player

var _current: String = ""
## Playlist mode: the ids being played in order and where we are.
var _playlist: Array = []
var _playlist_index: int = 0
## Preview (Options menu): the id being previewed and what to return to.
var previewing: String = ""
var _before_preview := {}

func _ready() -> void:
	player.volume_db = GameState.music_volume_db
	player.finished.connect(_on_finished)
	play_track(TITLE_TRACK)
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
	for ext in ["ogg", "wav"]:
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

# ---------------------------------------------------------------- playback

## Switches to a track, looping. A no-op if it's already playing, so a
## scene reload doesn't restart it.
func play_track(name: String) -> void:
	if name == _current and player.playing and _playlist.is_empty():
		return
	_playlist = []
	var stream := _stream(name)
	if stream == null:
		return
	_set_loop(stream, true)
	_start(name, stream)

## In-game music: the player's playlist in order (starting at a random song),
## moving on when each ends. Falls back to IN_GAME_TRACK if the playlist is
## empty or none of its songs can be loaded.
func play_game_playlist() -> void:
	var pl: Array = GameState.music_playlist.filter(func(id): return _stream(id) != null)
	if pl.is_empty():
		play_track(IN_GAME_TRACK)
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
	_playlist_index = (_playlist_index + 1) % _playlist.size()
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
