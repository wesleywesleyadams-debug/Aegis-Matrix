extends RefCounted
class_name EditorPalette
## Single source of truth for every placeable object type the map editor
## (scripts/MapEditorController.gd) offers, organized by category ("Unit",
## "Building", "World", "Item") -- the same "one dictionary, one accessor"
## shape ItemDefs/UnitDefs/BuildingDefs already use elsewhere in this
## project. RTSController.gd's own custom-map loader (see
## _load_custom_map) reads this same registry to resolve a saved entry's
## category+type_id back to a scene, so the palette and the loader can
## never drift out of sync about what a given category/type_id pair means.
##
## Units and buildings only have one real scene each per category entry
## today (ParentUnit.tscn for every unit type; a handful of dedicated
## building scenes) -- unlike ItemDefs, which already has its own
## scene-per-item_type table, UnitDefs/BuildingDefs only ever stored
## stat overrides, never scene references (see their own doc comments),
## so this is genuinely new plumbing, not a duplicate of something that
## already existed.

const UNIT_SCENE: PackedScene = preload("res://scenes/ParentUnit.tscn")
const BUILDING_SCENE: PackedScene = preload("res://scenes/ParentBuilding.tscn")
const HUT_SCENE: PackedScene = preload("res://scenes/Hut.tscn")
const CASTLE_SCENE: PackedScene = preload("res://scenes/Castle.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/Tower.tscn")
const TREE_SCENE: PackedScene = preload("res://scenes/Tree.tscn")
const OAK_TREE_SCENE: PackedScene = preload("res://scenes/OakTree.tscn")
const APPLE_TREE_SCENE: PackedScene = preload("res://scenes/AppleTree.tscn")
const CRYSTAL_CAVE_SCENE: PackedScene = preload("res://scenes/CrystalCave.tscn")
const MIST_FISSURE_SCENE: PackedScene = preload("res://scenes/MistFissure.tscn")

## Each entry: {"type_id", "display_name", "scene"} -- "scene" is always
## the base scene to instantiate; type_id is applied onto the instance's
## own `unit_type_id` afterward when the scene's own default doesn't
## already match (see instantiate() below), the same way Main.tscn's
## hand-placed Wall/Tower instances do it today.
const UNITS: Array[Dictionary] = [
	{"type_id": "peasant", "display_name": "Peasant", "scene": UNIT_SCENE},
]
const BUILDINGS: Array[Dictionary] = [
	{"type_id": "building", "display_name": "Generic Building", "scene": BUILDING_SCENE},
	{"type_id": "wall", "display_name": "Wall", "scene": BUILDING_SCENE},
	{"type_id": "hut", "display_name": "Hut", "scene": HUT_SCENE},
	{"type_id": "tower", "display_name": "Tower", "scene": TOWER_SCENE},
	{"type_id": "castle", "display_name": "Castle", "scene": CASTLE_SCENE},
]
const WORLD: Array[Dictionary] = [
	{"type_id": "tree", "display_name": "Tree", "scene": TREE_SCENE},
	{"type_id": "oak_tree", "display_name": "Oak Tree (Acorns)", "scene": OAK_TREE_SCENE},
	{"type_id": "apple_tree", "display_name": "Apple Tree (Apples)", "scene": APPLE_TREE_SCENE},
	{"type_id": "crystal_cave", "display_name": "Blue Crystal (Crystal)", "scene": CRYSTAL_CAVE_SCENE},
	{"type_id": "mist_fissure", "display_name": "Red Fissure (Mist)", "scene": MIST_FISSURE_SCENE},
]

## Category name -> that category's own list (see UNITS/BUILDINGS/WORLD
## above). "Item" is deliberately built dynamically from ItemDefs.DEFS's
## own keys (see items() below) rather than duplicated here -- ItemDefs
## already IS the single source of truth for every item type, so this
## reads it live instead of needing to be kept in sync by hand.
static func categories() -> Dictionary:
	return {
		"Unit": UNITS,
		"Building": BUILDINGS,
		"World": WORLD,
		"Item": items(),
	}

## Built fresh each call (cheap -- a handful of entries) from ItemDefs'
## own DEFS keys, so a new item type added there shows up in the palette
## automatically with no changes needed here.
static func items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item_type in ItemDefs.DEFS.keys():
		result.append({
			"type_id": item_type,
			"display_name": ItemDefs.get_item_name(item_type),
			"scene": ItemDefs.get_pickup_scene(item_type),
		})
	return result

## Finds the {"type_id", "display_name", "scene"} entry for `category`
## ("Unit"/"Building"/"World"/"Item") + `type_id`, or an empty Dictionary
## if no such entry exists (an unrecognized/stale category+type_id pair,
## e.g. from a hand-edited or out-of-date save file).
static func find_entry(category: String, type_id: String) -> Dictionary:
	for entry in categories().get(category, []):
		if entry["type_id"] == type_id:
			return entry
	return {}

## Instantiates `category`+`type_id`'s scene and, if the instance's own
## unit_type_id doesn't already match (e.g. "wall"/"building" both
## sharing ParentBuilding.tscn, which defaults to "building"), sets it --
## the same override Main.tscn's own hand-placed Wall/Tower instances
## apply directly in the scene file. Returns null for an unrecognized
## category+type_id, or for the "Item" category (item pickups are
## spawned via WorldItem.spawn_pickup/spawn_dropped instead -- see
## MapEditorController -- since ItemDefs' pickup scenes are Area3D
## pickups with their own animation/positioning behavior, not a plain
## instance-and-place like every other category).
static func instantiate(category: String, type_id: String) -> Node3D:
	if category == "Item":
		return null
	var entry := find_entry(category, type_id)
	if entry.is_empty() or entry["scene"] == null:
		return null
	var instance: Node3D = entry["scene"].instantiate()
	if "unit_type_id" in instance and instance.unit_type_id != type_id:
		instance.unit_type_id = type_id
	return instance
