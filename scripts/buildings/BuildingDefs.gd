extends RefCounted
class_name BuildingDefs
## Single source of truth for every building type's base stats -- the
## same "one dictionary, one static accessor per stat" shape ItemDefs.gd
## (equippable items) and UnitDefs.gd (units) already use.
##
## IMPORTANT: every entry below is deliberately written to reproduce
## today's existing per-.tscn values EXACTLY (see Entity._apply_type_defs,
## called from _ready()) -- introducing this lookup causes zero behavior
## change on its own. Doesn't cover trains_unit_type/train_interval --
## those are already genuinely per-instance via each building's own
## .tscn export (see Castle.tscn), not a hardcoded-per-type default that
## needed migrating here.
## "footprint_tiles" is how wide (and deep -- every building here is a
## square footprint) the building is in BuildPlacementController/
## EditorPlacementController's own BUILD_GRID_SIZE (2.6) cells --
## everything is 1 tile except Castle.tscn, whose own Transform3D scales
## its base ParentBuilding footprint 5x (see Main.tscn/EditorPalette).
## Both placement controllers snap a building's center so that a
## footprint_tiles-wide box centered there always lands exactly on grid
## lines (see snap_to_grid's own doc comment in either controller) --
## this is the single source of truth for the tile width that math needs,
## so the map editor and the real in-match "B" build key can never
## disagree about how big a given building type actually is on the grid.
## "cost" is what actually spends a player's resources (see
## ResourceHUD.spend_resources/BuildPlacementController.confirm_placement)
## -- resource_name -> amount, drawing on this game's 4x economy
## (Acorns, Apples, Crystal, Mist -- see ResourceHUD; Grace is gone
## entirely). Explicit, locked-in costs: dwellings (Hut) are cheap and
## acorns-only; Castle is the one big crystal sink; every other building
## is a flat 100-acorns placeholder until real per-type costs are
## designed.
## "garrison_capacity" is how many units Building.add_garrisoned_unit will
## let in at once (see Unit.garrison_in/seek_garrison) -- roughly scaled
## to each type's own footprint_tiles, same "bigger building, more room"
## reasoning real RTS garrison caps use.
## "build_time" is how many seconds a single constructing peasant (see
## Unit.construct_building/Building.advance_construction) takes to finish
## this building from a freshly placed foundation -- placeholder values,
## roughly scaled to footprint/max_health like everything else here.
## "display_name" is the single source of truth Entity.get_tooltip_title
## falls back to for any Building whose own node name isn't a deliberately
## hand-picked flavor name (see get_display_name) -- a building's node
## name in the scene tree is never meaningful the way a hand-placed
## roster Unit's is (there's no "flavor" to a second Hut, only an
## arbitrary "Hut2"/"Hut3" collision-resolved suffix, or worse, an
## anonymous "@CharacterBody3D@" if force_readable_name was ever missed
## at some add_child() call site), so display purposes should never
## depend on it at all.
const DEFS: Dictionary = {
	"building": {"display_name": "Building", "max_health": 300.0, "footprint_tiles": 1.0, "cost": {"acorns": 100}, "garrison_capacity": 3, "build_time": 20.0}, # ParentBuilding.tscn's own base default.
	"hut": {"display_name": "Hut", "max_health": 300.0, "footprint_tiles": 1.0, "cost": {"acorns": 25}, "garrison_capacity": 3, "build_time": 20.0}, # Hut.tscn never overrides health -- inherits the base. Dwelling: cheap, acorns-only.
	"wall": {"display_name": "Wall", "max_health": 300.0, "footprint_tiles": 1.0, "cost": {"acorns": 100}, "garrison_capacity": 0, "build_time": 15.0}, # Main.tscn's Wall node -- no interior, can't garrison anything.
	"tower": {"display_name": "Tower", "max_health": 300.0, "footprint_tiles": 1.0, "cost": {"acorns": 100}, "garrison_capacity": 5, "build_time": 25.0}, # Tower.tscn, same health -- no override.
	"castle": {"display_name": "Castle", "max_health": 600.0, "footprint_tiles": 5.0, "cost": {"crystal": 700}, "garrison_capacity": 15, "build_time": 60.0}, # Castle.tscn's own explicit override + its 5x scale.
}

## "" (no entry) for an unrecognized unit_type_id -- callers (see
## Entity.get_tooltip_title) treat that as "fall back to the node-name
## derivation instead," the same "no opinion, caller decides" reasoning
## get_max_health's -1.0 sentinel has.
static func get_display_name(unit_type_id: String) -> String:
	return DEFS.get(unit_type_id, {}).get("display_name", "")

## -1.0 sentinel means "no entry/no such stat for this unit_type_id" --
## callers (see Entity._apply_type_defs) treat that as "leave whatever
## @export default or .tscn override this Entity already has alone."
static func get_max_health(unit_type_id: String) -> float:
	return DEFS.get(unit_type_id, {}).get("max_health", -1.0)

## 1.0 (the common case) for an unrecognized unit_type_id, rather than a
## sentinel like get_max_health's -1.0 -- every caller of this one always
## wants a real, usable tile width to snap/validate against, never a "no
## opinion, leave it alone" case the way max_health has.
static func get_footprint_tiles(unit_type_id: String) -> float:
	return DEFS.get(unit_type_id, {}).get("footprint_tiles", 1.0)

## {} (free) for an unrecognized unit_type_id -- same "sensible default
## for a real, usable value" reasoning as get_footprint_tiles. Callers
## (ResourceHUD.spend_resources) iterate this dict's own keys, so an
## empty dict is a correct, zero-cost "nothing to spend" rather than a
## sentinel needing a special case.
static func get_cost(unit_type_id: String) -> Dictionary:
	return DEFS.get(unit_type_id, {}).get("cost", {})

## 0 (no room) for an unrecognized unit_type_id -- same "sensible default"
## reasoning as get_footprint_tiles/get_cost.
static func get_garrison_capacity(unit_type_id: String) -> int:
	return DEFS.get(unit_type_id, {}).get("garrison_capacity", 0)

## 20.0 (the common case) for an unrecognized unit_type_id -- same
## "sensible default for a real, usable number" reasoning as
## get_footprint_tiles.
static func get_build_time(unit_type_id: String) -> float:
	return DEFS.get(unit_type_id, {}).get("build_time", 20.0)
