class_name Projectile
extends Sprite2D
## Laser bolt or torpedo. Flies toward its target (torpedoes home) and
## applies damage on contact; lasers that lose their target fizzle out.

var shooter: Node2D
var target: Node2D # a SpaceEntity or a Planet being bombarded
var damage: float
## Damage vs defense layers (Defs.damage_profile of the shooter).
var profile: Dictionary = {}
## Slip shots (skip shields, hit armor and hull) are orange.
const SLIP_SHOT := Color("ff7a14")
var speed: float
var homing: bool
var weak_lock := false
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

func setup(from: Node2D, to: Node2D, weapon: String, dmg: float, spread: float = 0.0) -> void:
	shooter = from
	target = to
	damage = dmg
	homing = weapon == "torpedo" or weapon == "proton" or weapon == "missile"
	owner_pid = int(from.get("owner_id"))
	free_flight = weapon == "bomblet"
	# Ordnance Point-Defense can shoot down.
	if weapon in ["missile", "proton", "torpedo", "bomblet"]:
		add_to_group("ordnance")
	trail_on = weapon in ["missile", "proton", "torpedo"] and not Game.instance.sim_mode
	torp_wake = weapon in ["proton", "torpedo"]
	if Defs.AOE_RADIUS.has(weapon):
		splash = Defs.AOE_SHARE
		splash_r = Defs.AOE_RADIUS[weapon]
	# Proton Torpedoes steer only gently and give up once the target is well
	# off their nose: a target that turns hard can shake them off.
	weak_lock = weapon == "proton"
	if from is Ship:
		vs_class = from.weapon_mod.get("vs_class", {})
	# Kinetic Repeater slugs: fast and small.
	speed = (110.0 if weak_lock else (150.0 if weapon == "missile" else 85.0)) if homing else {"kinetic": 320.0, "bomblet": 150.0, "flak": 240.0, "rail": 900.0}.get(weapon, 210.0)
	# Misses expire just past weapon range instead of crossing the map.
	var reach: float = from.global_position.distance_to(to.global_position) + 60.0
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
	# Shot colors: generalists (and starbases) fire yellow; specialists fire
	# their variant's color (the layer they hit hardest: light blue shields,
	# red armor, green hull).
	modulate = Defs.GENERALIST_SHOT
	if from is Ship:
		profile = Defs.damage_profile(from.def)
		if from.def.has("variant"):
			modulate = Defs.VARIANTS[from.def["variant"]]["color"].lightened(0.15)
			# Shots that bypass layers are colored by the layers they do hit:
			# Slip (armor + hull) is orange, Disruptor (hull only) is purple. Their lasers are V-shaped; torpedoes stay round.
			if profile["pierce"] > 0:
				if weapon == "laser":
					texture = Defs.tex("bolt_v")
				if profile["pierce"] >= 2:
					# Purple, so it is never mistaken for a Ravager's green.
					modulate = Defs.VARIANTS["disruptor"]["color"].lightened(0.1)
				else:
					modulate = SLIP_SHOT
	global_position = from.global_position
	# Target Prediction: aim where a moving target will be when the shot gets
	# there; without it, at where it is now. Guided shots steer for
	# themselves and launch straight at the target: led far ahead, a slow
	# torpedo would start beyond its lock cone and fly off the wrong way.
	var lead := to.global_position
	if not homing and Game.instance.has_tech(owner_pid, "target_prediction") and to.get("velocity") is Vector2:
		lead += to.get("velocity") * (from.global_position.distance_to(to.global_position) / speed)
	_vel = (lead - global_position).normalized().rotated(spread) * speed
	rotation = _vel.angle()
	if free_flight:
		life = from.global_position.distance_to(to.global_position) * 1.3 / speed

func _physics_process(delta: float) -> void:
	if trail_on:
		_trail.append(global_position)
		if _trail.size() > (7 if torp_wake else 14):
			_trail.remove_at(0)
		queue_redraw()
	life -= delta
	if life <= 0.0:
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
				var want := to_t.normalized() * speed
				_vel = _vel.move_toward(want, speed * (0.9 if weak_lock else 3.0) * delta)
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
			if not vs_class.is_empty() and target is Ship:
				hit *= float(vs_class.get(str(target.def.get("base", target.ship_type)), 1.0))
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
