extends Entity
class_name Unit
## A mobile Entity that walks to a nav target and snaps its facing to 8
## cardinal directions, the way 2.5D RTS units (real 3D models, locked
## facings) have always worked. Health/belt/selection/attack-when-in-range
## plumbing all lives in Entity; this adds the nav agent, pathing, and
## chasing on top.

const MAX_SPEED: float = 4.5
const ARRIVE_DISTANCE: float = 0.15
## How close to a planned segment's endpoint counts as "there" before
## advancing to the next segment. Looser than ARRIVE_DISTANCE so avoidance
## jitter near a waypoint doesn't stall the handoff to the next direction.
const SEGMENT_ARRIVE_DISTANCE: float = 0.25
## How far a unit may drift sideways off its committed segment's line
## before the plan is considered stale and gets recomputed from where the
## unit actually is. Needed because avoidance can shove a unit well off
## its planned line (e.g. several units jostling into nearby formation
## slots); blindly continuing in the original direction at that point
## walks away from the target instead of toward it.
const MAX_SEGMENT_DEVIATION: float = 0.75

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
## Where an equipped weapon's visual attaches -- see ParentUnit.tscn.
@onready var weapon_slot: Node3D = model_root.get_node_or_null("WeaponSlot")

## Item type currently in this unit's weapon slot, or "" for none. Set via
## equip_weapon() -- purely visual for now, no stat effect.
var equipped_weapon: String = ""
var _weapon_visual: Node3D = null

## Fires whenever equipped_weapon changes (equip or unequip) -- lets
## RTSController's equipment panel stay in sync even when the change didn't
## come from the panel itself, e.g. a pickup landing directly in this
## unit's weapon slot (see WorldItem.gd).
signal weapon_changed(unit: Unit)

## The navigation server's avoidance-adjusted velocity arrives asynchronously
## via velocity_computed and isn't guaranteed to land every physics frame.
## Movement itself must not depend on that signal firing this exact frame,
## or a frame it doesn't fire reads as a hard stop -- cache the latest
## known-safe velocity and move with it unconditionally every frame.
var _safe_velocity: Vector3 = Vector3.ZERO
## Order-level intended march direction (raw atan2 angle). NAN means no
## order-derived facing is pending; unit will face whatever velocity drove
## it, or hold its current facing if stationary without an active order.
var _order_facing_angle: float = NAN
## Straight-line legs (each a fixed 8-way direction + endpoint) planned
## once when a destination is set, decomposed diagonal-then-straight so the
## unit commits to long runs instead of re-deriving direction from its
## current position every frame -- which, since quantized movement doesn't
## track a perfectly straight line, drifts the true bearing frame to frame
## and flip-flops between two snap angles whenever it straddles the
## boundary between them.
var _path_segments: Array[Dictionary] = []
var _segment_index: int = 0
## The current leg's true destination, used as a fallback once all planned
## segments are behind the unit (e.g. avoidance nudged it off-line) so it
## still closes the final gap instead of stopping short.
var _leg_target: Vector3 = Vector3.INF
## True once this unit has reached its own formation slot. While true, its
## nav_agent.max_speed is halved -- a unit already in formation only ever
## moves again if avoidance has to nudge it aside for a squadmate still
## finding its own slot, and that correction should be a gentle settle,
## not a full-speed dart, while the rest of the group is still arriving.
var _in_formation: bool = false
## Set by pick_up_item() -- the item this unit is walking to and will
## collect once close enough (see _update_pickup_target()). Cleared by any
## other order (move_to()/stop() both clear it, same as attack_target).
var _pickup_target: WorldItem = null
## How close counts as "there" for picking up an item -- looser than
## ARRIVE_DISTANCE since the item's a small trigger-free point, not
## something requiring precise positioning.
const PICKUP_RANGE: float = 1.0

func _ready() -> void:
	super._ready()
	add_to_group("units")
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = ARRIVE_DISTANCE
	nav_agent.max_speed = MAX_SPEED
	nav_agent.velocity_computed.connect(_on_velocity_computed)

## Sends the unit directly to its assigned formation slot near the
## destination -- not a staging point near where it's currently standing.
## Units starting at different spots naturally converge on the tightly
## clustered final slots as they travel, so ranks visibly fall into place
## as the group nears the destination (or each other), rather than
## detouring to organize before departing at all.
func move_to(target: Vector3, order_facing_angle: float = NAN) -> void:
	attack_target = null
	_pickup_target = null
	_order_facing_angle = order_facing_angle
	_in_formation = false
	nav_agent.max_speed = MAX_SPEED
	nav_agent.target_position = target
	_plan_octile_path(global_position, target)

## Cancels whatever this unit is currently doing -- moving, chasing,
## attacking -- and halts it in place immediately, rather than letting it
## finish its current leg/swing first. See RTSController's 'h' hotkey.
func stop() -> void:
	attack_target = null
	_pickup_target = null
	_order_facing_angle = NAN
	_path_segments = []
	_segment_index = 0
	_leg_target = Vector3.INF
	_in_formation = false
	nav_agent.target_position = global_position
	_safe_velocity = Vector3.ZERO

## Puts `item_type`'s visual into this unit's weapon slot, replacing
## whatever was there before -- only ever one weapon held at a time. Purely
## visual right now; no stat effect.
func equip_weapon(item_type: String) -> void:
	if _weapon_visual != null and is_instance_valid(_weapon_visual):
		_weapon_visual.queue_free()
	equipped_weapon = item_type
	var visual_scene: PackedScene = ItemDefs.get_visual_scene(item_type)
	if visual_scene != null and weapon_slot != null:
		_weapon_visual = visual_scene.instantiate()
		weapon_slot.add_child(_weapon_visual)
	else:
		_weapon_visual = null
	weapon_changed.emit(self)

## Clears the weapon slot and returns whichever item_type was in it (""
## if none) -- caller decides what happens to the item next (see
## RTSController's equipment panel right-click handler, which drops it on
## the ground as a pickup again).
func unequip_weapon() -> String:
	var item_type := equipped_weapon
	if _weapon_visual != null and is_instance_valid(_weapon_visual):
		_weapon_visual.queue_free()
	_weapon_visual = null
	equipped_weapon = ""
	weapon_changed.emit(self)
	return item_type

## Walks to `item` (an explicit right-click order, see RTSController's
## _issue_pickup_order) and collects it once close enough -- see
## _update_pickup_target(). Merely wandering/pathing near an item some
## other order happens to route past does NOT pick it up; only an actual
## order to it does.
func pick_up_item(item: WorldItem) -> void:
	move_to(item.global_position)
	_pickup_target = item

## Collects _pickup_target once within PICKUP_RANGE of it -- called every
## physics frame while a pickup order is outstanding (see
## _physics_process). Drops the order harmlessly if the item's gone
## (already collected by someone/something else, or otherwise freed)
## before this unit got there.
func _update_pickup_target() -> void:
	if not is_instance_valid(_pickup_target):
		_pickup_target = null
		return
	if global_position.distance_to(_pickup_target.global_position) > PICKUP_RANGE:
		return
	var item := _pickup_target
	_pickup_target = null
	item.collect(self)

## Chases `target` (reusing the ordinary move-to machinery to get there)
## and, once within attack_range, stops and repeatedly swings at it --
## see the attack_target handling in _physics_process / _update_attack_target.
func attack(target: Node3D) -> void:
	move_to(target.global_position)
	attack_target = target

## Same as move_to(), but follows a precomputed sequence of segments
## instead of plotting its own from scratch -- so a group of units can
## travel a shared route together (each merging onto it from wherever it
## actually starts, then following the exact same directions for the rest
## of the trip, offset to its own destination) rather than each
## independently working out its own potentially differently-shaped path.
## See RTSController._issue_move_order / _build_shared_path.
func move_along_path(target: Vector3, order_facing_angle: float, segments: Array[Dictionary]) -> void:
	attack_target = null
	_order_facing_angle = order_facing_angle
	_in_formation = false
	nav_agent.max_speed = MAX_SPEED
	nav_agent.target_position = target
	_leg_target = target
	_path_segments = segments
	_segment_index = 0

func _physics_process(_delta: float) -> void:
	if _attack_cooldown_remaining > 0.0:
		_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - _delta, 0.0)

	if _pickup_target != null:
		_update_pickup_target()

	var attacking_in_range := _update_attack_target(_delta)

	if not _in_formation and nav_agent.is_navigation_finished():
		_in_formation = true
		nav_agent.max_speed = MAX_SPEED * 0.5

	var desired_velocity := Vector3.ZERO
	if not attacking_in_range and not nav_agent.is_navigation_finished():
		var dir := _current_desired_direction()
		if dir != Vector3.ZERO:
			desired_velocity = dir * (MAX_SPEED * 0.5 if _in_formation else MAX_SPEED)

	# Route through the navigation server's reciprocal-avoidance simulation
	# rather than moving directly, so units traveling as a group steer
	# around each other instead of shoving through and clumping. The
	# result lands later via _on_velocity_computed, not synchronously.
	if nav_agent.avoidance_enabled:
		nav_agent.set_velocity(desired_velocity)
	else:
		_safe_velocity = desired_velocity

	velocity = _safe_velocity
	move_and_slide()

	if not attacking_in_range:
		var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
		if flat_velocity.length() > 0.05:
			_face_direction(flat_velocity.normalized(), get_physics_process_delta_time())
		elif not is_nan(_order_facing_angle):
			_face_snapped_angle(_order_facing_angle, get_physics_process_delta_time())

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	_safe_velocity = safe_velocity

## Same 8-way quantization used for facing, applied to a movement direction
## instead -- so a unit's actual travel heading always matches one of the
## same 8 angles its model can visibly face.
func _snap_direction_to_8(dir: Vector3) -> Vector3:
	var snapped_angle := snap_angle(atan2(dir.x, dir.z))
	return Vector3(sin(snapped_angle), 0.0, cos(snapped_angle))

## Decomposes the straight-line trip from `from` to `to` into at most two
## fixed-direction legs: diagonal first to close the shorter axis, then
## straight along whichever axis has distance left over. This is the
## standard octile-distance construction and yields the fewest possible
## direction changes for a direct order -- one turn, not a turn every step.
## Static (and public, via the Unit class name) so RTSController can reuse
## the exact same math when building a shared path for a group to follow.
static func compute_octile_segments(from: Vector3, to: Vector3) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	var delta := to - from
	delta.y = 0.0
	var dx := delta.x
	var dz := delta.z
	if absf(dx) < 0.01 and absf(dz) < 0.01:
		return segments

	var step_x := signf(dx)
	var step_z := signf(dz)
	var diag_dist: float = minf(absf(dx), absf(dz))
	var straight_dist: float = absf(absf(dx) - absf(dz))

	var cursor := from
	if diag_dist > 0.01:
		# diag_dist is how far to close each axis, not the segment's travel
		# distance -- moving `diag_dist` along the normalized (length-1)
		# diagonal only covers diag_dist/sqrt(2) per axis. Step by the raw
		# (step_x, step_z) vector instead so both axes actually close by
		# diag_dist, and store the normalized form separately for velocity.
		var diag_dir := Vector3(step_x, 0.0, step_z).normalized()
		cursor += Vector3(step_x, 0.0, step_z) * diag_dist
		segments.append({"dir": diag_dir, "end": cursor})
	if straight_dist > 0.01:
		var straight_dir: Vector3 = Vector3(step_x, 0.0, 0.0) if absf(dx) > absf(dz) else Vector3(0.0, 0.0, step_z)
		cursor += straight_dir * straight_dist
		segments.append({"dir": straight_dir, "end": cursor})
	return segments

func _plan_octile_path(from: Vector3, to: Vector3) -> void:
	_leg_target = to
	_path_segments = compute_octile_segments(from, to)
	_segment_index = 0

## Direction for the segment the unit is currently committed to, advancing
## to the next segment once close enough to this one's end. Falls back to
## heading straight for _leg_target once every planned segment is behind
## the unit -- e.g. avoidance nudged it off-line -- so it still closes the
## gap instead of stalling with a stale, already-completed plan.
func _current_desired_direction() -> Vector3:
	if _segment_index < _path_segments.size():
		var seg: Dictionary = _path_segments[_segment_index]
		var progress := _segment_progress(seg)
		if global_position.distance_to(seg["end"]) < SEGMENT_ARRIVE_DISTANCE or progress.along > 0.0:
			# Either genuinely arrived, or overshot the endpoint along the
			# line itself. The latter matters because avoidance can nudge a
			# unit just wide enough, right as it passes a crowded slot, to
			# miss the arrival check on every single frame -- after which
			# distance-to-end only grows and this segment would otherwise
			# never be considered done, leaving the unit walking its stale
			# direction past the target forever (this is what "along > 0"
			# catches: it stays true however far past the endpoint the line
			# carries it, even when the miss was lateral, not a shortfall).
			_segment_index += 1
		elif progress.perpendicular > MAX_SEGMENT_DEVIATION:
			# Avoidance has pushed the unit far enough off this segment's
			# line that continuing in its original direction no longer
			# leads toward the target -- replan fresh from here instead of
			# blindly walking further off course.
			_plan_octile_path(global_position, _leg_target)
		if _segment_index < _path_segments.size():
			return _path_segments[_segment_index]["dir"]

	if _leg_target != Vector3.INF:
		var to_target := _leg_target - global_position
		to_target.y = 0.0
		if to_target.length() > 0.01:
			return _snap_direction_to_8(to_target.normalized())
	return Vector3.ZERO

## Decomposes the unit's current position, relative to a segment's end,
## into how far past the endpoint it is along the segment's own direction
## (positive once overshot) and how far sideways off the segment's line it
## sits (always >= 0) -- the two ways a unit can stop tracking a planned
## segment usefully.
func _segment_progress(seg: Dictionary) -> Dictionary:
	var seg_end: Vector3 = seg["end"]
	var seg_dir: Vector3 = seg["dir"]
	var offset := global_position - seg_end
	offset.y = 0.0
	var along := offset.dot(seg_dir)
	var perpendicular := offset - seg_dir * along
	return {"along": along, "perpendicular": perpendicular.length()}
