class_name Abilities
extends RefCounted
## Ship jobs (Defs.JOBS): the passive effects and Q abilities that make each
## ship good at something particular. Ships call in here; the effects are
## drawn by Ship._draw_job in the job's accent color.

const REPAIR_RANGE := 180.0
const REPAIR_RATE := 5.0
const REPAIR_MAX_TARGETS := 4
## Ships count as out of combat this long after their last hit.
const REPAIR_CALM := 4.0
const EMERGENCY_RANGE := 200.0
const EMERGENCY_HEAL := 0.35
const BEACON_SENSOR := 350.0

static func job_def(s: Ship) -> Dictionary:
	return Defs.JOBS.get(s.def.get("job", ""), {})

static func ready_in(s: Ship) -> float:
	return maxf(0.0, s.ability_ready_at - Game.now())

static func is_active(s: Ship) -> bool:
	return Game.now() < s.ability_until

## Triggers the ship's Q ability. Returns "" on success, else why not.
static func use(s: Ship) -> String:
	var j := job_def(s)
	if j.is_empty() or not j.get("active", false):
		return "No active ability"
	if ready_in(s) > 0.0:
		return "Recharging (%ds)" % int(ceil(ready_in(s)))
	var g := Game.instance
	match s.def["job"]:
		"beacon":
			var b := Beacon.new()
			b.owner_id = s.owner_id
			b.position = s.global_position
			b.expires = Game.now() + float(j["duration"])
			g.fx_root.add_child(b)
		"field_repair":
			for o in allies_near(s, EMERGENCY_RANGE):
				repair(o, (o.max_hp + o.max_armor) * EMERGENCY_HEAL)
			s.ability_until = Game.now() + 0.6   # for the flash
	g.stats.count(s.owner_id, "ability_" + s.def["job"])
	s.ability_ready_at = Game.now() + float(j["cooldown"])
	s.queue_redraw()
	return ""

## Friendly ships (not s itself) within r of s.
static func allies_near(s: Node2D, r: float) -> Array:
	var out: Array = []
	var r2 := r * r
	for o in Game.instance.get_tree().get_nodes_in_group("ships"):
		if o != s and o.owner_id == s.owner_id and o.is_alive() and o.global_position.distance_squared_to(s.global_position) <= r2:
			out.append(o)
	return out

## A Radiation Sail Array with a charged solar shield whose bubble
## (Defs.SAIL_RADIUS) contains `e`, or null. `owner_only` limits it to
## arrays of e's own side (for soaking enemy fire).
## Disruptor EMP: a hit switches the target's shields off for EMP_TIME (each
## hit refreshes it). While off the shield blocks nothing and does not
## recharge, and it comes back at the value it had. Each ship can apply or
## refresh an EMP once per EMP_GUN_CD / its gun count (a 1-gun corvette every
## 4 s, a 4-gun carrier every 1 s): one shared timestamp, gun-scaled.
## Transient: not saved (it lasts 5 s at most).
const EMP_TIME := 5.0
const EMP_GUN_CD := 4.0

static func emp_on(e: Object) -> bool:
	var u = e.get("shield_off_until")
	return u != null and Game.now() < float(u)

## Call after the hit has landed (so the applying hit still hits the shield).
static func emp_try(target: Object, from: Object, profile: Dictionary) -> void:
	if not profile.get("emp", false) or not is_instance_valid(from) or from.get("emp_ready_at") == null:
		return
	if target.get("shield_off_until") == null:
		return
	var ms = target.call("max_shield") if target is Planet else target.get("max_shield")
	if float(ms) <= 0.0:
		return
	var now := Game.now()
	if now < float(from.emp_ready_at):
		return
	var d = from.get("def")
	var guns: int = maxi(1, int(d.get("guns", 1))) if d is Dictionary else 1
	from.emp_ready_at = now + EMP_GUN_CD / float(guns)
	# A Radiation Sail Array is EMP'd with its whole pool (touching bubbles).
	var hit: Array = [target]
	if target is Ship and target.def.has("solar_sail"):
		hit = sail_cluster(target, true)
	for o in hit:
		o.set("shield_off_until", now + EMP_TIME)
		o.call("queue_redraw")

static func sail_cover(e: Node2D, owner_only: bool = true) -> Node2D:
	var oid = e.get("owner_id")
	if owner_only and (oid == null or oid == 0):
		return null
	for o in Game.instance.job_ships.get("radiation_sail", []):
		if not is_instance_valid(o) or not o.is_alive() or o.shield <= 0.0 or emp_on(o):
			continue
		if owner_only and o.owner_id != oid:
			continue
		if o.global_position.distance_to(e.global_position) <= Defs.SAIL_RADIUS:
			return o
	return null

## Radiation damage multiplier: 0 for anything inside a charged solar
## shield's bubble - friend or foe, blocking it costs the shield nothing -
## and 1 everywhere else.
static func radiation_mult(e: Node2D) -> float:
	# The array itself is always immune, even with its shield down.
	if e is Ship and e.def.has("solar_sail"):
		return 0.0
	if sail_cover(e, false) != null:
		return 0.0
	return 1.0

## Spice Navigation: the share of spice-nebula radiation a ship still takes.
const SPICE_NAV_RADIATION := 0.25

## Weapon fire on anything under a solar shield is soaked by that shield
## first. Returns what gets through.
static func sail_absorb(e: Node2D, amount: float, from: Node2D, profile: Dictionary = {}) -> float:
	if from == null or amount <= 0.0:
		return amount
	# Slip shots slip past shields - solar ones too.
	if int(profile.get("pierce", 0)) >= 1:
		return amount
	var rsa := sail_cover(e)
	if rsa == null:
		return amount
	# Overcharged Coils: a share passes through, as with any shield.
	var past := 0.0
	if is_instance_valid(from) and from.get("owner_id") != null:
		past = amount * clampf(Game.instance.mod(from.owner_id, "shield_pierce") - 1.0, 0.0, 1.0)
	var rest := amount - past
	# Plasma counts its bonus against solar shields like any shield.
	var m: float = profile.get("vs", {}).get("shield", 1.0)
	# Touching bubbles are one mega shield whose points are the sum of the
	# arrays' (three full arrays: 300). A hit drains every array in
	# proportion to what it holds, so they all reach 0 - and burst - together.
	var pool := sail_cluster(rsa)
	var total := 0.0
	for o in pool:
		total += o.shield
	var soak := minf(total, rest * m)
	for o in pool:
		var before: float = o.shield
		o.shield = 0.0 if soak >= total else o.shield - soak * o.shield / total
		o.call("_solar_hit", from, before)
		o.queue_redraw()
	# A Disruptor hit soaked by the pool EMPs the arrays that took it.
	if soak > 0.0 and profile.get("emp", false) and is_instance_valid(from):
		emp_try(rsa, from, profile)
	return past + rest - soak / m

## Every charged array of the same side linked to `rsa` through touching
## bubbles (including rsa): together they form one mega shield.
## `include_off`: also arrays whose shields are EMP'd (to EMP a whole pool).
static func sail_cluster(rsa: Node2D, include_off: bool = false) -> Array:
	var all: Array = []
	for o in Game.instance.job_ships.get("radiation_sail", []):
		if is_instance_valid(o) and o.is_alive() and o.shield > 0.0 and o.owner_id == rsa.owner_id and (include_off or not emp_on(o)):
			all.append(o)
	var out: Array = [rsa]
	var i := 0
	while i < out.size():
		for o in all:
			if not out.has(o) and o.global_position.distance_to(out[i].global_position) <= 2.0 * Defs.SAIL_RADIUS:
				out.append(o)
		i += 1
	return out


## Field Repair: heals up to REPAIR_MAX_TARGETS damaged, out-of-combat
## friendly ships nearby; returns them (for the repair beams).
static func repair_tick(s: Ship, dt: float) -> Array:
	var healed: Array = []
	for o in allies_near(s, REPAIR_RANGE):
		if healed.size() >= REPAIR_MAX_TARGETS:
			break
		if (o.hp < o.max_hp or o.armor < o.max_armor) and Game.now() - o._last_hit_time > REPAIR_CALM:
			repair(o, REPAIR_RATE * dt)
			healed.append(o)
	return healed

## Restores `amount` points to a ship: hull first, then armor (shields
## regenerate on their own). Repair Tenders are the only way to get armor
## back.
static func repair(o: SpaceEntity, amount: float) -> void:
	var to_hull := minf(amount, o.max_hp - o.hp)
	o.hp += to_hull
	o.armor = minf(o.max_armor, o.armor + amount - to_hull)
	o.queue_redraw()
