extends RefCounted
class_name UnitDefs
## Single source of truth for every unit type's base combat/movement
## stats -- the same "one dictionary, one static accessor per stat" shape
## ItemDefs.gd already uses for equippable items. Adding a new unit type
## means adding one entry here, not touching several different constants
## spread across Entity.gd/Unit.gd.
##
## IMPORTANT: every entry below is deliberately written to reproduce
## today's existing shared defaults EXACTLY (see Entity.gd's own
## max_health/attack_damage/attack_cooldown/attack_range/vision_range
## @export defaults, and Unit.gd's former MAX_SPEED const) -- introducing
## this lookup (see Entity._apply_type_defs, called from _ready()) causes
## zero behavior change on its own. Every unit currently in the game
## (ParentUnit and every roster copy in Main.tscn -- Human, Darkling, Elf,
## etc.) is already mechanically identical today: they all inherit
## unit_type_id = "peasant" from ParentUnit.tscn and never override it, so
## their distinct node names are cosmetic only, not a real type
## distinction yet. Actually giving them different stats is a deliberate
## future step, not something this dictionary should introduce quietly.
const DEFS: Dictionary = {
	"peasant": {
		"max_health": 100.0,
		"attack_damage": 5.0,
		"attack_cooldown": 2.0,
		"attack_range": 1.0,
		"vision_range": 10.4,
		"max_speed": 2.25,
	},
}

## -1.0 sentinel means "no entry/no such stat for this unit_type_id" --
## callers (see Entity._apply_type_defs) treat that as "leave whatever
## @export default or .tscn override this Entity already has alone."
static func get_max_health(unit_type_id: String) -> float:
	return DEFS.get(unit_type_id, {}).get("max_health", -1.0)

static func get_attack_damage(unit_type_id: String) -> float:
	return DEFS.get(unit_type_id, {}).get("attack_damage", -1.0)

static func get_attack_cooldown(unit_type_id: String) -> float:
	return DEFS.get(unit_type_id, {}).get("attack_cooldown", -1.0)

static func get_attack_range(unit_type_id: String) -> float:
	return DEFS.get(unit_type_id, {}).get("attack_range", -1.0)

static func get_vision_range(unit_type_id: String) -> float:
	return DEFS.get(unit_type_id, {}).get("vision_range", -1.0)

## Same -1.0-means-"no override" convention as the other accessors here,
## even though Unit.gd's own max_speed is a plain var default rather than
## an @export -- kept consistent for callers.
static func get_max_speed(unit_type_id: String) -> float:
	return DEFS.get(unit_type_id, {}).get("max_speed", -1.0)
