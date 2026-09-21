extends RefCounted
class_name CombatBehavior
## Extracted from Entity.gd -- perform_attack()/_run_hit_check_window()/
## _land_hit_if_in_reach(), the actual swing-timing and hit-detection
## logic behind every entity's melee attack. Kept as a plain delegate
## object (not a scene-tree Node) owned by whichever Entity instance
## it fights for, rather than folded into a full ECS-style component
## system -- see the architecture-cleanup plan's own notes on why a full
## rewrite wasn't worth the risk/cost at this project's scale, but this
## one self-contained, verifiable-in-isolation chunk was.
##
## Calls back into `_owner` (`_owner._get_attack_animation_name()`,
## `_owner._get_attack_damage()`, `_owner._get_melee_reach()`,
## `_owner._get_melee_hit_offsets()`,
## `_owner._get_left_hand_weapon_item_type()`,
## `_owner._get_attack_cooldown()`) for every hook Unit.gd polymorphically
## overrides, rather than duplicating them here -- those overrides only
## work through Godot's normal class inheritance (Entity -> Unit), which
## a delegate object sitting outside that hierarchy can't participate in
## directly, so this must always ask the actual owner rather than assume
## Entity's own (unarmed) defaults. Same reasoning for reading/writing
## `_owner.attack_hitbox`/`_owner._attacking`/`_owner._attack_cooldown_
## remaining`/etc. directly rather than caching local copies -- those
## fields are this entity's own state, not this delegate's.
##
## Entity.HIT_CHECK_SPHERE_SCALE/MIN_HIT_SPHERE_RADIUS/ANIMATION_BLEND_
## TIME/MELEE_REACH/UNARMED_HIT_OFFSETS deliberately stayed on Entity.gd
## rather than moving here too, even though this is their main consumer --
## Unit.gd's own _update_attack_hitbox_size() reads
## Entity.HIT_CHECK_SPHERE_SCALE/MIN_HIT_SPHERE_RADIUS directly (to keep
## the debug hitbox mesh's visual size in sync with what this class
## actually checks), Unit.gd's own locomotion animation code reads
## Entity.ANIMATION_BLEND_TIME, and MELEE_REACH/UNARMED_HIT_OFFSETS back
## the _get_melee_reach()/_get_melee_hit_offsets() hooks that still live
## on Entity.gd itself (as the base implementation Unit overrides) --
## moving any of these would have meant updating those external
## references too, for no real benefit.

## How long the hitbox stays active (able to land a hit) once a swing
## starts, before switching off again for the rest of the cooldown -- one
## shared value for every weapon (unarmed, sword, ...), so the hit window
## itself doesn't vary by what's equipped, only its damage/reach/timing do.
const ATTACK_ACTIVE_DURATION: float = 0.5
## While dual-wielding, how far apart the two hands' hit-check windows sit
## from the swing's own impact fraction (see ATTACK_IMPACT_FRACTIONS) --
## the right hand's window opens this much EARLIER, the left hand's this
## much LATER, so the two swings feel like a proper one-two rather than
## both weapons connecting on the exact same frame. No-op for a
## single-weapon attack (only applies when the left hitbox is in use --
## see perform_attack).
const DUAL_WIELD_HAND_STAGGER: float = 0.1
## How far into a given attack animation (as a fraction of its length) each
## individual swing reaches full extension -- see Entity.gd's git history
## for the full derivation notes on each entry (measured off each clip via
## right-hand-to-shoulder distance, except Attack_DualWield's, re-measured
## against actual hitbox-to-target contact). Falls back to the "Attack"
## entry for any animation name not listed here.
const ATTACK_IMPACT_FRACTIONS: Dictionary = {
	# The Mixamo-sourced "Attack" clip is a 7.7s multi-punch combo, not a
	# single short swing -- 0.1105 is the first clean full-extension punch
	# (measured by sampling mixamorig_RightHand-to-mixamorig_RightShoulder
	# distance across the clip and finding its first strong local peak),
	# not the animation's midpoint. Using the midpoint (as every other
	# short single-swing clip here does) forced a ~3.85x speed-up to cram
	# it into the attack cooldown, making the punch look frantic; this
	# value instead gently slows the windup-to-first-punch segment to fill
	# the cooldown, and since perform_attack() only schedules one impact
	# per call, the rest of the combo past this point never plays --
	# animation_player.play() restarts the clip from 0 on the next attack.
	"Attack": [0.1105],
	"Attack_Sword": [0.375],
	"Attack_TwoHanded": [0.45],
	"Attack_DualWield": [0.2455, 0.3227, 0.8182],
}
## Approximate chest height above this entity's root, both for where the
## standardized hitbox sphere sits and for target_center below (matching
## conventions elsewhere in Entity.gd, e.g. WeaponSlot-relative offsets
## used to use roughly this same height).
const STANDARD_HITBOX_HEIGHT: float = 0.8

var _owner: Entity

func _init(owner: Entity) -> void:
	_owner = owner

func can_attack() -> bool:
	return _owner.attack_hitbox != null and not _owner._attacking and _owner._attack_cooldown_remaining <= 0.0

## Swings: shows the fist-tracking hitbox visual during the active window
## and lands a hit directly on attack_target if it's actually in reach at
## that moment. Damage is decided by an explicit distance check
## (_land_hit_if_in_reach), not Area3D's overlap signal -- headless testing
## found the signal/get_overlapping_bodies() unreliable for a small,
## fast-moving hitbox repositioned every frame via BoneAttachment3D: it sat
## genuinely within centimeters of the target's capsule for several
## consecutive physics frames without ever being reported as overlapping (a
## physics-server broadclose sync-lag class of issue, not a geometry one).
##
## Impacts are scheduled at FIXED, evenly-spaced times regardless of the
## animation's own native impact fractions: swing i fires at
## impact_fractions[0] * effective_cooldown + i * effective_cooldown, so
## every swing after the first is exactly effective_cooldown apart --
## including the gap from a combo's last swing to the NEXT call's first
## swing, since _attack_cooldown_remaining is set to exactly
## swing_count * effective_cooldown, so the math telescopes cleanly across
## combo boundaries too. The first swing keeps its own natural windup
## proportion (impact_fractions[0]) so it doesn't fire with zero backswing.
##
## To make the swing's actual VISUAL peak land on these fixed times even
## though the clip's own peaks aren't evenly spaced, playback speed is
## varied PER SEGMENT (between consecutive impacts) rather than held
## constant for the whole clip -- each segment's native duration is
## stretched/compressed to fill exactly the fixed duration it's now
## scheduled to take. This also means attack speed changes (effective_
## cooldown getting shorter/longer) are absorbed entirely by these
## per-segment speeds, so the fixed spacing holds no matter what
## effective_cooldown currently is.
func perform_attack() -> void:
	if not can_attack():
		return
	_owner._attacking = true
	var effective_cooldown := _owner._get_attack_cooldown()
	var animation_name := _owner._get_attack_animation_name()
	var left_item_type := _owner._get_left_hand_weapon_item_type()
	var use_left_hitbox: bool = not left_item_type.is_empty() and _owner.attack_hitbox_left != null

	if _owner.animation_player != null and _owner.animation_player.has_animation(animation_name):
		var attack_animation := _owner.animation_player.get_animation(animation_name)
		var impact_fractions: Array = ATTACK_IMPACT_FRACTIONS.get(animation_name, ATTACK_IMPACT_FRACTIONS["Attack"])
		var swing_count: int = impact_fractions.size()
		var native_length: float = attack_animation.length
		_owner._attack_cooldown_remaining = effective_cooldown * swing_count
		_owner.animation_player.play(animation_name, Entity.ANIMATION_BLEND_TIME, 1.0)
		var elapsed_before := 0.0
		var prev_native_time := 0.0
		var prev_target_time := 0.0
		for i in range(swing_count):
			var native_impact_time: float = native_length * impact_fractions[i]
			var segment_native_duration: float = maxf(native_impact_time - prev_native_time, 0.001)
			var target_impact_time: float = impact_fractions[0] * effective_cooldown + i * effective_cooldown
			var segment_target_duration: float = maxf(target_impact_time - prev_target_time, 0.001)
			_owner.animation_player.speed_scale = segment_native_duration / segment_target_duration
			prev_native_time = native_impact_time
			prev_target_time = target_impact_time
			# Stagger the two hands' own windows around the swing's shared
			# impact_time -- see DUAL_WIELD_HAND_STAGGER's doc comment. A
			# no-op (both equal impact_time) when not dual-wielding.
			var right_impact_time: float = target_impact_time - (DUAL_WIELD_HAND_STAGGER if use_left_hitbox else 0.0)
			var left_impact_time: float = target_impact_time + (DUAL_WIELD_HAND_STAGGER if use_left_hitbox else 0.0)
			var window_start: float = minf(right_impact_time, left_impact_time) - ATTACK_ACTIVE_DURATION / 2.0
			var window_end: float = maxf(right_impact_time, left_impact_time) + ATTACK_ACTIVE_DURATION / 2.0
			var impact_delay: float = maxf(window_start - elapsed_before, 0.0)
			if impact_delay > 0.0:
				await _owner.get_tree().create_timer(impact_delay).timeout
			elapsed_before += impact_delay
			if not await _run_hit_check_window(
				true, use_left_hitbox, left_item_type,
				right_impact_time - window_start, left_impact_time - window_start, window_end - window_start
			):
				return
			elapsed_before += window_end - window_start
	else:
		_owner._attack_cooldown_remaining = effective_cooldown
		await _run_hit_check_window(true, use_left_hitbox, left_item_type)
	_owner._attacking = false

## Opens a hit-check window spanning `window_length` seconds: shows the
## debug hitbox visual(s) (if GameState.show_combat_hitboxes is on) while
## each hand's own ATTACK_ACTIVE_DURATION-wide sub-window is active, polls
## every physics frame for a landed hit from attack_hitbox (using the
## active weapon's damage/reach/offsets) and, while dual-wielding,
## attack_hitbox_left too, then hides the visual(s) again. Each hitbox
## stops re-checking once it's landed its own hit for this window,
## independent of the other.
##
## `right_offset`/`left_offset` are each hand's own ATTACK_ACTIVE_DURATION
## sub-window's start time, measured from this window's own start (0.0) --
## see DUAL_WIELD_HAND_STAGGER; the single-weapon call site just leaves
## both at their defaults (0.0 offset, ATTACK_ACTIVE_DURATION length), so
## the two sub-windows are identical to the one shared window this used
## to be.
##
## Returns false if _owner (or its attack_hitbox) became invalid partway
## through -- the caller should stop the whole attack, not just this
## window, in that case.
func _run_hit_check_window(
	check_right: bool, check_left: bool, left_item_type: String,
	right_offset: float = 0.0, left_offset: float = 0.0, window_length: float = ATTACK_ACTIVE_DURATION
) -> bool:
	if not is_instance_valid(_owner) or (check_right and not is_instance_valid(_owner.attack_hitbox)):
		return false
	_owner._prev_hit_points_right.clear()
	_owner._prev_hit_points_left.clear()
	var elapsed := 0.0
	var hit_landed_right := false
	var hit_landed_left := false
	while elapsed < window_length:
		if not is_instance_valid(_owner):
			return false
		var right_active: bool = check_right and elapsed >= right_offset and elapsed <= right_offset + ATTACK_ACTIVE_DURATION
		var left_active: bool = check_left and elapsed >= left_offset and elapsed <= left_offset + ATTACK_ACTIVE_DURATION
		if _owner.attack_hitbox_mesh != null:
			_owner.attack_hitbox_mesh.visible = right_active and GameState.show_combat_hitboxes
		if _owner.attack_hitbox_left_mesh != null:
			_owner.attack_hitbox_left_mesh.visible = left_active and GameState.show_combat_hitboxes
		if right_active and not hit_landed_right:
			hit_landed_right = _land_hit_if_in_reach(
				_owner.attack_hitbox, _owner._get_melee_reach(), _owner._get_melee_hit_offsets(),
				_owner._get_attack_damage(), _owner._prev_hit_points_right
			)
		if left_active and not hit_landed_left:
			hit_landed_left = _land_hit_if_in_reach(
				_owner.attack_hitbox_left, _owner._get_melee_reach(left_item_type),
				_owner._get_melee_hit_offsets(left_item_type), _owner._get_attack_damage(left_item_type),
				_owner._prev_hit_points_left
			)
		await _owner.get_tree().physics_frame
		if not is_instance_valid(_owner):
			return false
		elapsed += _owner.get_physics_process_delta_time()
	if _owner.attack_hitbox_mesh != null and is_instance_valid(_owner.attack_hitbox_mesh):
		_owner.attack_hitbox_mesh.visible = false
	if _owner.attack_hitbox_left_mesh != null and is_instance_valid(_owner.attack_hitbox_left_mesh):
		_owner.attack_hitbox_left_mesh.visible = false
	return true

## STANDARDIZED HITBOX: the hit-check sphere is anchored to _owner's own
## facing (model_root.rotation.y), not to the weapon's literal animated
## bone position -- see Entity.gd's git history for the full derivation
## (several earlier capsule/weapon-tracked attempts were all abandoned for
## the same root cause: swing-direction unpredictability). Sits directly
## in front of the attacker, at a distance and size derived from the
## weapon's own reach.
##
## Guards against tunneling: the sphere center's own travel since the
## previous polled frame is checked as its own swept segment too (a quick
## turn could otherwise swing the sphere past the target between two
## physics frames without either single frame's sphere ever overlapping
## it). Falls back to a plain point check on the very first poll of a
## swing (see perform_attack(), which clears prev_points there).
##
## Returns true once a hit has actually landed, so the polling loop above
## stops re-damaging the same swing. Generalized over which reach/offsets/
## damage/history to check against, rather than always the right-hand
## one, so perform_attack() can run this once for the active weapon and,
## while dual-wielding, a second time for left_hand's -- each hand lands
## (or misses) its own hit independently. `hitbox`, if given, is
## repositioned to the computed point purely so its debug visual (see
## GameState.show_combat_hitboxes) honestly shows where a hit is actually
## decided; passing null skips that (no effect on the check itself).
func _land_hit_if_in_reach(
	hitbox: Area3D, reach: float, offsets: Array, damage: float, prev_points: Array[Vector3]
) -> bool:
	if not is_instance_valid(_owner.attack_target) or not _owner.attack_target.has_method("take_damage"):
		return false
	if offsets.is_empty():
		return false
	var target_center: Vector3 = _owner.attack_target.global_position + Vector3(0, STANDARD_HITBOX_HEIGHT, 0)
	var start: float = offsets[0]
	var end: float = offsets[offsets.size() - 1]
	var sphere_radius: float = maxf((end - start) / 2.0, Entity.MIN_HIT_SPHERE_RADIUS) * Entity.HIT_CHECK_SPHERE_SCALE
	var full_reach: float = reach + _owner.attack_target.get_engage_radius_bonus() + sphere_radius
	# model_root.rotation.y follows atan2(x, z) convention (see
	# Entity._face_angle/_update_attack_target), so forward = (sin, 0, cos).
	var forward := Vector3(sin(_owner.model_root.rotation.y), 0.0, cos(_owner.model_root.rotation.y))
	# Anchored so the sphere's NEAR edge sits right at _owner's own
	# hurtbox surface (get_engage_radius_bonus() returns the attacker's
	# own hurtbox radius here, same value used elsewhere for a defender's
	# footprint).
	var point: Vector3 = (
		_owner.global_position + Vector3(0, STANDARD_HITBOX_HEIGHT, 0)
		+ forward * (_owner.get_engage_radius_bonus() + sphere_radius)
	)
	if hitbox != null:
		hitbox.global_position = point
	var dist: float
	if prev_points.size() == 1:
		dist = _closest_distance_on_segment(prev_points[0], point, target_center)
	else:
		dist = point.distance_to(target_center)
	var landed: bool = dist <= full_reach
	prev_points.clear()
	prev_points.append(point)
	if landed:
		_owner.attack_target.take_damage(damage, _owner)
	return landed

## Shortest distance from `point` to the line segment [a, b] -- the swept
## check _land_hit_if_in_reach uses so a hit point's full travel between
## two frames counts, not just its two endpoint positions.
static func _closest_distance_on_segment(a: Vector3, b: Vector3, point: Vector3) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 0.0001:
		return a.distance_to(point)
	var t: float = clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return (a + ab * t).distance_to(point)
