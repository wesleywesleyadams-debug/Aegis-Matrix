class_name MatchStats
extends Node
## Records how a match went for the post-game Stats screen (and the AI
## balance harness, SimRunner): a snapshot of both sides every SAMPLE game
## seconds, plus running counters (ships built / lost, planets won / lost,
## starbases lost) fed by Game, Starbase and Ship events.

const SAMPLE := 30.0

var samples: Array = []
## pid -> {counter name -> int}
var counters := {}   # pid -> {stat: n}, filled as players act (see count)
var _next_sample: float = 0.0
var _stopped := false

func _process(_delta: float) -> void:
	if _stopped:
		return
	var t := Game.now()
	if t >= _next_sample:
		samples.append(sample(t))
		_next_sample += SAMPLE

func count(pid: int, what: String, n: int = 1) -> void:
	if not counters.has(pid):
		counters[pid] = {}
	counters[pid][what] = counters[pid].get(what, 0) + n

func get_count(pid: int, what: String) -> int:
	return counters.get(pid, {}).get(what, 0)

## Takes the final snapshot and stops sampling (the match is over).
func finish() -> void:
	if _stopped:
		return
	_stopped = true
	samples.append(sample(Game.now()))

## What one resource unit is worth to the score, banked. Anything owned
## counts for OWNED_WORTH times what it cost: having a thing is always worth
## more than having the resources for it (75 minerals = 7.5, a corvette = 15).
const BANKED_WORTH := 0.1
const OWNED_WORTH := 2.0
## Score for having explored the entire system.
const EXPLORE_WORTH := 100.0

## The running score shown above the minimap: a snapshot of what a side has
## right now, so it falls as well as rises.
##   banked - resources in the bank, x BANKED_WORTH
##   owned  - everything bought, at its cost x BANKED_WORTH x OWNED_WORTH:
##            ships, finished starbases, Mining Stations and Weapons Depots,
##            every building on every world, and every technology researched
##   worlds - 20 per world held, plus population /100 (people are not bought)
##   explored - EXPLORE_WORTH for the whole map charted, pro rata
func score(pid: int) -> int:
	var g := Game.instance
	var banked := 0.0
	for k in g.resources.get(pid, {}):
		banked += maxf(float(g.resources[pid][k]), 0.0)
	var owned := 0.0
	for s in g.get_tree().get_nodes_in_group("ships"):
		if s.owner_id == pid and s.is_alive():
			owned += _cost(s.def["cost"])
	for grp in [["starbases", Defs.STARBASE], ["mining_stations", Defs.MINING_STATION], ["depots", Defs.WEAPONS_DEPOT]]:
		for c in g.get_tree().get_nodes_in_group(grp[0]):
			if c.owner_id == pid and c.is_alive() and not c.under_construction:
				owned += _cost(grp[1]["cost"])
	var worlds := 0
	var pop := 0.0
	for p in g.get_tree().get_nodes_in_group("planets"):
		if p.owner_id == pid:
			worlds += 1
			pop += p.pop
			for b in p.buildings:
				if b != "":
					owned += _cost(Defs.BUILDINGS[b]["cost"])
	for t in g.researched.get(pid, {}):
		if Defs.TECHS.has(t):
			owned += _cost(Defs.TECHS[t]["cost"])
	# Each side's own fog of war, so it is what that side has actually seen.
	var v: Vision = g.visions.get(pid)
	var explored: float = v.explored_fraction() if v != null else 0.0
	return int(banked * BANKED_WORTH + owned * BANKED_WORTH * OWNED_WORTH + worlds * 20 + pop / 100.0 + explored * EXPLORE_WORTH)

## Every resource in a cost, summed.
static func _cost(c: Dictionary) -> float:
	var n := 0.0
	for r in c:
		n += float(c[r])
	return n

## Highest value of a sampled field for one side.
func peak(pid: int, field: String) -> int:
	var best := 0
	for s in samples:
		best = maxi(best, int(s[str(pid)].get(field, 0)))
	return best

## One snapshot per side: stockpiles, pop, worlds, fleet, starbases, tech.
static func sample(t: float) -> Dictionary:
	var g := Game.instance
	var out := {"t": int(t)}
	for pid in g.players:
		var pop := 0.0
		var worlds := 0
		for p in g.get_tree().get_nodes_in_group("planets"):
			if p.owner_id == pid:
				pop += p.pop
				worlds += 1
		var war := 0
		var miners := 0
		var power := 0.0
		for s in g.get_tree().get_nodes_in_group("ships"):
			if s.owner_id != pid or not s.is_alive():
				continue
			if s.def["role"] == "warship":
				war += 1
				power += s.max_hp + s.max_armor + s.max_shield
			elif s.is_miner():
				miners += 1
		var bases := 0
		for sb in g.get_tree().get_nodes_in_group("starbases"):
			if sb.owner_id == pid and sb.is_alive() and not sb.under_construction:
				bases += 1
		var r: Dictionary = g.resources[pid]
		out[str(pid)] = {"food": int(r["food"]), "minerals": int(r["minerals"]), "energy": int(r["energy"]), "spice": int(r["spice"]),
			"pop": int(pop), "worlds": worlds, "warships": war, "power": int(power), "miners": miners, "starbases": bases,
			"techs": g.researched[pid].size(), "score": g.stats.score(pid) if g.stats else 0, "mode": str(g.ai._state.get(pid, {}).get("mode", ""))}
	return out
