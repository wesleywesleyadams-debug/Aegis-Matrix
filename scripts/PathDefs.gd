extends RefCounted
class_name PathDefs
## Single source of truth for every Path of Chivalry/Cunning/etc's own
## static data -- same "one dictionary, one static accessor per stat"
## shape ItemDefs.gd/UnitDefs.gd/BuildingDefs.gd already use elsewhere in
## this project.
##
## The Paths system replaces the old placeholder "Age" concept entirely
## (see ResourceHUD's own age icon/label, now removed): instead of a
## fixed age ladder, a player follows up to MAX_FOLLOWED_PATHS paths
## total over the whole match (a lifetime cap, not "4 active at once" --
## once spent, a pick is gone for good), each permanently granting its
## own perk (perks stack, never lost even once a path's own unlock
## window has closed). See PathState.gd for the actual per-player
## followed-paths/unlock tracking that reads this table; this file is
## pure data.
##
## "tier" groups paths into the 4 rows shown in this system's own
## reference diagram (purple/green/blue/red) -- purely a display/
## adjacency-math grouping (see PathState.get_unlocked_paths), not a
## gameplay gate on its own. "perk_description" is a placeholder, not
## yet wired to any real stat multiplier -- UI-first per this feature's
## own build order (the pop-out panel needs real text to show before the
## numbers behind it matter).
const MAX_FOLLOWED_PATHS: int = 4

## One entry per tier -- purple, green, blue, red, in that order (tier
## index 0-3) -- matching this system's own reference diagram exactly.
const TIER_COLORS: Array[Color] = [
	Color(0.55, 0.25, 0.55),
	Color(0.25, 0.55, 0.25),
	Color(0.2, 0.45, 0.75),
	Color(0.75, 0.2, 0.2),
]

## What following ANY path in a given tier costs -- one cost per tier
## rather than per-path (every path in tainer 0 costs the same, etc.),
## same "flat placeholder, real balance later" status BuildingDefs'
## own 100-acorns placeholder has. Leans on the same rarity split
## BuildingDefs.get_cost's own doc comment describes (Acorns/Apples
## common, Crystal/Mist rarer) so a deeper tier naturally costs more AND
## needs a rarer resource, not just a bigger number of the same one.
const TIER_COSTS: Array[Dictionary] = [
	{"acorns": 100},
	{"acorns": 150, "apples": 50},
	{"apples": 150, "crystal": 50},
	{"crystal": 150, "mist": 100},
]

## How long following a path in a given tier takes to actually finish
## (see PathState.start_researching/advance_research) -- scales with
## tier same "deeper = slower" reasoning BuildingDefs.get_build_time's
## own per-type values have.
const TIER_RESEARCH_TIMES: Array[float] = [60.0, 120.0, 180.0, 240.0]

## Tier 0 (2 slots), tier 1 (3 slots), tier 2 (4 slots), tier 3 (5 slots)
## -- this exact slot-count-per-tier is also what PathState's adjacency
## math keys off of (see its own doc comment), not just display.
const DEFS: Dictionary = {
	"chivalry": {"tier": 0, "display_name": "Path of Chivalry", "abbr": "Ch", "perk_description": "+15% melee damage for Knights"},
	"cunning": {"tier": 0, "display_name": "Path of Cunning", "abbr": "Cn", "perk_description": "-20% unit training time"},
	"faith": {"tier": 1, "display_name": "Path of Faith", "abbr": "Fa", "perk_description": "Units passively regenerate 1% HP/sec"},
	"wishes": {"tier": 1, "display_name": "Path of Wishes", "abbr": "Wi", "perk_description": "-15% research/upgrade cost"},
	"magic": {"tier": 1, "display_name": "Path of Magic", "abbr": "Mg", "perk_description": "+10% vision range for all units"},
	"order": {"tier": 2, "display_name": "Path of Order", "abbr": "Or", "perk_description": "+20% building HP"},
	"desire": {"tier": 2, "display_name": "Path of Desire", "abbr": "De", "perk_description": "+15% resource gather rate"},
	"betrayal": {"tier": 2, "display_name": "Path of Betrayal", "abbr": "Bt", "perk_description": "Killing an enemy unit refunds 25% of its cost"},
	"chaos": {"tier": 2, "display_name": "Path of Chaos", "abbr": "Cx", "perk_description": "+25% attack speed, -10% max HP"},
	"purity": {"tier": 3, "display_name": "Path of Purity", "abbr": "Pu", "perk_description": "Units are immune to the first hit of every fight"},
	"corruption": {"tier": 3, "display_name": "Path of Corruption", "abbr": "Co", "perk_description": "Enemy units near your units gather 20% slower"},
	"avalon": {"tier": 3, "display_name": "Path of Avalon", "abbr": "Av", "perk_description": "+30% to all resource income"},
	"death": {"tier": 3, "display_name": "Path of Death", "abbr": "Dt", "perk_description": "Defeated enemies have a chance to drop bonus resources"},
	"decay": {"tier": 3, "display_name": "Path of Decay", "abbr": "Dc", "perk_description": "Enemy buildings within range slowly lose HP over time"},
}

## Every path id in this table, in DEFS' own declaration order -- callers
## that need to iterate every path (PathState's adjacency computation,
## the palette that would eventually build a Castle "choose a path" UI)
## use this rather than DEFS.keys() directly, so the order is explicit
## and documented in one place.
static func all_path_ids() -> Array[String]:
	var ids: Array[String] = []
	for path_id in DEFS:
		ids.append(path_id)
	return ids

## -1 (never a real tier) for an unrecognized path id -- callers should
## treat that as "this isn't a real path," not silently default to tier 0.
static func get_tier(path_id: String) -> int:
	return DEFS.get(path_id, {}).get("tier", -1)

## The path's own id, capitalized, as a last-resort fallback for an
## unrecognized path id -- callers should not normally hit this, but it
## reads better than a blank label if they do.
static func get_display_name(path_id: String) -> String:
	return DEFS.get(path_id, {}).get("display_name", path_id.capitalize())

static func get_perk_description(path_id: String) -> String:
	return DEFS.get(path_id, {}).get("perk_description", "")

## Explicit 2-letter abbreviation, not derived from display_name -- a
## first-letter-only derivation collides badly (Death and Decay -- both
## "D" -- sit in the SAME tier row right next to each other in
## PathTreeModal, unreadable at a glance). Falls back to the first 2
## letters of the id for an unrecognized path_id, same "last resort,
## should not normally hit this" reasoning get_display_name's fallback has.
static func get_abbr(path_id: String) -> String:
	return DEFS.get(path_id, {}).get("abbr", path_id.left(2).capitalize())

## White for an unrecognized path id/tier -- see TIER_COLORS' own doc
## comment for what a real tier resolves to.
static func get_color(path_id: String) -> Color:
	var tier := get_tier(path_id)
	if tier < 0 or tier >= TIER_COLORS.size():
		return Color.WHITE
	return TIER_COLORS[tier]

## {} (free) for an unrecognized path id -- see TIER_COSTS' own doc
## comment; callers (PathState.follow_path) treat an empty dict as
## "nothing to spend", same convention BuildingDefs.get_cost's own
## fallback has.
static func get_cost(path_id: String) -> Dictionary:
	var tier := get_tier(path_id)
	if tier < 0 or tier >= TIER_COSTS.size():
		return {}
	return TIER_COSTS[tier]

## TIER_RESEARCH_TIMES[3] (the slowest tier) for an unrecognized path id
## -- a deliberately conservative fallback, same "never silently free/
## instant" reasoning get_cost's own {} fallback avoids the opposite way.
static func get_research_time(path_id: String) -> float:
	var tier := get_tier(path_id)
	if tier < 0 or tier >= TIER_RESEARCH_TIMES.size():
		return TIER_RESEARCH_TIMES[-1]
	return TIER_RESEARCH_TIMES[tier]

## How many real path slots exist in `tier` (0-3) -- 2/3/4/5 respectively,
## matching this system's own reference diagram. Used by PathState's
## adjacency math (both the same-tier neighbor chain and the cross-tier
## proportional-overlap check) rather than hardcoding those counts twice.
static func get_tier_slot_count(tier: int) -> int:
	var count := 0
	for path_id in DEFS:
		if DEFS[path_id]["tier"] == tier:
			count += 1
	return count

## `path_id`'s left-to-right position (0-based) among only the real paths
## in its own tier -- e.g. chivalry is slot 0 of tier 0, cunning is slot
## 1, even though they're drawn at the far left/right of a visually
## wider row (see PathState's own doc comment on why the empty middle
## slot in tier 0's diagram isn't a real position for this purpose).
## Order matches DEFS' own declaration order, which is deliberately
## written left-to-right per tier to match the reference diagram.
static func get_slot_in_tier(path_id: String) -> int:
	var tier := get_tier(path_id)
	var index := 0
	for candidate_id in DEFS:
		if DEFS[candidate_id]["tier"] != tier:
			continue
		if candidate_id == path_id:
			return index
		index += 1
	return -1
