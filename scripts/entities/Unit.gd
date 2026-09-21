extends Entity
class_name Unit
## A mobile Entity that walks to a nav target, following the navigation
## server's own routed path (see _current_desired_direction) at whatever
## angle that path actually is -- free-facing, not locked to a fixed set of
## directions. Health/belt/selection/attack-when-in-range plumbing all
## lives in Entity; this adds the nav agent, pathing, and chasing on top.

## Was a const; now a per-instance var so UnitDefs (see Entity.
## _apply_type_defs, called from _ready() before nav_agent.max_speed is
## first set below) can vary it per unit_type_id. 2.25 remains the
## fallback for any type UnitDefs has no "max_speed" entry for.
var MAX_SPEED: float = 2.25
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
## Manually-adjustable offset (position + rotation) between the raw
## mixamorig_RightHand bone (which weapon_slot itself tracks every frame,
## overwriting any transform set on it directly -- see BoneAttachment3D)
## and where a weapon's grip should actually land in the palm. Weapon
## visuals attach here instead of directly to weapon_slot, so nudging this
## node's gizmo in the editor (see ParentUnit.tscn) shifts the effective
## grip point without touching the raw animation or bone.
@onready var weapon_grip_offset: Node3D = weapon_slot.find_child("GripOffset", false, false)
## Where a left-handed weapon's visual attaches. A two-handed item (e.g.
## crossbow), or a hybrid_hand one currently gripped two-handed (e.g. a
## longsword equipped alone), equips into BOTH this and weapon_slot at
## once (see equip_item) -- but only weapon_slot actually gets a visual
## instanced (see _set_slot's left_hand/right_hand-match check). It's
## one physical weapon, not two, so instancing a second copy here too
## would read as the unit holding two separate weapons crossed in an X
## rather than one gripped with both hands.
@onready var weapon_slot_left: Node3D = model_root.find_child("WeaponSlotLeft", true, false)
## Same manually-adjustable offset as weapon_grip_offset, but for the left
## hand (mixamorig_LeftHand) -- see weapon_grip_offset's doc comment.
@onready var weapon_grip_offset_left: Node3D = weapon_slot_left.find_child("GripOffset", false, false)
## Where an equipped "armor" item's visual attaches -- a chest bone, not
## a hand, so a piece of armor rides the torso instead of being gripped.
## Same GripPoint-alignment mechanism as weapons (see _align_to_grip_point)
## applies here too -- an armor scene's own GripPoint marker says how it
## sits on the chest, same as a weapon's says how it sits in a hand.
@onready var armor_slot: Node3D = model_root.find_child("ArmorSlot", true, false)
## Where an equipped "accessory" item's visual attaches -- the neck bone,
## for a necklace/amulet-style accessory. Same GripPoint mechanism as
## weapons/armor (see _align_to_grip_point).
@onready var accessory_slot: Node3D = model_root.find_child("AccessorySlot", true, false)

## The five backpack slots this unit's inventory is organized into. Order
## matters only for iteration (e.g. BuildingStoragePanel-style UI listing
## slots in a stable order); armor/accessory have no equipped-visual
## attachment point yet (no assets for it currently exist), so equipping
## into those only ever affects this dictionary, not model_root.
## "two_hand" is a fifth slot, separate from right_hand/left_hand, for
## whatever's currently gripped with both hands -- a strictly "two_hand"
## kind item (e.g. a crossbow), or a "hybrid_hand" one (e.g. a longsword)
## gripped two-handed by default when nothing else needs a hand (see
## equip_item). Its invariant: whenever "two_hand" is non-empty,
## right_hand and left_hand are BOTH empty, and vice versa -- only one of
## "two_hand" or {right_hand, left_hand} is ever in play, since a unit
## only has two hands. UnitBackpackPanel shows right_hand/left_hand as
## unusable (a red X, see ItemSlotButton.set_blocked) while "two_hand"
## holds a strict two_hand item (both hands are genuinely committed), but
## leaves them showing plain-empty while it holds a hybrid_hand one
## (equipping something there just re-grips the hybrid one-handed
## instead -- see _vacate_two_hand_slot).
const BACKPACK_SLOTS: Array[String] = ["armor", "right_hand", "left_hand", "accessory", "two_hand"]
## slot name -> item_type ("" for empty). Prefer equip_item()/unequip_slot()
## over writing this directly -- they also keep the equipped-visual
## (_slot_visuals) and backpack_changed signal in sync.
var backpack: Dictionary = {"armor": "", "right_hand": "", "left_hand": "", "accessory": "", "two_hand": ""}
## slot name -> the instanced visual currently attached for it (only ever
## populated for right_hand/left_hand/two_hand, the only slots with a real
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

## Set by repair_building() -- the building this unit is walking to and
## will heal once (and for as long as it stays) close enough (see
## _update_repair_target()). Cleared by any other order (move_to()/stop()
## both clear it, same as attack_target/_pickup_target), by the building
## reaching full health, or by the building being freed.
var repair_target: Building = null
## Same reasoning as PICKUP_RANGE -- close enough to touch/work on the
## building, not a precise stop.
const REPAIR_RANGE: float = 1.5
## HP restored per second while actively repairing -- an arbitrary but
## reasonable flat rate; real balancing (civ bonuses, resource cost per HP,
## etc.) doesn't exist yet, same "capability now, tuning later" status as
## other placeholder numbers in this project.
const REPAIR_RATE: float = 15.0

## Set by construct_building() -- the foundation this unit is walking to
## and will help build once (and for as long as it stays) close enough
## (see _update_construct_target()). Cleared by any other order
## (move_to()/stop() both clear it, same as repair_target), by the
## building finishing construction, or by the building being freed.
## Only ever set on a "peasant" -- see construct_building's own guard.
## The setter keeps the building's own add_construction_worker/
## remove_construction_worker bookkeeping (see Building.gd) in sync with
## every single place this changes, rather than needing a matching call
## at each one -- that bookkeeping is what drives the foundation's
## "someone is actively working on me right now" blinking selection ring,
## which needs to react correctly regardless of *why* this unit stopped
## (new order, walked out of range, building finished/died, ...).
var construct_target: Building = null:
	set(new_target):
		if new_target == construct_target:
			return
		if construct_target != null and is_instance_valid(construct_target):
			construct_target.remove_construction_worker(self)
		construct_target = new_target
		if construct_target != null:
			construct_target.add_construction_worker(self)
## Same reasoning as REPAIR_RANGE -- close enough to actually work on the
## foundation, not a precise stop.
const CONSTRUCT_RANGE: float = 1.5

## Set by gather_resource() -- the World resource node (an Oak Tree, Apple
## Tree, Crystal Cave, Mist Fissure, ...) this unit is walking to and will
## gather from once (and for as long as it stays) close enough (see
## _update_gather_target()). Cleared by any other order (move_to()/stop()
## both clear it, same as repair_target/construct_target), by the node
## depleting/being freed, or by GameState. Only ever set on a "peasant" --
## see gather_resource's own guard (this game's whole resource economy is
## peasant-labor-only: picked by hand for Acorns/Apples, mined with a
## pickaxe for Crystal, breathed in for Mist -- no dedicated gather
## animation per tool/verb exists yet, this is the same swing regardless
## of node type).
var gather_target: World = null
## Same reasoning as REPAIR_RANGE -- close enough to actually work the
## node, not a precise stop.
const GATHER_RANGE: float = 1.5
## Resource units gathered per second while actively working a node --
## base rate of 1 unit per 2 seconds (Path of Desire and other multipliers
## still apply on top via PathPerks.gather_rate_multiplier, see
## _update_gather_target's own call site).
const GATHER_RATE: float = 0.5

## Set by order_plant() -- the ground position this unit is walking to and
## will spend PLANT_TIME seconds planting a sapling at, once (and for as
## long as it stays) close enough (see _update_plant_target()). Cleared by
## any other order (move_to()/stop() both clear it, same as repair_target/
## construct_target/gather_target). Vector3.INF (Entity's own "no target"
## convention for a plain position rather than a node -- see
## _throw_target_position) means no plant order outstanding.
var plant_target_position: Vector3 = Vector3.INF
## Which tree scene to instantiate once planting finishes -- paired with
## plant_target_position, meaningless while that's Vector3.INF. Passed in
## by RTSController._issue_plant_click (already resolved from "oak"/
## "apple" there via PLANT_COSTS' own naming) rather than Unit.gd knowing
## OakTree.tscn/AppleTree.tscn's paths itself.
var _plant_tree_scene: PackedScene = null
## How long it takes a peasant to plant one sapling once close enough to
## the spot.
const PLANT_TIME: float = 5.0
## Same reasoning as REPAIR_RANGE -- close enough to actually plant on the
## spot, not a precise stop.
const PLANT_RANGE: float = 1.0
var _plant_timer: float = 0.0

## Set by seek_garrison() (Garrison/Seek Shelter commands) -- the building
## this unit is walking to and will enter once close enough (see
## _update_garrison_target()). Cleared once actually entered (becomes
## garrisoned_in instead), by any other order, or if the building fills up
## /is freed before this unit arrives.
var garrison_target: Building = null
## Set once this unit has actually entered a building (see garrison_in())
## -- null while merely walking toward one (see garrison_target instead).
## A garrisoned unit is hidden and inert: no collision, no physics
## processing of its own orders, until ungarrison() restores it.
var garrisoned_in: Building = null
## Same reasoning as REPAIR_RANGE -- close enough to actually enter the
## building, not a precise stop.
const GARRISON_RANGE: float = 1.5
## How far outside the building a unit reappears at once ungarrisoned --
## just past its own collision footprint so it doesn't spawn back inside
## a wall/other garrisoned unit's exact spot.
const UNGARRISON_OFFSET: float = 1.7
## This unit's own collision_layer/mask as they were right before
## garrison_in() zeroed them out -- restored by ungarrison() rather than
## a hardcoded pair of magic numbers, so this stays correct even if a
## future unit variant's own defaults ever differ from the base Unit's.
var _pre_garrison_collision_layer: int = 0
var _pre_garrison_collision_mask: int = 0

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
	# Path of Chaos -- baked in once at spawn (see PathPerks.chaos_health_multiplier's
	# own doc comment), same "stored field, apply once" reasoning
	# Building's own Path of Order bonus has. Unit-only, not the shared
	# Entity._ready() -- Chaos's own perk text is specifically "unit HP",
	# Order already covers the building side separately.
	max_health *= PathPerks.chaos_health_multiplier(player_id)
	current_health = max_health
	# Path of Magic -- "vision range for all units", baked in once at
	# spawn same as the two stat bumps just above.
	vision_range *= PathPerks.vision_range_multiplier(player_id)
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = ARRIVE_DISTANCE
	nav_agent.max_speed = MAX_SPEED
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	GameState.grip_points_visibility_changed.connect(_on_grip_points_visibility_changed)
	_on_grip_points_visibility_changed(GameState.show_grip_points)
	# _update_attack_hitbox_size otherwise only ever runs from equip_item's
	# _set_slot call -- a unit that starts (or ends up, after unequipping)
	# bare-handed would be left showing whatever placeholder size the
	# HitboxMesh's SphereMesh/CapsuleMesh happens to be authored at in
	# ParentUnit.tscn, not the real unarmed size (see UNARMED_HIT_OFFSETS).
	_update_attack_hitbox_size(attack_hitbox, "")
	_update_attack_hitbox_size(attack_hitbox_left, "")
	# Must run after AnimationPlayer's own (default-priority) per-frame
	# update, or whatever finger curl we apply this frame gets immediately
	# stomped by the animation's own (uncurled) finger keyframes evaluated
	# the same frame. Higher process_priority runs later, not sooner.
	process_priority = 100
	_build_idle_indicator()

## A billboarded "Zzz" floating above this unit's head, shown only while
## ResourceHUD's own "idle villager" definition is true for this unit
## (is_idle() and not fighting) -- the in-world half of the idle-villager
## warning; ResourceHUD's own top-bar icon is the other half. Built for
## every Unit, not just "peasant" ones, since unit_type_id can change
## after _ready() (a trained unit's type is set right after instancing --
## see Building._train_unit) and this is harmless to have sitting hidden
## on a non-peasant.
const IDLE_INDICATOR_OFFSET: Vector3 = Vector3(0, 2.5, 0)
## Dark blue fill, glowing outline -- Label3D can't render a literal
## glow, so `outline_modulate` (its outline color) stands in for one,
## same "closest built-in property" reasoning used elsewhere in this
## project for a stand-in effect. The fill is always this fixed constant
## (fully opaque -- _process multiplies in the current fade alpha on top
## each frame, see IDLE_INDICATOR_FADE_CYCLE); the glow is this unit's
## own team color instead (see Entity.PLAYER_COLORS, read live in
## _process rather than cached, since player_id can in principle change
## after _ready()) -- reads as "this is one of MY idle units" at a
## glance rather than the same color for every player.
const IDLE_INDICATOR_FILL_COLOR: Color = Color(0.05, 0.05, 0.35)
## 50% larger than this indicator's original 48.
const IDLE_INDICATOR_FONT_SIZE: int = 72
## Full fade loop length -- 2s fading in from invisible to fully opaque,
## then 2s fading back out, repeating for as long as the indicator stays
## visible. _process derives the current point in this cycle from
## _idle_elapsed directly (fmod) rather than a separate timer, so the
## fade always restarts from 0 (invisible) the instant a unit goes idle,
## in step with "!"/"Zzz" itself rather than an independent, possibly
## out-of-phase clock.
const IDLE_INDICATOR_FADE_CYCLE: float = 4.0
var _idle_indicator: Label3D = null
## "!" shows the instant a peasant goes idle (see _process) -- the more
## urgent, "notice me" version, for a peasant that just needs a new
## order. "Zzz" (IDLE_INDICATOR_SLEEP_DELAY) takes over once it's been
## idle long enough to read as actually neglected/forgotten about.
const IDLE_INDICATOR_SLEEP_DELAY: float = 5.0
## Seconds this unit has been continuously idle -- reset to 0 the moment
## is_idle() (or attack_target) stops being true (see _process), so this
## always measures "how long in a row", never an accumulated total.
var _idle_elapsed: float = 0.0

func _build_idle_indicator() -> void:
	var label := Label3D.new()
	label.text = "Zzz"
	label.font_size = IDLE_INDICATOR_FONT_SIZE
	label.outline_size = 16
	label.modulate = IDLE_INDICATOR_FILL_COLOR
	label.outline_modulate = Entity.PLAYER_COLORS.get(player_id, Color.WHITE)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = IDLE_INDICATOR_OFFSET
	label.visible = false
	add_child(label)
	_idle_indicator = label

func _process(delta: float) -> void:
	_apply_grip_pose()
	_apply_left_hand_ik()
	# Moved here from _physics_process (see its own doc comment there) --
	# purely presentation, so it runs on the render tick rather than the
	# fixed simulation tick. velocity is a CharacterBody3D property that
	# move_and_slide() (in _physics_process) already keeps current, so
	# reading it here is safe/up to date regardless of tick rate.
	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
	_update_locomotion_animation(flat_velocity.length() > 0.05)
	if _idle_indicator != null:
		var currently_idle: bool = unit_type_id == "peasant" and is_idle() and attack_target == null
		if currently_idle:
			_idle_elapsed += delta
		else:
			_idle_elapsed = 0.0
		if not currently_idle:
			_idle_indicator.visible = false
		else:
			_idle_indicator.visible = true
			_idle_indicator.text = "Zzz" if _idle_elapsed >= IDLE_INDICATOR_SLEEP_DELAY else "!"
			# Triangle wave, not a smooth sine -- "2s in, 2s out" reads as a
			# literal linear ramp both ways, not an ease-in/out curve.
			var fade_t := fmod(_idle_elapsed, IDLE_INDICATOR_FADE_CYCLE)
			var half_cycle := IDLE_INDICATOR_FADE_CYCLE * 0.5
			var alpha := fade_t / half_cycle if fade_t < half_cycle else (IDLE_INDICATOR_FADE_CYCLE - fade_t) / half_cycle
			var fill := IDLE_INDICATOR_FILL_COLOR
			fill.a = alpha
			var glow: Color = Entity.PLAYER_COLORS.get(player_id, Color.WHITE)
			glow.a = alpha
			_idle_indicator.modulate = fill
			_idle_indicator.outline_modulate = glow

## Overrides this unit's finger-curl every frame to match whatever's
## actually in its driving hand (see _get_active_weapon_item_type()),
## independent of which animation happens to be playing -- see
## GripPoses' doc comment for why this lives here instead of being baked
## per-animation in Blender. A no-op for anything without a skeleton
## (sprite-billboard entities, Building) or while unarmed/holding
## something with no curl category defined (see GripPoses.get_curl).
func _apply_grip_pose() -> void:
	if skeleton == null:
		return
	var slot_kind := ItemDefs.get_slot_kind(_get_active_weapon_item_type())
	var curl: Dictionary = GripPoses.get_curl(slot_kind)
	if curl.is_empty():
		return
	var finger_curl: Dictionary = curl.get("fingers", {})
	for finger in ["Index", "Middle", "Ring", "Pinky"]:
		for seg in finger_curl:
			_set_finger_curl("RightHand%s%d" % [finger, seg], finger_curl[seg])
	var thumb_curl: Dictionary = curl.get("thumb", {})
	for seg in thumb_curl:
		_set_finger_curl("RightHandThumb%d" % seg, thumb_curl[seg])

## Rotates one finger-segment bone (e.g. "RightHandIndex1") `deg` degrees
## around its own local X axis, closing it toward the palm -- same
## convention rebuild_vertical_idle.py's Blender-side finger curl uses.
## A no-op if this rig has no bone by that name (e.g. an older/simpler
## skeleton without full 5-finger rigging).
func _set_finger_curl(bone_name: String, deg: float) -> void:
	var idx := skeleton.find_bone("mixamorig_%s" % bone_name)
	if idx == -1:
		return
	skeleton.set_bone_pose_rotation(idx, Quaternion(Vector3(1, 0, 0), deg_to_rad(deg)))

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
	repair_target = null
	construct_target = null
	gather_target = null
	plant_target_position = Vector3.INF
	_plant_tree_scene = null
	garrison_target = null
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
	repair_target = null
	construct_target = null
	gather_target = null
	plant_target_position = Vector3.INF
	_plant_tree_scene = null
	garrison_target = null
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
## signal _physics_process already uses for formation/movement gating),
## isn't approaching a pickup or throw target, and isn't actively working
## a standing order once arrived either -- gathering, repairing,
## constructing, planting, or garrisoning. Without these, a peasant that
## had finished walking to a resource node and was actively gathering from
## it (nav_agent long since finished, so the travel check alone said
## "idle") still read as idle -- see _process's own "!"/"Zzz" indicator,
## which used exactly this bug to show while a peasant was visibly working.
## attack_target itself doesn't need checking here -- Entity.
## _update_attack_target only calls is_idle() from the branch where
## attack_target is already null.
func is_idle() -> bool:
	return (
		nav_agent.is_navigation_finished()
		and _pickup_target == null
		and _throw_target_position == Vector3.INF
		and repair_target == null
		and construct_target == null
		and gather_target == null
		and plant_target_position == Vector3.INF
		and garrison_target == null
	)

## Equips `item_type` into whichever BACKPACK_SLOTS slot(s) it fits (see
## ItemDefs.get_slot_kind) -- "one_hand" takes whichever of right_hand/
## left_hand is free (right_hand if both are); "two_hand" always takes
## the dedicated "two_hand" slot, clearing right_hand/left_hand/two_hand
## entirely first (it needs both hands genuinely, no re-gripping);
## "hybrid_hand" takes "two_hand" too, but only when right_hand AND
## left_hand are both already free -- otherwise (already dual-wielding,
## or about to) it takes whichever single hand is free instead (right_hand
## first), re-gripping anything already sitting in "two_hand" down to one
## hand first if needed (see _vacate_two_hand_slot); "armor"/"accessory"
## take their own single slot. Returns every item_type displaced to make
## room, in case the caller needs to put them back on the ground -- 0, 1,
## or ("two_hand" bumping out up to two different single-handed items at
## once) 2 entries. Never includes a hybrid_hand weapon that just
## re-gripped down to one hand to make room -- that weapon is still
## equipped, just no longer two-handed, not displaced at all. A bare []
## for an unrecognized item_type (nothing equipped, nothing displaced).
func equip_item(item_type: String) -> Array[String]:
	var kind := ItemDefs.get_slot_kind(item_type)
	var displaced: Array[String] = []
	match kind:
		"one_hand":
			_vacate_two_hand_slot(displaced)
			var hand := "right_hand" if backpack["right_hand"].is_empty() else "left_hand"
			_displace(hand, displaced)
			_set_slot(hand, item_type)
		"hybrid_hand":
			_vacate_two_hand_slot(displaced)
			if backpack["right_hand"].is_empty() and backpack["left_hand"].is_empty():
				_set_slot("two_hand", item_type)
			else:
				var hand := "right_hand" if backpack["right_hand"].is_empty() else "left_hand"
				_displace(hand, displaced)
				_set_slot(hand, item_type)
		"two_hand":
			_displace("right_hand", displaced)
			_displace("left_hand", displaced)
			_displace("two_hand", displaced)
			_set_slot("two_hand", item_type)
		"armor", "accessory":
			_displace(kind, displaced)
			_set_slot(kind, item_type)
	if not kind.is_empty():
		backpack_changed.emit(self)
	return displaced

## Clears the "two_hand" slot to make room for a hand-slot item about to
## be equipped. If it's holding a "hybrid_hand" weapon, that weapon isn't
## displaced at all -- it re-grips down to right_hand (guaranteed free,
## per the "two_hand" slot's own invariant that right_hand/left_hand are
## both empty whenever it's occupied), leaving left_hand free for
## whatever's about to be equipped there. If it's holding a strict
## "two_hand" item (can't be split into one hand), that gets fully
## displaced instead. A no-op if "two_hand" is already empty.
func _vacate_two_hand_slot(displaced: Array[String]) -> void:
	var occupant: String = backpack["two_hand"]
	if occupant.is_empty():
		return
	if ItemDefs.get_slot_kind(occupant) == "hybrid_hand":
		unequip_slot("two_hand")
		_set_slot("right_hand", occupant)
	else:
		_displace("two_hand", displaced)

## Clears `slot`'s current occupant (if any) into `displaced`. Always
## appends (even if another displaced slot already holds the same
## item_type) -- right_hand/left_hand/two_hand are always genuinely
## separate physical items now (the dedicated "two_hand" slot rework
## ended the old model where a single hybrid weapon's one physical item
## occupied both hand slots' values at once), so two units both holding
## e.g. an Iron Short Sword are two real swords that must both eject.
func _displace(slot: String, displaced: Array[String]) -> void:
	var old: String = unequip_slot(slot)
	if not old.is_empty():
		displaced.append(old)

## Clears `slot` and returns whichever item_type was in it ("" if none) --
## caller decides what happens to the item next (see RTSController's
## backpack/equipment panel right-click handlers, which drop it on the
## ground as a pickup again).
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
	# "two_hand" attaches to the same bone as right_hand -- the invariant
	# on BACKPACK_SLOTS' doc comment (only one of "two_hand" or
	# {right_hand, left_hand} is ever occupied at once) means they never
	# fight over it in practice.
	var attach_point: Node3D
	var scale_factor: float
	match slot:
		"right_hand", "two_hand":
			attach_point = weapon_grip_offset
			scale_factor = GRIPPED_WEAPON_SCALE
		"left_hand":
			attach_point = weapon_grip_offset_left
			scale_factor = GRIPPED_WEAPON_SCALE
		"armor":
			attach_point = armor_slot
			scale_factor = EQUIPPED_ARMOR_SCALE
		"accessory":
			attach_point = accessory_slot
			scale_factor = EQUIPPED_ARMOR_SCALE
		_:
			attach_point = null
			scale_factor = 1.0
	if slot == "right_hand" or slot == "two_hand":
		_update_attack_hitbox_size(attack_hitbox, _get_active_weapon_item_type())
	elif slot == "left_hand":
		_update_attack_hitbox_size(attack_hitbox_left, item_type)
	if attach_point == null or item_type.is_empty():
		return
	var visual_scene: PackedScene = ItemDefs.get_visual_scene(item_type)
	if visual_scene == null:
		return
	var new_visual: Node3D = visual_scene.instantiate()
	attach_point.add_child(new_visual)
	_align_to_grip_point(new_visual, scale_factor)
	_slot_visuals[slot] = new_visual
	_set_grip_marker_visible(new_visual, GameState.show_grip_points)

## Re-parents a weapon's contents so its own GripPoint marker (if it has
## one -- see e.g. IronGreatsword.tscn) lands exactly on attach_point's
## origin, instead of assuming every weapon's mesh origin already IS the
## grip. Lets a weapon's own scene say "the hand goes here, facing this
## way" as authored data rather than every weapon needing its whole mesh
## built around origin=grip by convention. A no-op but for the uniform
## scale (falls back to origin-as-grip) for a weapon with no GripPoint
## child, e.g. anything authored before this existed.
##
## Order matters here: GripPoint's own inverse transform is computed
## first (a pure rotation+translation, no scale, since GripPoint markers
## are never scaled), THEN the uniform scale is applied by prepending a
## scale-only Transform3D -- not by mutating `visual.scale` as a separate
## step afterward. Scaling after the fact would scale visual's origin
## while leaving the grip-alignment offset fixed, dragging the grip back
## away from attach_point's origin by exactly the amount the scale grew
## it; prepending the scale composes it into the same transform so the
## already-aligned grip point (which maps to exactly zero) stays at zero
## no matter the scale factor.
## Bends the left arm (a two-bone shoulder->elbow->wrist IK chain) each
## frame so the left hand reaches the equipped two-handed weapon's own
## "GripPointLeft" marker (see e.g. GreatswordBase.tscn) -- independent of
## wherever the raw animation happened to put that hand. This is the same
## kind of live pose override as _apply_grip_pose's finger curl (see its
## doc comment): the animation asset itself stays completely untouched,
## this just corrects the result after the fact, every frame, matching
## the "no custom pose baked into the animation" rule while still getting
## the hand to actually look like it's gripping the weapon.
##
## A no-op unless something is actually gripped two-handed (see
## _get_active_weapon_item_type/equip_item -- both a strict "two_hand"
## item and a "hybrid_hand" one gripped two-handed live in the "two_hand"
## backpack slot) AND that weapon's visual scene actually has a
## GripPointLeft marker (e.g. IronShortsword's never gripped two-handed,
## so it has none).
func _apply_left_hand_ik() -> void:
	if skeleton == null:
		return
	if backpack.get("two_hand", "").is_empty():
		return
	var weapon_visual: Node3D = _slot_visuals.get("two_hand")
	if weapon_visual == null or not is_instance_valid(weapon_visual):
		return
	var grip_left: Node3D = weapon_visual.find_child("GripPointLeft", false, false)
	if grip_left == null:
		return
	var shoulder_idx := skeleton.find_bone("mixamorig_LeftArm")
	var elbow_idx := skeleton.find_bone("mixamorig_LeftForeArm")
	var wrist_idx := skeleton.find_bone("mixamorig_LeftHand")
	if shoulder_idx == -1 or elbow_idx == -1 or wrist_idx == -1:
		return
	if skeleton.get_bone_parent(elbow_idx) != shoulder_idx:
		return

	var target_local: Vector3 = skeleton.to_local(grip_left.global_transform.origin)
	var shoulder_pose := skeleton.get_bone_global_pose(shoulder_idx)
	var elbow_pose := skeleton.get_bone_global_pose(elbow_idx)
	var wrist_pose := skeleton.get_bone_global_pose(wrist_idx)

	var upper_len: float = shoulder_pose.origin.distance_to(elbow_pose.origin)
	var lower_len: float = elbow_pose.origin.distance_to(wrist_pose.origin)
	if upper_len < 0.001 or lower_len < 0.001:
		return

	var to_target: Vector3 = target_local - shoulder_pose.origin
	var target_len: float = clampf(to_target.length(), 0.001, upper_len + lower_len - 0.001)
	var axis_dir: Vector3 = to_target.normalized()

	# Law of cosines: angle at the shoulder between "shoulder->target" and
	# "shoulder->elbow" once bent to exactly reach target_len away.
	var cos_shoulder := (upper_len * upper_len + target_len * target_len - lower_len * lower_len) / (2.0 * upper_len * target_len)
	var shoulder_angle := acos(clampf(cos_shoulder, -1.0, 1.0))

	# Bend plane: keep whatever side the animation's own elbow already
	# bends toward (its current offset from the shoulder->target line),
	# so the elbow doesn't flip to a physically-wrong side.
	var current_elbow_offset: Vector3 = elbow_pose.origin - shoulder_pose.origin
	var pole_component: Vector3 = current_elbow_offset - axis_dir * current_elbow_offset.dot(axis_dir)
	if pole_component.length() < 0.001:
		pole_component = skeleton.global_transform.basis.z
	var pole_dir: Vector3 = pole_component.normalized()
	var hinge_axis: Vector3 = axis_dir.cross(pole_dir)
	if hinge_axis.length() < 0.001:
		return
	hinge_axis = hinge_axis.normalized()

	var new_upper_dir: Vector3 = axis_dir.rotated(hinge_axis, shoulder_angle).normalized()
	var new_elbow_pos: Vector3 = shoulder_pose.origin + new_upper_dir * upper_len

	var old_upper_dir: Vector3 = current_elbow_offset.normalized()
	var shoulder_delta := Basis(Quaternion(old_upper_dir, new_upper_dir))
	_set_bone_global_basis(shoulder_idx, shoulder_delta * shoulder_pose.basis)
	skeleton.force_update_all_bone_transforms()

	var old_lower_dir: Vector3 = (wrist_pose.origin - elbow_pose.origin).normalized()
	var new_lower_dir: Vector3 = (target_local - new_elbow_pos).normalized()
	var elbow_delta := Basis(Quaternion(old_lower_dir, new_lower_dir))
	_set_bone_global_basis(elbow_idx, elbow_delta * elbow_pose.basis)
	skeleton.force_update_all_bone_transforms()

## Sets bone_idx's pose so its resulting skeleton-local global basis is
## exactly desired_global_basis -- back-solving the local pose_rotation
## from Skeleton3D's own composition rule (global_pose = parent_global_pose
## * rest * pose), since set_bone_pose_rotation only takes a rest-relative
## local value, not a global one. Assumes the parent's global pose is
## already up to date (see force_update_all_bone_transforms callers).
func _set_bone_global_basis(bone_idx: int, desired_global_basis: Basis) -> void:
	var parent_idx := skeleton.get_bone_parent(bone_idx)
	var parent_global_basis: Basis = (
		skeleton.get_bone_global_pose(parent_idx).basis if parent_idx != -1 else Basis.IDENTITY
	)
	var rest_basis: Basis = skeleton.get_bone_rest(bone_idx).basis
	var pose_basis: Basis = rest_basis.inverse() * parent_global_basis.inverse() * desired_global_basis
	skeleton.set_bone_pose_rotation(bone_idx, pose_basis.get_rotation_quaternion())

## Applies GameState.show_grip_points live to every currently-equipped
## visual's GripMarker (the red sphere authored onto its GripPoint node --
## see e.g. IronGreatsword.tscn), so toggling it updates whatever's already
## equipped rather than only items equipped after the flag flipped.
func _on_grip_points_visibility_changed(visible_now: bool) -> void:
	for visual in _slot_visuals.values():
		_set_grip_marker_visible(visual, visible_now)
	if _gather_tool_visual != null and is_instance_valid(_gather_tool_visual):
		_set_grip_marker_visible(_gather_tool_visual, visible_now)
	for hand_offset in [weapon_grip_offset, weapon_grip_offset_left]:
		if hand_offset == null:
			continue
		var marker: Node = hand_offset.find_child("GripMarker", false, false)
		if marker is Node3D:
			marker.visible = visible_now

func _set_grip_marker_visible(visual: Node3D, visible_now: bool) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	for grip_name in ["GripPoint", "GripPointLeft"]:
		var grip: Node3D = visual.find_child(grip_name, false, false)
		if grip == null:
			continue
		var marker: Node = grip.find_child("GripMarker", false, false)
		if marker is Node3D:
			marker.visible = visible_now

func _align_to_grip_point(visual: Node3D, scale_factor: float) -> void:
	var scale_only := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_factor), Vector3.ZERO)
	var grip: Node3D = visual.find_child("GripPoint", false, false)
	if grip == null:
		visual.transform = scale_only
		return
	visual.transform = scale_only * grip.transform.affine_inverse()

## Whichever item_type is actually driving this unit's combat/animation
## right now -- the "two_hand" slot's occupant if it has one (a weapon
## gripped two-handed, see BACKPACK_SLOTS' doc comment), otherwise
## right_hand's (empty if unarmed). Damage/reach still come from
## right_hand's weapon alone even while dual-wielding (see
## _get_attack_damage/_get_melee_reach_bonus) -- only the ANIMATION picks
## up on left_hand also being occupied (see _get_attack_animation_name's
## "dual_wield" grip), so both weapons visibly swing without left_hand's
## one actually adding its own separate damage number.
func _get_active_weapon_item_type() -> String:
	return backpack["two_hand"] if not backpack["two_hand"].is_empty() else backpack["right_hand"]

## Resizes a hitbox's debug visual (HitboxMesh) to match the sphere
## Entity._land_hit_if_in_reach actually checks hits against -- same
## shape (a sphere) and same radius formula ((weapon's reach span)/2 *
## Entity.HIT_CHECK_SPHERE_SCALE), so bigger weapons show a visibly bigger
## sphere (greatsword > longsword > shortsword). Only sizes it here --
## _land_hit_if_in_reach itself repositions the hitbox every check to the
## standardized in-front-of-the-attacker point the hit is actually decided
## against (see its own doc comment for why hit detection no longer tracks
## the weapon's literal animated position), so this function doesn't need
## to position it at all; whatever position it's left at between swings is
## irrelevant since it's only visible while actively swinging. Resets back
## to a small sphere for an empty hand or a non-melee item (see
## UNARMED_HIT_OFFSETS). Takes an explicit hitbox (attack_hitbox for
## right_hand/two_hand, or attack_hitbox_left for left_hand -- see
## _set_slot) since either hand's weapon can change independently while
## dual-wielding.
func _update_attack_hitbox_size(hitbox: Area3D, item_type: String) -> void:
	if hitbox == null:
		return
	var offsets := ItemDefs.get_melee_hit_offsets(item_type)
	if offsets.is_empty():
		offsets = UNARMED_HIT_OFFSETS
	var start: float = offsets[0]
	var end: float = offsets[offsets.size() - 1]
	var sphere_radius: float = maxf((end - start) / 2.0, Entity.MIN_HIT_SPHERE_RADIUS) * Entity.HIT_CHECK_SPHERE_SCALE
	var hitbox_mesh: MeshInstance3D = hitbox.get_node_or_null("HitboxMesh")
	if hitbox_mesh == null:
		return
	var sphere := SphereMesh.new()
	sphere.radius = sphere_radius
	sphere.height = sphere_radius * 2.0
	hitbox_mesh.mesh = sphere

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

## Walks to `building` (an explicit right-click-while-Repair-pending order,
## see RTSController._issue_repair_order) and heals it once close enough,
## repeatedly, for as long as the order stands -- see _update_repair_target().
## Unlike pick_up_item, this doesn't clear itself after one tick: repairing
## is an ongoing action, only stopped by the building healing to full, dying,
## being freed, or the unit being given a new/no order (see stop()/move_to()).
##
## Walks to a point just outside the building's own footprint (same
## "approach range, not the target's own unreachable center" reasoning as
## attack()'s approach point -- see get_engage_radius_bonus()), not
## building.global_position directly: for anything bigger than a 1-tile
## building (e.g. Castle's 5x5), the center sits deep inside solid
## collision the nav agent can never actually reach, so it'd give up
## short of REPAIR_RANGE and just sit there not healing.
func repair_building(building: Building) -> void:
	move_to(_approach_point_for_building(building))
	repair_target = building

## Shared by repair_building()/seek_garrison() -- a point just outside
## `building`'s own footprint, on the side closest to this unit's current
## position, rather than building.global_position itself (unreachable/
## inside solid collision for anything bigger than a 1-tile building).
## `target` is typed as the shared Entity base, not Building, so
## gather_resource() can reuse this for a World resource node too --
## same "approach range, not the target's own unreachable center"
## reasoning applies to a Crystal Cave's own collision as much as a
## Castle's.
func _approach_point_for_building(target: Entity) -> Vector3:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var approach_distance: float = maxf(target.get_engage_radius_bonus() - 0.2, 0.1)
	if to_target.length() > 0.01:
		return target.global_position - to_target.normalized() * approach_distance
	return target.global_position

## Heals repair_target by REPAIR_RATE per second once within REPAIR_RANGE of
## it -- called every physics frame while a repair order is outstanding (see
## _physics_process, which passes its own delta through -- same convention
## as _update_attack_target(_delta), not get_physics_process_delta_time(),
## so this stays correct even when driven manually, e.g. in a test).
## Clears itself once the building's back to full health, or harmlessly if
## the building's gone (destroyed/freed) before/while this unit was working
## on it.
func _update_repair_target(delta: float) -> void:
	if not is_instance_valid(repair_target):
		repair_target = null
		return
	if repair_target.current_health >= repair_target.max_health:
		repair_target = null
		return
	# Matches repair_building()'s own approach point -- REPAIR_RANGE plus
	# the target's own footprint bonus, same reasoning as attack()/
	# _update_attack_target's engage-range check.
	var engage_range: float = REPAIR_RANGE + repair_target.get_engage_radius_bonus()
	if global_position.distance_to(repair_target.global_position) > engage_range:
		return
	repair_target.current_health = minf(
		repair_target.max_health, repair_target.current_health + REPAIR_RATE * delta
	)

## Walks to `building` (a just-placed foundation this unit was selected
## for when it was placed, or an explicit Repair-order click on an
## unfinished foundation -- see BuildPlacementController.confirm_placement/
## RTSController._issue_repair_click) and helps build it once close enough,
## same "ongoing action, only stopped by finishing/dying/being freed/a new
## order" shape repair_building has. Only "peasant" units may construct or
## repair buildings -- a no-op for anything else, matching this feature's
## own restriction (see RTSController's own peasant-only filtering at each
## call site, which this guard backs up rather than relies on alone).
func construct_building(building: Building) -> void:
	if unit_type_id != "peasant":
		return
	move_to(_approach_point_for_building(building))
	construct_target = building

## Advances construct_target's construction by `delta` seconds once within
## CONSTRUCT_RANGE of it -- called every physics frame while a construct
## order is outstanding (see _physics_process). Clears itself once the
## building finishes construction, or harmlessly if the building's gone
## before/while this unit was working on it.
func _update_construct_target(delta: float) -> void:
	if not is_instance_valid(construct_target):
		construct_target = null
		return
	if not construct_target.is_under_construction:
		construct_target = null
		return
	var engage_range: float = CONSTRUCT_RANGE + construct_target.get_engage_radius_bonus()
	if global_position.distance_to(construct_target.global_position) > engage_range:
		return
	construct_target.advance_construction(delta)

## Walks to `node` (an explicit right-click-on-a-resource-node order, see
## RTSController._handle_right_click) and gathers from it once (and for as
## long as it stays) close enough -- see _update_gather_target(). Only
## "peasant" units may gather -- a no-op for anything else, matching this
## game's peasant-only-labor design (see gather_target's own doc comment).
func gather_resource(node: World) -> void:
	if unit_type_id != "peasant":
		return
	move_to(_approach_point_for_building(node))
	gather_target = node
	_last_gather_resource_type = node.resource_type

## Remembers gather_target's own resource_type independent of gather_target
## itself -- needed because by the time _update_gather_target notices a
## node has run dry (either queue_free()'d entirely, for a "remove"-type
## node like Crystal Cave/Mist Fissure, or still there but with
## resource_type already cleared, for a "stump"-type tree -- see
## World._deplete), the node itself can no longer say what it used to
## yield. _auto_retask_gather reads this to know what to look for next.
var _last_gather_resource_type: String = ""

## Visual-only "pickaxe is out" instance, shown while actually playing
## Gather_Mine (see GATHER_TOOL_ANIMATIONS/_update_gather_tool_visual) --
## attached to weapon_grip_offset the same way _set_slot attaches a real
## equipped weapon, but this is never a backpack item (peasants don't
## equip pickaxes -- see gather_resource's own peasant-only-labor doc
## comment), so it's tracked separately from _slot_visuals instead of
## going through equip_item.
var _gather_tool_visual: Node3D = null
const GATHER_TOOL_SCENE: PackedScene = preload("res://scenes/MiningPickBase.tscn")
## Which gather animation(s) should have a tool visibly out -- only
## Gather_Mine (crystal, and mist as a placeholder -- see GATHER_ANIMATIONS'
## own doc comment) actually swings a tool; Gather_Pick is bare-handed fruit
## picking and shouldn't show one.
const GATHER_TOOL_ANIMATIONS: Dictionary = {"Gather_Mine": true}

## Shows/hides _gather_tool_visual to match whether `animation_name` is one
## that should have a tool out (see GATHER_TOOL_ANIMATIONS) -- called every
## physics frame from _update_gather_target with whatever animation (if
## any) currently applies, and with "" from its own two early-return
## branches once gathering stops entirely, so the pickaxe never lingers in
## a peasant's hand after the last node of that type is gone.
func _update_gather_tool_visual(animation_name: String) -> void:
	var wants_tool: bool = GATHER_TOOL_ANIMATIONS.has(animation_name)
	var has_tool: bool = _gather_tool_visual != null and is_instance_valid(_gather_tool_visual)
	if wants_tool == has_tool:
		return
	if wants_tool:
		_gather_tool_visual = GATHER_TOOL_SCENE.instantiate()
		weapon_grip_offset.add_child(_gather_tool_visual)
		_align_to_grip_point(_gather_tool_visual, GRIPPED_WEAPON_SCALE)
		_set_grip_marker_visible(_gather_tool_visual, GameState.show_grip_points)
	else:
		_gather_tool_visual.queue_free()
		_gather_tool_visual = null

## Once a gather order's own node runs dry (see _update_gather_target),
## automatically retasks this peasant to the nearest other node of the
## same resource type that still has something left -- the user's own
## "task itself to the nearest node of that type" request, so depleting an
## Oak Tree doesn't leave a peasant standing idle next to a stump when
## another Oak Tree (or any other acorn source) is right there. Silently
## does nothing if this unit was never gathering, or if nothing else of
## that type remains anywhere on the map. World nodes are never
## fog-hidden (RTSController's fog-of-war pass deliberately leaves the
## "world" group alone -- see World.gd's own doc comment), so this scans
## every matching node currently in the scene rather than needing an
## explicit line-of-sight/visibility check of its own -- picking the
## nearest is already "within sight" in every practical sense here.
func _auto_retask_gather() -> void:
	if _last_gather_resource_type.is_empty():
		return
	var best: World = null
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group("world"):
		if not is_instance_valid(node) or not node.visible:
			continue
		if node.resource_type != _last_gather_resource_type or not node.can_gather():
			continue
		var dist := global_position.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best = node
	if best != null:
		gather_resource(best)

## Which animation plays while planting a sapling -- "" (see
## PLANT_ANIMATION_SOURCES) means no dedicated clip exists yet, so
## planting just holds Idle for PLANT_TIME seconds.
const PLANT_ANIMATION_NAME: String = "Plant_Sapling"
const PLANT_ANIMATION_SOURCES: Dictionary = {
	"Plant_Sapling": {"scene": "res://assets/models/human_male/anims/PlantSapling.fbx", "clip": "mixamo_com"},
}
static var _plant_animation_cache: Dictionary = {}

func _ensure_plant_animation() -> bool:
	return _ensure_cross_scene_animation(PLANT_ANIMATION_NAME, PLANT_ANIMATION_SOURCES, _plant_animation_cache)

## Walks to `position` (an explicit Plant Oak/Apple click, see
## RTSController._issue_plant_click, which has already spent the resource
## cost by the time this is called) and, once (and for as long as it
## stays) close enough, spends PLANT_TIME seconds planting a sapling there
## -- see _update_plant_target(). `tree_scene` is instantiated only once
## that timer completes (see _finish_planting) -- an interrupted order
## (this unit dies, or is given a new order, before then) simply never
## plants anything; the already-spent resource is not refunded, matching
## how a cancelled/lost building foundation doesn't refund its cost either.
## Only "peasant" units may plant -- a no-op for anything else, matching
## gather_resource's own peasant-only-labor guard.
func order_plant(tree_scene: PackedScene, position: Vector3) -> void:
	if unit_type_id != "peasant":
		return
	move_to(position)
	_plant_tree_scene = tree_scene
	plant_target_position = position
	_plant_timer = 0.0

## Advances a plant order once within PLANT_RANGE of plant_target_position
## -- faces the spot (same atan2/_face_angle pattern _update_gather_target
## uses) and plays PLANT_ANIMATION_NAME once its clip exists (see
## _ensure_plant_animation) while _plant_timer accumulates. Once PLANT_TIME
## is reached, actually creates the sapling and clears the order.
func _update_plant_target(delta: float) -> void:
	if plant_target_position == Vector3.INF:
		return
	var to_target := plant_target_position - global_position
	if to_target.length() > PLANT_RANGE:
		return
	if to_target.length() > 0.01:
		_face_angle(atan2(to_target.x, to_target.z), delta)
	if _ensure_plant_animation() and animation_player.current_animation != PLANT_ANIMATION_NAME:
		animation_player.play(PLANT_ANIMATION_NAME, ANIMATION_BLEND_TIME)
	_plant_timer += delta
	if _plant_timer < PLANT_TIME:
		return
	_finish_planting()

## Actually creates the sapling once PLANT_TIME elapses (see
## _update_plant_target) -- Gaia-owned (player_id GameState.NATURE_PLAYER_ID),
## not the planting player's, same reasoning RTSController._issue_plant_click
## used to have as its own doc comment (every other resource node in this
## game is neutral and gatherable by anyone, so a planted tree stays
## consistent with that).
func _finish_planting() -> void:
	var scene := _plant_tree_scene
	var position := plant_target_position
	plant_target_position = Vector3.INF
	_plant_tree_scene = null
	if scene == null:
		return
	var world_node := get_tree().current_scene.get_node_or_null("World")
	if world_node == null:
		return
	var tree: World = scene.instantiate()
	# Set before add_child, not after -- _ready() (which reads is_seedling
	# to scale the model down, see World.gd) fires the moment this joins
	# the tree, so setting these afterward would be too late for that
	# first-frame setup to see them.
	tree.player_id = GameState.NATURE_PLAYER_ID
	tree.is_seedling = true
	# force_readable_name=true -- see BuildPlacementController.confirm_placement's
	# identical fix for why.
	world_node.add_child(tree, true)
	tree.global_position = position
	# Re-bakes the navmesh now that this tree actually exists as an
	# obstacle (see NavGroundSetup.bake's own doc comment for why a caller
	# that adds obstacles after the region's first _ready() bake needs to
	# call this again) -- without it, a freshly planted tree would sit
	# there as a real collidable obstacle that units could still be routed
	# straight through, since the navmesh baked before it ever existed.
	var nav_region := get_tree().current_scene.get_node_or_null("NavigationRegion3D")
	if nav_region != null:
		nav_region.bake()

## Which gather animation plays for each resource type -- "" (no entry)
## means no dedicated clip exists yet, so gathering just holds Idle.
## "Gather_Pick" (Mixamo's "Pick Fruit", hand-picking motion) covers
## Acorns/Apples since both are picked by hand; "Gather_Mine" (Mixamo's
## "Heavy Weapon Swing") covers Crystal, mined with a pickaxe -- and
## temporarily stands in for Mist too (breathed in, no tool -- a swinging
## motion doesn't actually match that verb, but it's a placeholder until
## a real breathing-in/inhale clip is found, closer to "something is
## visibly happening" than plain Idle in the meantime). See
## GATHER_ANIMATION_SOURCES for where a real Mist clip would get added.
const GATHER_ANIMATIONS: Dictionary = {
	"acorns": "Gather_Pick",
	"apples": "Gather_Pick",
	"crystal": "Gather_Mine",
	"mist": "Gather_Mine",
}
## animation name -> {scene, clip} to pull it from, cached into every
## Unit's own AnimationPlayer library on first use (see
## _ensure_gather_animation) -- add an entry here (plus a matching
## GATHER_ANIMATIONS mapping above) whenever a new gather clip is found
## (Mist still needs one).
## "trim_length" (optional): clamps the played length to cut a long dead
## hold off the tail of a clip padded that way (see PickFruit -- no, see
## HeavyWeaponSwing's own former use of this before "loop_start"/"loop_end"
## replaced it here) without touching the motion before the cut.
## "loop_start"/"loop_end" (optional, takes priority over "trim_length"):
## crops the clip down to just this window and shifts every remaining key
## so playback starts at t=0 -- used instead of "trim_length" when the
## clip's very first frame (a whole-body wind-up reached only once, easing
## in from a stand-still idle) never recurs later in the clip, so a plain
## LOOP_LINEAR restart back to frame 0 visibly pops instead of reading as
## one continuous motion. HeavyWeaponSwing.fbx is exactly this case: it
## opens with a big two-swing wind-up (t=0 to ~2.9s) before settling into a
## steady one-swing-per-cycle rhythm, and its own tail (past ~5.4s) is a
## long frozen held pose the exporter padded the file with. 2.972/4.672
## were picked by sampling mixamorig_RightHand's own bone pose across the
## clip and finding the closest-matching pair of times in that steady
## rhythm (within ~2mm of each other) -- looping between exactly those two
## points means every repeat is one clean single swing with no visible
## seam, at the cost of skipping the clip's unique opening wind-up.
const GATHER_ANIMATION_SOURCES: Dictionary = {
	"Gather_Pick": {"scene": "res://assets/models/human_male/anims/PickFruit.fbx", "clip": "mixamo_com"},
	"Gather_Mine": {"scene": "res://assets/models/human_male/anims/HeavyWeaponSwing.fbx", "clip": "mixamo_com", "loop_start": 2.972, "loop_end": 4.672},
}
## Cache of already-extracted gather Animation resources, keyed by the
## same name GATHER_ANIMATIONS/GATHER_ANIMATION_SOURCES use -- loaded
## once per name (not once per Unit instance) since instantiating the
## source scene just to read its Animation resource is wasted work
## beyond the first Unit that ever needs it.
static var _gather_animation_cache: Dictionary = {}

## Pulls `animation_name`'s Animation resource out of its source scene
## (see GATHER_ANIMATION_SOURCES) the first time any Unit needs it, and
## adds it to this unit's own AnimationPlayer library so animation_player.
## play(animation_name) works exactly like any of its native clips (Idle/
## Walk/Attack). A no-op once already added to this particular unit.
func _ensure_gather_animation(animation_name: String) -> bool:
	return _ensure_cross_scene_animation(animation_name, GATHER_ANIMATION_SOURCES, _gather_animation_cache, true)

## Shared machinery behind _ensure_gather_animation and _ensure_plant_animation
## -- pulls `animation_name`'s Animation resource out of its source scene
## (looked up in `sources`, e.g. GATHER_ANIMATION_SOURCES/PLANT_ANIMATION_SOURCES)
## the first time any Unit needs it, caching the extracted, corrected result
## into `cache` (that caller's own static dict, so it's shared across every
## Unit instance -- see _gather_animation_cache's own doc comment), and adds
## it to THIS unit's own AnimationPlayer library so animation_player.
## play(animation_name) works exactly like any of its native clips (Idle/
## Walk/Attack). A no-op once already added to this particular unit.
## `lock_hips` (gather clips only, not planting -- see
## _ensure_gather_animation/_ensure_plant_animation's own call sites) is
## passed straight through to _retarget_root_bone_tracks -- see its own
## doc comment for why a gathering unit's Hips (and, by extension, its legs,
## which have no track of their own and just follow Hips down the chain)
## should stay put while Plant_Sapling's own intentional kneel still wants
## Hips free to move.
func _ensure_cross_scene_animation(animation_name: String, sources: Dictionary, cache: Dictionary, lock_hips: bool = false) -> bool:
	if animation_player == null or not sources.has(animation_name):
		return false
	if animation_player.has_animation(animation_name):
		return true
	if not cache.has(animation_name):
		var source: Dictionary = sources[animation_name]
		var temp: Node = (load(source["scene"]) as PackedScene).instantiate()
		var src_player: AnimationPlayer = temp.find_child("AnimationPlayer", true, false)
		var anim: Animation = null
		if src_player != null and src_player.has_animation(source["clip"]):
			anim = (src_player.get_animation(source["clip"]) as Animation).duplicate()
			# Mixamo clips aren't authored as looping -- gathering (and
			# planting, which can also outlast one play-through) can run
			# far longer than one play-through, so without this it would
			# freeze on the last frame instead of repeating the motion.
			anim.loop_mode = Animation.LOOP_LINEAR
			# The source FBX's own AnimationPlayer sits directly beside its
			# Skeleton3D (track paths like "Skeleton3D:mixamorig_Hips"), but
			# this unit's model nests its skeleton one level deeper, under
			# an Armature node (ParentUnit.tscn's "PeasantMale/Armature/
			# Skeleton3D") -- so those same track paths resolve to nothing
			# once added to this unit's own AnimationPlayer library, and the
			# clip "plays" (current_animation updates) while visibly doing
			# nothing. Rewrite each bone track's path to go through Armature
			# first so it actually resolves against this unit's skeleton.
			for i in range(anim.get_track_count()):
				var track_path: NodePath = anim.track_get_path(i)
				if String(track_path).begins_with("Skeleton3D"):
					anim.track_set_path(i, NodePath("Armature/" + String(track_path)))
			# The source FBX's root bone (Hips) has a different rest-pose
			# orientation than this unit's own skeleton -- every other bone
			# happens to share (near enough) the same rest basis, but Hips
			# being 90 degrees off is enough to rotate the whole body onto
			# its side once the raw source keys are applied directly to this
			# skeleton. Re-express the root bone's tracks in this skeleton's
			# own rest-basis convention so the pose comes out upright.
			_retarget_root_bone_tracks(anim, temp, lock_hips)
			if source.has("loop_start"):
				_crop_and_shift_animation(anim, source["loop_start"], source["loop_end"])
			elif source.has("trim_length"):
				anim.length = source["trim_length"]
		temp.free()
		cache[animation_name] = anim
	var cached: Animation = cache[animation_name]
	if cached == null:
		return false
	animation_player.get_animation_library("").add_animation(animation_name, cached)
	return true

## Crops `anim` down to just the [start, end] window and shifts every
## remaining key so playback starts at t=0 -- see GATHER_ANIMATION_SOURCES'
## own "loop_start"/"loop_end" doc comment for why this exists instead of
## just clamping anim.length from t=0.
func _crop_and_shift_animation(anim: Animation, start: float, end: float) -> void:
	for i in range(anim.get_track_count()):
		for k in range(anim.track_get_key_count(i) - 1, -1, -1):
			var t: float = anim.track_get_key_time(i, k)
			if t < start or t > end:
				anim.track_remove_key(i, k)
		for k in range(anim.track_get_key_count(i)):
			anim.track_set_key_time(i, k, anim.track_get_key_time(i, k) - start)
	anim.length = end - start

## Corrects `anim`'s root-bone (Hips) tracks for the rest-basis mismatch
## between `source_scene`'s skeleton and this unit's own -- see
## _ensure_gather_animation's call site comment for why only the root
## bone needs this. Converts each keyframe from the source rig's rest
## frame into this unit's rest frame via the two rest bases' relative
## rotation, so the pose composes correctly once played on this unit's
## own skeleton instead of coming out rotated onto its side.
func _retarget_root_bone_tracks(anim: Animation, source_scene: Node, lock_rotation: bool = false) -> void:
	var target_skeleton: Skeleton3D = animation_player.get_parent().find_child("Skeleton3D", true, false)
	var source_skeleton: Skeleton3D = source_scene.find_child("Skeleton3D", true, false)
	if target_skeleton == null or source_skeleton == null or target_skeleton.get_bone_count() == 0:
		return
	var root_bone_name := target_skeleton.get_bone_name(0)
	var source_root_idx := source_skeleton.find_bone(root_bone_name)
	if source_root_idx == -1:
		return
	var target_rest: Transform3D = target_skeleton.get_bone_rest(0)
	var target_rest_basis: Basis = target_rest.basis
	var source_rest_basis: Basis = source_skeleton.get_bone_rest(source_root_idx).basis
	var correction: Basis = target_rest_basis.inverse() * source_rest_basis
	var correction_quat := Quaternion(correction)
	for i in range(anim.get_track_count()):
		if not String(anim.track_get_path(i)).ends_with(":" + root_bone_name):
			continue
		var track_type := anim.track_get_type(i)
		for k in range(anim.track_get_key_count(i)):
			if track_type == Animation.TYPE_POSITION_3D:
				# Pinned to this unit's own rest position outright, not
				# corrected-and-kept, and NOT zeroed either -- a position
				# track key is the bone's absolute local position, not a
				# delta from rest (Godot's skeleton-animation convention
				# for this track type), so every source keyframe already
				# encodes the SOURCE rig's own Hips rest offset (its own
				# skeleton's hip-to-parent distance) as its literal value.
				# Applying that source-scale value as-is -- or, worse,
				# zeroing it outright, which collapses this unit's own
				# Hips to its parent's exact origin instead of its natural
				# rest offset -- displaces the root by whatever that
				# mismatch is, and this unit's model is scaled 190x at the
				# ModelRoot level (see ParentUnit.tscn's own PeasantMale
				# transform), so even a small mismatch there turns into
				# nearly a full meter of unwanted offset once that scale
				# applies -- visibly sinking the whole character through
				# the floor for the clip's entire duration (everything
				# below Hips in the chain drags along with it), not just
				# at one keyframe. None of these cross-scene clips are
				# meant to carry root motion anyway (a gathering/planting
				# unit should stay exactly where its own gameplay position
				# already put it), so holding Hips at this unit's own rest
				# position for every single frame is correct, not a
				# compromise -- see the Idle animation's own identical
				# convention (no baked root motion at all) for why this
				# matches how every native clip already behaves.
				anim.track_set_key_value(i, k, target_rest.origin)
			elif track_type == Animation.TYPE_ROTATION_3D:
				if lock_rotation:
					# Pinned to this unit's own rest rotation, same reasoning
					# as the position pin just above, for gather clips
					# specifically: the legs keep their own tracks (they
					# animate normally, which is what actually makes them
					# look natural), but they have no foot-planting IK to
					# compensate for the pelvis moving -- if Hips still
					# swayed with the source clip's own hip motion, the legs'
					# already-correct local bend would ride along with that
					# extra sway and lift the feet off the ground mid-swing.
					# Locking just Hips' rotation to rest keeps the pelvis a
					# fixed anchor for the legs to bend from while the spine/
					# arms still carry the swing -- not needed for
					# Plant_Sapling, whose own kneel-down motion actually
					# wants Hips to rotate.
					anim.track_set_key_value(i, k, Quaternion(target_rest_basis))
				else:
					var q: Quaternion = anim.track_get_key_value(i, k)
					anim.track_set_key_value(i, k, correction_quat.inverse() * q)

## Gathers GATHER_RATE*delta worth of resource from gather_target once
## within GATHER_RANGE of it, handing the result straight into the human
## player's bank (see World.gather/ResourceHUD.add_resource) -- called
## every physics frame while a gather order is outstanding (see
## _physics_process). Clears itself once the node depletes/is freed, or
## harmlessly if it was already gone before this unit arrived.
func _update_gather_target(delta: float) -> void:
	if not is_instance_valid(gather_target):
		gather_target = null
		_update_gather_tool_visual("")
		_auto_retask_gather()
		return
	if not gather_target.can_gather():
		gather_target = null
		_update_gather_tool_visual("")
		_auto_retask_gather()
		return
	var engage_range: float = GATHER_RANGE + gather_target.get_engage_radius_bonus()
	var to_target := gather_target.global_position - global_position
	if to_target.length() > engage_range:
		return
	# Faces the resource node's own center while gathering it -- same
	# atan2/_face_angle pattern _update_attack_target uses to turn a
	# unit toward its attack_target each frame, just for a static World
	# node instead of a moving Entity.
	if to_target.length() > 0.01:
		_face_angle(atan2(to_target.x, to_target.z), delta)
	# Play (once started, keeps playing via its own loop_mode -- see
	# _ensure_gather_animation) whichever gather animation this resource
	# type maps to, if any exists yet -- _update_locomotion_animation's own
	# gather_target check keeps this from being stomped back to Idle every
	# frame while it plays.
	var animation_name: String = GATHER_ANIMATIONS.get(gather_target.resource_type, "")
	if not animation_name.is_empty() and _ensure_gather_animation(animation_name) and animation_player.current_animation != animation_name:
		animation_player.play(animation_name, ANIMATION_BLEND_TIME)
	_update_gather_tool_visual(animation_name)
	var resource_hud: ResourceHUD = get_tree().current_scene.get_node_or_null("UI/ResourceHUD")
	if resource_hud == null:
		return
	# Path of Desire -- see PathPerks.gather_rate_multiplier's own doc
	# comment. Path of Corruption (the enemy-side slow) is applied inside
	# World.gather() itself, not here, since it depends on this
	# gathering unit's proximity to whichever enemy owns Corruption.
	var rate := GATHER_RATE * PathPerks.gather_rate_multiplier(player_id)
	gather_target.gather(rate * delta, resource_hud, player_id)

## Walks to `building` (Garrison's explicit click-a-building order, see
## RTSController._issue_garrison_click, or Seek Shelter's own automatic
## nearest-building pick, see RTSController._on_command_card_seek_shelter_pressed)
## and actually enters it once close enough -- see _update_garrison_target().
## A no-op if the building has no room at all right now (still worth
## calling: capacity can free up -- a garrisoned unit leaving -- before
## this unit arrives, so it keeps walking and re-checks every tick rather
## than giving up immediately).
func seek_garrison(building: Building) -> void:
	move_to(_approach_point_for_building(building))
	garrison_target = building

## Actually enters garrison_target once within GARRISON_RANGE of it and it
## still has room -- called every physics frame while a garrison order is
## outstanding (see _physics_process). Clears itself harmlessly if the
## building's gone, or if it's already full when this unit finally arrives
## (someone else took the last spot first).
func _update_garrison_target() -> void:
	if not is_instance_valid(garrison_target):
		garrison_target = null
		return
	var engage_range: float = GARRISON_RANGE + garrison_target.get_engage_radius_bonus()
	if global_position.distance_to(garrison_target.global_position) > engage_range:
		return
	var building := garrison_target
	garrison_target = null
	garrison_in(building)

## Actually hides/disables this unit and registers it with `building` --
## the "inside" state _update_garrison_target transitions into once close
## enough. Returns false (no change) if the building has no room; true on
## success. Stays in the "units" group throughout (still owned, still
## counts toward RTSController.get_player_score) -- garrisoned is a state
## a unit is in, not something that removes it from play.
func garrison_in(building: Building) -> bool:
	if not building.add_garrisoned_unit(self):
		return false
	stop()
	garrisoned_in = building
	_pre_garrison_collision_layer = collision_layer
	_pre_garrison_collision_mask = collision_mask
	visible = false
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	global_position = building.global_position
	return true

## Reverses garrison_in() -- pops this unit back out just outside
## garrisoned_in's footprint (see UNGARRISON_OFFSET), restoring visibility/
## collision/processing. A no-op if this unit isn't actually garrisoned
## anywhere. Called both by an explicit future ungarrison command and by
## Building._die() (a destroyed building can't keep holding anyone).
func ungarrison() -> void:
	if garrisoned_in == null:
		return
	var building := garrisoned_in
	garrisoned_in = null
	if is_instance_valid(building):
		building.remove_garrisoned_unit(self)
		var offset := Vector3(UNGARRISON_OFFSET, 0, 0)
		if building.get_engage_radius_bonus() > 0.0:
			offset = Vector3(building.get_engage_radius_bonus() + 0.2, 0, 0)
		global_position = building.global_position + offset
	visible = true
	collision_layer = _pre_garrison_collision_layer
	collision_mask = _pre_garrison_collision_mask
	set_physics_process(true)

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

## Fully removes `item_type` from wherever it's equipped -- the dedicated
## "two_hand" slot if that's where it actually is (gripped two-handed --
## a "two_hand" item always is; a "hybrid_hand" one only when nothing
## else made it yield a hand -- see Unit.equip_item), or just
## `source_slot` otherwise.
func unequip_item_fully(item_type: String, source_slot: String) -> void:
	if backpack["two_hand"] == item_type:
		unequip_slot("two_hand")
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

## Path of Purity: true once this unit has gone PURITY_SHIELD_RESET_TIME
## seconds without taking a hit (see _physics_process's own tick below) --
## "every fight" (not "ever") needs a shield that recharges once combat
## actually stops, not a one-time thing spent forever on the first hit
## of the whole match.
const PURITY_SHIELD_RESET_TIME: float = 6.0
var _purity_shield_ready: bool = true
var _time_since_last_hit: float = PURITY_SHIELD_RESET_TIME

## Overrides Entity's own always-refuse default -- see PathPerks.has_purity's
## own doc comment. Consuming the shield blocks take_damage's caller from
## applying any damage at all this hit (see Entity.take_damage), and
## starts the recharge clock over.
func _try_consume_purity_shield() -> bool:
	if not PathPerks.has_purity(player_id) or not _purity_shield_ready:
		_time_since_last_hit = 0.0
		return false
	_purity_shield_ready = false
	_time_since_last_hit = 0.0
	return true

func _physics_process(_delta: float) -> void:
	if is_dying():
		return
	if _attack_cooldown_remaining > 0.0:
		_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - _delta, 0.0)

	if not _purity_shield_ready:
		_time_since_last_hit += _delta
		if _time_since_last_hit >= PURITY_SHIELD_RESET_TIME:
			_purity_shield_ready = true

	# Path of Faith -- see PathPerks.hp_regen_fraction_per_second's own
	# doc comment. Gameplay state (heals current_health), so this lives
	# on the fixed simulation tick, not _process.
	var regen_fraction := PathPerks.hp_regen_fraction_per_second(player_id)
	if regen_fraction > 0.0 and current_health < max_health and current_health > 0.0:
		current_health = minf(max_health, current_health + max_health * regen_fraction * _delta)

	if _pickup_target != null:
		_update_pickup_target()

	if repair_target != null:
		_update_repair_target(_delta)

	if construct_target != null:
		_update_construct_target(_delta)

	if gather_target != null:
		_update_gather_target(_delta)

	if plant_target_position != Vector3.INF:
		_update_plant_target(_delta)

	if garrison_target != null:
		_update_garrison_target()

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
	# _update_locomotion_animation itself is presentation-only (just
	# triggers animation_player.play(), no gameplay effect) -- see
	# _process() below, which is where it actually runs now, off this
	# fixed-rate simulation tick so per-frame animation/crossfade cost
	# doesn't scale with physics tick rate as unit count grows.

## Plays Walk while actually translating and Idle otherwise (arriving,
## standing between orders, mid-attack-approach before it's in range) --
## guarded by current_animation so it doesn't restart the clip every single
## frame. Swaps in the "_TwoHanded" variant of either (Idle_TwoHanded/
## Walk_TwoHanded, both hands visibly on the grip throughout, not just
## during the attack swing) whenever anything's actually sitting in the
## "two_hand" slot -- a strict two_hand item (e.g. "iron_greatsword")
## just as much as a hybrid_hand one currently gripped two-handed, since
## either way both hands are visually occupied the same way -- falling
## back to the bare Idle/Walk if that variant doesn't exist for some
## reason. No-op for entities with no
## AnimationPlayer (e.g. the older sprite-billboard peasant, if one still
## exists). Always deferred to while a triggered one-shot animation (any
## "Attack"-prefixed clip -- see Entity._get_attack_animation_name(),
## which picks a weapon-specific one like "Attack_Sword" over the
## bare-handed "Attack") is still playing, so e.g. a target dying
## mid-swing and clearing attack_target doesn't snap the model back to
## Walk/Idle before the swing finishes.
func _update_locomotion_animation(is_moving: bool) -> void:
	if animation_player == null:
		return
	if animation_player.is_playing() and animation_player.current_animation.begins_with("Attack"):
		return
	# Same "don't fight the other system's own animation control" reasoning
	# as the Attack guard above -- while actively gathering (in range, not
	# just walking there), _update_gather_target owns which animation
	# plays; without this, this function would stomp it back to Idle every
	# single frame the instant it started (is_moving is false while
	# standing at a resource node).
	if gather_target != null and is_instance_valid(gather_target) and gather_target.can_gather():
		var engage_range: float = GATHER_RANGE + gather_target.get_engage_radius_bonus()
		if global_position.distance_to(gather_target.global_position) <= engage_range:
			return
	# Same reasoning as the gather guard just above -- while actively
	# planting (in range, not just walking there), _update_plant_target
	# owns which animation plays.
	if plant_target_position != Vector3.INF and global_position.distance_to(plant_target_position) <= PLANT_RANGE:
		return
	# animation_player.speed_scale is a global AnimationPlayer property that
	# CombatBehavior.perform_attack mutates directly for the attack swing's
	# own timing (never scoped to just that clip) -- force it back to
	# native 1.0 here every frame we're not mid-attack so Walk/Idle always
	# play at their original authored speed regardless of whatever the
	# last attack left it at.
	animation_player.speed_scale = 1.0
	var base_animation := "Walk" if is_moving else "Idle"
	var two_handed_animation := base_animation + "_TwoHanded"
	var gripped_two_handed: bool = not backpack["two_hand"].is_empty()
	var target_animation := two_handed_animation if gripped_two_handed and animation_player.has_animation(two_handed_animation) else base_animation
	if animation_player.current_animation != target_animation and animation_player.has_animation(target_animation):
		animation_player.play(target_animation, ANIMATION_BLEND_TIME)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	_safe_velocity = safe_velocity

## Swings whatever's actually driving this unit's combat right now (see
## _get_active_weapon_item_type) -- a "sword" gets its own dedicated
## clip, chosen by CURRENT grip rather than just its item_type -- sitting
## in the dedicated "two_hand" slot (gripped two-handed -- see
## equip_item) swings with a "two_hand" clip ("Attack_TwoHanded"), the
## same category a strict two_hand weapon would use once given one;
## sitting in right_hand ALONE swings with its own "one_hand" clip
## ("Attack_Sword"); sitting in right_hand WITH left_hand also occupied
## (dual-wielding two weapons at once) swings with a "dual_wield" clip
## ("Attack_DualWield") instead, showing both weapons in the strike
## rather than just the right-hand one -- see _get_active_weapon_item_type's
## doc comment for why damage still only comes from right_hand's weapon
## even though the animation reacts to left_hand too. Anything without a
## dedicated clip for its current grip (a missing animation, or an item
## with none defined at all, e.g. "crossbow" -- ranged, no melee swing to
## animate) falls back to the bare-handed punch. Keyed off backpack
## directly rather than the equipped visual node, since that's the single
## source of truth for what's actually equipped (see equip_item/_set_slot).
const WEAPON_ATTACK_ANIMATIONS: Dictionary = {
	"sword": {"one_hand": "Attack_Sword", "two_hand": "Attack_TwoHanded", "dual_wield": "Attack_DualWield"},
	"steel_longsword": {"one_hand": "Attack_Sword", "two_hand": "Attack_TwoHanded", "dual_wield": "Attack_DualWield"},
	"iron_greatsword": {"two_hand": "Attack_TwoHanded"},
	"iron_shortsword": {"one_hand": "Attack_Sword", "dual_wield": "Attack_DualWield"},
	"iron_dagger": {"one_hand": "Attack_Sword", "dual_wield": "Attack_DualWield"},
}

func _get_attack_animation_name() -> String:
	var item_type := _get_active_weapon_item_type()
	var animations: Dictionary = WEAPON_ATTACK_ANIMATIONS.get(item_type, {})
	var grip := "one_hand"
	if not backpack["two_hand"].is_empty():
		grip = "two_hand"
	elif not backpack["right_hand"].is_empty() and not backpack["left_hand"].is_empty():
		grip = "dual_wield"
	var animation_name: String = animations.get(grip, "")
	if not animation_name.is_empty() and animation_player != null and animation_player.has_animation(animation_name):
		return animation_name
	return _get_attack_animation_name_fallback(item_type)

## Falls back to the "one_hand" clip when "dual_wield" was picked but
## Attack_DualWield doesn't exist yet (e.g. before an animation has been
## imported for it -- see _get_attack_animation_name), rather than
## dropping straight to the bare-handed punch just because the off-hand
## happens to be occupied too. Still ends at the bare "Attack" if even
## that's missing.
func _get_attack_animation_name_fallback(item_type: String) -> String:
	var animations: Dictionary = WEAPON_ATTACK_ANIMATIONS.get(item_type, {})
	var one_hand_name: String = animations.get("one_hand", "")
	if not one_hand_name.is_empty() and animation_player != null and animation_player.has_animation(one_hand_name):
		return one_hand_name
	return "Attack"

## No longer overrides this to show race in place of the unit's actual
## name (e.g. "Unit2") -- the tooltip now shows the real name as its
## title, with race/faction shown separately at the tooltip's bottom-left
## (see ItemTooltipPanel.show_entity) instead of replacing the name
## entirely. Falls back to Entity's own base implementation
## (Entity.display_name_for(self)) unmodified.

## Adds Level/Attack rows to the hover tooltip (see
## Entity.get_tooltip_extra_stats, RTSController._update_map_item_hover)
## -- Building/World don't have a level or attack concept at all, so
## only Unit overrides this. _get_attack_damage() rather than
## attack_damage directly, so an equipped weapon's damage shows here
## too, not just the unarmed default.
func get_tooltip_extra_stats() -> Dictionary:
	return {"Level": level, "Attack": "%d" % _get_attack_damage()}

## Bonus damage/attack-speed multipliers for a hybrid_hand weapon
## gripped two-handed (see BACKPACK_SLOTS' doc comment) -- swinging it
## with both hands hits harder AND faster than one-handed/dual-wielded,
## on top of whatever its own base stats already are. Neither applies
## to a strict "two_hand" item (e.g. "iron_greatsword") -- that's always
## two-handed to begin with, its own stats already account for that,
## there's no one-handed baseline to be a bonus "over".
## Weapon visuals are sized to read clearly as a world pickup; shrunk by
## this factor only once gripped in a unit's hand so they don't look
## oversized relative to the unit itself.
const GRIPPED_WEAPON_SCALE: float = 1.41
## Armor visuals, unlike weapons, are authored to fit the body directly
## (there's no separate "read clearly on the ground" size to shrink down
## from -- a pickup crate/icon represents them there instead, same as
## armor already has no world-pickup visual distinct from its equipped
## one). 1.0 until an actual armor asset says otherwise.
const EQUIPPED_ARMOR_SCALE: float = 1.0

const TWO_HANDED_HYBRID_DAMAGE_MULTIPLIER: float = 1.25
const TWO_HANDED_HYBRID_ATTACK_SPEED_MULTIPLIER: float = 1.25

## True whenever the active weapon is a hybrid_hand one currently
## gripped two-handed -- shared by _get_attack_damage and
## _get_attack_cooldown so both bonuses key off the exact same check.
func _is_two_handed_hybrid_grip() -> bool:
	return not backpack["two_hand"].is_empty() and ItemDefs.get_slot_kind(_get_active_weapon_item_type()) == "hybrid_hand"

## Swaps in a weapon's own damage (see ItemDefs.get_damage) over the
## unarmed default -- an unequipped hand, or an item with no defined
## weapon damage (e.g. one not actually meant to be wielded), just falls
## back to attack_damage unmodified. item_type "" (the default) means the
## active weapon (_get_active_weapon_item_type -- right_hand/two_hand),
## which also gets TWO_HANDED_HYBRID_DAMAGE_MULTIPLIER applied when
## gripped two-handed; an explicit item_type (see perform_attack's
## left_item_type, for left_hand's weapon while dual-wielding) is used as
## given, with no two-handed bonus -- left_hand is never in a two-handed
## grip to begin with (see BACKPACK_SLOTS' doc comment).
func _get_attack_damage(item_type: String = "") -> float:
	var is_active := item_type.is_empty()
	var weapon_type := item_type if not is_active else _get_active_weapon_item_type()
	var weapon_damage := ItemDefs.get_damage(weapon_type)
	var base_damage := attack_damage if weapon_damage < 0.0 else weapon_damage
	if weapon_damage >= 0.0 and is_active and _is_two_handed_hybrid_grip():
		base_damage *= TWO_HANDED_HYBRID_DAMAGE_MULTIPLIER
	# Path of Chivalry -- see PathPerks.melee_damage_multiplier's own doc
	# comment for why this applies to every attack (melee is all this
	# project has) rather than a "Knight" unit type it has no equivalent of.
	return base_damage * PathPerks.melee_damage_multiplier(player_id)

## Whichever item_type is actually sitting in left_hand right now, or ""
## if it's empty -- see Entity._get_left_hand_weapon_item_type's doc
## comment for how perform_attack() uses this.
func _get_left_hand_weapon_item_type() -> String:
	return backpack["left_hand"]

## Shortens the cooldown by TWO_HANDED_HYBRID_ATTACK_SPEED_MULTIPLIER
## (a faster attack rate) when gripped two-handed -- see
## Entity._get_attack_cooldown, which perform_attack() actually reads.
func _get_attack_cooldown() -> float:
	var cooldown := attack_cooldown
	if _is_two_handed_hybrid_grip():
		cooldown /= TWO_HANDED_HYBRID_ATTACK_SPEED_MULTIPLIER
	# Path of Chaos -- see PathPerks.attack_speed_multiplier's own doc
	# comment.
	return cooldown / PathPerks.attack_speed_multiplier(player_id)

## The [crossguard, tip] capsule endpoints Entity._land_hit_if_in_reach
## checks a hit against along the equipped weapon's own length (see
## ItemDefs.get_melee_hit_offsets), instead of just one point at the fist
## -- a real capsule check now, not a handful of sampled points, so a
## sword can land a hit anywhere along its full edge. An unequipped hand,
## or an item with no offsets defined (e.g. the crossbow), falls back to
## the unarmed fist span (UNARMED_HIT_OFFSETS) rather than one bare point
## -- same capsule idea applied to a fist instead of a blade (a
## zero-length one, since UNARMED_HIT_OFFSETS is a single point).
func _get_melee_hit_offsets(item_type: String = "") -> Array:
	var weapon_type := item_type if not item_type.is_empty() else _get_active_weapon_item_type()
	var offsets := ItemDefs.get_melee_hit_offsets(weapon_type)
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
