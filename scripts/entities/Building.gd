extends Entity
class_name Building
## A stationary structure -- NOT a Unit (see Entity, the shared base both
## extend) -- so it's excluded from anything that specifically sweeps up
## "units" (the "units" group, the lobby's starting-unit-count/roster
## split, etc.), joining the "buildings" group instead. It still has
## health/belt/selection/team-color/attack-when-in-range, since all of
## that lives in Entity; Entity's own defaults already never move it,
## so there's nothing left to override here beyond group membership.

## True from the moment a foundation is placed (see
## BuildPlacementController.confirm_placement) until a constructing
## peasant's accumulated time reaches BuildingDefs.get_build_time (see
## advance_construction) -- gates every actual function this building
## would otherwise provide (training, garrison, upgrades) while still
## leaving it with normal health/collision, per this feature's own
## design: a foundation "has hp and a collision box" and nothing else.
var is_under_construction: bool = false
var _construction_timer: float = 0.0

## The actual visible model's own lowest/highest world-space Y (the union
## of every MeshInstance3D under model_root's own AABB, not this
## building's -- generally taller -- collision box) -- cached once in
## _ready() and used to size the ground-up reveal clip in
## _update_construction_shader (see get_construction_progress), so 50%
## constructed reveals exactly the bottom half of the model that's
## actually drawn, not the bottom half of its invisible collision
## footprint.
var _model_min_y: float = 0.0
var _model_max_y: float = 0.0

func _compute_model_y_range() -> void:
	var meshes := _find_mesh_instances(model_root)
	if meshes.is_empty():
		_model_min_y = global_position.y
		_model_max_y = global_position.y
		return
	var min_y := INF
	var max_y := -INF
	for mesh in meshes:
		var aabb: AABB = mesh.global_transform * mesh.get_aabb()
		min_y = minf(min_y, aabb.position.y)
		max_y = maxf(max_y, aabb.position.y + aabb.size.y)
	_model_min_y = min_y
	_model_max_y = max_y

## Shared world-space-clip shader that stands in for a mesh's normal
## material while this building is under construction -- see
## shaders/ConstructionReveal.gdshader's own doc comment for how the clip
## itself works, and _apply_construction_shader for how a mesh's normal
## color/roughness get copied into it so swapping materials doesn't
## change how the building looks, just how much of it is visible.
const CONSTRUCTION_SHADER: Shader = preload("res://shaders/ConstructionReveal.gdshader")
## Fraction of this building's full height visible the instant its
## foundation is placed, before any actual build time has been spent --
## so a brand-new foundation reads as "a sliver just poking out of the
## ground" rather than being fully invisible until a peasant starts
## working on it.
const MIN_REVEAL_FRACTION: float = 0.01

## Parallel arrays (index i = the same mesh) tracking every MeshInstance3D
## under model_root while the construction-reveal shader is active: the
## mesh itself, its original material_override (possibly null) to restore
## once finished, and the live ShaderMaterial instance whose
## reveal_world_y uniform _update_construction_shader raises every frame.
## Empty whenever is_under_construction is false.
var _construction_meshes: Array[MeshInstance3D] = []
var _construction_originals: Array[Material] = []
var _construction_shader_materials: Array[ShaderMaterial] = []

## Swaps every mesh under model_root onto its own ShaderMaterial instance
## (see CONSTRUCTION_SHADER), seeded with that mesh's current
## albedo/texture/roughness so the reveal is invisible as an effect in
## itself -- only the clip changes what's visible, not the color.
func _apply_construction_shader() -> void:
	for mesh in _find_mesh_instances(model_root):
		var original := mesh.material_override
		var source: Material = original if original != null else mesh.get_active_material(0)
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = CONSTRUCTION_SHADER
		if source is StandardMaterial3D:
			var std: StandardMaterial3D = source
			shader_mat.set_shader_parameter("albedo_color", std.albedo_color)
			shader_mat.set_shader_parameter("roughness", std.roughness)
			if std.albedo_texture != null:
				shader_mat.set_shader_parameter("albedo_texture", std.albedo_texture)
				shader_mat.set_shader_parameter("use_texture", true)
		_construction_meshes.append(mesh)
		_construction_originals.append(original)
		_construction_shader_materials.append(shader_mat)
		mesh.material_override = shader_mat
	_update_construction_shader()

## Raises reveal_world_y on every construction-reveal ShaderMaterial to
## match current progress -- called once up front (see
## _apply_construction_shader) and then every _process frame while
## is_under_construction stays true.
func _update_construction_shader() -> void:
	var reveal_fraction := maxf(MIN_REVEAL_FRACTION, get_construction_progress())
	var reveal_world_y: float = lerpf(_model_min_y, _model_max_y, reveal_fraction)
	for shader_mat in _construction_shader_materials:
		shader_mat.set_shader_parameter("reveal_world_y", reveal_world_y)

## Puts every mesh's original material_override back (null restores
## whatever the .tscn/inherited material chain would normally resolve
## to) once construction finishes -- see advance_construction.
func _restore_construction_materials() -> void:
	for i in _construction_meshes.size():
		var mesh := _construction_meshes[i]
		if is_instance_valid(mesh):
			mesh.material_override = _construction_originals[i]
	_construction_meshes.clear()
	_construction_originals.clear()
	_construction_shader_materials.clear()

## Recursive so a mesh nested more than one level under model_root (not
## the case for any building today, but not guaranteed to stay that way)
## still gets picked up.
func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child)
		result.append_array(_find_mesh_instances(child))
	return result

## 0.0 (nothing built yet) once is_under_construction is true; 1.0 once
## finished (and forever after, once is_under_construction is false).
func get_construction_progress() -> float:
	if not is_under_construction:
		return 1.0
	return clampf(_construction_timer / BuildingDefs.get_build_time(unit_type_id), 0.0, 1.0)

## Advances this foundation's construction by `delta` seconds -- called
## every physics tick a constructing peasant is actually in range (see
## Unit._update_construct_target), same "caller ticks me, I don't tick
## myself" shape Entity.take_damage's callers use. No-op once already
## finished, so a peasant that lingers after completion can't do
## anything odd by continuing to call this.
func advance_construction(delta: float) -> void:
	if not is_under_construction:
		return
	_construction_timer += delta
	if _construction_timer >= BuildingDefs.get_build_time(unit_type_id):
		is_under_construction = false
		_restore_construction_materials()
		construction_workers.clear()
		# Path of Order -- baked in once at the exact moment construction
		# finishes (see PathPerks.building_health_multiplier's own doc
		# comment for why this is a one-time bump rather than a live
		# multiplier at every max_health read site), and heals to the new
		# max since a just-finished building reads as freshly built, not
		# freshly built-then-damaged.
		max_health *= PathPerks.building_health_multiplier(player_id)
		current_health = max_health

## True if any of the human player's own buildings sits within
## PathPerks.DECAY_RADIUS of this one -- see _physics_process's own
## Path of Decay check.
func _near_human_building() -> bool:
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and building.player_id == GameState.human_player_id and building.global_position.distance_to(global_position) <= PathPerks.DECAY_RADIUS:
			return true
	return false

## Every peasant whose construct_target is currently this building -- kept
## in sync by Unit.construct_target's own setter (add_construction_worker/
## remove_construction_worker), not polled, so it stays correct the
## instant a peasant walks away/gets a new order/dies just as much as
## when one arrives. is_being_constructed() (whether at least one entry
## exists) is what get_tooltip_extra_stats/etc. could key off if a
## "someone is working on this" indicator is ever needed beyond the
## one-shot tasking blink (see add_construction_worker).
var construction_workers: Array[Unit] = []

## Every peasant actually tasked to construct this foundation (see
## Unit.construct_target's own setter, which is what calls this) fires
## the one-shot blink -- the feedback for "you just tasked a unit onto
## me", same "you just did the clicking, here's confirmation" moment
## blink_attack_target's own call site (an attack order) reacts to.
func add_construction_worker(unit: Unit) -> void:
	if unit in construction_workers:
		return
	construction_workers.append(unit)
	blink_construction_target()

func remove_construction_worker(unit: Unit) -> void:
	construction_workers.erase(unit)

## True while at least one peasant is actively working this foundation --
## see construction_workers' own doc comment.
func is_being_constructed() -> bool:
	return is_under_construction and not construction_workers.is_empty()

## Color the selection ring flashes while blinking -- distinct from both
## the normal green (Entity.SELECTION_RING_COLOR) and the attack-target
## red (Entity.ATTACK_TARGET_BLINK_COLOR) flash, so all three read as
## different things at a glance.
const CONSTRUCTION_BLINK_COLOR: Color = Color(1.0, 0.75, 0.15, 1.0)

## Flashes this foundation's selection ring amber twice -- fired once by
## add_construction_worker() whenever a foundation goes from nobody
## working it to somebody working it (a fresh assignment, or resuming an
## abandoned one), not a standing/indefinite blink for as long as work
## continues. Reuses Entity.blink_attack_target()'s own on/off rhythm and
## restore-afterward behavior, just with this feature's own color.
func blink_construction_target() -> void:
	blink_attack_target(2, CONSTRUCTION_BLINK_COLOR)

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

## Local corner this building's StorageFlag sits at -- the back top
## corner, diagonally opposite STORAGE_EJECT_ANGLE's front-bottom
## ejection point (the corner nearest the camera in this fixed
## isometric view), so the flag reads as sitting on the roof away from
## the viewer rather than in front of the building.
const STORAGE_FLAG_POSITION: Vector3 = Vector3(-1.17, 2.47, -1.17)
var _storage_flag: StorageFlag = null

## Adds `item_type` if there's a free slot, and reports whether it
## actually fit -- caller decides what happens to the item if not (e.g.
## _on_thrown_item_landed leaves it as a normal ground pickup instead of
## handing it over when storage is already full).
func store_item(item_type: String) -> bool:
	if stored_items.size() >= MAX_STORAGE_SLOTS:
		return false
	stored_items.append(item_type)
	storage_changed.emit(self)
	_update_storage_flag()
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
	_update_storage_flag()
	return true

## Shows/hides the back-top-corner StorageFlag depending on whether
## there's anything stored -- built lazily on first actual need (most
## buildings never store anything) rather than unconditionally in
## _ready(), and (re)colored every call so it always matches this
## building's current player_id even if that somehow changes after
## spawn.
func _update_storage_flag() -> void:
	var has_items := not stored_items.is_empty()
	if _storage_flag == null:
		if not has_items:
			return
		_storage_flag = StorageFlag.spawn(self, STORAGE_FLAG_POSITION, Entity.PLAYER_COLORS.get(player_id, Color.WHITE))
		return
	_storage_flag.visible = has_items
	_storage_flag.set_color(Entity.PLAYER_COLORS.get(player_id, Color.WHITE))

## Once an enemy building has been seen at least once, fog of war keeps it
## visible (at its last-known position) even after it drops out of vision
## again -- unlike enemy units, which vanish immediately. Set by
## RTSController._update_fog_of_war.
var ever_seen: bool = false

## Whether this building shows a Train section and accepts
## queue_training() at all -- only Castle.tscn sets this true right now.
## Replaces the old auto-repeating trains_unit_type field: peasant
## production used to run on its own free-running timer regardless of
## what the player did; now it's just one more entry in the same
## player-queued training_queue every other trainable type already uses
## (see queue_training/PEASANT_TRAIN_COST/PEASANT_TRAIN_TIME).
@export var can_train: bool = false
## What actually gets instantiated for any trained unit -- every roster
## unit in Main.tscn (Human, Darkling, Elf, ...) already reuses this
## exact same rigged model, differing only by unit_type_id, so a trained
## peasant/squire does too rather than needing its own dedicated model.
const TRAIN_UNIT_SCENE: PackedScene = preload("res://scenes/ParentUnit.tscn")
## How long training_queue takes per entry for every trainable type
## except "peasant" (which has its own fixed PEASANT_TRAIN_TIME) -- see
## _queue_interval_for. No more hut-count discount: dwellings only
## contribute population now (see ResourceHUD.POPULATION_PER_HUT).
const DEFAULT_TRAIN_INTERVAL: float = 60.0
## Peasants are trained through the same training_queue as every other
## type, but at their own fixed cost/duration rather than
## DEFAULT_TRAIN_INTERVAL -- charged up front when queued (see
## TaskPanel._on_train_pressed), same "pay now, refuse if you can't
## afford it" pattern a building's own placement cost uses.
const PEASANT_TRAIN_COST: Dictionary = {"apples": 50}
const PEASANT_TRAIN_TIME: float = 30.0

## Player-queued unit types waiting to be trained -- see queue_training(),
## called by TaskPanel's Peasant/Squire/Apprentice/Knight/Mage buttons.
var training_queue: Array[String] = []
var _queue_timer: float = 0.0

## Seconds to research any one upgrade (see UPGRADE_RESEARCH_TIME's own
## values -- there's only one upgrade defined right now, "Wild Rot", so
## a single flat constant is enough; a per-upgrade cost table like
## BuildingDefs.DEFS would replace this if a second one is ever added).
const UPGRADE_RESEARCH_TIME: float = 20.0
## Non-empty while a research order is outstanding -- same "one thing in
## progress, others queue behind it" idea as training_queue, but capped
## to a single slot per building (real RTS tech research is one-at-a-
## time per building too) rather than an array. Cleared either by
## finishing (moves into researched_upgrades) or by cancel_research().
var researching_upgrade: String = ""
var _upgrade_timer: float = 0.0
## Upgrades this building has actually finished researching -- permanent,
## unlike training_queue's one-shot spawns. Checked so a finished upgrade
## can't be re-queued or re-canceled.
var researched_upgrades: Array[String] = []

## Starts researching `upgrade_name` if this building has no research
## already running and hasn't already finished this one -- false (no
## change) otherwise, same "refuse silently, caller doesn't need to
## react" shape as add_garrisoned_unit.
func start_research(upgrade_name: String) -> bool:
	if not researching_upgrade.is_empty() or upgrade_name in researched_upgrades:
		return false
	researching_upgrade = upgrade_name
	_upgrade_timer = 0.0
	return true

## Cancels whatever's currently researching, discarding its progress --
## the technology backend's half of "cancel in-progress units/
## technologies by clicking the progress icon" (see TaskPanel's upgrade
## buttons, which double as their own progress display and cancel click
## target since there's no separate queue-icon row for a single slot).
## A no-op if nothing is researching.
func cancel_research() -> void:
	researching_upgrade = ""
	_upgrade_timer = 0.0

## Fraction (0..1) of the way through the current research -- 0.0 while
## nothing is researching. Mirrors get_queue_progress()'s shape.
func get_research_progress() -> float:
	if researching_upgrade.is_empty():
		return 0.0
	return clampf(_upgrade_timer / _effective_upgrade_research_time(), 0.0, 1.0)

## UPGRADE_RESEARCH_TIME, shortened by Path of Wishes -- see
## PathPerks.research_time_multiplier's own doc comment for why this is
## a time reduction rather than the perk text's literal "cost" (Wild Rot
## has no resource cost to reduce).
func _effective_upgrade_research_time() -> float:
	return UPGRADE_RESEARCH_TIME * PathPerks.research_time_multiplier(player_id)

## Prefers BuildingDefs' own display_name for unit_type_id over the node-
## name derivation Entity.get_tooltip_title falls back to -- unlike a
## hand-placed roster Unit (see ParentUnit.tscn's Human/Darkling/Elf/...),
## a Building's own node name is never a deliberate flavor choice, just
## whatever the scene's root happened to be named (or a collision-
## resolved "Hut2", or worse, an anonymous "@CharacterBody3D@" if
## force_readable_name was ever missed at some add_child() call site --
## see BuildPlacementController.confirm_placement's own fix for that).
## Falls back to the node-name derivation for any unit_type_id
## BuildingDefs doesn't recognize, so nothing regresses for a type this
## table hasn't been taught about yet.
func get_tooltip_title() -> String:
	var defs_name := BuildingDefs.get_display_name(unit_type_id)
	return defs_name if not defs_name.is_empty() else super.get_tooltip_title()

## Shows construction progress in the hover/selection tooltip in place of
## every other stat while this is still a foundation -- there's nothing
## else meaningful to show (see Entity.get_tooltip_extra_stats' own doc
## comment on what this overrides).
func get_tooltip_extra_stats() -> Dictionary:
	if not is_under_construction:
		return {}
	return {"Constructing": "%d%%" % int(get_construction_progress() * 100.0)}

## Units currently sheltered inside this building -- see
## Unit.garrison_in/seek_garrison (the Garrison/Seek Shelter commands).
## Capacity comes from BuildingDefs.get_garrison_capacity(unit_type_id),
## roughly scaled to footprint_tiles (see its own doc comment).
var garrisoned_units: Array[Unit] = []

func get_garrison_capacity() -> int:
	return BuildingDefs.get_garrison_capacity(unit_type_id)

func can_garrison() -> bool:
	return not is_under_construction and garrisoned_units.size() < get_garrison_capacity()

## Returns true and adds `unit` if there's room; false (no change)
## otherwise -- caller (Unit._update_garrison_target) checks this before
## actually hiding/disabling the unit, so a race between two units both
## approaching the last open slot never over-fills it.
func add_garrisoned_unit(unit: Unit) -> bool:
	if not can_garrison():
		return false
	garrisoned_units.append(unit)
	return true

func remove_garrisoned_unit(unit: Unit) -> void:
	garrisoned_units.erase(unit)

func _ready() -> void:
	super._ready()
	add_to_group("buildings")
	_compute_model_y_range()
	if is_under_construction:
		_apply_construction_shader()

## Presentation-only: keeps the construction-reveal clip in step with
## current progress every frame. No-op once construction finishes -- see
## the is_under_construction guard. Applies the shader lazily here (not
## just in _ready()) because BuildPlacementController.confirm_placement
## sets is_under_construction = true AFTER add_child() has already run
## this building's _ready() -- so for a freshly-placed foundation, the
## very first _process call is actually the first moment this building
## knows it's under construction at all.
func _process(_delta: float) -> void:
	if not is_under_construction:
		return
	if _construction_shader_materials.is_empty():
		_apply_construction_shader()
	else:
		_update_construction_shader()

## A garrisoned unit is hidden/disabled (see Unit.garrison_in), not gone --
## if the building holding it dies, every sheltered unit needs to actually
## reappear outside rather than being trapped invisible forever inside a
## building that no longer exists. Released BEFORE super._die() so each
## unit's own ungarrison() (which reads this building's global_position)
## still has a valid position to pop out next to.
func _die(attacker: Entity = null) -> void:
	for unit in garrisoned_units.duplicate():
		if is_instance_valid(unit):
			unit.ungarrison()
	super._die(attacker)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# Path of Decay -- checked from the (potential) VICTIM's own tick,
	# same shape World.gd's own Path of Corruption check has: this
	# building takes damage if it's an enemy of the human player, the
	# human follows Decay, and this building sits within
	# PathPerks.DECAY_RADIUS of any of the human's own buildings.
	# Deliberately not gated behind is_under_construction below --
	# a foundation can be decayed too, same as it can be attacked.
	if player_id != GameState.human_player_id and PathPerks.has_decay(GameState.human_player_id) and _near_human_building():
		take_damage(PathPerks.DECAY_DAMAGE_PER_SECOND * delta)
	# A foundation "has hp and a collision box" and nothing else -- no
	# training, no research -- until is_under_construction clears (see
	# advance_construction).
	if is_under_construction:
		return
	if not training_queue.is_empty():
		_queue_timer += delta
		var queue_interval := _queue_interval_for(training_queue[0])
		if _queue_timer >= queue_interval:
			_queue_timer -= queue_interval
			_train_unit(training_queue.pop_front())
	if not researching_upgrade.is_empty():
		_upgrade_timer += delta
		if _upgrade_timer >= _effective_upgrade_research_time():
			researched_upgrades.append(researching_upgrade)
			researching_upgrade = ""
			_upgrade_timer = 0.0

## Adds one unit of unit_type_id to this building's player-directed
## training queue -- see training_queue's doc comment. Multiple calls
## stack up multiple entries, trained one at a time in the order queued.
func queue_training(unit_type_id: String) -> void:
	training_queue.append(unit_type_id)

## Read-only copy for UI display (TrainingUpgradesPanel) -- callers should
## not mutate the returned array directly, use queue_training() instead.
func get_training_queue() -> Array[String]:
	return training_queue.duplicate()

## Removes one queued entry by index (see TaskPanel's queue icons -- left-
## clicking one calls this with its own position). Canceling index 0 --
## the entry actually in progress right now, mid-_queue_timer -- discards
## that partial progress too, same as if it had never been queued; every
## entry behind it simply shifts forward and starts counting from 0 once
## it becomes the new front, exactly like normal queue advancement.
func cancel_training(index: int) -> void:
	if index < 0 or index >= training_queue.size():
		return
	training_queue.remove_at(index)
	if index == 0:
		_queue_timer = 0.0

## Fraction (0..1) of the way through training the queue's current head --
## 0.0 while the queue is empty.
func get_queue_progress() -> float:
	if training_queue.is_empty():
		return 0.0
	return clampf(_queue_timer / _queue_interval_for(training_queue[0]), 0.0, 1.0)

## Seconds remaining until the queue's current head finishes training --
## 0.0 while the queue is empty.
func get_queue_seconds_remaining() -> float:
	if training_queue.is_empty():
		return 0.0
	return maxf(_queue_interval_for(training_queue[0]) - _queue_timer, 0.0)

## Peasants take their own fixed PEASANT_TRAIN_TIME; every other
## trainable type takes the flat DEFAULT_TRAIN_INTERVAL. Path of Cunning
## shortens either one -- see PathPerks.training_time_multiplier's own
## doc comment.
func _queue_interval_for(unit_type_id: String) -> float:
	var base := PEASANT_TRAIN_TIME if unit_type_id == "peasant" else DEFAULT_TRAIN_INTERVAL
	return base * PathPerks.training_time_multiplier(player_id)

## Spawns one unit_type_id unit at this building's first queued gather
## point (see gather_points -- the same "where trained units should walk
## to" spot a future full production queue would use too), or just
## adjacent to the building itself if no gather point has been set.
## Added alongside whatever other units already exist rather than under
## this building specifically -- group membership ("units", see
## Unit._ready), not scene-tree parentage, is what RTSController and
## every other group-based sweep actually key off of.
func _train_unit(unit_type_id: String) -> void:
	var unit: Node = TRAIN_UNIT_SCENE.instantiate()
	# ParentUnit.tscn's own root node is literally named "Unit" -- every
	# hand-placed roster entry in Main.tscn overrides that per-instance
	# (see e.g. its "Human"/"Darkling" nodes), but a unit spawned here at
	# runtime never would otherwise, so Entity.display_name_for (which
	# reads the node's own name, not unit_type_id) would show every
	# trained unit as just "Unit" regardless of what it actually is.
	unit.name = unit_type_id.capitalize()
	var container: Node = get_tree().current_scene.get_node_or_null("Units")
	if container == null:
		container = get_parent()
	container.add_child(unit)
	unit.player_id = player_id
	unit.unit_type_id = unit_type_id
	# +Z is this game's "south" (see CameraRig's transform in Main.tscn --
	# the camera sits out along +Z looking back toward the origin, so +Z
	# reads as "toward the bottom of the screen"/south). A trained unit
	# with nowhere queued to walk to (see gather_points) spawns just south
	# of the building's own footprint (see _footprint_half_extent_z --
	# NOT get_engage_radius_bonus(), a flat 1.7 tuned for the base 1-tile
	# building's engagement distance, not an actual footprint size; using
	# it here left a peasant spawning inside Castle's much bigger 5x5
	# footprint) rather than east of it.
	var spawn_pos: Vector3 = (
		gather_points[0] if not gather_points.is_empty()
		else global_position + Vector3(0, 0, _footprint_half_extent_z() + 1.0)
	)
	unit.global_position = spawn_pos

## This building's own actual half-footprint along Z (world units,
## already accounting for however much this instance's own transform
## scales its base CollisionShape3D -- e.g. Castle.tscn's 5x scale) --
## unlike get_engage_radius_bonus() (a flat constant tuned for the base
## 1-tile building's engagement distance), this reads the real shape, so
## it stays correct for a building with a much bigger footprint. Falls
## back to get_engage_radius_bonus() if this building has no
## CollisionShape3D with a BoxShape3D (shouldn't happen for any real
## building, but defensive).
func _footprint_half_extent_z() -> float:
	var collision: CollisionShape3D = get_node_or_null("CollisionShape3D")
	if collision == null or not (collision.shape is BoxShape3D):
		return get_engage_radius_bonus()
	var box: BoxShape3D = collision.shape
	return box.size.z * 0.5 * global_transform.basis.get_scale().z

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
