class_name MatchStats
extends Node
## Records how a match went for the post-game Stats screen (and the AI
## balance harness, SimRunner): a snapshot of both sides every SAMPLE game
## seconds, plus running counters (ships built / lost, planets won / lost,
## starbases lost) fed by Game, Starbase and Ship events.

const SAMPLE := 30.0

var samples: Array = []
## pid -> {counter name -> int}
var counters := {1: {}, 2: {}}
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

## Resources a side has gathered over the match (not spent), for the score.
var gathered := {1: 0.0, 2: 0.0}

## The running score shown above the minimap. Four parts, each something a
## side has built up, so it rises with good play and only the society part
## can fall back:
##   economy  - every resource gathered, /10
##   military - the build cost of enemy ships destroyed, /5
##   research - 25 per technology
##   society  - 20 per world held, plus population /100
func score(pid: int) -> int:
	var g := Game.instance
	var worlds := 0
	var pop := 0.0
	for p in g.get_tree().get_nodes_in_group("planets"):
		if p.owner_id == pid:
			worlds += 1
			pop += p.pop
	return int(gathered.get(pid, 0.0) / 10.0 + get_count(pid, "kill_value") / 5.0
		+ g.researched.get(pid, {}).size() * 25 + worlds * 20 + pop / 100.0)

## Highest value of a sampled field for one side.
func peak(pid: int, field: String) -> int:
	var best := 0
	for s in samples:
		best = maxi(best, int(s[str(pid)][field]))
	return best

## One snapshot per side: stockpiles, pop, worlds, fleet, starbases, tech.
static func sample(t: float) -> Dictionary:
	var g := Game.instance
	var out := {"t": int(t)}
	for pid in [1, 2]:
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
			"techs": g.researched[pid].size(), "mode": str(g.ai._state.get(pid, {}).get("mode", ""))}
	return out
