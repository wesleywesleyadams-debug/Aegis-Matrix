extends Node
## Autoload -- background music that keeps playing across scene changes.
## Tracks are loops in assets/audio/: music_<name>.ogg (licensed recordings,
## see CREDITS.md) or music_<name>.wav (procedural, baked by
## tools/gen_audio.gd). Each screen picks one via play_track().

const TITLE_TRACK: String = "title"
const LOBBY_TRACK: String = "lobby"
const IN_GAME_TRACK: String = "through_space"

## Per-track loudness trim (dB) so tracks sit at the same level (measured
## integrated loudness; the procedural loops are about -22 LUFS). Recordings
## are left untouched and turned down here instead.
const TRACK_TRIM := {"through_space": -3.0}

@onready var player: AudioStreamPlayer = $Player

var _current: String = ""

func _ready() -> void:
	player.volume_db = GameState.music_volume_db
	play_track(TITLE_TRACK)

## Switches to a track, looping. A no-op if it's already playing, so a
## scene reload doesn't restart it.
func play_track(name: String) -> void:
	if name == _current and player.playing:
		return
	_current = name
	var ogg := "res://assets/audio/music_%s.ogg" % name
	if ResourceLoader.exists(ogg):
		var stream: AudioStreamOggVorbis = load(ogg)
		stream.loop = true
		player.stream = stream
	else:
		var track: AudioStreamWAV = load("res://assets/audio/music_%s.wav" % name)
		track.loop_mode = AudioStreamWAV.LOOP_FORWARD
		track.loop_begin = 0
		track.loop_end = int(track.get_length() * track.mix_rate)
		player.stream = track
	apply_volume()
	player.play()
	if OS.get_environment("SL_MUSIC_DEBUG") != "":
		print("MUSIC %s: %s loop=%s volume %.1f dB playing=%s" % [name, player.stream.resource_path, str(player.stream.loop if player.stream is AudioStreamOggVorbis else player.stream.loop_mode), player.volume_db, str(player.playing)])

## Player volume = the Options music volume plus this track's trim.
func apply_volume() -> void:
	player.volume_db = GameState.music_volume_db + TRACK_TRIM.get(_current, 0.0)

func restart_current_track() -> void:
	player.seek(0.0)
