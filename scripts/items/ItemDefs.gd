extends RefCounted
class_name ItemDefs
## Single source of truth for every equippable item type -- what its
## equipped-on-a-unit visual is (Unit.equip_weapon) and what its
## world-pickup scene is (WorldItem.spawn_pickup). Adding a new item means
## adding one entry here, not touching two separate dictionaries in two
## separate files that used to have to be kept in sync by hand.

const DEFS: Dictionary = {
	"sword": {
		"visual": preload("res://scenes/Sword.tscn"),
		"pickup": preload("res://scenes/SwordPickup.tscn"),
	},
	"crossbow": {
		"visual": preload("res://scenes/Crossbow.tscn"),
		"pickup": preload("res://scenes/CrossbowPickup.tscn"),
	},
}

static func get_visual_scene(item_type: String) -> PackedScene:
	return DEFS.get(item_type, {}).get("visual")

static func get_pickup_scene(item_type: String) -> PackedScene:
	return DEFS.get(item_type, {}).get("pickup")
