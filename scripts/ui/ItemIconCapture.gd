extends Node
## Autoload singleton ("ItemIcons") that renders a still icon of any
## equippable item's actual 3D visual (see ItemDefs.get_visual_scene) on
## demand, the same "capture the real model instead of drawing a generic
## shape" idea IconCapture.gd already uses for unit portraits/selection-tray
## icons -- items just don't move, so unlike IconCapture this owns its own
## isolated SubViewport/World3D (own_world_3d = true) with its own lighting
## rather than sharing the main scene's, so it works regardless of which
## HUD panel or scene asks for an icon first.
##
## Icons are captured once per item_type and cached for the rest of the
## session (a sword always looks like a sword) -- callers go through
## request_icon() rather than reading the cache directly since a cache miss
## means a capture has to happen first (a couple of frames), not an
## instant result.

const VIEWPORT_SIZE := Vector2i(128, 128)
## How far back the camera sits, in multiples of the item's own bounding
## radius -- keeps small items (a dagger) and larger ones (a two-handed
## crossbow) both framed with comparable padding instead of one clipping
## and the other tiny in frame.
const DISTANCE_FACTOR := 1.8
const MIN_RADIUS := 0.25

@onready var viewport: SubViewport = $Viewport
@onready var camera: Camera3D = $Viewport/Camera3D

## item_type -> ImageTexture, once captured. Never evicted -- the item
## roster is small and fixed for a session, so this can't grow unbounded.
var _cache: Dictionary = {}
## item_type -> Array[Callable], callers still waiting on a capture that's
## queued or in flight (see request_icon).
var _pending_callbacks: Dictionary = {}
var _capture_queue: Array[String] = []
var _capturing: bool = false

## Fetches item_type's icon, calling `callback(texture: ImageTexture)`
## once it's available -- immediately (same call) if already cached,
## otherwise after the capture finishes (texture is null only if
## item_type isn't a recognized item). Always go through this rather than
## reading a cache directly; multiple callers can request the same
## item_type concurrently and will all be notified from one capture.
func request_icon(item_type: String, callback: Callable) -> void:
	if item_type.is_empty():
		return
	if _cache.has(item_type):
		callback.call(_cache[item_type])
		return
	if not _pending_callbacks.has(item_type):
		_pending_callbacks[item_type] = []
		_capture_queue.append(item_type)
	_pending_callbacks[item_type].append(callback)
	if not _capturing:
		_process_capture_queue()

## Works through _capture_queue one item at a time -- viewport/camera are
## shared, so capturing two items concurrently would have them race over
## the same render.
func _process_capture_queue() -> void:
	_capturing = true
	while not _capture_queue.is_empty():
		var item_type: String = _capture_queue.pop_front()
		var texture: ImageTexture = await _capture(item_type)
		_cache[item_type] = texture
		for callback: Callable in _pending_callbacks.get(item_type, []):
			callback.call(texture)
		_pending_callbacks.erase(item_type)
	_capturing = false

func _capture(item_type: String) -> ImageTexture:
	var scene: PackedScene = ItemDefs.get_visual_scene(item_type)
	if scene == null:
		return null
	var instance: Node3D = scene.instantiate()
	viewport.add_child(instance)
	await get_tree().process_frame
	var bounds := _compute_aabb(instance)
	var center := bounds.get_center()
	var radius: float = maxf(bounds.size.length() * 0.5, MIN_RADIUS)
	var distance := radius * DISTANCE_FACTOR
	camera.global_position = center + Vector3(distance, distance * 0.8, distance)
	camera.look_at(center, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	var vp_tex := viewport.get_texture()
	var img := vp_tex.get_image() if vp_tex != null else null
	instance.queue_free()
	if img == null:
		return null
	return ImageTexture.create_from_image(img)

## Combined AABB (in the capture viewport's world space) of every
## MeshInstance3D under `node`, recursively -- items are small hand-built
## meshes with no single top-level bounding volume of their own, so this
## has to walk the tree rather than reading one property.
func _compute_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var has_bounds := false
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null:
			var mesh_aabb: AABB = child.global_transform * child.mesh.get_aabb()
			result = mesh_aabb if not has_bounds else result.merge(mesh_aabb)
			has_bounds = true
		if child is Node3D:
			var child_aabb := _compute_aabb(child)
			if child_aabb.size != Vector3.ZERO:
				result = child_aabb if not has_bounds else result.merge(child_aabb)
				has_bounds = true
	return result
