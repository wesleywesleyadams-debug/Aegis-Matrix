class_name Sfx
extends Node
## Sound effects baked by tools/gen_audio.gd (assets/audio/sfx_*.wav).
## Positional sounds use a pool of AudioStreamPlayer2D, so combat far from
## the camera is quieter; UI sounds play non-positionally. Each sound is
## rate-limited so a 30-ship volley doesn't clip.

const NAMES := ["laser", "torpedo", "shield", "boom", "boom_big", "build", "claim", "alert", "click", "deny",
	"alert_starbase", "alert_ships", "alert_planet", "alert_planet_lost", "alert_starbase_lost", "alert_resource", "alert_energy", "alert_starved",
	"note_ship", "note_tech", "note_building", "note_colony", "note_starbase", "note_save"]
const POOL_SIZE := 24
const MIN_GAP := {"laser": 0.04, "torpedo": 0.08, "shield": 0.05, "boom": 0.06, "boom_big": 0.1}

var _streams := {}
var _pool: Array[AudioStreamPlayer2D] = []
var _ui: AudioStreamPlayer
var _last := {}
var _next := 0

func _ready() -> void:
	for n in NAMES:
		_streams[n] = load("res://assets/audio/sfx_%s.wav" % n)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.max_distance = 1600.0
		p.attenuation = 1.6
		add_child(p)
		_pool.append(p)
	_ui = AudioStreamPlayer.new()
	add_child(_ui)

## Positional effect at a world position.
func play_at(name: String, pos: Vector2, volume_db: float = 0.0) -> void:
	var now := Game.now()
	if now - _last.get(name, -1.0) < MIN_GAP.get(name, 0.0):
		return
	_last[name] = now
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = _streams[name]
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.92, 1.08)
	p.play()

## Interface sound, not positional.
func play_ui(name: String) -> void:
	_ui.stream = _streams[name]
	_ui.play()
