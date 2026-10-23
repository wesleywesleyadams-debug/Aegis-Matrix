class_name Projectile
extends Sprite2D
## Laser bolt or torpedo. Flies toward its target (torpedoes home) and
## applies damage on contact; lasers that lose their target fizzle out.

var shooter: Node2D
var target: Node2D # a SpaceEntity or a Planet being bombarded
var damage: float
## Damage vs defense layers (Defs.damage_profile of the shooter).
var profile: Dictionary = {}
## Disruptor shots (skip shields, hit armor and hull) are orange.
const DISRUPTOR_SHOT := Color("ff7a14")
var speed: float
var homing: bool
var weak_lock := false
## Homing shots: the fastest their heading can swing, radians per second.
const TURN_MISSILE := 2.5
const TURN_TORPEDO := 1.6
const TURN_WEAK := 0.9    # Proton Torpedoes steer gently
var turn_rate := 0.0
## Damage multipliers by target class (Defs.MOD_WEAPONS "vs_class").
var vs_class := {}
var life: float = 3.0
var _vel: Vector2

## Flak: burst share and radius; bomblet: unguided, bursts on the first enemy
## it touches (it passes through friendly hulls).
var splash := 0.0
var splash_r := 0.0
var free_flight := false
var owner_pid := 0
## Missiles and torpedoes leave a fading exhaust trail (world points).
var trail_on := false
## Torpedo wakes are short, wide and blue-white; missile trails long, thin, orange.
var torp_wake := false
var _trail: PackedVector2Array = []

## Dev duel stats: per side, shots launched and shots that expired with
## their target already gone (overkill).
static var fired := {}
static var fizzled := {}

## Overkill Awareness: damage this shot has booked against its target in
## Game's in-flight registry (taken back off exactly once: hit, expiry or free).
var _booked := 0.0
var _booked_tid := 0

func _unbook() -> void:
	if _booked > 0.0 and Game.instance:
		Game.instance.inflight_sub(owner_pid, _booked_tid, _booked)
	_booked = 0.0

func _exit_tree() -> void:
	_unbook()

## Target Prediction's lead: where `to` will have moved by the time a shot
## from `src` at `spd` arrives. Ships are led on their smoothed velocity
## (Ship.lead_vel); a ship braking hard is assumed to stop rather than keep
## going, and one coming mostly straight at the shooter (which tends to
## brake or break off at firing range) is led less.
static func lead_offset(to: Node2D, src: Vector2, spd: float) -> Vector2:
	var v: Vector2 = to.get("velocity")
	var acc := Vector2.ZERO
	if to is Ship:
		v = (to as Ship).lead_vel
		acc = (to as Ship).lead_acc
	var sp := v.length()
	if sp < 1.0:
		return Vector2.ZERO
	var t := src.distance_to(to.global_position) / spd
	var vd := v / sp
	# Deceleration along the direction of travel: the ship covers v*t - a*t^2/2
	# but never backs up past where it would stop.
	var dec := maxf(0.0, -acc.dot(vd))
	var travel := sp * t
	if dec > 1.0:
		var t_stop := sp / dec
		travel = sp * minf(t, t_stop) - 0.5 * dec * minf(t, t_stop) * minf(t, t_stop)
	var off := v * (travel / sp)
	# Split into the part along the line to the shooter and the part across
	# it (only the crossing part really moves the aim point off the target).
	var dist := src.distance_to(to.global_position)
	var n := (src - to.global_position) / maxf(dist, 1.0)
	var along := n * off.dot(n)
	var across := off - along
	var closing := maxf(0.0, vd.dot(n))
	if closing > 0.3 and to is Ship and (to as Ship).weapon_range() > 0.0:
		# A warship charging the shooter stops once in its own weapon range:
		# it is led in only as far as it has left to come, and while still
		# on the run-in (rarely straight) its sideways drift is led less.
		var left := maxf(0.0, dist - (to as Ship).weapon_range())
		if off.dot(n) > 0.0:
			along = along.limit_length(left)
		if left > 0.0:
			across *= 1.0 - 0.67 * closing
	return along + across

func setup(from: Node2D, to: Node2D, weapon: String, dmg: float, spread: float = 0.0, origin: Vector2 = Vector2.INF) -> void:
	var src: Vector2 = from.global_position if origin == Vector2.INF else origin
	shooter = from
	target = to
	damage = dmg
	homing = weapon == "torpedo" or weapon == "proton" or weapon == "missile"
	owner_pid = int(from.get("owner_id"))
	free_flight = weapon == "bomblet"
	# Ordnance Point-Defense can shoot down.
	if weapon in ["missile", "proton", "torpedo", "bomblet"]:
		add_to_group("ordnance")
	# Evasive warships watch for slow shots aimed at them.
	var jink_at: Ship = null
	if to is Ship and (to as Ship).engagement == Ship.Engage.EVASIVE:
		if weapon in Ship.DODGE_WEAPONS:
			(to as Ship).incoming.append(self)
		elif weapon in Ship.JINK_WEAPONS:
			jink_at = to as Ship
	trail_on = weapon in ["missile", "proton", "torpedo"] and not Game.instance.sim_mode
	torp_wake = weapon in ["proton", "torpedo"]
	if Defs.AOE_RADIUS.has(weapon):
		splash = Defs.AOE_SHARE
		splash_r = Defs.AOE_RADIUS[weapon]
	# Proton Torpedoes steer only gently and give up once the target is well
	# off their nose: a target that turns hard can shake them off.
	weak_lock = weapon == "proton"
	turn_rate = TURN_WEAK if weak_lock else (TURN_MISSILE if weapon == "missile" else TURN_TORPEDO)
	if from is Ship:
		vs_class = from.weapon_mod.get("vs_class", {})
	# Kinetic Repeater slugs: fast and small.
	speed = (110.0 if weak_lock else (150.0 if weapon == "missile" else 85.0)) if homing else {"kinetic": 320.0, "bomblet": 150.0, "flak": 240.0, "rail": 900.0}.get(weapon, 210.0)
	# Misses expire just past weapon range instead of crossing the map.
	var reach: float = src.distance_to(to.global_position) + 60.0
	life = minf(life, reach / speed * (2.0 if homing else 1.0))
	texture = Defs.tex("bolt_" + {"kinetic": "laser", "flak": "laser", "rail": "laser", "proton": "torpedo", "missile": "torpedo", "bomblet": "torpedo"}.get(weapon, weapon))
	# Bolt art is drawn at Defs.ART_SCALE like the rest of the sprites.
	scale = Vector2.ONE / Defs.ART_SCALE * {"kinetic": 0.55, "bomblet": 0.5, "missile": 0.6}.get(weapon, 1.0)
	if weapon == "missile":
		scale = Vector2(0.9, 0.35) / Defs.ART_SCALE   # long and slim: a missile body
	elif weapon == "rail":
		scale = Vector2(2.4, 0.3) / Defs.ART_SCALE   # a long thin streak
	elif weapon == "proton":
		scale = Vector2.ONE * 1.25 / Defs.ART_SCALE   # a fat, glowing ball
	# Point-Defense Lattice: sliver-thin, needle-long lasers.
	if from is Ship and from.weapon_mod.has("pd"):
		scale = Vector2(3.2, 0.16) / Defs.ART_SCALE
	# Shot colors: generalists (and starbases) fire yellow; specialists fire
	# their variant's color (the layer they hit hardest: light blue shields,
	# red armor, green hull).
	modulate = Defs.GENERALIST_SHOT
	if from is Ship:
		profile = Defs.damage_profile(from.def)
		if from.def.has("variant"):
			modulate = Defs.VARIANTS[from.def["variant"]]["color"].lightened(0.15)
			# Shots that bypass layers are colored by the layers they do hit:
			# Disruptor (hull only) is orange, its lasers V-shaped; torpedoes stay
			# round. Scrambler keeps its own purple.
			if profile["pierce"] > 0:
				if weapon == "laser":
					texture = Defs.tex("bolt_v")
				modulate = DISRUPTOR_SHOT
	global_position = src
	# Target Prediction: aim where a moving target will be when the shot gets
	# there; without it, at where it is now. Guided shots steer for
	# themselves and launch straight at the target: led far ahead, a slow
	# torpedo would start beyond its lock cone and fly off the wrong way.
	var lead := to.global_position
	if not homing and Game.instance.has_tech(owner_pid, "target_prediction") and to.get("velocity") is Vector2:
		lead += lead_offset(to, src, speed)
	_vel = (lead - global_position).normalized().rotated(spread) * speed
	# Evasive warships start jinking when fast rounds come at them.
	if jink_at != null:
		jink_at.note_fast_shot(self)
	rotation = _vel.angle()
	if DuelStats.on:
		DuelStats.launched(self, from, to)
	fired[owner_pid] = int(fired.get(owner_pid, 0)) + 1
	if free_flight:
		life = src.distance_to(to.global_position) * 1.3 / speed
	# Book the shot against its target so other guns of this side can see it
	# is already covered (Game.is_doomed). Area shots are left out.
	elif splash <= 0.0 and Game.instance.has_tech(owner_pid, "overkill_awareness"):
		_booked = damage * Game.vs_mult(vs_class, to)
		_booked_tid = to.get_instance_id()
		Game.instance.inflight_add(owner_pid, to, _booked)

func _physics_process(delta: float) -> void:
	if trail_on:
		_trail.append(global_position)
		if _trail.size() > (7 if torp_wake else 14):
			_trail.remove_at(0)
		queue_redraw()
	life -= delta
	if life <= 0.0:
		_unbook()
		if DuelStats.on:
			DuelStats.expired(self, is_instance_valid(target) and target.is_alive())
		if not free_flight and not (is_instance_valid(target) and target.has_method("is_alive") and target.is_alive()):
			fizzled[owner_pid] = int(fizzled.get(owner_pid, 0)) + 1
		queue_free()
		return
	if free_flight:
		# Unguided bomblet: bursts on the first ship in its path.
		var nxt := global_position + _vel * delta
		for x in Game.instance.hulls_near(global_position.lerp(nxt, 0.5), _vel.length() * delta + 6.0):
			# Flies straight through its own side and allies; only an enemy sets it off.
			if x == shooter or x.owner_id == owner_pid or not x.is_enemy_of(owner_pid):
				continue
			if Geometry2D.get_closest_point_to_segment(x.global_position, global_position, nxt).distance_to(x.global_position) <= x.radius:
				# Bursts on the first enemy it touches; the blast hurts enemies only.
				Game.instance.splash(x.global_position, splash_r, damage * splash, owner_pid, shooter if is_instance_valid(shooter) else null, profile, vs_class)
				queue_free()
				return
		# ...or on an enemy world, depot or Mining Station it falls onto (forts
		# are in hulls_near above).
		for w in get_tree().get_nodes_in_group("planets") + get_tree().get_nodes_in_group("depots") + get_tree().get_nodes_in_group("mining_stations"):
			if w.owner_id != owner_pid and w.is_enemy_of(owner_pid) and Geometry2D.get_closest_point_to_segment(w.global_position, global_position, nxt).distance_to(w.global_position) <= w.radius:
				Game.instance.splash(global_position, splash_r, damage * splash, owner_pid, shooter if is_instance_valid(shooter) else null, profile, vs_class)
				queue_free()
				return
		global_position = nxt
		# Bomblets blink as they fall, so a spread reads as bombs, not shots.
		visible = int(life * 12.0) % 2 == 0
		return
	if is_instance_valid(target) and target.is_alive():
		if homing:
			var to_t := target.global_position - global_position
			if weak_lock and absf(_vel.angle_to(to_t)) > deg_to_rad(50.0):
				homing = false   # lost the lock: flies on straight and may miss
			else:
				# A real turn limit: the heading swings at most turn_rate per
				# second, at full speed, so a target that moves hard enough
				# and late enough can slip out of its turn.
				var ang := _vel.angle_to(to_t)
				var step := turn_rate * delta
				_vel = _vel.rotated(clampf(ang, -step, step))
				rotation = _vel.angle()
		# Sweep the whole step against the target, not just the end point: at
		# high game speeds a bolt covers more ground per tick than the target
		# is wide, and a point test would fly straight through it.
		var next_pos := global_position + _vel * delta
		var near := Geometry2D.get_closest_point_to_segment(target.global_position, global_position, next_pos)
		if near.distance_to(target.global_position) <= target.radius:
			if splash > 0.0:
				Game.instance.splash(near, splash_r, damage * splash, owner_pid, shooter if is_instance_valid(shooter) else null, profile, vs_class)
				queue_free()
				return
			var hit := damage
			hit *= Game.vs_mult(vs_class, target)
			if DuelStats.on:
				DuelStats.hit(self, hit, target.hp + target.armor + target.shield)
			_unbook()
			target.take_damage(hit, shooter if is_instance_valid(shooter) and shooter is SpaceEntity else null, profile)
			if homing:
				Game.instance.spawn_explosion(near, 0.4)
			queue_free()
			return
	global_position += _vel * delta

## The exhaust trail, drawn in the projectile's own (rotated, scaled) space.
func _draw() -> void:
	if not trail_on or _trail.size() < 2:
		return
	var inv := global_transform.affine_inverse()
	for k in range(1, _trail.size()):
		var a: float = float(k) / _trail.size()
		if torp_wake:
			# A short, wide, glowing wake.
			draw_line(inv * _trail[k - 1], inv * _trail[k], Color(0.55, 0.85, 1.0, a * 0.35), 9.0 * a / scale.x)
			draw_line(inv * _trail[k - 1], inv * _trail[k], Color(0.9, 0.97, 1.0, a * 0.7), 3.0 * a / scale.x)
		else:
			draw_line(inv * _trail[k - 1], inv * _trail[k], Color(1.0, 0.75, 0.4, a * 0.55), 3.0 * a / scale.x)
