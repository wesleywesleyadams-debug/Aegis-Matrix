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

## Once an enemy building has been seen at least once, fog of war keeps it
## visible (at its last-known position) even after it drops out of vision
## again -- unlike enemy units, which vanish immediately. Set by
## RTSController._update_fog_of_war.
var ever_seen: bool = false

func _ready() -> void:
	super._ready()
	add_to_group("buildings")

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
