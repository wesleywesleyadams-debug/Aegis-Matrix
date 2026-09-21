extends Node
## Autoload -- background music that keeps playing across scene changes.
## Tracks are ambient loops baked by tools/gen_audio.gd into
## assets/audio/music_<name>.wav. Each screen picks one via play_track().

const TITLE_TRACK: String = "title"
const LOBBY_TRACK: String = "lobby"
const IN_GAME_TRACK: String = "game"

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
	var track: AudioStreamWAV = load("res://assets/audio/music_%s.wav" % name)
	track.loop_mode = AudioStreamWAV.LOOP_FORWARD
	track.loop_begin = 0
	track.loop_end = int(track.get_length() * track.mix_rate)
	player.stream = track
	player.play()

func restart_current_track() -> void:
	player.seek(0.0)
