class_name Drone
extends SpaceEntity
## An Interceptor Drone (carrier Mod): a tiny craft the carrier flies and
## fires for (Ship._fly_drones). It can be targeted and shot down like a
## ship, but is not a ship: no selection, orders, score or upkeep. The
## carrier builds a replacement for each one lost (Defs.DRONE_REBUILD).

const HULL := 60.0   # all hull: no shields or armor, and no marks or tech change it

const SPEED := 240.0
## Patrol: drones circle the carrier at the edge of their reach this fast
## (radians a second), spread evenly by slot.
const ORBIT_SPEED := 0.25
## How far past their reach drones look for prey to engage.
const SEARCH := 60.0
## Distance a drone holds from its target while firing.
const STANDOFF := 40.0
const FIRE_REACH := 90.0
## Drones fly nose-first: they turn at most this fast (radians a second) and
## fire only straight ahead, at a target within FIRE_CONE of the nose, so
## they make attack passes rather than hovering.
const TURN := 4.0
const FIRE_CONE := 0.25
var heading := 0.0

var carrier: Ship = null
var slot := 0
var tgt: Node2D = null
var _scan := 0.0
var cd := 0.0
var _shot_from := Vector2.ZERO
var _shot_to := Vector2.ZERO
var _shot_at := -10.0
var _spark_seed := 0.0
## For code that reads a ship's def (target scoring treats it as a non-warship).
var def := {"role": "drone"}

func _init() -> void:
	max_hp = HULL
	hp = HULL
	radius = 5.0
	display_name = "Interceptor Drone"

## Not in "entities": selection, saves and the neural AI never see drones.
func _ready() -> void:
	add_to_group("drones")
	z_index = 5

func _worth() -> float:
	return 0.0

func _die() -> void:
	_dead = true
	Game.instance.spawn_explosion(global_position, 0.4)
	died.emit(self)
	queue_free()

## Its own agent: it engages the enemy nearest to itself within the
## carrier's drone reach and sticks with it; with none, it patrols slowly
## round the edge of that reach, looking.
## A drone never strays past its reach from the carrier.
func _physics_process(delta: float) -> void:
	if _dead or not is_instance_valid(carrier) or not carrier.is_alive():
		return
	var g := Game.instance
	var sf: float = g.ship_speed_factor(owner_id)
	var reach: float = carrier.drone_reach()
	var home: Vector2 = carrier.global_position
	# Each drone picks its own fight: it stays on its target while that is
	# still alive and in reach, and otherwise keeps looking for the enemy
	# nearest to itself within the carrier's reach.
	if not _ok(tgt, home, reach):
		tgt = null
		_scan -= delta
		if _scan <= 0.0:
			_scan = 0.2
			var best_d := INF
			for e in g.enemies_near(self, reach * 2.0 + SEARCH, 8):
				if _ok(e, home, reach):
					var d := global_position.distance_to(e.global_position)
					if d < best_d:
						best_d = d
						tgt = e
	var goal: Vector2
	if tgt != null:
		goal = tgt.global_position   # fly at it; the turn limit makes passes
	else:
		var a := Game.now() * ORBIT_SPEED + TAU * slot / 4.0
		goal = home + Vector2.from_angle(a) * reach
	# Stay inside the leash: past it, turn for home.
	if global_position.distance_to(home) > reach:
		goal = home
	heading = rotate_toward(heading, (goal - global_position).angle(), TURN * delta * sf)
	global_position += Vector2.from_angle(heading) * SPEED * delta * sf
	rotation = heading
	cd -= delta * sf
	if tgt != null and cd <= 0.0:
		var to := tgt.global_position - global_position
		if to.length() <= tgt.radius + FIRE_REACH and absf(angle_difference(heading, to.angle())) <= FIRE_CONE:
			cd = carrier.drone_cooldown() * randf_range(0.9, 1.1)
			carrier.drone_hit(tgt)
			# The bolt runs straight ahead from the nose to the target's range.
			shot(global_position + Vector2.from_angle(heading) * maxf(to.length() - tgt.radius * 0.5, 4.0))

## Whether `e` is a live enemy close enough to the carrier to chase.
func _ok(e, home: Vector2, reach: float) -> bool:
	return is_instance_valid(e) and e.is_alive() and home.distance_to(e.global_position) <= reach + e.radius + SEARCH

func shot(to: Vector2) -> void:
	_shot_from = global_position
	_shot_to = to
	_shot_at = Game.now()
	_spark_seed = randf() * TAU

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(5, 0), Vector2(-4, -4), Vector2(-2, 0), Vector2(-4, 4)]), Color("c8d2ea"))
	draw_colored_polygon(PackedVector2Array([Vector2(-2, -2), Vector2(-2, 2), Vector2(-4, 0)]), Defs.team_color(owner_id))
	if hp < max_hp:
		draw_set_transform(Vector2.ZERO, -rotation)
		draw_line(Vector2(-5, -8), Vector2(-5 + 10.0 * hp / max_hp, -8), Color("4ade80"), 1.5)
		draw_set_transform(Vector2.ZERO)
	# A thin, quick tracer and a tiny spark where it lands.
	var age := Game.now() - _shot_at
	if age < 0.06:
		draw_line(to_local(_shot_from), to_local(_shot_to), Color(1.0, 0.9, 0.5, 0.7), 0.8)
	if age < 0.15:
		var hit := to_local(_shot_to)
		var k := 1.0 - age / 0.15
		for j in 4:
			var v := Vector2.from_angle(_spark_seed + j * 1.7) * (1.5 + 3.0 * (1.0 - k))
			draw_line(hit + v * 0.4, hit + v, Color(1.0, 0.85, 0.4, k), 0.7)
