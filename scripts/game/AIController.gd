class_name AIController
extends Node
## Simple computer opponent: keeps miners working (including one on spice
## once spice is scarce), colonizes nearby worlds, researches, builds a
## mixed fleet while it can afford the running costs, defends its
## starbase, and launches growing attack waves.

const TARGET_MINERS := 6

var players: Array[int] = []
var _state := {}
## Per-player state restored from a save (set before setup()).
var saved_state := {}

func setup(ai_players: Array) -> void:
	for pid in ai_players:
		players.append(pid)
		_state[pid] = saved_state.get(pid, {"wave": 8, "timer": randf(), "claimers": []})

func _process(delta: float) -> void:
	var game := Game.instance
	if game == null or game.is_over:
		return
	for pid in players:
		var st: Dictionary = _state[pid]
		st["timer"] -= delta
		if st["timer"] > 0.0:
			continue
		st["timer"] = 1.0
		_think(pid, st, game)

func _think(pid: int, st: Dictionary, game: Game) -> void:
	var base := game.nearest_starbase(pid, Vector2.ZERO)
	if base == null:
		return
	var res: Dictionary = game.resources[pid]
	var ships: Array = game.get_tree().get_nodes_in_group("ships").filter(func(s): return s.owner_id == pid)
	var miners := ships.filter(func(s): return s.def["role"] == "miner")
	var skimmers := ships.filter(func(s): return s.def["role"] == "skimmer")
	var giant := game.nearest_gas_giant(base.global_position, 4000.0)
	var war := ships.filter(func(s): return s.def["role"] == "warship")
	var colonists := ships.filter(func(s): return s.def["role"] == "colony")

	# Research: keep one tech going if energy isn't collapsing.
	if game.research[pid].is_empty() and game.research_queue[pid].is_empty() and res["energy"] > 150.0:
		var options: Array = Defs.TECHS.keys().filter(func(t): return game.tech_state(pid, t) == "available")
		# Skip pure-spice techs unless spice is plentiful.
		options = options.filter(func(t): return not Defs.TECHS[t]["cost"].has("spice") or res["spice"] > Defs.TECHS[t]["cost"]["spice"] * 1.2)
		if not options.is_empty():
			game.queue_research(pid, options.pick_random())

	# Builds: only queue when stockpiles can roughly cover the next item.
	if base.queue.size() < 2:
		var free_planet := _nearest_planet(base.global_position, game, func(p): return p.owner_id == 0)
		if miners.size() + base.queue.count("miner") < TARGET_MINERS:
			base.enqueue("miner")
		elif giant and game.has_tech(pid, "gas_skimming") and skimmers.size() + base.queue.count("skimmer") < 2:
			base.enqueue("skimmer")
		elif free_planet and colonists.is_empty() and not base.queue.has("colony") and res["spice"] >= 20.0:
			base.enqueue("colony")
		else:
			var pick := _pick_warship(pid, game)
			if pick != "" and res["minerals"] >= Defs.SHIPS[pick]["cost"]["minerals"] * 0.5:
				base.enqueue(pick)

	for c in colonists:
		if c.state == Ship.State.IDLE or c.state == Ship.State.MOVE:
			var p := _nearest_planet(c.global_position, game, func(pl): return pl.owner_id == 0)
			if p:
				c.order_colonize(p)

	for s in skimmers:
		if s.state == Ship.State.IDLE and giant:
			s.order_mine(giant)

	# Idle miners go back to work; one goes after spice when it's low.
	var on_spice := miners.filter(func(m): return is_instance_valid(m.mine_target) and m.mine_target.resource == "spice").size()
	for m in miners:
		if m.state == Ship.State.IDLE:
			var want := "spice" if res["spice"] < 60.0 and on_spice == 0 else "minerals"
			var rock := game.nearest_asteroid(m.global_position, 1600.0, want)
			if rock == null:
				rock = game.nearest_asteroid(m.global_position, 1600.0)
			if rock:
				m.order_mine(rock)
				if rock.resource == "spice":
					on_spice += 1

	# Develop planets: farms when food is falling, otherwise a rotating mix.
	var food_rate: float = game.rates[pid].get("food", 0.0)
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.owner_id != pid or not p.construction.is_empty() or not p.construction_queue.is_empty() or p.free_fields() == 0:
			continue
		var pick := "farm"
		if food_rate > 1.0:
			var cycle := ["generator", "mine", "farm", "habitat"]
			pick = cycle[(p.fields - p.free_fields()) % cycle.size()]
			if res["spice"] < 80.0 and p.spice_reserve > 1000.0 and p.count_building("spice_extractor") == 0:
				pick = "spice_extractor"
		for i in p.fields:
			if p.order_build(i, pick) == "":
				break

	# Defend: enemies near the starbase pull every warship home.
	var threat := game.nearest_enemy(base, 450.0)
	if threat:
		for s in war:
			if s.state != Ship.State.ATTACK:
				s.order_attack_move(threat.global_position)
		return

	var idle := war.filter(func(s): return s.state == Ship.State.IDLE)
	# Idle warships next to an enemy planet start bombarding it.
	for s in idle.duplicate():
		var ep := _nearest_planet(s.global_position, game, func(pl): return pl.is_enemy_of(pid))
		if ep and s.global_position.distance_to(ep.global_position) < 350.0:
			s.order_bombard(ep)
			idle.erase(s)
	if idle.size() >= st["wave"]:
		var goal := _attack_goal(pid, base.global_position, game)
		for s in idle:
			s.order_attack_move(goal + Vector2(randf_range(-40, 40), randf_range(-40, 40)))
		st["wave"] = mini(st["wave"] + 4, 30)

func _pick_warship(pid: int, game: Game) -> String:
	var options: Array[String] = ["corvette", "corvette", "destroyer", "destroyer", "cruiser"]
	options.shuffle()
	var sb := game.nearest_starbase(pid, Vector2.ZERO)
	for t in options:
		# Stop growing the fleet once upkeep would outrun income.
		if game.rates[pid].get("energy", 0.0) < 0.5 and game.resources[pid]["energy"] < 100.0:
			return ""
		if sb.can_queue(t) == "":
			return t
	return ""

func _nearest_planet(from: Vector2, game: Game, filter: Callable) -> Planet:
	var best: Planet = null
	var best_d := INF
	for p in game.get_tree().get_nodes_in_group("planets"):
		if filter.call(p):
			var d := from.distance_to(p.global_position)
			if d < best_d:
				best_d = d
				best = p
	return best

func _attack_goal(pid: int, from: Vector2, game: Game) -> Vector2:
	# Enemy-held planets first (they're closer and feed the enemy), then the base.
	var p := _nearest_planet(from, game, func(pl): return pl.owner_id != 0 and pl.owner_id != pid)
	var enemy_base: Starbase = null
	for sb in game.get_tree().get_nodes_in_group("starbases"):
		if sb.owner_id != pid:
			enemy_base = sb
	if p and (enemy_base == null or from.distance_to(p.global_position) < from.distance_to(enemy_base.global_position)):
		return p.global_position
	return enemy_base.global_position if enemy_base else from
