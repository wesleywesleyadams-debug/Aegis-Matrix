extends Node
## Autoload -- background music that keeps playing across scene changes,
## switching tracks per screen (see play_track() calls in
## TitleMenu.gd/Lobby.gd/RTSController.gd) rather than restarting from
## silence every time a scene loads.

## One entry per screen.
const TITLE_TRACK: String = "res://assets/audio/theme.mp3"
const LOBBY_TRACK: String = "res://assets/audio/nidavellir.mp3"
const IN_GAME_TRACK: String = "res://assets/audio/dragon_empress.mp3"

@onready var player: AudioStreamPlayer = $Player

var _current_path: String = ""

func _ready() -> void:
	player.volume_db = GameState.music_volume_db
	play_track(TITLE_TRACK)

## Switches to `path`'s track, looping. A no-op if it's already playing --
## calling this again from the same screen's _ready() (e.g. after a scene
## reload) doesn't restart the track from the beginning.
func play_track(path: String) -> void:
	if path == _current_path and player.playing:
		return
	_current_path = path
	var track: AudioStreamMP3 = load(path)
	track.loop = true
	player.stream = track
	player.play()
