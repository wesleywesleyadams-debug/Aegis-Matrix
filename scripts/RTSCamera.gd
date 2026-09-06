extends Node3D
## Pans and zooms a fixed-angle top-down camera rig over the ground plane.
## Uses orthographic projection (see Camera3D.projection in the scene) so
## units read as the same size no matter where they sit on screen -- with
## perspective, anything farther from the camera (e.g. higher up the
## screen, given the downward tilt) would look smaller, which is not how
## classic isometric RTS rendering like Age of Empires 2 looks or reads.
## Because of that, zooming an orthographic camera has to change its
## `size` (the world-space extent it views) rather than dolly the camera
## closer/farther -- moving an orthographic camera along its view axis
## doesn't change apparent scale at all, unlike a perspective one.

@export var pan_speed: float = 18.0
@export var zoom_speed: float = 2.0
@export var zoom_min: float = 6.0
@export var zoom_max: float = 30.0
@export var edge_pan_margin: int = 12
@export var edge_pan_enabled: bool = true

@onready var camera: Camera3D = $Camera3D

var _zoom_size: float = 16.0

func _ready() -> void:
	_zoom_size = camera.size
	_apply_zoom()

func _process(delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_action_strength("cam_right") - Input.get_action_strength("cam_left")
	input_dir.y = Input.get_action_strength("cam_down") - Input.get_action_strength("cam_up")

	if edge_pan_enabled and input_dir == Vector2.ZERO:
		var mouse_pos := get_viewport().get_mouse_position()
		var vp_size := get_viewport().get_visible_rect().size
		if get_viewport().has_focus():
			if mouse_pos.x <= edge_pan_margin:
				input_dir.x = -1.0
			elif mouse_pos.x >= vp_size.x - edge_pan_margin:
				input_dir.x = 1.0
			if mouse_pos.y <= edge_pan_margin:
				input_dir.y = -1.0
			elif mouse_pos.y >= vp_size.y - edge_pan_margin:
				input_dir.y = 1.0

	if input_dir != Vector2.ZERO:
		# Pan along world-flat forward/right so panning stays consistent
		# regardless of the camera's downward tilt.
		var forward := -global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		var move := (right * input_dir.x + forward * -input_dir.y) * pan_speed * delta
		global_position += move

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cam_zoom_in"):
		_zoom_size = clamp(_zoom_size - zoom_speed, zoom_min, zoom_max)
		_apply_zoom()
	elif event.is_action_pressed("cam_zoom_out"):
		_zoom_size = clamp(_zoom_size + zoom_speed, zoom_min, zoom_max)
		_apply_zoom()

func _apply_zoom() -> void:
	camera.size = _zoom_size
