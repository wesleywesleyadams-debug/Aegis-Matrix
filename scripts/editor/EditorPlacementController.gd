extends RefCounted
class_name EditorPlacementController
## Map editor's own arm/ghost-preview/snap/confirm placement flow --
## generalized from BuildPlacementController.gd (see that file's own doc
## comment) to place ANY EditorPalette category/type_id at an arbitrary
## player_id, rather than one hardcoded building scene for the human
## player only. Reuses the exact same grid-snap math and ghost-preview
## approach since there's no reason to invent a second one.

const BUILD_GRID_SIZE: float = 2.6
## Matches Main.tscn/MapEditor.tscn's Ground BoxMesh half-extent (180x180,
## centered on the origin) -- same bound BuildPlacementController.
## is_spot_valid checks, so a building can't be placed (or snapped) past
## the edge of the map here either.
const GROUND_HALF_EXTENT: float = 90.0

var _root: Node3D
var _raycast_service: RaycastService

## What's currently armed to place -- category/type_id resolve through
## EditorPalette; player_id is stamped onto the placed instance if it
## has that property (units/buildings do, world scenery doesn't).
var pending: bool = false
## Public (unlike the rest of this controller's internal state) since
## MapEditorController needs to know what was just placed, to record
## alongside the placed instance for its own save-file bookkeeping.
var category: String = ""
var type_id: String = ""
var _player_id: int = 1

var _ghost: Node3D = null
var _ghost_position: Vector3 = Vector3.INF
## Only Building placements are ever actually invalidated (see
## _is_in_bounds) -- units/world scenery have nothing to be invalid
## against, so this stays true for them and the ghost never tints red.
var _ghost_valid: bool = true
var _ghost_materials: Array[StandardMaterial3D] = []
## How wide (in BUILD_GRID_SIZE tiles) the currently-armed placement is --
## 1.0 for everything except a Building whose BuildingDefs entry says
## otherwise (e.g. Castle's 5.0), resolved once in arm() rather than
## re-looked-up every frame in update_ghost().
var _footprint_tiles: float = 1.0

func _init(root: Node3D, raycast_service: RaycastService) -> void:
	_root = root
	_raycast_service = raycast_service

## Arms placement for `category`+`type_id` (from EditorPalette) owned by
## `player_id`. Rebuilds the ghost every time (unlike
## BuildPlacementController's single reused box) since different
## categories need genuinely different preview visuals -- a real (if
## translucent) instance of the actual scene reads far better in an
## editor tool than one generic box would for a tree vs. a castle vs. a
## peasant.
func arm(arm_category: String, arm_type_id: String, player_id: int) -> void:
	_clear_ghost()
	category = arm_category
	type_id = arm_type_id
	_player_id = player_id
	_footprint_tiles = BuildingDefs.get_footprint_tiles(type_id) if category == "Building" else 1.0
	pending = true
	_ghost = EditorPalette.instantiate(category, type_id)
	if _ghost == null:
		pending = false
		return
	_make_ghost_translucent(_ghost)
	_root.add_child(_ghost)

func disarm() -> void:
	pending = false
	_clear_ghost()

func _clear_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_materials.clear()

## Swaps every visible surface of the ghost instance to a translucent
## unshaded material -- walks all MeshInstance3D descendants rather than
## assuming a fixed shape, since ghost previews now come from arbitrary
## unit/building/world scenes instead of one hand-built box (which can
## have more than one MeshInstance3D, e.g. Castle.tscn's several parts --
## every material created here is kept in _ghost_materials so
## _update_ghost_tint can recolor all of them together).
func _make_ghost_translucent(node: Node) -> void:
	if node is CollisionObject3D:
		node.set_deferred("collision_layer", 0)
		node.set_deferred("collision_mask", 0)
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		node.material_override = mat
		_ghost_materials.append(mat)
	for child in node.get_children():
		_make_ghost_translucent(child)

## One shared tint for every material a ghost's mesh parts got in
## _make_ghost_translucent -- green while a Building placement is on the
## grid and inside the map, red once _is_in_bounds says otherwise (see
## update_ghost). Units/world scenery never call this with anything but
## true, so they stay green -- there's nothing for them to be invalid
## against.
func _update_ghost_tint(valid: bool) -> void:
	var color := Color(0.3, 1.0, 0.4, 0.55) if valid else Color(1.0, 0.25, 0.25, 0.55)
	for mat in _ghost_materials:
		mat.albedo_color = color

## Exactly BuildPlacementController.snap_to_grid's own formula (see its
## doc comment for the odd-vs-even-footprint reasoning) -- snaps the
## object's own CENTER so that a footprint_tiles-wide square centered
## there always lands its edges exactly on the visual grid's drawn lines
## (debug_grid.gdshader draws a line at every world-space multiple of
## BUILD_GRID_SIZE), not just somewhere near them. The naive "round
## straight to the nearest multiple of BUILD_GRID_SIZE" this used to do
## instead puts an odd (e.g. 1-tile) footprint's edges exactly BETWEEN two
## grid lines rather than on them -- looks snapped but isn't actually
## aligned with what's drawn.
func snap_to_grid(world_pos: Vector3, footprint_tiles: float = 1.0) -> Vector3:
	var half_tiles := footprint_tiles / 2.0
	var cell_x: float = roundf(world_pos.x / BUILD_GRID_SIZE - half_tiles)
	var cell_z: float = roundf(world_pos.z / BUILD_GRID_SIZE - half_tiles)
	return Vector3(
		(cell_x + half_tiles) * BUILD_GRID_SIZE,
		0.0,
		(cell_z + half_tiles) * BUILD_GRID_SIZE
	)

## True if a footprint_tiles-wide square centered at (already-snapped)
## `pos` stays within the ground's own edge -- the same bound
## BuildPlacementController.is_spot_valid checks for the real "B" build
## key, applied here only to Building placements (see arm(); everything
## else keeps _footprint_tiles at 1.0 but is never actually checked, so
## a unit/tree can still be placed anywhere on the ground including near
## its edge).
func _is_in_bounds(pos: Vector3) -> bool:
	if category != "Building":
		return true
	var half: float = _footprint_tiles * BUILD_GRID_SIZE / 2.0
	return absf(pos.x) <= GROUND_HALF_EXTENT - half and absf(pos.z) <= GROUND_HALF_EXTENT - half

func update_ghost(mouse_pos: Vector2, ground_mask: int) -> void:
	if _ghost == null:
		return
	var hit := _raycast_service.raycast(mouse_pos, ground_mask)
	if hit.is_empty():
		return
	var snapped := snap_to_grid(hit["position"], _footprint_tiles)
	_ghost_position = snapped
	_ghost.global_position = snapped
	_ghost_valid = _is_in_bounds(snapped)
	_update_ghost_tint(_ghost_valid)

## Spawns a real instance at the ghost's last snapped position and
## stamps player_id, then re-arms the *same* category/type_id so placing
## several of the same thing in a row doesn't require reselecting it
## from the palette each time -- matches how a level editor's "stamp"
## tool conventionally behaves.
func confirm_placement() -> Node3D:
	if not pending or _ghost_position == Vector3.INF or not _ghost_valid:
		return null
	var instance := EditorPalette.instantiate(category, type_id)
	if instance == null:
		return null
	# force_readable_name=true -- see BuildPlacementController.confirm_placement's
	# identical fix for why (a colliding name otherwise falls back to an
	# anonymous "@ClassName@N" Node.name, which every hover tooltip/display
	# name has nothing meaningful to show for).
	_root.add_child(instance, true)
	instance.global_position = _ghost_position
	if "player_id" in instance:
		instance.player_id = _player_id
	return instance
