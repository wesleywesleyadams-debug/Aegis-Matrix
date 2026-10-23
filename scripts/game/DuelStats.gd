class_name DuelStats
## Dev only (SL_DUEL_STATS=1 with SL_DUEL): per-class firing statistics for a
## duel, printed as DSTAT lines at the end. Read-only: it never changes play.
## Keys are ship classes (ship_type).

static var on := false
static var t0 := 0.0
## class -> {stat: value}
static var c := {}
## Projectile -> [shooter class, target class]
static var _proj := {}

static func _b(k: String) -> Dictionary:
	if not c.has(k):
		c[k] = {"pulls": 0, "acc_miss": 0, "fired": 0, "hit": 0, "fizzle_dead": 0, "dodged": 0,
			"dmg": 0.0, "wasted": 0.0, "range_sum": 0.0, "move_sum": 0.0, "first": -1.0,
			"t_none": 0, "t_slew": 0, "t_reload": 0, "t_fire": 0, "regen": 0.0,
			"inrange_t": 0.0, "guns": 1, "share_sum": 0.0, "share_n": 0, "taken_dmg": 0.0}
	return c[k]

## A trigger pull: `fired` projectiles of `guns` launched (the rest missed on accuracy).
static func pull(s: Node2D, tgt: Node2D, acc: float, guns: int, fired: int, moving: float) -> void:
	var b := _b(s.ship_type)
	b["pulls"] += guns
	b["acc_miss"] += guns - fired
	b["range_sum"] += s.global_position.distance_to(tgt.global_position)
	b["move_sum"] += moving
	b["events"] = b.get("events", 0) + 1
	if b["first"] < 0.0:
		b["first"] = Game.now() - t0

## A turret (or fixed gun) tick: "none" no target, "slew" not on bearing,
## "reload" cooling down, "fire" shot this tick.
static func tick(s: Node2D, what: String) -> void:
	_b(s.ship_type)["t_" + what] += 1

static func launched(p: Node2D, from: Node2D, to: Node2D) -> void:
	if from is Ship:
		_proj[p] = [from.ship_type, to.get("ship_type") if to is Ship else "other", (to.velocity as Vector2).length() if to is Ship else 0.0, Game.now() - t0]
		_b(from.ship_type)["fired"] += 1
		# As a target: instantaneous velocity (what Target Prediction leads
		# on) vs net speed over the last 0.25 s (how far it really goes).
		if to is Ship:
			var bt := _b(to.ship_type)
			bt["tv_sum"] = bt.get("tv_sum", 0.0) + (to.velocity as Vector2).length()
			bt["ta_sum"] = bt.get("ta_sum", 0.0) + float(to.actual_speed)
			bt["tv_n"] = bt.get("tv_n", 0) + 1

## A projectile connects: `rem` is the target's toughness before the hit.
static func hit(p: Node2D, amount: float, rem: float) -> void:
	if not _proj.has(p):
		return
	var b := _b(_proj[p][0])
	b["hit"] += 1
	b["dmg"] += minf(amount, rem)
	b["wasted"] += maxf(0.0, amount - rem)
	_b(_proj[p][1])["taken_dmg"] += minf(amount, rem)
	_proj.erase(p)

## A projectile expired: its target already dead (overkill) or alive (dodged).
static func expired(p: Node2D, target_alive: bool) -> void:
	if not _proj.has(p):
		return
	_b(_proj[p][0])["fizzle_dead" if not target_alive else "dodged"] += 1
	if target_alive:
		# Dodges as a target: speed it had when the shot was launched, and when.
		var bd := _b(_proj[p][1])
		bd["dg_n"] = bd.get("dg_n", 0) + 1
		bd["dg_v"] = bd.get("dg_v", 0.0) + _proj[p][2]
		bd["dg_fast"] = bd.get("dg_fast", 0) + (1 if _proj[p][2] > 40.0 else 0)
		bd["dg_t"] = bd.get("dg_t", 0.0) + _proj[p][3]
	_proj.erase(p)

static func regen(s: Node2D, amount: float) -> void:
	if s is Ship:
		_b(s.ship_type)["regen"] += amount

## Sampled by the duel loop every `dt`: time with an enemy in reach, and how
## many enemy hulls are shooting at each ship that is being shot at.
static var _tl_next := 0.0
static var _life := {}
static func sample(ships: Array, dt: float) -> void:
	var shooters := {}
	# Timeline every 5 s: guns alive and toughness left per class.
	if Game.now() - t0 >= _tl_next:
		_tl_next += 5.0
		var tl := {}
		for s in ships:
			if is_instance_valid(s) and s is Ship and s.is_alive():
				var e: Array = tl.get(s.ship_type, [0, 0.0])
				tl[s.ship_type] = [e[0] + int(s.def.get("guns", 1)), e[1] + s.hp + s.armor + s.shield]
		var line := "DTL t=%d" % int(Game.now() - t0)
		for k in tl:
			line += " %s guns=%d tough=%.0f" % [k, tl[k][0], tl[k][1]]
		print(line)
	for s in ships:
		if not (is_instance_valid(s) and s is Ship and s.is_alive()):
			continue
		var b := _b(s.ship_type)
		b["guns"] = int(s.def.get("guns", 1))
		# Damage parked on hulls still alive (and so still shooting).
		var mx: float = s.max_hp + s.max_armor + s.max_shield
		b["wound_sum"] = b.get("wound_sum", 0.0) + (mx - s.hp - s.armor - s.shield) / mx
		b["alive_n"] = b.get("alive_n", 0) + 1
		var near = Game.instance.nearest_enemy(s, s.weapon_range())
		if near != null:
			b["inrange_t"] += dt
		# Spacing: nearest enemy / ally centre, and whether any gun has a target.
		var ne := INF
		var na := INF
		for o in ships:
			if o == s or not (is_instance_valid(o) and o is Ship and o.is_alive()):
				continue
			var dd: float = s.global_position.distance_to(o.global_position)
			if o.owner_id == s.owner_id:
				na = minf(na, dd)
			else:
				ne = minf(ne, dd)
		if ne < INF:
			b["ne_sum"] = b.get("ne_sum", 0.0) + ne
			b["ne_n"] = b.get("ne_n", 0) + 1
		if na < INF:
			b["na_sum"] = b.get("na_sum", 0.0) + na
			b["na_n"] = b.get("na_n", 0) + 1
		if not _life.has(s):
			_life[s] = [s.ship_type, Game.now() - t0, mx]
		var tg := {}
		for t in s._t_target:
			if is_instance_valid(t):
				tg[t] = true
		if s._t_target.is_empty() and is_instance_valid(s._aim_at) and s._aim_at.is_alive() \
				and s.global_position.distance_to(s._aim_at.global_position) <= s.weapon_range() + 60.0:
			tg[s._aim_at] = true
		for t in tg:
			shooters[t] = shooters.get(t, 0) + 1
		b["eng_sum"] = b.get("eng_sum", 0) + (1 if not tg.is_empty() else 0)
	# Deaths: lifetime and toughness each hull soaked (incl. regen) before dying.
	for s in _life.keys():
		if not (is_instance_valid(s) and s.is_alive()):
			var e: Array = _life[s]
			var b3 := _b(e[0])
			b3["deaths"] = b3.get("deaths", 0) + 1
			b3["life_sum"] = b3.get("life_sum", 0.0) + (Game.now() - t0) - e[1]
			_life.erase(s)
	for t in shooters:
		if t is Ship:
			var b2 := _b(t.ship_type)
			b2["share_sum"] += shooters[t]
			b2["share_n"] += 1

static func report() -> void:
	for k in c:
		var b: Dictionary = c[k]
		var shots: float = maxf(1.0, b["fired"])
		var pulls: float = maxf(1.0, b["pulls"])
		var ticks: float = maxf(1.0, b["t_none"] + b["t_slew"] + b["t_reload"] + b["t_fire"])
		var ev: float = maxf(1.0, b.get("events", 0))
		var expected: float = b["inrange_t"] * b["guns"] / 1.0
		print("DSTAT %s pulls=%d accmiss=%.0f%% fired=%d hit=%.0f%% overkill_fizzle=%.0f%% dodged=%.0f%% dmg=%.0f wasted_on_kill=%.0f (%.0f%%) range=%.0f movefrac=%.2f first=%.1fs ticks:none=%.0f%% slew=%.0f%% reload=%.0f%% fire=%.1f%% util=%.0f%% (pulls/expected while in reach) shooters_on_me=%.2f wounded=%.2f inreach=%.2f regen=%.0f taken=%.0f" % [
			k, b["pulls"], 100.0 * b["acc_miss"] / pulls, b["fired"], 100.0 * b["hit"] / shots,
			100.0 * b["fizzle_dead"] / shots, 100.0 * b["dodged"] / shots, b["dmg"], b["wasted"],
			100.0 * b["wasted"] / maxf(1.0, b["dmg"] + b["wasted"]), b["range_sum"] / ev, b["move_sum"] / ev, b["first"],
			100.0 * b["t_none"] / ticks, 100.0 * b["t_slew"] / ticks, 100.0 * b["t_reload"] / ticks, 100.0 * b["t_fire"] / ticks,
			100.0 * b["pulls"] / maxf(1.0, expected), b["share_sum"] / maxf(1.0, b["share_n"]), b.get("wound_sum", 0.0) / maxf(1.0, b.get("alive_n", 0)), b["inrange_t"] / maxf(0.5, 0.5 * b.get("alive_n", 0)), b["regen"], b["taken_dmg"]])
		print("DSTAT2 %s near_enemy=%.0f near_ally=%.0f engaged=%.2f deaths=%d life=%.1f tgt_vel=%.1f tgt_netspeed=%.1f dodged_n=%d dodged_vel=%.0f dodged_fast=%d dodged_t=%.1f" % [k,
			b.get("ne_sum", 0.0) / maxf(1.0, b.get("ne_n", 0)), b.get("na_sum", 0.0) / maxf(1.0, b.get("na_n", 0)),
			float(b.get("eng_sum", 0)) / maxf(1.0, b.get("alive_n", 0)), b.get("deaths", 0), b.get("life_sum", 0.0) / maxf(1.0, b.get("deaths", 0)),
			b.get("tv_sum", 0.0) / maxf(1.0, b.get("tv_n", 0)), b.get("ta_sum", 0.0) / maxf(1.0, b.get("tv_n", 0)),
			b.get("dg_n", 0), b.get("dg_v", 0.0) / maxf(1.0, b.get("dg_n", 0)), b.get("dg_fast", 0), b.get("dg_t", 0.0) / maxf(1.0, b.get("dg_n", 0))])
