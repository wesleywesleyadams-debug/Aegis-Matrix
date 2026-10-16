@tool
class_name Ship
extends SpaceEntity
## A single ship. Stats come from Defs.SHIPS[ship_type]; sprites are
## assets/pixel/ship_<type>.png plus a team-tinted overlay layer.

enum State { IDLE, MOVE, ATTACK, ATTACK_MOVE, MINE_GO, MINING, RETURN, COLONIZE, BUILD, BOMBARD, REFIT, DOCK_GO, DOCKED }

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
const MAX_HULL_RADIUS := 34.0

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
## Carrier side: one slot per bay, holding the ship in it (or null).
var bay_craft: Array = []
## Docking side: the carrier being flown to, and which bay was reserved.
var dock_carrier: Ship = null
var dock_slot: int = -1
## How fast a bay mends what is in it, as a fraction of the maximum per second.
const BAY_REPAIR_PER_SEC := 0.10
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

func _apply_visuals() -> void:
	if not is_node_ready() and not has_node("Hull"):
		return
	var hull: Sprite2D = get_node("Hull")
	var team: Sprite2D = get_node("Team")
	# One hull per class, whatever its rank.
	var art: String = "ship_" + ship_type
	hull.texture = Defs.tex(art)
	team.texture = Defs.tex(art + "_team")
	team.modulate = Defs.team_color(owner_id)
	# The art is drawn at Defs.ART_SCALE and shown at 1/ART_SCALE, so a ship
	# covers the same world space as before at twice the detail.
	hull.scale = Vector2.ONE / Defs.ART_SCALE
	team.scale = hull.scale
	_apply_mark()
	_rebuild_flames(hull.texture, hull.scale)

## Hull marks (Defs.HULL_MARKS) are rank: the hull keeps the one shape its
## class is built in, and research shows as chevrons laid over the nose â
## one for Mk II, two for Mk III, three for Mk IV.
func _apply_mark() -> void:
	if not has_node("Mark"):
		return
	var mk: Sprite2D = get_node("Mark")
	var cls: String = def.get("base", ship_type)
	var level := Game.instance.mark_level(owner_id, ship_type) if Game.instance else 0
	if level <= 0 or not Defs.MARK_LINES.has(cls):
		mk.visible = false
		return
	mk.texture = Defs.tex("ship_mark_%s_%d" % [cls, clampi(level, 1, 3)])
	mk.scale = Vector2.ONE / Defs.ART_SCALE
	mk.visible = mk.texture != null

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
	return float(def["range"]) * (Game.instance.mod(owner_id, "range") if Game.instance else 1.0)

## Turret sprites for a hull that has mounts: positions are fractions of the
## sprite (x along the hull from the stern, y off the keel), so they sit
## right whatever the mark's shape.
## Fittings that come from the def rather than the sprite: turret mounts and
## hangar bays. Called once `def` is known, since _ready builds the visuals
## before it assigns one.
func _apply_def_visuals() -> void:
	_rebuild_turrets()
	if def.has("bays") and bay_craft.size() != int(def["bays"]):
		bay_craft.resize(int(def["bays"]))

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
	var size := Vector2(hull.texture.get_size()) / Defs.ART_SCALE
	for m in def["turrets"]:
		var t := Sprite2D.new()
		t.texture = Defs.tex("ship_turret")
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.scale = Vector2.ONE / Defs.ART_SCALE * float(def.get("turret_scale", 1.0))
		t.position = Vector2((float(m[0]) - 0.5) * size.x, float(m[1]) * size.y)
		add_child(t)
		_turret_sprites.append(t)

## Where bay `i` sits in the carrier's own frame (see Defs.carrier_bays):
## the odd slots are the mirrored, lower-side bays.
func bay_offset(i: int) -> Vector2:
	var art: Dictionary = Defs.WARSHIP_ART_SIZE.get(ship_type, {})
	if art.is_empty():
		return Vector2.ZERO
	var bays: Array = Defs.carrier_bays(int(art["w"]), int(art["h"]))
	if bays.is_empty():
		return Vector2.ZERO
	var b: Vector2 = bays[(i / 2) % bays.size()]
	# Design units run from the stern; the sprite is centred on the hull.
	var x: float = b.x - art["w"] / 2.0
	var y: float = b.y * (1.0 if i % 2 == 0 else -1.0)
	return Vector2(x, y)

## A free bay for `craft`, or -1.
func free_bay() -> int:
	for i in bay_craft.size():
		if bay_craft[i] == null or not is_instance_valid(bay_craft[i]):
			return i
	return -1

func is_carrier() -> bool:
	return def.get("bays", 0) > 0

## Whether this ship is small enough to sit in a carrier's bay.
func fits_bay() -> bool:
	return def.get("role", "") == "warship" and not is_carrier() and float(def["radius"]) <= Defs.BAY_MAX_RADIUS

## Sends this ship to a carrier's bay to be mended.
func order_dock(c: Ship) -> void:
	held = false
	if c == null or not c.is_carrier() or c.owner_id != owner_id or not fits_bay():
		return
	dock_carrier = c
	state = State.DOCK_GO

## This ship's own berth on its carrier.
func bay_offset_for_slot() -> Vector2:
	return dock_carrier.bay_offset(dock_slot) if is_instance_valid(dock_carrier) and dock_slot >= 0 else Vector2.ZERO

## Mended and pushed back out, facing away from the carrier.
func _launch_from_bay() -> void:
	if is_instance_valid(dock_carrier) and dock_slot >= 0 and dock_slot < dock_carrier.bay_craft.size():
		dock_carrier.bay_craft[dock_slot] = null
	Game.instance.sfx.play_at("launch", global_position, -6.0)
	var away := Vector2.RIGHT.rotated(rotation)
	global_position += away * (radius + 6.0)
	move_goal = global_position
	dock_carrier = null
	dock_slot = -1
	state = State.IDLE

func is_miner() -> bool:
	return def.get("role", "") in ["miner", "skimmer"]

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
	_speed_cache = def["speed"] * Game.instance.mod(owner_id, "speed") * Game.instance.ship_speed_factor(owner_id) * storm
	return _speed_cache

## How fast this ship fills its hold on `node`, per minute (Defs.PER_MIN).
## Spice comes in slower than ore, and nebula gas slower still.
func harvest_rate(node: Node2D) -> float:
	var base: float = float(def.get("harvest", 0.5)) * Game.instance.mod(owner_id, "harvest")
	if node is NebulaPocket:
		return base * Defs.HARVEST_NEBULA_MULT
	if node.resource == "spice":
		return base * Defs.HARVEST_SPICE_MULT
	return base

func cargo_cap() -> int:
	return int(def.get("cargo", 0) * Game.instance.mod(owner_id, "cargo"))

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
	state = State.ATTACK
	target = e

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
	_regen_shields(delta)
	if def.get("job", "") == "field_repair":
		_repair_timer -= delta
		if _repair_timer <= 0.0:
			_repair_timer = 0.5
			_repairing = Abilities.repair_tick(self, 0.5)
			queue_redraw()
	# The queued route is drawn in local space, so it has to be redrawn as
	# the ship moves or it slides along with it.
	if selected and not order_queue.is_empty():
		queue_redraw()
	# Out of energy: weapons recharge (and engines run) at a quarter speed.
	var power := Game.instance.ship_speed_factor(owner_id)
	_cooldown -= delta * power
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
				if d > keep:
					desired = _arrive(target.global_position, 1.0)
				# A turreted hull (the carrier) lets its mounts do the aiming and
				# keeps its own heading; only fixed guns need the nose on target.
				if not def.has("turrets"):
					face_target = target
		State.DOCK_GO:
			# Fly to the carrier and take the bay reserved on arrival.
			if not is_instance_valid(dock_carrier) or not dock_carrier.is_alive():
				dock_carrier = null
				state = State.IDLE
			else:
				var slot := dock_carrier.free_bay()
				var berth: Vector2 = dock_carrier.global_position
				if slot >= 0:
					berth += dock_carrier.bay_offset(slot).rotated(dock_carrier.rotation)
				# Generous: the cradle is a point, and a ship nosing into it is
				# being pushed off by the crowd-separation force.
				if global_position.distance_to(berth) <= radius + 10.0 and slot >= 0:
					dock_slot = slot
					dock_carrier.bay_craft[slot] = self
					state = State.DOCKED
					velocity = Vector2.ZERO
					Game.instance.sfx.play_at("dock", global_position, -6.0)
				else:
					desired = _arrive(berth, 1.0)
		State.DOCKED:
			# Held in the cradle: hull first, then armor, then launched.
			if not is_instance_valid(dock_carrier) or not dock_carrier.is_alive():
				dock_carrier = null
				dock_slot = -1
				state = State.IDLE
			else:
				global_position = dock_carrier.global_position + bay_offset_for_slot().rotated(dock_carrier.rotation)
				rotation = dock_carrier.rotation + (PI * 0.5 if dock_slot % 2 == 0 else -PI * 0.5)
				velocity = Vector2.ZERO
				var step: float = BAY_REPAIR_PER_SEC * delta
				if hp < max_hp:
					hp = minf(max_hp, hp + max_hp * step)
				elif armor < max_armor:
					armor = minf(max_armor, armor + max_armor * step)
				else:
					_launch_from_bay()
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

	# Fire at whatever is in range, even while moving.
	if def["weapon"] != "" and _cooldown <= 0.0:
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
		if shoot and global_position.distance_to(shoot.global_position) <= weapon_range() + shoot.radius:
			var dmg: float = def["damage"] * (1.0 + Game.instance.mark_level(owner_id, ship_type) * float(Defs.MARK_STEP["damage"]))
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
				ready = bears_on(shoot.global_position)
			if ready:
				# Turrets can shoot on the move, but a moving mount is a worse
				# one: at full speed roughly a third of the volley goes wide.
				# Fixed guns are unaffected — they only fire while on the
				# bearing anyway.
				var acc := 1.0
				if def.has("turrets"):
					acc = lerpf(1.0, MOVING_ACCURACY, clampf(velocity.length() / maxf(max_speed(), 1.0), 0.0, 1.0))
				for g in int(def.get("guns", 1)):
					if randf() >= acc:
						continue
					Game.instance.fire(self, shoot, def["weapon"], dmg)
				_cooldown = def["cooldown"] / Game.instance.mod(owner_id, "fire_rate") * randf_range(0.9, 1.1)

	if Game.instance.is_ai(owner_id):
		desired = _avoid_sun(desired)
	# A ship on its final approach to a bay ignores the crowding force, or it
	# would be shouldered off the cradle it is trying to sit in.
	var crowd := Vector2.ZERO if state == State.DOCK_GO or state == State.DOCKED else _separation()
	# A parked ship takes the spot crowding gives it rather than fighting its
	# way back: otherwise two hulls that overlap at rest shove each other out
	# and fly straight back in, forever. Big hulls show it worst, since they
	# overlap from further away.
	if state == State.IDLE and crowd != Vector2.ZERO:
		move_goal = global_position + crowd.limit_length(radius)
	_steer(desired + crowd, delta, face_target if face_target != null else face_at)

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
				# A craft on (or lining up for) one of our bays sits inside the
				# hull by design: shoving it away would have the carrier jitter
				# in place, each bay pushing from a different side.
				if other is Ship and other.dock_carrier == self:
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
	if selected and not order_queue.is_empty():
		_draw_waypoints()
	_draw_job()
	super._draw()

var _harvest_fx: HarvestFx
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

## Job effects, in the job's accent color (Defs.JOBS): the Heat Shield's
## screen (a slow shimmer ring), a Tender's green repair beams and
## emergency flash, and an Escort's guard ring while selected.
## The shift-queued route, drawn while the ship is selected: a dashed line
## through each waypoint with a pip on every stop.
func _draw_waypoints() -> void:
	var pts := queued_points()
	if pts.is_empty():
		return
	var c := Color(1, 1, 1, 0.45)
	var from := to_local(move_goal if state != State.IDLE else global_position)
	for p in pts:
		var to := to_local(p)
		var d := to - from
		var steps := int(maxf(d.length() / 14.0, 1.0))
		for i in steps:
			if i % 2 == 0:
				draw_line(from + d * (float(i) / steps), from + d * (float(i + 1) / steps), c, 1.0)
		draw_circle(to, 3.0, c)
		from = to

func _draw_job() -> void:
	var jid: String = def.get("job", "")
	if jid == "":
		return
	var c: Color = Defs.JOBS[jid]["color"]
	var t := Time.get_ticks_msec() / 1000.0
	draw_set_transform(Vector2.ZERO, -global_rotation, Vector2.ONE)
	match jid:
		"heat_screen":
			var n := 48
			for i in n:
				if i % 2 == 0:
					var a := TAU * i / n + t * 0.3
					draw_arc(Vector2.ZERO, Abilities.HEAT_RANGE, a, a + TAU / n, 3, Color(c, 0.22), 1.5)
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
