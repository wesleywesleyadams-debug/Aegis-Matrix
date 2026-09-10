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
@export var zoom_max: float = 16.0
@export var edge_pan_margin: int = 12
@export var edge_pan_enabled: bool = true

## How far the rig's own XZ position may stray from the map center --
## matches Main.tscn's Ground BoxMesh half-extent (60x60, centered on
## the origin). Without this, edge-panning (or Minimap's click-to-
## recenter, which also calls clamp_to_map() -- see its own git
## history) can push the camera arbitrarily far off the map, past the
## ground plane entirely, showing nothing but sky/void.
const PAN_BOUND: float = 30.0

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

	_clamp_to_map()

## Keeps the ground point at the exact center of the screen from ever
## wandering past the map's edge, regardless of what moved the rig --
## edge-panning, keyboard panning, or Minimap's click-to-recenter (which
## clamps its own target the same way before computing its delta, but
## this is the backstop for anything else that ever moves the rig).
## Shifting the rig by delta V (with V.y == 0) shifts every ground-ray
## intersection by that exact same V (the rig only translates, never
## rotates, and this camera's rays are parallel -- orthographic -- so a
## uniform origin shift moves every intersection uniformly) -- so
## whatever correction brings the view-center back in bounds is exactly
## the same correction applied directly to the rig's own position.
func _clamp_to_map() -> void:
	var view_center := _ground_point(get_viewport().get_visible_rect().size / 2.0)
	var clamped_x := clampf(view_center.x, -PAN_BOUND, PAN_BOUND)
	var clamped_z := clampf(view_center.z, -PAN_BOUND, PAN_BOUND)
	global_position += Vector3(clamped_x - view_center.x, 0.0, clamped_z - view_center.z)

## Where the camera ray through `screen_pos` crosses the Y=0 ground
## plane -- valid for this game's fixed downward-angled orthographic
## camera, which never points level with or above the horizon. Same
## approach Minimap.gd uses for its view-bounds outline/click-to-recenter.
func _ground_point(screen_pos: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var t := -origin.y / direction.y
	return origin + direction * t

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cam_zoom_in"):
		_zoom_size = clamp(_zoom_size - zoom_speed, zoom_min, zoom_max)
		_apply_zoom()
	elif event.is_action_pressed("cam_zoom_out"):
		_zoom_size = clamp(_zoom_size + zoom_speed, zoom_min, zoom_max)
		_apply_zoom()

func _apply_zoom() -> void:
	camera.size = _zoom_size
