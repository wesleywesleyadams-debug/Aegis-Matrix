class_name Abilities
extends RefCounted
## Ship jobs (Defs.JOBS): the passive effects and Q abilities that make each
## ship good at something particular. Ships call in here; the effects are
## drawn by Ship._draw_job in the job's accent color.

const HEAT_RANGE := 170.0
const HEAT_CUT := 0.75
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

## Radiation damage multiplier (a Heat Shield Frigate nearby).
static func radiation_mult(e: SpaceEntity) -> float:
	var best := 1.0
	for o in Game.instance.job_ships.get("heat_screen", []):
		if o.owner_id != e.owner_id:
			continue
		var d2: float = o.global_position.distance_squared_to(e.global_position)
		if d2 <= HEAT_RANGE * HEAT_RANGE or o == e:
			best = 1.0 - HEAT_CUT
	return best

## True if a Heat Shield keeps this ship's shields up in a spice nebula.
static func nebula_protected(e: SpaceEntity) -> bool:
	return radiation_mult(e) < 1.0

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
