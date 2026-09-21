extends Label
class_name InsufficientFundsNotice
## Center-screen "Insufficient Funds" flash -- shown by ResourceHUD.spend_resources
## itself (the one true entry point every resource spend in this project
## already goes through -- building placement, unit training, and now
## PathTreeModal's path-following cost) whenever a spend fails for the
## human player specifically, so every "tried to buy something, couldn't
## afford it" moment anywhere in the game gets the same feedback without
## needing its own call site wired up individually.
##
## Last child under UI in Main.tscn (see its own doc comment on sibling
## ordering) so it draws on top of every other HUD panel, not just
## the game world -- a Control with no layout siblings competing for the
## same z-order otherwise.

const DISPLAY_DURATION: float = 1.0
const REJECT_SFX_DURATION: float = 0.18
const REJECT_SFX_FREQUENCY: float = 180.0
const REJECT_SFX_MIX_RATE: int = 44100

var _hide_timer: SceneTreeTimer = null
var _sfx_player: AudioStreamPlayer = null
static var _reject_sfx: AudioStreamWAV = null

func _ready() -> void:
	visible = false
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.stream = _get_reject_sfx()
	add_child(_sfx_player)

## Shows the notice for DISPLAY_DURATION seconds and plays the reject
## beep. Safe to call repeatedly in quick succession -- each call just
## restarts the same 1-second window rather than stacking timers.
func show_notice(message: String = "Insufficient Funds") -> void:
	text = message
	visible = true
	_sfx_player.play()
	_hide_timer = get_tree().create_timer(DISPLAY_DURATION)
	_hide_timer.timeout.connect(_on_hide_timeout)

func _on_hide_timeout() -> void:
	visible = false

## A short descending-envelope tone generated on the fly (no audio asset
## exists for this yet -- see this project's own established "no art
## assets, generate a stand-in procedurally" convention, ResourceIcon.gd's
## drawn glyphs being the visual equivalent). Built once and cached
## statically -- every InsufficientFundsNotice instance (there's only
## ever one in practice, but no need to assume that) shares the same
## generated buffer rather than regenerating it per instance.
func _get_reject_sfx() -> AudioStreamWAV:
	if _reject_sfx == null:
		_reject_sfx = _build_reject_sfx()
	return _reject_sfx

static func _build_reject_sfx() -> AudioStreamWAV:
	var sample_count := int(REJECT_SFX_MIX_RATE * REJECT_SFX_DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / REJECT_SFX_MIX_RATE
		var envelope := 1.0 - float(i) / sample_count
		var sample := sin(TAU * REJECT_SFX_FREQUENCY * t) * envelope * 0.6
		var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = REJECT_SFX_MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
