extends RefCounted
class_name PathPerks
## Wires each of PathDefs' 14 placeholder perk descriptions to an actual
## gameplay effect. One static helper per perk, each gated identically:
## only the HUMAN player benefits (see GameState.human_player_id/
## human_path_state -- there's no AI-side Paths progress to check yet,
## same "single human-controlled side" scope every other per-player
## system in this project already has), and only once that path has
## actually been followed (GameState.human_path_state.has_followed).
##
## Callers pass whatever `player_id` they already have on hand (a unit/
## building's own field, or an attacker/target's) rather than this class
## reaching into the scene tree itself -- keeps every perk a pure
## function of "whose side is this" rather than needing scene-tree
## access, and lets the exact same check work whether the caller is an
## Entity, a Building, or ResourceHUD.

static func _human_has(path_id: String) -> bool:
	return GameState.human_path_state.has_followed(path_id)

## Chivalry: +15% melee damage. Applied in Unit._get_attack_damage --
## every attack in this project is melee (no ranged units/projectiles
## exist yet), so this is just "melee damage" full stop, not narrowed to
## a "Knight" unit type this project has no equivalent of.
static func melee_damage_multiplier(player_id: int) -> float:
	return 1.15 if player_id == GameState.human_player_id and _human_has("chivalry") else 1.0

## Cunning: -20% unit training time. Applied in Building._queue_interval_for.
static func training_time_multiplier(player_id: int) -> float:
	return 0.8 if player_id == GameState.human_player_id and _human_has("cunning") else 1.0

## Faith: passive 1%-of-max-HP/sec regen for units. Applied in
## Unit._process. Returns the fraction (0.0 if not following) rather
## than a bool, so the caller can multiply straight into a delta-scaled
## heal amount.
static func hp_regen_fraction_per_second(player_id: int) -> float:
	return 0.01 if player_id == GameState.human_player_id and _human_has("faith") else 0.0

## Wishes: -15% research TIME. The perk text says "cost", but Wild Rot
## (the only research this project has) has no resource cost at all,
## only UPGRADE_RESEARCH_TIME -- reduced time is the closest real
## equivalent rather than inventing a cost that doesn't otherwise exist.
## Applied in Building.get_research_progress's own timer accumulation
## (see start_research/_physics_process).
static func research_time_multiplier(player_id: int) -> float:
	return 0.85 if player_id == GameState.human_player_id and _human_has("wishes") else 1.0

## Magic: +10% vision range. Applied in Entity.vision_range reads --
## see Unit/Building's own get_effective_vision_range wrappers.
static func vision_range_multiplier(player_id: int) -> float:
	return 1.10 if player_id == GameState.human_player_id and _human_has("magic") else 1.0

## Order: +20% building HP. Applied once at construction-finish time
## (Building.advance_construction) rather than live every frame -- a
## building's own max_health is a stored field read directly in many
## places (health bar, tooltip, take_damage clamp), so baking the bonus
## in once when it's actually built is simpler and cheaper than a live
## multiplier at every read site. This means the bonus only applies to
## buildings that finish construction AFTER Order is followed, not
## retroactively to already-standing ones -- an accepted simplification
## for this first pass (see [[darknight-paths-system]] memory note).
static func building_health_multiplier(player_id: int) -> float:
	return 1.20 if player_id == GameState.human_player_id and _human_has("order") else 1.0

## Desire: +15% resource gather rate. Applied in Unit._update_gather_target's
## own GATHER_RATE*delta call.
static func gather_rate_multiplier(player_id: int) -> float:
	return 1.15 if player_id == GameState.human_player_id and _human_has("desire") else 1.0

## Betrayal: killing an enemy unit refunds 25% of "its own cost" to the
## KILLER's side. Only "peasant" has a real defined training cost
## anywhere in this project (Building.PEASANT_TRAIN_COST) -- every other
## trainable type has none yet -- so REFUND_BASE_COST is a flat
## placeholder stand-in used regardless of the victim's actual type,
## rather than this perk depending on real per-type cost data that
## doesn't exist. Applied in Entity._die() via apply_kill_refund.
const REFUND_BASE_COST: Dictionary = {"acorns": 40}
const REFUND_FRACTION: float = 0.25

## Refunds REFUND_FRACTION of REFUND_BASE_COST to `killer_player_id` if
## that's the human player and they follow Betrayal -- a no-op
## (including no resource_hud access at all) otherwise. Called from
## Entity._die() once an attacker reference is known.
static func apply_kill_refund(killer_player_id: int, resource_hud: ResourceHUD) -> void:
	if killer_player_id != GameState.human_player_id or not _human_has("betrayal") or resource_hud == null:
		return
	for resource_name in REFUND_BASE_COST:
		var refund_amount: int = int(REFUND_BASE_COST[resource_name] * REFUND_FRACTION)
		resource_hud.add_resource(killer_player_id, resource_name, refund_amount)

## Chaos: +25% attack speed (shorter cooldown) alongside -10% max HP --
## two multipliers for the one path, since the perk text is explicitly
## a tradeoff. Attack speed is a live multiplier (Unit._get_attack_cooldown);
## the HP penalty is baked in once at spawn (Entity._ready()), same
## "stored field, apply once" reasoning building_health_multiplier's own
## doc comment has.
static func attack_speed_multiplier(player_id: int) -> float:
	return 1.25 if player_id == GameState.human_player_id and _human_has("chaos") else 1.0

static func chaos_health_multiplier(player_id: int) -> float:
	return 0.9 if player_id == GameState.human_player_id and _human_has("chaos") else 1.0

## Purity: units are immune to the first hit of every fight. "Every
## fight" (not "ever") means the immunity has to refresh once a unit's
## been out of combat for a while -- see Unit.HAS_TAKEN_HIT_COOLDOWN and
## _has_purity_shield_up for the actual refresh logic; this just answers
## "is this player's Purity perk active at all."
static func has_purity(player_id: int) -> bool:
	return player_id == GameState.human_player_id and _human_has("purity")

## Corruption: enemy units gathering within CORRUPTION_RADIUS of any of
## this player's own units gather 20% slower. Checked spatially in
## World.gather() (see its own doc comment for the proximity scan) --
## this just answers "does `owner_player_id` have Corruption at all",
## letting the caller decide whether the GATHERING unit is actually near
## one of owner_player_id's units.
const CORRUPTION_RADIUS: float = 8.0
const CORRUPTION_SLOW_MULTIPLIER: float = 0.8
static func has_corruption(player_id: int) -> bool:
	return player_id == GameState.human_player_id and _human_has("corruption")

## Avalon: +30% to ALL resource income -- both what a peasant gathers
## (World.gather()) and any other add_resource call for this player,
## since ResourceHUD.add_resource is the one true entry point every
## resource gain already goes through.
static func resource_income_multiplier(player_id: int) -> float:
	return 1.30 if player_id == GameState.human_player_id and _human_has("avalon") else 1.0

## Death: a defeated enemy has a DEATH_DROP_CHANCE to instantly credit
## the KILLER's side DEATH_DROP_AMOUNT of DEATH_DROP_RESOURCE -- an
## instant credit rather than an actual world pickup (WorldItem is built
## for equipment drops, not a generic resource; simplest real
## implementation without building a whole new pickup type for this one
## perk). Called from Entity._die() once an attacker reference is known,
## same call site apply_kill_refund uses.
const DEATH_DROP_CHANCE: float = 0.4
const DEATH_DROP_RESOURCE: String = "acorns"
const DEATH_DROP_AMOUNT: int = 25
static func apply_death_drop(killer_player_id: int, resource_hud: ResourceHUD) -> void:
	if killer_player_id != GameState.human_player_id or not _human_has("death") or resource_hud == null:
		return
	if randf() < DEATH_DROP_CHANCE:
		resource_hud.add_resource(killer_player_id, DEATH_DROP_RESOURCE, DEATH_DROP_AMOUNT)

## Decay: enemy buildings within DECAY_RADIUS of any of this player's
## own buildings slowly lose HP over time. Checked periodically in
## Building._physics_process (see its own doc comment) -- this just
## answers "does `player_id` have Decay at all."
const DECAY_RADIUS: float = 10.0
const DECAY_DAMAGE_PER_SECOND: float = 2.0
static func has_decay(player_id: int) -> bool:
	return player_id == GameState.human_player_id and _human_has("decay")
