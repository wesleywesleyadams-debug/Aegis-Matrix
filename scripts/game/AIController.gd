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
		elif GameState.neural_ai and OS.get_environment("SL_SIM") == "" and Game.instance.rl_server_pid <= 0:
			path = "res://ai/commander.json"
		if path != "":
			var net := NeuralNet.load_json(path)
			# Weights from an older network shape can't drive this commander.
			if net and (net.n_in != NeuralCommander.N_FEATURES or net.n_out != NeuralCommander.ACTIONS.size()):
				push_warning("Ignoring %s: %d x %d weights, this build needs %d x %d" % [
					path, net.n_in, net.n_out, NeuralCommander.N_FEATURES, NeuralCommander.ACTIONS.size()])
				net = null
			if net:
				_state[pid]["nn"] = NeuralCommander.new(net, pid)
		# The learning agent (tools/rl/): SL_RL_PORT, for side SL_RL_SIDE.
		if OS.get_environment("SL_RL_PORT") != "" and pid == maxi(1, int(OS.get_environment("SL_RL_SIDE"))):
			var agent := RLAgent.new(pid, int(OS.get_environment("SL_RL_PORT")))
			Game.instance.add_child(agent)
			_state[pid]["nn"] = agent
		# Self-play (curriculum level 5): the other side is a second learning
		# agent, on SL_RL_PORT2 (the trainer runs a frozen copy of the policy).
		elif OS.get_environment("SL_RL_PORT2") != "" and OS.get_environment("SL_RL_PORT") != "":
			var opp := RLAgent.new(pid, int(OS.get_environment("SL_RL_PORT2")))
			Game.instance.add_child(opp)
			_state[pid]["nn"] = opp
		# A normal match: a lobby "Neural AI" slot is played by the learning
		# agent, through the server Game started (Game.RL_SERVE_PORT).
		elif Game.instance.rl_server_pid > 0 and Game.instance.player_type(pid) == "neural":
			var live := RLAgent.new(pid, Game.RL_SERVE_PORT, 30000)
			Game.instance.add_child(live)
			_state[pid]["nn"] = live
			print("Neural AI v%d plays P%d: %s" % [Game.instance.rl_version, pid, "connected" if live.connected() else "no server - scripted AI instead"])

func _process(delta: float) -> void:
	var game := Game.instance
	if game == null or game.is_over:
		return
	# A fresh order every tick: whoever thinks second sees a world the first
	# has already acted on, and a fixed order gave that side most of the wins.
	var order := players.duplicate()
	order.shuffle()
	for pid in order:
		var st: Dictionary = _state[pid]
		st["timer"] -= delta
		if st["timer"] > 0.0:
			continue
		st["timer"] = 1.0
		_think(pid, st, game)

func _think(pid: int, st: Dictionary, game: Game) -> void:
	# The learning agent runs its whole side itself: nothing scripted (unless
	# it lost its server, in a normal match - then the scripted AI takes over).
	if st.get("nn") is RLAgent and (game.sim_mode or st["nn"].connected()):
		st["nn"].tick(game, game.nearest_starbase(pid, Vector2.ZERO), self)
		return
	var base := game.nearest_starbase(pid, Vector2.ZERO)
	if base == null:
		return
	var res: Dictionary = game.resources[pid]
	var ships: Array = game.get_tree().get_nodes_in_group("ships").filter(func(s): return s.owner_id == pid)
	var miners := ships.filter(func(s): return s.def["role"] == "miner")
	var skimmers := ships.filter(func(s): return s.def["role"] == "skimmer")
	# Fog of war: this player's own sensors and memory (null without fog).
	var v: Vision = game.visions.get(pid)
	var giant := game.nearest_gas_giant(base.global_position, 4000.0, v)
	# The closest explored point inside a spice nebula (INF if none known).
	var neb_spot := _nebula_spot(base.global_position, game, v)
	var war := ships.filter(func(s): return s.def["role"] == "warship")
	var colonists := ships.filter(func(s): return s.def["role"] == "colony")
	# What the build picker needs to know about the fleet it is adding to.
	st["fleet"] = war.size()
	st["carriers"] = war.filter(func(s): return s.is_carrier()).size()
	# Warships inside a Warp Gate or mid-warp take no orders: they count for
	# strength (all_war) but the order-giving code below only sees the rest.
	var all_war := war
	war = war.filter(func(s): return not s.warping and not (s.docked and is_instance_valid(s.warp_gate)))
	if OS.get_environment("SL_AI_DEBUG") != "" and int(Game.now()) % 20 == 0:
		print("AIDBG t=%d pid=%d mode=%s queue=%s stalled=%s stall=%s blocked=%s prog=%.1f" % [Game.now(), pid, st.get("mode", ""), str(base.queue), str(base.build_stalled), str(st.get("stall", 0)), str(st.get("blocked", {})), base.build_progress])
	# Enemies just spotted near home: re-plan now instead of at the next
	# scheduled rethink.
	if v and not st.get("threat", false) and v.enemy_near(base.global_position, 900.0) > 0:
		st["next_rethink"] = 0.0
	var nn = st.get("nn")   # NeuralCommander or RLAgent: both have tick()
	if nn == null:
		_rethink(pid, st, game, base, all_war)
	_manage_queues(pid, st, game, base)
	var mode: String = st.get("mode", "expand")

	# Research never idles: the moment a project ends the next one starts
	# (the AI thinks every second; one project runs at a time).
	# (The learning agent picks its own research.)
	if not (st.get("nn") is RLAgent) and game.research[pid].is_empty() and game.research_queue[pid].is_empty():
		# Mods: one per class, only for a class it fields, and only the one its
		# intel says fits (see _pick_mod). It never swaps a Mod once chosen.
		var options: Array = Defs.TECHS.keys().filter(func(t): return game.tech_state(pid, t) == "available" 			and (not Defs.TECHS[t].has("mod") or _mod_wanted(pid, game, t, war)))
		# Prefer techs it can pay for now; fall back to anything available.
		var payable := options.filter(func(t): return not Defs.TECHS[t]["cost"].has("spice") or res["spice"] > Defs.TECHS[t]["cost"]["spice"] * 1.2)
		if not payable.is_empty():
			options = payable
		if not options.is_empty():
			var tech := _pick_tech(options, all_war.size())
			game.queue_research(pid, tech)
			if Defs.TECHS[tech].get("group", "") == "constructs":
				_flog(pid, "research %s" % tech)

	# Builds: only queue when stockpiles can roughly cover the next item.
	if nn == null and base.queue.size() < 2:
		var free_planet := _nearest_planet(base.global_position, game, func(p): return _known_free(pid, p, game))
		if miners.size() + base.queue.count("miner") < TARGET_MINERS:
			base.enqueue("miner")
		# (Not while it can't pay the skimmer's spice, or just after one was
		# cancelled for stalling: re-queueing it at once kept two unpayable
		# skimmers at the head of the queue and blocked every other build.)
		elif (giant or neb_spot != Vector2.INF) and game.has_tech(pid, "gas_skimming") and skimmers.size() + base.queue.count("skimmer") < 2 				and res["spice"] >= Defs.SHIPS["skimmer"]["cost"]["spice"] * 1.1 and Game.now() >= st.get("blocked", {}).get("skimmer", -1.0):
			base.enqueue("skimmer")
		# Jobs: a Scout for sensors, a Repair Tender once the fleet is sizable,
		# a Radiation Sail Array where the system has radiation hazards to fight in.
		# Always one Scout: it explores, then patrols.
		elif v and _count_role(ships, base, "scout") == 0 and base.can_queue("scout") == "":
			base.enqueue("scout")
		elif war.size() >= 8 and _count_type(ships, base, "tender") == 0 and base.can_queue("tender") == "" and res["spice"] >= 15.0:
			base.enqueue("tender")
		elif war.size() >= 6 and _hazardous(game) and _count_type(ships, base, "heatshield") == 0 and base.can_queue("heatshield") == "" and res["spice"] >= 15.0:
			base.enqueue("heatshield")
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

	# Skimmers: gas giants for minerals; one harvests spice gas in a known
	# spice nebula while spice is short (slow, but it never runs out).
	var on_neb := skimmers.filter(func(s): return s.mine_target is NebulaPocket).size()
	for s in skimmers:
		if neb_spot != Vector2.INF and on_neb == 0 and res["spice"] < 150.0 and not (s.mine_target is NebulaPocket):
			s.order_mine(game.nebula_pocket_at(neb_spot))
			on_neb += 1
		elif s.state == Ship.State.IDLE:
			if giant:
				s.order_mine(giant)
			elif neb_spot != Vector2.INF:
				s.order_mine(game.nebula_pocket_at(neb_spot))

	# Idle miners go back to work; one goes after spice when it's low.
	var on_spice := miners.filter(func(m): return is_instance_valid(m.mine_target) and m.mine_target.resource == "spice").size()
	for m in miners:
		if m.state == Ship.State.IDLE:
			# Spice gates colonies and bigger hulls: keep up to two miners on it
			# while it's short.
			var want := "spice" if res["spice"] < 150.0 and on_spice < 2 else "minerals"
			var rock := game.nearest_asteroid(m.global_position, 1600.0, want, v)
			if rock == null:
				rock = game.nearest_asteroid(m.global_position, 1600.0, "minerals", v)
			if rock:
				m.order_mine(rock)
				if rock.resource == "spice":
					on_spice += 1
	# Miners rarely go idle (a rock lasts a long time), so the idle check alone
	# left every miner on minerals while spice sat at zero. While spice is
	# short, move one busy mineral miner a tick onto a known spice rock.
	if res["spice"] < 150.0 and on_spice < 2:
		var rock := game.nearest_asteroid(base.global_position, 1600.0, "spice", v)
		if rock:
			for m in miners:
				if m.state in [Ship.State.MINE_GO, Ship.State.MINING] and is_instance_valid(m.mine_target) and m.mine_target.resource == "minerals":
					m.order_mine(rock)
					break

	# Develop planets: farms when food is falling, otherwise a rotating mix.
	var food_rate: float = game.rates[pid].get("food", 0.0)
	# Farms grow in proportion to fertility, so food goes where the soil is:
	# a poor world only farms if this side has nothing better.
	var best_soil := 0.0
	for p0 in game.get_tree().get_nodes_in_group("planets"):
		if p0.owner_id == pid and p0.free_fields() > 0:
			best_soil = maxf(best_soil, float(p0.type_def().get("fertility", 1.0)))
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.owner_id != pid or not p.construction.is_empty() or not p.construction_queue.is_empty() or p.free_fields() == 0:
			continue
		var pick := "farm"
		if food_rate > 0.01:
			var cycle := ["generator", "mine", "farm", "habitat"]
			pick = cycle[(p.fields - p.free_fields()) % cycle.size()]
			# Energy falling: power plants first.
			if game.rates[pid].get("energy", 0.0) < 0.06 and res["energy"] < 35.0:
				pick = "generator"
		# Spice short: an Extractor on a world with a real reserve, even while
		# food dips, as long as the larder has some slack.
		if (food_rate > 0.01 or res["food"] > 300.0) and res["spice"] < 150.0 and res["spice"] >= 15.0 and p.spice_reserve > 500.0 and p.count_building("spice_extractor") == 0:
			pick = "spice_extractor"
		if pick == "farm" and float(p.type_def().get("fertility", 1.0)) < best_soil * 0.6:
			pick = "generator"
		for i in p.fields:
			if p.order_build(i, pick) == "":
				break

	_scout(pid, st, game, ships.filter(func(s): return s.def["role"] == "scout") + war)
	_use_jobs(pid, ships, game)
	_expand_production(pid, st, game, base, ships)
	_manage_depot(pid, ships, base, game)
	# Frontier Outposts and Warp Gates (scripted AI only). Before the fleet
	# orders below, so ships it puts in a gate aren't also sent elsewhere.
	if nn == null:
		war = _manage_forts(pid, st, game, base, ships, war, all_war.size())

	# The learned commander decides builds and fleet moves itself.
	if nn != null:
		nn.tick(game, base, self)
		return

	# Defend: enemies near the starbase pull every warship home.
	var threat := game.nearest_enemy(base, 450.0)
	# Only enemies our sensors can actually see (not ones hidden in a nebula).
	if threat and v and not v.can_see(threat):
		threat = null
	if threat:
		for s in war:
			if s.state != Ship.State.ATTACK:
				s.order_attack_move(threat.global_position)
		return

	var idle := war.filter(func(s): return s.state == Ship.State.IDLE)
	# Idle warships next to an enemy planet start bombarding it (not a turtle).
	for s in (idle.duplicate() if not (game.rl_side > 0 and pid != game.rl_side and game.opp_level == 2) else []):
		var ep := _nearest_planet(s.global_position, game, func(pl): return pl.is_enemy_of(pid) and (v == null or v.is_visible_at(pl.global_position)))
		# Only a world the warships near it can actually bring down.
		if ep and s.global_position.distance_to(ep.global_position) < 350.0 and _can_win(pid, idle.filter(func(o): return o.global_position.distance_to(ep.global_position) < 500.0), ep.global_position, game):
			s.order_bombard(ep)
			idle.erase(s)
	# Aggressive: any idle group that can destroy something goes for it,
	# whatever the mode and whatever it costs (see _can_win).
	var need := 3
	# Training curriculum (see Game.opp_level): a turtle never attacks, a
	# slow opponent waits for a bigger wave.
	var vs_rl: bool = game.rl_side > 0 and pid != game.rl_side
	if vs_rl and game.opp_level == 3:
		need = 8
	if vs_rl and game.opp_level == 2:
		need = 1 << 30
	if idle.size() >= need:
		var goal := _winnable_target(pid, idle, base.global_position, game)
		if goal != Vector2.INF:
			for s in idle:
				s.order_attack_move(goal + Vector2(randf_range(-40, 40), randf_range(-40, 40)))
			# Radiation Sail Arrays (support, not warships) go with the wave to
			# screen it from radiation and soak fire with their solar shield.
			for rsa in ships.filter(func(s): return s.ship_type.ends_with("heatshield") and s.state == Ship.State.IDLE):
				rsa.order_move(goal + Vector2(randf_range(-80, 80), randf_range(-80, 80)))
			st["wave"] = mini(st["wave"] + 4, 30)
	# Waves already out pull back if their target has become too strong.
	_recall_losing_waves(pid, war, base, game)

## Which tech to start next. Unlocking a class or a depot beats upgrading
## what you already have, and a hull mark is only worth it once there is a
## fleet to apply it to — otherwise the AI spends its early energy making
## three corvettes slightly better while the enemy fields destroyers.
func _pick_tech(options: Array, fleet: int) -> String:
	var best := ""
	var best_score := -INF
	for t in options:
		var d: Dictionary = Defs.TECHS[t]
		var score := 0.0
		match d.get("group", "general"):
			"warships":
				# Unlocks (they have no "class") come first, then marks.
				score = 100.0 if not d.has("class") else 40.0 + minf(fleet, 12) * 2.0 - d["tier"] * 8.0
			"constructs":
				# What a construct UNLOCKS is worth far more than what it
				# improves, now that the line is more than one tech deep.
				score = 75.0 if d["effects"].keys().any(func(k): return k.begins_with("unlock")) else 48.0 - d["tier"] * 6.0
				# A Warp Gate moves a fleet: worth it only once there is one.
				if d["effects"].has("unlock_warp_gate") and fleet < 6:
					score = 30.0
			"weapons":
				# Weapons pay off in proportion to the fleet carrying them.
				score = 40.0 + minf(fleet, 12) * 1.8 - d["tier"] * 6.0
			"logistics", "worlds":
				score = 55.0 - d["tier"] * 5.0
			"defense":
				score = 35.0 + minf(fleet, 12) * 1.5 - d["tier"] * 6.0
			"mods":
				score = 46.0 + minf(fleet, 12) * 1.5
			_:
				score = 45.0 - d["tier"] * 5.0
		# Cheap things first when scores are close, and a little noise so two
		# AIs on the same map don't research in lockstep.
		score -= (d["cost"].get("energy", 0.0) / 45.0 + d["cost"].get("spice", 0.0) / 20.0)
		score += randf() * 6.0
		if score > best_score:
			best_score = score
			best = t
	return best

func _pick_warship(pid: int, game: Game, st: Dictionary = {}) -> String:
	# Any class it has unlocked, with no caps. The richer it is, the more it
	# leans to big hulls, which turn a stockpile into strength fastest.
	var options: Array[String] = ["corvette", "corvette", "destroyer", "destroyer", "cruiser", "carrier"]
	if float(game.resources[pid]["minerals"]) > SPARE_MINERALS * 2.0:
		options.append_array(["cruiser", "carrier", "carrier"])
	options.shuffle()
	var sb := game.nearest_starbase(pid, Vector2.ZERO)
	var res: Dictionary = game.resources[pid]
	# Stop growing the fleet once upkeep would outrun income.
	if game.rates[pid].get("energy", 0.0) < 0.06 and res["energy"] < 22.0:
		return ""
	for t in options:
		if st.get("corvettes_only", false) and Defs.SHIPS[t].get("base", t) != "corvette":
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

## A fleet only detours to an enemy world when it is this much closer than the
## enemy starbase (a fraction of the distance), so attacks reach the yards
## that build the enemy fleet instead of grinding on colonies along the way.
const DETOUR := 0.5
## Attack once our fleet is this much stronger than theirs.
const ATTACK_EDGE := 1.15
## This far ahead the AI goes for the kill: it attacks with whatever it has
## and heads for the nearest enemy world or starbase, since either one
## falling (with the rest) ends the match.
const FINISH_EDGE := 2.0

func _attack_goal(pid: int, from: Vector2, game: Game) -> Vector2:
	if _state.get(pid, {}).get("finishing", false):
		var kill := _finish_target(pid, from, game)
		if kill != Vector2.INF:
			return kill
	# The enemy starbase wins the match; a small enemy colony on the way is
	# fair game (big worlds take too long to bombard).
	var v: Vision = game.visions.get(pid)
	if v:
		# Fog of war: only targets we've seen. With no enemy starbase found
		# yet, head for the mirror image of our home (systems are point-
		# symmetric, so that's where the enemy most likely started).
		var kp := _nearest_planet(from, game, func(pl): return game.is_hostile(pid, v.known_owner(pl)) and v.seen_planet_pop.get(pl, 0.0) < 4000.0)
		var kb := v.known_enemy_base(from)
		var home := game.nearest_starbase(pid, Vector2.ZERO)
		# Starts are evenly spaced round the star: the next one along is the
		# nearest likely enemy home.
		var base_pos: Vector2 = kb[0] if not kb.is_empty() else (home.global_position.rotated(TAU / game.players.size()) if home else Vector2.ZERO)
		# Nothing hostile known and that guess already checked: sweep for
		# the leftovers instead of idling (see _scout_target).
		if kb.is_empty() and kp == null and v.is_visible_at(base_pos):
			var sc := _scout_target(pid, from, game, v)
			if sc != Vector2.INF:
				return sc
		if kp and from.distance_to(kp.global_position) < from.distance_to(base_pos) * DETOUR:
			return kp.global_position
		return base_pos
	var p := _nearest_planet(from, game, func(pl): return game.is_hostile(pid, pl.owner_id) and pl.pop < 4000.0)
	var enemy_base: Starbase = null
	for sb in game.get_tree().get_nodes_in_group("starbases"):
		if game.is_hostile(pid, sb.owner_id) and (enemy_base == null or from.distance_to(sb.global_position) < from.distance_to(enemy_base.global_position)):
			enemy_base = sb
	if p and (enemy_base == null or from.distance_to(p.global_position) < from.distance_to(enemy_base.global_position) * DETOUR):
		return p.global_position
	return enemy_base.global_position if enemy_base else from

## The nearest enemy world or finished starbase this player knows of (any
## size: when finishing, every one counts). INF if none is known.
func _finish_target(pid: int, from: Vector2, game: Game) -> Vector2:
	var v: Vision = game.visions.get(pid)
	var best := Vector2.INF
	var best_d := INF
	for p in game.get_tree().get_nodes_in_group("planets"):
		var owner_seen: int = v.known_owner(p) if v else p.owner_id
		if game.is_hostile(pid, owner_seen) and from.distance_to(p.global_position) < best_d:
			best_d = from.distance_to(p.global_position)
			best = p.global_position
	if v:
		var kb := v.known_enemy_base(from)
		if not kb.is_empty() and from.distance_to(kb[0]) < best_d:
			best = kb[0]
		if best == Vector2.INF:
			# Clean-up: the enemy's last worlds may be out of sight; go and look.
			best = _scout_target(pid, from, game, v)
	else:
		for sb in game.get_tree().get_nodes_in_group("starbases"):
			if game.is_hostile(pid, sb.owner_id) and from.distance_to(sb.global_position) < best_d:
				best_d = from.distance_to(sb.global_position)
				best = sb.global_position
	return best

## Where to look for hidden enemies: the nearest world that isn't ours or an
## ally's and isn't in sight right now (its owner may have changed since we
## last looked). INF if every world is in view.
func _scout_target(pid: int, from: Vector2, game: Game, v: Vision) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for p in game.get_tree().get_nodes_in_group("planets"):
		var ko: int = v.known_owner(p)
		if ko != 0 and game.are_allies(pid, ko):
			continue
		if v.is_visible_at(p.global_position):
			continue
		var d := from.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p.global_position
	return best

## A planet this player knows to be free (seen unclaimed); without fog, any
## unclaimed planet.
func _known_free(pid: int, p: Planet, game: Game) -> bool:
	var v: Vision = game.visions.get(pid)
	if v:
		return v.known_owner(p) == 0
	return p.owner_id == 0

## Scouting: one ship (a Scout, else the fastest warship) explores until the
## whole system is known, then patrols it for good (only with fog of war).
const SCOUT_UNTIL := 0.98   # "the whole system" (a few cells sit in rock fields/behind the star)

func _scout(pid: int, st: Dictionary, game: Game, war: Array) -> void:
	var v: Vision = game.visions.get(pid)
	if v == null or war.is_empty() or Game.now() < st.get("next_scout", 0.0):
		return
	st["next_scout"] = Game.now() + 5.0
	# (Untyped until checked: the old scout may have been destroyed.)
	var old = st.get("scout")
	var sc: Ship = old if is_instance_valid(old) else null
	if sc == null or not sc.is_alive():
		# A Scout if we have one, else the fastest warship (corvettes).
		var pick: Array = war.filter(func(s): return s.def["role"] == "scout")
		if pick.is_empty():
			pick = war.duplicate()
			pick.sort_custom(func(a, b): return a.def["speed"] > b.def["speed"])
		sc = pick[0]
		st["scout"] = sc
	var arrived: bool = sc.state == Ship.State.IDLE or sc.global_position.distance_to(sc.move_goal) < 60.0
	if v.explored_fraction() < SCOUT_UNTIL:
		# First uncover the whole system.
		if arrived or v.is_explored_at(sc.move_goal):
			sc.order_move(v.nearest_unexplored(sc.global_position))
	elif arrived:
		# Then patrol for good: round the system world by world, skipping
		# ours, allies' and any already in sight, so news of the enemy
		# (fleets, new colonies) stays current.
		var worlds: Array = game.get_tree().get_nodes_in_group("planets").filter(func(p): return not (p.owner_id != 0 and game.are_allies(pid, p.owner_id)))
		worlds.sort_custom(func(a, b): return a.global_position.angle() < b.global_position.angle())
		if worlds.is_empty():
			return
		var i: int = st.get("patrol_i", 0)
		for k in worlds.size():
			var w: Node2D = worlds[(i + k) % worlds.size()]
			if not v.is_visible_at(w.global_position) or k == worlds.size() - 1:
				st["patrol_i"] = (i + k + 1) % worlds.size()
				sc.order_move(w.global_position + Vector2.from_angle(randf() * TAU) * 220.0)
				break

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
		mine += s.max_hp + s.max_armor + s.max_shield
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
		if not game.is_hostile(pid, s.owner_id) or not s.is_alive() or s.def["role"] != "warship":
			continue
		theirs += s.max_hp + s.max_armor + s.max_shield
		if s.global_position.distance_to(base.global_position) < 900.0:
			threat = true
		else:
			for p in game.get_tree().get_nodes_in_group("planets"):
				if p.owner_id == pid and s.global_position.distance_to(p.global_position) < 500.0:
					threat = true
					break
	var res: Dictionary = game.resources[pid]
	var rates: Dictionary = game.rates[pid]
	var energy_starved: bool = res["energy"] < 7.0 and rates.get("energy", 0.0) < 0.0
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
	elif mine > theirs * ATTACK_EDGE and war.size() >= 8:
		mode = "attack"
	# Clearly winning: finish it, however small the fleet.
	elif mine > theirs * FINISH_EDGE and war.size() >= 2:
		mode = "attack"
	st["finishing"] = mine > theirs * FINISH_EDGE
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

# ---------------------------------------------------------------- jobs

func _count_type(ships: Array, base: Starbase, t: String) -> int:
	return ships.filter(func(s): return s.ship_type == t).size() + base.queue.count(t)

func _count_role(ships: Array, base: Starbase, role: String) -> int:
	var q := 0
	for t in base.queue:
		if Defs.SHIPS[t]["role"] == role:
			q += 1
	return ships.filter(func(s): return s.def["role"] == role).size() + q

## Systems where a Radiation Sail Array earns its keep: a spice nebula or twin suns.
func _hazardous(game: Game) -> bool:
	if not game.nebula_list.is_empty():
		return true
	return game.stars_list.any(func(s): return s.orbit_radius > 0.0)

## Uses ship abilities when the situation calls for them, and keeps Repair
## Tenders with the fleet.
func _use_jobs(pid: int, ships: Array, game: Game) -> void:
	var war := ships.filter(func(s): return s.def["role"] == "warship")
	var home := game.nearest_starbase(pid, Vector2.ZERO)
	for s in ships:
		match s.def.get("job", ""):
			"field_repair":
				if Abilities.ready_in(s) <= 0.0:
					var hurt := Abilities.allies_near(s, Abilities.EMERGENCY_RANGE).filter(func(o): return o.hp < o.max_hp * 0.6)
					if hurt.size() >= 3:
						Abilities.use(s)
				# Stay with the fleet: move to the warships' center.
				if not war.is_empty():
					var c := Vector2.ZERO
					for w in war:
						c += w.global_position
					c /= war.size()
					if s.global_position.distance_to(c) > 160.0 and (s.state == Ship.State.IDLE or s.global_position.distance_to(s.move_goal) > 200.0 or s.move_goal.distance_to(c) > 160.0):
						s.order_move(c)
			"beacon":
				# Leave a beacon deep in the field (far from home, none nearby).
				if Abilities.ready_in(s) <= 0.0 and home and s.global_position.distance_to(home.global_position) > 1200.0:
					var near := game.get_tree().get_nodes_in_group("beacons").any(func(b): return b.owner_id == pid and b.global_position.distance_to(s.global_position) < 600.0)
					if not near:
						Abilities.use(s)

## A harvest spot in the nearest spice nebula this player has explored, on
## the side facing `from`; Vector2.INF if it has explored none.
func _nebula_spot(from: Vector2, game: Game, v: Vision) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for n in game.get_tree().get_nodes_in_group("nebulae"):
		var p: Vector2 = n.heart_toward(from)
		if v != null and not v.is_explored_at(p):
			continue
		var d := from.distance_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best

## The corvette variant that best fits the enemy defenses seen so far (see
## Defs.VARIANTS), or "" when we haven't seen enough of their fleet.
## Whether to research Mod `t` now: the class is fielded (2+ hulls), has no
## Mod yet (none researched or in progress), and `t` is the one that fits.
func _mod_wanted(pid: int, game: Game, t: String, war: Array) -> bool:
	var cls: String = Defs.TECHS[t]["mod"]
	if war.filter(func(s): return s.def.get("base", s.ship_type) == cls).size() < 2:
		return false
	for id in Defs.TECHS:
		if Defs.TECHS[id].get("mod", "") == cls and game.tech_state(pid, id) in ["done", "active", "queued"]:
			return false
	return _pick_mod(pid, game, cls) == t

## The Mod for `cls` that suits the enemy warships this player has seen
## lately (its own sightings only - no cheating): big hulls, swarms of
## corvettes, or missile/torpedo/drone users each call for a different one.
func _pick_mod(pid: int, game: Game, cls: String) -> String:
	var v: Vision = game.visions.get(pid)
	var n := 0
	var small := 0
	var big := 0
	var ordnance := 0
	if v:
		for id in v.sightings:
			var sg: Array = v.sightings[id]
			if sg.size() < 6:
				continue
			n += 1
			if sg[4] == "corvette":
				small += 1
			elif sg[4] in ["cruiser", "carrier"]:
				big += 1
			if sg[5] in ["proton", "missile", "bomblet", "drones"]:
				ordnance += 1
	var fs := float(small) / maxf(n, 1)
	var fb := float(big) / maxf(n, 1)
	var fo := float(ordnance) / maxf(n, 1)
	var seen := n >= 3
	match cls:
		"corvette":
			return "mod_proton_torpedoes" if seen and fb >= 0.35 else ("mod_arc_emitters" if seen and fs >= 0.5 else "mod_kinetic_repeaters")
		"destroyer":
			return "mod_flak_cannons" if seen and fs >= 0.5 else ("mod_cluster_bombs" if seen and fb >= 0.35 else "mod_homing_missiles")
		"cruiser":
			return "mod_point_defense_lattice" if seen and fo >= 0.3 else ("mod_ion_lance" if seen and fb >= 0.35 else "mod_rail_cannons")
		"carrier":
			return "mod_interceptor_drones" if seen and fs >= 0.5 else ("mod_missile_barrage" if seen and fb >= 0.35 else "mod_tractor_beams")
	return ""

func _pick_variant(pid: int, game: Game) -> String:
	var v: Vision = game.visions.get(pid)
	if v == null:
		return ""
	# For every enemy warship seen lately, the base damage each variant needs
	# to destroy it (layer by layer, with its bonus / pierce and base damage)
	# vs a generalist; pick the variant with the lowest total.
	var seen: Array = []
	for id in v.sightings:
		var sg: Array = v.sightings[id]
		if sg.size() > 3:
			seen.append(sg[3])
	if seen.size() < 3:
		return ""
	var gen := 0.0
	for l in seen:
		gen += l.x + l.y + l.z
	var best := ""
	var best_cost := gen * 0.97
	for vid in Defs.VARIANTS:
		var vd: Dictionary = Defs.VARIANTS[vid]
		var vs: Dictionary = vd["vs"]
		var cost := 0.0
		for l in seen:
			var need: float = l.z / vs.get("hull", 1.0)
			if vd["pierce"] < 2:
				need += l.y / vs.get("armor", 1.0)
			if vd["pierce"] < 1:
				need += l.x / vs.get("shield", 1.0)
			cost += need / vd["damage"]
		if cost < best_cost:
			best_cost = cost
			best = vid
	return best

# ---------------------------------------------------------------- weapons depot

## Spend, don't hoard: when minerals pile up past SPARE_MINERALS, add as many
## starbases as the stockpile pays for (a mining station only where a worked
## rock lacks a drop-off and a starbase is out of reach), and keep every extra
## starbase building warships. One yard cannot turn a growing income into
## ships fast enough, which is what left AI fleets small and games stalled.
const SPARE_MINERALS := 1500.0

func _expand_production(pid: int, st: Dictionary, game: Game, base: Starbase, ships: Array) -> void:
	var res: Dictionary = game.resources[pid]
	var bases: Array = game.get_tree().get_nodes_in_group("starbases").filter(func(b): return b.owner_id == pid)
	# Every yard but the home one is a pure warship yard.
	for b in bases:
		if b == base or b.queue.size() >= 2 or st.get("mode", "") == "recover":
			continue
		var pick := _pick_warship(pid, game, st)
		if pick != "" and b.can_queue(pick) == "" and res["minerals"] >= Defs.SHIPS[pick]["cost"]["minerals"]:
			b.enqueue(pick)
	var stations: Array = game.get_tree().get_nodes_in_group("mining_stations").filter(func(m): return m.owner_id == pid)
	# Build a construct when minerals pile up (a starbase), or when a worked
	# rock has no drop-off and a station is affordable.
	var gap := _dropoff_gap(pid, game, ships, bases + stations)
	if res["minerals"] < SPARE_MINERALS and (gap == Vector2.INF or res["minerals"] < Defs.MINING_STATION["cost"]["minerals"]):
		return
	var builders := ships.filter(func(s): return s.def["role"] == "constructor")
	if builders.is_empty():
		if base.queue.count("constructor") == 0 and base.can_queue("constructor") == "":
			base.enqueue("constructor")
		return
	if builders.any(func(c): return c.state == Ship.State.BUILD):
		return
	var idle := builders.filter(func(c): return c.state == Ship.State.IDLE)
	if idle.is_empty():
		return
	# A starbase by default, as many as the stockpile pays for. Only when a
	# starbase is out of reach does it fall back to a mining station, and
	# only for a resource our harvesters are working with no drop-off nearby.
	var sb_cost: Dictionary = Defs.STARBASE["cost"]
	if res["minerals"] >= sb_cost["minerals"] and res["spice"] >= sb_cost.get("spice", 0):
		var site := _yard_site(pid, game, bases)
		if site != Vector2.INF:
			idle[0].order_build_starbase(site)
			return
	if res["minerals"] >= Defs.MINING_STATION["cost"]["minerals"]:
		if gap != Vector2.INF:
			idle[0].order_build_station(gap)

## Where a mining station is needed: beside a rock one of our harvesters is
## working that has no starbase or station within DROPOFF_NEAR. INF if every
## worked rock already has a drop-off close by.
const DROPOFF_NEAR := 700.0

func _dropoff_gap(pid: int, game: Game, ships: Array, drops: Array) -> Vector2:
	for s in ships:
		if not s.def["role"] in ["miner", "skimmer"] or not is_instance_valid(s.mine_target):
			continue
		var rock: Vector2 = s.mine_target.global_position
		if drops.any(func(d): return is_instance_valid(d) and d.global_position.distance_to(rock) < DROPOFF_NEAR):
			continue
		for r in [90.0, 140.0, 200.0]:
			for a in range(8):
				var q: Vector2 = rock + Vector2.from_angle(TAU * a / 8.0) * r
				if game.site_problem("station", q) == "":
					return q
	return Vector2.INF

## A legal starbase site beside one of our worlds that has no yard nearby.
func _yard_site(pid: int, game: Game, bases: Array) -> Vector2:
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.owner_id != pid or bases.any(func(b): return b.global_position.distance_to(p.global_position) < 700.0):
			continue
		for r in [160.0, 220.0, 280.0]:
			for a in [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]:
				var q: Vector2 = p.global_position + Vector2.from_angle(a) * r
				if game.starbase_site_problem(q) == "":
					return q
	# Every world has a yard: ring the yards we already have.
	for b in bases:
		for r in [260.0, 360.0, 460.0]:
			for a in range(12):
				var q2: Vector2 = b.global_position + Vector2.from_angle(TAU * a / 12.0) * r
				if game.starbase_site_problem(q2) == "":
					return q2
	return Vector2.INF

## Once the fleet is sizable: get a Constructor, build a Weapons Depot near
## home, then refit idle generalist corvettes near home into the variant
## that suits the enemy defenses seen so far (a few at a time).
func _manage_depot(pid: int, ships: Array, base: Starbase, game: Game) -> void:
	if not game.has_tech(pid, str(Defs.WEAPONS_DEPOT["requires"])):
		return
	var war := ships.filter(func(s): return s.def["role"] == "warship")
	var want := _pick_variant(pid, game)
	var depots: Array = game.get_tree().get_nodes_in_group("depots").filter(func(d): return d.owner_id == pid)
	var builders := ships.filter(func(s): return s.def["role"] == "constructor")
	# Each depot fits one variant, so build one for the variant our intel says
	# we want (and a second later if the enemy fleet changes).
	var have := depots.any(func(d): return d.variant == want)
	if want != "" and not have and depots.size() < 3:
		if war.size() >= 6 and builders.is_empty() and base.queue.count("constructor") == 0 and base.can_queue("constructor") == "":
			base.enqueue("constructor")
		for c in builders:
			if c.state == Ship.State.IDLE:
				var site := _depot_site(base.global_position, game)
				if site != Vector2.INF:
					c.order_build_depot(site, want)
				break
	# Send idle generalists to a finished depot: the one we want if it exists,
	# otherwise whatever we have.
	var depot: WeaponsDepot = game.nearest_depot(pid, base.global_position, want)
	if depot == null:
		depot = game.nearest_depot(pid, base.global_position)
	if depot == null:
		return
	var heading := ships.filter(func(s): return s.state == Ship.State.REFIT).size()
	for s in war:
		if heading + depot.bays.size() >= int(Defs.WEAPONS_DEPOT["capacity"]):
			break
		if s.state == Ship.State.IDLE and s.can_refit(depot.variant) and s.global_position.distance_to(base.global_position) < 1200.0 and randf() < 0.5:
			s.order_refit(depot.variant, depot)
			heading += 1

## A free spot for a depot a little way from home, toward the middle.
func _depot_site(home: Vector2, game: Game) -> Vector2:
	var dir := (-home).normalized() if home.length() > 1.0 else Vector2.RIGHT
	for r in [260.0, 340.0, 420.0]:
		for a in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, PI]:
			var p: Vector2 = home + dir.rotated(a) * r
			if game.depot_site_problem(p) == "":
				return p
	return Vector2.INF

# ---------------------------------------------------------------- fight sense
# The AI takes any fight it expects to win, however many ships it costs.
# A side's strength is its total damage per second times its total toughness
# (the duel tests show fights scaling that way); attackers must out-strength
# the defence by WIN_MARGIN squared (just over 1: winning at all is enough).

const WIN_MARGIN := 1.02
## Enemy ships counted as defending a target within this range of it.
const DEFEND_RANGE := 600.0
## Damage per second per point of toughness, for enemy ships known only by
## their size (fog of war): about the fleet average across the classes.
const DPS_PER_TOUGH := 0.04

func _ship_dps(s: Ship, game: Game) -> float:
	if s.def.get("weapon", "") == "":
		return 0.0
	return float(s.def["damage"]) * int(s.def.get("guns", 1)) / maxf(float(s.def["cooldown"]), 0.1) \
		* Defs.mark_mult(s.ship_type, game.mark_level(s.owner_id, s.ship_type)) * game.mod(s.owner_id, "damage")

## [dps, toughness] of whatever defends `at` for the enemies of `pid`: the
## starbase or world there plus enemy warships around it.
func _defence_at(pid: int, at: Vector2, game: Game) -> Vector2:
	var dps := 0.0
	var tough := 0.0
	for sb in game.get_tree().get_nodes_in_group("starbases"):
		if game.is_hostile(pid, sb.owner_id) and sb.global_position.distance_to(at) < 120.0:
			dps += Defs.STARBASE["damage"] / Defs.STARBASE["cooldown"]
			tough += sb.hp + sb.armor + sb.shield
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.is_enemy_of(pid) and p.global_position.distance_to(at) < 120.0:
			dps += p.count_building("battery") * Defs.BATTERY["damage"] / Defs.BATTERY["cooldown"]
			tough += p.shield + p.pop / Planet.POP_PER_DAMAGE
	var v: Vision = game.visions.get(pid)
	# Enemy Frontier Outposts covering the target (only ones we have seen).
	for f in (v.seen_forts.keys() if v else game.get_tree().get_nodes_in_group("forts")):
		if is_instance_valid(f) and f is FrontierOutpost and game.is_hostile(pid, f.owner_id) and f.global_position.distance_to(at) < 300.0:
			dps += Defs.FRONTIER_OUTPOST["damage"] / Defs.FRONTIER_OUTPOST["cooldown"]
			tough += f.hp + f.armor + f.shield
	if v:
		# Only what we have seen recently.
		for id in v.sightings:
			var sg: Array = v.sightings[id]
			if Game.now() - sg[0] < 30.0 and at.distance_to(sg[2]) < DEFEND_RANGE:
				tough += sg[1]
				dps += sg[1] * DPS_PER_TOUGH
	else:
		for s in game.get_tree().get_nodes_in_group("ships"):
			if game.is_hostile(pid, s.owner_id) and s.def["role"] == "warship" and s.global_position.distance_to(at) < DEFEND_RANGE:
				tough += s.hp + s.armor + s.shield
				dps += _ship_dps(s, game)
	return Vector2(dps, tough)

## True if `ships` should beat what defends `at` with ships to spare.
func _can_win(pid: int, ships: Array, at: Vector2, game: Game) -> bool:
	var dps := 0.0
	var tough := 0.0
	for s in ships:
		dps += _ship_dps(s, game)
		tough += s.hp + s.armor + s.shield
	var d := _defence_at(pid, at, game)
	return dps * tough > d.x * d.y * WIN_MARGIN * WIN_MARGIN and dps > 0.0

## The nearest enemy starbase or world (that we know of) `ships` can take,
## or INF if none: no attack is launched then.
func _winnable_target(pid: int, ships: Array, from: Vector2, game: Game) -> Vector2:
	var v: Vision = game.visions.get(pid)
	var spots: Array = []
	for p in game.get_tree().get_nodes_in_group("planets"):
		var o: int = v.known_owner(p) if v else p.owner_id
		if o > 0 and o != pid:
			spots.append(p.global_position)
	if v:
		for sb in v.seen_bases:
			spots.append(v.seen_bases[sb][0])
	else:
		for sb in game.get_tree().get_nodes_in_group("starbases"):
			if game.is_hostile(pid, sb.owner_id):
				spots.append(sb.global_position)
	spots.sort_custom(func(a, b): return from.distance_to(a) < from.distance_to(b))
	for at in spots:
		if _can_win(pid, ships, at, game):
			return at
	return Vector2.INF

## Attack-moving warships heading for a fight they would now lose come home.
func _recall_losing_waves(pid: int, war: Array, base: Starbase, game: Game) -> void:
	var groups := {}
	for s in war:
		if s.state == Ship.State.ATTACK_MOVE:
			var key := Vector2i((s.move_goal / 200.0).round())
			if not groups.has(key):
				groups[key] = []
			groups[key].append(s)
	for key in groups:
		var g: Array = groups[key]
		var at: Vector2 = g[0].move_goal
		if not _can_win(pid, g, at, game):
			for s in g:
				s.order_move(base.global_position + Vector2(randf_range(-80, 80), randf_range(-80, 80)))

# ---------------------------------------------------------------- forts
# Frontier Outposts hold exposed ground (worlds, stations and worked belts far
# from any starbase, on the side facing the enemy); a Warp Gate near home
# garrisons the idle fleet and flings it at a target it has seen and can
# beat, or at its own territory under attack. Same costs, sites and
# information (its own Vision) as a player.

## Seconds between outpost orders, and the most it keeps at once.
const OUTPOST_EVERY := 150.0
const OUTPOST_MAX := 4
## A world / station / belt this far from every own starbase is "exposed".
const EXPOSED := 900.0
## Warships in a gate before it warps them at a target.
const GATE_WAVE := 5
## The longest ships wait in a gate with nothing to warp at, and how long
## they then stay out before the gate takes them again.
const GATE_HOLD := 120.0
const GATE_REST := 60.0
## Where a warped wave lands: this far short of its target, outside its guns.
const WARP_STANDOFF := 650.0

## SL_AI_FORTS_LOG=1: one "AIFORT" line per outpost / gate decision.
func _flog(pid: int, msg: String) -> void:
	if OS.get_environment("SL_AI_FORTS_LOG") != "":
		print("AIFORT t=%d P%d %s" % [int(Game.now()), pid, msg])

## Returns `war` without the ships it sent into a gate this tick.
func _manage_forts(pid: int, st: Dictionary, game: Game, base: Starbase, ships: Array, war: Array, fleet: int) -> Array:
	var v: Vision = game.visions.get(pid)
	var forts: Array = game.get_tree().get_nodes_in_group("forts").filter(func(f): return f.owner_id == pid and f.is_alive())
	var builders := ships.filter(func(s): return s.def["role"] == "constructor")
	if OS.get_environment("SL_AI_FORTS_LOG") != "":
		var done: Dictionary = st.get("forts_done", {})
		for f in forts:
			if not f.under_construction and not done.has(f.get_instance_id()):
				done[f.get_instance_id()] = true
				_flog(pid, "%s finished at (%d,%d)" % [f.label(), f.global_position.x, f.global_position.y])
		st["forts_done"] = done
	# The gate first: it is the one that needs saving up for.
	if game.has_tech(pid, str(Defs.WARP_GATE["requires"])):
		_plan_gate(pid, st, game, base, forts, builders, fleet)
	if game.has_tech(pid, str(Defs.FRONTIER_OUTPOST["requires"])):
		_plan_outpost(pid, st, game, base, forts, builders.filter(func(c): return c.state != Ship.State.IDLE or not st.get("gate_wants_builder", false)), v, fleet)
	return _use_gates(pid, st, game, forts, war, v)

## An idle Constructor, or null (then one is queued if none exists).
func _idle_builder(base: Starbase, builders: Array) -> Ship:
	for c in builders:
		if c.state == Ship.State.IDLE:
			return c
	if builders.is_empty() and base.queue.count("constructor") == 0 and base.can_queue("constructor") == "":
		base.enqueue("constructor")
	return null

## Spare energy for one more construct's upkeep (per minute).
func _upkeep_ok(pid: int, game: Game, upkeep_per_min: float) -> bool:
	return game.rates[pid].get("energy", 0.0) > 0.06 + upkeep_per_min / 60.0 or game.resources[pid]["energy"] > 250.0

## Enemy starbases and worlds this player knows of (its own Vision).
func _enemy_spots(pid: int, game: Game, v: Vision) -> Array:
	var spots: Array = []
	for p in game.get_tree().get_nodes_in_group("planets"):
		var o: int = v.known_owner(p) if v else p.owner_id
		if o > 0 and o != pid and game.is_hostile(pid, o):
			spots.append(p.global_position)
	if v:
		for sb in v.seen_bases:
			spots.append(v.seen_bases[sb][0])
	else:
		for sb in game.get_tree().get_nodes_in_group("starbases"):
			if game.is_hostile(pid, sb.owner_id):
				spots.append(sb.global_position)
	return spots

func _plan_outpost(pid: int, st: Dictionary, game: Game, base: Starbase, forts: Array, builders: Array, v: Vision, fleet: int) -> void:
	if Game.now() < st.get("next_outpost", 0.0) or st.get("mode", "") == "recover" or st.get("threat", false):
		return
	var d: Dictionary = Defs.FRONTIER_OUTPOST
	var res: Dictionary = game.resources[pid]
	# Never at the cost of the fleet: a fleet first, and the bill (paid over
	# the build) in hand with a little to spare.
	if fleet < 4 or res["minerals"] < d["cost"]["minerals"] + 150.0 or res["spice"] < d["cost"]["spice"] + 30.0 or not _upkeep_ok(pid, game, d["upkeep"]):
		return
	var pending := builders.filter(func(c): return c.state == Ship.State.BUILD and c.build_kind == "outpost")
	var have: int = forts.filter(func(f): return f is FrontierOutpost).size() + pending.size()
	var worlds: int = game.get_tree().get_nodes_in_group("planets").filter(func(p): return p.owner_id == pid).size()
	# One to start; another every 7 minutes and per two worlds, up to OUTPOST_MAX.
	var cap := mini(OUTPOST_MAX, mini(1 + int(Game.now() / 420.0), 1 + worlds / 2))
	if have >= cap:
		return
	var taken: Array = forts.map(func(f): return f.global_position) + pending.map(func(c): return c.build_site)
	var site := _outpost_site(pid, game, base, taken, v)
	if site == Vector2.INF:
		st["next_outpost"] = Game.now() + 30.0
		return
	var c := _idle_builder(base, builders)
	if c == null:
		return
	c.order_build_fort(site, "outpost")
	st["next_outpost"] = Game.now() + OUTPOST_EVERY
	_flog(pid, "outpost ordered at (%d,%d) (%d/%d)" % [site.x, site.y, have + 1, cap])

## A legal outpost site guarding the most exposed thing we own: a world,
## Mining Station or worked rock far from every own starbase, nearest the
## known enemy, with no fort of ours near it yet. Placed on its enemy side.
func _outpost_site(pid: int, game: Game, base: Starbase, taken: Array, v: Vision) -> Vector2:
	var enemy := _enemy_spots(pid, game, v)
	var anchors: Array = []
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.owner_id == pid:
			anchors.append(p.global_position)
	for m in game.get_tree().get_nodes_in_group("mining_stations"):
		if m.owner_id == pid:
			anchors.append(m.global_position)
	for s in game.get_tree().get_nodes_in_group("ships"):
		if s.owner_id == pid and s.def["role"] in ["miner", "skimmer"] and is_instance_valid(s.mine_target):
			anchors.append(s.mine_target.global_position)
	var best := Vector2.INF
	var best_score := INF
	# Exposed holdings first; with none, the front line: whatever we hold
	# nearest the known enemy (the outpost then goes out in front of it).
	var reach := 300.0
	for pass_i in 2:
		if best != Vector2.INF or (pass_i == 1 and enemy.is_empty()):
			break
		if pass_i == 1:
			reach = 420.0
		for a in anchors:
			var yard := game.nearest_starbase(pid, a, true)
			if pass_i == 0 and yard and yard.global_position.distance_to(a) < EXPOSED:
				continue
			if taken.any(func(t): return t.distance_to(a) < 700.0):
				continue
			if v and v.enemy_near(a, 700.0) > 0:
				continue
			# Nearest the enemy we know of; with none known, farthest from home.
			var score: float = -a.distance_to(base.global_position)
			if not enemy.is_empty():
				score = INF
				for e in enemy:
					score = minf(score, a.distance_to(e))
			if score < best_score:
				best_score = score
				best = a
	if best == Vector2.INF:
		return Vector2.INF
	# On the enemy side of it (or the side away from home).
	var toward := (best - base.global_position).normalized()
	if not enemy.is_empty():
		enemy.sort_custom(func(x, y): return best.distance_to(x) < best.distance_to(y))
		toward = (enemy[0] - best).normalized()
	for r in [reach - 130.0, reach - 70.0, reach]:
		for ang in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, PI]:
			var q: Vector2 = best + toward.rotated(ang) * r
			if game.site_problem("outpost", q) == "":
				return q
	return Vector2.INF

func _plan_gate(pid: int, st: Dictionary, game: Game, base: Starbase, forts: Array, builders: Array, fleet: int) -> void:
	st["gate_wants_builder"] = false
	if st.get("mode", "") == "recover" or st.get("threat", false):
		return
	var d: Dictionary = Defs.WARP_GATE
	var res: Dictionary = game.resources[pid]
	var gates := forts.filter(func(f): return f is WarpGate)
	var pending := builders.filter(func(c): return c.state == Ship.State.BUILD and c.build_kind == "gate")
	var n: int = gates.size() + pending.size()
	# One gate; a second only late in a long, rich game.
	var rich: bool = Game.now() > 1800.0 and res["minerals"] > 6000.0
	if n >= 2 or (n >= 1 and not rich) or not pending.is_empty():
		return
	# The bill is paid over the build, so half of it in hand will do.
	if fleet < 6 or res["minerals"] < d["cost"]["minerals"] * 0.5 or res["spice"] < d["cost"]["spice"] + 60.0 or not _upkeep_ok(pid, game, d["upkeep"]):
		return
	# Beside home (a second beside another yard, well away from the first).
	var yard: Node2D = base
	if not gates.is_empty():
		var far := -1.0
		for b in game.get_tree().get_nodes_in_group("starbases"):
			var dg: float = b.global_position.distance_to(gates[0].global_position)
			if b.owner_id == pid and dg > far:
				far = dg
				yard = b
		if far < 1500.0:
			return
	var site := Vector2.INF
	var dir := (-yard.global_position).normalized() if yard.global_position.length() > 1.0 else Vector2.RIGHT
	for r in [300.0, 400.0, 520.0]:
		for ang in [0.6, -0.6, 1.2, -1.2, 0.0, 2.0, -2.0, PI]:
			var q: Vector2 = yard.global_position + dir.rotated(ang) * r
			if site == Vector2.INF and game.site_problem("gate", q) == "":
				site = q
	if site == Vector2.INF:
		return
	var c := _idle_builder(base, builders)
	st["gate_wants_builder"] = c == null
	if c == null:
		return
	c.order_build_fort(site, "gate")
	_flog(pid, "gate ordered at (%d,%d)" % [site.x, site.y])

## `q` pulled onto the gate's reach: a point beyond warp_max is stepped
## back along the gate->q line to just inside it (the wave lands there and
## flies the rest), one closer than warp_min pushed out to it.
func _clamp_warp(g: WarpGate, q: Vector2) -> Vector2:
	var d: Dictionary = Defs.WARP_GATE
	var off := q - g.global_position
	if off.length() < 1.0:
		return q
	return g.global_position + off.normalized() * clampf(off.length(), float(d["warp_min"]) + 50.0, float(d["warp_max"]) - 50.0)

## A landing point WARP_STANDOFF short of `target` on the gate's side
## (stepped in to the gate's reach if the target is further), clear of
## stars and debris; INF if none.
func _landing(target: Vector2, g: WarpGate, game: Game) -> Vector2:
	var back := (g.global_position - target).normalized()
	for ang in [0.0, 0.4, -0.4, 0.8, -0.8]:
		var q: Vector2 = _clamp_warp(g, target + back.rotated(ang) * WARP_STANDOFF)
		if q.length() > Game.MAP_RADIUS - 150.0 or game.is_blocked(q, 40.0):
			continue
		if game.stars_list.any(func(s): return s.global_position.distance_to(q) < s.radiation_radius + 80.0):
			continue
		if g.warp_problem(q) == "":
			return q
	return Vector2.INF

## Warps gate `g`'s garrison to `at`; once landed they attack-move on `goal`.
func _warp_wave(pid: int, st: Dictionary, g: WarpGate, at: Vector2, goal: Vector2, why: String) -> bool:
	var out := g.ships().duplicate()
	if g.warp(at) != "":
		return false
	var w: Array = st.get("warped", [])
	for s in out:
		w.append([s, goal, Game.now() + 90.0])
	st["warped"] = w
	st["gate_since"].erase(g.get_instance_id())
	_flog(pid, "WARP %s: %d ships %d px to (%d,%d), goal (%d,%d)" % [why, out.size(), int(g.global_position.distance_to(at)), at.x, at.y, goal.x, goal.y])
	return true

## Runs every finished gate: defend, attack, release, then fill it with idle
## warships near it. Returns `war` minus the ships just sent in.
func _use_gates(pid: int, st: Dictionary, game: Game, forts: Array, war: Array, v: Vision) -> Array:
	if not st.has("gate_since"):
		st["gate_since"] = {}
	# Warped waves that have landed attack-move on their goal.
	var w: Array = st.get("warped", [])
	var landed := 0
	for i in range(w.size() - 1, -1, -1):
		var s = w[i][0]
		if not is_instance_valid(s) or not s.is_alive() or Game.now() > w[i][2]:
			w.remove_at(i)
		elif not s.warping:
			if s.state == Ship.State.IDLE:
				s.order_attack_move(w[i][1] + Vector2(randf_range(-40, 40), randf_range(-40, 40)))
				landed += 1
			w.remove_at(i)
	if landed > 0:
		_flog(pid, "landed: %d ships attack-moving on their goal" % landed)
	var mode: String = st.get("mode", "")
	# Our own worlds and starbases with enemies at them (that we can see).
	var hurt: Array = []
	if v:
		for e in game.get_tree().get_nodes_in_group("starbases") + game.get_tree().get_nodes_in_group("planets"):
			if e.owner_id == pid and v.enemy_near(e.global_position, 600.0) > 0:
				hurt.append(e.global_position)
	for g in forts:
		if not (g is WarpGate) or not g.is_open():
			continue
		var inside: Array = g.ships()
		var key: int = g.get_instance_id()
		if inside.is_empty():
			st["gate_since"].erase(key)
		elif not st["gate_since"].has(key):
			st["gate_since"][key] = Game.now()
		if not inside.is_empty():
			# Defend: territory under attack far away gets the garrison;
			# an attack right by the gate gets it ejected to fight.
			var done := false
			for h in hurt:
				if g.global_position.distance_to(h) < Defs.WARP_GATE["warp_min"] + 200.0:
					g.eject_all()
					st["gate_since"].erase(key)
					st["gate_rest"] = Game.now() + 30.0
					_flog(pid, "eject: enemies near the gate (%d ships)" % inside.size())
					done = true
					break
				if g.cooldown_left <= 0.0:
					var land: Vector2 = _clamp_warp(g, h + (g.global_position - h).normalized() * 250.0)
					if g.warp_problem(land) == "" and _warp_wave(pid, st, g, land, h, "defend"):
						done = true
						break
			if done:
				continue
			# Attack: a known target the garrison can beat, far enough to warp.
			if g.cooldown_left <= 0.0 and inside.size() >= GATE_WAVE and mode != "recover":
				var goal := _winnable_target(pid, inside, g.global_position, game)
				if goal != Vector2.INF:
					var land2 := _landing(goal, g, game)
					if land2 != Vector2.INF and _warp_wave(pid, st, g, land2, goal, "attack"):
						st["wave"] = mini(st["wave"] + 4, 30)
						continue
			# Nothing worth warping at for a while: let them out.
			if Game.now() - float(st["gate_since"].get(key, Game.now())) > GATE_HOLD:
				g.eject_all()
				st["gate_since"].erase(key)
				st["gate_rest"] = Game.now() + GATE_REST
				_flog(pid, "eject: held %ds with no target (%d ships)" % [int(GATE_HOLD), inside.size()])
				continue
		# Fill it: idle warships near the gate go in (not while home is under
		# attack, recovering, or resting after a release).
		if st.get("threat", false) or mode == "recover" or Game.now() < st.get("gate_rest", 0.0) 				or hurt.any(func(h): return g.global_position.distance_to(h) < Defs.WARP_GATE["warp_min"] + 200.0):
			continue
		var sent: Array = []
		for s in war:
			if s.state == Ship.State.IDLE and s.global_position.distance_to(g.global_position) < 1400.0:
				s.order_garrison(g)
				sent.append(s)
		if not sent.is_empty():
			_flog(pid, "garrison: %d ships sent in (%d inside)" % [sent.size(), inside.size()])
			war = war.filter(func(s): return not sent.has(s))
	return war
