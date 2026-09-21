extends RefCounted
class_name RaycastService
## Extracted from RTSController.gd -- every screen-position raycast/
## click-target-resolution helper in one place. These were the most
## "called into" functions in that file (nearly every other
## responsibility cluster -- input dispatch, move/attack orders, drag/
## drop, selection, hover -- called through them) despite depending on
## almost nothing of their own: just a Camera3D and the "units"/
## "buildings"/"items" groups. RTSController keeps one instance of this
## (built once `camera` is ready) and forwards its own identically-named
## methods to it unchanged, so no other call site anywhere in that file
## needed to change.

## Widens the effective click target for units/buildings/items beyond
## their exact (fairly narrow) collision shape, only used once a direct
## raycast against that shape has already missed -- finds whichever
## visible candidate's world position passes closest to the click ray,
## within this tolerance, measured at roughly chest height rather than at
## the feet, since that's where most of a standing entity's visible bulk
## actually is.
const UNIT_CLICK_TOLERANCE: float = 0.5
const UNIT_CLICK_HEIGHT: float = 0.9

var _camera: Camera3D

func _init(camera: Camera3D) -> void:
	_camera = camera

## Shared camera-ray builder for every screen-position raycast this
## service does. Items live on Area3D (see WorldItem.ITEM_MASK),
## everything else (ground/units/buildings) on ordinary PhysicsBody3D,
## hence the two collide_with_* flags -- default to the body-only case
## everyone else uses.
func raycast(screen_pos: Vector2, mask: int, collide_with_areas: bool = false, collide_with_bodies: bool = true) -> Dictionary:
	var space_state := _camera.get_world_3d().direct_space_state
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.collide_with_areas = collide_with_areas
	query.collide_with_bodies = collide_with_bodies
	return space_state.intersect_ray(query)

func raycast_unit(screen_pos: Vector2, unit_mask: int) -> Node3D:
	var hit := raycast(screen_pos, unit_mask)
	if not hit.is_empty():
		var collider: Node3D = hit["collider"]
		# Fog of war hides this entity -- an entity you can't see shouldn't
		# be clickable either.
		if collider.visible:
			return collider
	return find_nearest_unit_to_ray(screen_pos)

func find_nearest_unit_to_ray(screen_pos: Vector2) -> Node3D:
	var origin := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var best: Node3D = null
	var best_dist := UNIT_CLICK_TOLERANCE
	var tree := _camera.get_tree()
	var candidates: Array = tree.get_nodes_in_group("units") + tree.get_nodes_in_group("buildings")
	for entity in candidates:
		if not is_instance_valid(entity) or not entity.visible:
			continue
		var target_point: Vector3 = entity.global_position + Vector3(0, UNIT_CLICK_HEIGHT, 0)
		var t := (target_point - origin).dot(dir)
		if t <= 0.0:
			continue
		var closest_point_on_ray := origin + dir * t
		var dist := closest_point_on_ray.distance_to(target_point)
		if dist < best_dist:
			best_dist = dist
			best = entity
	return best

## Right-clicking any unit not owned by the human player counts as an
## attack target -- anything else is fair game regardless of an eventual
## real faction/ally system.
func raycast_enemy_unit(screen_pos: Vector2, unit_mask: int) -> Node3D:
	var unit := raycast_unit(screen_pos, unit_mask)
	if unit == null or unit.is_player_controlled():
		return null
	return unit

## Any building under the click, regardless of owner -- used for gather-
## point targeting, which cares about "is this a building" rather than
## "is this an enemy."
func raycast_building(screen_pos: Vector2, unit_mask: int) -> Node3D:
	var unit := raycast_unit(screen_pos, unit_mask)
	if unit == null or not (unit is Building):
		return null
	return unit

## Raycasts for a WorldItem under the cursor -- items live on
## WorldItem.ITEM_MASK (an Area3D, not a body), so this needs its own
## query with collide_with_areas on. Falls back to the same click-
## tolerance widening raycast_unit gets, once a direct hit against the
## item's own (fairly small) pickup collider misses, so right-clicking
## just next to a pickup still collects it.
func raycast_item(screen_pos: Vector2, item_mask: int) -> WorldItem:
	var hit := raycast(screen_pos, item_mask, true, false)
	if not hit.is_empty():
		var collider: Object = hit["collider"]
		if collider is WorldItem:
			return collider
	return find_nearest_item_to_ray(screen_pos)

## Same closest-point-to-ray widening find_nearest_unit_to_ray does for
## units/buildings, applied to world items instead -- only used once a
## direct raycast against the item's own collider has already missed.
func find_nearest_item_to_ray(screen_pos: Vector2) -> WorldItem:
	var origin := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var best: WorldItem = null
	var best_dist := UNIT_CLICK_TOLERANCE
	for item in _camera.get_tree().get_nodes_in_group("items"):
		if not is_instance_valid(item) or not item.visible:
			continue
		var target_point: Vector3 = item.global_position + Vector3(0, UNIT_CLICK_HEIGHT, 0)
		var t := (target_point - origin).dot(dir)
		if t <= 0.0:
			continue
		var closest_point_on_ray := origin + dir * t
		var dist := closest_point_on_ray.distance_to(target_point)
		if dist < best_dist:
			best_dist = dist
			best = item
	return best
