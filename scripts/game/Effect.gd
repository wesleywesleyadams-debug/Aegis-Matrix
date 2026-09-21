class_name Effect
extends Sprite2D
## One-shot sprite-sheet animation (explosions, shield flashes) that frees
## itself when done.

var fps: float = 14.0
var fade: bool = false
var _t: float = 0.0

func _process(delta: float) -> void:
	_t += delta
	if hframes > 1:
		var f := int(_t * fps)
		if f >= hframes:
			queue_free()
			return
		frame = f
	else:
		var life := 1.0 / fps * 4.0
		modulate.a = 1.0 - _t / life
		if _t >= life:
			queue_free()
