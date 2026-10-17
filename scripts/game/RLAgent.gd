class_name RLAgent
extends Node
## The learning AI's body in the game: every DECIDE seconds it describes the
## match to a Python trainer (tools/rl/) over a local TCP socket, waits for
## its decision and carries it out. Built to ADAPT to new rules, so nothing
## here names a ship, tech or map feature:
##   - the world is a SET of entities, each a feature vector (kind, owner
##     relation, position, health layers, firepower, speed...);
##   - every choice is a set of OPTIONS described by their stats - each ship
##     it could build right now (costs, time, layers, damage, range, speed,
##     role), each tech it could research (costs, time, tier, and its effects
##     hashed into a fixed-size vector so new effect keys still fit), each
##     place its fleet could go. The network scores options; a new ship or
##     tech is simply one more option it can judge by its stats.
## Mining, colonist targeting, planet development and ship steering stay with
## the scripted AIController (it calls tick() like NeuralCommander).
##
## Protocol: one JSON object per line each way. Game -> trainer: {obs...,
## "reward_info", "done"}. Trainer -> game: {"build": i, "tech": i,
## "target": i} (-1 = none) or {"quit": true}.
## Started with SL_RL_PORT (and SL_RL_SIDE, default 1) in a sim (SL_SIM).

const DECIDE := 2.0
## How many entities (nearest to the home base first) the trainer sees.
const MAX_ENTITIES := 160
## Hash buckets for tech effects (any effect key, present or future).
const EFFECT_BUCKETS := 24
const ROLES := ["miner", "skimmer", "colony", "constructor", "scout", "support", "warship"]
const KINDS := ["ship", "starbase", "station", "depot", "planet", "asteroid", "nebula", "storm", "star"]

var pid: int = 1
var _tcp := StreamPeerTCP.new()
var _buf := ""
var _next := 0.0
var _done_sent := false
var _build_ids: Array = []
var _tech_ids: Array = []
var _targets: Array = []
## How often each kind of decision was taken (dev reports read it).
var counts := {}

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

## Called from AIController._think (once a second).
func tick(game: Game, base: Starbase, _ai: AIController) -> void:
	if Game.now() < _next or _done_sent:
		return
	_next = Game.now() + DECIDE
	_send(_observe(game, base, false))
	var reply := _receive()
	if reply.get("quit", false):
		game.get_tree().quit()
		return
	_act(game, base, reply)

func _finish() -> void:
	if _done_sent or _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	_done_sent = true
	var game := Game.instance
	_send(_observe(game, game.nearest_starbase(pid, Vector2.ZERO) if game else null, true))

# ---------------------------------------------------------------- observe

func _observe(game: Game, base: Starbase, done: bool) -> Dictionary:
	var home: Vector2 = base.global_position if base else Vector2.ZERO
	var r: Dictionary = game.resources[pid]
	var rt: Dictionary = game.rates.get(pid, {})
	var me := [r.get("food", 0.0) / 1000.0, r.get("minerals", 0.0) / 1000.0, r.get("energy", 0.0) / 1000.0, r.get("spice", 0.0) / 1000.0,
		rt.get("food", 0.0), rt.get("minerals", 0.0), rt.get("energy", 0.0), rt.get("spice", 0.0),
		game.total_pop(pid) / 10000.0, Game.now() / 3600.0, float(game.players.size()) / 8.0,
		1.0 if game.research[pid].is_empty() and game.research_queue[pid].is_empty() else 0.0,
		float(base.queue.size()) / 5.0 if base else 0.0]
	var obs := {
		"t": Game.now(), "pid": pid, "self": me, "done": done,
		"won": game.winner_pid == pid or (done and not game.is_defeated(pid) and game.living_players().size() == 1),
		"lost": game.is_defeated(pid),
		"score": game.stats.score(pid),
		"enemy_score": _enemy_score(game),
		"entities": _entities(game, home),
		"build_opts": _build_options(game, base),
		"tech_opts": _tech_options(game),
		"targets": _target_options(game, home),
	}
	return obs

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

func _kind(k: String) -> Array:
	var v := []
	for name in KINDS:
		v.append(1 if name == k else 0)
	return v

## One feature row: kind one-hot, owner relation, position (fraction of the
## map radius, relative to home), health layers (log-scaled), fill
## fractions, firepower, reach, speed, size, extra (cargo / pop / amount).
func _row(kind: String, owner: int, pos: Vector2, home: Vector2, hp: float, armor: float, shield: float, frac: float, dps: float, reach: float, speed: float, size: float, extra: float, game: Game) -> Array:
	var rel := pos - home
	var row := _kind(kind) + _rel(owner, game)
	row.append_array([rel.x / Game.MAP_RADIUS, rel.y / Game.MAP_RADIUS, pos.length() / Game.MAP_RADIUS,
		log(1.0 + hp) / 8.0, log(1.0 + armor) / 8.0, log(1.0 + shield) / 8.0, frac,
		log(1.0 + dps) / 5.0, reach / 1000.0, speed / 200.0, size / 100.0, extra])
	return row

func _entities(game: Game, home: Vector2) -> Array:
	var v: Vision = game.visions.get(pid)
	var rows: Array = []
	var tree := game.get_tree()
	for e in tree.get_nodes_in_group("entities"):
		if not e.is_alive():
			continue
		# Fog: an enemy is only seen where our sensors reach.
		if e.owner_id != pid and v and not v.can_see(e):
			continue
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
		var frac: float = (e.hp + e.armor + e.shield) / maxf(mx, 1.0)
		rows.append([home.distance_to(e.global_position), _row(kind, e.owner_id, e.global_position, home, e.max_hp, e.max_armor, e.max_shield, frac, dps, reach, speed, e.radius, extra, game)])
	for p in tree.get_nodes_in_group("planets"):
		var o: int = v.known_owner(p) if v else p.owner_id
		rows.append([home.distance_to(p.global_position), _row("planet", o, p.global_position, home, p.pop, 0.0, p.shield, p.pop / maxf(p.max_pop(), 1.0), 0.0, 0.0, 0.0, p.radius, float(p.fields) / 30.0, game)])
	for a in tree.get_nodes_in_group("asteroids"):
		if v and not v.is_explored_at(a.global_position):
			continue
		var amt: float = a.amount if a.get("amount") != null else 0.0
		rows.append([home.distance_to(a.global_position), _row("asteroid", 0, a.global_position, home, amt, 0.0, 0.0, 1.0 if a.resource == "spice" else 0.0, 0.0, 0.0, 0.0, a.radius, 0.0, game)])
	for n in tree.get_nodes_in_group("nebulae"):
		rows.append([home.distance_to(n.global_position), _row("nebula", 0, n.global_position, home, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, (n.radius if n.shape == "cloud" else n.outer) / 10.0, 0.0, game)])
	for s in tree.get_nodes_in_group("storms"):
		rows.append([home.distance_to(s.global_position), _row("storm", 0, s.global_position, home, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, s.radius / 10.0, 0.0, game)])
	for s in tree.get_nodes_in_group("stars"):
		rows.append([home.distance_to(s.global_position), _row("star", 0, s.global_position, home, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, s.core_radius, 0.0, game)])
	rows.sort_custom(func(x, y): return x[0] < y[0])
	return rows.slice(0, MAX_ENTITIES).map(func(x): return x[1])

## Every ship the home starbase could start right now, described by stats.
func _build_options(game: Game, base: Starbase) -> Array:
	_build_ids = []
	var out: Array = []
	if base == null:
		return out
	var r: Dictionary = game.resources[pid]
	for t in Defs.SHIPS:
		var d: Dictionary = Defs.SHIPS[t]
		if d.has("variant") or base.can_queue(t) != "":
			continue
		if r["spice"] < d["cost"].get("spice", 0):
			continue
		var c: Dictionary = d["cost"]
		var role: String = d.get("role", "warship")
		var row := [c.get("minerals", 0.0) / 1000.0, c.get("spice", 0.0) / 100.0, c.get("energy", 0.0) / 100.0, float(d.get("build_time", 30.0)) / 100.0,
			log(1.0 + d.get("hp", 0.0)) / 8.0, log(1.0 + d.get("armor", 0.0)) / 8.0, log(1.0 + d.get("shield", 0.0)) / 8.0,
			float(d.get("damage", 0.0)) * int(d.get("guns", 1)) / maxf(float(d.get("cooldown", 1.0)), 0.1) / 30.0,
			float(d.get("range", 0.0)) / 1000.0, float(d.get("speed", 0.0)) / 200.0, float(d.get("upkeep", 0.0)),
			float(d.get("cargo", 0.0)) / 100.0, 1.0 if d.has("job") else 0.0]
		for rl in ROLES:
			row.append(1 if role == rl else 0)
		_build_ids.append(t)
		out.append(row)
	return out

## Every tech it could start, with its effects hashed into buckets.
func _tech_options(game: Game) -> Array:
	_tech_ids = []
	var out: Array = []
	if not (game.research[pid].is_empty() and game.research_queue[pid].is_empty()):
		return out
	for id in Defs.TECHS:
		if game.tech_state(pid, id) != "available":
			continue
		var t: Dictionary = Defs.TECHS[id]
		var row := [t["cost"].get("energy", 0.0) / 1000.0, t["cost"].get("spice", 0.0) / 100.0, float(t["time"]) / 300.0, float(t["tier"]) / 3.0]
		var fx := []
		fx.resize(EFFECT_BUCKETS)
		fx.fill(0.0)
		for k in t["effects"]:
			fx[hash(k) % EFFECT_BUCKETS] += float(t["effects"][k])
		row.append_array(fx)
		_tech_ids.append(id)
		out.append(row)
	return out

## Where the fleet could be sent: known enemy worlds and bases, free worlds,
## and home (defend). Each described like an entity.
func _target_options(game: Game, home: Vector2) -> Array:
	_targets = [home]
	var out: Array = [_row("starbase", pid, home, home, 0, 0, 0, 1, 0, 0, 0, 0, 0, game)]
	var v: Vision = game.visions.get(pid)
	for p in game.get_tree().get_nodes_in_group("planets"):
		var o: int = v.known_owner(p) if v else p.owner_id
		if o != pid:
			_targets.append(p.global_position)
			out.append(_row("planet", o, p.global_position, home, p.pop, 0, p.shield, 0, 0, 0, 0, p.radius, 0, game))
	if v:
		for sb in v.seen_bases:
			_targets.append(v.seen_bases[sb][0])
			out.append(_row("starbase", _any_enemy(game), v.seen_bases[sb][0], home, 0, 0, 0, v.seen_bases[sb][1], 0, 0, 0, 0, 0, game))
	return out

## Some enemy player id (for describing an enemy thing whose owner we only
## know to be hostile).
func _any_enemy(game: Game) -> int:
	for p in game.players:
		if game.is_hostile(pid, p):
			return p
	return 0

# ---------------------------------------------------------------- act

func _act(game: Game, base: Starbase, a: Dictionary) -> void:
	var b := int(a.get("build", -1))
	if b >= 0 and b < _build_ids.size() and base:
		base.enqueue(_build_ids[b])
	var t := int(a.get("tech", -1))
	if t >= 0 and t < _tech_ids.size():
		game.queue_research(pid, _tech_ids[t])
	var g := int(a.get("target", -1))
	if g >= 0 and g < _targets.size():
		var goal: Vector2 = _targets[g]
		for s in game.get_tree().get_nodes_in_group("ships"):
			if s.owner_id == pid and s.def["role"] == "warship" and s.is_alive() and not s.docked:
				s.order_attack_move(goal + Vector2(randf_range(-40, 40), randf_range(-40, 40)))

# ---------------------------------------------------------------- wire

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
