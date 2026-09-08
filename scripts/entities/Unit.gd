extends Entity
class_name Unit
## A mobile Entity that walks to a nav target, following the navigation
## server's own routed path (see _current_desired_direction) at whatever
## angle that path actually is -- free-facing, not locked to a fixed set of
## directions. Health/belt/selection/attack-when-in-range plumbing all
## lives in Entity; this adds the nav agent, pathing, and chasing on top.

const MAX_SPEED: float = 2.25
const ARRIVE_DISTANCE: float = 0.15

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
## Where an equipped weapon's visual attaches -- see ParentUnit.tscn.
@onready var weapon_slot: Node3D = model_root.find_child("WeaponSlot", true, false)

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
## True once this unit has reached its own formation slot. While true, its
## nav_agent.max_speed is halved -- a unit already in formation only ever
## moves again if avoidance has to nudge it aside for a squadmate still
## finding its own slot, and that correction should be a gentle settle,
## not a full-speed dart, while the rest of the group is still arriving.
var _in_formation: bool = false
## How often (seconds) a unit that's stuck short of engage range against a
## live attack_target (see _physics_process) retries approaching it, plus
## a random per-retry jitter (+/- this much) so several stuck units don't
## all replan on the exact same frame -- left in lockstep, they tend to
## retry toward each other's just-vacated spots in near-perfect sync and
## livelock instead of spreading out.
const STUCK_RECHASE_INTERVAL: float = 1.0
const STUCK_RECHASE_JITTER: float = 0.4
var _stuck_rechase_cooldown: float = 0.0
## Approach angles (degrees, see attack()'s approach_angle_offset) a stuck
## retry picks randomly from -- straight toward the target, or various
## sides of it. A unit stuck on the direct approach tries a random side
## instead of the same blocked spot every retry, so a crowd blocking one
## particular side (the common case: a knot of allies already surrounding
## the same target) eventually gets routed around. Randomized rather than
## a fixed sequence for the same desync reason as the interval jitter --
## several stuck units cycling the same fixed sequence in lockstep tend to
## all pick the same next angle at the same time.
const STUCK_RECHASE_ANGLE_OFFSETS: Array[float] = [0.0, 40.0, -40.0, 80.0, -80.0, 120.0, -120.0, 160.0, -160.0]
## Set by pick_up_item() -- the item this unit is walking to and will
## collect once close enough (see _update_pickup_target()). Cleared by any
## other order (move_to()/stop() both clear it, same as attack_target).
var _pickup_target: WorldItem = null
## How close counts as "there" for picking up an item -- looser than
## ARRIVE_DISTANCE since the item's a small trigger-free point, not
## something requiring precise positioning.
const PICKUP_RANGE: float = 1.0

## Fires once a throw_item() order actually lands -- see
## _update_throw_target(). RTSController listens for this to spawn the
## thrown item and, if it was aimed at a unit/building rather than bare
## ground, hand it over once the throw animation finishes.
signal item_thrown(unit: Unit, item_type: String, target_position: Vector3, target_unit: Unit, target_building: Building)

## Set by throw_item() -- a drag-drop of the equipped item somewhere out of
## immediate reach: this unit walks toward _throw_target_position and, once
## within THROW_RANGE, throws _throw_item_type there (see
## _update_throw_target()). Cleared by any other order (move_to()/stop()
## both clear it, same as _pickup_target/attack_target) -- the item just
## stays equipped, nothing thrown, if some other order interrupts first.
var _throw_item_type: String = ""
var _throw_target_position: Vector3 = Vector3.INF
## Where the thrown item ends up once it lands -- at most one of these is
## set (neither, for a plain ground drop), mirroring ItemSlotButton's own
## drag payload shape.
var _throw_target_unit: Unit = null
var _throw_target_building: Building = null
## How close counts as within throwing range -- one tile, the same
## distance the eject-on-drop animation already treats as "nearby" (see
## WorldItem.TILE_SIZE), not ARRIVE_DISTANCE's much tighter
## precise-positioning radius.
const THROW_RANGE: float = WorldItem.TILE_SIZE

func _ready() -> void:
	super._ready()
	add_to_group("units")
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = ARRIVE_DISTANCE
	nav_agent.max_speed = MAX_SPEED
	nav_agent.velocity_computed.connect(_on_velocity_computed)

## Sends the unit to `target` via the navigation server's own pathfinding
## (see _current_desired_direction), which routes around baked-in obstacles
## -- buildings, the wall -- rather than a straight line toward it.
func move_to(target: Vector3, order_facing_angle: float = NAN) -> void:
	attack_target = null
	_pickup_target = null
	_clear_throw_target()
	_order_facing_angle = order_facing_angle
	_in_formation = false
	nav_agent.max_speed = MAX_SPEED
	nav_agent.target_position = target

## Cancels whatever this unit is currently doing -- moving, chasing,
## attacking -- and halts it in place immediately, rather than letting it
## finish its current leg/swing first. See RTSController's 'h' hotkey.
## Also holds off aggressive stance for a moment (see
## HALT_AGGRESSIVE_SUPPRESS_DURATION) so the unit actually stands down
## instead of immediately re-engaging whatever it was just pulled off of.
func stop() -> void:
	attack_target = null
	_pickup_target = null
	_clear_throw_target()
	_order_facing_angle = NAN
	_in_formation = false
	nav_agent.target_position = global_position
	_safe_velocity = Vector3.ZERO
	suppress_aggressive_stance(HALT_AGGRESSIVE_SUPPRESS_DURATION)

## True only while this unit isn't still traveling toward an ordered
## destination (nav_agent.is_navigation_finished(), the same "arrived"
## signal _physics_process already uses for formation/movement gating)
## and isn't approaching a pickup or throw target either. attack_target
## itself doesn't need checking here -- Entity._update_attack_target only
## calls is_idle() from the branch where attack_target is already null.
func is_idle() -> bool:
	return (
		nav_agent.is_navigation_finished()
		and _pickup_target == null
		and _throw_target_position == Vector3.INF
	)

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

## Walks toward `target_position` and, once within THROW_RANGE, throws
## `item_type` there (see _update_throw_target()) -- a drag-drop of the
## equipped item out of the equipment panel onto somewhere out of
## immediate reach. `target_unit`/`target_building` (at most one set) say
## what happens to the item once it lands, mirroring
## RTSController.handle_item_drag_drop's own unit/building/ground cases.
## Does nothing if this unit isn't actually holding `item_type` right now
## (e.g. the drag started before some other order already changed it).
func throw_item(item_type: String, target_position: Vector3, target_unit: Unit = null, target_building: Building = null) -> void:
	if equipped_weapon != item_type:
		return
	move_to(target_position)
	_throw_item_type = item_type
	_throw_target_position = target_position
	_throw_target_unit = target_unit
	_throw_target_building = target_building

func _clear_throw_target() -> void:
	_throw_item_type = ""
	_throw_target_position = Vector3.INF
	_throw_target_unit = null
	_throw_target_building = null

## Executes the throw once within THROW_RANGE of _throw_target_position --
## called every physics frame while a throw order is outstanding (see
## _physics_process), the same "checked every frame regardless of nav
## completion" pattern _update_pickup_target uses. Unequips the item (same
## visual/state change unequip_weapon() itself causes) and reports it
## thrown; RTSController owns actually spawning/animating/handing it off
## from there (see item_thrown).
func _update_throw_target() -> void:
	if _throw_target_position == Vector3.INF:
		return
	if global_position.distance_to(_throw_target_position) > THROW_RANGE:
		return
	var item_type := _throw_item_type
	var target_position := _throw_target_position
	var target_unit := _throw_target_unit
	var target_building := _throw_target_building
	# Halts movement immediately rather than continuing on toward
	# target_position (which move_to() aimed the nav agent at directly) --
	# THROW_RANGE is deliberately looser than nav's own arrival distance, so
	# without this the unit would keep walking the rest of the way in even
	# though the item already left its hand. stop() also re-clears the
	# throw fields (harmless -- already about to be overwritten/moot).
	stop()
	unequip_weapon()
	item_thrown.emit(self, item_type, target_position, target_unit, target_building)

## Chases `target` (reusing the ordinary move-to machinery to get there)
## and, once within attack_range, stops and repeatedly swings at it --
## see the attack_target handling in _physics_process / _update_attack_target.
## Sends the unit to a point just short of the target's own center rather
## than the exact center itself -- target.global_position sits inside the
## target's own collision body (and, when multiple attackers pile onto the
## same target, inside whichever attacker already claimed the melee spot
## closest to it too), which the nav agent can never actually reach. Once
## it gives up approaching an unreachable point it reports itself
## "finished" while still outside attack_range, leaving the unit
## permanently stuck -- neither still chasing nor close enough to swing --
## which is exactly the "some units just stand there instead of fighting"
## bug this fixes (confirmed headlessly: in an 8-unit brawl where multiple
## units picked the same nearest enemy, every unit except the one that
## grabbed the exact center point first got stranded this way,
## indefinitely, at a fixed distance outside attack_range).
##
## `approach_angle_offset` rotates the approach point around the target
## (degrees, 0 = straight from this unit's own current position) -- see
## STUCK_RECHASE_ANGLE_OFFSETS, which passes a random non-zero offset for a
## stuck retry, when a unit's direct approach turns out to be blocked
## (typically by allies already surrounding the same target) and it needs
## to try a different side instead of re-aiming at the same blocked spot
## forever.
func attack(target: Node3D, approach_angle_offset: float = 0.0) -> void:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	# Match the exact same effective range _update_attack_target checks
	# against (attack_range plus the target's own footprint bonus -- see
	# Entity.get_engage_radius_bonus(), e.g. a Building's much larger box)
	# so the approach point is inside engage range, not inside the
	# target's own collision body.
	var engage_range: float = attack_range
	if target.has_method("get_engage_radius_bonus"):
		engage_range += target.get_engage_radius_bonus()
	var approach_distance: float = maxf(engage_range - 0.2, 0.1)
	var destination := target.global_position
	if to_target.length() > 0.01:
		var approach_dir := to_target.normalized()
		if approach_angle_offset != 0.0:
			approach_dir = approach_dir.rotated(Vector3.UP, deg_to_rad(approach_angle_offset))
		destination = target.global_position - approach_dir * approach_distance
	move_to(destination)
	attack_target = target

func _physics_process(_delta: float) -> void:
	if is_dying():
		return
	if _attack_cooldown_remaining > 0.0:
		_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - _delta, 0.0)

	if _pickup_target != null:
		_update_pickup_target()

	if _throw_target_position != Vector3.INF:
		_update_throw_target()

	var attacking_in_range := _update_attack_target(_delta)

	# A unit chasing attack_target can end up permanently stuck just short
	# of engage range -- most commonly when several units converge on the
	# same target and whichever one didn't claim the spot nearest it gets
	# physically blocked by an ally already standing there. Once
	# nav_agent gives up trying to reach an unreachable point it reports
	# itself "finished" for good, so without a periodic retry the unit
	# would just stand there forever, neither fighting nor still trying to
	# close the gap, even after whatever was blocking it moves away or
	# dies. attack() recomputes a fresh approach point and re-plans from
	# the unit's current position each retry.
	if attack_target != null and not attacking_in_range and nav_agent.is_navigation_finished():
		_stuck_rechase_cooldown -= _delta
		if _stuck_rechase_cooldown <= 0.0:
			_stuck_rechase_cooldown = STUCK_RECHASE_INTERVAL + randf_range(-STUCK_RECHASE_JITTER, STUCK_RECHASE_JITTER)
			var offset: float = STUCK_RECHASE_ANGLE_OFFSETS[randi() % STUCK_RECHASE_ANGLE_OFFSETS.size()]
			attack(attack_target, offset)
	else:
		_stuck_rechase_cooldown = 0.0

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

	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var is_moving := flat_velocity.length() > 0.05
	if not attacking_in_range:
		if is_moving:
			_face_direction(flat_velocity.normalized(), get_physics_process_delta_time())
		elif not is_nan(_order_facing_angle):
			_face_angle(_order_facing_angle, get_physics_process_delta_time())
	_update_locomotion_animation(is_moving)

## Plays Walk while actually translating and Idle otherwise (arriving,
## standing between orders, mid-attack-approach before it's in range) --
## guarded by current_animation so it doesn't restart the clip every single
## frame. No-op for entities with no AnimationPlayer (e.g. the older
## sprite-billboard peasant, if one still exists). Always deferred to while
## a triggered one-shot animation (currently just Attack) is still
## playing, so e.g. a target dying mid-swing and clearing attack_target
## doesn't snap the model back to Walk/Idle before the swing finishes.
func _update_locomotion_animation(is_moving: bool) -> void:
	if animation_player == null:
		return
	if animation_player.is_playing() and animation_player.current_animation == "Attack":
		return
	var target_animation := "Walk" if is_moving else "Idle"
	if animation_player.current_animation != target_animation and animation_player.has_animation(target_animation):
		animation_player.play(target_animation)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	_safe_velocity = safe_velocity

## Direction toward the next corner of the navigation server's actual
## computed route to the current target (see NavGroundSetup.gd, which bakes
## the navmesh with holes at buildings/the wall so this route already goes
## around them) -- the raw, unquantized direction, so a unit can walk (and
## face) any angle rather than only 8 fixed ones. NavigationAgent3D advances
## get_next_path_position() to the following corner on its own once close
## enough to this one, so this needs no separate arrival/deviation tracking
## of its own.
func _current_desired_direction() -> Vector3:
	if nav_agent.is_navigation_finished():
		return Vector3.ZERO
	var to_next := nav_agent.get_next_path_position() - global_position
	to_next.y = 0.0
	if to_next.length() < 0.01:
		return Vector3.ZERO
	return to_next.normalized()
