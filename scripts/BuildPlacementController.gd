extends RefCounted
class_name BuildPlacementController
## Extracted from RTSController.gd -- everything to do with arming
## building placement (B), previewing a translucent ghost box snapped to
## the grid, and confirming placement. This was one of the more
## self-contained responsibility clusters in that file (its own ghost/
## snap/validity state, touched by nothing else) but still needed
## `_root` (the scene's own root, for `$Buildings`/`$Wall` lookups and
## as the ghost mesh's parent) passed in explicitly rather than assumed,
## since a plain helper object has no scene-tree position of its own to
## resolve relative node paths against the way the original methods
## (as RTSController's own) implicitly could.

## World-space size of one grid cell -- matches DebugGrid's own cell_size
## shader parameter (see Main.tscn) exactly, so a snapped building's edges
## land right on the drawn grid lines rather than off by some unrelated
## amount.
const BUILD_GRID_SIZE: float = 2.6

var _root: Node3D
var _raycast_service: RaycastService
## Called with the newly-placed building once confirm_placement() spawns
## it -- lets RTSController wire up its storage_changed signal the same
## way it does for every other building, without this controller needing
## to know anything about that signal itself.
var _on_building_placed: Callable

## Which EditorPalette "Building" entry set_pending's next arm will place
## -- defaults to the plain generic building (this controller's own
## original, only-ever building type before TaskPanel grew a real build
## submenu). Set via set_building_type() before calling set_pending(true)
## -- see RTSController._on_build_type_selected.
var building_type: String = "building"

## True while the player has armed building placement and is positioning
## the ghost preview -- see RTSController._unhandled_input's KEY_B
## handling.
var pending: bool = false
## Translucent preview box following the cursor while pending is true --
## a standalone MeshInstance3D rather than a real ParentBuilding
## instance, since a ghost needs none of a real building's health/
## selection/nav-agent/collision, just a box to preview placement with.
## Built lazily (see _get_ghost) and reused across placements rather
## than freed/recreated each time.
var _ghost: MeshInstance3D = null
var _ghost_material: StandardMaterial3D = null
## Where the ghost is currently snapped to, updated every update_ghost()
## call while armed -- read by confirm_placement() so it doesn't need to
## redo the raycast/snap right as the player commits.
var _ghost_position: Vector3 = Vector3.INF
var _ghost_valid: bool = false

func _init(root: Node3D, raycast_service: RaycastService, on_building_placed: Callable) -> void:
	_root = root
	_raycast_service = raycast_service
	_on_building_placed = on_building_placed

## Toggles/sets building-placement arming (B). Mutually exclusive with
## attack-move (see RTSController._unhandled_input, which disarms the
## other before arming this one) -- both are "pending click" modes and
## having two armed at once would make a click ambiguous. Shows/hides
## the ghost preview.
func set_pending(p: bool, mouse_pos: Vector2, ground_mask: int) -> void:
	pending = p
	_get_ghost().visible = p
	if p:
		_resize_ghost_for_current_type()
		update_ghost(mouse_pos, ground_mask)

## Selects which building type the next set_pending(true) arms placement
## for -- call before arming, e.g. from a build-submenu icon press.
func set_building_type(type_id: String) -> void:
	building_type = type_id

## Resizes the ghost box to match building_type's real footprint (e.g.
## Castle's 5x5) so the preview accurately shows how much space the
## building that's actually about to be placed will take up, rather than
## always previewing at the generic building's 1x1.
func _resize_ghost_for_current_type() -> void:
	var footprint: float = BuildingDefs.get_footprint_tiles(building_type)
	var ghost := _get_ghost()
	var mesh: BoxMesh = ghost.mesh
	mesh.size = Vector3(BUILD_GRID_SIZE * footprint, 2.6, BUILD_GRID_SIZE * footprint)

## Lazily builds the translucent preview box the first time it's needed,
## reusing it for every placement after that rather than recreating it
## each time B is pressed.
func _get_ghost() -> MeshInstance3D:
	if _ghost != null:
		return _ghost
	_ghost = MeshInstance3D.new()
	_ghost.visible = false
	var mesh := BoxMesh.new()
	mesh.size = Vector3(BUILD_GRID_SIZE, 2.6, BUILD_GRID_SIZE)
	_ghost.mesh = mesh
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = _ghost_material
	_root.add_child(_ghost)
	return _ghost

## Snaps `world_pos` to the center of the nearest grid cell a
## `footprint_tiles`-wide square building could occupy -- an odd footprint
## (the default, 1) centers on a cell, landing on the half-cell offset
## grid lines are drawn at (see debug_grid.gdshader); an even footprint
## (e.g. a 4x4 building) instead centers exactly on a grid-line
## intersection, so its edges still land on grid lines rather than
## straddling one. Both are really the same formula: snap the building's
## own min-corner to the nearest whole grid cell, then re-add half its own
## footprint width to get back its center.
func snap_to_grid(world_pos: Vector3, footprint_tiles: float = 1.0) -> Vector3:
	var half_tiles := footprint_tiles / 2.0
	var cell_x: float = roundf(world_pos.x / BUILD_GRID_SIZE - half_tiles)
	var cell_z: float = roundf(world_pos.z / BUILD_GRID_SIZE - half_tiles)
	return Vector3(
		(cell_x + half_tiles) * BUILD_GRID_SIZE,
		0.0,
		(cell_z + half_tiles) * BUILD_GRID_SIZE
	)

## True if a `footprint_tiles`-wide building centered at (already-snapped)
## `pos` wouldn't overlap the ground's own edge, another building, or the
## map's static Wall obstacle. Doesn't check units -- those move out of the
## way on their own and aren't a real placement obstruction the way a
## permanent structure is.
func is_spot_valid(pos: Vector3, footprint_tiles: float = 1.0) -> bool:
	var half: float = footprint_tiles * BUILD_GRID_SIZE / 2.0
	# Matches Main.tscn's Ground BoxMesh half-extent (180x180, centered on
	# the origin).
	var ground_half := 90.0
	if absf(pos.x) > ground_half - half or absf(pos.z) > ground_half - half:
		return false
	var flat_pos := Vector2(pos.x, pos.z)
	for building in _root.get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building):
			continue
		var other_half: float = BUILD_GRID_SIZE / 2.0
		var flat_other := Vector2(building.global_position.x, building.global_position.z)
		if absf(flat_pos.x - flat_other.x) < half + other_half and absf(flat_pos.y - flat_other.y) < half + other_half:
			return false
	var wall := _root.get_node_or_null("Wall")
	if wall != null:
		var wall_flat := Vector2(wall.global_position.x, wall.global_position.z)
		# Wall is 3x0.4 (see Main.tscn) -- treat it as a generous 2x2
		# footprint for this check rather than reading its exact box size,
		# comfortably covering it either way.
		if absf(flat_pos.x - wall_flat.x) < half + 1.0 and absf(flat_pos.y - wall_flat.y) < half + 1.0:
			return false
	return true

## Raycasts the ground under the cursor, snaps it to the grid, and updates
## the ghost's position/color to match -- called every frame while
## pending is true. No-op (ghost just stays wherever it last was) if
## the cursor isn't currently over the ground at all.
func update_ghost(mouse_pos: Vector2, ground_mask: int) -> void:
	var hit := _raycast_service.raycast(mouse_pos, ground_mask)
	if hit.is_empty():
		return
	var footprint: float = BuildingDefs.get_footprint_tiles(building_type)
	var snapped := snap_to_grid(hit["position"], footprint)
	_ghost_position = snapped
	_ghost_valid = is_spot_valid(snapped, footprint)
	var ghost := _get_ghost()
	ghost.global_position = snapped + Vector3(0, 1.3, 0)
	_ghost_material.albedo_color = (
		Color(0.3, 1.0, 0.4, 0.45) if _ghost_valid else Color(1.0, 0.25, 0.25, 0.45)
	)

## The left-click that fires once building placement is armed -- spawns a
## real building at the ghost's current (already snapped) position if
## valid, then disarms back to normal click behavior either way. Does
## nothing (stays armed) on an invalid spot, so a misplaced click doesn't
## silently cancel the whole thing.
func confirm_placement() -> void:
	if not _ghost_valid or _ghost_position == Vector3.INF:
		return
	# First real spender of this game's 4x economy (see
	# ResourceHUD.spend_resources's own doc comment) -- refuses (stays
	# armed, same no-op UX as an invalid spot) rather than placing for
	# free if the human player can't afford it.
	var resource_hud: ResourceHUD = _root.get_node("UI/ResourceHUD")
	var cost: Dictionary = BuildingDefs.get_cost(building_type)
	if not resource_hud.spend_resources(GameState.human_player_id, cost):
		return
	var building: Node3D = EditorPalette.instantiate("Building", building_type)
	if building == null:
		resource_hud.refund_resources(GameState.human_player_id, cost)
		return
	# force_readable_name=true so a name collision with an existing
	# same-type building (near-guaranteed -- Main.tscn's hand-placed
	# roster already has nodes named "Hut"/"Wall"/etc, and every other
	# player-placed building of the same type shares it too) resolves to
	# a readable "Hut2"/"Hut3" the way Godot's own editor does it, rather
	# than silently falling back to add_child()'s default behavior: an
	# anonymous internal "@CharacterBody3D@" name that Entity.display_name_for
	# (and this building's own hover tooltip) has nothing meaningful to show.
	_root.get_node("Buildings").add_child(building, true)
	building.global_position = _ghost_position
	building.player_id = GameState.human_player_id
	_on_building_placed.call(building)
	pending = false
	_get_ghost().visible = false
