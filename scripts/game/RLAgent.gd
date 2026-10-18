class_name RLAgent
extends Node
## The learning AI's body in the game. It runs its whole side - nothing comes
## from the scripted AI - and it can give every order a human player can.
##
## Every DECIDE seconds it describes the match to a Python trainer (tools/rl/)
## over a local TCP socket, receives a list of orders and carries them out.
## Built to ADAPT to new rules, so nothing here names a ship, tech, building
## or map feature:
##   entities - everything it can see, each a feature vector (kind, owner
##              relation, position, health layers, firepower, reach, speed);
##   actors   - every unit, starbase, station, depot and world it owns, plus
##              the empire itself (for research), each with a mask of the
##              VERBS it can use right now;
##   objects  - everything that can be built or researched (every ship,
##              building, construct and tech the game defines), described by
##              its stats hashed into a fixed-size vector, so a new one is
##              simply one more row;
##   targets  - every entity above, plus points on a grid over the system.
## An order is {actor, verb, object, target} (-1 where unused); the trainer
## may send any number per step. Invalid orders are ignored.
##
## Protocol: one JSON object per line each way. Game -> trainer: the
## observation (with "done", "won", "lost", "score", "enemy_score").
## Trainer -> game: {"orders": [[actor, verb, object, target], ...]} or
## {"quit": true}. Started with SL_RL_PORT (+ SL_RL_SIDE) in a sim (SL_SIM).

const DECIDE := 2.0
const MAX_ENTITIES := 220
## Hash buckets for any definition's stats (present or future keys).
const OBJ_BUCKETS := 48
## Grid of target points over the system (GRID x GRID, inside the disc).
const GRID := 12
const KINDS := ["ship", "starbase", "station", "depot", "planet", "asteroid", "nebula", "storm", "star", "point"]
## Every order the game has, as engine-level verbs.
const VERBS := ["stop", "move", "attack_move", "attack", "mine", "return", "colonize", "bombard",
	"dock", "refit", "found", "ability", "build_ship", "cancel_ship", "rally",
	"build_building", "cancel_building", "demolish", "research", "cancel_research"]
## What kind of object each object row is (one-hot in its features).
const OBJ_KINDS := ["ship", "building", "construct", "tech"]

var pid: int = 1
var _tcp := StreamPeerTCP.new()
var _buf := ""
var _next := 0.0
var _done_sent := false
## This step's lookups, so the trainer's indices can be resolved.
var _ents: Array = []        # Node2D per entity row
var _actors: Array = []      # [kind, node] per actor row ("empire" has null)
var _objects: Array = []     # [kind, id, extra] per object row
var _targets: Array = []     # Node2D or Vector2 per target row
## How often each verb was used (dev reports read it).
var counts := {}
## SL_TRACE=<file>: each decision, one JSON line of where everything is, for
## the trainer's replay images (tools/rl/replay.py).
var _trace: FileAccess = null
var _found := {}   # enemy starbases / worlds seen this match (instance id)

func _init(side: int, port: int) -> void:
	pid = side
	_tcp.connect_to_host("127.0.0.1", port)
	var t0 := Time.get_ticks_msec()
	while _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() - t0 < 10000:
		_tcp.poll()
		OS.delay_msec(5)
	if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		push_error("RLAgent: no trainer on port %d" % port)

func _ready() -> void:
	Game.instance.match_over.connect(func(_won: bool): _finish())

func _exit_tree() -> void:
	_finish()

## Called from AIController._think (once a second) - the only thing the
## AIController does for this side.
func tick(game: Game, base: Starbase, _ai: AIController) -> void:
	if Game.now() < _next or _done_sent:
		return
	_next = Game.now() + DECIDE
	_send(_observe(game, base, false))
	_write_trace(game)
	var reply := _receive()
	if reply.get("quit", false):
		game.get_tree().quit()
		return
	for o in reply.get("orders", []):
		if o is Array and o.size() == 4:
			_order(game, int(o[0]), int(o[1]), int(o[2]), int(o[3]))

func _finish() -> void:
	if _done_sent or _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	_done_sent = true
	var game := Game.instance
	if game:
		_send(_observe(game, game.nearest_starbase(pid, Vector2.ZERO), true))

# ---------------------------------------------------------------- observe

func _observe(game: Game, base: Starbase, done: bool) -> Dictionary:
	var home: Vector2 = base.global_position if base else _centroid(game)
	var r: Dictionary = game.resources[pid]
	var rt: Dictionary = game.rates.get(pid, {})
	var me := [r.get("food", 0.0) / 1000.0, r.get("minerals", 0.0) / 1000.0, r.get("energy", 0.0) / 1000.0, r.get("spice", 0.0) / 1000.0,
		rt.get("food", 0.0), rt.get("minerals", 0.0), rt.get("energy", 0.0), rt.get("spice", 0.0),
		game.total_pop(pid) / 10000.0, Game.now() / 3600.0, float(game.players.size()) / 8.0,
		game.upkeep(pid) / 60.0, float(game.researched[pid].size()) / 40.0]
	var ents := _entities(game, home)
	return {
		"t": Game.now(), "pid": pid, "self": me, "done": done,
		"won": game.winner_pid == pid or (done and not game.is_defeated(pid) and game.living_players().size() == 1),
		"lost": game.is_defeated(pid),
		"score": game.stats.score(pid),
		"enemy_score": _enemy_score(game),
		"closed": _fleet_distance(game),
		"gathered": _fleet_cohesion(game),
		"tally": {"ship_kills": game.stats.get_count(pid, "ship_kills"), "construct_kills": game.stats.get_count(pid, "construct_kills"),
			"starbase_kills": game.stats.get_count(pid, "starbase_kills"), "starbase_damage": game.stats.get_count(pid, "starbase_damage"),
			"damage_dealt": game.stats.get_count(pid, "damage_dealt"), "pop_bombarded": game.stats.get_count(pid, "pop_bombarded"), "discovered": game.stats.get_count(pid, "discovered"),
			"damage_hurt": game.stats.get_count(pid, "damage_hurt"), "starbase_hurt": game.stats.get_count(pid, "starbase_hurt"), "planet_kills": game.stats.get_count(pid, "planet_kills"),
			"colonized": game.stats.get_count(pid, "colonized"), "kill_value": game.stats.get_count(pid, "kill_value"), "lost_value": game.stats.get_count(pid, "lost_value")},
		"entities": ents,
		# Dev (SL_RL_LABELS): the entity row of a visible enemy starbase, as a
		# ground-truth label for offline perception tests. Never used in training.
		"label_foe_sb": _ents.find(_ents.filter(func(e): return e is Starbase and e.is_enemy_of(pid)).front()) if OS.get_environment("SL_RL_LABELS") != "" and _ents.any(func(e): return e is Starbase and e.is_enemy_of(pid)) else -1,
		"actors": _actor_rows(game, home),
		"objects": _object_rows(game),
		"targets": _target_rows(game, home, ents.size()),
		"verbs": VERBS.size(),
	}

func _centroid(game: Game) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for s in game.get_tree().get_nodes_in_group("entities"):
		if s.owner_id == pid:
			c += s.global_position
			n += 1
	return c / n if n > 0 else Vector2.ZERO

func _enemy_score(game: Game) -> float:
	var best := 0.0
	for p in game.players:
		if game.is_hostile(pid, p):
			best = maxf(best, game.stats.score(p))
	return best

func _rel(owner: int, game: Game) -> Array:
	if owner == pid:
		return [1, 0, 0, 0]
	if owner == 0:
		return [0, 0, 0, 1]
	return [0, 1, 0, 0] if game.are_allies(pid, owner) else [0, 0, 1, 0]

func _onehot(names: Array, k: String) -> Array:
	return names.map(func(n): return 1 if n == k else 0)

## One entity feature row (see the class doc).
func _row(kind: String, owner: int, pos: Vector2, home: Vector2, hp: float, armor: float, shield: float, frac: float, dps: float, reach: float, speed: float, size: float, extra: float, game: Game) -> Array:
	var rel := pos - home
	var row := _onehot(KINDS, kind) + _rel(owner, game)
	row.append_array([rel.x / Game.MAP_RADIUS, rel.y / Game.MAP_RADIUS, pos.x / Game.MAP_RADIUS, pos.y / Game.MAP_RADIUS,
		log(1.0 + hp) / 8.0, log(1.0 + armor) / 8.0, log(1.0 + shield) / 8.0, frac,
		log(1.0 + dps) / 5.0, reach / 1000.0, speed / 200.0, size / 100.0, extra])
	return row

func _entity_row(e: Node2D, home: Vector2, game: Game, v: Vision) -> Array:
	if e is Planet:
		var p: Planet = e
		var o: int = v.known_owner(p) if v else p.owner_id
		return _row("planet", o, p.global_position, home, p.pop, 0.0, p.shield, p.pop / maxf(p.max_pop(), 1.0), 0.0, 0.0, 0.0, p.radius, float(p.free_fields()) / 30.0, game)
	if e is Asteroid:
		return _row("asteroid", 0, e.global_position, home, float(e.amount), 0.0, 0.0, 1.0 if e.resource == "spice" else 0.0, 0.0, 0.0, 0.0, e.radius, 0.0, game)
	if e is SpiceNebula:
		return _row("nebula", 0, e.global_position, home, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, (e.radius if e.shape == "cloud" else e.outer) / 10.0, 0.0, game)
	if e is IonStorm:
		return _row("storm", 0, e.global_position, home, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, e.radius / 10.0, 0.0, game)
	if e.is_in_group("stars"):
		return _row("star", 0, e.global_position, home, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, e.core_radius, 0.0, game)
	var kind := "ship" if e is Ship else ("starbase" if e is Starbase else ("station" if e is MiningStation else "depot"))
	var dps := 0.0
	var reach := 0.0
	var speed := 0.0
	var extra := 0.0
	if e is Ship:
		var s: Ship = e
		if s.def.get("weapon", "") != "":
			dps = float(s.def["damage"]) * int(s.def.get("guns", 1)) / maxf(float(s.def["cooldown"]), 0.1)
			reach = s.weapon_range()
		speed = s.max_speed()
		extra = float(s.cargo) / 100.0
	var mx: float = e.max_hp + e.max_armor + e.max_shield
	return _row(kind, e.owner_id, e.global_position, home, e.max_hp, e.max_armor, e.max_shield, (e.hp + e.armor + e.shield) / maxf(mx, 1.0), dps, reach, speed, e.radius, extra, game)

## Everything it can see, nearest to home first (its own things always).
func _entities(game: Game, home: Vector2) -> Array:
	var v: Vision = game.visions.get(pid)
	var tree := game.get_tree()
	var cand: Array = []
	for e in tree.get_nodes_in_group("entities"):
		if e.is_alive() and (e.owner_id == pid or v == null or v.can_see(e)):
			cand.append(e)
	cand.append_array(tree.get_nodes_in_group("planets"))
	for a in tree.get_nodes_in_group("asteroids"):
		if v == null or v.is_explored_at(a.global_position):
			cand.append(a)
	cand.append_array(tree.get_nodes_in_group("nebulae"))
	cand.append_array(tree.get_nodes_in_group("storms"))
	cand.append_array(tree.get_nodes_in_group("stars"))
	# Training tally: each enemy starbase or world the first time it's seen.
	for e in cand:
		var o = e.get("owner_id")
		if o != null and o != 0 and game.is_hostile(pid, o) and (e is Starbase or e is Planet) 				and not _found.has(e.get_instance_id()) and (v == null or v.is_visible_at(e.global_position)):
			_found[e.get_instance_id()] = true
			game.stats.count(pid, "discovered")
	cand.sort_custom(func(x, y): return (0 if x.get("owner_id") == pid else 1) * 1e6 + home.distance_to(x.global_position) < (0 if y.get("owner_id") == pid else 1) * 1e6 + home.distance_to(y.global_position))
	_ents = cand.slice(0, MAX_ENTITIES)
	return _ents.map(func(e): return _entity_row(e, home, game, v))

## Its own units, buildings and worlds (each pointing at its entity row),
## plus the empire, each with a mask over VERBS.
func _actor_rows(game: Game, home: Vector2) -> Array:
	_actors = [["empire", null]]
	var idle_research: bool = game.research[pid].is_empty() and game.research_queue[pid].is_empty()
	var rows: Array = [{"entity": -1, "mask": _mask({"research": idle_research, "cancel_research": not idle_research})}]
	for i in _ents.size():
		var e: Node2D = _ents[i]
		if e.get("owner_id") != pid:
			continue
		var m := {}
		if e is Ship:
			var s: Ship = e
			if s.docked:
				continue
			var armed: bool = s.def.get("weapon", "") != ""
			m = {"stop": true, "move": true, "attack_move": armed, "attack": armed, "bombard": armed,
				"mine": s.is_miner(), "return": s.is_miner() and s.cargo > 0,
				"colonize": s.def["role"] == "colony", "found": s.def["role"] == "constructor",
				"dock": s.fits_bay(), "refit": not s.def.has("variant") and Defs.VARIANTS_OF.has(s.ship_type),
				"ability": not Abilities.job_def(s).is_empty() and Abilities.job_def(s).get("active", false) and Abilities.ready_in(s) <= 0.0}
		elif e is Starbase:
			var sb: Starbase = e
			m = {"build_ship": not sb.under_construction, "cancel_ship": not sb.queue.is_empty(), "rally": not sb.under_construction}
		elif e is Planet:
			var p: Planet = e
			m = {"build_building": p.free_fields() > 0, "cancel_building": not p.construction.is_empty() or not p.construction_queue.is_empty(),
				"demolish": p.buildings.any(func(b): return b != "")}
		elif e is WeaponsDepot:
			m = {"cancel_ship": not e.bays.is_empty()}
		else:
			continue
		_actors.append(["entity", e])
		rows.append({"entity": i, "mask": _mask(m)})
	# Group orders: each cluster of 2+ of its armed ships (within GROUP_RADIUS
	# of the first one, in nearest-to-home order) is also an actor, shown as
	# its lead ship's row with "group" set. An order to it goes to every ship
	# in it, so one decision can move a fleet; single ships stay orderable.
	var taken := {}
	for i in _ents.size():
		var lead = _ents[i]
		if not (lead is Ship) or lead.owner_id != pid or lead.docked or lead.def.get("weapon", "") == "" or taken.has(lead):
			continue
		var grp: Array = []
		for j in range(i, _ents.size()):
			var s2 = _ents[j]
			if s2 is Ship and s2.owner_id == pid and not s2.docked and s2.def.get("weapon", "") != "" and not taken.has(s2) \
					and s2.global_position.distance_to(lead.global_position) <= GROUP_RADIUS:
				grp.append(s2)
		if grp.size() < 2:
			continue
		for s3 in grp:
			taken[s3] = true
		_actors.append(["group", grp])
		rows.append({"entity": i, "group": grp.size(),
			"mask": _mask({"stop": true, "move": true, "attack_move": true, "attack": true, "bombard": true})})
	return rows

## How close (units) ships must be to the lead to join its group order.
const GROUP_RADIUS := 250.0

func _mask(m: Dictionary) -> Array:
	return VERBS.map(func(vb): return 1 if m.get(vb, false) else 0)

## A definition's stats, hashed into OBJ_BUCKETS (log-scaled, signed), so any
## field - including ones added later - lands somewhere.
func _hash_stats(d: Dictionary, prefix: String = "") -> Array:
	var out := []
	out.resize(OBJ_BUCKETS)
	out.fill(0.0)
	_hash_into(out, d, prefix)
	return out

func _hash_into(out: Array, d: Dictionary, prefix: String) -> void:
	for k in d:
		var val = d[k]
		var key := prefix + str(k)
		if val is Dictionary:
			_hash_into(out, val, key + ".")
		elif val is float or val is int:
			var x := float(val)
			out[hash(key) % OBJ_BUCKETS] += signf(x) * log(1.0 + absf(x))
		elif val is bool:
			out[hash(key) % OBJ_BUCKETS] += 1.0 if val else 0.0
		elif val is String and k in ["role", "job", "weapon", "variant", "group", "line", "class", "base"]:
			out[hash(key + "=" + val) % OBJ_BUCKETS] += 1.0

## Every ship, building, construct and tech the game defines.
func _object_rows(game: Game) -> Array:
	_objects = []
	var rows: Array = []
	for t in Defs.SHIPS:
		if Defs.SHIPS[t].has("variant"):
			continue   # variants come from refits, not starbases
		_objects.append(["ship", t, ""])
		rows.append(_onehot(OBJ_KINDS, "ship") + [1.0 if Game.instance.nearest_starbase(pid, Vector2.ZERO) and Game.instance.nearest_starbase(pid, Vector2.ZERO).can_queue(t) == "" else 0.0] + _hash_stats(Defs.SHIPS[t]))
	for b in Defs.BUILDINGS:
		_objects.append(["building", b, ""])
		rows.append(_onehot(OBJ_KINDS, "building") + [1.0] + _hash_stats(Defs.BUILDINGS[b]))
	_objects.append(["construct", "starbase", ""])
	rows.append(_onehot(OBJ_KINDS, "construct") + [1.0] + _hash_stats(Defs.STARBASE))
	_objects.append(["construct", "station", ""])
	rows.append(_onehot(OBJ_KINDS, "construct") + [1.0] + _hash_stats(Defs.MINING_STATION))
	var depots_ok := game.has_tech(pid, str(Defs.WEAPONS_DEPOT["requires"]))
	for v in Defs.VARIANTS:
		_objects.append(["construct", "depot", v])
		rows.append(_onehot(OBJ_KINDS, "construct") + [1.0 if depots_ok else 0.0] + _add(_hash_stats(Defs.WEAPONS_DEPOT), _hash_stats(Defs.VARIANTS[v], "variant.")))
	for id in Defs.TECHS:
		_objects.append(["tech", id, ""])
		rows.append(_onehot(OBJ_KINDS, "tech") + [1.0 if game.tech_state(pid, id) == "available" else 0.0] + _hash_stats(Defs.TECHS[id]))
	return rows

func _add(a: Array, b: Array) -> Array:
	var out := a.duplicate()
	for i in out.size():
		out[i] += b[i]
	return out

## Targets: every entity row (by index, so the trainer can reuse their
## encodings), then grid points over the system.
func _target_rows(game: Game, home: Vector2, n_ents: int) -> Array:
	_targets = _ents.duplicate()
	var pts: Array = []
	var step := Game.MAP_RADIUS * 2.0 / GRID
	for gy in GRID:
		for gx in GRID:
			var p := Vector2(-Game.MAP_RADIUS + (gx + 0.5) * step, -Game.MAP_RADIUS + (gy + 0.5) * step)
			if p.length() > Game.MAP_RADIUS - 40.0:
				continue
			_targets.append(p)
			var v: Vision = game.visions.get(pid)
			pts.append(_row("point", 0, p, home, 0, 0, 0, 1.0 if v and v.is_explored_at(p) else 0.0, 0, 0, 0, 0, 0, game))
	return pts

# ---------------------------------------------------------------- act

func _order(game: Game, ai: int, vi: int, oi: int, ti: int) -> void:
	if ai < 0 or ai >= _actors.size() or vi < 0 or vi >= VERBS.size():
		return
	var verb: String = VERBS[vi]
	if _actors[ai][0] == "group":
		# The same order for every ship still alive in the group.
		var ships: Array = _actors[ai][1]
		_actors[ai] = ["entity", null]
		for s in ships:
			if is_instance_valid(s):
				_actors[ai][1] = s
				_order(game, ai, vi, oi, ti)
		_actors[ai] = ["group", ships]
		return
	var actor = _actors[ai][1]
	if actor != null and not is_instance_valid(actor):
		return
	var obj: Array = _objects[oi] if oi >= 0 and oi < _objects.size() else []
	var tgt = _targets[ti] if ti >= 0 and ti < _targets.size() else null
	if tgt is Object and not is_instance_valid(tgt):
		return
	var pos: Vector2 = (tgt.global_position if tgt is Node2D else tgt) if tgt != null else Vector2.INF
	counts[verb] = counts.get(verb, 0) + 1
	match verb:
		"research":
			if not obj.is_empty() and obj[0] == "tech":
				game.queue_research(pid, obj[1])
		"cancel_research":
			var cur: String = game.research[pid].get("id", "")
			if cur != "":
				game.cancel_research(pid, cur)
		"stop":
			actor.order_stop()
		"move":
			if pos != Vector2.INF:
				actor.order_move(pos.limit_length(Game.MAP_RADIUS - 20.0))
		"attack_move":
			if pos != Vector2.INF:
				actor.order_attack_move(pos.limit_length(Game.MAP_RADIUS - 20.0))
		"attack":
			if tgt is SpaceEntity and tgt.is_enemy_of(pid):
				actor.order_attack(tgt)
		"bombard":
			if tgt is Planet and tgt.is_enemy_of(pid):
				actor.order_bombard(tgt)
		"mine":
			if tgt != null and tgt is Node2D and actor.can_mine(tgt):
				actor.order_mine(tgt)
			elif pos != Vector2.INF and game.in_nebula(pos):
				var pocket := game.nebula_pocket_at(pos)
				if pocket and actor.can_mine(pocket):
					actor.order_mine(pocket)
		"return":
			actor.order_return(tgt if tgt is SpaceEntity and tgt.owner_id == pid else null)
		"colonize":
			if tgt is Planet and tgt.owner_id == 0 and tgt.is_habitable():
				actor.order_colonize(tgt)
		"dock":
			if tgt is Ship and tgt.owner_id == pid and tgt.is_carrier():
				actor.order_dock(tgt)
		"refit":
			if tgt is WeaponsDepot and tgt.owner_id == pid and actor.can_refit(tgt.variant):
				actor.order_refit(tgt.variant, tgt)
		"found":
			if not obj.is_empty() and obj[0] == "construct" and pos != Vector2.INF:
				match obj[1]:
					"starbase": actor.order_build_starbase(pos)
					"station": actor.order_build_station(pos)
					"depot": actor.order_build_depot(pos, obj[2])
		"ability":
			Abilities.use(actor)
		"build_ship":
			if not obj.is_empty() and obj[0] == "ship" and actor is Starbase:
				actor.enqueue(obj[1])
		"cancel_ship":
			if actor is Starbase and not actor.queue.is_empty():
				actor.cancel(actor.queue.size() - 1)
			elif actor is WeaponsDepot:
				actor.cancel_all()
		"rally":
			if actor is Starbase and pos != Vector2.INF:
				actor.set_rally(pos, tgt if tgt is Node2D else null)
		"build_building":
			if not obj.is_empty() and obj[0] == "building" and actor is Planet:
				for f in actor.fields:
					if actor.can_build(f, obj[1]) == "":
						actor.order_build(f, obj[1])
						break
		"cancel_building":
			if actor is Planet:
				var f: int = actor.construction.get("field", -1)
				if f < 0 and not actor.construction_queue.is_empty():
					f = actor.construction_queue[-1]["field"]
				if f >= 0:
					actor.cancel_build(f)
		"demolish":
			if actor is Planet and not obj.is_empty() and obj[0] == "building":
				var f2: int = actor.buildings.find(obj[1])
				if f2 >= 0:
					actor.demolish(f2)

# ---------------------------------------------------------------- wire

## Training: how far its spearhead (the 8 warships closest to a seen enemy
## starbase) has closed in, summed over the match. Each decision adds the
## mean of how much nearer those ships got; ships that died or were built
## since don't count, so losses don't read as retreating.
var _near_prev := {}      # warship instance id -> distance last decision
var _closed := 0.0

func _fleet_distance(game: Game) -> float:
	var foes := game.get_tree().get_nodes_in_group("starbases").filter(func(s): return s.is_alive() and _found.has(s.get_instance_id()))
	var cur := {}
	if not foes.is_empty():
		for sh in game.get_tree().get_nodes_in_group("ships"):
			if sh.owner_id != pid or not sh.is_alive() or sh.def.get("role", "") != "warship":
				continue
			var best := INF
			for f in foes:
				best = minf(best, sh.global_position.distance_to(f.global_position))
			cur[sh.get_instance_id()] = best
	var lead: Array = _near_prev.keys()
	lead.sort_custom(func(x, y): return _near_prev[x] < _near_prev[y])
	lead = lead.slice(0, 8).filter(func(k): return cur.has(k))
	if not lead.is_empty():
		_closed += lead.reduce(func(acc, k): return acc + _near_prev[k] - cur[k], 0.0) / lead.size()
	_near_prev = cur
	return _closed

## Training: how much its armed ships have drawn together, summed over the
## match. Each decision adds the drop in their spread (_spread), over the
## ships alive both then and now (so losses and new builds don't count);
## spreading out subtracts the same.
var _pos_prev := {}       # armed ship instance id -> position last decision
var _gathered := 0.0

func _fleet_cohesion(game: Game) -> float:
	var cur := {}
	for sh in game.get_tree().get_nodes_in_group("ships"):
		if sh.owner_id == pid and sh.is_alive() and not sh.docked and sh.def.get("weapon", "") != "":
			cur[sh.get_instance_id()] = sh.global_position
	var both: Array = _pos_prev.keys().filter(func(k): return cur.has(k))
	if both.size() >= 2:
		_gathered += _spread(both, _pos_prev) - _spread(both, cur)
	_pos_prev = cur
	return _gathered

## Mean distance from each ship to its nearest companion (capped at 1000):
## separate groups are fine, stragglers count.
func _spread(ids: Array, pos: Dictionary) -> float:
	var t := 0.0
	for k in ids:
		var best := 1000.0
		for k2 in ids:
			if k2 != k:
				best = minf(best, pos[k].distance_to(pos[k2]))
		t += best
	return t / ids.size()

func _write_trace(game: Game) -> void:
	var path := OS.get_environment("SL_TRACE")
	if path == "":
		return
	if _trace == null:
		_trace = FileAccess.open(path, FileAccess.WRITE)
		if _trace == null:
			return
	var rows := []
	var tree := game.get_tree()
	for g in [["ships", "s"], ["starbases", "b"], ["planets", "p"]]:
		for e in tree.get_nodes_in_group(g[0]):
			if g[0] != "planets" and not e.is_alive():
				continue
			rows.append([g[1], int(e.owner_id), int(e.global_position.x), int(e.global_position.y)])
	_trace.store_line(JSON.stringify({"t": snappedf(Game.now(), 0.1), "me": pid, "e": rows}))
	_trace.flush()

func _send(d: Dictionary) -> void:
	_tcp.poll()
	_tcp.put_data((JSON.stringify(d) + "\n").to_utf8_buffer())

func _receive() -> Dictionary:
	while true:
		var nl := _buf.find("\n")
		if nl >= 0:
			var line := _buf.substr(0, nl)
			_buf = _buf.substr(nl + 1)
			var parsed = JSON.parse_string(line)
			return parsed if parsed is Dictionary else {}
		_tcp.poll()
		if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return {"quit": true}
		var n := _tcp.get_available_bytes()
		if n > 0:
			_buf += _tcp.get_utf8_string(n)
		else:
			OS.delay_usec(200)
	return {}
