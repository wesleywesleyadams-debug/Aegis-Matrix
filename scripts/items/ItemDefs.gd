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
const DEFS: Dictionary = {
	"sword": {
		"visual": preload("res://scenes/Sword.tscn"),
		"pickup": preload("res://scenes/SwordPickup.tscn"),
		"slot": "one_hand",
		"stats": {"Type": "One-Handed Weapon", "Damage": "8"},
	},
	"crossbow": {
		"visual": preload("res://scenes/Crossbow.tscn"),
		"pickup": preload("res://scenes/CrossbowPickup.tscn"),
		"slot": "two_hand",
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
