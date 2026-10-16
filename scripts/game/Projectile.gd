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
const SLIP_SHOT := Color("ffa43a")
var speed: float
var homing: bool
var life: float = 3.0
var _vel: Vector2

func setup(from: Node2D, to: Node2D, weapon: String, dmg: float) -> void:
	shooter = from
	target = to
	damage = dmg
	homing = weapon == "torpedo"
	speed = 170.0 if homing else 420.0
	# Misses expire just past weapon range instead of crossing the map.
	var reach: float = from.global_position.distance_to(to.global_position) + 60.0
	life = minf(life, reach / speed * (2.0 if homing else 1.0))
	texture = Defs.tex("bolt_" + weapon)
	# Bolt art is drawn at Defs.ART_SCALE like the rest of the sprites.
	scale = Vector2.ONE / Defs.ART_SCALE
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
					# Purple, so it is never mistaken for a Reaver's green.
					modulate = Defs.VARIANTS["disruptor"]["color"].lightened(0.1)
				else:
					modulate = SLIP_SHOT
	global_position = from.global_position
	var lead := to.global_position
	if to is Ship:
		lead += (to as Ship).velocity * (from.global_position.distance_to(to.global_position) / speed)
	_vel = (lead - global_position).normalized() * speed
	rotation = _vel.angle()

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if is_instance_valid(target) and target.is_alive():
		if homing:
			var want := (target.global_position - global_position).normalized() * speed
			_vel = _vel.move_toward(want, speed * 3.0 * delta)
			rotation = _vel.angle()
		# Sweep the whole step against the target, not just the end point: at
		# high game speeds a bolt covers more ground per tick than the target
		# is wide, and a point test would fly straight through it.
		var next_pos := global_position + _vel * delta
		var near := Geometry2D.get_closest_point_to_segment(target.global_position, global_position, next_pos)
		if near.distance_to(target.global_position) <= target.radius:
			target.take_damage(damage, shooter if is_instance_valid(shooter) else null, profile)
			if homing:
				Game.instance.spawn_explosion(near, 0.4)
			queue_free()
			return
	global_position += _vel * delta
