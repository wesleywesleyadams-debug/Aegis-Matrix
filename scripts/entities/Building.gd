extends Entity
class_name Building
## A stationary structure -- NOT a Unit (see Entity, the shared base both
## extend) -- so it's excluded from anything that specifically sweeps up
## "units" (the "units" group, the lobby's starting-unit-count/roster
## split, etc.), joining the "buildings" group instead. It still has
## health/belt/selection/team-color/attack-when-in-range, since all of
## that lives in Entity; Entity's own defaults already never move it,
## so there's nothing left to override here beyond group membership.

## Where units produced by this building (once production exists) should
## walk to after spawning -- in order, same as a unit's queued waypoints.
## Set by right-clicking while this building is selected (plain click
## replaces the whole queue with one point; shift-click appends another),
## see RTSController._handle_right_click. Each entry gets a numbered flag,
## the same visual language as a unit move-order queue.
var gather_points: Array[Vector3] = []
var _gather_flags: Array[Node3D] = []

## Items this building is holding (see BuildingStoragePanel, shown while
## this building is selected) -- one entry per item, in the order they
## were stored, up to MAX_STORAGE_SLOTS (no stacking -- 6 items takes 6
## slots regardless of type). Units drop equipped items in here by
## dragging them onto the building (see RTSController._place_dragged_item)
## instead of the item landing on the ground the way dropping on empty
## space or another unit does.
signal storage_changed(building: Building)
var stored_items: Array[String] = []
const MAX_STORAGE_SLOTS: int = 6

## Angle passed as WorldItem.spawn_pickup's `facing_angle` when ejecting a
## stored item back onto the ground (see
## RTSController._on_storage_item_right_clicked) -- a building never
## rotates (model_root.rotation.y is always 0, unlike a Unit's), so using
## that directly would always eject straight out one fixed cardinal side.
## This picks a diagonal instead, landing the item at the building's own
## bottom corner (the one nearest the camera in this game's fixed
## isometric view) rather than the middle of a side, which reads more like
## an actual doorstep/loading-corner than a point floating off one wall.
const STORAGE_EJECT_ANGLE: float = 3.0 * PI / 4.0

## Adds `item_type` if there's a free slot, and reports whether it
## actually fit -- caller decides what happens to the item if not (e.g.
## _on_thrown_item_landed leaves it as a normal ground pickup instead of
## handing it over when storage is already full).
func store_item(item_type: String) -> bool:
	if stored_items.size() >= MAX_STORAGE_SLOTS:
		return false
	stored_items.append(item_type)
	storage_changed.emit(self)
	return true

## Removes the first entry matching `item_type`, if any, and reports
## whether one was actually found -- caller (see BuildingStoragePanel's
## drag-out/right-click handlers) decides what happens to the item next.
func take_item(item_type: String) -> bool:
	var index := stored_items.find(item_type)
	if index == -1:
		return false
	stored_items.remove_at(index)
	storage_changed.emit(self)
	return true

## Once an enemy building has been seen at least once, fog of war keeps it
## visible (at its last-known position) even after it drops out of vision
## again -- unlike enemy units, which vanish immediately. Set by
## RTSController._update_fog_of_war.
var ever_seen: bool = false

func _ready() -> void:
	super._ready()
	add_to_group("buildings")

## Buildings present a much bigger box footprint (one full tile, 2.6x2.6x2.6,
## half-extent 1.3 -- see BoxShape3D_body in ParentBuilding.tscn) than the
## Unit-sized opponent attack_range/MELEE_REACH are tuned for -- an
## attacking unit's own collision capsule physically can't reach anywhere
## near attack_range=1.0 of this building's *center* before colliding with
## its wall first. See Entity.get_engage_radius_bonus()'s doc comment.
func get_engage_radius_bonus() -> float:
	return 1.7

## Replaces the whole gather-point queue with a single point -- a plain
## (non-shift) right-click, same as how a fresh unit move order drops
## whatever waypoints that group already had queued.
func set_gather_point(world_position: Vector3) -> void:
	_clear_gather_flags()
	gather_points = [world_position]
	_gather_flags = [_spawn_gather_flag(world_position, 1)]

## Appends another gather point after whatever's already queued -- a
## shift-right-click, same as appending a waypoint to a unit's queue.
func queue_gather_point(world_position: Vector3) -> void:
	gather_points.append(world_position)
	_gather_flags.append(_spawn_gather_flag(world_position, gather_points.size()))

## Clears the whole gather-point queue and removes its flags -- the
## building-side half of the 'h' hotkey (see
## RTSController._halt_selected_units); the gather queue is the only
## standing "order" a building has to cancel.
func clear_gather_point() -> void:
	gather_points.clear()
	_clear_gather_flags()

func _spawn_gather_flag(world_position: Vector3, number: int) -> Node3D:
	var flag := WaypointFlag.spawn(self, world_position, number)
	flag.visible = selected
	return flag

func _clear_gather_flags() -> void:
	for flag in _gather_flags:
		if is_instance_valid(flag):
			flag.queue_free()
	_gather_flags.clear()

func _on_selection_changed() -> void:
	for flag in _gather_flags:
		if is_instance_valid(flag):
			flag.visible = selected
