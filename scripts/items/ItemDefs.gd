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
## occupied either). "hybrid_hand" is a one-hand item that grips
## two-handed by default (occupying both hand slots, like "two_hand")
## whenever the other hand is free, but yields to a one_hand/hybrid_hand
## item equipped alongside it -- picking either up next to it re-grips
## down to a single hand so both weapons fit, one per hand (see
## Unit.equip_item's "hybrid_hand" branch). "stats" is display-only data
## for ItemTooltipPanel --
## nothing currently reads it for actual combat math (equipping stays
## visual-only, same as before this system existed).
## "damage"/"melee_reach" are the actual combat numbers (see
## Unit._get_attack_damage/_get_melee_reach) -- "stats" is the display
## copy shown in ItemTooltipPanel, kept as its own dictionary rather than
## generated from these since not every stat line is combat-numeric.
## "name" is the tooltip's title -- the item's actual proper name (e.g.
## "Iron Longsword"), falling back to a bare capitalized item_type (see
## get_item_name) when there isn't one yet. "display_name" is the
## tooltip's subtitle -- bakes the hand-type distinction into a short
## descriptor ("Hybrid-Handed Sword": fits in either hand, unlike a
## "slot": "two_hand" item, which needs both at once) rather than a
## separate "Type" stat row.
const DEFS: Dictionary = {
	"sword": {
		"visual": preload("res://scenes/Sword.tscn"),
		"pickup": preload("res://scenes/SwordPickup.tscn"),
		"slot": "hybrid_hand",
		"name": "Iron Longsword",
		"display_name": "Hybrid-Handed Sword",
		"damage": 10.0,
		"melee_reach": 0.5,
		"hit_offsets": [0.0, 0.25, 0.5],
		"stats": {"Damage": "10"},
	},
	"steel_longsword": {
		"visual": preload("res://scenes/SteelSword.tscn"),
		"pickup": preload("res://scenes/SteelSwordPickup.tscn"),
		"slot": "hybrid_hand",
		"name": "Steel Longsword",
		"display_name": "Hybrid-Handed Sword",
		"damage": 12.0,
		"melee_reach": 0.5,
		"hit_offsets": [0.0, 0.25, 0.5],
		"stats": {"Damage": "12"},
	},
	"crossbow": {
		"visual": preload("res://scenes/Crossbow.tscn"),
		"pickup": preload("res://scenes/CrossbowPickup.tscn"),
		"slot": "two_hand",
		"display_name": "Two-Handed Crossbow",
		"damage": 14.0,
		"stats": {"Damage": "14"},
	},
	"iron_greatsword": {
		"visual": preload("res://scenes/IronGreatsword.tscn"),
		"pickup": preload("res://scenes/IronGreatswordPickup.tscn"),
		"slot": "two_hand",
		"name": "Iron Greatsword",
		"display_name": "Two-Handed Sword",
		"damage": 16.0,
		"melee_reach": 0.75,
		"hit_offsets": [0.0, 0.375, 0.75],
		"stats": {"Damage": "16"},
	},
}

static func get_visual_scene(item_type: String) -> PackedScene:
	return DEFS.get(item_type, {}).get("visual")

## This item's proper name for ItemTooltipPanel's title (e.g. "Iron
## Longsword") -- falls back to a bare item_type.capitalize() for an
## item that hasn't been given a proper name yet, or an unrecognized
## item_type.
static func get_item_name(item_type: String) -> String:
	return DEFS.get(item_type, {}).get("name", item_type.capitalize())

## Hand-type descriptor for ItemTooltipPanel's subtitle -- bakes in the
## one-/two-/hybrid-handed distinction (e.g. "Hybrid-Handed Sword") that
## used to be its own separate "Type" stat row, rather than a bare
## item_type.capitalize(). Falls back to that plain capitalized form
## for an unrecognized item_type.
static func get_display_name(item_type: String) -> String:
	return DEFS.get(item_type, {}).get("display_name", item_type.capitalize())

static func get_pickup_scene(item_type: String) -> PackedScene:
	return DEFS.get(item_type, {}).get("pickup")

## Which Unit.BACKPACK_SLOTS slot(s) this item occupies -- "one_hand",
## "two_hand", "hybrid_hand", "armor", or "accessory". "" for an
## unrecognized item_type.
static func get_slot_kind(item_type: String) -> String:
	return DEFS.get(item_type, {}).get("slot", "")

## Display-only stat rows for ItemTooltipPanel, as {label: value}. Empty for
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
