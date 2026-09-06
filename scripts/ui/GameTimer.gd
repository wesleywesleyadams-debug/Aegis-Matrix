extends Label
## Elapsed match time, top-center of the screen. Uses the default
## PROCESS_MODE_INHERIT, so _process simply stops running while
## get_tree().paused is true -- no manual pause check needed here.

var _elapsed: float = 0.0

func _process(delta: float) -> void:
	_elapsed += delta
	_update_text()

func get_elapsed() -> float:
	return _elapsed

## Used when restoring a saved match -- resumes the display from wherever
## the save was taken rather than the usual count-up-from-zero.
func set_elapsed(seconds: float) -> void:
	_elapsed = seconds
	_update_text()

func _update_text() -> void:
	var total_seconds := int(_elapsed)
	var hours := total_seconds / 3600
	var minutes := (total_seconds / 60) % 60
	var seconds := total_seconds % 60
	if hours > 0:
		text = "%d:%02d:%02d" % [hours, minutes, seconds]
	else:
		text = "%d:%02d" % [minutes, seconds]
