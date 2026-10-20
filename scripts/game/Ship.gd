@tool
class_name Ship
extends SpaceEntity
## A single ship. Stats come from Defs.SHIPS[ship_type]; sprites are
## assets/pixel/ship_<type>.png plus a team-tinted overlay layer.

enum State { IDLE, MOVE, ATTACK, ATTACK_MOVE, MINE_GO, MINING, RETURN, COLONIZE, BUILD, BOMBARD, REFIT }

@export_enum("miner", "colony", "constructor", "corvette", "destroyer", "cruiser") var ship_type: String = "corvette":
	set(v):
		ship_type = v
		if is_node_ready():
			_apply_visuals()

var def: Dictionary
var state: State = State.IDLE
var velocity: Vector2 = Vector2.ZERO
var move_goal: Vector2
var attack_move_goal: Vector2
## Seconds until an idle weapon may scan for targets again (empty scans only).
## Guns are fixed forward: a ship has to be pointing within this of a target
## to shoot it, and turns onto the bearing first. Big hulls turn slowly (see
## _steer), so a cruiser caught beam-on really does have to come about.
const FIRE_ARC := deg_to_rad(40.0)
## A harvester's beam comes out of its nose too, so it has to come about
## before it can work a rock. Wider than a gun's arc: this is a chore, not a
## duel, and a barge that fidgets on station looks broken.
const HARVEST_ARC := deg_to_rad(35.0)
## A barge or skimmer left idle this long finds its own work again: it takes
## its load home if it has one, else puts in to the nearest resource it can
## reach. An idle harvester is pure loss, and chasing them around the map is
## not the part of this game anyone wants to play.
const IDLE_RETASK := 5.0

## Radius of the biggest hull in the game (the carrier), used to size the
## separation search. Keep in step with Defs if a larger hull is ever added.
const MAX_HULL_RADIUS := 64.0   # the carrier

## How well a turreted hull shoots at full speed, against standing still.
const MOVING_ACCURACY := 0.65

## Swings the turrets toward `point` at their own rate and says whether they
## are on the bearing yet. The sprites are drawn in hull space, so they are
## offset by the hull's own rotation.
func _traverse(point: Vector2, delta: float) -> bool:
	var want: float = (point - global_position).angle()
	var rate: float = float(def.get("turret_rate", 1.0))
	_turret_rot = rotate_toward(_turret_rot, want, rate * delta)
	for t in _turret_sprites:
		if is_instance_valid(t):
			t.rotation = _turret_rot - rotation
	return absf(angle_difference(_turret_rot, want)) <= deg_to_rad(8.0)

## Independent turrets. With an attack order (or a bombard), every turret
## takes the ordered target while it is within reach - focus fire as before.
## Otherwise (attack-move, idle, ordered target out of reach) each turret
## keeps or picks its own enemy in reach, preferring ones no other turret of
## this ship is on, so a carrier can engage up to four ships at once.
func _fire_turrets(delta: float) -> void:
	if weapon_mod.has("drones"):
		_fly_drones(delta)
		# The launch doors double as point defense with Defensive Fire.
		_df_cd -= delta
		if _df_cd <= 0.0 and _defensive_fire():
			_df_cd = def["cooldown"] / Game.instance.mod(owner_id, "fire_rate")
		return
	elif not _drones.is_empty():
		_clear_drones()
	var g := Game.instance
	var rng := weapon_range()
	var ordered: Node2D = null
	if state == State.BOMBARD and is_instance_valid(bombard_target):
		ordered = bombard_target
	elif state == State.ATTACK and target_ordered and is_instance_valid(target) and target.is_alive():
		ordered = target
	var focus: bool = ordered != null and global_position.distance_to(ordered.global_position) <= rng + float(ordered.get("radius"))
	_t_scan -= delta
	if not focus and _t_scan <= 0.0:
		_t_scan = SCAN_INTERVAL
		_t_near = g.enemies_near(self, rng, _turret_sprites.size() + 2)
	var n := _turret_sprites.size()
	var dmg: float = def["damage"] * Defs.mark_mult(ship_type, g.mark_level(owner_id, ship_type))
	var per: int = maxi(1, int(round(float(def.get("guns", n)) / float(n))))
	var acc := lerpf(1.0, MOVING_ACCURACY, clampf(velocity.length() / maxf(max_speed(), 1.0), 0.0, 1.0))
	if g.duel_nomovepen or g.has_tech(owner_id, "gyro_stabilizers"):
		acc = 1.0
	var taken := {}
	var rate: float = float(def.get("turret_rate", 1.0))
	var had_beams := not _beams.is_empty()
	_beams.clear()
	var pd: float = float(weapon_mod.get("pd", 0.0))
	# Defensive Fire: a turret with nothing to shoot shoots down ordnance.
	var screen: bool = pd <= 0.0 and g.has_tech(owner_id, "defensive_fire")
	var claimed := {}
	for i in n:
		# Point-Defense: a ready turret first swats incoming ordnance.
		if pd > 0.0 and _t_cd[i] <= 0.0:
			var shot_down := _pd_target(pd, claimed)
			if shot_down:
				claimed[shot_down] = true
				_t_rot[i] = (shot_down.global_position - global_position).angle()
				_turret_sprites[i].rotation = _t_rot[i] - rotation
				g.intercept(self, shot_down)
				_t_cd[i] = def["cooldown"] * 0.4 / g.mod(owner_id, "fire_rate")
				continue
		var tgt: Node2D = null
		# Point-Defense: after ordnance, enemy drones come before any ship.
		if pd > 0.0:
			tgt = _pd_drone(rng, claimed)
			if tgt:
				claimed[tgt] = true
		if tgt != null:
			pass
		elif focus:
			tgt = ordered
		else:
			var cur = _t_target[i]
			if is_instance_valid(cur) and cur.is_alive() and not taken.has(cur) \
					and global_position.distance_to(cur.global_position) <= rng + cur.radius:
				tgt = cur
			else:
				for e in _t_near:
					if is_instance_valid(e) and e.is_alive() and not taken.has(e):
						tgt = e
						break
				if tgt == null and not _t_near.is_empty() and is_instance_valid(_t_near[0]) and _t_near[0].is_alive():
					tgt = _t_near[0]   # more turrets than enemies: double up
		if _t_target[i] != tgt:
			_t_beam_time[i] = 0.0   # the lance's ramp starts over on a new target
		_t_target[i] = tgt
		if tgt == null:
			if screen and _t_cd[i] <= 0.0:
				var sd := _pd_target(DEFENSIVE_FIRE_R, claimed)
				if sd:
					claimed[sd] = true
					_t_rot[i] = (sd.global_position - global_position).angle()
					_turret_sprites[i].rotation = _t_rot[i] - rotation
					g.intercept(self, sd)
					_t_cd[i] = def["cooldown"] / g.mod(owner_id, "fire_rate")
			continue
		taken[tgt] = true
		# Traverse this turret toward its own target.
		var want: float = (tgt.global_position - global_position).angle()
		_t_rot[i] = rotate_toward(_t_rot[i], want, rate * delta)
		_turret_sprites[i].rotation = _t_rot[i] - rotation
		var on_target: bool = absf(angle_difference(_t_rot[i], want)) <= deg_to_rad(8.0)
		# Ion Lance: a continuous beam, damage every tick, ramping on one target.
		if weapon_mod.has("beam"):
			if on_target:
				var b: Array = weapon_mod["beam"]
				_t_beam_time[i] += delta
				var ramp: float = lerpf(b[0], b[1], clampf(_t_beam_time[i] / b[2], 0.0, 1.0)) * float(weapon_mod.get("dmg", 1.0))
				var dps: float = dmg / def["cooldown"] * g.mod(owner_id, "fire_rate") * g.mod(owner_id, "damage")
				tgt.take_damage(dps * ramp * delta * Game.instance.ship_speed_factor(owner_id), self, Defs.damage_profile(def))
				_beams.append([_turret_sprites[i].global_position, tgt.global_position, ramp])
			continue
		if _t_cd[i] > 0.0 or not on_target:
			continue
		var wpn: String = weapon_mod.get("weapon", def["weapon"])
		var n_proj: int = int(weapon_mod.get("count", 1))
		var spread: float = float(weapon_mod.get("spread", 0.0))
		if weapon_mod.has("fan"):
			# A fresh fan width every launch, so no two runs land alike.
			spread = deg_to_rad(randf_range(weapon_mod["fan"][0], weapon_mod["fan"][1])) * 0.5
		var shot: float = dmg * float(weapon_mod.get("dmg", 1.0))
		if pd > 0.0 and tgt is Drone:
			shot *= PD_DRONE_MULT
		for k in per:
			if randf() < acc or wpn == "missile":   # missiles never miss
				for j in n_proj:
					var off := 0.0 if n_proj == 1 else lerpf(-spread, spread, float(j) / (n_proj - 1)) + randf_range(-0.06, 0.06)
					g.fire(self, tgt, wpn, shot, off)
		_t_cd[i] = def["cooldown"] * float(weapon_mod.get("cd", 1.0)) / g.mod(owner_id, "fire_rate") * randf_range(0.9, 1.1)
		if weapon_mod.get("run", false):
			_run_out = _t_cd[i] * 0.5

	if weapon_mod.has("tractor"):
		_tractor(delta, rng, n)
	elif not _tbeams.is_empty():
		_tbeams.clear()
		had_beams = true
	if had_beams or not _beams.is_empty() or not _tbeams.is_empty():
		queue_redraw()

## Tractor Beams: each turret holds a beam on its own target (or, past laser
## range, the nearest enemy out to `reach` x attack range). The beam slows
## from tr[0] at the far edge to tr[1] up close and slowly reels the target in.
func _tractor(delta: float, rng: float, n: int) -> void:
	var g := Game.instance
	var tr: Array = weapon_mod["tractor"]
	var reach: float = rng * float(tr[2])
	_t_far_scan -= delta
	if _t_far_scan <= 0.0:
		_t_far_scan = SCAN_INTERVAL
		_t_far = g.enemies_near(self, reach, n + 2)
	_tbeams.clear()
	var held := {}
	for i in n:
		var t = _t_target[i]
		if not (is_instance_valid(t) and t.is_alive()) or held.has(t):
			t = null
			for e in _t_far:
				if is_instance_valid(e) and e.is_alive() and not held.has(e):
					t = e
					break
		if t == null or not (t is Ship or t is Drone):
			continue
		var d: float = global_position.distance_to(t.global_position)
		if d > reach + t.radius:
			continue
		held[t] = true
		var slow: float = lerpf(float(tr[1]), float(tr[0]), clampf(d / reach, 0.0, 1.0))
		t.tractor_hit(slow)
		if d > rng * 0.6:   # reel in only to the guns' sweet spot
			t.global_position += (global_position - t.global_position).normalized() * 12.0 * slow * delta
		_tbeams.append([_turret_sprites[i].global_position, t.global_position, slow])

## Another ship's tractor beam slows this one by `slow` (0..1).
func tractor_hit(slow: float) -> void:
	_tr_roll()
	_tr_acc *= 1.0 - slow

func _tr_roll() -> void:
	var f := Engine.get_physics_frames()
	if f != _tr_frame:
		_tr_prev = _tr_acc if f == _tr_frame + 1 else 1.0
		_tr_acc = 1.0
		_tr_frame = f

## How much of its speed tractor beams leave this ship (1 = free).
func _tractor_keep() -> float:
	_tr_roll()
	return _tr_prev

## Interceptor Drones: they circle the carrier; any enemy within reach of
## the carrier draws a drone out, which closes to 40 and fires lasers.
## The turrets become launch doors. The carrier builds one drone every
## DRONE_BUILD seconds while short of its full set (a full set takes 20 s),
## each flying out of a door; a lost drone is rebuilt the same way.
const DRONE_BUILD := 5.0
const DOOR_OPEN := 0.8
func _fly_drones(delta: float) -> void:
	var g := Game.instance
	var cfg: Array = weapon_mod["drones"]
	var count: int = int(cfg[0])
	var reach: float = float(cfg[1])
	var sf: float = g.ship_speed_factor(owner_id)
	if _drones.is_empty():
		_drone_timer = DRONE_BUILD
		for ts in _turret_sprites:
			ts.visible = false   # the mounts are launch doors now
		if not is_instance_valid(_door_layer):
			_door_layer = Node2D.new()
			_door_layer.draw.connect(_draw_doors.bind(_door_layer))
			add_child(_door_layer)
		_door_layer.queue_redraw()
	while _drones.size() < count:
		_drones.append(null)
		_door_open.append(-10.0)
	var empty := -1
	for i in count:
		if not (is_instance_valid(_drones[i]) and _drones[i].is_alive()):
			_drones[i] = null
			if empty < 0:
				empty = i
	if empty < 0:
		_drone_timer = DRONE_BUILD
		drones_ready = false
	else:
		_drone_timer -= delta * sf
		if drones_ready or drones_saved > 0:
			_drone_timer = 0.0
		if _drone_timer <= 0.0:
			_drone_timer = DRONE_BUILD
			# Launch from a door (one per mount, round the hull).
			var door: int = empty % maxi(_turret_sprites.size(), 1)
			var d := Drone.new()
			d.owner_id = owner_id
			d.carrier = self
			d.slot = empty
			d.cd = randf()
			g.fx_root.add_child(d)
			d.global_position = _turret_sprites[door].global_position if not _turret_sprites.is_empty() else global_position
			d.heading = (d.global_position - global_position).angle()
			d.rotation = d.heading
			_drones[empty] = d
			_door_open[door] = Game.now()
			drones_saved = maxi(drones_saved - 1, 0)
	for k in _door_open.size():
		if Game.now() - _door_open[k] < DOOR_OPEN:
			_door_layer.queue_redraw()
			break
	# Each drone flies and fights on its own (Drone._physics_process).

## How far from the carrier its drones may range.
func drone_reach() -> float:
	return float(weapon_mod.get("drones", [0, 0.0])[1])

## One drone's laser hit on `tg`: the carrier's gun damage split across its
## drones (weaker against heavy hulls, see MOD_WEAPONS vs_class).
func drone_hit(tg: Node2D) -> void:
	var g := Game.instance
	var count: int = int(weapon_mod.get("drones", [4])[0])
	var dmg: float = def["damage"] * Defs.mark_mult(ship_type, g.mark_level(owner_id, ship_type)) * float(weapon_mod.get("dmg", 1.0))
	var per: float = float(def.get("guns", count)) / float(count)
	var k: float = float(weapon_mod.get("vs_class", {}).get(tg.def.get("base", tg.get("ship_type")), 1.0)) if tg is Ship else 1.0
	tg.take_damage(dmg * per * k * g.mod(owner_id, "damage"), self, Defs.damage_profile(def))

## Seconds between one drone's shots.
func drone_cooldown() -> float:
	return def["cooldown"] / Game.instance.mod(owner_id, "fire_rate")

## The launch doors, drawn on a layer above the hull (see _fly_drones).
func _draw_doors(L: Node2D) -> void:
	var tc := Defs.team_color(owner_id)
	for k in _turret_sprites.size():
		var ts: Sprite2D = _turret_sprites[k]
		# The turret art's round mount: radius 6.5 px, 4.5 px behind the
		# sprite's center (ship_turret.png), so the door sits exactly on it.
		var c: Vector2 = ts.position + Vector2(-4.5, 0).rotated(ts.rotation) * ts.scale
		var r: float = 6.5 * ts.scale.x
		var age: float = Game.now() - (_door_open[k] if k < _door_open.size() else -10.0)
		var open: float = clampf(1.0 - absf(age / DOOR_OPEN * 2.0 - 1.0), 0.0, 1.0) if age < DOOR_OPEN else 0.0
		L.draw_circle(c, r, Color("0b0f1e"))
		if open > 0.0:
			L.draw_circle(c, r * 0.85 * open, Color(1.0, 0.85, 0.4, 0.9 * open))
		_draw_iris(L, c, r * 0.95, open)
		L.draw_arc(c, r, 0.0, TAU, 20, Color("4a5370"), maxf(r * 0.18, 0.5))
		L.draw_arc(c, r * 1.05, 0.0, TAU, 20, Color(tc, 0.8), maxf(r * 0.1, 0.4))

## A spiral iris hatch (like a vent door): IRIS_BLADES curved blades that
## turn and draw back to open a round hole of `open` (0..1) of the radius.
const IRIS_BLADES := 6
func _draw_iris(L: Node2D, c: Vector2, r: float, open: float) -> void:
	var ri: float = r * 0.85 * open
	var turn: float = open * 1.2
	var twist := 1.7
	var w := TAU / IRIS_BLADES
	for i in IRIS_BLADES:
		var b0: float = w * i + turn
		var pts := PackedVector2Array()
		for q in 7:   # leading edge, rim to hole
			var t := q / 6.0
			pts.append(c + Vector2.from_angle(b0 + t * twist) * lerpf(r, ri, t))
		for q in range(1, 4):   # along the hole
			pts.append(c + Vector2.from_angle(b0 + twist + w * q / 3.0) * ri)
		for q in range(5, -1, -1):   # next blade's edge, hole to rim
			var t := q / 6.0
			pts.append(c + Vector2.from_angle(b0 + w + t * twist) * lerpf(r, ri, t))
		for q in range(2, 0, -1):   # back along the rim
			pts.append(c + Vector2.from_angle(b0 + w * q / 3.0) * r)
		if ri < 0.05:
			pts = _dedupe(pts)
		if pts.size() >= 3:
			L.draw_colored_polygon(pts, Color("7d88a8") if i % 2 == 0 else Color("6b7594"))
		var seam := PackedVector2Array()
		for q in 7:
			var t := q / 6.0
			seam.append(c + Vector2.from_angle(b0 + t * twist) * lerpf(r, ri, t))
		L.draw_polyline(seam, Color("2a3048"), maxf(r * 0.07, 0.4))

func _dedupe(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.001:
			out.append(p)
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) < 0.001:
		out.remove_at(out.size() - 1)
	return out

## Recalls (frees) every drone: the Mod was switched off or the carrier is gone.
func _clear_drones() -> void:
	for d in _drones:
		if is_instance_valid(d):
			d.queue_free()
	_drones.clear()
	_door_open.clear()
	if is_instance_valid(_door_layer):
		_door_layer.queue_free()
	for ts in _turret_sprites:
		if is_instance_valid(ts):
			ts.visible = true
	queue_redraw()

func _exit_tree() -> void:
	# Destroyed: the drones go down with the carrier. Otherwise (Mod switched
	# off, ship handed over) they are just recalled.
	if _dead:
		for d in _drones:
			if is_instance_valid(d) and d.is_alive():
				d._die()
	_clear_drones()

## Defensive Fire (Targeting tier 3): how near ordnance must be for an idle turret to shoot it down.
const DEFENSIVE_FIRE_R := 120.0
## Defensive Fire for hulls without free turrets (fixed-gun ships, drone
## carriers): when ready and idle, shoot down one enemy missile, torpedo or
## bomblet within DEFENSIVE_FIRE_R. Returns whether it fired; fixed guns
## then reload as from a normal shot.
var _df_cd := 0.0
func _defensive_fire() -> bool:
	if not Game.instance.has_tech(owner_id, "defensive_fire") or weapon_mod.has("pd"):
		return false
	var sd := _pd_target(DEFENSIVE_FIRE_R, {})
	if sd == null:
		return false
	Game.instance.intercept(self, sd)
	if not weapon_mod.has("drones"):
		_cooldown = def["cooldown"] / Game.instance.mod(owner_id, "fire_rate")
	return true

## Point-Defense: x damage against Interceptor Drones.
const PD_DRONE_MULT := 2.0
## Point-Defense: the nearest enemy drone within weapon range `r` not
## already taken by another of this ship's turrets.
func _pd_drone(r: float, claimed: Dictionary) -> Node2D:
	var best: Node2D = null
	var best_d := r
	for d in get_tree().get_nodes_in_group("drones"):
		if not is_instance_valid(d) or not d.is_alive() or claimed.has(d) or not d.is_enemy_of(owner_id):
			continue
		var dist := global_position.distance_to(d.global_position)
		if dist < best_d:
			best_d = dist
			best = d
	return best

## Point-Defense: the nearest enemy missile, torpedo or bomblet within `r`
## not already being shot by another of this ship's turrets.
func _pd_target(r: float, claimed: Dictionary) -> Node2D:
	var best: Node2D = null
	var best_d := r
	for p in get_tree().get_nodes_in_group("ordnance"):
		if not is_instance_valid(p) or claimed.has(p) or p.owner_pid == owner_id or not Game.instance.is_hostile(owner_id, p.owner_pid):
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best

## True when `point` lies inside the forward firing arc.
func bears_on(point: Vector2, arc: float = FIRE_ARC) -> bool:
	return absf(angle_difference(rotation, (point - global_position).angle())) <= arc

const SCAN_INTERVAL := 0.2
var _scan_cd: float = 0.0
## max_speed() is asked several times a tick; compute it once per tick.
var _speed_frame: int = -1
var _speed_cache: float = 0.0
## Where _arrive was last steering to (for AI sun avoidance).
var _nav_goal: Vector2
## Route around debris rings: remaining waypoints, the goal they lead to,
## and when it was planned / last checked for a straight shot.
var _path := PackedVector2Array()
var _path_final := Vector2.INF
var _path_time: float = -100.0
var _direct_time: float = -100.0
var _direct := false
## AI ships only enter a star's radiation zone when their destination is
## inside it (an enemy parked there) and they have at least this much hull.
const SUN_RISK_HP := 0.6
var target: SpaceEntity
## The class's active weapon Mod (Defs.MOD_WEAPONS entry), {} for none.
var weapon_mod := {}
## Attack runs (Proton Torpedoes): seconds left peeling away after a shot.
var _run_out := 0.0
## True when `target` came from an attack order (player or AI), not from the
## ship picking a fight on its own: turrets focus only an ordered target.
var target_ordered := false
## An Asteroid (barges) or a gas giant Planet (skimmers); both expose
## resource, amount, radius and extract().
var mine_target: Node2D
var cargo: int = 0
var cargo_type: String = "minerals"
var colonize_target: Planet
var bombard_target: Planet
var build_site: Vector2
## What a Constructor is building at build_site: "starbase" or "depot".
var build_kind: String = "starbase"
## Which variant a depot being built will fit.
var build_variant: String = "plasma"
## Refit (see order_refit): the variant being fitted, the depot, and the
## refit time still to go.
var refit_variant: String = ""
var refit_depot: WeaponsDepot
var refit_left: float = 0.0

## Jobs (see Abilities): when the Q ability can be used again, until when
## its effect lasts, and the ships a Repair Tender is currently healing.
var ability_ready_at: float = 0.0
var ability_until: float = 0.0
var _repairing: Array = []
var _repair_timer: float = 0.0
var _cooldown: float = 0.0
var _mine_timer: float = 0.0
## Fractional ore gathered between ticks (nodes hold whole units).
var _mine_carry: float = 0.0
## How long a harvester has been doing nothing (see IDLE_RETASK).
var _idle_for: float = 0.0
## The drop-off this ship was sent to by hand, if any (see order_return).
var dropoff: SpaceEntity = null
## Told to hold position by its owner (Stop). A held harvester stays held: it
## is the one way to park a barge somewhere and have it stay there. Any other
## order releases it.
var held: bool = false
var _acquire_timer: float = 0.0
var _flame_timer: float = 0.0
## Carrier turrets traverse on their own, so the hull need not come about.
## Kept as a global angle; the sprites are drawn relative to the hull.
var _turret_rot: float = 0.0
var _turret_sprites: Array[Sprite2D] = []
## Independent turrets: each has its own aim (global angle), target and
## cooldown. With an attack order they all focus the ordered target while it
## is in reach; otherwise each picks its own, spreading over nearby enemies.
var _t_rot: Array[float] = []
var _t_target: Array = []
var _t_cd: Array[float] = []
var _t_near: Array = []      # enemies in reach, nearest first (rescanned)
## Ion Lance: per turret, seconds on its current target, and the beams to draw
## this frame ([from, to] in world space).
var _t_beam_time: Array[float] = []
var _beams: Array = []
## Tractor Beams: [from, to] to draw this frame, and per-turret far targets.
var _tbeams: Array = []
var _t_far: Array = []
var _t_far_scan := 0.0
## Being tractored: the product of (1 - slow) of every beam on this ship,
## gathered over one physics frame and used for the next (_tractor_keep).
var _tr_frame := -1
var _tr_acc := 1.0
var _tr_prev := 1.0
## Interceptor Drones (Drone nodes, null while being rebuilt) and the
## seconds left on each rebuild.
var _drones: Array = []
## Seconds until the next drone is built; when each door last opened.
var _drone_timer := 0.0
## Dev (duels): launch the whole set at once instead of one every DRONE_BUILD.
var drones_ready := false
## Loading a save: this many drones were out, so launch them at once.
var drones_saved := 0

## Seconds until this carrier launches its next drone (for the panel).
func drone_next_in() -> float:
	return _drone_timer

## Live Interceptor Drones out from this carrier (for saves).
func drone_count() -> int:
	return _drones.filter(func(d): return is_instance_valid(d) and d.is_alive()).size()
var _door_open: Array[float] = []
var _door_layer: Node2D = null
var _t_scan := 0.0
## One Sprite2D per thruster, built from the hull by _rebuild_flames().
var _flames: Array[Sprite2D] = []

@onready var hull_sprite: Sprite2D = $Hull
@onready var team_sprite: Sprite2D = $Team
@onready var flame_sprite: Sprite2D = $Flame

func _ready() -> void:
	_apply_visuals()
	if Engine.is_editor_hint():
		return
	super._ready()
	add_to_group("ships")
	def = Defs.SHIPS[ship_type]
	_apply_def_visuals()
	display_name = Game.instance.ship_name(owner_id, ship_type)
	refresh_stats()
	hp = max_hp
	# A solar sail's shield starts empty and is only charged by harvesting.
	shield = max_shield
	armor = max_armor
	radius = def["radius"]
	move_goal = global_position
	_acquire_timer = randf() * 0.3
	if Defs.CARGO_TANK.has(ship_type):
		_cargo_fx = CargoTank.new()
		_cargo_fx.host = self
		# Above the hull sprite, and rotating with it: the tank is part of
		# the ship, not an overlay above it.
		_cargo_fx.z_index = 1
		add_child(_cargo_fx)
	if is_miner() or def.get("role", "") == "skimmer":
		_harvest_fx = HarvestFx.new()
		_harvest_fx.host = self
		# top_level, like the status gauges: the beam is a line between two
		# points in the world, so it must not inherit the hull's rotation, and
		# it has to repaint every frame to animate.
		_harvest_fx.top_level = true
		_harvest_fx.z_index = -1
		add_child(_harvest_fx)
	# Rank chevrons beside every warship (see MarkTag).
	if Defs.MARK_LINES.has(def.get("base", ship_type)):
		_mark_tag = MarkTag.new()
		_mark_tag.host = self
		_mark_tag.top_level = true
		_mark_tag.z_index = 20
		add_child(_mark_tag)
		_apply_mark()

func _apply_visuals() -> void:
	if not is_node_ready() and not has_node("Hull"):
		return
	var hull: Sprite2D = get_node("Hull")
	var team: Sprite2D = get_node("Team")
	# One hull per class, whatever its rank or variant.
	var art: String = "ship_" + Defs.SHIPS.get(ship_type, {}).get("base", ship_type)
	hull.texture = Defs.tex(art)
	team.texture = Defs.tex(art + "_team")
	team.modulate = Defs.team_color(owner_id)
	# The art is drawn at Defs.ART_SCALE and shown at 1/ART_SCALE, so a ship
	# covers the same world space as before at twice the detail.
	# "size" draws a class bigger than its art (destroyer 1.33x, cruiser
	# 1.66x, carrier 2x); its radius in Defs is scaled to match.
	hull.scale = Vector2.ONE / Defs.ART_SCALE * float(Defs.SHIPS.get(ship_type, {}).get("size", 1.0))
	team.scale = hull.scale
	_apply_mark()
	_rebuild_flames(hull.texture, hull.scale)

## Rank and fit at a glance: tiny chevrons beside the ship, one per mark
## (Mk I = one, Mk IV = four), in the colour of its variant - yellow for a
## generalist (Defs.GENERALIST_COLOR).
func _apply_mark() -> void:
	if has_node("Mark"):
		get_node("Mark").texture = null
		get_node("Mark").visible = false
	if _mark_tag == null:
		return
	var level := Game.instance.mark_level(owner_id, ship_type) if Game.instance else 0
	_mark_tag.count = level + 1
	_mark_tag.color = Defs.VARIANTS[def["variant"]]["color"] if def.has("variant") else Defs.GENERALIST_COLOR
	_mark_tag.queue_redraw()

## One flame per thruster, found from the hull art itself: the stern column
## is scanned for runs of solid pixels and a flame is placed behind the
## middle of each. A carrier gets one per nacelle, a destroyer one per prong,
## a barge one on its keel â and nothing has to be told where its engines
## are when the art changes.
func _rebuild_flames(tex: Texture2D, art_scale: Vector2) -> void:
	for f in _flames:
		if is_instance_valid(f):
			f.queue_free()
	_flames.clear()
	if not has_node("Flame"):
		return
	var tmpl: Sprite2D = get_node("Flame")
	tmpl.visible = false
	if tex == null:
		return
	var img := tex.get_image()
	var w := img.get_width()
	var h := img.get_height()
	# The first column carrying any hull is the stern; step one in from it so
	# a run is the member itself rather than its outline.
	var sx := -1
	for x in w:
		for y in h:
			if img.get_pixel(x, y).a > 0.0:
				sx = x
				break
		if sx >= 0:
			break
	if sx < 0:
		return
	sx = mini(sx + 1, w - 1)
	var centers: Array[float] = []
	var start := -1
	for y in h:
		var is_solid: bool = img.get_pixel(sx, y).a > 0.0
		if is_solid and start < 0:
			start = y
		elif not is_solid and start >= 0:
			centers.append((start + y - 1) / 2.0)
			start = -1
	if start >= 0:
		centers.append((start + h - 1) / 2.0)
	var back: float = -(w / 2.0) * art_scale.x - 2.0
	for c in centers:
		var f: Sprite2D = tmpl.duplicate()
		f.scale = art_scale
		f.position = Vector2(back, (c - h / 2.0) * art_scale.y)
		f.visible = false
		add_child(f)
		_flames.append(f)

## Weapon reach, after the Weapons line ("range").
func weapon_range() -> float:
	return float(def["range"]) * float(weapon_mod.get("range", 1.0)) * (Game.instance.mod(owner_id, "range") if Game.instance else 1.0)

## Turret sprites for a hull that has mounts: positions are fractions of the
## sprite (x along the hull from the stern, y off the keel), so they sit
## right whatever the mark's shape.
## Fittings that come from the def rather than the sprite: turret mounts and
## drone doors. Called once `def` is known, since _ready builds the visuals
## before it assigns one.
func _apply_def_visuals() -> void:
	_rebuild_turrets()
	_apply_mark()

func _rebuild_turrets() -> void:
	for t in _turret_sprites:
		if is_instance_valid(t):
			t.queue_free()
	_turret_sprites.clear()
	if not def.has("turrets") or not has_node("Hull"):
		return
	var hull: Sprite2D = get_node("Hull")
	if hull.texture == null:
		return
	var size := Vector2(hull.texture.get_size()) * hull.scale
	for m in def["turrets"]:
		var t := Sprite2D.new()
		t.texture = Defs.tex("ship_turret")
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.scale = hull.scale * float(def.get("turret_scale", 1.0))
		t.position = Vector2((float(m[0]) - 0.5) * size.x, float(m[1]) * size.y)
		add_child(t)
		_turret_sprites.append(t)
	var n := _turret_sprites.size()
	_t_rot.resize(n)
	_t_rot.fill(rotation)
	_t_target.resize(n)
	_t_target.fill(null)
	_t_cd.resize(n)
	_t_beam_time.resize(n)
	_t_beam_time.fill(0.0)
	for i in n:
		_t_cd[i] = randf() * float(def.get("cooldown", 1.0))

func is_carrier() -> bool:
	return def.get("base", ship_type) == "carrier"

## Harvesters (economy subclass): the Mining Barge and the Gas Skimmer. Every
## tech that says "harvesters" (Logistics gather rate and cargo, Convoy
## Protocols) applies to exactly these.
func is_harvester() -> bool:
	return def.get("subclass", "") == "harvester"

func is_miner() -> bool:
	return is_harvester()

## Barges mine asteroids; skimmers mine gas giants and spice nebulae.
func can_mine(target: Node2D) -> bool:
	if def.get("role", "") == "miner":
		return target is Asteroid
	if def.get("role", "") == "skimmer":
		# Gas giants (minerals) and spice nebulae (spice gas).
		return target is NebulaPocket or (target is Planet and not (target as Planet).is_habitable())
	return false

func _find_mine_target(resource: String) -> Node2D:
	if def["role"] == "skimmer":
		if resource == "spice":
			return Game.instance.nearest_pocket(global_position, 3000.0)
		return Game.instance.nearest_gas_giant(global_position, 3000.0)
	return Game.instance.nearest_asteroid(global_position, 900.0, resource)

## The closest thing this harvester can work, whatever it yields: a barge
## weighs mineral rocks against spice rocks, a skimmer gas giants against
## nebulae, and the nearer one wins. Distance is what decides, because a
## shorter run is more of everything per minute.
func _nearest_resource() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for t in [_find_mine_target("minerals"), _find_mine_target("spice")]:
		if t == null:
			continue
		var d: float = global_position.distance_to(t.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best

## Re-derives hull/armor/shield caps from research, keeping current fractions.
func refresh_stats() -> void:
	var g := Game.instance
	# The weapon Mod this class fires with (Defs.MOD_WEAPONS), if any.
	var cls: String = str(Defs.SHIPS[ship_type].get("base", ship_type))
	var m := g.active_mod(owner_id, cls) if def.get("role", "") == "warship" else ""
	weapon_mod = Defs.MOD_WEAPONS.get(m, {})
	# Dev (tuning grids): SL_MOD_DMG overrides the tested Mod's damage.
	if OS.get_environment("SL_MOD_DMG") != "" and m == OS.get_environment("SL_MOD"):
		weapon_mod = weapon_mod.duplicate()
		weapon_mod["dmg"] = float(OS.get_environment("SL_MOD_DMG"))
	display_name = g.ship_name(owner_id, ship_type)
	_apply_mark()
	var hp_frac := hp / max_hp if max_hp > 0.0 else 1.0
	var ar_frac := armor / max_armor if max_armor > 0.0 else 1.0
	var sh_frac := shield / max_shield if max_shield > 0.0 else 1.0
	max_hp = def["hp"] * g.hull_mod(owner_id, ship_type, "hull")
	max_shield = def["shield"] * g.hull_mod(owner_id, ship_type, "shield")
	hp = max_hp * hp_frac
	shield = max_shield * sh_frac
	max_armor = def.get("armor", 0.0) * g.hull_mod(owner_id, ship_type, "armor")
	armor = max_armor * ar_frac

func max_speed() -> float:
	var f := Engine.get_physics_frames()
	if f == _speed_frame:
		return _speed_cache
	_speed_frame = f
	var storm := IonStorm.SLOW if Game.instance.in_storm(global_position) else 1.0
	_speed_cache = def["speed"] * Game.instance.mod(owner_id, "speed") * Game.instance.ship_speed_factor(owner_id) * storm * _tractor_keep()
	return _speed_cache

## How fast this ship fills its hold on `node`, per minute (Defs.PER_MIN).
## (Spice and nebula gas: Defs.HARVEST_SPICE_MULT / HARVEST_NEBULA_MULT, now 1.)
func harvest_rate(node: Node2D) -> float:
	var base: float = float(def.get("harvest", 0.5)) * (Game.instance.mod(owner_id, "harvest") if is_harvester() else 1.0)
	if node is NebulaPocket:
		return base * Defs.HARVEST_NEBULA_MULT
	if node.resource == "spice":
		return base * Defs.HARVEST_SPICE_MULT
	return base

func cargo_cap() -> int:
	return int(def.get("cargo", 0) * (Game.instance.mod(owner_id, "cargo") if is_harvester() else 1.0))

# ---------------------------------------------------------------- orders

func take_damage(amount: float, from: SpaceEntity = null, profile: Dictionary = {}) -> void:
	super.take_damage(amount, from, profile)
	if owner_id == Game.instance.player_id and hp > 0.0 and from != null:
		Game.instance.alert("Your ships are under attack!", "alert_ships", false, global_position)

# ---------------------------------------------------------------- order queue

## Shift-queued orders, each [method name, args]. The ship replays the next
## one whenever it runs out of work (see _physics_process), so you can chain
## "mine here, then there, then dock" in one go.
var order_queue: Array = []

## Issue an order now, or add it to the queue when the player held Shift and
## the ship is already busy. A plain (unqueued) order wipes the queue.
func do_or_queue(queued: bool, method: String, args: Array) -> void:
	if queued and (state != State.IDLE or not order_queue.is_empty()):
		order_queue.append([method, args])
		queue_redraw()
		return
	if not queued:
		order_queue.clear()
	callv(method, args)

## Starts the next queued order; drops entries whose target is gone.
func _pop_order() -> void:
	while not order_queue.is_empty():
		var o: Array = order_queue.pop_front()
		var args: Array = o[1]
		var dead := false
		for a in args:
			if typeof(a) == TYPE_OBJECT and not is_instance_valid(a):
				dead = true
		if dead:
			continue
		callv(o[0], args)
		queue_redraw()
		return

## Where each queued order points, for the waypoint line (see _draw).
func queued_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for o in order_queue:
		for a in o[1]:
			# typeof first: "is" on a freed instance is an error.
			if typeof(a) == TYPE_VECTOR2:
				out.append(a)
			elif typeof(a) == TYPE_OBJECT and is_instance_valid(a) and a is Node2D:
				out.append(a.global_position)
	return out

func order_move(pos: Vector2) -> void:
	held = false
	state = State.MOVE
	move_goal = pos
	target = null

func order_attack_move(pos: Vector2) -> void:
	held = false
	if is_miner():
		order_move(pos)
		return
	state = State.ATTACK_MOVE
	attack_move_goal = pos
	move_goal = pos
	target = null

func order_attack(e: SpaceEntity) -> void:
	held = false
	if is_miner():
		return
	# Not already attack-moving somewhere: once this target is dead, hold
	# here (the old default goal was the map centre - into the star).
	if state != State.ATTACK_MOVE:
		attack_move_goal = global_position
	state = State.ATTACK
	target = e
	target_ordered = true

func order_mine(a: Node2D) -> void:
	held = false
	if not can_mine(a):
		order_move(a.global_position)
		return
	if cargo > 0 and a.resource != cargo_type:
		state = State.RETURN
	else:
		state = State.RETURN if cargo >= cargo_cap() else State.MINE_GO
	mine_target = a

## `at` names the construct to unload at; without it the nearest one wins.
func order_return(at: SpaceEntity = null) -> void:
	held = false
	dropoff = at
	if is_miner() and cargo > 0:
		state = State.RETURN

func order_colonize(p: Planet) -> void:
	held = false
	if def["role"] != "colony":
		order_move(p.global_position)
		return
	colonize_target = p
	state = State.COLONIZE

## Warships: close to weapons range of an enemy planet and fire on it until
## its population is gone.
func order_bombard(p: Planet) -> void:
	held = false
	if def["weapon"] == "":
		order_move(p.global_position)
		return
	bombard_target = p
	target = null
	state = State.BOMBARD

func order_build_starbase(pos: Vector2) -> void:
	held = false
	if def["role"] != "constructor":
		return
	build_site = pos
	build_kind = "starbase"
	state = State.BUILD

func order_stop() -> void:
	# Deliberate: this is the player (or the AI) saying stay put, which turns
	# off the idle re-tasking below.
	held = true
	order_queue.clear()
	state = State.IDLE
	target = null
	move_goal = global_position

# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if docked:
		return
	if def.has("solar_sail"):
		_solar_tick(delta)
	else:
		_regen_shields(delta)
	if def.get("job", "") == "field_repair":
		_repair_timer -= delta
		if _repair_timer <= 0.0:
			_repair_timer = 0.5
			_repairing = Abilities.repair_tick(self, 0.5)
			queue_redraw()
	# Out of energy: weapons recharge (and engines run) at a quarter speed.
	var power := Game.instance.ship_speed_factor(owner_id)
	_cooldown -= delta * power
	_run_out -= delta
	for i in _t_cd.size():
		_t_cd[i] -= delta * power
	_acquire_timer -= delta
	_scan_cd -= delta

	var desired := Vector2.ZERO
	var face_target: SpaceEntity = null
	# What the hull should come about to point at, for things that are not
	# entities (a rock, a gas giant, a patch of nebula).
	var face_at: Node2D = null

	if state != State.IDLE:
		_idle_for = 0.0

	match state:
		State.IDLE:
			if not order_queue.is_empty():
				_pop_order()
			elif is_miner() and not held:
				# A harvester with nothing to do goes back to work, unless its
				# owner parked it on purpose.
				_idle_for += delta
				if _idle_for >= IDLE_RETASK:
					_idle_for = 0.0
					if cargo > 0:
						order_return()
					else:
						var job := _nearest_resource()
						if job != null:
							order_mine(job)
			elif def["weapon"] != "" and _acquire_timer <= 0.0:
				var e := Game.instance.nearest_enemy(self, weapon_range() + 60.0)
				if e:
					attack_move_goal = global_position
					target = e
					target_ordered = false
					state = State.ATTACK
				else:
					# Nothing flying nearby: an enemy colony already in range is
					# worth shooting at too, and it will not come to us.
					var ep := Game.instance.nearest_enemy_planet(owner_id, global_position, weapon_range())
					if ep != null:
						attack_move_goal = global_position
						order_bombard(ep)
					elif Game.instance.is_ai(owner_id) and max_shield > 0.0 and Game.instance.in_nebula(global_position):
						_leave_nebula()
			desired = _arrive(move_goal, 0.0)
		State.MOVE:
			desired = _arrive(move_goal, 1.0)
			if global_position.distance_to(move_goal) < 6.0:
				state = State.IDLE
		State.ATTACK_MOVE:
			if _acquire_timer <= 0.0:
				var e := Game.instance.nearest_enemy(self, weapon_range() + 120.0)
				if e:
					target = e
					target_ordered = false
					state = State.ATTACK
				else:
					# An enemy colony on the way counts as something to attack.
					var ep := Game.instance.nearest_enemy_planet(owner_id, global_position, weapon_range())
					if ep != null:
						order_bombard(ep)
			desired = _arrive(attack_move_goal, 1.0)
			if global_position.distance_to(attack_move_goal) < 8.0:
				state = State.IDLE
				move_goal = global_position
		State.ATTACK:
			if not is_instance_valid(target) or not target.is_alive():
				target = null
				# Resume the attack-move (or guard spot) we were on.
				state = State.ATTACK_MOVE
			else:
				var d := global_position.distance_to(target.global_position)
				var keep: float = weapon_range() * 0.8
				if weapon_mod.get("run", false) and _run_out > 0.0:
					# Breaking away after a launch: curve out and off to the side.
					var away := (global_position - target.global_position).normalized()
					desired = (away + away.orthogonal() * 0.8).normalized() * max_speed()
				else:
					if d > keep * (0.6 if weapon_mod.get("run", false) else 1.0):
						desired = _arrive(target.global_position, 1.0)
					# A turreted hull (the carrier) lets its mounts do the aiming and
					# keeps its own heading; only fixed guns need the nose on target.
					if not def.has("turrets"):
						face_target = target
		State.MINE_GO:
			if not is_instance_valid(mine_target) or mine_target.amount <= 0:
				var want: String = mine_target.resource if is_instance_valid(mine_target) else cargo_type
				mine_target = _find_mine_target(want)
				if mine_target == null:
					state = State.RETURN if cargo > 0 else State.IDLE
			else:
				# Stands off far enough that the harvesting beam is a beam and not
				# a smudge between two touching sprites.
				var reach: float = mine_target.radius + radius + 16.0
				if global_position.distance_to(mine_target.global_position) <= reach + 4.0:
					state = State.MINING
					_mine_carry = 0.0
				else:
					desired = _arrive(mine_target.global_position, 1.0, reach)
		State.MINING:
			if not is_instance_valid(mine_target) or mine_target.amount <= 0:
				state = State.MINE_GO
			else:
				# Come about onto the rock first: the beam comes out of the
				# nose, so nothing is harvested until the nose is on it.
				face_at = mine_target
				if not bears_on(mine_target.global_position, HARVEST_ARC):
					_mine_carry = 0.0
				else:
					# Fill the hold at a steady rate; head home once full.
					cargo_type = mine_target.resource
					_mine_carry += harvest_rate(mine_target) / Defs.PER_MIN * delta
					var whole := int(_mine_carry)
					if whole > 0:
						_mine_carry -= float(whole)
						cargo += mine_target.extract(mini(whole, cargo_cap() - cargo))
						queue_redraw()
					if cargo >= cargo_cap():
						state = State.RETURN
						queue_redraw()
		State.COLONIZE:
			if not is_instance_valid(colonize_target) or colonize_target.owner_id != 0 or not colonize_target.is_habitable():
				state = State.IDLE
				move_goal = global_position
			else:
				var reach := colonize_target.radius + radius + 6.0
				# In orbit: colonizing takes Planet.COLONIZE_TIME; the ship is
				# used up when the colony is founded.
				if global_position.distance_to(colonize_target.global_position) <= reach + 4.0 and colonize_target.progress_colonize(self, delta):
					_dead = true
					died.emit(self)
					queue_free()
					return
				desired = _arrive(colonize_target.global_position, 1.0, reach)
		State.BOMBARD:
			if not is_instance_valid(bombard_target) or not bombard_target.is_enemy_of(owner_id):
				bombard_target = null
				state = State.IDLE
				move_goal = global_position
			else:
				var keep: float = weapon_range() * 0.8 + bombard_target.radius
				if global_position.distance_to(bombard_target.global_position) > keep:
					desired = _arrive(bombard_target.global_position, 1.0, keep)
				face_target = null
				# Fixed guns must point at the world to fire; a planet is no
				# SpaceEntity, so it turns via face_at (ships already in range
				# used to just sit there, pointing the wrong way).
				face_at = bombard_target
		State.BUILD:
			if global_position.distance_to(build_site) <= 8.0:
				var problem: String = Game.instance.site_problem(build_kind, build_site)
				if problem == "":
					match build_kind:
						"depot": Game.instance.found_depot(owner_id, build_site, build_variant)
						"station": Game.instance.found_station(owner_id, build_site)
						_: Game.instance.found_starbase(owner_id, build_site)
					_dead = true
					died.emit(self)
					queue_free()
					return
				if owner_id == Game.instance.player_id:
					Game.instance.message.emit("Starbase site is blocked.", Color("ff8a5a"))
				state = State.IDLE
				move_goal = global_position
			else:
				desired = _arrive(build_site, 1.0)
		State.REFIT:
			# Fly to the depot that fits this variant and wait for a free bay.
			if not is_instance_valid(refit_depot) or not refit_depot.is_alive() or refit_depot.under_construction or refit_depot.variant != refit_variant:
				refit_depot = Game.instance.nearest_depot(owner_id, global_position, refit_variant)
			if refit_depot == null:
				state = State.IDLE
				move_goal = global_position
			else:
				var hold: float = refit_depot.radius + radius + 12.0
				if global_position.distance_to(refit_depot.global_position) > hold + 8.0:
					desired = _arrive(refit_depot.global_position, 1.0, hold)
				elif refit_depot.has_room():
					refit_depot.dock(self)
		State.RETURN:
			# The one it was sent to, or whichever is closest: starbase or
			# Mining Station.
			var base: SpaceEntity = dropoff if is_instance_valid(dropoff) and dropoff.owner_id == owner_id else Game.instance.nearest_dropoff(owner_id, global_position)
			if base == null:
				state = State.IDLE
			else:
				var reach := base.radius + radius + 2.0
				if global_position.distance_to(base.global_position) <= reach + 4.0:
					Game.instance.add_resources(owner_id, {cargo_type: float(cargo)})
					cargo = 0
					dropoff = null
					state = State.MINE_GO if is_instance_valid(mine_target) else State.IDLE
					if state == State.IDLE:
						move_goal = global_position
				else:
					desired = _arrive(base.global_position, 1.0, reach)

	if _acquire_timer <= 0.0:
		_acquire_timer = 0.25

	# Turreted hulls: every turret aims and fires on its own (_fire_turrets).
	if def["weapon"] != "" and def.has("turrets") and not _turret_sprites.is_empty():
		_fire_turrets(delta)
	# Fire at whatever is in range, even while moving.
	elif def["weapon"] != "" and _cooldown <= 0.0:
		var shoot: Node2D = target if is_instance_valid(target) and target.is_alive() else null
		if state == State.BOMBARD and is_instance_valid(bombard_target):
			shoot = bombard_target
		if shoot == null or global_position.distance_to(shoot.global_position) > weapon_range() + shoot.radius:
			# Nothing locked on: scan for anything in range, but only every
			# SCAN_INTERVAL when the last scan came up empty.
			shoot = null
			if _scan_cd <= 0.0:
				shoot = Game.instance.nearest_enemy(self, weapon_range())
				if shoot == null:
					_scan_cd = SCAN_INTERVAL
		if shoot == null:
			_defensive_fire()   # fixed guns with nothing to shoot
		if shoot and global_position.distance_to(shoot.global_position) <= weapon_range() + shoot.radius:
			var dmg: float = def["damage"] * Defs.mark_mult(ship_type, Game.instance.mark_level(owner_id, ship_type))
			var ready := false
			if def.has("turrets"):
				# Turreted: the mounts traverse, the hull carries on. They
				# turn slowly enough that a corvette circling a carrier can
				# stay off the bearing.
				ready = _traverse(shoot.global_position, delta)
			else:
				# Fixed guns: come onto the bearing first.
				if face_target == null and shoot is SpaceEntity:
					face_target = shoot
				elif face_target == null and face_at == null:
					face_at = shoot
				ready = bears_on(shoot.global_position)
			if ready:
				# Every gun aims the same: a shooter on the move is a worse one,
				# and at full speed roughly a third of its shots go wide.
				var acc := lerpf(1.0, MOVING_ACCURACY, clampf(velocity.length() / maxf(max_speed(), 1.0), 0.0, 1.0))
				if Game.instance.duel_nomovepen or Game.instance.has_tech(owner_id, "gyro_stabilizers"):
					acc = 1.0
				var wpn: String = weapon_mod.get("weapon", def["weapon"])
				dmg *= float(weapon_mod.get("dmg", 1.0))
				for g in int(def.get("guns", 1)):
					if randf() >= acc:
						continue
					if wpn == "arc":
						Game.instance.arc_strike(self, shoot, dmg, weapon_mod["chain"], weapon_mod["jump"])
					else:
						Game.instance.fire(self, shoot, wpn, dmg)
				_cooldown = def["cooldown"] * float(weapon_mod.get("cd", 1.0)) / Game.instance.mod(owner_id, "fire_rate") * randf_range(0.9, 1.1)
				# Attack run: peel away for half the reload, then come round again.
				if weapon_mod.get("run", false):
					_run_out = _cooldown * 0.5

	if Game.instance.is_ai(owner_id):
		desired = _avoid_sun(desired)
	var crowd := _separation()
	# A parked ship takes the spot crowding gives it rather than fighting its
	# way back: otherwise two hulls that overlap at rest shove each other out
	# and fly straight back in, forever. Big hulls show it worst, since they
	# overlap from further away.
	if state == State.IDLE and crowd != Vector2.ZERO:
		move_goal = global_position + crowd.limit_length(radius)
	_steer(desired + crowd, delta, face_target if face_target != null else face_at)
	# Duel arena: nobody leaves.
	if Game.instance.arena_radius > 0.0 and global_position.length() > Game.instance.arena_radius:
		global_position = global_position.limit_length(Game.instance.arena_radius)

## Desired velocity toward `goal`, slowing inside the braking radius.
## `stop_at` leaves a gap (e.g. to hover beside an asteroid).
func _arrive(goal: Vector2, urgency: float, stop_at: float = 0.0) -> Vector2:
	# Ringed systems: head for the next waypoint around the debris, at full
	# speed, until the final approach.
	if Game.instance.nav != null:
		var wp := _route(goal)
		if wp.distance_to(goal) > 1.0:
			_nav_goal = wp
			return (wp - global_position).normalized() * max_speed()
	_nav_goal = goal
	var to := goal - global_position
	var dist := to.length() - stop_at
	if dist <= 1.0:
		return Vector2.ZERO
	var speed: float = max_speed()
	var slow := clampf(dist / 60.0, 0.15, 1.0)
	if urgency <= 0.0:
		slow = clampf(dist / 30.0, 0.0, 0.5)
	return to.normalized() * speed * slow

## Whether this ship is holding a spot rather than going somewhere: only
## ships at rest push each other apart.
func _parked() -> bool:
	return (state == State.IDLE or state == State.MINING) and velocity.length() < 12.0

## Ships do not collide: they fly over and under each other, and nothing is
## ever shouldered off course. The only crowding left is between ships that
## are both PARKED, which keeps a resting fleet spread out instead of stacked
## on one pixel — and even that is gentle.
func _separation() -> Vector2:
	if not _parked():
		return Vector2.ZERO
	# Reads the fine grid directly (no temporary array), only the cells that
	# could hold an overlapping hull (reach = our radius + the largest hull).
	var push := Vector2.ZERO
	var g := Game.instance
	# The reach must cover the LARGEST hull out there, not an average one:
	# if it is shorter than radius + other.radius, two big hulls push apart
	# until they fall out of each other's reach, drift back together and push
	# again — parked carriers visibly judder against each other.
	var reach := radius + MAX_HULL_RADIUS
	var p := global_position
	var lo := Vector2i(((p - Vector2(reach, reach)) / Game.CELL).floor())
	var hi := Vector2i(((p + Vector2(reach, reach)) / Game.CELL).floor())
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var cell = g._grid.get(Vector2i(cx, cy))
			if cell == null:
				continue
			for other in cell:
				if other == self or not is_instance_valid(other):
					continue
				# A ship on the move is passed through, not pushed against.
				if other is Ship and not (other as Ship)._parked():
					continue
				var d: Vector2 = p - other.global_position
				if absf(d.x) > reach or absf(d.y) > reach:
					continue
				var min_d: float = radius + other.radius
				var len := d.length()
				if len < min_d and len > 0.01:
					push += d / len * (min_d - len) * 2.0
				elif len <= 0.01:
					push += Vector2.from_angle(randf() * TAU) * 6.0
	return push

func _steer(desired: Vector2, delta: float, face: Node2D) -> void:
	var speed: float = max_speed()
	var accel := speed * 2.2
	velocity = velocity.move_toward(desired.limit_length(speed), accel * delta)
	var step := velocity * delta
	# Debris is solid: slide along it (try each axis), else stop.
	if Game.instance.nav != null and Game.instance.is_blocked(global_position + step, radius * 0.5):
		if not Game.instance.is_blocked(global_position + Vector2(step.x, 0), radius * 0.5):
			step = Vector2(step.x, 0)
			velocity.y = 0.0
		elif not Game.instance.is_blocked(global_position + Vector2(0, step.y), radius * 0.5):
			step = Vector2(0, step.y)
			velocity.x = 0.0
		else:
			step = Vector2.ZERO
			velocity = Vector2.ZERO
	global_position += step

	var face_dir := Vector2.ZERO
	if face:
		face_dir = face.global_position - global_position
	elif velocity.length() > 8.0:
		face_dir = velocity
	if face_dir != Vector2.ZERO:
		# Bigger hulls turn slower.
		var turn_rate := clampf(6.0 * 8.0 / radius, 1.2, 6.0) * Game.instance.ship_speed_factor(owner_id)
		rotation = rotate_toward(rotation, face_dir.angle(), turn_rate * delta)

	var thrusting := velocity.length() > 12.0
	if thrusting:
		_flame_timer += delta
	var frame := int(_flame_timer * 12.0) % 2
	for f in _flames:
		f.visible = thrusting
		f.frame = frame

func _draw() -> void:
	if Engine.is_editor_hint():
		return
	_draw_job()
	# Ion Lance beams, brighter and wider as they ramp up.
	for bm in _beams:
		var a := to_local(bm[0])
		var z := to_local(bm[1])
		var k: float = clampf((float(bm[2]) - 0.6) / 0.8, 0.0, 1.0)
		var col: Color = Defs.VARIANTS[def["variant"]]["color"] if def.has("variant") else Color("7fd8ff")
		draw_line(a, z, Color(col, 0.35 + 0.25 * k), (3.0 + 4.0 * k) / scale.x)
		draw_line(a, z, Color(Color.WHITE, 0.8), (1.0 + 1.0 * k) / scale.x)
	# Tractor beams: a pale green cone, stronger the harder it holds.
	for bm in _tbeams:
		var a := to_local(bm[0])
		var z := to_local(bm[1])
		var side := (z - a).orthogonal().normalized() * 7.0 / scale.x
		draw_colored_polygon(PackedVector2Array([a, z + side, z - side]), Color(0.6, 1.0, 0.7, 0.10 + 0.15 * float(bm[2])))
		draw_line(a, z, Color(0.6, 1.0, 0.7, 0.55), 1.0 / scale.x)
	super._draw()

var _harvest_fx: HarvestFx
var _mark_tag: MarkTag

## A warship's mark chevrons, drawn upright beside it whatever its heading.
class MarkTag extends Node2D:
	var host: Ship
	var count := 1
	var color := Color.YELLOW

	func _process(_delta: float) -> void:
		if not is_instance_valid(host):
			return
		# The same small size on screen at any zoom.
		var z: float = get_viewport().get_canvas_transform().get_scale().x
		scale = Vector2.ONE / maxf(z, 0.01) * 1.6
		global_position = host.global_position + Vector2(-host.radius - 6.0, host.radius * 0.3)
		visible = host.visible

	func _draw() -> void:
		# Stacked upward, the lowest first, each with a dark backing so it
		# reads on any background.
		for k in count:
			var y := -k * 3.5
			var pts := PackedVector2Array([Vector2(-3, y + 1.5), Vector2(0, y - 1.5), Vector2(3, y + 1.5)])
			draw_polyline(pts, Color(0, 0, 0, 0.8), 2.6)
			draw_polyline(pts, color, 1.3)

var _cargo_fx: CargoTank

## Paints what is in the hold into the glass tank the hull art leaves empty.
class CargoTank extends Node2D:
	var host: Ship
	var _shown := -1

	func _process(_delta: float) -> void:
		if is_instance_valid(host) and host.cargo != _shown:
			_shown = host.cargo
			queue_redraw()

	func _draw() -> void:
		if is_instance_valid(host):
			host.draw_cargo(self)

## The harvesting beam: a working barge or skimmer pulls a visible stream of
## ore off the rock, so a glance says which ships are earning their upkeep.
## Drawn by a top_level child, which keeps the beam straight whatever the hull
## is doing and lets it animate every frame instead of once per unit mined.
class HarvestFx extends Node2D:
	var host: Ship

	func _process(_delta: float) -> void:
		if not is_instance_valid(host):
			return
		global_position = host.global_position
		var working: bool = host.state == Ship.State.MINING and is_instance_valid(host.mine_target)
		visible = working and host.visible
		if working:
			queue_redraw()

	func _draw() -> void:
		if is_instance_valid(host):
			host.draw_harvest(self)

## Motes travelling up the beam, per second of flight.
const HARVEST_MOTES := 5
const HARVEST_MOTE_SPEED := 0.7

## Draws the beam into `on` (the overlay), in world-aligned local space.
func draw_harvest(on: CanvasItem) -> void:
	if not is_instance_valid(mine_target) or not bears_on(mine_target.global_position, HARVEST_ARC):
		return
	var to: Vector2 = mine_target.global_position - global_position
	var dist := to.length()
	if dist < 1.0:
		return
	var dir := to / dist
	var col: Color = Defs.RESOURCE_COLORS.get(mine_target.resource, Color("3fd6b0"))
	# From the hull's nose to the target's surface, not its centre: a gas
	# giant's centre is a long way inside it.
	var from := dir * radius
	var at: Vector2 = to - dir * float(mine_target.radius)
	if (at - from).dot(dir) <= 0.0:
		at = to
	var t := Game.now()
	# The beam: a wide soft column with a bright core, breathing slowly.
	var pulse := 0.55 + 0.25 * sin(t * 6.0)
	on.draw_line(from, at, Color(col, 0.18 * pulse), 4.0)
	on.draw_line(from, at, Color(col, 0.75 * pulse), 1.0)
	# Ore coming up the beam, each mote fading in at the rock and out at the
	# hull so the stream has a direction.
	var span := at - from
	var side := Vector2(-dir.y, dir.x)
	for i in HARVEST_MOTES:
		var k: float = fmod(t * HARVEST_MOTE_SPEED + float(i) / float(HARVEST_MOTES), 1.0)
		var p: Vector2 = at - span * k + side * sin(k * TAU + float(i)) * 1.5
		var a: float = sin(k * PI)
		on.draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(col, a))
	# A bite of light where the beam meets the rock.
	var flare: float = 2.0 + 1.5 * absf(sin(t * 4.0))
	on.draw_circle(at, flare, Color(col, 0.35))

## What is in the hold, painted inside the glass tank the hull art leaves
## empty: the resource's own colour, filling from the stern forward as the
## load grows. An empty tank stays dark, so a loaded barge reads as loaded at
## a glance and an idle one does not.
func draw_cargo(on: CanvasItem) -> void:
	var t: Array = Defs.CARGO_TANK.get(ship_type, [])
	if t.is_empty() or cargo <= 0:
		return
	var cap: int = cargo_cap()
	if cap <= 0:
		return
	var frac: float = clampf(float(cargo) / float(cap), 0.0, 1.0)
	var x0: float = float(t[0]) + 1.0
	var x1: float = float(t[1]) - 1.0
	var hw: float = float(t[2]) - 1.0
	var col: Color = Defs.RESOURCE_COLORS.get(cargo_type, Color("3fd6b0"))
	# The whole tank takes a wash of the resource's colour, so WHAT is being
	# hauled reads even with one unit in the hold; the bright band on top of
	# it is HOW MUCH, filling from the stern forward.
	on.draw_rect(Rect2(x0, -hw, x1 - x0, hw * 2.0), Color(col, 0.30))
	var w := maxf((x1 - x0) * frac, 1.0)
	on.draw_rect(Rect2(x0, -hw, w, hw * 2.0), col)
	on.draw_rect(Rect2(x0, -hw, w, 1.0), col.lightened(0.45))
	# A sheen down the glass, so it reads as a window and not a decal.
	on.draw_rect(Rect2(x1 - 1.0, -hw, 1.0, hw * 2.0), Color(1, 1, 1, 0.22))

## AI steering around stars' radiation zones. Paths that would cross a zone
## bend along its edge; a ship that finds itself inside without a reason
## heads straight out. Entering is allowed only for a strategic goal inside
## the zone, and only while hull is at least SUN_RISK_HP.
func _avoid_sun(desired: Vector2) -> Vector2:
	var goal := _nav_goal if desired != Vector2.ZERO else global_position
	var done_binary := false
	for star in Game.instance.stars_list:
		var c: Vector2 = star.global_position
		var r: float = star.radiation_radius + radius + 12.0
		# A binary pair is one obstacle for the AI: its whole orbit plus both
		# zones, centered on the system center (threading the moving lane
		# between the suns is left to the player).
		if star.orbit_radius > 0.0:
			if done_binary:
				continue
			done_binary = true
			c = Vector2.ZERO
			r += star.orbit_radius
		# Strategic exception: only a goal inside an actual star zone counts.
		var goal_inside := false
		if desired != Vector2.ZERO:
			for s2 in Game.instance.stars_list:
				if goal.distance_to(s2.global_position) < s2.radiation_radius + radius + 12.0:
					goal_inside = true
		if goal_inside and hp >= max_hp * SUN_RISK_HP:
			continue
		var out := global_position - c
		var speed: float = max_speed()
		if out.length() < r:
			# Inside with no good reason: leave by the shortest way.
			return out.normalized() * speed
		if desired == Vector2.ZERO:
			continue
		if goal_inside:
			# Worth it only with enough hull: otherwise hold at the edge.
			if out.length() < r + 20.0 and desired.dot(-out) > 0.0:
				return Vector2.ZERO
			continue
		# Does the straight path to the goal cut through the zone?
		var seg := goal - global_position
		var t := clampf((c - global_position).dot(seg) / maxf(seg.length_squared(), 0.001), 0.0, 1.0)
		if (global_position + seg * t).distance_to(c) >= r:
			continue
		# Follow the zone's edge, turning the way that heads toward the goal.
		var tangent := out.normalized().orthogonal()
		if tangent.dot(seg) < 0.0:
			tangent = -tangent
		var push := clampf((r + 40.0 - out.length()) / 40.0, 0.0, 1.0)
		return (tangent + out.normalized() * push).normalized() * desired.length()
	return desired

## AI: an idle ship parked in a spice nebula moves just outside it (the
## nearest edge), since sitting there only costs shields.
func _leave_nebula() -> void:
	for n in Game.instance.nebula_list:
		if n.contains(global_position):
			order_move(n.exit_from(global_position))
			return

## Next point to fly at on the way to `final`, planning a path around debris
## when the straight line is blocked. Straight-line checks run every 0.3 s,
## re-plans at most every 0.5 s (chasing a moving target).
func _route(final: Vector2) -> Vector2:
	var g := Game.instance
	var t := Game.now()
	if t - _direct_time > 0.3 or final.distance_to(_path_final) > 60.0:
		_direct_time = t
		_direct = g.line_clear(global_position, final)
	if _direct:
		_path = PackedVector2Array()
		_path_final = final
		return final
	if _path.is_empty() or (final.distance_to(_path_final) > 60.0 and t - _path_time > 0.5):
		_path = g.find_path(global_position, final)
		_path_final = final
		_path_time = t
	while _path.size() > 1 and global_position.distance_to(_path[0]) < 30.0:
		_path.remove_at(0)
	return _path[0] if not _path.is_empty() else final

## Job effects, in the job's accent color (Defs.JOBS): the Radiation Sail Array's
## screen (a slow shimmer ring), a Tender's green repair beams and
## emergency flash, and an Escort's guard ring while selected.
func _draw_job() -> void:
	var jid: String = def.get("job", "")
	if jid == "":
		return
	var c: Color = Defs.JOBS[jid]["color"]
	var t := Time.get_ticks_msec() / 1000.0
	draw_set_transform(Vector2.ZERO, -global_rotation, Vector2.ONE)
	match jid:
		"radiation_sail":
			_draw_solar_shield(t)
		"field_repair":
			for o in _repairing:
				if is_instance_valid(o):
					var to: Vector2 = (o.global_position - global_position)
					draw_line(Vector2.ZERO, to, Color(c, 0.35 + 0.25 * sin(t * 10.0)), 1.5)
					draw_circle(to, 2.0, Color(c, 0.8))
			if Abilities.is_active(self):
				draw_arc(Vector2.ZERO, Abilities.EMERGENCY_RANGE, 0.0, TAU, 96, Color(c, 0.8), 3.0)
				draw_circle(Vector2.ZERO, Abilities.EMERGENCY_RANGE, Color(c, 0.12))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------------------------------------------------------------- refits

## Can this ship be refitted into variant v? Only generalists that have
## that variant; a specialist is permanent (see Defs.VARIANTS).
func can_refit(v: String) -> bool:
	return not def.has("variant") and Defs.VARIANTS_OF.get(ship_type, []).has(v)

## Fly to a Weapons Depot of variant v (`at` picks one) and refit there.
func order_refit(v: String, at: WeaponsDepot = null) -> void:
	held = false
	if not can_refit(v):
		return
	refit_variant = v
	refit_left = float(def["refit"]["time"])
	refit_depot = at
	state = State.REFIT

## Goes inside a depot: hidden, safe and not a target until the refit is done.
func enter_depot(d: WeaponsDepot) -> void:
	docked = true
	refit_depot = d
	velocity = Vector2.ZERO
	global_position = d.global_position
	visible = false
	selected = false
	Game.instance.selection.erase(self)

## Launches back out of a depot once refitted.
func leave_depot(d: WeaponsDepot) -> void:
	docked = false
	visible = true
	var dir := Vector2.from_angle(randf() * TAU)
	global_position = d.global_position + dir * (d.radius + radius + 10.0)
	move_goal = global_position
	state = State.IDLE

## Turns this ship into another type in place (a finished refit), keeping
## how damaged each layer is.
func _become(new_type: String) -> void:
	var hp_f := hp / max_hp if max_hp > 0.0 else 1.0
	var ar_f := armor / max_armor if max_armor > 0.0 else 1.0
	var sh_f := shield / max_shield if max_shield > 0.0 else 1.0
	ship_type = new_type
	def = Defs.SHIPS[new_type]
	_apply_def_visuals()
	display_name = Game.instance.ship_name(owner_id, ship_type)
	refresh_stats()
	hp = max_hp * hp_f
	armor = max_armor * ar_f
	shield = max_shield * sh_f
	refit_variant = ""
	state = State.IDLE
	move_goal = global_position
	var g := Game.instance
	g.stats.count(owner_id, "refit_" + def["variant"])
	if owner_id == g.player_id:
		g.notify("Refit complete: %s." % def["name"], "note_ship", global_position)
		g.selection_changed.emit()
	queue_redraw()

## Builds a Mining Station on site; the Constructor is used up doing it.
func order_build_station(pos: Vector2) -> void:
	held = false
	if def["role"] != "constructor":
		return
	build_site = pos
	build_kind = "station"
	state = State.BUILD
	move_goal = pos
	target = null

func order_build_depot(pos: Vector2, v: String = "plasma") -> void:
	held = false
	if def["role"] != "constructor":
		return
	build_site = pos
	build_kind = "depot"
	build_variant = v
	state = State.BUILD

# ---------------------------------------------------------------- solar sail

## Is this ship inside a star's radiation or a spice nebula (where a solar
## sail harvests)?
func in_solar_field() -> bool:
	var g := Game.instance
	if g.in_nebula(global_position):
		return true
	for st in g.get_tree().get_nodes_in_group("stars"):
		if st.dps_at(global_position.distance_to(st.global_position), radius) > 0.0:
			return true
	return false

## Radiation Sail Array: harvests def.solar_sail energy a minute while in a
## field. Each point first recharges the solar shield (1 energy = 10% of its maximum),
## with no pause after taking fire - it charges whenever energy comes in;
## once the shield is full the rest goes to the owner's energy pool.
func _solar_tick(delta: float) -> void:
	_solar_fx_tick(delta)
	var was_full := _sail_mode == "full"
	_sail_mode = ""
	if not in_solar_field():
		return
	_mote_timer -= delta
	if _mote_timer <= 0.0:
		_mote_timer = 0.12
		_motes.append({"a": randf() * TAU, "d": 1.0, "life": 0.0, "out": was_full})
	var g := Game.instance
	var gain: float = float(def["solar_sail"]) / 60.0 * delta * g.mod(owner_id, "energy")
	# Each point of energy charges Defs.SAIL_SHIELD_FRAC_PER_ENERGY of the
	# maximum (10%), so shield techs don't slow the refill.
	var per_energy := maxf(max_shield * Defs.SAIL_SHIELD_FRAC_PER_ENERGY, 0.001)
	var into_shield := minf(gain, maxf(max_shield - shield, 0.0) / per_energy)
	if into_shield > 0.0:
		_sail_mode = "charge"
		shield = minf(max_shield, shield + into_shield * per_energy)
		queue_redraw()
	if _sail_mode == "" and gain > 0.0:
		_sail_mode = "full"
	if gain > into_shield:
		g.resources[owner_id]["energy"] += gain - into_shield

## The colour this ship's shield layer is drawn in (a solar sail's is purple).
func shield_color() -> Color:
	return def.get("shield_color", Defs.LAYER_COLORS["shield"])

# ---------------------------------------------------------------- solar shield look
# The Radiation Sail Array's shield, drawn by _draw_job in world-aligned
# space: a large shimmering bubble (Defs.SAIL_RADIUS, nearly two carriers wide) that
#  - ripples gently at the edge,
#  - pulls in purple motes while it harvests,
#  - ripples out from where a shot lands,
#  - flickers and thins below SAIL_LOW charge,
#  - shatters at 0 and grows back out as it recharges.

const SAIL_LOW := 0.25
const SAIL_REFORM := 1.0
var _motes: Array = []
var _mote_timer := 0.0
var _sail_hits: Array = []
var _sail_shards: Array = []
## What the array is doing this frame: "charge" (filling its shield), "full"
## (shield full, energy to the stockpile) or "" (idle) - drives the arcs.
var _sail_mode := ""
var _sail_reform := 1.0
var _sail_was_up := false

func _sail_radius() -> float:
	return Defs.SAIL_RADIUS

func _solar_hit(from: SpaceEntity, before: float) -> void:
	var a: float = (from.global_position - global_position).angle() if is_instance_valid(from) else randf() * TAU
	_sail_hits.append({"a": a, "t": 0.0})
	if before > 0.0 and shield <= 0.0:
		# Shatter: fragments of the bubble fly outward and fade.
		for i in 14:
			var aa := TAU * i / 14.0 + randf_range(-0.1, 0.1)
			_sail_shards.append({"a": aa, "r": _sail_radius(), "v": randf_range(30.0, 70.0), "t": 0.0})

func _solar_fx_tick(delta: float) -> void:
	for m in _motes:
		m["life"] += delta
		m["d"] = maxf(0.0, m["d"] - delta * 1.4)
	_motes = _motes.filter(func(m): return m["d"] > 0.0)
	for h in _sail_hits:
		h["t"] += delta
	_sail_hits = _sail_hits.filter(func(h): return h["t"] < 0.7)
	for s in _sail_shards:
		s["t"] += delta
		s["r"] += s["v"] * delta
	_sail_shards = _sail_shards.filter(func(s): return s["t"] < 0.9)
	# Growing back out after a break.
	var up := shield > 0.0
	if up and not _sail_was_up:
		_sail_reform = 0.0
	_sail_was_up = up
	_sail_reform = minf(1.0, _sail_reform + delta / SAIL_REFORM)
	queue_redraw()

func _draw_solar_shield(t: float) -> void:
	var sc := shield_color()
	var R := _sail_radius()
	# Motes drifting in from the field, fading as they soak in.
	for m in _motes:
		# Charging they drift in; once full, energy streams back out to the
		# stockpile in the arcs' white/yellow.
		var out: bool = m.get("out", false)
		var p: Vector2 = Vector2.from_angle(m["a"]) * R * (1.0 + 1.6 * ((1.0 - m["d"]) if out else m["d"]))
		if out:
			draw_circle(p, 2.6, Color(Color("ffe066"), 0.35 * m["d"]))
		draw_circle(p, 1.6, Color(Color("fff6cc"), 0.85 * m["d"]) if out else Color(sc, 0.25 + 0.55 * (1.0 - m["d"])))
	# Shards of a broken bubble.
	for s in _sail_shards:
		var k: float = 1.0 - s["t"] / 0.9
		draw_arc(Vector2.ZERO, s["r"], s["a"] - 0.18, s["a"] + 0.18, 4, Color(sc, 0.8 * k), 2.0)
	if max_shield <= 0.0 or shield <= 0.0:
		return
	var f := shield / max_shield
	var grow := 0.55 + 0.45 * ease(_sail_reform, 0.4)
	var r0 := R * grow
	var alpha := 0.35 + 0.45 * f
	var width := 2.0
	if f < SAIL_LOW:
		# Running low: the edge thins (no flicker).
		width = 1.2
	# Shimmering edge: a soft wobble around the circle. Where an allied
	# array's bubble overlaps this one, the edge inside it is left out, so
	# touching bubbles merge into one mega shield with a single outer wall.
	var others: Array = []
	for o in Abilities.sail_cluster(self):
		if o != self:
			others.append(o.global_position - global_position)
	var edge := func(a: float) -> Vector2:
		return Vector2.from_angle(a) * (r0 + 1.4 * sin(a * 5.0 + t * 2.2) + 0.9 * sin(a * 9.0 - t * 3.1))
	var inside := func(p: Vector2) -> bool:
		for q in others:
			if p.distance_to(q) < R:
				return true
		return false
	var seg := PackedVector2Array()
	var n := 96
	var was_hidden := false
	for i in n + 1:
		var a := TAU * i / n
		var p: Vector2 = edge.call(a)
		var hidden: bool = inside.call(p)
		if i > 0 and hidden != was_hidden:
			# Find where the wall meets the neighbour's, so the seam closes.
			var lo := TAU * (i - 1) / n
			var hi := a
			for _k in 8:
				var mid := (lo + hi) * 0.5
				if inside.call(edge.call(mid)) == was_hidden:
					lo = mid
				else:
					hi = mid
			seg.append(edge.call((lo + hi) * 0.5))
		was_hidden = hidden
		if not hidden:
			seg.append(p)
		if (hidden or i == n) and seg.size() > 1:
			draw_polyline(seg, Color(sc, alpha), width, true)
			draw_polyline(seg, Color(sc.lightened(0.5), alpha * 0.35), width + 3.0, true)
		if hidden:
			seg = PackedVector2Array()
	# Impact ripples: a bright flare at the hit that spreads along the edge.
	for h in _sail_hits:
		var k: float = h["t"] / 0.7
		var spread := 0.15 + 1.4 * k
		draw_arc(Vector2.ZERO, r0, h["a"] - spread, h["a"] + spread, 18, Color(sc.lightened(0.6), 0.9 * (1.0 - k)), 3.0 * (1.0 - k) + 1.0)
		draw_circle(Vector2.from_angle(h["a"]) * r0, 4.0 * (1.0 - k) + 1.0, Color(Color.WHITE, 0.7 * (1.0 - k)))
	_draw_sail_arcs(r0)

## Electrical arcs between the hull and the bubble while the array works:
## white/purple while charging the shield, white/yellow once it is full and
## the energy flows to the stockpile. One strike every 0-3 seconds (sometimes two in quick succession), fading
## out over SAIL_ARC_LIFE like a lightning flash: a sudden bright snap that
## dies away, along a jagged path with a fork, different every strike.
const SAIL_ARC_LIFE := 0.3
var _arc_next := 0.0
var _arc_at := -10.0
var _arc_angles: Array = []

func _draw_sail_arcs(r0: float) -> void:
	var t := Game.now()
	if _sail_mode != "" and t >= _arc_next:
		_arc_at = t
		_arc_next = t + randf_range(0.12, 3.0)
		_arc_angles = []
		for i in randi_range(1, 3):
			var kinks: Array = []
			for j in 11:
				kinks.append(randf_range(-0.1, 0.1))
			_arc_angles.append({"a": randf() * TAU, "kinks": kinks, "fork": randi_range(3, 6), "fork_dir": [-1.0, 1.0].pick_random()})
	var age := t - _arc_at
	if age > SAIL_ARC_LIFE:
		return
	var fade := pow(1.0 - age / SAIL_ARC_LIFE, 2.0)
	var glow: Color = shield_color() if _sail_mode != "full" else Color("ffe066")
	for i in _arc_angles.size():
		var s: Dictionary = _arc_angles[i]
		var a: float = s["a"]
		var pts := PackedVector2Array()
		var steps := 10
		for j in steps + 1:
			var k := float(j) / steps
			var r := lerpf(10.0, r0, k)
			var jit: float = 0.0 if j == 0 or j == steps else s["kinks"][j]
			pts.append(Vector2.from_angle(a + jit) * r)
		draw_polyline(pts, Color(glow, 0.45 * fade), 4.0, true)
		draw_polyline(pts, Color(Color.WHITE, 0.9 * fade), 1.4, true)
		draw_circle(pts[steps], 2.5, Color(glow, 0.8 * fade))
		# A short fork splitting off partway out.
		var fi: int = s["fork"]
		var fork := PackedVector2Array([pts[fi]])
		var fa: float = a + s["kinks"][fi] + 0.25 * s["fork_dir"]
		for j in 3:
			fork.append(pts[fi] + Vector2.from_angle(fa + s["kinks"][j + 1] * 3.0) * (r0 * 0.09 * (j + 1)))
		draw_polyline(fork, Color(glow, 0.35 * fade), 3.0, true)
		draw_polyline(fork, Color(Color.WHITE, 0.7 * fade), 1.0, true)
