class_name Drone
extends SpaceEntity
## An Interceptor Drone (carrier Mod): a tiny craft the carrier flies and
## fires for (Ship._fly_drones). It can be targeted and shot down like a
## ship, but is not a ship: no selection, orders, score or upkeep. The
## carrier builds a replacement for each one lost (Defs.DRONE_REBUILD).

const HULL := 60.0   # all hull: no shields or armor, and no marks or tech change it

var carrier: Node2D = null
var tgt: Node2D = null
var cd := 0.0
var _shot_from := Vector2.ZERO
var _shot_to := Vector2.ZERO
var _shot_at := -10.0
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

func shot(to: Vector2) -> void:
	_shot_from = global_position
	_shot_to = to
	_shot_at = Game.now()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var aim: Vector2 = tgt.global_position if is_instance_valid(tgt) else (carrier.global_position if is_instance_valid(carrier) else global_position + Vector2.RIGHT)
	draw_set_transform(Vector2.ZERO, (aim - global_position).angle() - global_rotation)
	draw_colored_polygon(PackedVector2Array([Vector2(5, 0), Vector2(-4, -4), Vector2(-2, 0), Vector2(-4, 4)]), Color("c8d2ea"))
	draw_colored_polygon(PackedVector2Array([Vector2(-2, -2), Vector2(-2, 2), Vector2(-4, 0)]), Defs.team_color(owner_id))
	draw_set_transform(Vector2.ZERO)
	if hp < max_hp:
		draw_line(Vector2(-5, -8), Vector2(-5 + 10.0 * hp / max_hp, -8), Color("4ade80"), 1.5)
	if Game.now() - _shot_at < 0.08:
		draw_line(to_local(_shot_from), to_local(_shot_to), Color("ffd84a"), 1.5)
