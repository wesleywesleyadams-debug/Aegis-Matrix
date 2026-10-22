class_name NeuralCommander
## Learned high-level play for one AI side. Every DECIDE seconds it turns the
## match into FEATURES numbers, asks the NeuralNet for a score per ACTION,
## masks actions that can't be done right now, and carries out the best one.
## Ship steering, mining, colonist targeting and planet development stay with
## the scripted AIController, so the network learns strategy: what to build,
## what to research, when to open a Weapons Depot and refit, and when to
## attack, defend or regroup.
## Trained by tools/es_train.pl (evolution strategies).

## Every buildable hull (Defs.BUILD_ORDER), plus the strategic moves.
const ACTIONS := ["wait", "miner", "skimmer", "colony", "constructor", "scout", "tender",
	"corvette", "destroyer", "cruiser", "carrier", "heatshield",
	"research_offense", "research_defense", "research_economy",
	"depot", "refit", "attack", "defend", "regroup"]
const N_FEATURES := 43
const HIDDEN := 28
const DECIDE := 2.0

## Research grouped the way a commander thinks about it.
const TECH_GROUPS := {
	"research_offense": ["destroyers", "depots", "ion_cannons", "corvette_mk2", "cruisers", "destroyer_mk2", "particle_lances", "overcharged_coils", "burst_cyclers", "hullbreaker_rounds", "corvette_mk3", "destroyer_mk3", "cruiser_mk2", "corvette_mk4", "destroyer_mk4", "cruiser_mk3", "cruiser_mk4"],
	"research_defense": ["deflectors", "phase_shields", "aegis_matrix", "composite_plating", "reactive_armor",
		"neutronium_armor", "reinforced_frames", "nanite_plating", "adaptive_hulls"],
	"research_economy": ["hydroponics", "deep_drills", "gas_skimming", "gene_clinics", "arcologies",
		"ion_thrusters", "spice_navigation", "cutting_lasers", "resonance_drills", "bulk_holds", "fusion_drives", "solar_collectors", "plasma_reactors", "dark_matter"],
}
var net: NeuralNet
var pid: int
var last_action: String = ""
var counts := {}
var _next: float = 0.0
## The trained policy is stochastic: it samples actions by their softmax
## weights (that mix is what training rewarded; always taking the top score
## plays a different, much weaker strategy). SL_NN_GREEDY forces argmax.
var explore: bool = OS.get_environment("SL_NN_GREEDY") == ""

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
		# Sample from a softmax over the valid actions.
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
		p += s.max_hp + s.max_armor + s.max_shield
	return p

func _base_frac(game: Game, side: int) -> float:
	for sb in game.starbase_list:
		if is_instance_valid(sb) and sb.owner_id == side and sb.is_alive() and not sb.under_construction:
			return (sb.hp + sb.armor + sb.shield) / maxf(sb.max_hp + sb.max_armor + sb.max_shield, 1.0)
	return 0.0

func _count_role(ships: Array, role: String) -> int:
	return ships.filter(func(s): return s.def["role"] == role).size()

func _count_type(ships: Array, t: String) -> int:
	return ships.filter(func(s): return s.ship_type == t).size()

## How far a defense line has been researched, 0-3 (Codex: Defenses tab).
func _line_level(game: Game, line: String) -> int:
	var n := 0
	for id in Defs.TECHS:
		if Defs.TECHS[id].get("line", "") == line and game.has_tech(pid, id):
			n += 1
	return n

## The cheapest tech of a group this side could start now ("" if none).
func _next_tech(game: Game, group: String) -> String:
	var best := ""
	var best_cost := INF
	for id in TECH_GROUPS[group]:
		if game.tech_state(pid, id) != "available":
			continue
		var c: float = Defs.TECHS[id]["cost"].get("energy", 0.0) + Defs.TECHS[id]["cost"].get("spice", 0.0) * 1.2
		if c < best_cost:
			best_cost = c
			best = id
	return best

## What the network sees, each roughly in [-1, 1]: the same things the Codex
## tells a player. Stockpiles and rates, both fleets, worlds, what is built,
## what is researched, and what its sensors know of the enemy.
func features(game: Game, base: Starbase) -> PackedFloat32Array:
	# The network was trained on one opponent: with more, it watches the
	# nearest living enemy.
	var foe := 0
	var foe_d := INF
	var v0: Vision = game.visions.get(pid)
	for o in game.living_players():
		if game.is_hostile(pid, o):
			# (With fog: its nearest starbase this side has seen, else unknown.)
			var d: float = INF
			if v0 and base:
				for id in v0.seen_bases:
					if int(v0.seen_bases[id][2]) == o:
						d = minf(d, base.global_position.distance_to(v0.seen_bases[id][0]))
			else:
				var ob := game.nearest_starbase(o, base.global_position if base else Vector2.ZERO)
				d = base.global_position.distance_to(ob.global_position) if base and ob else 0.0
			if foe == 0 or d < foe_d:
				foe = o
				foe_d = d
	if foe == 0:
		foe = game.players.filter(func(o): return o != pid)[0]
	var r: Dictionary = game.resources[pid]
	var rates: Dictionary = game.rates[pid]
	var v: Vision = game.visions.get(pid)
	var ships: Array = game.get_tree().get_nodes_in_group("ships").filter(func(s): return s.owner_id == pid)
	var mine := _war(game, pid)
	var theirs_power: float = v.enemy_power() if v else _power(_war(game, foe))
	var worlds := 0
	var foe_worlds := 0
	var free := 0
	for p in game.get_tree().get_nodes_in_group("planets"):
		var o: int = v.known_owner(p) if v else p.owner_id
		if p.owner_id == pid:
			worlds += 1
		elif o == foe:
			foe_worlds += 1
		elif o == 0 and p.is_habitable():
			free += 1
	var near := 0
	if v:
		near = v.enemy_near(base.global_position, 900.0)
	else:
		for s in _war(game, foe):
			if s.global_position.distance_to(base.global_position) < 900.0:
				near += 1
	var foe_base := 0.0
	if v:
		var kb := v.known_enemy_base(base.global_position)
		foe_base = kb[1] if not kb.is_empty() else 1.0
	else:
		foe_base = _base_frac(game, foe)
	# What the enemy's defenses are made of, so it can pick the right depot.
	var layers := {"shield": 0.0, "armor": 0.0, "hull": 0.0}
	if v:
		layers = v.enemy_layers()
	else:
		for s in _war(game, foe):
			layers["shield"] += s.max_shield
			layers["armor"] += s.max_armor
			layers["hull"] += s.max_hp
	var lt: float = maxf(layers["shield"] + layers["armor"] + layers["hull"], 1.0)
	var depots: int = game.get_tree().get_nodes_in_group("depots").filter(func(d): return d.owner_id == pid).size()
	var specialists := ships.filter(func(s): return s.def.has("variant")).size()
	var idle := mine.filter(func(s): return s.state == Ship.State.IDLE).size()
	return PackedFloat32Array([
		minf(Game.now() / 1800.0, 2.0),
		log(1.0 + r["minerals"]) / 8.0, log(1.0 + r["energy"]) / 6.0, log(1.0 + r["spice"]) / 6.0, log(1.0 + r["food"]) / 10.0,
		clampf(rates.get("energy", 0.0) / 1.5, -1.0, 1.0), clampf(rates.get("minerals", 0.0) / 10.0, -1.0, 1.0),
		clampf(rates.get("food", 0.0) / 3000.0, -1.0, 1.0), clampf(rates.get("spice", 0.0) / 3.0, -1.0, 1.0),
		tanh(_power(mine) / 5000.0), tanh(theirs_power / 5000.0),
		worlds / 6.0, foe_worlds / 6.0, free / 8.0,
		_count_role(ships, "miner") / 8.0, _count_role(ships, "skimmer") / 3.0,
		_count_role(ships, "colony") / 2.0, _count_role(ships, "constructor") / 2.0,
		_count_role(ships, "scout") / 2.0, _count_role(ships, "support") / 2.0,
		_count_type(ships, "heatshield") / 3.0,
		minf(mine.size() / 20.0, 1.0), minf(idle / 20.0, 1.0),
		base.queue.size() / 5.0, _base_frac(game, pid), foe_base,
		1.0 if near > 0 else 0.0, minf(near / 20.0, 1.0),
		float(game.researched[pid].size()) / float(Defs.TECHS.size()),
		1.0 if game.has_tech(pid, "cruisers") else 0.0,
		1.0 if game.has_tech(pid, "gas_skimming") else 0.0,
		_line_level(game, "shields") / 3.0, _line_level(game, "armor") / 3.0, _line_level(game, "hull") / 3.0,
		minf(depots, 2) / 2.0, float(specialists) / maxf(mine.size(), 1.0),
		layers["shield"] / lt, layers["armor"] / lt, layers["hull"] / lt,
		1.0 if game.has_tech(pid, "carriers") else 0.0,
		minf(game.get_tree().get_nodes_in_group("starbases").filter(func(b): return b.owner_id == pid).size() / 10.0, 2.0),
		minf((v.seen_bases.size() if v else game.get_tree().get_nodes_in_group("starbases").filter(func(b): return b.owner_id == foe).size()) / 10.0, 2.0),
		1.0,
	])

func _valid(a: String, game: Game, base: Starbase) -> bool:
	var r: Dictionary = game.resources[pid]
	match a:
		"wait", "defend", "regroup":
			return true
		"attack":
			return not _war(game, pid).is_empty()
		"research_offense", "research_defense", "research_economy":
			return game.research[pid].is_empty() and game.research_queue[pid].is_empty() and _next_tech(game, a) != ""
		"depot":
			# Needs the tech and an idle Constructor (used up building it).
			if not game.has_tech(pid, str(Defs.WEAPONS_DEPOT["requires"])):
				return false
			return game.get_tree().get_nodes_in_group("ships").any(
				func(s): return s.owner_id == pid and s.def["role"] == "constructor" and s.state == Ship.State.IDLE)
		"refit":
			if game.nearest_depot(pid, base.global_position) == null:
				return false
			return _war(game, pid).any(func(s): return s.state == Ship.State.IDLE and not s.def.has("variant") and Defs.VARIANTS_OF.has(s.ship_type))
		"colony":
			if r["minerals"] < Defs.SHIPS["colony"]["cost"].get("minerals", 0.0):
				return false
			for p in game.get_tree().get_nodes_in_group("planets"):
				if ai_free(game, p) and p.is_habitable():
					return base.can_queue("colony") == ""
			return false
		_:
			var d: Dictionary = Defs.SHIPS[a]
			if r["spice"] < d["cost"].get("spice", 0):
				return false
			return base.can_queue(a) == ""

func _do(a: String, game: Game, base: Starbase, ai: AIController) -> void:
	match a:
		"wait":
			pass
		"research_offense", "research_defense", "research_economy":
			var t := _next_tech(game, a)
			if t != "":
				game.queue_research(pid, t)
		"depot":
			# The variant its intel says is worth fitting (see AIController).
			var want := ai._pick_variant(pid, game)
			if want == "":
				want = "reaver"
			for s in game.get_tree().get_nodes_in_group("ships"):
				if s.owner_id == pid and s.def["role"] == "constructor" and s.state == Ship.State.IDLE:
					var site := ai._depot_site(base.global_position, game)
					if site != Vector2.INF:
						s.order_build_depot(site, want)
					return
		"refit":
			var depot := game.nearest_depot(pid, base.global_position)
			if depot == null:
				return
			var sent := 0
			for s in _war(game, pid):
				if sent + depot.bays.size() >= int(Defs.WEAPONS_DEPOT["capacity"]):
					break
				if s.state == Ship.State.IDLE and s.can_refit(depot.variant):
					s.order_refit(depot.variant, depot)
					sent += 1
		"attack":
			# Only toward a target the fleet can take with ships to spare.
			var goal := ai._winnable_target(pid, _war(game, pid).filter(func(s): return s.state == Ship.State.IDLE or s.state == Ship.State.MOVE), base.global_position, game)
			if goal == Vector2.INF:
				return
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
		_:
			base.enqueue(a)

## A planet this side knows to be free (see AIController._known_free).
func ai_free(game: Game, p: Planet) -> bool:
	var v: Vision = game.visions.get(pid)
	return v.known_owner(p) == 0 if v else p.owner_id == 0
