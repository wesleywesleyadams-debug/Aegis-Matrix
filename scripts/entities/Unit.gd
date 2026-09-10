extends Entity
class_name Unit
## A mobile Entity that walks to a nav target, following the navigation
## server's own routed path (see _current_desired_direction) at whatever
## angle that path actually is -- free-facing, not locked to a fixed set of
## directions. Health/belt/selection/attack-when-in-range plumbing all
## lives in Entity; this adds the nav agent, pathing, and chasing on top.

const MAX_SPEED: float = 2.25
const ARRIVE_DISTANCE: float = 0.15

## Shown as the hover tooltip's title (see get_tooltip_title) in place
## of the raw node name -- "human" is the only race that currently
## exists (see GameState's lobby slot default), so every unit is one
## for now, but this is per-unit rather than hardcoded so a future
## race-differentiated unit just sets this on spawn.
@export var race: String = "human"

## Every unit starts at level 1. No leveling system exists yet (see
## Entity.take_damage's doc comment) -- once kills automatically scale
## up stats, this is what increments, and level 1 is simply "no bonus
## applied yet" rather than a special-cased starting state.
var level: int = 1

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
## Where a right/two-handed weapon's visual attaches -- see ParentUnit.tscn.
@onready var weapon_slot: Node3D = model_root.find_child("WeaponSlot", true, false)
## Where a left-handed weapon's visual attaches. A two-handed item (e.g.
## crossbow), or a hybrid_hand one currently gripped two-handed (e.g. a
## longsword equipped alone), equips into BOTH this and weapon_slot at
## once (see equip_item) -- but only weapon_slot actually gets a visual
## instanced (see _set_slot's left_hand/right_hand-match check). It's
## one physical weapon, not two, so instancing a second copy here too
## would read as the unit holding two separate weapons crossed in an X
## rather than one gripped with both hands.
@onready var weapon_slot_left: Node3D = model_root.find_child("WeaponSlotLeft", true, false)

## The four backpack slots this unit's inventory is organized into. Order
## matters only for iteration (e.g. BuildingStoragePanel-style UI listing
## slots in a stable order); armor/accessory have no equipped-visual
## attachment point yet (no assets for it currently exist), so equipping
## into those only ever affects this dictionary, not model_root.
const BACKPACK_SLOTS: Array[String] = ["armor", "right_hand", "left_hand", "accessory"]
## slot name -> item_type ("" for empty). Prefer equip_item()/unequip_slot()
## over writing this directly -- they also keep the equipped-visual
## (_slot_visuals) and backpack_changed signal in sync.
var backpack: Dictionary = {"armor": "", "right_hand": "", "left_hand": "", "accessory": ""}
## slot name -> the instanced visual currently attached for it (only ever
## populated for right_hand/left_hand, the only slots with a real
## attachment point -- see BACKPACK_SLOTS' doc comment above).
var _slot_visuals: Dictionary = {}

## Fires whenever any backpack slot changes (equip or unequip) -- lets
## RTSController's backpack/equipment panels stay in sync even when the
## change didn't come from the panel itself, e.g. a pickup landing
## directly in this unit's hands (see WorldItem.gd).
signal backpack_changed(unit: Unit)

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
## See attack_move_to()/is_attack_moving()/_on_aggressive_scan_found_nothing().
var _attack_moving: bool = false
var _attack_move_target: Vector3 = Vector3.INF
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
## Which backpack slot _throw_item_type is coming from -- see throw_item().
var _throw_source_slot: String = ""
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
## -- buildings, the wall -- rather than a straight line toward it. A plain
## order (this is the entry point RTSController uses for an ordinary move),
## so it cancels attack-move mode -- see _move_to_internal for the shared
## part attack()/attack_move_to() reuse without doing that.
func move_to(target: Vector3, order_facing_angle: float = NAN) -> void:
	_attack_moving = false
	_attack_move_target = Vector3.INF
	_move_to_internal(target, order_facing_angle)

func _move_to_internal(target: Vector3, order_facing_angle: float = NAN) -> void:
	attack_target = null
	_pickup_target = null
	_clear_throw_target()
	_order_facing_angle = order_facing_angle
	_in_formation = false
	nav_agent.max_speed = MAX_SPEED
	nav_agent.target_position = target

## Attack-move: like move_to(), but any hostile unit encountered along the
## way (not just once idle at the destination -- see is_attack_moving()'s
## effect on Entity._update_attack_target's aggressive-stance gate) gets
## engaged immediately, and once it's dead or lost the unit resumes marching
## toward `target` on its own (see _on_aggressive_scan_found_nothing())
## rather than just standing wherever the fight ended.
func attack_move_to(target: Vector3) -> void:
	_move_to_internal(target)
	_attack_moving = true
	_attack_move_target = target

func is_attack_moving() -> bool:
	return _attack_moving

## Called (see Entity._try_acquire_aggressive_target) whenever an
## aggressive-stance scan finds no hostile to engage. Mid-attack-move with
## the destination not yet reached, that means whatever fight interrupted
## the march (if any) is over -- resume toward it, still in attack-move
## mode (_move_to_internal, not move_to(), so this doesn't cancel itself).
## A no-op otherwise: an ordinary idle scan finding nothing just means nothing
## in range, nothing to do.
func _on_aggressive_scan_found_nothing() -> void:
	if not _attack_moving:
		return
	if global_position.distance_to(_attack_move_target) <= ARRIVE_DISTANCE:
		_attack_moving = false
		_attack_move_target = Vector3.INF
		return
	if nav_agent.is_navigation_finished():
		_move_to_internal(_attack_move_target)

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
	_attack_moving = false
	_attack_move_target = Vector3.INF
	nav_agent.target_position = global_position
	_safe_velocity = Vector3.ZERO
	suppress_aggressive_stance(HALT_AGGRESSIVE_SUPPRESS_DURATION)

## Issues an explicit player attack order (see RTSController._issue_attack_order)
## -- distinct from the low-level attack() that _try_acquire_aggressive_target
## and the stuck-rechase retry also call internally, both of which must NOT
## cancel an in-progress attack-move (engaging whatever they found *is* the
## point of attack-move; a specific attack order, on the other hand, is a
## brand new command that should replace it). Also marks the target as
## player-ordered (_attack_target_is_ordered) so it sticks even if a closer
## hostile wanders by afterward -- see _try_switch_to_closer_target, which
## only ever reprioritizes an auto-acquired target.
func order_attack(target: Node3D) -> void:
	_attack_moving = false
	_attack_move_target = Vector3.INF
	attack(target)
	_attack_target_is_ordered = true

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

## Equips `item_type` into whichever BACKPACK_SLOTS slot(s) it fits (see
## ItemDefs.get_slot_kind) -- "one_hand" takes whichever of right_hand/
## left_hand is free (right_hand if both are), "two_hand" always takes
## both at once, "hybrid_hand" takes both UNLESS the other hand already
## holds a one_hand/hybrid_hand weapon (then just the free hand, so both
## weapons fit at once -- see the "hybrid_hand" branch below), "armor"/
## "accessory" take their own single slot. Returns every item_type
## displaced to make room, in case the caller needs to put them back on
## the ground -- 0, 1, or (a two-hand item bumping two different items
## out, one from each hand) 2 entries. Never includes a hybrid_hand
## weapon that just re-gripped down to one hand to make room (see
## _make_room_in_hand) -- that weapon is still equipped, just no longer
## two-handed, not displaced at all. A bare [] for an unrecognized
## item_type (nothing equipped, nothing displaced).
func equip_item(item_type: String) -> Array[String]:
	var kind := ItemDefs.get_slot_kind(item_type)
	var displaced: Array[String] = []
	match kind:
		"one_hand":
			var hand := "right_hand" if backpack["right_hand"].is_empty() else "left_hand"
			_make_room_in_hand(hand, displaced)
			_set_slot(hand, item_type)
		"hybrid_hand":
			var hand := "right_hand" if backpack["right_hand"].is_empty() else "left_hand"
			var other := "left_hand" if hand == "right_hand" else "right_hand"
			_make_room_in_hand(hand, displaced)
			_set_slot(hand, item_type)
			# Only grip two-handed if the other hand is free -- a one_hand/
			# hybrid_hand weapon already there (or one about to fill it,
			# see the "one_hand" branch above re-checking this same hand
			# via is_empty()) means this weapon should leave that hand to
			# the other weapon instead of muscling in on both.
			if backpack[other].is_empty():
				_set_slot(other, item_type)
		"two_hand":
			_displace("right_hand", displaced)
			_displace("left_hand", displaced)
			_set_slot("right_hand", item_type)
			_set_slot("left_hand", item_type)
		"armor", "accessory":
			_displace(kind, displaced)
			_set_slot(kind, item_type)
	if not kind.is_empty():
		backpack_changed.emit(self)
	return displaced

## Clears `hand` to make room for whatever's about to be equipped into
## it. Usually that's just displacing whatever's there (see _displace).
## But if `hand`'s occupant is a "hybrid_hand" weapon currently gripped
## two-handed (right_hand and left_hand both hold it), it doesn't get
## displaced at all -- it re-grips down to a single hand (releasing just
## `hand`, via a plain unequip_slot that does NOT add to `displaced`)
## and stays equipped in the other one, exactly the "picking up a second
## weapon un-two-hands the hybrid one" behavior this slot kind exists
## for. A "two_hand" item's grip can't be split that way (it genuinely
## needs both hands), so that case still clears both hands and displaces
## it as a whole, same as before.
func _make_room_in_hand(hand: String, displaced: Array[String]) -> void:
	var occupant: String = backpack[hand]
	if occupant.is_empty():
		return
	var gripped_two_handed: bool = backpack["right_hand"] == backpack["left_hand"]
	if gripped_two_handed and ItemDefs.get_slot_kind(occupant) == "hybrid_hand":
		unequip_slot(hand)
	elif gripped_two_handed:
		_displace("right_hand", displaced)
		_displace("left_hand", displaced)
	else:
		_displace(hand, displaced)

## Clears `slot`'s current occupant (if any) into `displaced`, skipping a
## duplicate entry if it's the same item_type already added -- true when
## clearing both hands of the same two-handed item, which should read as
## displacing that one item once, not twice.
func _displace(slot: String, displaced: Array[String]) -> void:
	var old: String = unequip_slot(slot)
	if not old.is_empty() and old not in displaced:
		displaced.append(old)

## Clears `slot` and returns whichever item_type was in it ("" if none) --
## caller decides what happens to the item next (see RTSController's
## backpack/equipment panel right-click handlers, which drop it on the
## ground as a pickup again). Unlike equip_item(), a two-handed item
## occupying both hands is NOT automatically cleared from the other hand
## when only one slot is named -- callers that need "unequip whatever
## `item_type` actually is" (as opposed to "empty this one slot no matter
## what's in it") should clear both hand slots themselves if needed.
func unequip_slot(slot: String) -> String:
	var item_type: String = backpack.get(slot, "")
	if item_type.is_empty():
		return ""
	_set_slot(slot, "")
	backpack_changed.emit(self)
	return item_type

func _set_slot(slot: String, item_type: String) -> void:
	backpack[slot] = item_type
	var visual: Node3D = _slot_visuals.get(slot)
	if visual != null and is_instance_valid(visual):
		visual.queue_free()
	_slot_visuals.erase(slot)
	var attach_point: Node3D = weapon_slot if slot == "right_hand" else (weapon_slot_left if slot == "left_hand" else null)
	if slot == "right_hand":
		_update_attack_hitbox_position(item_type)
	if attach_point == null or item_type.is_empty():
		return
	# A weapon gripped two-handed (right_hand and left_hand both holding the
	# same item_type -- always set right_hand first, see equip_item's
	# "two_hand"/"hybrid_hand" branches) is ONE physical weapon, not two --
	# skip instancing a second copy of its visual at the left hand, or it
	# reads as the unit holding two separate weapons crossed in an X rather
	# than one weapon gripped with both hands.
	if slot == "left_hand" and item_type == backpack["right_hand"]:
		return
	var visual_scene: PackedScene = ItemDefs.get_visual_scene(item_type)
	if visual_scene == null:
		return
	var new_visual: Node3D = visual_scene.instantiate()
	attach_point.add_child(new_visual)
	_slot_visuals[slot] = new_visual

## Slides AttackHitbox out along the hand bone's own forward axis (+Y,
## matching how each weapon's visual scene is authored -- e.g. Sword.tscn's
## blade extends from the grip at local Y=0 to the tip at Y=0.9) so the hit
## detection volume actually sits at the weapon's business end when fully
## extended, not at the fist regardless of what's equipped. Reset back to
## the hand itself (offset 0) for an empty hand or a non-melee item.
func _update_attack_hitbox_position(item_type: String) -> void:
	if attack_hitbox == null:
		return
	attack_hitbox.position = Vector3(0, ItemDefs.get_melee_reach_bonus(item_type), 0)

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
## `item_type` there (see _update_throw_target()) -- a drag-drop of an
## equipped item out of the backpack/equipment panel onto somewhere out of
## immediate reach. `source_slot` says which backpack slot it's coming
## from (needed to actually clear it once thrown -- see
## unequip_item_fully). `target_unit`/`target_building` (at most one set)
## say what happens to the item once it lands, mirroring
## RTSController.handle_item_drag_drop's own unit/building/ground cases.
## Does nothing if `source_slot` doesn't actually hold `item_type` right
## now (e.g. the drag started before some other order already changed it).
func throw_item(item_type: String, source_slot: String, target_position: Vector3, target_unit: Unit = null, target_building: Building = null) -> void:
	if backpack.get(source_slot, "") != item_type:
		return
	move_to(target_position)
	_throw_item_type = item_type
	_throw_source_slot = source_slot
	_throw_target_position = target_position
	_throw_target_unit = target_unit
	_throw_target_building = target_building

func _clear_throw_target() -> void:
	_throw_item_type = ""
	_throw_source_slot = ""
	_throw_target_position = Vector3.INF
	_throw_target_unit = null
	_throw_target_building = null

## Executes the throw once within THROW_RANGE of _throw_target_position --
## called every physics frame while a throw order is outstanding (see
## _physics_process), the same "checked every frame regardless of nav
## completion" pattern _update_pickup_target uses. Unequips the item (same
## visual/state change unequip_slot() itself causes) and reports it
## thrown; RTSController owns actually spawning/animating/handing it off
## from there (see item_thrown).
func _update_throw_target() -> void:
	if _throw_target_position == Vector3.INF:
		return
	if global_position.distance_to(_throw_target_position) > THROW_RANGE:
		return
	var item_type := _throw_item_type
	var source_slot := _throw_source_slot
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
	unequip_item_fully(item_type, source_slot)
	item_thrown.emit(self, item_type, target_position, target_unit, target_building)

## Fully removes `item_type` from wherever it's equipped -- both hands
## if it's currently gripped two-handed (a "two_hand" item always is; a
## "hybrid_hand" one only when nothing else made it yield a hand -- see
## Unit.equip_item), since a single named slot isn't the whole picture
## then, or just `source_slot` otherwise.
func unequip_item_fully(item_type: String, source_slot: String) -> void:
	if backpack["right_hand"] == item_type and backpack["left_hand"] == item_type:
		unequip_slot("right_hand")
		unequip_slot("left_hand")
	else:
		unequip_slot(source_slot)

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
	if target != attack_target:
		_attack_target_is_ordered = false
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
	_move_to_internal(destination)
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
## a triggered one-shot animation (any "Attack"-prefixed clip -- see
## Entity._get_attack_animation_name(), which picks a weapon-specific one
## like "Attack_Sword" over the bare-handed "Attack") is still playing, so
## e.g. a target dying mid-swing and clearing attack_target doesn't snap
## the model back to Walk/Idle before the swing finishes.
func _update_locomotion_animation(is_moving: bool) -> void:
	if animation_player == null:
		return
	if animation_player.is_playing() and animation_player.current_animation.begins_with("Attack"):
		return
	var target_animation := "Walk" if is_moving else "Idle"
	if animation_player.current_animation != target_animation and animation_player.has_animation(target_animation):
		animation_player.play(target_animation, ANIMATION_BLEND_TIME)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	_safe_velocity = safe_velocity

## Swings whatever's actually in this unit's right hand -- a "sword" gets
## its own dedicated clip, chosen by CURRENT grip rather than just its
## item_type -- a hybrid_hand weapon (e.g. "sword") gripped two-handed
## (both hand slots holding the same weapon -- see equip_item) swings
## with a "two_hand" clip ("Attack_TwoHanded"), the same category a
## strict two_hand weapon would use once given one; gripped one-handed
## (dual-wielding two weapons at once) it swings with its own
## "one_hand" clip ("Attack_Sword") instead. Anything without a
## dedicated clip for its current grip (a missing animation, or an item
## with none defined at all, e.g. "crossbow" -- ranged, no melee swing
## to animate) falls back to the bare-handed punch. Keyed off backpack
## directly rather than the equipped visual node, since that's the
## single source of truth for what's actually equipped (see
## equip_item/_set_slot).
const WEAPON_ATTACK_ANIMATIONS: Dictionary = {
	"sword": {"one_hand": "Attack_Sword", "two_hand": "Attack_TwoHanded"},
	"steel_longsword": {"one_hand": "Attack_Sword", "two_hand": "Attack_TwoHanded"},
}

func _get_attack_animation_name() -> String:
	var animations: Dictionary = WEAPON_ATTACK_ANIMATIONS.get(backpack["right_hand"], {})
	var gripped_two_handed: bool = backpack["right_hand"] == backpack["left_hand"]
	var animation_name: String = animations.get("two_hand" if gripped_two_handed else "one_hand", "")
	if not animation_name.is_empty() and animation_player != null and animation_player.has_animation(animation_name):
		return animation_name
	return "Attack"

## Shows this unit's race in place of its raw node name (e.g. "Unit2").
func get_tooltip_title() -> String:
	return race.capitalize()

## Adds Level/Attack rows to the hover tooltip (see
## Entity.get_tooltip_extra_stats, RTSController._update_map_item_hover)
## -- Building/World don't have a level or attack concept at all, so
## only Unit overrides this. _get_attack_damage() rather than
## attack_damage directly, so an equipped weapon's damage shows here
## too, not just the unarmed default.
func get_tooltip_extra_stats() -> Dictionary:
	return {"Level": level, "Attack": "%d" % _get_attack_damage()}

## Swaps in the equipped right-hand weapon's own damage (see
## ItemDefs.get_damage) over the unarmed default -- an unequipped hand, or
## an item with no defined weapon damage (e.g. one not actually meant to
## be wielded), just falls back to attack_damage unmodified.
func _get_attack_damage() -> float:
	var weapon_damage := ItemDefs.get_damage(backpack["right_hand"])
	return weapon_damage if weapon_damage >= 0.0 else attack_damage

## Strings several hit-check points along the equipped weapon's own length
## (see ItemDefs.get_melee_hit_offsets) instead of just the one point at
## the fist -- e.g. a sword checks its grip, mid-blade, and tip each frame
## (swept against their own previous-frame positions too, see
## Entity._land_hit_if_in_reach), approximating a capsule along the blade.
## An unequipped hand, or an item with no offsets defined (e.g. the
## crossbow), falls back to the unarmed fist span (UNARMED_HIT_OFFSETS)
## rather than one bare point -- same capsule idea applied to a fist
## instead of a blade.
func _get_melee_hit_offsets() -> Array:
	var offsets := ItemDefs.get_melee_hit_offsets(backpack["right_hand"])
	return offsets if not offsets.is_empty() else UNARMED_HIT_OFFSETS

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
