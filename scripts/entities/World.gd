extends Entity
class_name World
## A static world object (trees, resource nodes, ...) -- not a
## player-built Building and not a mobile Unit. Joins the "world" group
## instead of "units"/"buildings", so RTSController's fog-of-war pass
## leaves it alone entirely: unlike an enemy Building it's never hidden or
## "remembered" once seen, since it's just always there -- the same way the
## ground itself is never hidden, only lit or unlit by whoever's nearby.

## Sub-type for display only (e.g. "pine", "oak") -- "" for a World
## object with no species concept. Shown in the hover tooltip title as
## "Pine Tree" rather than just "Tree" (see get_tooltip_title). Cleared
## once depleted (see _deplete) so a stump reads as "Old Oak Stump", not
## "Oak Old Oak Stump".
@export var species: String = ""

## Overrides the tooltip title outright (e.g. "Oak Tree") instead of
## deriving it from species + this node's own (arbitrary, often
## disambiguated-with-a-number) node name -- see get_tooltip_title.
## Empty means fall back to the species/node-name derivation.
@export var display_name_override: String = ""

## Which of this game's 4 resources gathering this node yields --
## "acorns"/"apples"/"crystal"/"mist", or "" for a World object that
## can't be gathered at all (a decorative rock, or an already-depleted
## stump -- see resource_type being cleared in _deplete). Matches
## ResourceHUD.RESOURCE_ORDER's own naming exactly, since gather() hands
## straight into ResourceHUD.add_resource with this string.
@export var resource_type: String = ""
## Total yield this node started with -- 100 for a tree (Oak/Apple),
## 400/500 for Crystal Cave/Mist Fissure (see each scene's own values).
## 0 for a non-gatherable World object, same "no resource" reasoning
## resource_type's own empty-string default has.
@export var max_resource: float = 0.0
var current_resource: float

## "stump" (trees): stays in the world with resource_type cleared and
## collision disabled once depleted, so it reads as scenery rather than
## vanishing outright -- see _become_stump/DEPLETED_SPECIES. "remove"
## (Crystal Cave/Mist Fissure): queue_free()s entirely once depleted,
## same "limited resource, gone once mined out" convention AoE2's own
## gold/stone has. Ignored entirely for a non-gatherable World object.
@export_enum("stump", "remove") var depleted_behavior: String = "stump"
## What `species` becomes once this node depletes into a stump -- e.g.
## "old oak" for an Oak Tree, so get_tooltip_title reads "Old Oak Stump".
## Ignored for depleted_behavior == "remove" (nothing to rename).
@export var depleted_species: String = ""
## Node name (a child of ModelRoot) to hide once depleted into a stump --
## e.g. a tree's foliage mesh, so only the bare trunk remains standing.
## Ignored for depleted_behavior == "remove". Empty means nothing hides.
@export var depleted_hide_node: NodePath = NodePath()

## How far outside this node's own collision a unit needs to stand to
## gather/interact with it -- same "approach range tuned to this node's
## own footprint, not its unreachable center" reasoning Building.gd's own
## override has (its flat 1.7 is tuned for a 1-tile building; this node's
## own box footprint varies per resource-node scene, so each sets its own
## value instead of sharing one constant). 0.0 (Entity's own default) is
## fine for a World object nothing ever needs to approach precisely, like
## a plain decorative tree.
@export var engage_radius_bonus: float = 0.0

func get_engage_radius_bonus() -> float:
	return engage_radius_bonus

## False for a pure resource node (Oak/Apple Tree, Crystal Cave, Mist
## Fissure) -- these have no health at all: no health bar, and immune to
## take_damage entirely (see the override below), rather than the earlier
## "just give it a huge max_health" stand-in. True (the default) keeps a
## plain decorative World object (the non-gatherable pine Tree) exactly as
## choppable/attackable as it always was.
@export var has_health: bool = true

## True from the moment a peasant plants this tree (see
## RTSController._issue_plant_click) until GROW_TIME seconds pass (see
## _physics_process) -- shown small (see SEEDLING_SCALE) and can't be
## gathered yet (see can_gather), matching the "starts as a seedling,
## grows into a mature tree" behavior Oak/Apple planting is meant to
## have. Always false (the default) for a hand-placed map tree/resource
## node -- those start already grown.
@export var is_seedling: bool = false
## How long a planted seedling takes to mature into a full, gatherable
## tree.
const GROW_TIME: float = 60.0
var _grow_timer: float = 0.0
## Uniform scale a seedling renders at (shrunk down from its mature
## ModelRoot size) -- purely visual, so a growing sapling reads as
## smaller than a full tree without needing a wholly separate seedling
## model/scene.
const SEEDLING_SCALE: float = 0.35

func _ready() -> void:
	super._ready()
	add_to_group("world")
	current_resource = max_resource
	if not has_health:
		_update_resource_bar()
	if is_seedling:
		model_root.scale = Vector3.ONE * SEEDLING_SCALE
	if _is_deciduous():
		_season_clock = get_tree().current_scene.get_node_or_null("UI/SeasonClock")
		if _season_clock != null:
			_season_clock.season_changed.connect(_on_season_changed)
			_season_clock.day_changed.connect(_on_day_changed)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_seedling:
		_grow_timer += delta
		if _grow_timer >= GROW_TIME:
			is_seedling = false
			model_root.scale = Vector3.ONE
	_update_fall_refresh(delta)

## True for an oak/apple tree specifically (checked via unit_type_id,
## which -- unlike species -- stays "oak_tree"/"apple_tree" for life even
## once depleted into a stump; see species' own doc comment for why it
## isn't a safe permanent check) -- every other World object (Crystal
## Cave, Mist Fissure, a decorative Pine) neither refreshes on Fall nor
## dies of old age.
func _is_deciduous() -> bool:
	return unit_type_id == "oak_tree" or unit_type_id == "apple_tree"

## Where this tree looks up the shared annual calendar -- see SeasonClock.gd.
## Null for anything _is_deciduous() doesn't apply to, or if a scene
## somehow has no UI/SeasonClock at all (a bare debug/test scene); every
## call site below already no-ops gracefully when this is null.
var _season_clock: Node = null

func _on_season_changed(season: String, _year: int) -> void:
	if season == "Fall":
		_start_fall_refresh()

## How many in-game winters this tree has lived through -- see
## _on_day_changed. Every other World object has no lifespan at all
## (_is_deciduous() gates the signal connection that ever calls this).
const TREE_LIFESPAN_WINTERS: int = 4
var _winters_survived: int = 0

## Fires once per in-game day (see SeasonClock.day_changed) -- checked
## against SeasonClock's own calendar rather than this tree's personal
## age, so "how many winters has this tree seen" just means "how many
## times has winter's last day happened while this tree existed", the
## same everyday sense a real tree's ring count would have. Winter's last
## day is always the calendar year's very last day (YEAR_DAYS - 1) given
## SeasonClock's own quarter split -- see its SEASON_START_DAYS doc
## comment. Once TREE_LIFESPAN_WINTERS of those have passed, the tree
## simply dies of old age (queue_free()) -- unlike depleted_behavior's
## "stump" outcome, old age is the end for good, not just this season's
## harvest running out.
func _on_day_changed(total_days: int) -> void:
	if total_days % SeasonClock.YEAR_DAYS != SeasonClock.YEAR_DAYS - 1:
		return
	_winters_survived += 1
	if _winters_survived >= TREE_LIFESPAN_WINTERS:
		queue_free()

## How many in-game days the Fall refresh (see _start_fall_refresh) takes
## to fully top a tree back up -- the user's own "over the course of 30
## in-game seconds/days" request (SeasonClock.DAY_SECONDS makes those the
## same unit).
const FALL_REFRESH_DAYS: float = 30.0
var _fall_refresh_active: bool = false
## Resource units added per in-game day -- fixed once, from the deficit at
## the moment Fall actually started, rather than continuously re-aimed at
## "whatever's still missing" -- so it composes correctly with a peasant
## gathering from this same tree at the same time (each tick just adds its
## own fixed increment on top of gather()'s own subtraction, instead of
## one clobbering the other the way a "lerp toward max_resource" formula
## would if gathering changed current_resource out from under it).
var _fall_refresh_rate: float = 0.0
var _fall_refresh_days_remaining: float = 0.0

## Starts this tree's once-a-year top-up the instant Fall begins --
## already-full trees and already-depleted stumps (resource_type cleared
## by _deplete) both no-op, since there's nothing to refresh either way.
func _start_fall_refresh() -> void:
	if resource_type.is_empty() or current_resource >= max_resource:
		return
	_fall_refresh_rate = (max_resource - current_resource) / FALL_REFRESH_DAYS
	_fall_refresh_days_remaining = FALL_REFRESH_DAYS
	_fall_refresh_active = true

func _update_fall_refresh(delta: float) -> void:
	if not _fall_refresh_active:
		return
	var delta_days: float = delta / SeasonClock.DAY_SECONDS
	current_resource = minf(current_resource + _fall_refresh_rate * delta_days, max_resource)
	_fall_refresh_days_remaining -= delta_days
	_update_resource_bar()
	if current_resource >= max_resource or _fall_refresh_days_remaining <= 0.0:
		_fall_refresh_active = false

## Presentation-only: continuously grows a planted seedling's visual size
## from SEEDLING_SCALE up to full size in step with _grow_timer, rather
## than jumping straight from tiny to full-grown the instant GROW_TIME is
## reached -- matches this project's own sim/presentation split (gameplay
## state -- _grow_timer, is_seedling, can_gather -- stays on the physics
## tick in _physics_process; this only ever reads it). No-op once grown
## (is_seedling already false, and _physics_process's own final snap to
## Vector3.ONE already covers the last frame exactly).
func _process(_delta: float) -> void:
	if not is_seedling:
		return
	var t := clampf(_grow_timer / GROW_TIME, 0.0, 1.0)
	model_root.scale = Vector3.ONE * lerpf(SEEDLING_SCALE, 1.0, t)

## A decorative World object without health (see has_health's own doc
## comment) keeps the health bar hidden no matter what (selection, taking
## damage elsewhere, ...) tries to show it -- but a gatherable resource
## node (has_health false AND a resource_type) instead reuses this same
## bar to show its own remaining/total yield, see _update_resource_bar.
func _update_health_bar_visibility() -> void:
	if not has_health:
		_update_resource_bar()
		return
	super._update_health_bar_visibility()

## Shows health_bar as a "how much is left" bar for a gatherable resource
## node -- only while partially depleted (hidden at full yield, same as a
## full-health unit's own bar; and there's nothing left to show once it
## hits zero -- a stump's resource_type is already cleared by then, and a
## "remove" node has already queue_free()d itself, see _deplete), rather
## than the selection/damage-driven visibility Entity's own
## _update_health_bar_visibility gives a combat unit. Called after every
## gather() tick so the bar's fill fraction stays live, and once from
## _ready() in case a node somehow starts already-depleted.
func _update_resource_bar() -> void:
	if resource_type.is_empty() or max_resource <= 0.0:
		health_bar.visible = false
		return
	health_bar.set_health_fraction(current_resource / max_resource)
	health_bar.visible = current_resource > 0.0 and current_resource < max_resource

## No-op instead of Entity's own damage/death handling -- a pure resource
## node (see has_health) can never be destroyed by combat at all, matching
## real RTS resource nodes (a Crystal Cave isn't a "kill it for XP"
## target).
func take_damage(amount: float, attacker: Entity = null) -> void:
	if not has_health:
		return
	super.take_damage(amount, attacker)

func get_tooltip_title() -> String:
	if not display_name_override.is_empty():
		return display_name_override
	var base_name := Entity.display_name_for(self)
	return "%s %s" % [species.capitalize(), base_name] if not species.is_empty() else base_name

## Static/descriptive only -- what this object is, not any live-changing
## count (see the user's own "tooltips should never show progress" rule).
## A live number belongs in PortraitPanel instead (see its own
## _refresh_world_extras/get_growth_progress), which stays attached to one
## selected object for as long as it's selected; a tooltip can appear over
## a different object the very next frame, so it should read the same
## whether it's the first hover or the hundredth, not tick down live.
func get_tooltip_extra_stats() -> Dictionary:
	if is_seedling:
		return {"Status": "Growing"}
	if resource_type.is_empty():
		return {}
	return {"Yields": resource_type.capitalize()}

## 0..1 fraction of the way a planted seedling (see is_seedling) has grown
## -- shared by get_tooltip_extra_stats' own plain-text percentage and
## PortraitPanel's live growth bar (see PortraitPanel._refresh_world_extras)
## so neither has to reach into _grow_timer directly.
func get_growth_progress() -> float:
	return clampf(_grow_timer / GROW_TIME, 0.0, 1.0)

## True while there's still something a peasant can gather here -- checked
## by Unit._update_gather_target/RTSController's right-click-to-gather
## handling before issuing or continuing a gather order.
func can_gather() -> bool:
	return not is_seedling and not resource_type.is_empty() and current_resource > 0.0

## Takes up to `amount` off this node's remaining resource and hands it
## straight to the human player's bank (see ResourceHUD.add_resource) --
## returns the actual amount taken (less than `amount` right at the very
## end, once fewer than a full tick's worth remains), same "clamp to
## what's actually left" shape Building.advance_construction's timer
## doesn't need but a depleting stockpile does. Deletes/stumps itself via
## _deplete once nothing's left.
## Fractional leftover from previous gather() calls that hasn't added up
## to a whole resource unit yet -- a single tick's worth (GATHER_RATE *
## one physics delta) is well under 1.0, so int()-truncating each call on
## its own would silently discard every tick's gain forever and never
## actually deposit anything. Banked here and only handed to
## ResourceHUD.add_resource (which only deals in whole ints) once it
## crosses a whole unit.
var _carry: float = 0.0

## Path of Corruption -- "enemy units near your units gather 20%
## slower": if the HUMAN player follows Corruption and `player_id` (the
## gatherer, an enemy from the human's perspective) is gathering within
## PathPerks.CORRUPTION_RADIUS of any of the human's own units, this
## node's own yield is slowed for that tick. Checked here (not in
## Unit._update_gather_target, which only knows its OWN player_id) since
## this is the one place that already knows both "who's gathering" and
## "where" (this node's own position, close enough to the gathering
## unit for a radius check without needing the unit's exact position
## threaded through the whole call chain).
func _slowed_by_corruption(gatherer_player_id: int) -> bool:
	if gatherer_player_id == GameState.human_player_id or not PathPerks.has_corruption(GameState.human_player_id):
		return false
	for unit in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(unit) and unit.player_id == GameState.human_player_id and unit.global_position.distance_to(global_position) <= PathPerks.CORRUPTION_RADIUS:
			return true
	return false

func gather(amount: float, resource_hud: ResourceHUD, player_id: int) -> float:
	if not can_gather():
		return 0.0
	if _slowed_by_corruption(player_id):
		amount *= PathPerks.CORRUPTION_SLOW_MULTIPLIER
	var taken: float = minf(amount, current_resource)
	current_resource -= taken
	_carry += taken
	var whole := int(_carry)
	if whole > 0:
		resource_hud.add_resource(player_id, resource_type, whole)
		_carry -= whole
	_update_resource_bar()
	if current_resource <= 0.0:
		_deplete()
	return taken

func _deplete() -> void:
	if depleted_behavior == "remove":
		queue_free()
		return
	resource_type = ""
	species = depleted_species
	display_name_override = ""
	selection_ring.visible = false
	if not depleted_hide_node.is_empty():
		var hidden := get_node_or_null(depleted_hide_node)
		if hidden != null:
			hidden.visible = false
	collision_layer = 0
	collision_mask = 0

## World objects never fight -- overriding both means neither an order to
## attack it (attack(), from Unit.gd's chase-and-attack override) nor its
## own defend-when-approached default (Entity._update_attack_target, via
## can_attack() gating perform_attack()) can ever land a swing.
func attack(_target: Node3D) -> void:
	pass

func can_attack() -> bool:
	return false
