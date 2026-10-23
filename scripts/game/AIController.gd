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


# ======================================================================
# COORDINATOR
# ======================================================================
# Runs each side once a second: builds the shared Ctx, then calls the
# protocols in a fixed order (situation -> research -> production ->
# economy -> construction -> preservation -> defense -> military). A protocol
# that takes ships (defense, preservation, gates) runs before the ones that
# would otherwise give them other orders.

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
		_flee_blasts(pid, game)

## Everything one planning tick of one side shares between protocols.
class Ctx:
	var pid: int
	var st: Dictionary
	var game: Game
	var base: Starbase
	var res: Dictionary
	var ships: Array
	var miners: Array
	var skimmers: Array
	var v: Vision
	var giant: Planet
	var neb_spot: Vector2
	var war: Array
	var all_war: Array
	var colonists: Array
	var nn
	var mode: String

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
	var giant := _safe_giant(pid, base.global_position, game, v)
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
	var c := Ctx.new()
	c.pid = pid
	c.st = st
	c.game = game
	c.base = base
	c.res = res
	c.ships = ships
	c.miners = miners
	c.skimmers = skimmers
	c.v = v
	c.giant = giant
	c.neb_spot = neb_spot
	c.war = war
	c.all_war = all_war
	c.colonists = colonists
	_debug_log(c)
	# Enemies just spotted near home: re-plan now instead of at the next
	# scheduled rethink.
	if v and not st.get("threat", false) and v.enemy_near(base.global_position, 900.0) > 0:
		st["next_rethink"] = 0.0
	_note_builders(pid, st, game, v)
	var nn = st.get("nn")   # NeuralCommander or RLAgent: both have tick()
	if nn == null:
		_rethink(pid, st, game, base, all_war)
		_update_reserve(pid, st, game, all_war.size())
	_manage_queues(pid, st, game, base)
	c.nn = nn
	var mode: String = st.get("mode", "expand")
	c.mode = mode

	_research_protocol(c)
	_production_home_yard(c)
	_expansion_colonize(c)
	_economy_harvesters(c)
	_economy_worlds(c)
	_economy_power(c)

	if nn == null:
		# Preservation protocol: leave fights not worth their cost; retreating
		# and peeled-off ships take no other orders (see _preserve).
		_preserve(pid, st, game, base, war, v)
		war = war.filter(func(s): return not _held_back(st, s))
		_guard_harvesters(pid, st, game, war, ships, v)
	_scout(pid, st, game, ships.filter(func(s): return s.def["role"] == "scout") + war)
	_use_jobs(pid, ships, game, st)
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

	c.war = war
	if _defense_protocol(c):
		return
	_military_protocol(c)

## Coordinator: SL_AI_DEBUG / SL_AI_BUDGET_LOG lines.
func _debug_log(cx: Ctx) -> void:
	var pid: int = cx.pid
	var st: Dictionary = cx.st
	var game: Game = cx.game
	var base: Starbase = cx.base
	var res: Dictionary = cx.res
	var war: Array = cx.war
	var all_war: Array = cx.all_war
	var mode: String = cx.mode
	if OS.get_environment("SL_AI_DEBUG") != "" and int(Game.now()) % 20 == 0:
		print("AIDBG t=%d pid=%d mode=%s queue=%s stalled=%s stall=%s blocked=%s prog=%.1f" % [Game.now(), pid, st.get("mode", ""), str(base.queue), str(base.build_stalled), str(st.get("stall", 0)), str(st.get("blocked", {})), base.build_progress])
	# SL_AI_BUDGET_LOG=1: one "AIBUD" line per side a minute (budget / attack state).
	if OS.get_environment("SL_AI_BUDGET_LOG") != "" and Game.now() >= st.get("next_budlog", 0.0):
		st["next_budlog"] = Game.now() + 60.0
		var qs := []
		for b in game.get_tree().get_nodes_in_group("starbases"):
			if b.owner_id == pid:
				qs.append("%s%s" % ["*" if b.under_construction else "", ",".join(b.queue)])
		print("AIBUD t=%d P%d mode=%s M=%d S=%d E=%d emargin=%.0f umult=%.2f reserve=%s capped=%s commit=%s rally=%s war=%d yards=[%s] research=%s %s cover=%s cov_on_s=%d cov_spent=%d demol=%d ow=%s assaults=%d waves_lost=%d mass_s=%d" % [
			Game.now(), pid, st.get("mode", ""), res["minerals"], res["spice"], res["energy"], _energy_margin(pid, game), game.upkeep_multiplier(pid),
			st.get("reserve_for", ""), str(st.get("upkeep_capped", false)), str(st.get("commit", false)), str(st.has("rally")), all_war.size(), " | ".join(qs), str(game.research[pid].get("id", "-")), st.get("commit_dbg", ""),
			"on" if game.spice_cover_on(pid) else "off", int(st.get("cover_on_s", 0.0)), int(st.get("cover_spent", 0.0)), st.get("demolished", 0), str(st.get("overwhelm", false)), st.get("assaults", 0), st.get("assault_waves_lost", 0), int(st.get("assault_mass_s", 0.0))])
		# Colonization: colony ships by state, and every free habitable world
		# with whether this side knows it is free and how far it is.
		var cst := {}
		for c in cx.colonists:
			var k: String = Ship.State.keys()[c.state]
			cst[k] = cst.get(k, 0) + 1
		var fw := []
		for p in game.get_tree().get_nodes_in_group("planets"):
			if p.owner_id <= 0 and p.is_habitable():
				fw.append("%s:%s:%d" % [p.planet_name, "known" if _known_free(pid, p, game) else "unknown", int(base.global_position.distance_to(p.global_position))])
		print("AIBUD   P%d colonists=%s free_worlds=[%s]" % [pid, str(cst), " ".join(fw)])
		if st.get("commit", false) and st.has("commit_target"):
			var ct: Vector2 = st["commit_target"]
			var hist := {}
			for s in all_war:
				var k := "%s%s" % [Ship.State.keys()[s.state], "@front" if s.global_position.distance_to(ct) < FRONT else ""]
				hist[k] = hist.get(k, 0) + 1
			for s in all_war:
				if s.state == Ship.State.BOMBARD and is_instance_valid(s.bombard_target):
					var bt: Planet = s.bombard_target
					var k2 := "bomb:%s(o%d pop%d d%d)" % [bt.planet_name, bt.owner_id, int(bt.pop), int(s.global_position.distance_to(bt.global_position))]
					hist[k2] = hist.get(k2, 0) + 1
				elif s.state == Ship.State.ATTACK and is_instance_valid(s.target):
					var k3 := "atk:%s" % s.target.get_class() if not (s.target is Starbase) else "atk:yard"
					hist[k3] = hist.get(k3, 0) + 1
			var tp := _nearest_planet(ct, game, func(_pl): return true)
			print("AIBUD   P%d target (%d,%d) winnable=%s states=%s planet=%s owner=%d pop=%d shield=%d" % [pid, ct.x, ct.y, str(st.get("commit_winnable", true)), str(hist),
				tp.planet_name if tp else "-", tp.owner_id if tp else -1, tp.pop if tp else 0, tp.shield if tp else 0])

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

## A gas giant or world counting down to its blast: every ship of ours inside
## it (plus a margin) runs straight out, whatever it was doing. Called after
## the rest of the AI's orders so nothing sends it back in. Stations can't move.
func _flee_blasts(pid: int, game: Game) -> void:
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.doom_timer < 0.0:
			continue
		var r: float = p.blast_radius() + 120.0
		for s in game.get_tree().get_nodes_in_group("ships"):
			if s.owner_id != pid or not s.is_alive() or s.docked or s.warping:
				continue
			var off: Vector2 = s.global_position - p.global_position
			if off.length() < r:
				var out: Vector2 = p.global_position + (off.normalized() if off.length() > 1.0 else Vector2.RIGHT) * (r + 60.0)
				if s.move_goal.distance_to(out) > 40.0 or s.state != Ship.State.MOVE:
					s.order_move(out)

# Frontier Outposts hold exposed ground (worlds, stations and worked belts far
# from any starbase, on the side facing the enemy); a Warp Gate near home
# garrisons the idle fleet and flings it at a target it has seen and can
# beat, or at its own territory under attack. Same costs, sites and
# information (its own Vision) as a player.

## Seconds between outpost orders, and the most it keeps at once.
const OUTPOST_EVERY := 150.0

const OUTPOST_MAX := 5

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


# ======================================================================
# INTEL / SCOUTING
# ======================================================================
# What this side knows: its own Vision only (sensors + memory), never hidden
# state. One Scout explores then patrols; enemy mix, builders and holdings
# are remembered with decay.

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
		var worlds: Array = game.get_tree().get_nodes_in_group("planets").filter(func(p): return not (v.known_owner(p) > 0 and game.are_allies(pid, v.known_owner(p))))
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

## The matchup side our `cls` ships fight as right now (its active Mod).
func _our_side(pid: int, game: Game, cls: String) -> int:
	var slot: int = SIDE_MODS.get(cls, []).find(game.active_mod(pid, cls))
	return _side_index(cls, maxi(slot, 0))

## The enemy fleet mix as this side remembers it: {side index: weight}.
## Each warship seen counts 1, halving every MIX_HALF_LIFE since last seen;
## one seen destroyed (gone from where it was, see Vision) is dropped.
func _enemy_mix(pid: int, st: Dictionary, game: Game) -> Dictionary:
	var v: Vision = game.visions.get(pid)
	var mem: Dictionary = st.get("mix_mem", {})
	var now := Game.now()
	if v:
		for id in v.sightings:
			var sg: Array = v.sightings[id]
			if sg.size() < 6:
				continue
			var cls := str(sg[4])
			var slot: int = SEEN_WEAPON_SLOT.get(cls, {}).get(str(sg[5]), 0)
			mem[id] = [_side_index(cls, slot), float(sg[0]), sg[3]]
		for id in mem.keys():
			# Vision forgets a ship after a while, or at once when seen gone:
			# inside its memory window, a missing one was seen destroyed.
			if not v.sightings.has(id) and now - float(mem[id][1]) < Vision.SIGHTING_MEMORY - 1.0:
				mem.erase(id)
			elif now - float(mem[id][1]) > MIX_HALF_LIFE * 5.0:
				mem.erase(id)
	st["mix_mem"] = mem
	var mix := {}
	for id in mem:
		var i: int = mem[id][0]
		if i >= 0:
			mix[i] = mix.get(i, 0.0) + pow(0.5, (now - float(mem[id][1])) / MIX_HALF_LIFE)
	return mix

## Short text of the mix's top sides (logs).
func _mix_text(mix: Dictionary) -> String:
	var keys := mix.keys()
	keys.sort_custom(func(a, b): return mix[a] > mix[b])
	var parts := []
	for k in keys.slice(0, 4):
		var cls: String = SIDE_CLASSES[int(k) / 4]
		var m: String = SIDE_MODS[cls][int(k) % 4]
		parts.append("%s%s:%.1f" % [cls, "" if m == "" else "/" + m.trim_prefix("mod_"), mix[k]])
	return ",".join(parts)

## Each rethink: refresh the mix, and switch researched Mods off (back to
## lasers) where the laser does clearly better against it, on again where
## the Mod does.
func _counter_update(pid: int, st: Dictionary, game: Game) -> void:
	var mix := _enemy_mix(pid, st, game)
	st["mix"] = mix
	if _mix_weight(mix) < MIX_MIN:
		return
	for cls in SIDE_CLASSES:
		for slot in range(1, 4):
			var m: String = SIDE_MODS[cls][slot]
			if not game.has_tech(pid, m):
				continue
			var off: bool = game.mods_disabled.get(pid, {}).has(m)
			var with_mod := _side_score(_side_index(cls, slot), mix)
			var laser := _side_score(_side_index(cls, 0), mix)
			if (not off and laser > with_mod + 0.25) or (off and with_mod > laser + 0.1):
				game.toggle_mod(pid, m)
				_flog(pid, "counter: %s %s %s (mod %.2f vs laser %.2f; seen %s)" % [cls, m, "OFF" if not off else "ON", with_mod, laser, _mix_text(mix)])

## Enemy warships seen within `r` of `pos` in the last `secs` seconds.
func _enemy_seen_near(v: Vision, pos: Vector2, r: float, secs: float) -> bool:
	var now := Game.now()
	for id in v.sightings:
		var sg: Array = v.sightings[id]
		if now - sg[0] < secs and pos.distance_to(sg[2]) < r:
			return true
	return false

## No commitment before this (game seconds), with fewer warships than
## COMMIT_MIN, or unless this much stronger than everything known.
const COMMIT_AFTER := 600.0

const COMMIT_MIN := 8

const COMMIT_EDGE := 1.3

## Committed: stay in until strength falls below this share of the enemy's.
const COMMIT_DROP := 0.7

## How much a known enemy construct's hull counts toward enemy strength.
const COMMIT_CONSTRUCT_SHARE := 0.25

## The most starbases' worth of known constructs counted toward that.
const COMMIT_CONSTRUCT_CAP := 2.0

## Ships within this of the target are "at the front".
const FRONT := 1400.0

## A committed army that can't yet take its target waits this far short of it.
const STAGE_BACK := 900.0

## Hull + armor + shield of the enemy starbases and outposts this player has seen.
func _known_constructs(pid: int, game: Game, v: Vision) -> float:
	var t := 0.0
	var sbt: float = Defs.STARBASE["hp"] + Defs.STARBASE["armor"] + Defs.STARBASE["shield"]
	if v:
		for sb in v.seen_bases:
			t += sbt * float(v.seen_bases[sb][1])
		for f in v.seen_forts:
			t += (Defs.FRONTIER_OUTPOST["hp"] + Defs.FRONTIER_OUTPOST["armor"] + Defs.FRONTIER_OUTPOST["shield"]) * float(v.seen_forts[f][1])
	else:
		for sb in game.get_tree().get_nodes_in_group("starbases"):
			if game.is_hostile(pid, sb.owner_id):
				t += sb.hp + sb.armor + sb.shield
	return t

## Enemy Constructors in sight are remembered (where, when) for a minute:
## with the enemy's yards gone they are what keeps it in the game.
func _note_builders(pid: int, st: Dictionary, game: Game, v: Vision) -> void:
	var mem: Dictionary = st.get("seen_builders", {})
	for s in game.get_tree().get_nodes_in_group("ships"):
		if game.is_hostile(pid, s.owner_id) and s.is_alive() and s.def["role"] == "constructor" and (v == null or v.can_see(s)):
			mem[s.get_instance_id()] = [s.global_position, Game.now()]
	for id in mem.keys():
		var gone: bool = v != null and v.is_visible_at(mem[id][0]) and _visible_builder(pid, id, Game.instance, v) == null
		if Game.now() - float(mem[id][1]) > 60.0 or gone:
			mem.erase(id)
	st["seen_builders"] = mem

## An enemy Constructor we can see right now, as a node (null if not).
func _visible_builder(_pid: int, id: int, _game: Game, v: Vision) -> Ship:
	if id == 0 or not is_instance_id_valid(id):
		return null
	var s = instance_from_id(id)
	if s is Ship and s.is_alive() and (v == null or v.can_see(s)):
		return s
	return null

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


# ======================================================================
# PRODUCTION
# ======================================================================
# What the yards build: support hulls, warship class / variant / Mod by
# counter-value against the seen enemy mix, extra yards and stations, the
# savings reserve, and the upkeep brake.

## PRODUCTION protocol: needs -> budget buckets -> the home yard's best item.
## Bucket weights start at PROD_BASE and shift with the situation this side
## can see: under threat -> military; safe but behind on worlds -> economy and
## expansion; clearly ahead -> military to close the game.
const PROD_BASE := {"military": 1.0, "economy": 1.1, "expansion": 1.0, "support": 0.6}
const PROD_THREAT_MIL := 2.0
const PROD_BEHIND_ECO := 1.5
const PROD_AHEAD_MIL := 1.5
## Own warship toughness over the known enemy fleet's that counts as ahead.
const PROD_AHEAD_RATIO := 1.5
## Spare minerals above SPARE_MINERALS: warships score this much higher.
const PROD_RICH_MULT := 2.5
## The single Scout outranks everything while it is missing.
const PROD_SCOUT_SCORE := 10.0
## A savings goal (starbase / gate) may hold back hulls this long before it
## is dropped for SAVE_COOLDOWN seconds, so ships keep flowing.
const SAVE_DEADLINE := 150.0
const SAVE_COOLDOWN := 90.0
## Upkeep-capped with this many spare minerals: the excess goes into Power
## Plants. The first REPLACE_RESERVE stays banked to rebuild lost hulls.
const REPLACE_RESERVE := 600.0
const CAPPED_POWER_MINERALS := 800.0 + REPLACE_RESERVE

func _budget_weights(pid: int, st: Dictionary, game: Game, v: Vision) -> Dictionary:
	var w: Dictionary = PROD_BASE.duplicate()
	var mine: float = st.get("mine_power", 0.0)
	var theirs: float = st.get("theirs_power", 0.0)
	var own_w := 0
	var their_w := 0
	for p in game.get_tree().get_nodes_in_group("planets"):
		var o: int = v.known_owner(p) if v else p.owner_id
		if o == pid:
			own_w += 1
		elif o > 0 and game.is_hostile(pid, o):
			their_w += 1
	if st.get("threat", false):
		w["military"] *= PROD_THREAT_MIL
	elif their_w > own_w:
		w["economy"] *= PROD_BEHIND_ECO
		w["expansion"] *= PROD_BEHIND_ECO
	if mine > maxf(theirs, 400.0) * PROD_AHEAD_RATIO:
		w["military"] *= PROD_AHEAD_MIL
	return w

## PRODUCTION protocol (home yard): the support hulls and warships the
## home starbase queues, in priority order.
func _production_home_yard(cx: Ctx) -> void:
	var pid: int = cx.pid
	var st: Dictionary = cx.st
	var game: Game = cx.game
	var base: Starbase = cx.base
	var res: Dictionary = cx.res
	var ships: Array = cx.ships
	var miners: Array = cx.miners
	var skimmers: Array = cx.skimmers
	var v: Vision = cx.v
	var giant: Planet = cx.giant
	var neb_spot: Vector2 = cx.neb_spot
	var war: Array = cx.war
	var colonists: Array = cx.colonists
	var nn = cx.nn
	var mode: String = cx.mode
	# The learned commander builds for itself.
	if nn != null or base.queue.size() >= 2:
		return
	var w := _budget_weights(pid, st, game, v)
	st["budget"] = w
	# Candidates for the home yard, each scored bucket weight x urgency;
	# the best affordable one is queued (other yards build warships).
	var cands: Array = []   # [score, item]
	# Intel: exactly one Scout - built only while none is alive or queued.
	if v and _count_role(ships, base, "scout") == 0 and base.can_queue("scout") == "":
		cands.append([PROD_SCOUT_SCORE, "scout"])
	var target := _target_miners(pid, st, game, v)
	var have_m: int = miners.size() + base.queue.count("miner")
	if have_m < target:
		cands.append([w["economy"] * (1.0 + float(target - have_m) / maxf(target, 1)), "miner"])
	# (Not while it can't pay the skimmer's spice, or just after one was
	# cancelled for stalling: re-queueing it at once kept two unpayable
	# skimmers at the head of the queue and blocked every other build.)
	if (giant or neb_spot != Vector2.INF) and game.has_tech(pid, "gas_skimming") and skimmers.size() + base.queue.count("skimmer") < (3 if st.get("crust_low", false) else 2) \
			and Game.now() >= st.get("blocked", {}).get("skimmer", -1.0):
		cands.append([w["economy"] * 0.9, "skimmer"])
	# Support: a Repair Tender once the fleet is sizable (two for a fortress
	# assault), a Radiation Sail Array where radiation hazards are fought in.
	if war.size() >= (4 if st.get("overwhelm", false) else 8) and _count_type(ships, base, "tender") < (2 if st.get("overwhelm", false) else 1) and base.can_queue("tender") == "":
		cands.append([w["support"], "tender"])
	if war.size() >= 6 and _hazardous(game) and _count_type(ships, base, "heatshield") == 0 and base.can_queue("heatshield") == "":
		cands.append([w["support"] * 0.8, "heatshield"])
	# A colony ship waits on a free world inside a spice nebula: an escort.
	elif st.get("want_escort", false) and _count_type(ships, base, "heatshield") == 0 and base.can_queue("heatshield") == "":
		cands.append([w["expansion"] * 1.2, "heatshield"])
	# Expansion: keep colonizing unless enemies are at our worlds.
	var free_planet := _nearest_planet(base.global_position, game, func(p): return _known_free(pid, p, game) and p.is_habitable())
	if free_planet and mode != "recover" and not st.get("threat", false) and colonists.size() + base.queue.count("colony") < 2:
		cands.append([w["expansion"] * 1.2, "colony"])
	# Military: the counter-picked class, if the minerals above the
	# savings goal cover half of it (it pays the rest while it builds).
	if mode != "recover" and not _yard_besieged(pid, st, base, v):
		var pick := _pick_warship(pid, game, st)
		var spare := _spare(pid, st, game, "minerals")
		if pick != "" and spare >= Defs.SHIPS[pick]["cost"]["minerals"] * 0.5:
			# Minerals piling up: warships ahead of everything but the scout.
			cands.append([w["military"] * (PROD_RICH_MULT if spare > SPARE_MINERALS else 1.0), pick])
	if cands.is_empty():
		return
	cands.sort_custom(func(a, b): return a[0] > b[0])
	base.enqueue(cands[0][1])

func _pick_warship(pid: int, game: Game, st: Dictionary = {}) -> String:
	# Any class it has unlocked, with no caps. The richer it is, the more it
	# leans to big hulls, which turn a stockpile into strength fastest.
	var options: Array[String] = ["corvette", "corvette", "destroyer", "destroyer", "cruiser", "carrier"]
	if float(game.resources[pid]["minerals"]) > SPARE_MINERALS * 2.0:
		options.append_array(["cruiser", "carrier", "carrier"])
	options.shuffle()
	# Upkeep is multiplied empire-wide per unit, so once the multiplier is
	# high, one big hull adds far less upkeep per point of strength than a
	# handful of small ones: biggest first then.
	if game.upkeep_multiplier(pid) >= BIG_HULLS_MULT:
		options = ["carrier", "cruiser", "destroyer", "corvette"]
	# Counter-picking: once enough of the enemy fleet has been seen, order
	# the classes by how they fare against it (see _class_order).
	var counter := _class_order(pid, game, st)
	if not counter.is_empty():
		options = counter
	var sb := game.nearest_starbase(pid, Vector2.ZERO)
	var res: Dictionary = game.resources[pid]
	var capped := true
	for t in options:
		# The only brake on spending: energy income must cover the upkeep this
		# hull adds (its own plus the multiplier it puts on everything else).
		if not _upkeep_fits(pid, game, Defs.SHIPS[t]["upkeep"], Defs.UPKEEP_WEIGHT.get(t, Defs.UPKEEP_WEIGHT_SMALL)):
			continue
		capped = false
		# Recently cancelled for stalling: give it a minute.
		if Game.now() < st.get("blocked", {}).get(t, -1.0):
			continue
		if sb.can_queue(t) == "":
			st["upkeep_capped"] = false
			return t
	st["upkeep_capped"] = capped
	return ""

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
	# The other yards likewise (a hull stalled on spice there blocked that
	# yard for good, with minerals piling up behind it).
	if not st.has("ystall"):
		st["ystall"] = {}
	for b in game.get_tree().get_nodes_in_group("starbases"):
		if b == base or b.owner_id != pid:
			continue
		var yk := str(b.get_instance_id())
		if b.build_stalled and not b.queue.is_empty():
			st["ystall"][yk] = st["ystall"].get(yk, 0.0) + 1.0
			if st["ystall"][yk] >= STALL_CANCEL:
				if not st.has("blocked"):
					st["blocked"] = {}
				st["blocked"][b.queue[0]] = Game.now() + 60.0
				b.cancel(0)
				st["ystall"][yk] = 0.0
		else:
			st["ystall"][yk] = 0.0
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
	# Enough seen: the Mod whose measured duels go best against the mix.
	var mix: Dictionary = _state.get(pid, {}).get("mix", {})
	if _mix_weight(mix) >= MIX_MIN and SIDE_MODS.has(cls):
		var best := ""
		var best_sc := -INF
		for slot in range(1, 4):
			var sc := _side_score(_side_index(cls, slot), mix)
			if sc > best_sc:
				best_sc = sc
				best = SIDE_MODS[cls][slot]
		return best
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
	# For every enemy warship remembered (decaying with time since seen; its
	# defense layers as seen), how much base damage each variant needs to
	# destroy it relative to a generalist (Defs.kill_ratio), weighted by its
	# toughness; the variant with the lowest total, if clearly better.
	var mem: Dictionary = _state.get(pid, {}).get("mix_mem", {})
	if mem.size() < 3:
		return ""
	var now := Game.now()
	var tot := 0.0
	var by := {}
	for id in mem:
		var l = mem[id][2]
		if not (l is Vector3):
			continue
		var w: float = pow(0.5, (now - float(mem[id][1])) / MIX_HALF_LIFE) * (l.x + l.y + l.z)
		tot += w
		var tgt := {"shield": l.x, "armor": l.y, "hp": l.z}
		for vid in Defs.VARIANTS:
			by[vid] = by.get(vid, 0.0) + w * Defs.kill_ratio(tgt, vid)
	if tot <= 0.0:
		return ""
	var best := ""
	var best_r := 0.93
	for vid in by:
		var r: float = by[vid] / tot
		if r < best_r:
			best_r = r
			best = vid
	var st: Dictionary = _state.get(pid, {})
	if best != st.get("last_variant", "") and best != "":
		st["last_variant"] = best
		_flog(pid, "counter: depot variant %s (kill cost x%.2f of a generalist; seen %s)" % [best, best_r, _mix_text(st.get("mix", {}))])
	return best

# What it builds, which Mod each class carries (research and on/off) and
# which variant its depot fits follow the enemy warships it has SEEN (its
# own Vision, remembered with decay), scored with the measured side-vs-side
# duel results in data/matchups.json. Before contact: the defaults.

## data/matchups.json sides, in order: class, then its laser and three Mods.
const SIDE_CLASSES := ["corvette", "destroyer", "cruiser", "carrier"]

const SIDE_MODS := {
	"corvette": ["", "mod_kinetic_repeaters", "mod_arc_emitters", "mod_proton_torpedoes"],
	"destroyer": ["", "mod_flak_cannons", "mod_cluster_bombs", "mod_homing_missiles"],
	"cruiser": ["", "mod_ion_lance", "mod_rail_cannons", "mod_point_defense_lattice"],
	"carrier": ["", "mod_interceptor_drones", "mod_tractor_beams", "mod_missile_barrage"],
}

## What a Mod's ships visibly fire (Vision sightings): weapon -> slot in SIDE_MODS.
## Point-Defense and Tractor Beams look like lasers from outside.
const SEEN_WEAPON_SLOT := {
	"corvette": {"kinetic": 1, "arc": 2, "proton": 3},
	"destroyer": {"flak": 1, "bomblet": 2, "missile": 3},
	"cruiser": {"beam": 1, "rail": 2},
	"carrier": {"drones": 1, "missile": 3},
}

## Seconds over which a remembered enemy warship's weight halves.
const MIX_HALF_LIFE := 360.0

## Seen-weight needed before it counter-picks at all.
const MIX_MIN := 3.0

static var _matchups: Array = []

static func _weights() -> Array:
	if _matchups.is_empty():
		var f := FileAccess.open("res://data/matchups.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary and d.has("weights"):
				_matchups = d["weights"]
		if _matchups.is_empty():
			_matchups = [[]]
	return _matchups

static func _side_index(cls: String, slot: int) -> int:
	var c := SIDE_CLASSES.find(cls)
	return -1 if c < 0 else c * 4 + slot

## How side `side` fares against the mix: weighted mean duel weight, -1..1.
func _side_score(side: int, mix: Dictionary) -> float:
	var w: Array = _weights()
	if side < 0 or side >= w.size():
		return 0.0
	var tot := 0.0
	var acc := 0.0
	for j in mix:
		var x = w[side][j] if j < w[side].size() else null
		tot += mix[j]
		acc += mix[j] * (float(x) if x != null else 0.0)
	return acc / tot if tot > 0.0 else 0.0

static func _mix_weight(mix: Dictionary) -> float:
	var t := 0.0
	for j in mix:
		t += mix[j]
	return t

## Classes in the order to build them against the enemy mix seen (best
## first, by duel weight with a little noise and, under a high upkeep
## multiplier, a lean to big hulls); hard-countered classes dropped while
## anything decent is unlocked. Empty before enough contact.
func _class_order(pid: int, game: Game, st: Dictionary) -> Array[String]:
	var mix: Dictionary = st.get("mix", {})
	var out: Array[String] = []
	if _mix_weight(mix) < MIX_MIN:
		return out
	var scored := []
	var big := game.upkeep_multiplier(pid) >= BIG_HULLS_MULT
	for i in SIDE_CLASSES.size():
		var cls: String = SIDE_CLASSES[i]
		if Defs.SHIPS[cls].has("requires") and not game.has_tech(pid, str(Defs.SHIPS[cls]["requires"])):
			continue
		var sc := _side_score(_our_side(pid, game, cls), mix)
		# A Mod it could still pick for this class lifts it a little.
		if game.active_mod(pid, cls) == "":
			var best_mod := sc
			for slot in range(1, 4):
				best_mod = maxf(best_mod, _side_score(_side_index(cls, slot), mix))
			sc = sc * 0.7 + best_mod * 0.3
		scored.append([cls, sc + randf() * 0.25 + (i * 0.08 if big else 0.0), sc])
	scored.sort_custom(func(a, b): return a[1] > b[1])
	var decent: bool = scored.any(func(x): return x[2] > -0.2)
	for x in scored:
		if decent and x[2] < -0.5:
			continue
		out.append(x[0])
	if Game.now() >= st.get("next_counter_log", 0.0) and not out.is_empty():
		st["next_counter_log"] = Game.now() + 120.0
		_flog(pid, "counter: seen %s -> build order %s" % [_mix_text(mix), str(scored.map(func(x): return "%s %.2f" % [x[0], x[2]]))])
	return out

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
	# (Every yard builds in parallel, from whatever is above the reserve; a
	# yard with enemies at it that it can't hold builds nothing - its new
	# hulls would die as they launch.)
	var v: Vision = game.visions.get(pid)
	for b in bases:
		if b == base or b.under_construction or b.queue.size() >= 2 or st.get("mode", "") == "recover" or _yard_besieged(pid, st, b, v):
			continue
		var pick := _pick_warship(pid, game, st)
		if pick != "" and b.can_queue(pick) == "" and _spare(pid, st, game, "minerals") >= Defs.SHIPS[pick]["cost"]["minerals"] * 0.5:
			b.enqueue(pick)
	var stations: Array = game.get_tree().get_nodes_in_group("mining_stations").filter(func(m): return m.owner_id == pid)
	# Build a construct when the budget is saving for a starbase and has it
	# in hand, or when a worked rock has no drop-off and a station is
	# affordable.
	var gap := _dropoff_gap(pid, game, ships, bases + stations)
	var want_yard: bool = st.get("reserve_for", "") == "starbase" and res["minerals"] >= Defs.STARBASE["cost"]["minerals"] * 0.6
	if not want_yard and (gap == Vector2.INF or _spare(pid, st, game, "minerals") < Defs.MINING_STATION["cost"]["minerals"]):
		return
	var builders := ships.filter(func(s): return s.def["role"] == "constructor")
	var sb_cost: Dictionary = Defs.STARBASE["cost"]
	var pending: Array = builders.filter(func(c): return c.state == Ship.State.BUILD and c.build_kind == "starbase")
	# Yards are the throughput limit (one hull at a time each), so when the
	# stockpile pays for several, several go up at once - one Constructor
	# each (up to four Constructors).
	var yards_paid := int((float(res["minerals"]) - pending.size() * float(sb_cost["minerals"]) * 0.6) / (float(sb_cost["minerals"]) * 0.6))
	if want_yard and yards_paid >= 2 and builders.filter(func(c): return c.state == Ship.State.IDLE).is_empty() \
			and builders.size() < 4 and base.queue.count("constructor") == 0 and base.can_queue("constructor") == "":
		base.enqueue("constructor")
	if builders.is_empty():
		if base.queue.count("constructor") == 0 and base.can_queue("constructor") == "":
			base.enqueue("constructor")
		return
	var idle := builders.filter(func(c): return c.state == Ship.State.IDLE)
	if idle.is_empty():
		return
	# A starbase by default, as many as the stockpile pays for. Only when a
	# starbase is out of reach does it fall back to a mining station, and
	# only for a resource our harvesters are working with no drop-off nearby.
	if want_yard and yards_paid >= 1 and bases.size() + pending.size() < MAX_YARDS:
		var taken: Array = bases.map(func(b): return b.global_position) + pending.map(func(c): return c.build_site)
		var site := _yard_site(pid, game, taken)
		if site != Vector2.INF:
			idle[0].order_build_starbase(site)
			_flog(pid, "starbase ordered at (%d,%d) (%d yards, %d going up)" % [site.x, site.y, bases.size(), pending.size() + 1])
			return
	if builders.any(func(c): return c.state == Ship.State.BUILD):
		return
	if stations.size() < MAX_STATIONS and _spare(pid, st, game, "minerals") >= Defs.MINING_STATION["cost"]["minerals"] and gap != Vector2.INF \
			and (v == null or not _enemy_seen_near(v, gap, 900.0, 60.0)) \
			and _upkeep_fits(pid, game, Defs.MINING_STATION["upkeep"], Defs.UPKEEP_WEIGHT_SMALL):
		idle[0].order_build_station(gap)

# Spend everything above the reserve for the next big purchase (a starbase
# or a Warp Gate), continuously. The one brake is upkeep: nothing that adds
# upkeep is bought once energy income would no longer cover it. Then the
# spare goes to what adds none or raises income instead: Power Plants,
# Defense Batteries, research, refits.

## Upkeep multiplier from which the AI builds its biggest hulls first.
const BIG_HULLS_MULT := 2.5

## Never more than this many starbases at a time (built or going up): past
## this, minerals go into the fleet instead.
const MAX_YARDS := 4
## Other construct caps (at a time, built or going up).
const MAX_GATES := 1
const MAX_STATIONS := 4

## Energy per minute left after upkeep (research spending added back: it
## is optional, and counting it would block ships while a project runs).
func _energy_margin(pid: int, game: Game) -> float:
	var r: float = game.rates[pid].get("energy", 0.0) * Defs.PER_MIN
	var cur: Dictionary = game.research[pid]
	if not cur.is_empty() and not cur.get("stalled", false):
		var t: Dictionary = Defs.TECHS[cur["id"]]
		r += float(t["cost"].get("energy", 0.0)) / float(t["time"]) * Defs.PER_MIN
	return r

## Upkeep per minute one more unit (own upkeep `u`, multiplier weight `w`,
## energy it makes `income` per minute) adds: its own upkeep plus the
## multiplier it puts on everything already owned.
func _added_upkeep(pid: int, game: Game, u: float, w: float, income: float = 0.0) -> float:
	var m := game.upkeep_multiplier(pid)
	var base := game.base_upkeep(pid)
	# Hulls already queued in our yards will add theirs too: count them as owned.
	var m2 := m
	var base2 := base
	for sb in game.get_tree().get_nodes_in_group("starbases"):
		if sb.owner_id == pid:
			for t in sb.queue:
				base2 += float(Defs.SHIPS[t]["upkeep"])
				m2 *= Defs.UPKEEP_WEIGHT.get(Defs.SHIPS[t].get("base", t), Defs.UPKEEP_WEIGHT_SMALL)
	return m2 * w * (base2 + u) - m * base - income

## True if energy income still covers that unit's upkeep - or the stockpile
## can carry the shortfall for ten minutes.
func _upkeep_fits(pid: int, game: Game, u: float, w: float, income: float = 0.0) -> bool:
	var add := _added_upkeep(pid, game, u, w, income)
	if add <= 0.0:
		return true
	var margin := _energy_margin(pid, game)
	return margin - add > 1.0 or float(game.resources[pid]["energy"]) > maxf(add - margin, 0.0) * 10.0 + 80.0

## What is left of resource `k` after the reserve for the next big purchase
## (and, for minerals, a couple of minutes of Power Plant fuel: minerals now
## pay for energy, and spice never covers fuel).
func _spare(pid: int, st: Dictionary, game: Game, k: String) -> float:
	# (At 0 minerals every Power Plant stops: always keep some fuel back.)
	var fuel := maxf(game.fuel_per_min(pid) * FUEL_MINUTES, 60.0) if k == "minerals" else 0.0
	return float(game.resources[pid].get(k, 0.0)) - float(st.get("reserve", {}).get(k, 0.0)) - fuel

## Picks the next big purchase to save toward (st["reserve_for"]) and how
## much of each resource to hold back for it (st["reserve"]). A Warp Gate
## once researched and there is a fleet to move; otherwise another starbase
## while minerals still pile up faster than the yards can spend them.
func _update_reserve(pid: int, st: Dictionary, game: Game, fleet: int) -> void:
	var res: Dictionary = game.resources[pid]
	var mode: String = st.get("mode", "")
	var pick := ""
	var calm: bool = mode != "recover" and not st.get("threat", false)
	var bases: Array = game.get_tree().get_nodes_in_group("starbases").filter(func(b): return b.owner_id == pid)
	var builders: Array = game.get_tree().get_nodes_in_group("ships").filter(func(s): return s.owner_id == pid and s.def["role"] == "constructor")
	var forts: Array = game.get_tree().get_nodes_in_group("forts").filter(func(f): return f.owner_id == pid and f is WarpGate)
	# (Not while far ahead and assaulting: reinforcements come first.)
	if calm and not st.get("overwhelm", false) and game.has_tech(pid, str(Defs.WARP_GATE["requires"])) and forts.is_empty() and fleet >= 6 \
			and not builders.any(func(c): return c.state == Ship.State.BUILD and c.build_kind == "gate") \
			and _upkeep_fits(pid, game, Defs.WARP_GATE["upkeep"], Defs.UPKEEP_WEIGHT["starbase"]):
		pick = "gate"
	elif mode != "recover" and bases.size() < MAX_YARDS \
			and (st.get("reserve_for", "") == "starbase" or (float(res["minerals"]) > SPARE_MINERALS and game.rates[pid].get("minerals", 0.0) > 0.0)) \
			and _upkeep_fits(pid, game, Defs.STARBASE["upkeep"], Defs.UPKEEP_WEIGHT["starbase"]) \
			and _yard_site(pid, game, bases.map(func(b): return b.global_position)) != Vector2.INF:
		pick = "starbase"
	# Savings goals have a deadline: one not reached in SAVE_DEADLINE is
	# dropped for SAVE_COOLDOWN so the yards keep building meanwhile.
	if Game.now() < st.get("save_block_until", -1.0):
		pick = ""
	elif pick == "":
		st.erase("save_since")
	else:
		if pick != st.get("reserve_for", "") or not st.has("save_since"):
			st["save_since"] = Game.now()
		var cost: Dictionary = Defs.WARP_GATE["cost"] if pick == "gate" else Defs.STARBASE["cost"]
		if float(res["minerals"]) < float(cost["minerals"]) and Game.now() - float(st["save_since"]) > SAVE_DEADLINE:
			_flog(pid, "savings for %s dropped after %ds (minerals %d)" % [pick, int(SAVE_DEADLINE), int(res["minerals"])])
			st["save_block_until"] = Game.now() + SAVE_COOLDOWN
			st.erase("save_since")
			pick = ""
	st["reserve_for"] = pick
	st["reserve"] = (Defs.WARP_GATE["cost"] if pick == "gate" else Defs.STARBASE["cost"] if pick == "starbase" else {}).duplicate()

## Spare energy for one more construct's upkeep (per minute).
func _upkeep_ok(pid: int, game: Game, upkeep_per_min: float) -> bool:
	return game.rates[pid].get("energy", 0.0) > 0.06 + upkeep_per_min / 60.0 or game.resources[pid]["energy"] > 250.0


# ======================================================================
# RESEARCH
# ======================================================================
# Research never idles; scored by group, Mods only where they fit.

## RESEARCH protocol: research never idles; Mods only for fielded classes
## and the one intel says fits; otherwise _pick_tech scores by group.
func _research_protocol(cx: Ctx) -> void:
	var pid: int = cx.pid
	var st: Dictionary = cx.st
	var game: Game = cx.game
	var res: Dictionary = cx.res
	var war: Array = cx.war
	var all_war: Array = cx.all_war
	var nn = cx.nn
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
			if Defs.TECHS[tech].has("mod"):
				_flog(pid, "counter: research %s (seen %s)" % [tech, _mix_text(st.get("mix", {}))])
			if Defs.TECHS[tech].get("group", "") == "constructs":
				_flog(pid, "research %s" % tech)

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


# ======================================================================
# ECONOMY / EXPANSION
# ======================================================================
# Harvesters to work, colonies to free worlds, world fields, Power Plants only
# while energy is short (and paused while a pile covers the shortfall),
# crusts kept, spice cover.

## EXPANSION protocol: colony ships settle the nearest known free world.
func _expansion_colonize(cx: Ctx) -> void:
	var pid: int = cx.pid
	var game: Game = cx.game
	var colonists: Array = cx.colonists
	var st: Dictionary = cx.st
	st["want_escort"] = false
	for c in colonists:
		var escorted: bool = c.has_meta("escort") and is_instance_valid(c.get_meta("escort"))
		if escorted and c.state == Ship.State.COLONIZE:
			# Keep the escort's radiation bubble over the colony ship.
			var rsa: Ship = c.get_meta("escort")
			rsa.order_move(c.global_position + (c.colonize_target.global_position - c.global_position).limit_length(20.0))
			continue
		if c.state == Ship.State.IDLE or c.state == Ship.State.MOVE:
			var p := _nearest_planet(c.global_position, game, func(pl): return _known_free(pid, pl, game) and pl.is_habitable())
			if p == null:
				continue
			# A world inside a spice nebula: its radiation kills a lone colony
			# ship, so it goes under a Radiation Sail Array's bubble.
			if not game.in_nebula(p.global_position):
				c.order_colonize(p)
				continue
			var rsa := _escort_for(pid, c, game)
			if rsa == null:
				st["want_escort"] = true
				continue
			c.set_meta("escort", rsa)
			rsa.set_meta("escorting", c)
			if rsa.global_position.distance_to(c.global_position) > ESCORT_JOIN:
				# Meet up outside the nebula first.
				rsa.order_move(c.global_position)
				if c.state != Ship.State.IDLE:
					c.order_move(c.global_position)
			else:
				c.order_colonize(p)

## Radiation Sail Array within this distance of its colony ship: they go in.
const ESCORT_JOIN := 40.0

## True while this Radiation Sail Array escorts a live colony ship.
func _escorting(s: Ship) -> bool:
	return s.has_meta("escorting") and is_instance_valid(s.get_meta("escorting"))

## A Radiation Sail Array free to escort colony ship c (already on it, or
## not with the fleet), nearest first.
func _escort_for(pid: int, c: Ship, game: Game) -> Ship:
	var best: Ship = null
	for s in game.get_tree().get_nodes_in_group("ships"):
		if s.owner_id != pid or not s.is_alive() or not s.ship_type.ends_with("heatshield"):
			continue
		var on = s.get_meta("escorting") if s.has_meta("escorting") else null
		if on == c:
			return s
		if is_instance_valid(on):
			continue
		if best == null or s.global_position.distance_to(c.global_position) < best.global_position.distance_to(c.global_position):
			best = s
	return best

## ECONOMY protocol (harvesting): skimmers and miners to work, spice first
## while it is short, away from unstable gas giants.
func _economy_harvesters(cx: Ctx) -> void:
	var pid: int = cx.pid
	var game: Game = cx.game
	var base: Starbase = cx.base
	var miners: Array = cx.miners
	var skimmers: Array = cx.skimmers
	var v: Vision = cx.v
	var giant: Planet = cx.giant
	var neb_spot: Vector2 = cx.neb_spot
	# Skimmers: gas giants for minerals; one harvests spice gas in a known
	# spice nebula while spice is short (nebulae are finite: depleted ones are skipped).
	var on_neb := skimmers.filter(func(s): return s.mine_target is NebulaPocket).size()
	# A gas giant about to blow with our own worlds or stations in its blast:
	# stop skimming it (next to only enemies, draining it is fair game).
	for s in skimmers:
		var mt = s.mine_target
		if is_instance_valid(mt) and mt is Planet and not _giant_safe(pid, mt, game):
			if giant:
				s.order_mine(giant)
			elif neb_spot != Vector2.INF:
				s.order_mine(game.nebula_pocket_at(neb_spot))
			else:
				s.order_move(base.global_position + Vector2(randf_range(-80, 80), randf_range(-80, 80)))
			_flog(pid, "skimmer pulled off unstable %s" % mt.planet_name)
	for s in skimmers:
		if neb_spot != Vector2.INF and on_neb == 0 and _spice_short(pid, game) and not (s.mine_target is NebulaPocket):
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
			var want := "spice" if _spice_short(pid, game) and on_spice < 2 else "minerals"
			var rock := game.nearest_asteroid(m.global_position, 1600.0, want, v)
			if rock == null:
				rock = game.nearest_asteroid(m.global_position, 1600.0, "minerals", v)
			# Nearby belts worked out: the best known deposit further afield
			# that no enemy is seen near (a Mining Station follows, see _dropoff_gap).
			if rock == null:
				rock = _far_rock(pid, m.global_position, game, v)
			if rock:
				m.order_mine(rock)
				if rock.resource == "spice":
					on_spice += 1
	# Miners rarely go idle (a rock lasts a long time), so the idle check alone
	# left every miner on minerals while spice sat at zero. While spice is
	# short, move one busy mineral miner a tick onto a known spice rock.
	if _spice_short(pid, game) and on_spice < 2:
		var rock := game.nearest_asteroid(base.global_position, 1600.0, "spice", v)
		if rock:
			for m in miners:
				if m.state in [Ship.State.MINE_GO, Ship.State.MINING] and is_instance_valid(m.mine_target) and m.mine_target.resource == "minerals":
					m.order_mine(rock)
					break

## ECONOMY protocol (worlds): spent crusts swapped out and free fields built
## (farms, mines, Power Plants only while energy is short, batteries).
func _economy_worlds(cx: Ctx) -> void:
	var pid: int = cx.pid
	var st: Dictionary = cx.st
	var game: Game = cx.game
	var res: Dictionary = cx.res
	var ships: Array = cx.ships
	var v: Vision = cx.v
	# Develop planets: farms when food is falling, otherwise a rotating mix.
	var food_rate: float = game.rates[pid].get("food", 0.0)
	# Farms grow in proportion to fertility, so food goes where the soil is:
	# a poor world only farms if this side has nothing better.
	var best_soil := 0.0
	for p0 in game.get_tree().get_nodes_in_group("planets"):
		if p0.owner_id == pid and p0.free_fields() > 0:
			best_soil = maxf(best_soil, float(p0.type_def().get("fertility", 1.0)))
	# Economy planner: Power Plants only for the energy actually needed
	# (they burn minerals), Mining Complexes wherever the crust lasts.
	var want_power := _want_power(pid, game)
	# Finite crusts: never mine our own worlds to death. Pause a world's
	# Mining Complexes only just before its crust runs out (see _mine_pause_at),
	# then turn them into something useful (one at a time).
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.owner_id != pid or not p.is_habitable():
			continue
		if not p.mining_paused and p.count_building("mine") > 0 and p.mineral_reserve <= _mine_pause_at(p):
			p.mining_paused = true
			_flog(pid, "pause mining on %s (crust %d of %d)" % [p.planet_name, int(p.mineral_reserve), int(p.max_mineral_reserve)])
		# Only worlds paused for their crust (not for a mineral glut, see
		# _toggle_mining) give up their Mining Complexes for good.
		if p.mining_paused and p.mineral_reserve <= _mine_pause_at(p) * 1.5 and p.construction.is_empty() and p.construction_queue.is_empty() and Game.now() >= st.get("mine_swap_at", {}).get(p.name, 0.0):
			var at: int = p.buildings.find("mine")
			if at >= 0:
				st["demolished"] = st.get("demolished", 0) + 1
				p.demolish(at)
				var to := "farm" if game.rates[pid].get("food", 0.0) < 0.0 else ("generator" if want_power else "habitat")
				if to == "habitat" and p.count_building("habitat") >= 3:
					to = "farm"
				if p.order_build(at, to) == "":
					_note_build(st, p, at)
				_flog(pid, "swap: spent mine -> %s on %s (crust %d)" % [to, p.planet_name, int(p.mineral_reserve)])
				if not st.has("mine_swap_at"):
					st["mine_swap_at"] = {}
				st["mine_swap_at"][p.name] = Game.now() + 20.0
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.owner_id != pid or not p.construction.is_empty() or not p.construction_queue.is_empty() or p.free_fields() == 0:
			continue
		var pick := "farm"
		if food_rate > 0.01:
			# Mines first wherever the crust lasts; Power Plants only while
			# the energy plan wants them (see _want_power).
			var cycle := ["mine", "generator", "mine", "farm", "habitat"] if want_power else ["mine", "mine", "farm", "habitat"]
			pick = cycle[(p.fields - p.free_fields()) % cycle.size()]
			# Energy falling: power plants first.
			if game.rates[pid].get("energy", 0.0) < 0.06 and res["energy"] < 35.0:
				pick = "generator"
		# Spice short: an Extractor on a world with a real reserve, even while
		# food dips, as long as the larder has some slack.
		if (food_rate > 0.01 or res["food"] > 300.0) and _spice_short(pid, game) and p.spice_reserve > 200.0 and p.count_building("spice_extractor") == 0:
			pick = "spice_extractor"
		if pick == "farm" and float(p.type_def().get("fertility", 1.0)) < best_soil * 0.6:
			pick = "generator"
		# Spending (see the budget section): with upkeep the brake on new ships, fields go
		# to power (more upkeep room), and spare minerals harden the worlds
		# nearest the enemy with Defense Batteries (no upkeep).
		if pick != "spice_extractor" and (food_rate > 0.01 or res["food"] > 300.0):
			# Upkeep-capped with minerals to spare: Power Plants only (more
			# energy lifts the cap; nothing that adds upkeep).
			if st.get("upkeep_capped", false) and (want_power or _spare(pid, st, game, "minerals") > CAPPED_POWER_MINERALS):
				pick = "generator"
			# Batteries only while under threat: idle hardening just prolongs
			# a stalemate.
			elif st.get("threat", false) and _spare(pid, st, game, "minerals") > 600.0 \
					and p.count_building("battery") < 2 and _frontier_world(pid, p, game, v):
				pick = "battery"
		# No new Mining Complexes on a world with little crust left.
		if pick == "mine" and not _mine_room(p):
			pick = "generator" if want_power else ("habitat" if p.count_building("habitat") < 3 else "farm")
		if pick == "generator" and not want_power and not st.get("upkeep_capped", false) and game.rates[pid].get("energy", 0.0) >= 0.06:
			pick = "mine" if _mine_room(p) else ("habitat" if p.count_building("habitat") < 3 else "farm")
		for i in p.fields:
			if p.order_build(i, pick) == "":
				_note_build(st, p, i)
				break

## ECONOMY protocol (power, mining, spice cover toggles).
func _economy_power(cx: Ctx) -> void:
	var pid: int = cx.pid
	var st: Dictionary = cx.st
	var game: Game = cx.game
	var base: Starbase = cx.base
	var v: Vision = cx.v
	_toggle_power(pid, st, game)
	_toggle_mining(pid, st, game)
	_spice_cover_policy(pid, st, game, base)
	_swap_for_power(pid, st, game)
	_swap_from_power(pid, st, game, v)

## Uses ship abilities when the situation calls for them, and keeps Repair
## Tenders with the fleet.
func _use_jobs(pid: int, ships: Array, game: Game, st: Dictionary = {}) -> void:
	var war := ships.filter(func(s): return s.def["role"] == "warship")
	var home := game.nearest_starbase(pid, Vector2.ZERO)
	for s in ships:
		match s.def.get("job", ""):
			"field_repair":
				if Abilities.ready_in(s) <= 0.0:
					var hurt := Abilities.allies_near(s, Abilities.EMERGENCY_RANGE).filter(func(o): return o.hp < o.max_hp * 0.6)
					if hurt.size() >= 3:
						Abilities.use(s)
				# Stay with the fleet: move to the warships' center (in a
				# fortress assault, the massed assault group's, see _press_attack).
				if not war.is_empty():
					var c := Vector2.ZERO
					for w in war:
						c += w.global_position
					c /= war.size()
					if st.has("assault_center"):
						c = st["assault_center"]
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
		# Nebulae run dry (SpiceNebula.CELL): a harvested-out one is no use.
		if n.depleted():
			continue
		var p: Vector2 = n.heart_toward(from)
		if v != null and not v.is_explored_at(p):
			continue
		var d := from.distance_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best

## Minutes of Power Plant fuel the AI keeps back from spending.
const FUEL_MINUTES := 2.0

## The least crust at which the AI pauses a world's Mining Complexes (see _mine_pause_at).
const AI_PAUSE_FLOOR := 300.0

## Energy planner: Power Plants only while plant income < AI_POWER_MARGIN x
## need and the stockpile is under AI_ENERGY_ENOUGH; above AI_ENERGY_SURPLUS
## surplus plants are turned back into mines and other buildings.
const AI_POWER_MARGIN := 1.4

const AI_ENERGY_ENOUGH := 1000.0

const AI_ENERGY_SURPLUS := 2000.0

## Minutes of shortfall the pile above AI_ENERGY_ENOUGH must cover to pause plants.
const AI_PAUSE_RUNWAY := 5.0

## Energy stock below which (while falling) the AI acts to avoid a blackout.
const AI_ENERGY_FLOOR := 250.0

## Spare minerals above which the AI pauses a world's mines to keep its crust.
const AI_MINERAL_GLUT := 6000.0

## A gas giant this close to empty is treated as about to blow.
const AI_GIANT_DANGER := 1500

## False when gas giant `p` is nearly drained and something of ours that
## cannot just fly off (a world or a construct) sits inside its blast.
func _giant_safe(pid: int, p: Planet, game: Game) -> bool:
	if p.amount > AI_GIANT_DANGER:
		return true
	var r := p.blast_radius() + 150.0
	for w in game.get_tree().get_nodes_in_group("planets"):
		if w != p and w.owner_id == pid and w.global_position.distance_to(p.global_position) < r + w.radius:
			return false
	for grp in ["starbases", "forts", "depots", "mining_stations"]:
		for e in game.get_tree().get_nodes_in_group(grp):
			if e.owner_id == pid and e.is_alive() and e.global_position.distance_to(p.global_position) < r:
				return false
	return true

## The nearest known gas giant worth skimming (see _giant_safe).
func _safe_giant(pid: int, from: Vector2, game: Game, v: Vision) -> Planet:
	var best: Planet = null
	var best_d := 4000.0
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.is_habitable() or p.amount <= 0 or (v and v.known_owner(p) < 0) or not _giant_safe(pid, p, game):
			continue
		var d := from.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best

## A world of ours worth hardening: far from every own starbase, or within
## reach of an enemy holding we know of.
func _frontier_world(pid: int, p: Planet, game: Game, v: Vision) -> bool:
	var yard := game.nearest_starbase(pid, p.global_position)
	if yard == null or yard.global_position.distance_to(p.global_position) > EXPOSED:
		return true
	for e in _enemy_spots(pid, game, v):
		if p.global_position.distance_to(e) < 2200.0:
			return true
	return false

## Upkeep is the brake, energy is genuinely short and minerals pile up:
## turn a Mining Complex on a full world into a Power Plant. One at a time,
## never a world's last mine.
func _swap_for_power(pid: int, st: Dictionary, game: Game) -> void:
	var want: bool = st.get("upkeep_capped", false) and _want_power(pid, game) and _spare(pid, st, game, "minerals") >= CAPPED_POWER_MINERALS and game.rates[pid].get("food", 0.0) >= 0.0
	# Hysteresis: the need must last SWAP_NEED_FOR before a building goes.
	if not _need_lasts(st, "need_power_since", want) or Game.now() < st.get("next_swap", 0.0):
		return
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.owner_id != pid or p.free_fields() > 0 or not p.construction.is_empty() or not p.construction_queue.is_empty() or p.count_building("mine") < 2:
			continue
		for i in p.fields:
			if p.buildings[i] == "mine" and _old_enough(st, p, i):
				_replace(pid, st, p, i, "generator")
				st["next_swap"] = Game.now() + 45.0
				_flog(pid, "swap: mine -> power plant on %s" % p.planet_name)
				return

## Energy piling up far past what upkeep and research use (Power Plants burn
## minerals for it and it buys nothing else): turn a surplus Power Plant into
## a Mining Complex where the crust lasts (minerals are what runs out), else
## a Farm while food falls, a Defense Battery on a frontier world, or a
## Habitat. Faster the bigger the pile.
func _swap_from_power(pid: int, st: Dictionary, game: Game, v: Vision) -> void:
	var e := float(game.resources[pid]["energy"])
	var surplus: bool = e >= AI_ENERGY_SURPLUS and _energy_margin(pid, game) >= 0.0
	if not _need_lasts(st, "power_surplus_since", surplus) or Game.now() < st.get("next_power_swap", 0.0):
		return
	# Keep income covering upkeep alone (the stockpile pays for research).
	var income := _plant_income(pid, game)
	var upk: float = game.upkeep(pid) + game.building_upkeep(pid)
	# Plants already switched off for a while are the long-term surplus: those first.
	var worlds: Array = game.get_tree().get_nodes_in_group("planets").filter(func(w): return w.owner_id == pid)
	worlds.sort_custom(func(a, b): return int(a.power_paused) > int(b.power_paused))
	for p in worlds:
		if p.owner_id != pid or not p.construction.is_empty() or not p.construction_queue.is_empty() or p.count_building("generator") == 0:
			continue
		# Short-term surplus is what pausing is for (see _toggle_power): only
		# plants switched off for a while (or a huge pile) are torn down.
		if e < AI_ENERGY_SURPLUS * 3.0 and not (p.power_paused and Game.now() - float(st.get("paused_at", {}).get(p.name, Game.now())) >= SWAP_PAUSED_FOR):
			continue
		var per_plant := _plant_rate(p, game)
		# Below a big pile, never take income under what upkeep costs (a
		# switched-off plant makes nothing anyway).
		if not p.power_paused and e < AI_ENERGY_SURPLUS * 3.0 and income - per_plant < upk * 1.05:
			continue
		var to := ""
		if _mine_room(p):
			to = "mine"
		elif game.rates[pid].get("food", 0.0) < 0.0:
			to = "farm"
		elif p.count_building("battery") < 3 and _frontier_world(pid, p, game, v):
			to = "battery"
		elif p.count_building("habitat") < 3:
			to = "habitat"
		else:
			to = "farm"
		for i in p.fields:
			if p.buildings[i] == "generator" and _old_enough(st, p, i):
				_replace(pid, st, p, i, to)
				st["next_power_swap"] = Game.now() + (8.0 if e > AI_ENERGY_SURPLUS * 4.0 else 20.0)
				_flog(pid, "swap: power plant -> %s on %s (energy %d, plant income %d/min, upkeep %d/min)" % [to, p.planet_name, int(e), int(income), int(upk)])
				return

## Building churn guards: a building is only torn down for another once it
## has stood BUILDING_KEEP seconds (since this AI ordered it), the need for
## the swap has lasted SWAP_NEED_FOR, and (for surplus Power Plants) the
## world's plants have sat switched off for SWAP_PAUSED_FOR - pausing comes
## before demolishing.
const BUILDING_KEEP := 480.0

const SWAP_NEED_FOR := 120.0

const SWAP_PAUSED_FOR := 240.0

func _note_build(st: Dictionary, p: Planet, i: int) -> void:
	if not st.has("built_at"):
		st["built_at"] = {}
	st["built_at"]["%s:%d" % [p.name, i]] = Game.now()

func _old_enough(st: Dictionary, p: Planet, i: int) -> bool:
	return Game.now() - float(st.get("built_at", {}).get("%s:%d" % [p.name, i], -INF)) >= BUILDING_KEEP

## True once `cond` has held for SWAP_NEED_FOR (tracked under `key`).
func _need_lasts(st: Dictionary, key: String, cond: bool) -> bool:
	if not cond:
		st.erase(key)
		return false
	if not st.has(key):
		st[key] = Game.now()
	return Game.now() - float(st[key]) >= SWAP_NEED_FOR

func _replace(pid: int, st: Dictionary, p: Planet, i: int, to: String) -> void:
	p.demolish(i)
	if p.order_build(i, to) == "":
		_note_build(st, p, i)
	st["demolished"] = st.get("demolished", 0) + 1

## Energy per minute one running Power Plant on `p` makes.
func _plant_rate(p: Planet, game: Game) -> float:
	return 20.0 * p.pop_output_mult() * game.mod(p.owner_id, "energy") * float(p.type_def().get("energy_mult", 1.0))

## Short-term surplus: with a big energy stockpile, switch whole worlds'
## Power Plants off (Pause power: no energy, no fuel burnt) while what is
## left still covers upkeep; switch them back on as the stockpile or the
## margin falls. Every 10 s, one world at a time.
func _toggle_power(pid: int, st: Dictionary, game: Game) -> void:
	if Game.now() < st.get("next_power_toggle", 0.0):
		return
	st["next_power_toggle"] = Game.now() + (3.0 if game.in_blackout(pid) else 10.0)
	var e := float(game.resources[pid]["energy"])
	var income := _plant_income(pid, game)
	var upk: float = game.upkeep(pid) + game.building_upkeep(pid)
	var need := _energy_need(pid, game)
	var on: Array = []
	var off: Array = []
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.owner_id == pid and p.count_building("generator") > 0:
			(off if p.power_paused else on).append(p)
	# Blackout guard: the pile nearly gone and still falling - every plant
	# back on at once and, with none left to switch on, the mines with the
	# least crust off (they draw energy too, where the rules charge for it).
	if game.in_blackout(pid) or (e < AI_ENERGY_FLOOR and game.rates[pid].get("energy", 0.0) < 0.0):
		for p in off:
			p.power_paused = false
		if not off.is_empty():
			_flog(pid, "blackout guard: %d worlds' power back on (energy %d)" % [off.size(), int(e)])
		elif Game.now() >= st.get("next_blackout_mine", 0.0):
			var mw: Array = game.get_tree().get_nodes_in_group("planets").filter(func(w): return w.owner_id == pid and w.count_building("mine") > 0 and not w.mining_paused)
			if mw.size() > 1:
				mw.sort_custom(func(a, b): return a.mineral_reserve < b.mineral_reserve)
				mw[0].mining_paused = true
				st["next_blackout_mine"] = Game.now() + 30.0
				_flog(pid, "blackout guard: pause mining on %s (energy %d)" % [mw[0].planet_name, int(e)])
		return
	# Resume: the pile is running down, or income no longer covers upkeep.
	if not off.is_empty() and (e < AI_ENERGY_ENOUGH * 0.5 or (_energy_margin(pid, game) < 0.0 and e < AI_ENERGY_ENOUGH) or (income < need and e < AI_ENERGY_ENOUGH * 0.25)):
		off.sort_custom(func(a, b): return a.count_building("generator") > b.count_building("generator"))
		off[0].power_paused = false
		_flog(pid, "resume power on %s (energy %d, plant income %d/min, upkeep %d/min)" % [off[0].planet_name, int(e), int(income), int(upk)])
		return
	# Pause: a big pile, and what keeps running still pays the upkeep
	# (the pile pays for research). Fewest plants first.
	if e > AI_ENERGY_ENOUGH * 1.2 and not on.is_empty() and _energy_margin(pid, game) > 0.0:
		on.sort_custom(func(a, b): return a.count_building("generator") < b.count_building("generator"))
		for p in on:
			var lose: float = _plant_rate(p, game) * p.count_building("generator")
			# Research no longer draws energy, so a pile is only upkeep
			# cover: run it down as long as what is above AI_ENERGY_ENOUGH
			# lasts AI_PAUSE_RUNWAY minutes of the shortfall.
			var short := upk - (income - lose)
			if short <= upk * -0.05 or (e - AI_ENERGY_ENOUGH) / maxf(short, 1.0) >= AI_PAUSE_RUNWAY:
				p.power_paused = true
				if not st.has("paused_at"):
					st["paused_at"] = {}
				st["paused_at"][p.name] = Game.now()
				_flog(pid, "pause power on %s (%d plants; energy %d, plant income %d/min, upkeep %d/min)" % [p.planet_name, p.count_building("generator"), int(e), int(income), int(upk)])
				return

## Mining Complexes on and off: a mineral glut (far more than the yards
## and reserve can use) pauses the world with the least crust left, to keep
## it for later; short of minerals, a glut-paused world whose crust allows
## is resumed. Worlds near their crust's end stay paused (see _mine_pause_at).
func _toggle_mining(pid: int, st: Dictionary, game: Game) -> void:
	if Game.now() < st.get("next_mine_toggle", 0.0):
		return
	st["next_mine_toggle"] = Game.now() + 15.0
	var spare := _spare(pid, st, game, "minerals")
	var worlds: Array = game.get_tree().get_nodes_in_group("planets").filter(func(w): return w.owner_id == pid and w.is_habitable() and w.count_building("mine") > 0)
	if spare < AI_MINERAL_GLUT * 0.4 and float(game.resources[pid]["energy"]) > AI_ENERGY_FLOOR * 3.0:
		for p in worlds:
			if p.mining_paused and p.mineral_reserve > _mine_pause_at(p) * 1.5 + 50.0:
				p.mining_paused = false
				_flog(pid, "resume mining on %s (crust %d, spare minerals %d)" % [p.planet_name, int(p.mineral_reserve), int(spare)])
				return
	elif spare > AI_MINERAL_GLUT:
		worlds = worlds.filter(func(w): return not w.mining_paused)
		if worlds.size() < 2:
			return
		worlds.sort_custom(func(a, b): return a.mineral_reserve < b.mineral_reserve)
		worlds[0].mining_paused = true
		_flog(pid, "pause mining on %s (mineral glut: spare %d; crust %d kept)" % [worlds[0].planet_name, int(spare), int(worlds[0].mineral_reserve)])

## Spice cover (Game.set_spice_cover): ON spends spice on any food /
## minerals / energy shortfall; OFF saves it for research and lets the
## shortfall bite. Cover is what keeps the yards building through mineral
## gaps (in sims, turning it off whenever spice was under a few hundred left
## fewer warships and bought no extra research), so OFF is reserved for
## when research itself is at stake: no emergency for COVER_CALM seconds and
## the stock under what the running project still needs (see _research_keep).
## It goes ON in an emergency (food about to run out, energy about to black
## out or already out, minerals stalled with the enemy at our worlds) or once
## the stock is back over COVER_GLUT_MULT x that need.
const COVER_GLUT_MULT := 1.5

const COVER_CALM := 60.0

## Minutes of food / energy deficit left that count as an emergency.
const COVER_RUNWAY := 1.5

func _cover_emergency(pid: int, st: Dictionary, game: Game, base: Starbase) -> String:
	var res: Dictionary = game.resources[pid]
	var rates: Dictionary = game.rates[pid]
	var fr: float = rates.get("food", 0.0) * Defs.PER_MIN
	if fr < 0.0 and float(res["food"]) < -fr * COVER_RUNWAY:
		return "starvation"
	var er: float = rates.get("energy", 0.0) * Defs.PER_MIN
	if game.in_blackout(pid) or (er < 0.0 and float(res["energy"]) < maxf(AI_ENERGY_FLOOR, -er * COVER_RUNWAY)):
		return "blackout"
	if st.get("threat", false) and float(res["minerals"]) < 50.0 and base.build_stalled:
		return "mineral stall under attack"
	return ""

func _spice_cover_policy(pid: int, st: Dictionary, game: Game, base: Starbase) -> void:
	var on := game.spice_cover_on(pid)
	# Tally for the logs: time with cover on, spice spent covering.
	if on:
		st["cover_on_s"] = st.get("cover_on_s", 0.0) + 1.0
		st["cover_spent"] = st.get("cover_spent", 0.0) + game.spice_covering(pid) / Defs.PER_MIN
	if Game.now() < st.get("next_cover", 0.0):
		return
	st["next_cover"] = Game.now() + 5.0
	var why := _cover_emergency(pid, st, game, base)
	var spice := float(game.resources[pid]["spice"])
	var keep := _research_keep(pid, game)
	if why != "":
		st["cover_alarm"] = Game.now()
	elif spice > keep * COVER_GLUT_MULT:
		why = "spice to spare (%d, research needs %d)" % [int(spice), int(keep)]
	var want := on
	if why != "":
		want = true
	elif Game.now() - float(st.get("cover_alarm", -INF)) >= COVER_CALM and spice < keep:
		want = false
	if want != on:
		game.set_spice_cover(pid, want)
		st["cover_flips"] = st.get("cover_flips", 0) + 1
		var r: Dictionary = game.resources[pid]
		_flog(pid, "spice cover %s: %s (S=%d F=%d M=%d E=%d)" % ["ON" if want else "OFF", why if want else "no shortfall threatens survival, saving spice for research (needs %d)" % int(keep), int(spice), int(r["food"]), int(r["minerals"]), int(r["energy"])])

## Spice the research under way still needs (plus a margin, at least 100):
## below this, cover would eat what the project is about to draw.
func _research_keep(pid: int, game: Game) -> float:
	var need := 0.0
	var cur: Dictionary = game.research[pid]
	if not cur.is_empty():
		var t: Dictionary = Defs.TECHS[cur["id"]]
		need = float(t["cost"].get("spice", 0.0)) * (1.0 - float(cur["progress"]) / float(t["time"]))
	return maxf(100.0, need + 50.0)

## Spice pays for all research: worth more harvesters, Extractors and
## skimming while the stock is under SPICE_LOW or income is thin.
const SPICE_LOW := 400.0

const SPICE_INCOME_MIN := 40.0

func _spice_short(pid: int, game: Game) -> bool:
	return float(game.resources[pid]["spice"]) < SPICE_LOW or game.rates[pid].get("spice", 0.0) * Defs.PER_MIN < SPICE_INCOME_MIN

## Energy per minute this side's Power Plants are making now.
func _plant_income(pid: int, game: Game) -> float:
	var t := 0.0
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.owner_id == pid:
			t += p.energy_out
	return t

## Energy per minute the side needs: upkeep plus research (the running
## project's rate, or a typical one) plus a little for shields.
func _energy_need(pid: int, game: Game) -> float:
	# Research costs spice now; any energy a project still costs counts.
	var r := 0.0
	var cur: Dictionary = game.research[pid]
	if not cur.is_empty():
		var t: Dictionary = Defs.TECHS[cur["id"]]
		r = float(t["cost"].get("energy", 0.0)) / float(t["time"]) * Defs.PER_MIN
	# Everything else that draws energy (shield regen, and any building
	# upkeep the rules charge) shows in the measured flow: what the plants
	# make minus the net rate is what is being spent.
	var spent: float = _plant_income(pid, game) - game.rates[pid].get("energy", 0.0) * Defs.PER_MIN
	if cur.is_empty():
		spent += r
	return maxf(game.upkeep(pid) + game.building_upkeep(pid) + r, spent) + 20.0

## Whether to build (or keep) more Power Plants: only while income falls
## short of AI_POWER_MARGIN x the need and the stockpile isn't big already.
func _want_power(pid: int, game: Game) -> bool:
	var e := float(game.resources[pid]["energy"])
	# Upkeep outgrowing income caps the fleet even with a pile in hand.
	var short: bool = _energy_margin(pid, game) < 0.0 and e < AI_ENERGY_SURPLUS
	if e > AI_ENERGY_ENOUGH and not short:
		return false
	# Plants switched off come back on first (see _toggle_power).
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.owner_id == pid and p.power_paused and p.count_building("generator") > 0:
			return false
	var margin := AI_POWER_MARGIN if e > AI_ENERGY_ENOUGH * 0.3 else AI_POWER_MARGIN + 0.3
	return _plant_income(pid, game) < _energy_need(pid, game) * margin

## Crust at which a world's Mining Complexes stop: a minute of
## digging at their current rate (implosion is only at 0), never under
## AI_PAUSE_FLOOR.
func _mine_pause_at(p: Planet) -> float:
	var dig: float = p.count_building("mine") * 20.0 * p.pop_output_mult()
	return maxf(AI_PAUSE_FLOOR, dig * 1.0)

## Room for one more Mining Complex: enough crust for it and the ones there
## to dig for several minutes before the pause point.
func _mine_room(p: Planet) -> bool:
	if p.mining_paused:
		return false
	var n := p.count_building("mine") + 1
	return p.mineral_reserve > AI_PAUSE_FLOOR * 2.0 + n * 20.0 * p.pop_output_mult() * 6.0

## Harvesters wanted: TARGET_MINERS, more as our worlds' crusts give out
## (belts and gas giants take over), while known belts still hold minerals.
func _target_miners(pid: int, st: Dictionary, game: Game, v: Vision) -> int:
	if Game.now() < st.get("next_miner_plan", 0.0):
		return st.get("miner_target", TARGET_MINERS)
	st["next_miner_plan"] = Game.now() + 20.0
	var worlds := 0
	var spent := 0
	var crust := 0.0
	var crust_max := 0.0
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.owner_id == pid and p.is_habitable():
			worlds += 1
			crust += p.mineral_reserve
			crust_max += p.max_mineral_reserve
			if p.mining_paused or not _mine_room(p):
				spent += 1
	st["crust_low"] = crust_max > 0.0 and crust < crust_max * 0.4
	var known := 0.0
	for a in game.get_tree().get_nodes_in_group("asteroids"):
		if a.resource == "minerals" and a.amount > 0 and (v == null or v.is_explored_at(a.global_position)):
			known += a.amount
	var n := TARGET_MINERS
	if known > 1500.0:
		n += mini(spent, 4) + (2 if st["crust_low"] else 0)
	st["miner_target"] = mini(n, 12)
	return st["miner_target"]

## The richest-for-distance known mineral rock anywhere, away from enemies
## seen lately and our own exploding bodies; null if none.
func _far_rock(pid: int, from: Vector2, game: Game, v: Vision) -> Asteroid:
	var best: Asteroid = null
	var best_score := -INF
	for a in game.get_tree().get_nodes_in_group("asteroids"):
		if a.is_queued_for_deletion() or a.amount <= 0 or a.resource != "minerals":
			continue
		if v and (not v.is_explored_at(a.global_position) or _enemy_seen_near(v, a.global_position, 700.0, 60.0)):
			continue
		var home := game.nearest_starbase(pid, a.global_position)
		var dh: float = home.global_position.distance_to(a.global_position) if home else 0.0
		var score: float = minf(float(a.amount), 600.0) - from.distance_to(a.global_position) * 0.15 - dh * 0.1
		if score > best_score:
			best_score = score
			best = a
	return best


# ======================================================================
# CONSTRUCTION
# ======================================================================
# Where constructs go: yards, drop-offs, depots, outposts and gates, never
# into spots where enemies were seen lately.

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
	# (`bases`: positions of our yards and yard sites already ordered.)
	var v: Vision = game.visions.get(pid)
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.owner_id != pid or bases.any(func(b): return b.distance_to(p.global_position) < 700.0):
			continue
		# Only where it is safe: no enemy warships seen near that world.
		if v and v.enemy_near(p.global_position, 900.0) > 0:
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
				var q2: Vector2 = b + Vector2.from_angle(TAU * a / 12.0) * r
				if game.starbase_site_problem(q2) == "" and (v == null or v.enemy_near(q2, 900.0) == 0):
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
	# we want: at most one of each variant (a new one if the enemy fleet changes).
	var have := depots.any(func(d): return d.variant == want)
	if want != "" and not have:
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

func _plan_outpost(pid: int, st: Dictionary, game: Game, base: Starbase, forts: Array, builders: Array, v: Vision, fleet: int) -> void:
	# (Under threat only with minerals to spare: then holding ground is
	# exactly what the stockpile should buy.)
	if Game.now() < st.get("next_outpost", 0.0) or st.get("mode", "") == "recover" or (st.get("threat", false) and _spare(pid, st, game, "minerals") < 3000.0):
		return
	var d: Dictionary = Defs.FRONTIER_OUTPOST
	var res: Dictionary = game.resources[pid]
	# Never at the cost of the fleet: a fleet first, and the bill (paid over
	# the build) in hand with a little to spare.
	if fleet < 4 or res["minerals"] < d["cost"]["minerals"] + 150.0 or not _upkeep_ok(pid, game, d["upkeep"]):
		return
	var pending := builders.filter(func(c): return c.state == Ship.State.BUILD and c.build_kind == "outpost")
	var have: int = forts.filter(func(f): return f is FrontierOutpost).size() + pending.size()
	var worlds: int = game.get_tree().get_nodes_in_group("planets").filter(func(p): return p.owner_id == pid).size()
	# One to start; another every 7 minutes and per two worlds, up to OUTPOST_MAX.
	var cap := mini(OUTPOST_MAX, mini(1 + int(Game.now() / 420.0), 1 + worlds / 2))
	# Minerals piling up past what the yards can use: more ground held.
	var rich: bool = _spare(pid, st, game, "minerals") > 3000.0
	if rich:
		cap = mini(OUTPOST_MAX, cap + 2)
	if have >= cap:
		return
	var taken: Array = forts.map(func(f): return f.global_position) + pending.map(func(c): return c.build_site)
	var site := _outpost_site(pid, game, base, taken, v)
	# Not into a contested spot (enemies seen there lately).
	if site != Vector2.INF and v and _enemy_seen_near(v, site, 700.0, 60.0):
		site = Vector2.INF
	if site == Vector2.INF:
		st["next_outpost"] = Game.now() + 30.0
		return
	var c := _idle_builder(base, builders)
	if c == null:
		return
	c.order_build_fort(site, "outpost")
	st["next_outpost"] = Game.now() + (OUTPOST_EVERY * 0.4 if rich else OUTPOST_EVERY)
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
	# One Warp Gate at a time (MAX_GATES).
	if n >= MAX_GATES or not pending.is_empty():
		return
	# The bill is paid over the build, so half of it in hand will do.
	if fleet < 6 or res["minerals"] < d["cost"]["minerals"] * 0.5 or not _upkeep_ok(pid, game, d["upkeep"]):
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


# ======================================================================
# MILITARY / ENGAGEMENT
# ======================================================================
# Mode and commitment (_rethink), target choice by cost to kill, waves,
# fortress assaults and gate jumps. Fight sense (_defence_at, _can_win) uses
# only what this side has seen.

## MILITARY protocol: a committed army presses its target; otherwise idle
## groups bombard worlds in reach and launch waves at winnable targets.
func _military_protocol(cx: Ctx) -> void:
	var pid: int = cx.pid
	var st: Dictionary = cx.st
	var game: Game = cx.game
	var base: Starbase = cx.base
	var ships: Array = cx.ships
	var v: Vision = cx.v
	var war: Array = cx.war
	var mode: String = cx.mode
	# Committed (clearly ahead): the whole army goes for the kill in waves.
	if st.get("commit", false):
		_press_attack(pid, st, game, base, war, ships, v)
		return

	var idle := war.filter(func(s): return s.state == Ship.State.IDLE)
	# Idle warships next to an enemy planet start bombarding it (not a turtle).
	for s in (idle.duplicate() if not (game.rl_side > 0 and pid != game.rl_side and game.opp_level == 2) else []):
		var ep := _nearest_planet(s.global_position, game, func(pl): return pl.is_enemy_of(pid) and (v == null or v.is_visible_at(pl.global_position)))
		# Only a world the warships near it can actually bring down.
		if ep and _hurts_worlds(s) and s.global_position.distance_to(ep.global_position) < 350.0 and _can_win(pid, idle.filter(func(o): return o.global_position.distance_to(ep.global_position) < 500.0), ep.global_position, game):
			s.order_bombard(ep)
			idle.erase(s)
	# Aggressive: any idle group that can destroy something goes for it,
	# whatever the mode and whatever it costs (see _can_win).
	# Gather a wave of meaningful size first (half the army, 3 to 8 ships)
	# instead of trickling ships out three at a time.
	var need := clampi(war.size() / 2, 3, 8)
	if _regrouping(st):
		need = maxi(need, ceili(war.size() * REGROUP_SHARE))
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
			for rsa in ships.filter(func(s): return s.ship_type.ends_with("heatshield") and s.state == Ship.State.IDLE and not _escorting(s)):
				rsa.order_move(goal + Vector2(randf_range(-80, 80), randf_range(-80, 80)))
			st["wave"] = mini(st["wave"] + 4, 30)
	# Waves already out pull back if their target has become too strong.
	_recall_losing_waves(pid, war, base, game)

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

## Upkeep-capped (the fleet can't grow any more): waiting gains nothing, so
## attack / commit at this smaller edge instead of ATTACK_EDGE / COMMIT_EDGE.
const CAPPED_EDGE := 0.95

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
	_counter_update(pid, st, game)
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
	# (A Blackout counts: buildings are offline, so no new hulls or attacks.)
	var energy_starved: bool = (res["energy"] < 7.0 and rates.get("energy", 0.0) < 0.0) or game.in_blackout(pid)
	var starved := energy_starved
	var free := _nearest_planet(base.global_position, game, func(p): return _known_free(pid, p, game) and p.is_habitable()) != null
	var mode := "expand" if free else "build_up"
	if starved:
		mode = "recover"
	elif threat or theirs > mine * 1.3:
		mode = "build_up"
	elif mine > theirs * (CAPPED_EDGE if st.get("upkeep_capped", false) else ATTACK_EDGE) and war.size() >= 8:
		mode = "attack"
	# Clearly winning: finish it, however small the fleet.
	elif mine > theirs * FINISH_EDGE and war.size() >= 2:
		mode = "attack"
	st["finishing"] = mine > theirs * FINISH_EDGE
	st["mine_power"] = mine
	st["theirs_power"] = theirs
	st["threat"] = threat
	# Commit to a decisive attack when clearly ahead of everything it knows
	# of (warships seen lately plus the starbases and outposts it has seen);
	# stay committed through minor losses, drop it only when the edge is gone.
	# Constructs are taken one at a time (targets are picked by cost to kill
	# and must be winnable, see _commit_target): a sprawl of yards counts as
	# at most COMMIT_CONSTRUCT_CAP starbases' worth, not all at once.
	var sbt: float = Defs.STARBASE["hp"] + Defs.STARBASE["armor"] + Defs.STARBASE["shield"]
	var known := theirs + minf(_known_constructs(pid, game, v), sbt * COMMIT_CONSTRUCT_CAP) * COMMIT_CONSTRUCT_SHARE
	# No enemy fleet seen lately: the constructs alone don't hold it back
	# (each target must still be winnable before the army goes, else it stages).
	if theirs < 400.0:
		known = theirs
	var was: bool = st.get("commit", false)
	var commit: bool = was
	# Far ahead (see _overwhelming): commit even without the usual edge over
	# the constructs, and stay in while the advantage holds.
	var ow := _overwhelming(pid, st, game, v, mine, theirs, war.size())
	if ow != st.get("overwhelm", false):
		_flog(pid, "overwhelm %s: mine %d (+%d in production) vs seen fleet %d, %d warships" % ["ON" if ow else "off", int(mine), int(st.get("str_prod", 0.0)), int(theirs), war.size()])
	st["overwhelm"] = ow
	if ow and not was and Game.now() >= COMMIT_AFTER and not energy_starved:
		commit = true
	elif ow and was:
		commit = war.size() >= 2 and not energy_starved
	elif not was:
		# With no enemy fleet seen lately, a smaller army can finish the job.
		var cmin := COMMIT_MIN if theirs > 400.0 else COMMIT_MIN / 2
		commit = Game.now() >= COMMIT_AFTER and war.size() >= cmin and mine > known * (CAPPED_EDGE if st.get("upkeep_capped", false) else COMMIT_EDGE) and not energy_starved
	elif war.size() < (COMMIT_MIN / 2 if theirs > 400.0 else 2) or energy_starved or (mine < known * COMMIT_DROP and war.size() < st.get("commit_peak", 0) * 0.6):
		commit = false
	# (The edge alone doesn't end it: its picture of the enemy remembers
	# ships for two minutes, so it only lets go once it has really lost much
	# of the army it committed.)
	st["commit_dbg"] = "mine=%d theirs=%d known=%d" % [int(mine), int(theirs), int(known)]
	st["commit_peak"] = maxi(st.get("commit_peak", 0), war.size()) if commit else 0
	if commit != was:
		_flog(pid, "commit %s: mine %d vs known %d (%d warships)" % ["ON" if commit else "off", int(mine), int(known), war.size()])
	st["commit"] = commit
	if commit:
		mode = "attack"
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

## Fortress assault: how far ahead a side must be (army plus warships in
## its yards' queues, against the enemy fleet it has seen lately) before it
## stops waiting for a target that looks winnable and storms the strongest
## worlds and yards anyway, accepting losses.
const OVERWHELM_EDGE := 3.0

## ... or: no enemy fleet seen lately and at most this many enemy worlds and
## yards known.
const OVERWHELM_FEW := 3

const OVERWHELM_FEW_AFTER := 1200.0

## Least warships for either.
const OVERWHELM_MIN := 6

## Assault: the share of the army that must be massed at the staging point
## before it goes in, and after how long (s) a smaller share will do.
const ASSAULT_MASS := 0.75

const ASSAULT_WAIT := 150.0

## Far ahead of everything this side knows of the enemy (own Vision only):
## see OVERWHELM_EDGE / OVERWHELM_FEW.
func _overwhelming(pid: int, st: Dictionary, game: Game, v: Vision, mine: float, theirs: float, n_war: int) -> bool:
	if n_war < OVERWHELM_MIN or Game.now() < COMMIT_AFTER:
		return false
	# Production: warships queued in our own yards count at half.
	var prod := 0.0
	for b in game.get_tree().get_nodes_in_group("starbases"):
		if b.owner_id == pid and not b.under_construction:
			for t in b.queue:
				var d: Dictionary = Defs.SHIPS.get(t, {})
				if d.get("role", "") == "warship":
					prod += (float(d.get("hp", 0.0)) + float(d.get("armor", 0.0)) + float(d.get("shield", 0.0))) * 0.5
	# (Capped: a full queue is not a fleet yet.)
	prod = minf(prod, mine * 0.5)
	st["str_prod"] = prod
	var strength := mine + prod
	if strength >= OVERWHELM_EDGE * maxf(theirs, 1.0) and mine >= 2.0 * theirs and theirs > 400.0:
		return true
	if theirs > 400.0:
		return false
	# No fleet seen lately: few holdings left (worlds + yards it knows of).
	var held := 0
	for p in game.get_tree().get_nodes_in_group("planets"):
		var o: int = v.known_owner(p) if v else p.owner_id
		if o > 0 and o != pid and game.is_hostile(pid, o):
			held += 1
	held += v.seen_bases.size() if v else game.get_tree().get_nodes_in_group("starbases").filter(func(b): return game.is_hostile(pid, b.owner_id)).size()
	# (Not before OVERWHELM_FEW_AFTER: early on, few known holdings only
	# means little has been explored.)
	return Game.now() >= OVERWHELM_FEW_AFTER and strength >= 1500.0 and (held <= OVERWHELM_FEW or strength >= OVERWHELM_EDGE * 1500.0)

## The committed army's target, by cost to kill: what defends it as seen
## (starbases, outposts, battery worlds and warships near it, see
## _defence_at) against the army's strength, plus distance, plus what taking
## it is worth. A side is out once it has no starbase and no Constructor, or
## no worlds: so its yards first (weakly defended ones before strong), its
## Constructors when they are all that keeps it alive or are caught in the
## open, then worlds (small before populous ones, which take long to
## bombard). Only targets it can win at; with none, it stages short of the
## cheapest (or goes looking when it knows of nothing).
func _commit_target(pid: int, st: Dictionary, war: Array, from: Vector2, game: Game, v: Vision) -> Vector2:
	var cands: Array = []   # [pos, kind, extra cost, builder id]
	if v:
		for sb in v.seen_bases:
			cands.append([v.seen_bases[sb][0], "yard", 0.0, 0])
	else:
		for sb in game.get_tree().get_nodes_in_group("starbases"):
			if game.is_hostile(pid, sb.owner_id):
				cands.append([sb.global_position, "yard", 0.0, 0])
	var yards_known := cands.size()
	var builders: Dictionary = st.get("seen_builders", {})
	for id in builders:
		# The last Constructors of a side with no yard left end it.
		cands.append([builders[id][0], "builder", -0.4 if yards_known == 0 else 0.5, id])
	for p in game.get_tree().get_nodes_in_group("planets"):
		var o: int = v.known_owner(p) if v else p.owner_id
		if o > 0 and o != pid and game.is_hostile(pid, o):
			var pop: float = v.seen_planet_pop.get(p, 0.0) if v else p.pop
			cands.append([p.global_position, "world", 0.5 + pop / 6000.0, 0])
	if cands.is_empty() and v:
		var look := _scout_target(pid, from, game, v)
		if look != Vector2.INF:
			st["commit_winnable"] = true
			st["commit_kind"] = "look"
			return look
	var dps := 0.0
	var tough := 0.0
	for s in war:
		dps += _ship_dps(s, game)
		tough += s.hp + s.armor + s.shield
	var ours := maxf(dps * tough, 1.0)
	var best: Array = []
	var best_cost := INF
	var cheapest: Array = []
	var cheapest_cost := INF
	for c in cands:
		var d := _defence_at(pid, c[0], game)
		var cost: float = d.x * d.y / ours * 2.0 + from.distance_to(c[0]) / 2500.0 + c[2]
		if cost < cheapest_cost:
			cheapest_cost = cost
			cheapest = c
		if cost < best_cost and _can_win(pid, war, c[0], game):
			best_cost = cost
			best = c
	if not best.is_empty():
		st["commit_winnable"] = true
		st["commit_kind"] = best[1]
		st["commit_builder"] = best[3]
		return best[0]
	# Nothing it can take yet: stage short of the cheapest (see _press_attack).
	st["commit_winnable"] = cands.is_empty()
	if not cheapest.is_empty():
		st["commit_kind"] = cheapest[1]
		st["commit_builder"] = cheapest[3]
		return cheapest[0]
	st["commit_kind"] = "guess"
	return _attack_goal(pid, from, game)

## Committed: ships at the front finish their target (bombard worlds, attack
## everything else) and move on to the next; fresh hulls gather at home and
## go out in waves of meaningful size; no recall over minor losses.
func _press_attack(pid: int, st: Dictionary, game: Game, base: Starbase, war: Array, ships: Array, v: Vision) -> void:
	if war.is_empty():
		return
	var center := Vector2.ZERO
	for s in war:
		center += s.global_position
	center /= war.size()
	var goal: Vector2 = st.get("commit_target", Vector2.INF)
	var spots := _enemy_spots(pid, game, v)
	var valid: bool = goal != Vector2.INF and spots.any(func(e): return e.distance_to(goal) < 150.0)
	var kind: String = st.get("commit_kind", "")
	if kind == "builder":
		valid = st.get("seen_builders", {}).has(st.get("commit_builder", 0))
	elif kind == "look":
		valid = goal != Vector2.INF and not (v and v.is_visible_at(goal))
	if not valid or Game.now() >= st.get("commit_retarget", 0.0):
		var old := goal
		goal = _commit_target(pid, st, war, center, game, v)
		st["commit_target"] = goal
		st["commit_retarget"] = Game.now() + (8.0 if st.get("commit_kind", "") == "builder" else 20.0)
		if old == Vector2.INF or old.distance_to(goal) > 150.0:
			_flog(pid, "commit target %s (%d,%d) winnable=%s, %d warships" % [st.get("commit_kind", "?"), goal.x, goal.y, str(st.get("commit_winnable", true)), war.size()])
	if goal == Vector2.INF:
		return
	# Not winnable yet with the whole army: gather it at a staging point
	# short of the target (out of its guns) until it is, rather than feeding
	# it in piecemeal.
	# Far ahead (fortress assault, see _overwhelming): mass the army there
	# instead, then storm it together and keep at it while the advantage
	# holds; a wave that is wiped out regroups with the next one.
	# (Fortified targets too: batteries and yards grind down ships that
	# arrive a few at a time even when the fight counts as winnable.)
	var fortified: bool = st.get("commit_kind", "") in ["yard", "world"] and _defence_at(pid, goal, game).x > 0.0
	if (not st.get("commit_winnable", true) or fortified) and st.get("overwhelm", false):
		if not _assault(pid, st, game, base, war, goal):
			return
	else:
		st.erase("assault_center")
		if st.get("assault_goal", Vector2.INF) != Vector2.INF:
			_flog(pid, "assault over (%s)" % ("target winnable" if st.get("commit_winnable", true) else "advantage gone"))
			st["assault_goal"] = Vector2.INF
	if not st.get("commit_winnable", true) and not st.get("overwhelm", false):
		var stage: Vector2 = goal + (base.global_position - goal).normalized() * STAGE_BACK
		for s in war:
			if s.state == Ship.State.IDLE and s.global_position.distance_to(stage) > 200.0:
				s.order_move(stage + Vector2(randf_range(-80, 80), randf_range(-80, 80)))
		return
	var world_goal: bool = _nearest_planet(goal, game, func(pl): return pl.global_position.distance_to(goal) < 150.0) != null
	# A yard target in sight: shoot the yard, not the world beside it (the
	# yards and Constructors end a side; a big world takes half an hour).
	var yard: Starbase = null
	if st.get("commit_kind", "") == "yard":
		for sb in game.get_tree().get_nodes_in_group("starbases"):
			if game.is_hostile(pid, sb.owner_id) and sb.is_alive() and sb.global_position.distance_to(goal) < 150.0 and (v == null or v.can_see(sb)):
				yard = sb
				world_goal = false
				break
	if yard:
		for s in war:
			if s.global_position.distance_to(yard.global_position) < FRONT and s.state in [Ship.State.IDLE, Ship.State.BOMBARD]:
				s.order_attack(yard)
	# A Constructor in sight: everyone near goes straight for it.
	var prey: Ship = _visible_builder(pid, st.get("commit_builder", 0), game, v) if st.get("commit_kind", "") == "builder" else null
	if prey:
		for s in war:
			if s.global_position.distance_to(prey.global_position) < FRONT and s.state in [Ship.State.IDLE, Ship.State.MOVE, Ship.State.ATTACK_MOVE]:
				s.order_attack(prey)
	var home_idle: Array = []
	for s in war:
		# Still bombarding an old world target: on to the new one.
		if s.state == Ship.State.BOMBARD and not world_goal:
			s.order_attack_move(goal + Vector2(randf_range(-50, 50), randf_range(-50, 50)))
			continue
		if s.state != Ship.State.IDLE:
			continue
		if s.global_position.distance_to(goal) < FRONT:
			# At the front: a world target is bombarded, anything else
			# attacked (a starbase's guns before a world's population).
			var ep := _nearest_planet(goal, game, func(pl): return pl.is_enemy_of(pid) and (v == null or v.is_visible_at(pl.global_position)))
			if ep and ep.global_position.distance_to(goal) < 150.0 and s.global_position.distance_to(ep.global_position) < 450.0 and _hurts_worlds(s):
				s.order_bombard(ep)
			else:
				s.order_attack_move(goal + Vector2(randf_range(-50, 50), randf_range(-50, 50)))
		else:
			home_idle.append(s)
	# Reinforcements gather at a forward rally short of the target (when no
	# enemy has been seen there lately) and leave it in waves, not one by one.
	var wave_min := clampi(war.size() / 3, 3, 8)
	# Just fell back: no trickle, the next wave is most of the army.
	if _regrouping(st):
		wave_min = maxi(wave_min, ceili(war.size() * REGROUP_SHARE))
	var rally: Vector2 = goal + (base.global_position - goal).normalized() * (FRONT + 300.0)
	var rally_ok: bool = v == null or not _enemy_seen_near(v, rally, 800.0, 30.0)
	var at_rally := home_idle.filter(func(s): return rally_ok and s.global_position.distance_to(rally) < 450.0)
	if rally_ok:
		for s in home_idle:
			if not at_rally.has(s):
				s.order_move(rally + Vector2(randf_range(-100, 100), randf_range(-100, 100)))
	var ready: Array = at_rally if rally_ok else home_idle
	if ready.size() >= wave_min:
		for s in ready:
			s.order_attack_move(goal + Vector2(randf_range(-50, 50), randf_range(-50, 50)))
		for rsa in ships.filter(func(s): return s.ship_type.ends_with("heatshield") and s.state == Ship.State.IDLE and not _escorting(s)):
			rsa.order_move(goal + Vector2(randf_range(-80, 80), randf_range(-80, 80)))

## Fortress assault on `goal` (not winnable by the usual measure, but far
## ahead): the army masses at a staging point out of the target's guns, then
## goes in together (ASSAULT_MASS of it, or less after ASSAULT_WAIT).
## Returns true while the assault is under way (the caller then runs the
## normal front logic: bombard worlds, attack everything else, reinforce in
## waves); false while it is still massing. A wave wiped out at the front
## sends the survivors and the next ships back to mass again.
func _assault(pid: int, st: Dictionary, game: Game, base: Starbase, war: Array, goal: Vector2) -> bool:
	var stage: Vector2 = goal + (base.global_position - goal).normalized() * STAGE_BACK
	if st.get("assault_goal", Vector2.INF) == Vector2.INF or st["assault_goal"].distance_to(goal) > 150.0:
		st["assault_goal"] = goal
		st["assault_since"] = Game.now()
		st["assault_on"] = false
		_flog(pid, "assault: massing for %s (%d,%d), %d warships" % [st.get("commit_kind", "?"), goal.x, goal.y, war.size()])
	var at_front := war.filter(func(s): return s.global_position.distance_to(goal) < FRONT * 0.6)
	if st.get("assault_on", false):
		var c := Vector2.ZERO
		for s in at_front:
			c += s.global_position
		st["assault_center"] = c / at_front.size() if not at_front.is_empty() else stage
		# Wave gone: regroup.
		if at_front.is_empty() and Game.now() - float(st.get("assault_launch", 0.0)) > 30.0:
			st["assault_on"] = false
			st["assault_since"] = Game.now()
			st["assault_waves_lost"] = st.get("assault_waves_lost", 0) + 1
			_flog(pid, "assault: wave lost at (%d,%d), regrouping (%d warships)" % [goal.x, goal.y, war.size()])
			return false
		return true
	st["assault_center"] = stage
	var massed := war.filter(func(s): return s.global_position.distance_to(stage) < 400.0)
	for s in war:
		if s.state == Ship.State.IDLE and s.global_position.distance_to(stage) > 300.0:
			s.order_move(stage + Vector2(randf_range(-100, 100), randf_range(-100, 100)))
	var waited: float = Game.now() - float(st.get("assault_since", Game.now()))
	var need := maxi(OVERWHELM_MIN - 1, ceili(war.size() * (ASSAULT_MASS if waited < ASSAULT_WAIT else 0.5)))
	if massed.size() < need:
		st["assault_mass_s"] = st.get("assault_mass_s", 0.0) + 1.0
		return false
	st["assault_on"] = true
	st["assault_launch"] = Game.now()
	st["assaults"] = st.get("assaults", 0) + 1
	for s in massed:
		s.order_attack_move(goal + Vector2(randf_range(-50, 50), randf_range(-50, 50)))
	_flog(pid, "assault: %d of %d warships go in at %s (%d,%d) after %ds massing" % [massed.size(), war.size(), st.get("commit_kind", "?"), goal.x, goal.y, int(waited)])
	return true

# The AI takes any fight it expects to win, however many ships it costs.
# A side's strength is its total damage per second times its total toughness
# (the duel tests show fights scaling that way); attackers must out-strength
# the defence by WIN_MARGIN squared (just over 1: winning at all is enough).
const WIN_MARGIN := 1.02

## Enemy ships counted as defending a target within this range of it.
const DEFEND_RANGE := 600.0

## Enemy starbases, outposts and battery worlds this close to a target join its defence.
const SUPPORT_RANGE := 450.0

## Damage per second per point of toughness, for enemy ships known only by
## their size (fog of war): about the fleet average across the classes.
const DPS_PER_TOUGH := 0.04

## False for unarmed hulls (every weapon, Interceptor Drones included, can
## bombard a world).
func _hurts_worlds(s: Ship) -> bool:
	return s.def.get("weapon", "") != ""

func _ship_dps(s: Ship, game: Game) -> float:
	if s.def.get("weapon", "") == "":
		return 0.0
	return float(s.def["damage"]) * int(s.def.get("guns", 1)) / maxf(float(s.def["cooldown"]), 0.1) \
		* Defs.mark_mult(s.ship_type, game.mark_level(s.owner_id, s.ship_type)) * game.mod(s.owner_id, "damage")

## [dps, toughness] of whatever defends `at` for the enemies of `pid`: the
## starbase or world there plus enemy warships around it.
## A world's population is not counted: bombarding it down takes time, but
## it never shoots back, so it doesn't decide whether the fight is won (it
## used to make every sizable world look unbeatable, so fleets never went).
func _defence_at(pid: int, at: Vector2, game: Game) -> Vector2:
	var dps := 0.0
	var tough := 0.0
	var v: Vision = game.visions.get(pid)
	# Every enemy starbase close enough to join the fight (yards cluster;
	# counting only the one at the target sent whole fleets to die), and
	# with fog only the ones we have seen, as last seen.
	var sbt: float = Defs.STARBASE["hp"] + Defs.STARBASE["armor"] + Defs.STARBASE["shield"]
	if v:
		for sb in v.seen_bases:
			if v.seen_bases[sb][0].distance_to(at) < SUPPORT_RANGE:
				dps += Defs.construct_dps(Defs.STARBASE)
				tough += sbt * float(v.seen_bases[sb][1])
	else:
		for sb in game.get_tree().get_nodes_in_group("starbases"):
			if game.is_hostile(pid, sb.owner_id) and sb.global_position.distance_to(at) < SUPPORT_RANGE:
				dps += Defs.construct_dps(Defs.STARBASE)
				tough += sb.hp + sb.armor + sb.shield
	# Enemy worlds' batteries and shields: with fog, as this player knows
	# them (in sight: as they are; else as last seen, or a guess).
	for p in game.get_tree().get_nodes_in_group("planets"):
		if p.global_position.distance_to(at) >= SUPPORT_RANGE - 100.0:
			continue
		if v:
			var ko: int = v.known_owner(p)
			if ko <= 0 or ko == pid or not game.is_hostile(pid, ko):
				continue
			var pd := v.planet_defence(p)
			dps += pd.x * Defs.BATTERY["damage"] / Defs.BATTERY["cooldown"]
			tough += pd.y
		elif p.is_enemy_of(pid):
			dps += p.count_building("battery") * Defs.BATTERY["damage"] / Defs.BATTERY["cooldown"]
			tough += p.shield
	# Enemy Frontier Outposts covering the target (only ones we have seen,
	# as last seen).
	var ft: float = Defs.FRONTIER_OUTPOST["hp"] + Defs.FRONTIER_OUTPOST["armor"] + Defs.FRONTIER_OUTPOST["shield"]
	if v:
		for id in v.seen_forts:
			var fm: Array = v.seen_forts[id]
			if game.is_hostile(pid, int(fm[2])) and fm[0].distance_to(at) < SUPPORT_RANGE:
				dps += Defs.construct_dps(Defs.FRONTIER_OUTPOST)
				tough += ft * float(fm[1])
	else:
		for f in game.get_tree().get_nodes_in_group("forts"):
			if f is FrontierOutpost and f.is_alive() and game.is_hostile(pid, f.owner_id) and f.global_position.distance_to(at) < SUPPORT_RANGE:
				dps += Defs.construct_dps(Defs.FRONTIER_OUTPOST)
				tough += f.hp + f.armor + f.shield
	if v:
		# Only what we have seen recently.
		for id in v.sightings:
			var sg: Array = v.sightings[id]
			if Game.now() - sg[0] < 30.0 and at.distance_to(sg[2]) < DEFEND_RANGE:
				tough += sg[1]
				# Its class is plain to see: its guns (base marks) beat a guess.
				var cd: Dictionary = Defs.SHIPS.get(sg[4], {}) if sg.size() > 4 else {}
				if cd.has("damage"):
					dps += float(cd["damage"]) * int(cd.get("guns", 1)) / maxf(float(cd["cooldown"]), 0.1)
				else:
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
			# Committed: the gate is the reinforcement line - smaller batches
			# go straight to the army's target.
			var committed: bool = st.get("commit", false) and st.has("commit_target")
			if g.cooldown_left <= 0.0 and committed and inside.size() >= 3:
				var ct: Vector2 = st["commit_target"]
				var land3 := _landing(ct, g, game)
				if land3 != Vector2.INF and _warp_wave(pid, st, g, land3, ct, "reinforce"):
					continue
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


# ======================================================================
# DEFENSE
# ======================================================================
# Home starbase, harvesters and besieged yards.

## DEFENSE protocol: enemies at the home starbase pull the fleet in when the
## fight can be held, else gather at a safe rally. True while defending.
func _defense_protocol(cx: Ctx) -> bool:
	var pid: int = cx.pid
	var st: Dictionary = cx.st
	var game: Game = cx.game
	var base: Starbase = cx.base
	var v: Vision = cx.v
	var war: Array = cx.war
	# Defend: enemies near the starbase pull every warship home.
	var threat := game.nearest_enemy(base, 450.0)
	# Only enemies our sensors can actually see (not ones hidden in a nebula).
	if threat and v and not v.can_see(threat):
		threat = null
	if threat:
		# A fight it can hold (with the starbase's guns): everyone in. One it
		# can't: whoever is already in it fights, the rest (and new hulls)
		# gather at a safe rally point until together they can, instead of
		# trickling in one at a time to die.
		var tp: Vector2 = threat.global_position
		if _can_hold(pid, war, base, tp, game):
			st.erase("rally")
			for s in war:
				if s.state != Ship.State.ATTACK:
					s.order_attack_move(tp)
		else:
			var rally := _safe_rally(pid, st, game, base, tp)
			st["rally"] = rally
			for s in war:
				if s.global_position.distance_to(tp) < 300.0:
					if s.state != Ship.State.ATTACK:
						s.order_attack_move(tp)
				elif s.global_position.distance_to(rally) > 150.0 and s.move_goal.distance_to(rally) > 150.0:
					s.order_move(rally + Vector2(randf_range(-60, 60), randf_range(-60, 60)))
		return true
	st.erase("rally")
	return false

## Harvesters with enemy warships at them: idle warships that can win go
## to them; with none, the harvesters run for the nearest yard.
func _guard_harvesters(pid: int, st: Dictionary, game: Game, war: Array, ships: Array, v: Vision) -> void:
	if v == null or Game.now() < st.get("next_guard", 0.0):
		return
	st["next_guard"] = Game.now() + 3.0
	var idle := war.filter(func(s): return s.state == Ship.State.IDLE)
	for h in ships:
		if not h.def["role"] in ["miner", "skimmer", "constructor"] or v.enemy_near(h.global_position, 380.0) == 0:
			continue
		var yard := game.nearest_starbase(pid, h.global_position)
		if yard and yard.global_position.distance_to(h.global_position) < 450.0:
			continue
		var near := idle.filter(func(s): return s.global_position.distance_to(h.global_position) < 2200.0)
		if not near.is_empty() and _can_win(pid, near, h.global_position, game):
			for s in near:
				s.order_attack_move(h.global_position + Vector2(randf_range(-40, 40), randf_range(-40, 40)))
				idle.erase(s)
			_flog(pid, "escort: %d warships to %s under attack at (%d,%d)" % [near.size(), h.def["role"], h.global_position.x, h.global_position.y])
		elif yard and h.state != Ship.State.BUILD:
			h.order_move(yard.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60)))

## A yard with enemies at it that the defence can't hold builds no warships
## (they would die as they launch) - as long as another yard can.
func _yard_besieged(pid: int, st: Dictionary, b: Starbase, v: Vision) -> bool:
	if v == null or not st.has("rally") or v.enemy_near(b.global_position, 600.0) == 0:
		return false
	return Game.instance.get_tree().get_nodes_in_group("starbases").any(func(o): return o != b and o.owner_id == pid and not o.under_construction and v.enemy_near(o.global_position, 900.0) == 0)

## True if `war` plus the starbase's own guns should beat the enemies at `at`.
func _can_hold(pid: int, war: Array, base: Starbase, at: Vector2, game: Game) -> bool:
	var dps := Defs.construct_dps(Defs.STARBASE) if base.global_position.distance_to(at) < 600.0 else 0.0
	var tough := base.hp + base.armor + base.shield if dps > 0.0 else 0.0
	for s in war:
		dps += _ship_dps(s, game)
		tough += s.hp + s.armor + s.shield
	var d := _defence_at(pid, at, game)
	return dps * tough > d.x * d.y * 0.8

## Where a fleet that can't hold gathers: the own yard farthest from the
## fight with no enemies near it, else a point behind home away from them.
func _safe_rally(pid: int, st: Dictionary, game: Game, base: Starbase, threat: Vector2) -> Vector2:
	var v: Vision = game.visions.get(pid)
	var best := Vector2.INF
	var best_d := 1200.0
	for b in game.get_tree().get_nodes_in_group("starbases"):
		if b.owner_id != pid or b.under_construction:
			continue
		var d: float = b.global_position.distance_to(threat)
		if d > best_d and (v == null or v.enemy_near(b.global_position, 900.0) == 0):
			best_d = d
			best = b.global_position + (b.global_position - threat).normalized() * 150.0
	if best != Vector2.INF:
		return best
	var away := (base.global_position - threat).normalized()
	if away == Vector2.ZERO:
		away = -base.global_position.normalized()
	var q: Vector2 = base.global_position + away * 800.0
	return q.limit_length(Game.MAP_RADIUS - 250.0)


# ======================================================================
# PRESERVATION
# ======================================================================
# (Rules in the block comment below.)

# Ships, constructs and worlds are kept alive unless losing some buys
# something worth it. Every PRESERVE_EVERY seconds each local fight (own
# warships with an enemy in sight) is weighed with what this side can see
# or remembers (its Vision, never hidden information): own guns x toughness
# (plus own starbases / outposts in range) against _defence_at. A fight
# whose odds, raised by what it is for (OBJ_*), fall below PRESERVE_WEIGHT
# is left: the whole group falls back to a safe rally and regroups into one
# bigger wave. Badly hurt ships peel off home when the rest still win.
# Never left: the last stand at its only starbase.

## How much own losses weigh against what a fight buys: a fight is left when
## sqrt(own power / enemy power) x (1 + objective bonus) drops below this.
const PRESERVE_WEIGHT := 0.9

## Objective bonuses: an enemy starbase or Constructor (ends a side), own
## world / starbase / construct defended, an enemy group about to die.
const OBJ_GAME_WIN := 0.5

const OBJ_DEFEND := 0.3

const OBJ_FINISH := 0.3
## Bonus while this side is far ahead overall (overwhelm / finishing).
const OBJ_AHEAD := 0.4

## A group this battered (share of its toughness left) leaves an even fight.
const PRESERVE_BATTERED := 0.4

## A ship under this share of its toughness peels off (if the rest still win).
const PEEL_AT := 0.3

## Seconds a retreating group takes no other orders; a peeled ship stays
## home until healed past PEEL_BACK (or PEEL_MAX seconds).
const RETREAT_HOLD := 40.0

const PEEL_BACK := 0.7

const PEEL_MAX := 120.0

## After a retreat, the next wave waits for this share of the army (seconds).
const REGROUP_FOR := 120.0

const REGROUP_SHARE := 0.7

const PRESERVE_EVERY := 2.0

## Enemies this close to a warship make it part of a fight.
const FIGHT_RANGE := 600.0

## Own warships this close to an engaged one fight as one group.
const GROUP_RANGE := 900.0

func _tough_frac(s: Ship) -> float:
	return (s.hp + s.armor + s.shield) / maxf(s.max_hp + s.max_armor + s.max_shield, 1.0)

## True while `s` is retreating or peeled off (other fleet code leaves it be).
func _held_back(st: Dictionary, s: Ship) -> bool:
	var h: Dictionary = st.get("held", {})
	var id := s.get_instance_id()
	if not h.has(id):
		return false
	var e: Array = h[id]
	if Game.now() < float(e[0]):
		return true
	# Peeled: until healed, or PEEL_MAX.
	if e[1] and _tough_frac(s) < PEEL_BACK and Game.now() < float(e[0]) + PEEL_MAX - RETREAT_HOLD:
		return true
	h.erase(id)
	return false

func _hold(st: Dictionary, s: Ship, peeled: bool) -> void:
	if not st.has("held"):
		st["held"] = {}
	st["held"][s.get_instance_id()] = [Game.now() + RETREAT_HOLD, peeled]

func _regrouping(st: Dictionary) -> bool:
	return Game.now() < float(st.get("regroup_until", -1.0))

## Own power at `at`: `ships` plus own starbases and outposts in range.
func _own_power(pid: int, ships: Array, at: Vector2, game: Game) -> Vector2:
	var dps := 0.0
	var tough := 0.0
	for s in ships:
		dps += _ship_dps(s, game)
		tough += s.hp + s.armor + s.shield
	for sb in game.get_tree().get_nodes_in_group("starbases"):
		if sb.owner_id == pid and sb.is_alive() and not sb.under_construction and sb.global_position.distance_to(at) < SUPPORT_RANGE:
			dps += Defs.construct_dps(Defs.STARBASE)
			tough += sb.hp + sb.armor + sb.shield
	for f in game.get_tree().get_nodes_in_group("forts"):
		if f is FrontierOutpost and f.owner_id == pid and f.is_alive() and f.global_position.distance_to(at) < SUPPORT_RANGE:
			dps += Defs.construct_dps(Defs.FRONTIER_OUTPOST)
			tough += f.hp + f.armor + f.shield
	return Vector2(dps, tough)

## What a fight at `at` is for: OBJ_* bonus, or INF for a last stand.
func _objective(pid: int, at: Vector2, own_t: float, enemy_t: float, game: Game, v: Vision) -> float:
	var bases: Array = game.get_tree().get_nodes_in_group("starbases").filter(func(b): return b.owner_id == pid and not b.under_construction)
	if bases.size() <= 1 and (bases.is_empty() or bases[0].global_position.distance_to(at) < 900.0):
		return INF
	var bonus := 0.0
	for sb in game.get_tree().get_nodes_in_group("starbases"):
		if game.is_hostile(pid, sb.owner_id) and sb.is_alive() and sb.global_position.distance_to(at) < 500.0 and (v == null or v.can_see(sb)):
			bonus = OBJ_GAME_WIN
	if bonus == 0.0:
		for s in game.get_tree().get_nodes_in_group("ships"):
			if game.is_hostile(pid, s.owner_id) and s.def["role"] == "constructor" and s.global_position.distance_to(at) < 500.0 and (v == null or v.can_see(s)):
				bonus = OBJ_GAME_WIN
				break
	var defending := bases.any(func(b): return b.global_position.distance_to(at) < 700.0)
	if not defending:
		for p in game.get_tree().get_nodes_in_group("planets"):
			if p.owner_id == pid and p.global_position.distance_to(at) < 700.0:
				defending = true
				break
	if not defending:
		for grp in ["mining_stations", "depots", "forts"]:
			if game.get_tree().get_nodes_in_group(grp).any(func(e): return e.owner_id == pid and e.global_position.distance_to(at) < 600.0):
				defending = true
				break
	if defending:
		bonus += OBJ_DEFEND
	if enemy_t < own_t * 0.3:
		bonus += OBJ_FINISH
	return bonus

func _preserve(pid: int, st: Dictionary, game: Game, base: Starbase, war: Array, v: Vision) -> void:
	if v == null or Game.now() < st.get("next_preserve", 0.0):
		return
	st["next_preserve"] = Game.now() + PRESERVE_EVERY
	# Local fights: warships with an enemy in sight, each with every free
	# warship of ours within GROUP_RANGE of it (one fleet is one group, not
	# split along a grid into fragments that each look outmatched).
	var free := war.filter(func(s): return not _held_back(st, s))
	var groups: Array = []
	var taken := {}
	for s in free:
		if taken.has(s) or v.enemy_near(s.global_position, FIGHT_RANGE) == 0:
			continue
		var g: Array = free.filter(func(o): return not taken.has(o) and o.global_position.distance_to(s.global_position) < GROUP_RANGE)
		for o in g:
			taken[o] = true
		groups.append(g)
	for g: Array in groups:
		var c := Vector2.ZERO
		for s in g:
			c += s.global_position
		c /= g.size()
		var enemy := _defence_at(pid, c, game)
		var pw_e: float = enemy.x * enemy.y
		if pw_e <= 0.0:
			continue
		var own := _own_power(pid, g, c, game)
		var obj := _objective(pid, c, own.y, enemy.y, game, v)
		if obj == INF:
			continue
		# Clearly ahead overall: press on through rougher local odds to close
		# the game (losses are replaced faster than the enemy's).
		if st.get("overwhelm", false) or st.get("finishing", false):
			obj += OBJ_AHEAD
		var odds: float = sqrt(own.x * own.y / pw_e)
		var left := 0.0
		var full := 0.0
		for s in g:
			left += s.hp + s.armor + s.shield
			full += s.max_hp + s.max_armor + s.max_shield
		var battered: bool = left < full * PRESERVE_BATTERED and odds < 1.2
		if odds * (1.0 + obj) < PRESERVE_WEIGHT or battered:
			var to := _safe_rally(pid, st, game, base, c)
			for s in g:
				s.order_move(to + Vector2(randf_range(-80, 80), randf_range(-80, 80)))
				_hold(st, s, false)
			st["retreats"] = st.get("retreats", 0) + 1
			st["regroup_until"] = Game.now() + REGROUP_FOR
			game.stats.count(pid, "ai_retreats")
			_flog(pid, "retreat: %d warships from (%d,%d), odds %.2f obj %.1f%s" % [g.size(), c.x, c.y, odds, obj, " battered" if battered else ""])
			continue
		# Winning: the worst-hurt ships go home while the rest still win.
		var keep: Array = g.duplicate()
		for s in g:
			if _tough_frac(s) >= PEEL_AT or keep.size() <= 1:
				continue
			var rest: Array = keep.filter(func(o): return o != s)
			var p2 := _own_power(pid, rest, c, game)
			if sqrt(p2.x * p2.y / pw_e) * (1.0 + obj) >= PRESERVE_WEIGHT * 1.2:
				keep = rest
				var home := game.nearest_starbase(pid, s.global_position)
				var to: Vector2 = home.global_position if home and v.enemy_near(home.global_position, 600.0) == 0 else _safe_rally(pid, st, game, base, c)
				s.order_move(to + Vector2(randf_range(-60, 60), randf_range(-60, 60)))
				_hold(st, s, true)
				game.stats.count(pid, "ai_peels")
