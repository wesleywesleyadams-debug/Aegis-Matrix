extends Control
## Draws a live blip for every unit/building at its ground-plane position,
## projected into the same isometric diamond shape the terrain itself
## forms under this game's camera -- world (x, z) -> local (x + z) on the
## diamond's horizontal axis, (z - x) on its vertical axis, both then
## scaled by GROUND_HALF_EXTENT/FILL_HALF_DIAGONAL. Derived empirically
## via Camera3D.unproject_position() on known world points (see git
## history) rather than hand-deriving the camera's rotation matrices --
## an earlier hand-derived version got the axis assignment backwards
## twice in a row, so this reads straight off Godot's own projection
## instead of re-deriving it.
##
## Also the click target for "recenter the camera here" -- left-clicking
## anywhere on the diamond inverts that same projection back to a world
## point and shifts CameraRig so the current view centers on it. This is
## a Control (not a plain Node2D) specifically so it can receive that
## click at all -- Border/Fill (Polygon2D, plain 2D nodes) can't.
##
## CENTER matches Border/Fill's own Polygon2D position (the diamond's
## center within this Control's rect) -- every draw call and the click
## handler both offset through it, so local (0, 0) in projection terms
## lines up with world (0, 0) regardless of where this Control's own
## top-left corner sits.

const CENTER: Vector2 = Vector2(210, 120)
const GROUND_HALF_EXTENT: float = 30.0
const FILL_HALF_DIAGONAL: Vector2 = Vector2(199.0, 109.0)
## Blips are small squares, not circles -- reads as a cleaner, more
## "map icon" look at this size than a circle does, and matches
## strategy-game minimap convention (a dot per unit/building).
const BLIP_SIZE: float = 5.0
## Trees (World.gd, "world" group) always show this fixed dark green,
## not Entity.PLAYER_COLORS[3] (Nature's own, lighter neutral green
## used for tabard/health-bar identity) -- scenery, not a faction, so
## it reads distinctly from an actual Nature-owned unit/building on
## the same map.
const TREE_COLOR: Color = Color(0.08, 0.28, 0.1, 1)
const VIEW_BOUNDS_COLOR: Color = Color(1, 1, 1, 0.85)
const VIEW_BOUNDS_WIDTH: float = 2.0

## |x + z| and |z - x| both reach exactly 2 * GROUND_HALF_EXTENT at the
## very edge of the ground plane (at whichever corner maximizes each) --
## see the class doc comment.
const MAX_RAW: float = 2.0 * GROUND_HALF_EXTENT

## RTSController's own camera/rig -- Main.tscn's scene root owns them
## directly as $CameraRig and $CameraRig/Camera3D, so reached the same
## way here rather than threading a reference through export vars for a
## node this far removed in the tree.
@onready var camera: Camera3D = get_tree().current_scene.get_node("CameraRig/Camera3D")
@onready var camera_rig: Node3D = get_tree().current_scene.get_node("CameraRig")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	for group in ["units", "buildings"]:
		for entity in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(entity):
				continue
			var color: Color = Entity.PLAYER_COLORS.get(entity.player_id, Color.WHITE)
			_draw_blip(entity.global_position, color)
	for tree in get_tree().get_nodes_in_group("world"):
		if not is_instance_valid(tree):
			continue
		_draw_blip(tree.global_position, TREE_COLOR)
	_draw_view_bounds()

func _draw_blip(world_pos: Vector3, color: Color) -> void:
	var center := CENTER + _project(world_pos)
	draw_rect(Rect2(center - Vector2.ONE * BLIP_SIZE / 2.0, Vector2.ONE * BLIP_SIZE), color)

## Outlines the ground-plane quadrilateral the camera's own viewport
## rectangle actually covers right now, so the player can tell where on
## the map their current view sits -- each screen corner raycast down
## to the Y=0 ground plane (same "click a point on the ground" approach
## RTSController's own raycasts use), then projected the same way a
## unit/building's blip is.
func _draw_view_bounds() -> void:
	var viewport_rect := get_viewport().get_visible_rect()
	var screen_corners := [
		viewport_rect.position,
		Vector2(viewport_rect.end.x, viewport_rect.position.y),
		viewport_rect.end,
		Vector2(viewport_rect.position.x, viewport_rect.end.y),
	]
	var points: PackedVector2Array = []
	for screen_pos in screen_corners:
		points.append(CENTER + _project(_ground_point(screen_pos)))
	points.append(points[0])
	draw_polyline(points, VIEW_BOUNDS_COLOR, VIEW_BOUNDS_WIDTH)

## Left-clicking anywhere ON THE DIAMOND (Frame's own Control rect is a
## bounding box around it, not the diamond's actual shape -- a click in
## one of its corners, outside the diamond, isn't a click on any real
## terrain and is ignored rather than extrapolated to a wildly
## out-of-bounds world point) shifts CameraRig so the ground point under
## the cursor becomes the new center of the actual view -- computed as a
## delta from wherever the view is currently centered (the ground point
## straight down the middle of the viewport right now) rather than
## assuming any fixed relationship between CameraRig's own position and
## its look-at point, so this works regardless of current zoom/pan.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var local_click: Vector2 = event.position - CENTER
		if absf(local_click.x) / FILL_HALF_DIAGONAL.x + absf(local_click.y) / FILL_HALF_DIAGONAL.y > 1.0:
			return
		accept_event()
		var target := _unproject(local_click)
		var current_center := _ground_point(get_viewport().get_visible_rect().size / 2.0)
		var delta := target - current_center
		delta.y = 0.0
		camera_rig.global_position += delta

## Where the camera ray through `screen_pos` crosses the Y=0 ground
## plane -- valid for this game's fixed downward-angled orthographic
## camera, which never points level with or above the horizon.
func _ground_point(screen_pos: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var t := -origin.y / direction.y
	return origin + direction * t

func _project(world_pos: Vector3) -> Vector2:
	var raw := Vector2(world_pos.x + world_pos.z, world_pos.z - world_pos.x)
	return raw / MAX_RAW * FILL_HALF_DIAGONAL

## Inverse of _project() -- solves (x + z, z - x) = raw back to (x, z).
func _unproject(local_pos: Vector2) -> Vector3:
	var raw := local_pos / FILL_HALF_DIAGONAL * MAX_RAW
	var x := (raw.x - raw.y) / 2.0
	var z := (raw.x + raw.y) / 2.0
	return Vector3(x, 0.0, z)
