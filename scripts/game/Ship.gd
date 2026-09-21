@tool
class_name Ship
extends SpaceEntity
## A single ship. Stats come from Defs.SHIPS[ship_type]; sprites are
## assets/pixel/ship_<type>.png plus a team-tinted overlay layer.

enum State { IDLE, MOVE, ATTACK, ATTACK_MOVE, MINE_GO, MINING, RETURN, COLONIZE, BUILD, BOMBARD }

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
var target: SpaceEntity
## An Asteroid (barges) or a gas giant Planet (skimmers); both expose
## resource, amount, radius and extract().
var mine_target: Node2D
var cargo: int = 0
var cargo_type: String = "minerals"
var colonize_target: Planet
var bombard_target: Planet
var build_site: Vector2

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
	refresh_stats()
	hp = max_hp
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
	return def.get("role", "") in ["miner", "skimmer"]

## Barges mine asteroids; skimmers mine gas giants.
func can_mine(target: Node2D) -> bool:
	if def.get("role", "") == "miner":
		return target is Asteroid
	if def.get("role", "") == "skimmer":
		return target is Planet and not (target as Planet).is_habitable()
	return false

func _find_mine_target(resource: String) -> Node2D:
	if def["role"] == "skimmer":
		return Game.instance.nearest_gas_giant(global_position, 3000.0)
	return Game.instance.nearest_asteroid(global_position, 900.0, resource)

## Re-derives hull/shield caps from research, keeping current fractions.
func refresh_stats() -> void:
	var g := Game.instance
	var hp_frac := hp / max_hp if max_hp > 0.0 else 1.0
	var sh_frac := shield / max_shield if max_shield > 0.0 else 1.0
	max_hp = def["hp"] * g.mod(owner_id, "hull")
	max_shield = def["shield"] * g.mod(owner_id, "shield")
	hp = max_hp * hp_frac
	shield = max_shield * sh_frac

func max_speed() -> float:
	return def["speed"] * Game.instance.mod(owner_id, "speed") * Game.instance.ship_speed_factor(owner_id)

func cargo_cap() -> int:
	return int(def.get("cargo", 0) * Game.instance.mod(owner_id, "cargo"))

# ---------------------------------------------------------------- orders

func take_damage(amount: float, from: SpaceEntity = null) -> void:
	super.take_damage(amount, from)
	if owner_id == Game.instance.player_id and hp > 0.0 and from != null:
		Game.instance.alert("Your ships are under attack!", "alert_ships")

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

func order_mine(a: Node2D) -> void:
	if not can_mine(a):
		order_move(a.global_position)
		return
	if cargo > 0 and a.resource != cargo_type:
		state = State.RETURN
	else:
		state = State.RETURN if cargo >= cargo_cap() else State.MINE_GO
	mine_target = a

func order_return() -> void:
	if is_miner() and cargo > 0:
		state = State.RETURN

func order_colonize(p: Planet) -> void:
	if def["role"] != "colony":
		order_move(p.global_position)
		return
	colonize_target = p
	state = State.COLONIZE

## Warships: close to weapons range of an enemy planet and fire on it until
## its population is gone.
func order_bombard(p: Planet) -> void:
	if def["weapon"] == "":
		order_move(p.global_position)
		return
	bombard_target = p
	target = null
	state = State.BOMBARD

func order_build_starbase(pos: Vector2) -> void:
	if def["role"] != "constructor":
		return
	build_site = pos
	state = State.BUILD

func order_stop() -> void:
	state = State.IDLE
	target = null
	move_goal = global_position

# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_regen_shields(delta)
	# Out of energy: weapons recharge (and engines run) at a quarter speed.
	var power := Game.instance.ship_speed_factor(owner_id)
	_cooldown -= delta * power
	_acquire_timer -= delta

	var desired := Vector2.ZERO
	var face_target: SpaceEntity = null

	match state:
		State.IDLE:
			if def["weapon"] != "" and _acquire_timer <= 0.0:
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
			if not is_instance_valid(mine_target) or mine_target.amount <= 0:
				var want: String = mine_target.resource if is_instance_valid(mine_target) else cargo_type
				mine_target = _find_mine_target(want)
				if mine_target == null:
					state = State.RETURN if cargo > 0 else State.IDLE
			else:
				var reach: float = mine_target.radius + radius + 4.0
				if global_position.distance_to(mine_target.global_position) <= reach + 4.0:
					state = State.MINING
					_mine_timer = def["mine_time"]
				else:
					desired = _arrive(mine_target.global_position, 1.0, reach)
		State.MINING:
			if not is_instance_valid(mine_target) or mine_target.amount <= 0:
				state = State.MINE_GO
			else:
				_mine_timer -= delta
				queue_redraw()
				if _mine_timer <= 0.0:
					cargo_type = mine_target.resource
					cargo += mine_target.extract(cargo_cap() - cargo)
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
				var keep: float = def["range"] * 0.8 + bombard_target.radius
				if global_position.distance_to(bombard_target.global_position) > keep:
					desired = _arrive(bombard_target.global_position, 1.0, keep)
				face_target = null
		State.BUILD:
			if global_position.distance_to(build_site) <= 8.0:
				if Game.instance.starbase_site_problem(build_site) == "":
					Game.instance.found_starbase(owner_id, build_site)
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
		State.RETURN:
			var base := Game.instance.nearest_starbase(owner_id, global_position)
			if base == null:
				state = State.IDLE
			else:
				var reach := base.radius + radius + 2.0
				if global_position.distance_to(base.global_position) <= reach + 4.0:
					Game.instance.add_resources(owner_id, {cargo_type: float(cargo)})
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
		var shoot: Node2D = target if is_instance_valid(target) and target.is_alive() else null
		if state == State.BOMBARD and is_instance_valid(bombard_target):
			shoot = bombard_target
		if shoot == null or global_position.distance_to(shoot.global_position) > def["range"] + shoot.radius:
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
	var speed: float = max_speed()
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
	var speed: float = max_speed()
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
		var turn_rate := clampf(6.0 * 8.0 / radius, 1.2, 6.0) * Game.instance.ship_speed_factor(owner_id)
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
