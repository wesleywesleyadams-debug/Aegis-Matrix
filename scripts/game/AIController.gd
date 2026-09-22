class_name AIController
extends Node
## Simple computer opponent: keeps miners working (including one on spice
## once spice is scarce), colonizes nearby worlds, researches, builds a
## mixed fleet while it can afford the running costs, defends its
## starbase, and launches growing attack waves.

const TARGET_MINERS := 6
## Earliest game time for an attack wave (seconds).
const FIRST_WAVE_TIME := 420.0

var players: Array[int] = []
var _state := {}
## Per-player state restored from a save (set before setup()).
var saved_state := {}

func setup(ai_players: Array) -> void:
	for pid in ai_players:
		players.append(pid)
		_state[pid] = saved_state.get(pid, {"wave": 10, "timer": randf(), "claimers": []})
		# Learned commander (NeuralCommander): for training, SL_NN_WEIGHTS +
		# SL_NN_SIDE pick the side; in normal play GameState.neural_ai puts
		# the trained res://ai/commander.json in charge of every AI side.
		var path := ""
		if OS.get_environment("SL_NN_WEIGHTS") != "" and int(OS.get_environment("SL_NN_SIDE")) == pid:
			path = OS.get_environment("SL_NN_WEIGHTS")
		# Self-play training: the opposing side runs another network.
		elif OS.get_environment("SL_NN_OPP_WEIGHTS") != "" and int(OS.get_environment("SL_NN_SIDE")) != pid:
			path = OS.get_environment("SL_NN_OPP_WEIGHTS")
		elif GameState.neural_ai and OS.get_environment("SL_SIM") == "":
			path = "res://ai/commander.json"
		if path != "":
			var net := NeuralNet.load_json(path)
			if net:
				_state[pid]["nn"] = NeuralCommander.new(net, pid)

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
	if OS.get_environment("SL_AI_DEBUG") != "" and int(Game.now()) % 20 == 0:
		print("AIDBG t=%d pid=%d mode=%s queue=%s stalled=%s stall=%s blocked=%s prog=%.1f" % [Game.now(), pid, st.get("mode", ""), str(base.queue), str(base.build_stalled), str(st.get("stall", 0)), str(st.get("blocked", {})), base.build_progress])
	var nn: NeuralCommander = st.get("nn")
	if nn == null:
		_rethink(pid, st, game, base, war)
	_manage_queues(pid, st, game, base)
	var mode: String = st.get("mode", "expand")

	# Research: keep one tech going if energy isn't collapsing.
	if game.research[pid].is_empty() and game.research_queue[pid].is_empty() and res["energy"] > 150.0:
		var options: Array = Defs.TECHS.keys().filter(func(t): return game.tech_state(pid, t) == "available")
		# Skip pure-spice techs unless spice is plentiful.
		options = options.filter(func(t): return not Defs.TECHS[t]["cost"].has("spice") or res["spice"] > Defs.TECHS[t]["cost"]["spice"] * 1.2)
		if not options.is_empty():
			game.queue_research(pid, options.pick_random())

	# Builds: only queue when stockpiles can roughly cover the next item.
	if nn == null and base.queue.size() < 2:
		var free_planet := _nearest_planet(base.global_position, game, func(p): return _known_free(pid, p, game))
		if miners.size() + base.queue.count("miner") < TARGET_MINERS:
			base.enqueue("miner")
		elif giant and game.has_tech(pid, "gas_skimming") and skimmers.size() + base.queue.count("skimmer") < 2:
			base.enqueue("skimmer")
		# Keep colonizing unless enemies are actually at our worlds (being
		# outgunned elsewhere isn't a reason to stop growing).
		elif free_planet and mode != "recover" and not st.get("threat", false) and colonists.size() + base.queue.count("colony") < 2 and res["spice"] >= 10.0:
			base.enqueue("colony")
		elif mode != "recover":
			var pick := _pick_warship(pid, game, st)
			if pick != "" and res["minerals"] >= Defs.SHIPS[pick]["cost"]["minerals"] * 0.5:
				base.enqueue(pick)

	for c in colonists:
		if c.state == Ship.State.IDLE or c.state == Ship.State.MOVE:
			var p := _nearest_planet(c.global_position, game, func(pl): return _known_free(pid, pl, game))
			if p:
				c.order_colonize(p)

	for s in skimmers:
		if s.state == Ship.State.IDLE and giant:
			s.order_mine(giant)

	# Idle miners go back to work; one goes after spice when it's low.
	var on_spice := miners.filter(func(m): return is_instance_valid(m.mine_target) and m.mine_target.resource == "spice").size()
	for m in miners:
		if m.state == Ship.State.IDLE:
			# Spice gates colonies and bigger hulls: keep up to two miners on it
			# while it's short.
			var want := "spice" if res["spice"] < 150.0 and on_spice < 2 else "minerals"
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
			# Energy falling: power plants first.
			if game.rates[pid].get("energy", 0.0) < 0.5 and res["energy"] < 300.0:
				pick = "generator"
			if res["spice"] < 150.0 and p.spice_reserve > 500.0 and p.count_building("spice_extractor") == 0:
				pick = "spice_extractor"
		for i in p.fields:
			if p.order_build(i, pick) == "":
				break

	_scout(pid, st, game, war)

	# The learned commander decides builds and fleet moves itself.
	if nn != null:
		nn.tick(game, base, self)
		return

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
		# Only small colonies are worth bombarding; big worlds would take forever.
		if ep and ep.pop < 4000.0 and s.global_position.distance_to(ep.global_position) < 350.0:
			s.order_bombard(ep)
			idle.erase(s)
	# No attack waves in the opening minutes: build up first.
	# Attack mode (clearly stronger): go now with a smaller wave.
	var need: int = 6 if mode == "attack" else st["wave"]
	if mode != "build_up" and idle.size() >= need and Game.now() >= FIRST_WAVE_TIME:
		var goal := _attack_goal(pid, base.global_position, game)
		for s in idle:
			s.order_attack_move(goal + Vector2(randf_range(-40, 40), randf_range(-40, 40)))
		st["wave"] = mini(st["wave"] + 4, 30)

func _pick_warship(pid: int, game: Game, st: Dictionary = {}) -> String:
	var options: Array[String] = ["corvette", "corvette", "destroyer", "destroyer", "cruiser"]
	options.shuffle()
	var sb := game.nearest_starbase(pid, Vector2.ZERO)
	var res: Dictionary = game.resources[pid]
	# Stop growing the fleet once upkeep would outrun income.
	if game.rates[pid].get("energy", 0.0) < 0.5 and res["energy"] < 200.0:
		return ""
	for t in options:
		if st.get("corvettes_only", false) and t != "corvette":
			continue
		# Recently cancelled for stalling: give it a minute.
		if Game.now() < st.get("blocked", {}).get(t, -1.0):
			continue
		# A hull whose spice we can't pay stalls the whole queue: skip it.
		if res["spice"] < Defs.SHIPS[t]["cost"].get("spice", 0) * 1.1:
			continue
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
	# The enemy starbase wins the match; a small enemy colony on the way is
	# fair game (big worlds take too long to bombard).
	var v: Vision = game.visions.get(pid)
	if v:
		# Fog of war: only targets we've seen. With no enemy starbase found
		# yet, head for the mirror image of our home (systems are point-
		# symmetric, so that's where the enemy most likely started).
		var kp := _nearest_planet(from, game, func(pl): return v.known_owner(pl) > 0 and v.known_owner(pl) != pid and v.seen_planet_pop.get(pl, 0.0) < 4000.0)
		var kb := v.known_enemy_base(from)
		var home := game.nearest_starbase(pid, Vector2.ZERO)
		var base_pos: Vector2 = kb[0] if not kb.is_empty() else (-home.global_position if home else Vector2.ZERO)
		if kp and from.distance_to(kp.global_position) < from.distance_to(base_pos):
			return kp.global_position
		return base_pos
	var p := _nearest_planet(from, game, func(pl): return pl.owner_id != 0 and pl.owner_id != pid and pl.pop < 4000.0)
	var enemy_base: Starbase = null
	for sb in game.get_tree().get_nodes_in_group("starbases"):
		if sb.owner_id != pid:
			enemy_base = sb
	if p and (enemy_base == null or from.distance_to(p.global_position) < from.distance_to(enemy_base.global_position)):
		return p.global_position
	return enemy_base.global_position if enemy_base else from

## A planet this player knows to be free (seen unclaimed); without fog, any
## unclaimed planet.
func _known_free(pid: int, p: Planet, game: Game) -> bool:
	var v: Vision = game.visions.get(pid)
	if v:
		return v.known_owner(p) == 0
	return p.owner_id == 0

## Scouting: one warship explores the nearest unexplored spot until most of
## the system is known (only with fog of war).
const SCOUT_UNTIL := 0.85

func _scout(pid: int, st: Dictionary, game: Game, war: Array) -> void:
	var v: Vision = game.visions.get(pid)
	if v == null or war.is_empty() or Game.now() < st.get("next_scout", 0.0):
		return
	st["next_scout"] = Game.now() + 5.0
	if v.explored_fraction() >= SCOUT_UNTIL:
		return
	# (Untyped until checked: the old scout may have been destroyed.)
	var old = st.get("scout")
	var sc: Ship = old if is_instance_valid(old) else null
	if sc == null or not sc.is_alive():
		# The fastest warship (corvettes) makes the best scout.
		war.sort_custom(func(a, b): return a.def["speed"] > b.def["speed"])
		sc = war[0]
		st["scout"] = sc
	if sc.state == Ship.State.IDLE or sc.global_position.distance_to(sc.move_goal) < 60.0 or v.is_explored_at(sc.move_goal):
		sc.order_move(v.nearest_unexplored(sc.global_position))

# ---------------------------------------------------------------- strategy

## Re-reads the situation every RETHINK seconds and picks a mode:
##   recover  - out of energy: no new warships, cancel queued ones (out of
##              spice only limits the fleet to corvettes, in any mode)
##   build_up - under threat or outgunned: warships first, no colonies, no waves
##   attack   - clearly stronger: smaller waves launch right away
##   expand   - otherwise: colonies first while free worlds remain
## Switching mode cancels queued items that no longer fit.
const RETHINK := 15.0

func _rethink(pid: int, st: Dictionary, game: Game, base: Starbase, war: Array) -> void:
	if Game.now() < st.get("next_rethink", 0.0):
		return
	st["next_rethink"] = Game.now() + RETHINK
	var mine := 0.0
	for s in war:
		mine += s.max_hp + s.max_shield
	var theirs := 0.0
	var threat := false
	var v: Vision = game.visions.get(pid)
	if v:
		# Fog of war: judge the enemy only by what our sensors have seen.
		theirs = v.enemy_power()
		threat = v.enemy_near(base.global_position, 900.0) > 0
		for p in game.get_tree().get_nodes_in_group("planets"):
			if p.owner_id == pid and v.enemy_near(p.global_position, 500.0) > 0:
				threat = true
				break
	for s in ([] if v else game.get_tree().get_nodes_in_group("ships")):
		if s.owner_id == pid or s.owner_id == 0 or not s.is_alive() or s.def["role"] != "warship":
			continue
		theirs += s.max_hp + s.max_shield
		if s.global_position.distance_to(base.global_position) < 900.0:
			threat = true
		else:
			for p in game.get_tree().get_nodes_in_group("planets"):
				if p.owner_id == pid and s.global_position.distance_to(p.global_position) < 500.0:
					threat = true
					break
	var res: Dictionary = game.resources[pid]
	var rates: Dictionary = game.rates[pid]
	var energy_starved: bool = res["energy"] < 60.0 and rates.get("energy", 0.0) < 0.0
	var spice_starved: bool = res["spice"] < 10.0 and rates.get("spice", 0.0) <= 0.0
	# Out of spice alone isn't a crisis: corvettes cost none (see _pick_warship).
	st["corvettes_only"] = spice_starved
	var starved := energy_starved
	var free := _nearest_planet(base.global_position, game, func(p): return _known_free(pid, p, game) and p.is_habitable()) != null
	var mode := "expand" if free else "build_up"
	if starved:
		mode = "recover"
	elif threat or theirs > mine * 1.3:
		mode = "build_up"
	elif mine > theirs * 1.4 and war.size() >= 8:
		mode = "attack"
	st["threat"] = threat
	var old: String = st.get("mode", "")
	st["mode"] = mode
	if mode == old:
		return
	# Drop queued items (not the one already being built) that the new plan
	# doesn't want.
	for i in range(base.queue.size() - 1, 0, -1):
		var t: String = base.queue[i]
		var role: String = Defs.SHIPS[t]["role"]
		if (mode == "recover" and role == "warship") or (threat and role == "colony"):
			base.cancel(i)

func _front_needs_spice(base: Starbase) -> bool:
	return not base.queue.is_empty() and Defs.SHIPS[base.queue[0]]["cost"].has("spice")

## Cancel builds that have been stuck waiting on resources: the starbase's
## front item after STALL_CANCEL seconds (and don't requeue that type for a
## minute), planet constructions after PLANET_STALL_CANCEL. Refunds follow
## the usual cancel rules.
const STALL_CANCEL := 12.0
const PLANET_STALL_CANCEL := 20.0

func _manage_queues(pid: int, st: Dictionary, game: Game, base: Starbase) -> void:
	if base.build_stalled and not base.queue.is_empty():
		st["stall"] = st.get("stall", 0.0) + 1.0
		if st["stall"] >= STALL_CANCEL:
			var t: String = base.queue[0]
			if not st.has("blocked"):
				st["blocked"] = {}
			st["blocked"][t] = Game.now() + 60.0
			base.cancel(0)
			st["stall"] = 0.0
	else:
		st["stall"] = 0.0
	if not st.has("pstall"):
		st["pstall"] = {}
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.owner_id != pid or p.construction.is_empty():
			continue
		var key := String(p.name)
		if p.construction_stalled:
			st["pstall"][key] = st["pstall"].get(key, 0.0) + 1.0
			if st["pstall"][key] >= PLANET_STALL_CANCEL:
				p.cancel_build(p.construction["field"])
				st["pstall"][key] = 0.0
		else:
			st["pstall"][key] = 0.0
