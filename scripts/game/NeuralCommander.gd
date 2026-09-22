class_name NeuralCommander
## Learned high-level play for one AI side. Every DECIDE seconds it turns the
## match into FEATURES numbers, asks the NeuralNet for a score per ACTION,
## masks actions that can't be done right now, and carries out the best one.
## Everything else (mining, colonist targeting, planet development, research,
## ship steering) stays with the scripted AIController, so the network only
## learns strategy: what to build and when to attack, defend or regroup.
## Trained by tools/es_train.pl (evolution strategies).

const ACTIONS := ["wait", "corvette", "destroyer", "cruiser", "miner", "colony", "attack", "defend", "regroup"]
const N_FEATURES := 21
const HIDDEN := 16
const DECIDE := 2.0

var net: NeuralNet
var pid: int
var last_action: String = ""
var counts := {}
var _next: float = 0.0
## Training runs (SL_NN_EXPLORE) sample actions instead of taking the best.
var explore: bool = OS.get_environment("SL_NN_EXPLORE") != ""

func _init(network: NeuralNet, side: int) -> void:
	net = network
	pid = side

## Called from AIController._think (once a second).
func tick(game: Game, base: Starbase, ai: AIController) -> void:
	if Game.now() < _next:
		return
	_next = Game.now() + DECIDE
	var scores := net.forward(features(game, base))
	var best := -1
	if explore:
		# Training: sample from a softmax over the valid actions so perturbed
		# networks actually play differently (and learning has signal).
		var ps := PackedFloat32Array()
		var total := 0.0
		var top := -INF
		for k in ACTIONS.size():
			if _valid(ACTIONS[k], game, base):
				top = maxf(top, scores[k])
		for k in ACTIONS.size():
			var p := exp(scores[k] - top) if _valid(ACTIONS[k], game, base) else 0.0
			ps.append(p)
			total += p
		var roll := randf() * total
		for k in ACTIONS.size():
			roll -= ps[k]
			if ps[k] > 0.0 and roll <= 0.0:
				best = k
				break
	else:
		var best_s := -INF
		for k in ACTIONS.size():
			if scores[k] > best_s and _valid(ACTIONS[k], game, base):
				best_s = scores[k]
				best = k
	if best < 0:
		return
	last_action = ACTIONS[best]
	counts[last_action] = counts.get(last_action, 0) + 1
	_do(last_action, game, base, ai)

func _war(game: Game, side: int) -> Array:
	return game.get_tree().get_nodes_in_group("ships").filter(func(s): return s.owner_id == side and s.is_alive() and s.def["role"] == "warship")

func _power(ships: Array) -> float:
	var p := 0.0
	for s in ships:
		p += s.max_hp + s.max_shield
	return p

func _base_frac(game: Game, side: int) -> float:
	for sb in game.starbase_list:
		if is_instance_valid(sb) and sb.owner_id == side and sb.is_alive() and not sb.under_construction:
			return (sb.hp + sb.shield) / maxf(sb.max_hp + sb.max_shield, 1.0)
	return 0.0

## What the network sees, each roughly in [-1, 1].
func features(game: Game, base: Starbase) -> PackedFloat32Array:
	var foe := 3 - pid
	var r: Dictionary = game.resources[pid]
	var mine := _war(game, pid)
	var theirs := _war(game, foe)
	var worlds := [0, 0, 0]
	var free := 0
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.owner_id == pid:
			worlds[1] += 1
		elif p.owner_id == foe:
			worlds[2] += 1
		elif p.is_habitable():
			free += 1
	var near := 0
	for s in theirs:
		if s.global_position.distance_to(base.global_position) < 900.0:
			near += 1
	var ships := game.get_tree().get_nodes_in_group("ships").filter(func(s): return s.owner_id == pid)
	var miners := ships.filter(func(s): return s.is_miner()).size()
	var colonists := ships.filter(func(s): return s.def["role"] == "colony").size()
	var idle := mine.filter(func(s): return s.state == Ship.State.IDLE).size()
	var f := PackedFloat32Array([
		minf(Game.now() / 1800.0, 2.0),
		log(1.0 + r["minerals"]) / 8.0, log(1.0 + r["energy"]) / 8.0, log(1.0 + r["spice"]) / 6.0, log(1.0 + r["food"]) / 10.0,
		clampf(game.rates[pid].get("energy", 0.0) / 10.0, -1.0, 1.0),
		tanh(_power(mine) / 5000.0), tanh(_power(theirs) / 5000.0),
		worlds[1] / 6.0, worlds[2] / 6.0, free / 8.0,
		miners / 8.0, colonists / 2.0,
		1.0 if near > 0 else 0.0, minf(near / 20.0, 1.0),
		base.queue.size() / 5.0, minf(idle / 20.0, 1.0),
		_base_frac(game, pid), _base_frac(game, foe),
		1.0 if game.has_tech(pid, "cruiser_doctrine") else 0.0,
		1.0,
	])
	return f

func _valid(a: String, game: Game, base: Starbase) -> bool:
	var r: Dictionary = game.resources[pid]
	match a:
		"wait", "defend", "regroup":
			return true
		"attack":
			return not _war(game, pid).is_empty()
		"colony":
			if r["spice"] < Defs.SHIPS["colony"]["cost"]["spice"]:
				return false
			for p in game.get_tree().get_nodes_in_group("planets"):
				if p.owner_id == 0 and p.is_habitable():
					return base.can_queue("colony") == ""
			return false
		_:
			var d: Dictionary = Defs.SHIPS[a]
			if r["spice"] < d["cost"].get("spice", 0):
				return false
			return base.can_queue(a) == ""

func _do(a: String, game: Game, base: Starbase, ai: AIController) -> void:
	match a:
		"corvette", "destroyer", "cruiser", "miner", "colony":
			base.enqueue(a)
		"attack":
			var goal := ai._attack_goal(pid, base.global_position, game)
			for s in _war(game, pid):
				if s.state == Ship.State.IDLE or s.state == Ship.State.MOVE:
					s.order_attack_move(goal + Vector2(randf_range(-40, 40), randf_range(-40, 40)))
		"defend":
			for s in _war(game, pid):
				s.order_attack_move(base.global_position + Vector2(randf_range(-80, 80), randf_range(-80, 80)))
		"regroup":
			# Pull stragglers back toward the fleet's center of mass.
			var ws := _war(game, pid)
			if ws.is_empty():
				return
			var c := Vector2.ZERO
			for s in ws:
				c += s.global_position
			c /= ws.size()
			for s in ws:
				if s.global_position.distance_to(c) > 250.0:
					s.order_move(c)
