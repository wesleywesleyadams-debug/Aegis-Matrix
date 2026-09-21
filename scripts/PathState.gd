extends RefCounted
class_name PathState
## Tracks one player's progress through the Paths system -- which paths
## they've permanently followed (perks stack, never lost), which path
## (if any) is currently being researched, and which paths are
## currently selectable to START researching (see get_selectable_paths),
## per the rule worked out with the user directly from their reference
## diagram's two example playthroughs:
##
## - A path becomes selectable only via ADJACENCY to whichever path was
##   most recently followed -- not a fixed prerequisite graph. Following
##   a NEW path REPLACES the whole selectable set with that new path's
##   own neighbors (already-followed paths never reappear, since they're
##   filtered out); it does not union with what was selectable before.
## - Adjacency has two halves:
##   - Same-tier: immediate left/right neighbor among the tier's REAL
##     paths only (see PathDefs.get_slot_in_tier's own doc comment on
##     why tier 0's empty middle slot doesn't count as a real neighbor
##     gap -- chivalry and cunning are each other's only tier-0
##     neighbor, full stop, regardless of the wider row they're drawn in).
##   - Cross-tier (down one tier only): two paths are adjacent if their
##     normalized horizontal position within their own tier's slot count
##     overlaps or touches at all -- tiers have different slot counts
##     (2/3/4/5), so this is a proportional-overlap check, not an index
##     match. See _tiers_are_adjacent.
## - Followed paths are capped at PathDefs.MAX_FOLLOWED_PATHS for the
##   WHOLE game -- a lifetime limit, not "4 active at once". Once spent,
##   there is no way to follow a 5th path even if one becomes selectable.
## - Starting to research a path spends its PathDefs.get_cost immediately
##   (see PathTreeModal._on_node_clicked, which does the actual spend
##   before calling start_researching) but takes PathDefs.get_tier's own
##   TIER_RESEARCH_TIMES to actually finish -- see start_researching/
##   advance_research. Only one path can be mid-research at a time (there's
##   only one "next pick" slot to spend on anyway); get_selectable_paths
##   returns empty while one is in progress, same "nothing else to choose
##   right now" reasoning a building's own single-slot research
##   (Building.researching_upgrade) has.
##
## This class holds no player_id/scene-tree state of its own -- callers
## (one instance per player, e.g. GameState.human_path_state) own the
## instance and decide who it belongs to. Something in the scene tree
## (PathsPanel._process) has to actually call advance_research(delta)
## every frame -- this class never ticks itself.

## Path ids this player has permanently followed, in the order they
## finished researching -- also what fills the 4 on-screen slots left-
## to-right/top-to-bottom (see PathsPanel).
var followed_paths: Array[String] = []

## "" while nothing is being researched -- see start_researching/
## advance_research/cancel_research.
var researching_path: String = ""
var _research_timer: float = 0.0

func can_follow_more() -> bool:
	return followed_paths.size() < PathDefs.MAX_FOLLOWED_PATHS

func has_followed(path_id: String) -> bool:
	return path_id in followed_paths

func is_researching() -> bool:
	return not researching_path.is_empty()

## Every path this player could choose to START researching right now --
## empty while can_follow_more() is false (nothing left to spend a pick
## on) OR a research is already in progress (only one at a time). Before
## any path has ever been followed, this is every tier-0 path (chivalry,
## cunning) -- there's no "most recently followed path" yet to compute
## adjacency from.
func get_selectable_paths() -> Array[String]:
	if not can_follow_more() or is_researching():
		return []
	if followed_paths.is_empty():
		var starters: Array[String] = []
		for path_id in PathDefs.all_path_ids():
			if PathDefs.get_tier(path_id) == 0:
				starters.append(path_id)
		return starters
	var frontier: String = followed_paths[-1]
	var selectable: Array[String] = []
	for path_id in PathDefs.all_path_ids():
		if has_followed(path_id):
			continue
		if _are_adjacent(frontier, path_id):
			selectable.append(path_id)
	return selectable

## Starts researching `path_id` if it's actually selectable right now
## (see get_selectable_paths) -- false (no change) otherwise, same
## "refuse silently, caller doesn't need to react" shape other order-
## issuing methods in this project use (e.g. Building.add_garrisoned_unit).
## Does NOT spend any resources itself -- see PathTreeModal._on_node_clicked,
## which spends PathDefs.get_cost before ever calling this, so a failed
## spend never leaves this in a half-started state.
func start_researching(path_id: String) -> bool:
	if path_id not in get_selectable_paths():
		return false
	researching_path = path_id
	_research_timer = 0.0
	return true

## Advances the current research by `delta` seconds, finishing (moving
## researching_path into followed_paths) once PathDefs.get_research_time
## is reached. A no-op if nothing is researching -- callers (PathsPanel._process)
## don't need to guard the call themselves.
func advance_research(delta: float) -> void:
	if not is_researching():
		return
	_research_timer += delta
	if _research_timer >= PathDefs.get_research_time(researching_path):
		followed_paths.append(researching_path)
		researching_path = ""
		_research_timer = 0.0

## Fraction (0..1) of the way through the current research -- 0.0 while
## nothing is researching. Mirrors Building.get_research_progress's own
## shape.
func get_research_progress() -> float:
	if not is_researching():
		return 0.0
	return clampf(_research_timer / PathDefs.get_research_time(researching_path), 0.0, 1.0)

## Seconds remaining until the current research finishes -- 0.0 while
## nothing is researching.
func get_research_seconds_remaining() -> float:
	if not is_researching():
		return 0.0
	return maxf(PathDefs.get_research_time(researching_path) - _research_timer, 0.0)

## True if `a` and `b` are adjacent per this system's own rule (see this
## class's doc comment) -- same tier and immediate neighbors, or
## exactly ONE TIER DEEPER with overlapping/touching horizontal
## position. Deliberately one-directional for the cross-tier case --
## see _tiers_are_adjacent's own doc comment for the exact bug this
## direction restriction fixes.
func _are_adjacent(a: String, b: String) -> bool:
	var tier_a := PathDefs.get_tier(a)
	var tier_b := PathDefs.get_tier(b)
	if tier_a == tier_b:
		return absi(PathDefs.get_slot_in_tier(a) - PathDefs.get_slot_in_tier(b)) == 1
	if tier_b != tier_a + 1:
		return false
	return _tiers_are_adjacent(a, tier_a, b, tier_b)

## Proportional horizontal-overlap check between a path in `tier_a` and
## one in the immediately adjacent `tier_b` -- normalizes each path's
## slot index into a 0..1 fractional range based on its OWN tier's slot
## count (2/3/4/5 -- see PathDefs.get_tier_slot_count), then checks those
## two ranges touch or overlap. Verified against both of the user's own
## example playthroughs before this was written; the one-directional
## restriction in _are_adjacent above exists because this overlap check
## alone is symmetric and would otherwise keep e.g. cunning (tier 0)
## reachable from wishes (tier 1) forever, contradicting the user's own
## example where following wishes locks cunning back out.
func _tiers_are_adjacent(a: String, tier_a: int, b: String, tier_b: int) -> bool:
	var count_a := PathDefs.get_tier_slot_count(tier_a)
	var count_b := PathDefs.get_tier_slot_count(tier_b)
	var slot_a := PathDefs.get_slot_in_tier(a)
	var slot_b := PathDefs.get_slot_in_tier(b)
	var start_a: float = float(slot_a) / count_a
	var end_a: float = float(slot_a + 1) / count_a
	var start_b: float = float(slot_b) / count_b
	var end_b: float = float(slot_b + 1) / count_b
	return end_a >= start_b and start_a <= end_b
