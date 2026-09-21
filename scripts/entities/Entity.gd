extends CharacterBody3D
class_name Entity
## Shared base for anything with health, a team color, and can be
## selected/attacked -- Unit (mobile) and Building (stationary) both
## extend this. Everything movement-related (nav agent, pathing, chasing)
## lives in Unit only; Entity's own default attack()/_physics_process()
## assume a stationary defender, which is exactly what Building wants
## unmodified and what Unit overrides to add chasing on top of.

const TURN_SPEED: float = 12.0
## How close model_root's current facing needs to be to the target's
## actual direction, in radians, before _update_attack_target lets a swing
## fire -- see its own doc comment for why this exists (facing turns
## gradually, not instantly, so without this gate a swing could fire while
## still facing wherever the unit happened to be facing before the target
## came into range).
const FACING_TOLERANCE: float = deg_to_rad(8.0)

## Identifies this entity's type for UI purposes -- e.g. the selection
## tray groups same-type units into one icon with a count badge rather
## than one tile per individual unit.
@export var unit_type_id: String = "entity"

@export var max_health: float = 100.0
var current_health: float

## A node's own name isn't reliably its display name -- Godot silently
## appends a number to keep sibling names unique (e.g. Main.tscn's two
## Dwellings, the second actually named "Dwelling2"), which would
## otherwise show up as if it were a different, numbered thing. Strips
## a trailing run of digits -- Godot's own uniquification pattern -- off
## any Entity's name for display, shared by PortraitPanel (the selected/
## inspected subject) and RTSController's hover tooltip alike, rather
## than each re-deriving it.
static var _trailing_digits := RegEx.create_from_string("\\d+$")

static func display_name_for(entity: Node) -> String:
	var stripped := _trailing_digits.sub(entity.name, "")
	return stripped if not stripped.is_empty() else entity.name

## Override to customize how this Entity's name reads in the hover
## tooltip (see RTSController._update_map_item_hover) -- e.g. World.gd
## prepends a tree's species ("Pine Tree"). Defaults to the plain
## display name.
func get_tooltip_title() -> String:
	return Entity.display_name_for(self)

## Override to add extra stat rows to the hover tooltip, beyond the
## Health row ItemTooltipPanel.show_entity always adds -- e.g. World.gd's
## Wood yield for a tree. Empty (no extra rows) by default.
func get_tooltip_extra_stats() -> Dictionary:
	return {}

## How much damage one unarmed swing deals (see Unit._get_attack_damage,
## which swaps this out for the equipped weapon's own damage whenever
## backpack.right_hand actually holds one), and the minimum time between
## swings.
@export var attack_damage: float = 5.0
## Idle time between swings is this minus ATTACK_ACTIVE_DURATION (the hit
## window) -- 2.0 total = 0.3s hit window + 1.7s idle.
@export var attack_cooldown: float = 2.0

## Overridable hook for this entity's actual effective cooldown -- plain
## attack_cooldown unmodified by default. Unit overrides this to apply a
## two-handed hybrid weapon's attack-speed bonus (see
## Unit.TWO_HANDED_HYBRID_ATTACK_SPEED_MULTIPLIER).
func _get_attack_cooldown() -> float:
	return attack_cooldown
## How close (center to center) counts as "in range to swing". Kept above
## both entities' combined collision radii (0.57 for two Units at radius
## 0.285 -- see CollisionShape3D/NavigationAgent3D in ParentUnit.tscn) or
## units would physically collide before ever reaching attack range, and
## given some extra clearance beyond that (rather than the bare minimum)
## so the models' visible armor doesn't read as overlapping while
## fighting. Not unlimited headroom though: the melee hitbox tracks the
## actual fist through the swing (see AttackHitbox in ParentUnit.tscn)
## instead of sitting in a big fixed box in front of the chest, so too long
## a range lets the target drift out from in front of a small hitbox
## entirely (see MELEE_REACH below). This is the ATTACKER's own base
## reach, independent of the TARGET's size -- see get_engage_radius_bonus()
## for that half of the total engagement distance.
@export var attack_range: float = 1.0
## Extra distance added to the ATTACKER's attack_range and MELEE_REACH
## when deciding whether it's close enough to swing at (and land a hit
## on) THIS entity as a target -- how big a footprint THIS entity presents
## for combat purposes, kept as its own explicit, separate value rather
## than derived from (or shared with) whatever collision shape it uses for
## movement/blocking -- shrinking a unit's movement collision to reduce
## clumping/jitter shouldn't also shrink how far away it can be hit, and
## vice versa.
##
## Default implementation reads a "Hurtbox" child's own CollisionShape3D
## radius if the entity has one (see ParentUnit.tscn) -- a real, separate
## shape purely for this (not used for movement/blocking at all, hence not
## monitoring/monitorable), whose radius becomes this bonus directly. Kept
## modest for Unit (see ParentUnit.tscn's Hurtbox) -- enough that combat
## reaches a little further than movement collision alone would put a
## unit in range for, not a full redo of engagement distance. Falls back
## to 0.0 for an entity with no Hurtbox (e.g. World.gd's Tree). Building
## overrides this outright with its own much larger box footprint, since a
## Unit's collision capsule physically can't get anywhere near
## attack_range=1.0 of a Building's *center* -- it collides with the box's
## face first, at combined-radius distance box_half_extent + unit_radius
## (roughly 1.3 + 0.285 = 1.585), already past attack_range on its own.
func get_engage_radius_bonus() -> float:
	if _hurtbox_shape != null and _hurtbox_shape.shape != null:
		return _hurtbox_shape.shape.radius
	return 0.0
## How far this entity can see -- used by fog of war (see RTSController's
## _update_fog_of_war) to decide whether enemy entities within range (and
## with a clear has_line_of_sight()) should be revealed. 4 tiles at the
## debug grid's 2.6-unit cell size (see Main.tscn's DebugGrid shader).
@export var vision_range: float = 10.4
## Crossfade duration used for every animation_player.play() call on this
## entity (swinging into an attack, and Unit's own Idle/Walk switches) --
## AnimationPlayer.play()'s default custom_blend (-1) falls back to 0,
## which pops instantly between whatever pose each clip happened to end/
## start on (most visible going from a swing's extended end pose straight
## to Idle's neutral one, or back into the next swing's start pose).
## Blending over this much time smooths that regardless of how different
## the two poses are, without needing the clips themselves to share a
## pose at the cut point.
const ANIMATION_BLEND_TIME: float = 0.25
## How close the hitbox needs to be to a target's approximate body center
## (see _land_hit_if_in_reach) to actually land a hit -- roughly the
## target's own capsule radius (0.285) plus the fist hitbox's own reach,
## with a bit of extra margin to cover attack_range's slightly longer
## engagement distance.
const MELEE_REACH: float = 0.65

## Whether this entity automatically engages any hostile unit that wanders
## within vision_range and a clear has_line_of_sight(), without waiting
## for an explicit player attack order (see _try_acquire_aggressive_target,
## called from _update_attack_target whenever attack_target is empty).
## The seed of a proper stance system (aggressive/defensive/hold-fire) if
## one gets built later -- for now just an always-on default.
@export var aggressive_stance: bool = true
## True only while this entity has no outstanding player-issued task --
## aggressive stance (see _update_attack_target) only auto-acquires a new
## target while this is true, so an explicit player order (moving
## somewhere, fetching an item) always takes priority over automatically
## picking a fight. Building has no such tasks to interrupt (its gather
## point is a standing background order, not something aggressive stance
## would compete with), so this default (always idle) is fine unmodified;
## Unit overrides it with a real check against its own order state.
func is_idle() -> bool:
	return true
## True while this entity is executing an attack-move order -- see
## Unit.attack_move_to(). Lets aggressive stance auto-acquire a target
## while still traveling (not just once idle at the destination, which
## is_idle() alone gates), so a unit ordered to attack-move actually
## engages anything hostile it passes along the way. Building/the default
## Entity have no such order, hence always false.
func is_attack_moving() -> bool:
	return false
## How often (seconds) an idle entity re-scans for an aggressive-stance
## target -- doesn't need to happen every physics frame, and this keeps
## the O(n) nearby-unit scan from running more than necessary as unit
## counts grow.
const AGGRESSIVE_SCAN_INTERVAL: float = 0.5
var _aggressive_scan_cooldown: float = 0.0
## How long the 'h' hotkey (see RTSController._halt_selected_units /
## Unit.stop()) keeps a halted unit standing genuinely idle before
## aggressive stance can pick up a new target again -- otherwise a unit
## halted mid-fight (or one that immediately re-spots the same nearby
## enemy) would just resume attacking the very next scan, making "stop"
## not actually stop anything.
const HALT_AGGRESSIVE_SUPPRESS_DURATION: float = 1.0
var _aggressive_stance_suppress_timer: float = 0.0

## Blocks aggressive stance from acquiring a new target for `duration`
## seconds, regardless of aggressive_stance/AGGRESSIVE_SCAN_INTERVAL.
func suppress_aggressive_stance(duration: float) -> void:
	_aggressive_stance_suppress_timer = duration

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
## True while attack_target was set by an explicit player order (see
## Unit.order_attack()) rather than auto-acquired by aggressive stance or
## an attack-move's scan -- see _update_attack_target's re-evaluation,
## which only switches to a closer hostile for the latter. A player's
## explicit attack order sticks to that exact target no matter what
## wanders closer in the meantime; auto-engagement always prioritizes
## whoever's actually nearest instead of tunnel-visioning on the first
## thing it happened to spot.
var _attack_target_is_ordered: bool = false

@onready var model_root: Node3D = $ModelRoot
## See get_engage_radius_bonus() -- null for an entity with no "Hurtbox"
## child (e.g. Building, which overrides get_engage_radius_bonus() outright
## instead, and World.gd's Tree, which has neither).
@onready var _hurtbox_shape: CollisionShape3D = get_node_or_null("Hurtbox/CollisionShape3D")
## A ring (Unit) or a square frame (Building) -- shape doesn't matter here.
## Normally only `visible` is touched (hence typed as the common Node3D
## base rather than MeshInstance3D specifically); blink_attack_target()
## below also recolors it, since that needs to work across both shapes.
@onready var selection_ring: Node3D = $SelectionRing
## The ring's normal (non-blinking) color -- matches Mat_ring/the
## Building selection frame's material in both ParentUnit.tscn and
## ParentBuilding.tscn. Restored after blink_attack_target() finishes.
const SELECTION_RING_COLOR: Color = Color(0.3, 1, 0.4, 1)
## Flash color for blink_attack_target() -- distinct red, unmistakable
## against the ring's normal green.
const ATTACK_TARGET_BLINK_COLOR: Color = Color(1, 0.15, 0.15, 1)
## Amber, matching Building.CONSTRUCTION_BLINK_COLOR's own "you just
## tasked something onto me" language -- used for a World resource node
## (Oak Tree, Crystal Cave, ...) when peasants are right-clicked onto it
## to gather (see RTSController._handle_right_click), the same one-shot
## feedback moment blink_attack_target already gives an attack order.
const GATHER_TARGET_BLINK_COLOR: Color = Color(1.0, 0.75, 0.15, 1.0)
## How long each on/off phase of blink_attack_target() lasts -- same
## rhythm WorldItem.blink_selection() uses for "you just right-clicked
## this item".
const ATTACK_BLINK_INTERVAL: float = 0.12
## Present only for entities using a real rigged/skinned model with baked
## animations (e.g. Unit's paladin model) -- null for sprite-billboard
## entities and for Building, which never plays Walk/Idle.
@onready var animation_player: AnimationPlayer = model_root.find_child("AnimationPlayer", true, false)
## Same "present only for a rigged/skinned model" caveat as animation_player
## above -- null for sprite-billboard entities and Building. See Unit's
## _apply_grip_pose(), which overrides individual finger bones on this
## every frame to curl around whatever's equipped, independent of
## whatever animation clip is currently playing.
@onready var skeleton: Skeleton3D = model_root.find_child("Skeleton3D", true, false)
@onready var health_bar: Node3D = $HealthBar
## Melee hitbox -- for a rigged/skinned entity (see ParentUnit.tscn) this is
## a small fist-sized box nested under WeaponSlot, a BoneAttachment3D on the
## right hand bone, so it tracks the actual fist/weapon through animation
## rather than sitting at a fixed chest-forward offset. Looked up
## recursively since it's no longer necessarily a direct child of
## model_root. Billboard sprite units (no skeleton) would have it directly
## under model_root instead, same as before.
@onready var attack_hitbox: Area3D = model_root.find_child("AttackHitbox", true, false)
## Purely visual -- a translucent yellow sphere roughly matching the
## hitbox's own reach, shown only while the hitbox is actually active (see
## perform_attack()) AND GameState.show_combat_hitboxes is on, so a
## swing's actual hit window is visible instead of invisible collision
## math. Null for anything without an AttackHitbox to begin with.
@onready var attack_hitbox_mesh: MeshInstance3D = (
	attack_hitbox.get_node_or_null("HitboxMesh") if attack_hitbox != null else null
)
## Same idea as attack_hitbox, but for a weapon actually held in left_hand
## (see ParentUnit.tscn's AttackHitboxLeft, nested under WeaponSlotLeft) --
## only relevant while dual-wielding (see Unit._get_attack_animation_name's
## "dual_wield" grip), since left_hand's weapon is otherwise visual-only.
## Null for anything without one (e.g. Building, or an older model built
## before this existed).
@onready var attack_hitbox_left: Area3D = model_root.find_child("AttackHitboxLeft", true, false)
@onready var attack_hitbox_left_mesh: MeshInstance3D = (
	attack_hitbox_left.get_node_or_null("HitboxMesh") if attack_hitbox_left != null else null
)
## Purely visual -- a translucent yellow sphere matching the Hurtbox's own
## radius (see get_engage_radius_bonus), shown persistently (not just
## during a swing) whenever GameState.show_combat_hitboxes is on. Null for
## anything without a Hurtbox to begin with (e.g. World.gd's Tree).
@onready var hurtbox_mesh: MeshInstance3D = get_node_or_null("Hurtbox/HurtboxMesh")
## The paladin model's tabard/skirt fabric, recolored per player_id. This
## mesh is split into two material surfaces (surface 0 = the rest of the armor, surface
## 1 = just the tabard fabric, given a flat white base material with no
## texture so a team color multiplies onto it cleanly instead of muddying
## against the fabric's original navy/orange paint -- see
## assets/models/paladin/paladin.glb and the Blender script that split it).
## Node is confusingly named "Paladin_J_Nordstrom_Helmet" -- the source
## Mixamo export's two mesh objects came out with their names swapped from
## what they actually contain; this one is the main body, not the helmet.
## Null for entities with no such mesh (e.g. Building, or the old
## sprite-billboard peasant).
@onready var tabard: MeshInstance3D = model_root.find_child("Paladin_J_Nordstrom_Helmet", true, false)

var _attack_cooldown_remaining: float = 0.0
var _attacking: bool = false
## The actual swing-timing/hit-detection logic lives in CombatBehavior.gd
## now -- see its own doc comment for why it's a plain delegate object
## rather than folded into this class or a full ECS component. Built in
## _ready() (needs `self` to exist first).
var _combat: CombatBehavior
## The world positions _get_melee_hit_offsets() resolved to on the
## previous polled frame, for the right-hand/two-hand hitbox (attack_hitbox)
## -- see _land_hit_if_in_reach(), which checks the
## segment from each of these to its current-frame counterpart (not just
## the current point alone) so a fast swing can't tunnel a hit point past
## the target between two physics frames without either ever landing
## exactly on it. Empty at the start of each swing (see perform_attack()),
## so the first poll falls back to a plain point check.
var _prev_hit_points_right: Array[Vector3] = []
## Same as _prev_hit_points_right, but for the left-hand hitbox
## (attack_hitbox_left) while dual-wielding.
var _prev_hit_points_left: Array[Vector3] = []

## Debug visualization of the has_line_of_sight() check against attack_target
## -- a thin line from this entity to its target, green when clear and red
## when something on SIGHT_OBSTACLE_MASK is blocking it. Only shown while an
## attack_target is actually within attack_range (i.e. exactly when the LOS
## check is the thing deciding whether a swing lands).
var _sight_line: MeshInstance3D
var _sight_line_mesh: ImmediateMesh
var _sight_line_mat: StandardMaterial3D

## Player 4/9 (Mob, Gaia) are non-playable factions -- see
## GameState.MOB_PLAYER_ID/NATURE_PLAYER_ID -- with no lobby control ever
## offering them as a Play As choice (only Player 1/Player 2 exist).
const PLAYER_COLORS: Dictionary = {
	1: Color(0.2, 0.45, 0.9), # blue
	2: Color(0.85, 0.2, 0.2), # red
	4: Color(0.55, 0.4, 0.35), # Mob -- neutral brown
	9: Color(1, 1, 1), # Gaia -- white
}

const PLAYER_NAMES: Dictionary = {
	1: "Player 1",
	2: "Player 2",
	4: "Mob",
	9: "Gaia",
}

## Which player owns this entity. Whichever of Player 1/2 the human chose
## in the lobby (see GameState.human_player_id) can be selected/ordered
## (see RTSController) -- the other exists and is visually distinct (red
## vs. blue tabard/health-bar fill) but nothing controls it yet.
@export var player_id: int = 1:
	set(value):
		player_id = value
		_update_tabard_color()
		if health_bar:
			health_bar.set_fill_color(PLAYER_COLORS.get(player_id, Color.WHITE))

## Whether this is one of the human player's own entities (per
## GameState.human_player_id, set by the lobby's Play As choice) --
## RTSController uses this everywhere it needs "is this mine to command"
## rather than re-deriving the same comparison at each call site.
func is_player_controlled() -> bool:
	return player_id == GameState.human_player_id

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

## Applies GameState.show_combat_hitboxes live to a unit already on the
## field, not just ones that read it fresh in their own _ready() -- the
## hurtbox ring is persistent so it can just be toggled directly; the
## attack hitbox ring only ever shows during an active swing already
## (see perform_attack()), so there's nothing to toggle mid-swing here,
## just whether the *next* swing is allowed to show it.
func _on_combat_hitboxes_visibility_changed(visible_now: bool) -> void:
	if hurtbox_mesh != null:
		hurtbox_mesh.visible = visible_now

## Pulls this Entity's stats from UnitDefs and BuildingDefs, keyed by
## unit_type_id -- see either file's own doc comment for why every entry
## currently reproduces whatever this Entity's @export default/.tscn
## override already was, so this causes zero behavior change on its own;
## it exists so a future stat change/new type only touches one
## dictionary entry, not several constants spread across
## Entity.gd/Unit.gd/Building.gd/individual .tscn files. Run first thing
## in _ready(), before current_health is copied from max_health, so a
## def-file HP entry affects starting health too. A type with no
## matching entry (or a stat key that entry doesn't define) leaves this
## Entity's existing value untouched (see each Defs file's -1.0 "no
## override" sentinel).
##
## Deliberately doesn't branch on `self is Unit`/`self is Building` --
## Entity.gd is Unit/Building's own base class, and referencing either
## derived class_name from here creates a circular script-parse
## dependency (Unit/Building extends Entity, which would need to resolve
## Unit/Building's type first). Since unit_type_id strings never collide
## between the two Defs files' key sets ("peasant" vs. "hut"/"castle"/
## "wall"/"tower"/"building"), just trying both lookups and applying
## whichever actually has a matching entry sidesteps that entirely.
## MAX_SPEED is only ever a Unit property (Building has no such field),
## set dynamically via set() rather than a static Unit-typed
## reference/cast for the same reason -- Object.set() on a nonexistent
## property is a silent no-op, so this is still safe for a Building.
func _apply_type_defs() -> void:
	var defs_max_health := UnitDefs.get_max_health(unit_type_id)
	var defs_attack_damage := UnitDefs.get_attack_damage(unit_type_id)
	var defs_attack_cooldown := UnitDefs.get_attack_cooldown(unit_type_id)
	var defs_attack_range := UnitDefs.get_attack_range(unit_type_id)
	var defs_vision_range := UnitDefs.get_vision_range(unit_type_id)
	var defs_max_speed := UnitDefs.get_max_speed(unit_type_id)
	if defs_max_health >= 0.0:
		max_health = defs_max_health
	if defs_attack_damage >= 0.0:
		attack_damage = defs_attack_damage
	if defs_attack_cooldown >= 0.0:
		attack_cooldown = defs_attack_cooldown
	if defs_attack_range >= 0.0:
		attack_range = defs_attack_range
	if defs_vision_range >= 0.0:
		vision_range = defs_vision_range
	if defs_max_speed >= 0.0:
		set("MAX_SPEED", defs_max_speed)

	var defs_building_max_health := BuildingDefs.get_max_health(unit_type_id)
	if defs_building_max_health >= 0.0:
		max_health = defs_building_max_health

func _ready() -> void:
	_combat = CombatBehavior.new(self)
	_apply_type_defs()
	selection_ring.visible = false
	current_health = max_health
	health_bar.set_health_fraction(1.0)
	_update_health_bar_visibility()
	_update_tabard_color()
	health_bar.set_fill_color(PLAYER_COLORS.get(player_id, Color.WHITE))

	if hurtbox_mesh != null:
		hurtbox_mesh.visible = GameState.show_combat_hitboxes
	GameState.combat_hitboxes_visibility_changed.connect(_on_combat_hitboxes_visibility_changed)

	_sight_line_mesh = ImmediateMesh.new()
	_sight_line_mat = StandardMaterial3D.new()
	_sight_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sight_line = MeshInstance3D.new()
	_sight_line.mesh = _sight_line_mesh
	_sight_line.material_override = _sight_line_mat
	_sight_line.visible = false
	add_child(_sight_line)

## Recolors the tabard fabric (surface 1 of `tabard`, see its doc comment)
## by team. Its base material comes from the imported mesh resource itself
## (get_active_material), not an existing surface_material_override, since
## nothing overrides it by default -- duplicating it here (rather than
## mutating it directly) is what creates that first override, so this
## recolors only this one entity's instance rather than every entity
## sharing the same underlying mesh resource.
func _update_tabard_color() -> void:
	if tabard == null:
		return
	var material := tabard.get_active_material(1)
	if material == null:
		return
	material = material.duplicate()
	material.albedo_color = PLAYER_COLORS.get(player_id, Color.WHITE)
	tabard.set_surface_override_material(1, material)

## Flashes this entity's own selection ring red twice -- the feedback for
## "a unit just targeted you for melee" (see
## RTSController._issue_attack_order), reusing WorldItem.blink_selection()'s
## on/off rhythm for "you just right-clicked this". Forces the ring
## visible+red for the blink regardless of whether this entity is actually
## selected, then restores it to whatever `selected` actually is (and its
## normal green) once done, so blinking an unselected enemy's ring doesn't
## leave it stuck visible, and blinking a selected one doesn't leave it red.
## `color` defaults to the attack-target red but is overridable -- see
## Building.blink_construction_target(), the other "you just tasked a unit
## onto me" moment that reuses this same on/off rhythm with its own color.
func blink_attack_target(times: int = 2, color: Color = ATTACK_TARGET_BLINK_COLOR) -> void:
	if selection_ring == null:
		return
	_recolor_selection_ring(color)
	for i in times:
		selection_ring.visible = true
		await get_tree().create_timer(ATTACK_BLINK_INTERVAL).timeout
		if not is_instance_valid(self):
			return
		selection_ring.visible = false
		await get_tree().create_timer(ATTACK_BLINK_INTERVAL).timeout
		if not is_instance_valid(self):
			return
	selection_ring.visible = selected
	_recolor_selection_ring(SELECTION_RING_COLOR)

## Recolors every mesh surface under selection_ring -- a single
## MeshInstance3D torus for Unit, or a Node3D holding four bar
## MeshInstance3D children for Building (see ParentUnit.tscn/
## ParentBuilding.tscn) -- so blink_attack_target() works the same way
## regardless of which shape this entity actually has.
func _recolor_selection_ring(color: Color) -> void:
	_recolor_mesh_recursive(selection_ring, color)

func _recolor_mesh_recursive(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var material: Material = node.get_surface_override_material(0)
		if material == null:
			material = node.mesh.surface_get_material(0)
		if material != null:
			material = material.duplicate()
			if material is StandardMaterial3D:
				material.albedo_color = color
				if material.emission_enabled:
					material.emission = color
			node.set_surface_override_material(0, material)
	for child in node.get_children():
		_recolor_mesh_recursive(child, color)

## Reduces health by `amount` (clamped at 0) and updates the floating bar.
## Triggers _die(attacker) once health actually reaches 0 -- no-ops
## instead of re-triggering it if already dying (an in-flight swing that
## lands the same frame death starts, or a couple of frames later while
## the death animation is still playing, shouldn't restart the death
## sequence). `attacker` (added for Path of Betrayal/Death -- see
## PathPerks.apply_kill_refund/apply_death_drop, both keyed off the
## KILLER's own player_id) is optional and only ever passed by
## CombatBehavior's own melee-hit call site; nothing else deals damage
## in this project yet. Path of Purity's "immune to the first hit of
## every fight" (see _try_consume_purity_shield -- Entity's own version
## always refuses, Unit overrides it) is checked before any of that,
## since a blocked hit deals no damage and can't kill anything.
func take_damage(amount: float, attacker: Entity = null) -> void:
	if _dying:
		return
	if _try_consume_purity_shield():
		return
	current_health = maxf(current_health - amount, 0.0)
	health_bar.set_health_fraction(current_health / max_health)
	_update_health_bar_visibility()
	if current_health <= 0.0:
		_die(attacker)

## Always refuses (no shield to consume) -- see Unit's own override for
## the actual Path of Purity mechanic. A World object or Building has no
## "fight" concept to speak of, so this is a no-op for them by design,
## not an oversight.
func _try_consume_purity_shield() -> bool:
	return false

func heal(amount: float) -> void:
	current_health = minf(current_health + amount, max_health)
	health_bar.set_health_fraction(current_health / max_health)
	_update_health_bar_visibility()

## Set the moment health reaches 0 (see take_damage) -- an entity stays
## "alive" as far as Node validity goes throughout its death animation
## (queue_free() only happens at the very end), but every other system
## needs to immediately stop treating it as a living participant: no
## longer targetable by aggressive stance or attack orders, no longer
## blocking movement/pathing, no longer shown as selected. is_dying() lets
## other code (Unit's own movement/combat loop, chiefly) check this
## without needing its own separate signal wiring.
var _dying: bool = false

func is_dying() -> bool:
	return _dying

## How long a non-animated entity (a Building, or any Unit whose model
## happens to have no "Death" animation) sinks into the ground before
## being removed, when there's no real death animation to time against
## instead.
const DEATH_FALLBACK_DURATION: float = 1.2
const DEATH_SINK_DEPTH: float = 1.0

## Plays "Death" (if this entity's model has one -- see the paladin's
## baked-in animations) or a simple sink-into-the-ground fallback
## otherwise, then removes the entity. Combat/selection participation
## (targetable, collidable, selected) is turned off immediately here, not
## after the animation finishes, so a unit mid-death doesn't keep
## absorbing hits, blocking a chasing enemy's path, or showing up as a
## valid aggressive-stance target for the rest of the fight.
##
## Deliberately NOT removed from the units/buildings group here, though --
## RTSController._update_fog_of_war treats current group membership as
## "this entity can see," and a dying unit is still very visibly standing
## there for the next several seconds playing its death animation. Pulling
## it out of the group immediately meant an enemy it was the only one
## keeping visible would flicker out of sight (fog-of-war correctly, if
## confusingly, hiding it) while the dying unit's own animation was still
## playing on screen -- the "living unit disappeared" surprise this fixes.
## queue_free() at the very end naturally drops it from every group at the
## moment it's actually gone, which is the right time for vision to go
## with it.
func _die(attacker: Entity = null) -> void:
	if _dying:
		return
	_dying = true
	attack_target = null
	collision_layer = 0
	collision_mask = 0
	selection_ring.visible = false
	health_bar.visible = false
	selected = false
	if attacker != null and is_instance_valid(attacker):
		var resource_hud: ResourceHUD = get_tree().current_scene.get_node_or_null("UI/ResourceHUD")
		PathPerks.apply_kill_refund(attacker.player_id, resource_hud)
		PathPerks.apply_death_drop(attacker.player_id, resource_hud)
	if animation_player != null and animation_player.has_animation("Death"):
		animation_player.play("Death")
		await animation_player.animation_finished
	else:
		var tween := create_tween()
		tween.tween_property(model_root, "position:y", model_root.position.y - DEATH_SINK_DEPTH, DEATH_FALLBACK_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await tween.finished
	if is_instance_valid(self):
		queue_free()

## Thin forwarder -- see CombatBehavior.gd, where the actual combat
## logic (perform_attack/can_attack/hit-detection) now lives. Built in
## _ready() (see _combat).
func can_attack() -> bool:
	return _combat.can_attack()

## Which AnimationPlayer clip perform_attack() should play for this swing --
## "Attack" (bare-handed) by default. Unit overrides this to swing whatever
## weapon-specific animation matches its currently-equipped right_hand item
## (e.g. "Attack_Sword"), falling back to "Attack" for an unarmed unit or
## one holding something with no dedicated swing animation yet. Building
## has no weapon to equip, so the default is fine unmodified.
func _get_attack_animation_name() -> String:
	return "Attack"

## How much damage this swing actually deals -- attack_damage (the unarmed
## amount) by default. Unit overrides this to use a weapon's own damage
## (see ItemDefs.get_damage) whenever one's equipped. item_type lets a
## caller ask about a SPECIFIC hand's weapon (e.g. left_hand's, while
## dual-wielding -- see perform_attack()) rather than always the "active"
## one (right_hand/two_hand); "" (the default) means "the active weapon",
## same as before this parameter existed.
func _get_attack_damage(item_type: String = "") -> float:
	return attack_damage

## How close this entity's hitbox needs to reach a target to land a hit --
## MELEE_REACH (the unarmed fist's reach), not currently overridden by
## Unit. A weapon's added reach is instead baked directly into where the
## hitbox itself sits (see Unit._update_attack_hitbox_position), not into
## this value. See _get_attack_damage's doc comment for what item_type
## does (accepted here too for a uniform signature across all three
## per-swing lookups, even though this one ignores it today).
func _get_melee_reach(item_type: String = "") -> float:
	return MELEE_REACH

## The [start, end] capsule endpoints (along a hitbox's parent's own +Y,
## the same axis every weapon's visual scene is authored along -- see
## ItemDefs.get_melee_hit_offsets) _land_hit_if_in_reach checks a hit
## against each frame. Mirrors "dagger"'s own hit_offsets (see
## ItemDefs.DEFS) rather than being a separate, smaller span of its own --
## a bare fist's hit-check sphere is now the same size as the smallest
## real weapon's, not its own even-smaller thing. Unit overrides this to
## span an equipped weapon's own length instead, from crossguard to tip --
## same idea, just a longer capsule for a longer weapon. See
## _get_attack_damage's doc comment for what item_type does.
const UNARMED_HIT_OFFSETS: Array = [0.0, 0.15]

func _get_melee_hit_offsets(item_type: String = "") -> Array:
	return UNARMED_HIT_OFFSETS

## The item_type actually held in left_hand right now, or "" if left_hand
## is empty/this entity has no such concept (Building, an unarmed unit,
## one wielding a two-handed/hybrid-two-handed weapon whose left_hand slot
## sits empty by design -- see BACKPACK_SLOTS' doc comment). "" by
## default; Unit overrides this to read backpack["left_hand"] directly.
## perform_attack() uses this (together with attack_hitbox_left) to decide
## whether a swing should also check a left-hand hit, dual-wielding only.
func _get_left_hand_weapon_item_type() -> String:
	return ""

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

## Thin forwarder -- see CombatBehavior.gd (_combat, built in _ready()),
## where the actual swing-timing/hit-detection logic now lives.
func perform_attack() -> void:
	_combat.perform_attack()

## Multiplier on the hit-check sphere's radius -- a mutable static (not
## const) specifically so a test harness can dial it up and re-test
## within one running process instead of editing this file and
## recompiling for every trial. 1.0 is the sphere's "just encloses the
## weapon's reach" baseline size; leave at 1.0 for normal play. Read by
## CombatBehavior.gd (the actual hit-check) and Unit._update_attack_
## hitbox_size (the debug visual, kept in sync with it) -- stayed on
## Entity.gd rather than moving to CombatBehavior.gd since Unit.gd
## already references it class-qualified as Entity.HIT_CHECK_SPHERE_SCALE.
static var HIT_CHECK_SPHERE_SCALE: float = 4.0
## The smallest a hit-check sphere's un-scaled radius (half of
## offsets[end] - offsets[start], before HIT_CHECK_SPHERE_SCALE) is ever
## allowed to be -- matches "dagger"'s own (see ItemDefs.DEFS: hit_offsets
## [0.0, 0.15], so (0.15 - 0.0) / 2.0), the shortest real weapon. Nothing
## (including bare fists, see UNARMED_HIT_OFFSETS) gets a smaller
## hit-check sphere than the dagger's. See HIT_CHECK_SPHERE_SCALE's doc
## comment for why this also stayed on Entity.gd.
const MIN_HIT_SPHERE_RADIUS: float = 0.075

## Base version: just marks `target` as what to defend against, since a
## stationary Entity can't chase. Unit overrides this to also move toward
## the target first. Switching to an actually different target resets
## _attack_target_is_ordered to false (auto-acquired by default -- see
## Unit.order_attack() for how a player order marks itself sticky
## afterward); re-attacking the SAME target (e.g. Unit's stuck-rechase
## retry, just recomputing an approach point) leaves it untouched, so that
## doesn't quietly downgrade a player's still-current explicit order.
func attack(target: Node3D) -> void:
	if target != attack_target:
		_attack_target_is_ordered = false
	attack_target = target

## Default per-frame behavior for a stationary Entity: tick the attack
## cooldown and handle an in-progress attack_target (face it and swing
## once it's in range). Unit overrides this entirely to add movement.
func _physics_process(delta: float) -> void:
	if _dying:
		return
	if _attack_cooldown_remaining > 0.0:
		_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - delta, 0.0)
	_update_attack_target(delta)

## Handles an in-progress attack_target: clears it once the target dies or
## is freed, otherwise faces it and swings once close enough. Returns true
## when in range and actively attacking this frame -- Unit uses that to
## suppress its ordinary chase-movement and velocity-driven facing, since
## both would otherwise fight with standing still to swing.
func _update_attack_target(delta: float) -> bool:
	if _aggressive_stance_suppress_timer > 0.0:
		_aggressive_stance_suppress_timer -= delta
	if attack_target == null:
		_sight_line.visible = false
		if aggressive_stance and _aggressive_stance_suppress_timer <= 0.0 and (is_idle() or is_attack_moving()):
			_aggressive_scan_cooldown -= delta
			if _aggressive_scan_cooldown <= 0.0:
				_aggressive_scan_cooldown = AGGRESSIVE_SCAN_INTERVAL
				_try_acquire_aggressive_target()
		return false
	if not is_instance_valid(attack_target) or attack_target.current_health <= 0.0:
		attack_target = null
		_sight_line.visible = false
		return false

	if aggressive_stance and not _attack_target_is_ordered:
		_aggressive_scan_cooldown -= delta
		if _aggressive_scan_cooldown <= 0.0:
			_aggressive_scan_cooldown = AGGRESSIVE_SCAN_INTERVAL
			_try_switch_to_closer_target()

	var to_target := attack_target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	if dist > attack_range + attack_target.get_engage_radius_bonus():
		_sight_line.visible = false
		return false

	var in_los := has_line_of_sight(attack_target)
	_draw_sight_line(attack_target, in_los)
	if not in_los:
		return false

	if dist > 0.01:
		var target_angle := atan2(to_target.x, to_target.z)
		_face_angle(target_angle, delta)
		# _face_angle only steps model_root.rotation.y partway toward
		# target_angle each frame (lerp_angle, see TURN_SPEED) -- it
		# doesn't snap there instantly. Swinging before that catches up
		# means the swing can fire while still facing whatever direction
		# the unit happened to be facing before this target came into
		# range, not actually toward the target -- which is exactly the
		# kind of misalignment ATTACK_IMPACT_FRACTIONS' hitbox-contact
		# measurements assume ISN'T happening (see its doc comment on
		# Attack_DualWield, whose 3 swing directions make it especially
		# sensitive to this). Hold off swinging until facing is within
		# FACING_TOLERANCE of the target, rather than firing on the very
		# first in-range frame regardless of current orientation.
		if absf(angle_difference(model_root.rotation.y, target_angle)) > FACING_TOLERANCE:
			return true
	perform_attack()
	return true

## Two entities are hostile to each other only if they're on opposite
## sides of the two actual playable factions (player_id 1/2) -- Gaia/Mob
## (player_id 3/4, see PLAYER_NAMES) are left alone by aggressive stance
## even though they'd technically have a "different player_id", since
## nothing establishes them as active combatants yet.
func _is_hostile_to(other: Entity) -> bool:
	return is_hostile_to_player(other.player_id)

## Same check as _is_hostile_to, but against a bare player_id rather than
## another Entity -- for a caller that doesn't have (or need) one of that
## side's actual Entities on hand, e.g. PortraitPanel's Ally/Enemy label,
## which checks a selected/inspected entity against
## GameState.human_player_id directly. Deliberately NOT the same thing as
## "is this the human player's own id" -- once there's ever a third,
## allied player_id in play, that side's entities should read "Ally" here
## (not hostile to the human player) without being the human player's own
## units.
func is_hostile_to_player(other_player_id: int) -> bool:
	return player_id != other_player_id and player_id in [1, 2] and other_player_id in [1, 2]

## Scans nearby units (not buildings -- aggressive stance is about
## reacting to mobile threats wandering close, not proactively marching on
## stationary structures, which stays a deliberate player order) for the
## CLOSEST hostile one within vision_range with a clear has_line_of_sight().
func _find_nearest_hostile() -> Entity:
	var nearest: Entity = null
	var nearest_dist := vision_range
	for candidate in get_tree().get_nodes_in_group("units"):
		if candidate == self or not is_instance_valid(candidate) or not candidate.visible:
			continue
		if candidate.current_health <= 0.0 or not _is_hostile_to(candidate):
			continue
		var dist: float = global_position.distance_to(candidate.global_position)
		if dist > nearest_dist:
			continue
		if not has_line_of_sight(candidate):
			continue
		nearest_dist = dist
		nearest = candidate
	return nearest

## Engages the closest hostile found by _find_nearest_hostile() via
## attack() (dispatches to Unit's own override, which also kicks off the
## chase), if any -- called while attack_target is empty, see
## _update_attack_target.
func _try_acquire_aggressive_target() -> void:
	var nearest := _find_nearest_hostile()
	if nearest != null:
		attack(nearest)
	else:
		_on_aggressive_scan_found_nothing()

## How much nearer a new candidate has to be than the current attack_target
## to actually win the swap (see _try_switch_to_closer_target) -- a bare
## sliver closer would otherwise cause needless back-and-forth switching
## between two roughly-equidistant hostiles every scan interval.
const CLOSER_TARGET_SWITCH_MARGIN: float = 1.0

## Re-evaluates an in-progress, NOT player-ordered attack_target (see
## _attack_target_is_ordered) against whoever's actually nearest right now,
## switching to it if meaningfully closer -- so auto-engagement (aggressive
## stance, attack-move) always prioritizes the nearest threat instead of
## tunnel-visioning on the first thing it happened to spot and chasing it
## all over the battlefield while a second attacker closes in from behind.
## A player's explicit attack order is exempt entirely -- that target
## sticks no matter what wanders closer.
func _try_switch_to_closer_target() -> void:
	var nearest := _find_nearest_hostile()
	if nearest == null or nearest == attack_target:
		return
	var current_dist := global_position.distance_to(attack_target.global_position)
	var candidate_dist := global_position.distance_to(nearest.global_position)
	if candidate_dist + CLOSER_TARGET_SWITCH_MARGIN < current_dist:
		attack(nearest)

## Called whenever an aggressive-stance scan (see _try_acquire_aggressive_target)
## finds no hostile to engage. Only meaningful to Unit's attack-move (resume
## marching toward the attack-move destination); a no-op by default.
func _on_aggressive_scan_found_nothing() -> void:
	pass

## Redraws the green/red debug sight line toward `target` -- see _sight_line.
func _draw_sight_line(target: Node3D, clear: bool) -> void:
	_sight_line.visible = true
	_sight_line_mat.albedo_color = Color(0.2, 1.0, 0.3) if clear else Color(1.0, 0.2, 0.2)
	_sight_line_mesh.clear_surfaces()
	_sight_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_sight_line_mesh.surface_add_vertex(to_local(global_position + Vector3(0, SIGHT_RAY_HEIGHT, 0)))
	_sight_line_mesh.surface_add_vertex(to_local(target.global_position + Vector3(0, SIGHT_RAY_HEIGHT, 0)))
	_sight_line_mesh.surface_end()

## Smoothly turns model_root toward `dir`'s heading -- freely, at whatever
## angle the direction actually is, not snapped to any fixed set of
## facings. Movement itself (see Unit._current_desired_direction) is
## likewise unconstrained, so a unit walking a diagonal or navmesh-routed
## path turns to face exactly the way it's actually going.
func _face_direction(dir: Vector3, delta: float) -> void:
	_face_angle(atan2(dir.x, dir.z), delta)

func _face_angle(angle: float, delta: float) -> void:
	model_root.rotation.y = lerp_angle(model_root.rotation.y, angle, TURN_SPEED * delta)
