extends RefCounted
class_name ItemDefs
## Single source of truth for every equippable item type -- what its
## equipped-on-a-unit visual is (Unit.equip_weapon) and what its
## world-pickup scene is (WorldItem.spawn_pickup). Adding a new item means
## adding one entry here, not touching two separate dictionaries in two
## separate files that used to have to be kept in sync by hand.

## "slot" says which of Unit.BACKPACK_SLOTS an item fits into --
## "one_hand" fits either RIGHT_HAND or LEFT_HAND (whichever's free, see
## Unit.equip_item), "two_hand" always occupies both at once (a bow/
## crossbow needs both hands, so equipping one displaces whatever
## occupied either). "stats" is display-only data for ItemStatsPanel --
## nothing currently reads it for actual combat math (equipping stays
## visual-only, same as before this system existed).
## "damage"/"melee_reach" are the actual combat numbers (see
## Unit._get_attack_damage/_get_melee_reach) -- "stats" is the display
## copy shown in ItemStatsPanel, kept as its own dictionary rather than
## generated from these since not every stat line is combat-numeric (e.g.
## "Type").
const DEFS: Dictionary = {
	"sword": {
		"visual": preload("res://scenes/Sword.tscn"),
		"pickup": preload("res://scenes/SwordPickup.tscn"),
		"slot": "one_hand",
		"damage": 8.0,
		"melee_reach": 0.5,
		"hit_offsets": [0.0, 0.25, 0.5],
		"stats": {"Type": "One-Handed Weapon", "Damage": "8"},
	},
	"crossbow": {
		"visual": preload("res://scenes/Crossbow.tscn"),
		"pickup": preload("res://scenes/CrossbowPickup.tscn"),
		"slot": "two_hand",
		"damage": 14.0,
		"stats": {"Type": "Two-Handed Weapon", "Damage": "14"},
	},
}

static func get_visual_scene(item_type: String) -> PackedScene:
	return DEFS.get(item_type, {}).get("visual")

static func get_pickup_scene(item_type: String) -> PackedScene:
	return DEFS.get(item_type, {}).get("pickup")

## Which Unit.BACKPACK_SLOTS slot(s) this item occupies -- "one_hand",
## "two_hand", "armor", or "accessory". "" for an unrecognized item_type.
static func get_slot_kind(item_type: String) -> String:
	return DEFS.get(item_type, {}).get("slot", "")

## Display-only stat rows for ItemStatsPanel, as {label: value}. Empty for
## an unrecognized item_type or one with none defined.
static func get_stats(item_type: String) -> Dictionary:
	return DEFS.get(item_type, {}).get("stats", {})

## This weapon's actual attack damage -- -1.0 for an unrecognized
## item_type or one with none defined, so callers (see
## Unit._get_attack_damage) can tell "no weapon-specific damage" apart
## from a genuine 0.
static func get_damage(item_type: String) -> float:
	return DEFS.get(item_type, {}).get("damage", -1.0)

## Extra melee reach this weapon's length adds over an unarmed swing --
## 0.0 for an unrecognized item_type or one with none defined (e.g. a
## ranged weapon like the crossbow, which doesn't extend melee reach at
## all).
static func get_melee_reach_bonus(item_type: String) -> float:
	return DEFS.get(item_type, {}).get("melee_reach", 0.0)

## Sample points along the weapon's own length (local offsets from the
## hand, in the direction its visual scene extends -- see Sword.tscn's
## blade running from grip at Y=0 to tip at Y=0.9) that
## Entity._land_hit_if_in_reach checks a hit against, approximating a
## capsule strung along the blade rather than one point at the fist --
## closer to how a real weapon can land a hit anywhere along its edge, not
## only at the very tip. Empty for an unrecognized item_type or one with
## no offsets defined (e.g. an unequipped hand, or the crossbow, which has
## no melee swing at all) -- callers (see Unit._get_melee_hit_offsets) treat
## that as "fall back to the unarmed fist span" rather than "one point at
## the hand", since those are different things.
static func get_melee_hit_offsets(item_type: String) -> Array:
	return DEFS.get(item_type, {}).get("hit_offsets", [])
