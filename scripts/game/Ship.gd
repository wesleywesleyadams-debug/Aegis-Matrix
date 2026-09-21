@tool
class_name Ship
extends SpaceEntity
## A single ship. Stats come from Defs.SHIPS[ship_type]; sprites are
## assets/pixel/ship_<type>.png plus a team-tinted overlay layer.

enum State { IDLE, MOVE, ATTACK, ATTACK_MOVE, MINE_GO, MINING, RETURN }

@export_enum("miner", "corvette", "destroyer", "cruiser") var ship_type: String = "corvette":
	set(v):
		ship_type = v
		if is_node_ready():
			_apply_visuals()

var def: Dictionary
var state: State = State.IDLE
var velocity: Vector2 = Vector2.ZERO
var move_goal: Vector2
var attack_move_goal: Vector2
var target: SpaceEntity
var mine_target: Asteroid
var cargo: int = 0

var _cooldown: float = 0.0
var _mine_timer: float = 0.0
var _acquire_timer: float = 0.0
var _flame_timer: float = 0.0

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
	display_name = def["name"]
	max_hp = def["hp"]
	hp = max_hp
	max_shield = def["shield"]
	shield = max_shield
	radius = def["radius"]
	move_goal = global_position
	_acquire_timer = randf() * 0.3

func _apply_visuals() -> void:
	if not is_node_ready() and not has_node("Hull"):
		return
	var hull: Sprite2D = get_node("Hull")
	var team: Sprite2D = get_node("Team")
	var flame: Sprite2D = get_node("Flame")
	hull.texture = Defs.tex("ship_" + ship_type)
	team.texture = Defs.tex("ship_" + ship_type + "_team")
	team.modulate = Defs.team_color(owner_id)
	# Flame sits just behind the stern.
	flame.position = Vector2(-hull.texture.get_width() / 2.0 - 2.0, 0)

func is_miner() -> bool:
	return def.get("role", "") == "miner"

# ---------------------------------------------------------------- orders

func order_move(pos: Vector2) -> void:
	state = State.MOVE
	move_goal = pos
	target = null

func order_attack_move(pos: Vector2) -> void:
	if is_miner():
		order_move(pos)
		return
	state = State.ATTACK_MOVE
	attack_move_goal = pos
	move_goal = pos
	target = null

func order_attack(e: SpaceEntity) -> void:
	if is_miner():
		return
	state = State.ATTACK
	target = e

func order_mine(a: Asteroid) -> void:
	if not is_miner():
		order_move(a.global_position)
		return
	mine_target = a
	state = State.RETURN if cargo >= def["cargo"] else State.MINE_GO

func order_return() -> void:
	if is_miner() and cargo > 0:
		state = State.RETURN

func order_stop() -> void:
	state = State.IDLE
	target = null
	move_goal = global_position

# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_regen_shields(delta)
	_cooldown -= delta
	_acquire_timer -= delta

	var desired := Vector2.ZERO
	var face_target: SpaceEntity = null

	match state:
		State.IDLE:
			if not is_miner() and _acquire_timer <= 0.0:
				var e := Game.instance.nearest_enemy(self, def["range"] + 60.0)
				if e:
					attack_move_goal = global_position
					target = e
					state = State.ATTACK
			desired = _arrive(move_goal, 0.0)
		State.MOVE:
			desired = _arrive(move_goal, 1.0)
			if global_position.distance_to(move_goal) < 6.0:
				state = State.IDLE
		State.ATTACK_MOVE:
			if _acquire_timer <= 0.0:
				var e := Game.instance.nearest_enemy(self, def["range"] + 120.0)
				if e:
					target = e
					state = State.ATTACK
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
				var keep: float = def["range"] * 0.8
				if d > keep:
					desired = _arrive(target.global_position, 1.0)
				face_target = target
		State.MINE_GO:
			if not is_instance_valid(mine_target) or mine_target.minerals <= 0:
				mine_target = Game.instance.nearest_asteroid(global_position, 900.0)
				if mine_target == null:
					state = State.RETURN if cargo > 0 else State.IDLE
			else:
				var reach := mine_target.radius + radius + 4.0
				if global_position.distance_to(mine_target.global_position) <= reach:
					state = State.MINING
					_mine_timer = def["mine_time"]
				else:
					desired = _arrive(mine_target.global_position, 1.0, reach)
		State.MINING:
			if not is_instance_valid(mine_target) or mine_target.minerals <= 0:
				state = State.MINE_GO
			else:
				_mine_timer -= delta
				queue_redraw()
				if _mine_timer <= 0.0:
					cargo += mine_target.extract(def["cargo"])
					state = State.RETURN
					queue_redraw()
		State.RETURN:
			var base := Game.instance.nearest_starbase(owner_id, global_position)
			if base == null:
				state = State.IDLE
			else:
				var reach := base.radius + radius + 2.0
				if global_position.distance_to(base.global_position) <= reach + 4.0:
					Game.instance.add_resources(owner_id, {"minerals": cargo})
					cargo = 0
					state = State.MINE_GO if is_instance_valid(mine_target) else State.IDLE
					if state == State.IDLE:
						move_goal = global_position
				else:
					desired = _arrive(base.global_position, 1.0, reach)

	if _acquire_timer <= 0.0:
		_acquire_timer = 0.25

	# Fire at whatever is in range, even while moving.
	if def["weapon"] != "" and _cooldown <= 0.0:
		var shoot: SpaceEntity = target if is_instance_valid(target) and target.is_alive() else null
		if shoot == null or global_position.distance_to(shoot.global_position) > def["range"]:
			shoot = Game.instance.nearest_enemy(self, def["range"])
		if shoot and global_position.distance_to(shoot.global_position) <= def["range"] + shoot.radius:
			Game.instance.fire(self, shoot, def["weapon"], def["damage"])
			_cooldown = def["cooldown"] * randf_range(0.9, 1.1)

	_steer(desired + _separation(), delta, face_target)

## Desired velocity toward `goal`, slowing inside the braking radius.
## `stop_at` leaves a gap (e.g. to hover beside an asteroid).
func _arrive(goal: Vector2, urgency: float, stop_at: float = 0.0) -> Vector2:
	var to := goal - global_position
	var dist := to.length() - stop_at
	if dist <= 1.0:
		return Vector2.ZERO
	var speed: float = def["speed"]
	var slow := clampf(dist / 60.0, 0.15, 1.0)
	if urgency <= 0.0:
		slow = clampf(dist / 30.0, 0.0, 0.5)
	return to.normalized() * speed * slow

func _separation() -> Vector2:
	var push := Vector2.ZERO
	for other in Game.instance.ships_near(global_position, radius * 2.5):
		if other == self:
			continue
		var d: Vector2 = global_position - other.global_position
		var min_d: float = radius + other.radius
		var len := d.length()
		if len < min_d and len > 0.01:
			push += d / len * (min_d - len) * 6.0
		elif len <= 0.01:
			push += Vector2.from_angle(randf() * TAU) * 10.0
	return push

func _steer(desired: Vector2, delta: float, face: SpaceEntity) -> void:
	var speed: float = def["speed"]
	var accel := speed * 2.2
	velocity = velocity.move_toward(desired.limit_length(speed), accel * delta)
	global_position += velocity * delta

	var face_dir := Vector2.ZERO
	if face:
		face_dir = face.global_position - global_position
	elif velocity.length() > 8.0:
		face_dir = velocity
	if face_dir != Vector2.ZERO:
		# Bigger hulls turn slower.
		var turn_rate := clampf(6.0 * 8.0 / radius, 1.2, 6.0)
		rotation = rotate_toward(rotation, face_dir.angle(), turn_rate * delta)

	var thrusting := velocity.length() > 12.0
	flame_sprite.visible = thrusting
	if thrusting:
		_flame_timer += delta
		flame_sprite.frame = int(_flame_timer * 12.0) % 2

func _draw() -> void:
	if Engine.is_editor_hint():
		return
	if state == State.MINING and is_instance_valid(mine_target):
		# Flickering tractor beam to the asteroid.
		var to := to_local(mine_target.global_position)
		var a := 0.5 + 0.4 * sin(Game.now() * 20.0)
		draw_line(Vector2(radius * 0.6, 0), to, Color(0.45, 1.0, 0.85, a), 1.0)
	super._draw()
	if cargo > 0 and selected:
		draw_set_transform(Vector2.ZERO, -global_rotation, Vector2.ONE)
		draw_rect(Rect2(-radius - 3, radius + 4, 3, 3), Color("3fd6b0"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
