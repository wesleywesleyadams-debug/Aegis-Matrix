extends CharacterBody3D
class_name Entity
## Shared base for anything with health, a team color, and can be
## selected/attacked -- Unit (mobile) and Building (stationary) both
## extend this. Everything movement-related (nav agent, pathing, chasing)
## lives in Unit only; Entity's own default attack()/_physics_process()
## assume a stationary defender, which is exactly what Building wants
## unmodified and what Unit overrides to add chasing on top of.

const DIRECTION_COUNT: int = 8
const TURN_SPEED: float = 12.0

## Identifies this entity's type for UI purposes -- e.g. the selection
## tray groups same-type units into one icon with a count badge rather
## than one tile per individual unit.
@export var unit_type_id: String = "entity"

@export var max_health: float = 100.0
var current_health: float

## How much damage one swing deals, and the minimum time between swings.
@export var attack_damage: float = 10.0
## Idle time between swings is this minus ATTACK_ACTIVE_DURATION (the hit
## window) -- 2.0 total = 0.15s hit window + 1.85s idle.
@export var attack_cooldown: float = 2.0
## How close (center to center) counts as "in range to swing". Kept tight
## (barely past both entities' combined collision radii, 0.76 for two
## Units at radius 0.38 -- see CollisionShape3D/NavigationAgent3D in
## ParentUnit.tscn) because the melee hitbox now tracks the actual fist
## through the swing (see AttackHitbox in ParentUnit.tscn) instead of
## sitting in a big fixed box in front of the chest -- facing is quantized
## to 8 directions, so at a longer range the up-to-22.5-degree worst-case
## facing error swings the fist wide of a small hitbox entirely. Must stay
## above the combined collision radii or units would physically collide
## before ever reaching attack range.
@export var attack_range: float = 0.85
## How far this entity can see -- used by fog of war (see RTSController's
## _update_fog_of_war) to decide whether enemy entities within range (and
## with a clear has_line_of_sight()) should be revealed. 4 tiles at the
## debug grid's 2.6-unit cell size (see Main.tscn's DebugGrid shader).
@export var vision_range: float = 10.4
## How long the hitbox stays active (able to land a hit) once a swing
## starts, before switching off again for the rest of the cooldown.
const ATTACK_ACTIVE_DURATION: float = 0.15
## How far into the "Attack" animation (as a fraction of its length) the
## fist/weapon reaches full extension -- measured directly off the
## paladin's Attack clip via right-hand-to-shoulder distance sampled frame
## by frame (peaked at t=0.627s of a 1.533s clip). perform_attack() uses
## this to delay turning the hitbox on until the swing has actually landed,
## instead of firing it the instant the animation starts.
const ATTACK_IMPACT_FRACTION: float = 0.409
## How close the hitbox needs to be to a target's approximate body center
## (see _land_hit_if_in_reach) to actually land a hit -- roughly the
## target's own capsule radius (0.38) plus the fist hitbox's own reach.
const MELEE_REACH: float = 0.58

## Collision layer terrain/wall obstacles sit on (see Main.tscn "Wall" nodes)
## -- separate from GROUND_MASK/UNIT_MASK in RTSController.gd, which are
## about click targeting, not sight blocking.
const SIGHT_OBSTACLE_MASK: int = 8
## Ray height for line-of-sight checks -- roughly chest height, so a low
## obstacle (like the ground itself) doesn't spuriously block sight between
## two entities standing on it.
const SIGHT_RAY_HEIGHT: float = 1.0

## Entity currently being attacked/defended against, or null for none.
## Set by attack() and cleared automatically once the target dies or is
## freed, or (for Unit) as soon as it's given an ordinary move order.
var attack_target: Node3D = null

@onready var model_root: Node3D = $ModelRoot
## A ring (Unit) or a square frame (Building) -- shape doesn't matter here,
## only `visible` is ever touched, so this is typed as the common Node3D
## base rather than MeshInstance3D specifically.
@onready var selection_ring: Node3D = $SelectionRing
@onready var unit_sprite: Sprite3D = model_root.get_node_or_null("UnitSprite")
## Present only for entities using a real rigged/skinned model with baked
## animations (e.g. Unit's paladin model) -- null for sprite-billboard
## entities and for Building, which never plays Walk/Idle.
@onready var animation_player: AnimationPlayer = model_root.find_child("AnimationPlayer", true, false)
@onready var health_bar: Node3D = $HealthBar
## Melee hitbox -- for a rigged/skinned entity (see ParentUnit.tscn) this is
## a small fist-sized box nested under WeaponSlot, a BoneAttachment3D on the
## right hand bone, so it tracks the actual fist/weapon through animation
## rather than sitting at a fixed chest-forward offset. Looked up
## recursively since it's no longer necessarily a direct child of
## model_root. Billboard sprite units (no skeleton) would have it directly
## under model_root instead, same as before.
@onready var attack_hitbox: Area3D = model_root.find_child("AttackHitbox", true, false)
## Purely visual -- a translucent box matching the hitbox's own shape,
## shown only while the hitbox is actually active (see perform_attack()) so
## a swing's actual hit window is visible instead of invisible collision
## math. Null for anything without an AttackHitbox to begin with.
@onready var attack_hitbox_mesh: MeshInstance3D = (
	attack_hitbox.get_node_or_null("HitboxMesh") if attack_hitbox != null else null
)
## Waist-level (or base-level, for buildings) ring recolored per
## player_id -- the one visible marker of which player owns this entity.
@onready var belt: MeshInstance3D = model_root.get_node_or_null("Belt")

var _attack_cooldown_remaining: float = 0.0
var _attacking: bool = false

## Debug visualization of the has_line_of_sight() check against attack_target
## -- a thin line from this entity to its target, green when clear and red
## when something on SIGHT_OBSTACLE_MASK is blocking it. Only shown while an
## attack_target is actually within attack_range (i.e. exactly when the LOS
## check is the thing deciding whether a swing lands).
var _sight_line: MeshInstance3D
var _sight_line_mesh: ImmediateMesh
var _sight_line_mat: StandardMaterial3D

## Players 3+ (Nature, Mob) are non-playable factions -- see
## GameState.NATURE_PLAYER_ID/MOB_PLAYER_ID -- with no lobby control ever
## offering them as a Play As choice (only Player 1/Player 2 exist).
const PLAYER_COLORS: Dictionary = {
	1: Color(0.2, 0.45, 0.9), # blue
	2: Color(0.85, 0.2, 0.2), # red
	3: Color(0.45, 0.62, 0.28), # Nature -- neutral green
	4: Color(0.55, 0.4, 0.35), # Mob -- neutral brown
}

const PLAYER_NAMES: Dictionary = {
	1: "Player 1",
	2: "Player 2",
	3: "Nature",
	4: "Mob",
}

## Which player owns this entity. Whichever of Player 1/2 the human chose
## in the lobby (see GameState.human_player_id) can be selected/ordered
## (see RTSController) -- the other exists and is visually distinct (red
## vs. blue belt/health-bar fill) but nothing controls it yet.
@export var player_id: int = 1:
	set(value):
		player_id = value
		_update_belt_color()
		if health_bar:
			health_bar.set_fill_color(PLAYER_COLORS.get(player_id, Color.WHITE))

## Whether this is one of the human player's own entities (per
## GameState.human_player_id, set by the lobby's Play As choice) --
## RTSController uses this everywhere it needs "is this mine to command"
## rather than re-deriving the same comparison at each call site.
func is_player_controlled() -> bool:
	return player_id == GameState.human_player_id

## Pre-rendered 8-directional sprite frames (index 0 = facing angle 0,
## index i = facing angle i * 45 deg), used instead of rotating model_root
## when this entity has a UnitSprite child -- a classic 2.5D
## sprite-billboard look rather than a live rotating 3D model. Left empty
## for ordinary (3D model) entities.
@export var sprite_frames: Array[Texture2D] = []

var selected: bool = false:
	set(value):
		selected = value
		if selection_ring:
			selection_ring.visible = value
		_update_health_bar_visibility()
		_on_selection_changed()

## Hook for subclasses that need to react to selection changes beyond the
## selection ring/health bar handled above -- e.g. Building shows/hides its
## gather-point flag only while selected.
func _on_selection_changed() -> void:
	pass

## Only shows the health bar when it's actually informative -- damaged or
## selected -- rather than always-on. With many units standing close
## together (the default spawn grid, melee range during combat), an
## always-visible bar per unit crowds and visually overlaps neighboring
## units' bars from this camera's angle; hiding it for untouched, unselected
## units removes most of that clutter since full-health idle units are the
## common case.
func _update_health_bar_visibility() -> void:
	if health_bar:
		health_bar.visible = selected or current_health < max_health

func _ready() -> void:
	selection_ring.visible = false
	current_health = max_health
	health_bar.set_health_fraction(1.0)
	_update_health_bar_visibility()
	_update_belt_color()
	health_bar.set_fill_color(PLAYER_COLORS.get(player_id, Color.WHITE))

	_sight_line_mesh = ImmediateMesh.new()
	_sight_line_mat = StandardMaterial3D.new()
	_sight_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sight_line = MeshInstance3D.new()
	_sight_line.mesh = _sight_line_mesh
	_sight_line.material_override = _sight_line_mat
	_sight_line.visible = false
	add_child(_sight_line)

## Recolors this entity's own belt material by team. The belt's material is
## a single Resource shared by every instance of this scene until
## duplicated here -- mutating it directly (without duplicating first)
## would recolor every entity's belt at once instead of just this one.
func _update_belt_color() -> void:
	if belt == null:
		return
	var material := belt.get_surface_override_material(0)
	if material == null:
		return
	material = material.duplicate()
	material.albedo_color = PLAYER_COLORS.get(player_id, Color.WHITE)
	belt.set_surface_override_material(0, material)

## Reduces health by `amount` (clamped at 0) and updates the floating bar.
## No death handling yet -- there's no combat system to call this from
## yet, but the plumbing is here for when there is.
func take_damage(amount: float) -> void:
	current_health = maxf(current_health - amount, 0.0)
	health_bar.set_health_fraction(current_health / max_health)
	_update_health_bar_visibility()

func heal(amount: float) -> void:
	current_health = minf(current_health + amount, max_health)
	health_bar.set_health_fraction(current_health / max_health)
	_update_health_bar_visibility()

func can_attack() -> bool:
	return attack_hitbox != null and not _attacking and _attack_cooldown_remaining <= 0.0

## True when nothing on SIGHT_OBSTACLE_MASK sits between this entity and
## `target` -- used to stop an in-range target from being attacked (or
## acquired) through a wall.
func has_line_of_sight(target: Node3D) -> bool:
	var space_state := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, SIGHT_RAY_HEIGHT, 0)
	var to := target.global_position + Vector3(0, SIGHT_RAY_HEIGHT, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, SIGHT_OBSTACLE_MASK)
	query.exclude = [self, target]
	var result := space_state.intersect_ray(query)
	return result.is_empty()

## Swings: shows the fist-tracking hitbox visual during the active window
## and lands a hit directly on attack_target if it's actually in reach at
## that moment. Damage is decided by an explicit distance check
## (_land_hit_if_in_reach), not Area3D's overlap signal -- headless testing
## found the signal/get_overlapping_bodies() unreliable for a small,
## fast-moving hitbox repositioned every frame via BoneAttachment3D: it sat
## genuinely within centimeters of the target's capsule for several
## consecutive physics frames without ever being reported as overlapping (a
## physics-server broadphase sync-lag class of issue, not a geometry one).
func perform_attack() -> void:
	if not can_attack():
		return
	_attacking = true
	_attack_cooldown_remaining = attack_cooldown
	var impact_delay := 0.0
	if animation_player != null and animation_player.has_animation("Attack"):
		animation_player.play("Attack")
		var attack_animation := animation_player.get_animation("Attack")
		# Center the hit window on the moment the fist/weapon is actually
		# fully extended (measured directly off the paladin's Attack clip:
		# right-hand-to-shoulder distance peaks at ~41% of the way through
		# it), rather than swinging the box on the instant the animation
		# starts -- otherwise the hitbox fires during the windup, well
		# before the fist has reached the target.
		impact_delay = maxf(attack_animation.length * ATTACK_IMPACT_FRACTION - ATTACK_ACTIVE_DURATION / 2.0, 0.0)
	if impact_delay > 0.0:
		await get_tree().create_timer(impact_delay).timeout
	if not is_instance_valid(self) or not is_instance_valid(attack_hitbox):
		return
	if attack_hitbox_mesh != null:
		attack_hitbox_mesh.visible = true
	# Poll every physics frame across the active window rather than
	# checking once -- the impact_delay above is timed off the fist's
	# distance-from-shoulder peak, which doesn't necessarily land on the
	# exact same frame as the fist's closest approach to wherever this
	# particular target actually is standing, so a single check can miss
	# the true closest moment by a frame or two.
	var elapsed := 0.0
	var hit_landed := false
	while elapsed < ATTACK_ACTIVE_DURATION:
		if not is_instance_valid(self):
			return
		if not hit_landed:
			hit_landed = _land_hit_if_in_reach()
		await get_tree().physics_frame
		if not is_instance_valid(self):
			return
		elapsed += get_physics_process_delta_time()
	if attack_hitbox_mesh != null and is_instance_valid(attack_hitbox_mesh):
		attack_hitbox_mesh.visible = false
	_attacking = false

## See perform_attack()'s doc comment for why this is an explicit check
## rather than Area3D overlap detection. target_center approximates the
## defender's capsule/body center the same way WeaponSlot-relative offsets
## do elsewhere in this file -- entity root position plus a waist/chest-
## height offset. Returns true once a hit has actually landed, so the
## polling loop above stops re-damaging the same swing.
func _land_hit_if_in_reach() -> bool:
	if not is_instance_valid(attack_target) or not attack_target.has_method("take_damage"):
		return false
	var target_center: Vector3 = attack_target.global_position + Vector3(0, 0.8, 0)
	if attack_hitbox.global_position.distance_to(target_center) <= MELEE_REACH:
		attack_target.take_damage(attack_damage)
		return true
	return false

## Base version: just marks `target` as what to defend against, since a
## stationary Entity can't chase. Unit overrides this to also move toward
## the target first.
func attack(target: Node3D) -> void:
	attack_target = target

## Default per-frame behavior for a stationary Entity: tick the attack
## cooldown and handle an in-progress attack_target (face it and swing
## once it's in range). Unit overrides this entirely to add movement.
func _physics_process(delta: float) -> void:
	if _attack_cooldown_remaining > 0.0:
		_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - delta, 0.0)
	_update_attack_target(delta)

## Handles an in-progress attack_target: clears it once the target dies or
## is freed, otherwise faces it and swings once close enough. Returns true
## when in range and actively attacking this frame -- Unit uses that to
## suppress its ordinary chase-movement and velocity-driven facing, since
## both would otherwise fight with standing still to swing.
func _update_attack_target(delta: float) -> bool:
	if attack_target == null:
		_sight_line.visible = false
		return false
	if not is_instance_valid(attack_target) or attack_target.current_health <= 0.0:
		attack_target = null
		_sight_line.visible = false
		return false

	var to_target := attack_target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	if dist > attack_range:
		_sight_line.visible = false
		return false

	var in_los := has_line_of_sight(attack_target)
	_draw_sight_line(attack_target, in_los)
	if not in_los:
		return false

	if dist > 0.01:
		_face_direction(to_target.normalized(), delta)
	perform_attack()
	return true

## Redraws the green/red debug sight line toward `target` -- see _sight_line.
func _draw_sight_line(target: Node3D, clear: bool) -> void:
	_sight_line.visible = true
	_sight_line_mat.albedo_color = Color(0.2, 1.0, 0.3) if clear else Color(1.0, 0.2, 0.2)
	_sight_line_mesh.clear_surfaces()
	_sight_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_sight_line_mesh.surface_add_vertex(to_local(global_position + Vector3(0, SIGHT_RAY_HEIGHT, 0)))
	_sight_line_mesh.surface_add_vertex(to_local(target.global_position + Vector3(0, SIGHT_RAY_HEIGHT, 0)))
	_sight_line_mesh.surface_end()

func _face_direction(dir: Vector3, delta: float) -> void:
	var angle := atan2(dir.x, dir.z)
	_turn_toward_snapped(angle, delta)

func _face_snapped_angle(angle: float, delta: float) -> void:
	_turn_toward_snapped(angle, delta)

func _turn_toward_snapped(angle: float, delta: float) -> void:
	var snapped_angle := snap_angle(angle)
	if unit_sprite != null and not sprite_frames.is_empty():
		# Sprite-billboard entity: there's no in-between frame to interpolate
		# toward, so just switch straight to whichever pre-rendered frame
		# matches this facing -- the classic instant-swap look, not a
		# smooth turn. Still record the angle on model_root (a billboard
		# sprite ignores inherited rotation when rendering, so this has no
		# visual effect) purely so anything reading facing off model_root
		# -- e.g. PortraitCamera -- keeps working the same regardless of
		# which kind of entity it's looking at.
		unit_sprite.texture = sprite_frames[_facing_index(snapped_angle)]
		model_root.rotation.y = snapped_angle
	else:
		# Ordinary 3D-model entity: smoothly turn the model toward the
		# nearest of 8 cardinal facings.
		model_root.rotation.y = lerp_angle(model_root.rotation.y, snapped_angle, TURN_SPEED * delta)

## Maps a snapped angle back to a 0..7 sprite-frame index, matching the
## order sprite_frames was rendered in (index i = i * 45 degrees).
func _facing_index(snapped_angle: float) -> int:
	var step := TAU / DIRECTION_COUNT
	var index := int(round(snapped_angle / step)) % DIRECTION_COUNT
	if index < 0:
		index += DIRECTION_COUNT
	return index

## Static (and public, via the subclass name) so RTSController can snap
## the group's travel angle to the same 8 directions before using it to
## orient the formation grid -- otherwise the grid ends up rotated to
## whatever raw angle points at the target, which usually isn't one of the
## 8 angles movement actually snaps to, leaving the formation visibly
## skewed relative to the path the group actually takes.
static func snap_angle(angle: float) -> float:
	var step := TAU / DIRECTION_COUNT
	return round(angle / step) * step
