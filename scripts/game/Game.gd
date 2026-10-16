class_name Game
extends Node2D
## Root of scenes/Main.tscn. Owns the match: per-player economy (four
## resources, pay-over-time with spice substitution, upkeep, research),
## spatial queries, spawning, the human player's selection/orders, the
## camera, and win/loss. Everything else reaches it through Game.instance.

signal selection_changed
signal message(text: String, color: Color)
## A message that stays up `extra` seconds (real time) longer than usual,
## and is never pushed off the stack by newer ones: the arrival lines.
signal message_long(text: String, color: Color, extra: float)
signal match_over(won: bool)
signal tech_completed(pid: int, tech_id: String)

const SHIP_SCENE := preload("res://scenes/Ship.tscn")
const STARBASE_SCENE := preload("res://scenes/Starbase.tscn")
const PLANET_SCENE := preload("res://scenes/Planet.tscn")
const ASTEROID_SCENE := preload("res://scenes/Asteroid.tscn")
const MAP_RECT := Rect2(-1800, -1150, 3600, 2300)
const ZOOM_LEVELS: Array[float] = [1.0, 2.0, 3.0, 4.0, 6.0]
const CELL := 64.0
## Coarse spatial hash for target searches (weapon ranges are a few hundred px).
const BIG_CELL := 256.0
const PAN_SPEED := 900.0
const EDGE_PAN_MARGIN := 6
const SUBSTITUTABLE := ["food", "minerals", "energy"]

static var instance: Game
## Scaled, pause-aware match clock (seconds). Use this, not wall time.
static var _clock: float = 0.0
## Balance-sim run (SL_SIM): skip everything that only exists to be seen or
## heard (effects, sounds, the HUD) so matches run faster. Outcomes are
## unaffected: projectiles, which carry the damage, still fly.
var sim_mode: bool = false
## The title screen's background match: the AI plays both sides, silently,
## with no HUD, no fog and no player input, and a DemoDirector moving the
## camera. Unlike a sim, everything is still drawn.
var demo_mode: bool = false

var player_id: int = 1
var players: Array[int] = [1, 2]
var resources := {}
## Net change per second over the last second, per player per resource.
var rates := {}
## The last RATE_WINDOW one-second samples, so the HUD can show a trend that
## does not flicker with every delivery: pid -> resource -> Array[float].
const RATE_WINDOW := 60
var _rate_hist := {}
var researched := {}      # pid -> {tech_id: true}
var research := {}        # pid -> {"id": String, "progress": float, "stalled": bool} or {}
var research_queue := {}  # pid -> Array of tech ids

var selection: Array[SpaceEntity] = []
var focused_planet: Planet
var focused_asteroid: Asteroid
var focused_star: Star
var control_groups := {}
var paused_menu: bool = false
var is_over: bool = false
## After the match: the player chose View Map (look around, select to inspect;
## no orders). Set by the HUD.
var map_view: bool = false
## Post-game stats (see MatchStats).
var stats: MatchStats = MatchStats.new()
## Fog of war for the human player (null in sims / with SL_NOFOG).
var vision: Vision
## Every player's sensors / intel by player id (the AI plays by these too).
## Empty with SL_NOFOG (then the AI knows everything, as before).
var visions := {}
## Alive ships by job id, rebuilt every tick (see Abilities).
var job_ships := {}
## Starbase placement mode for a selected Constructor.
var placing_starbase: bool = false
## Placing a Weapons Depot (Constructor, E).
var placing_depot: bool = false
## Placing a Mining Station (see start_station_placement).
var placing_station: bool = false

var _grid := {}
var _grid_big := {}
## Cached once per physics tick (see _physics_process).
var stars_list: Array = []
var starbase_list: Array = []
var nebula_list: Array = []
var storm_list: Array = []
var ring_list: Array = []
var _rate_acc := {}
var _rate_timer: float = 0.0
var _was_starved := false
var _was_empty := {}
var _zoom_index: int = 2
var _drag_start_screen: Vector2
var _mouse_down: bool = false
var _dragging: bool = false
var _mid_drag: bool = false
var _last_click_time: float = 0.0
var _last_group_key: int = -1
var _last_group_time: float = 0.0
var _last_real_us: int = 0

@onready var world: Node2D = $World
@onready var ships_root: Node2D = $World/Ships
@onready var starbases_root: Node2D = $World/Starbases
@onready var fx_root: Node2D = $World/FX
@onready var camera: Camera2D = $Camera
@onready var hud: HUD = $HUD
@onready var ai: AIController = $AI
@onready var sfx: Sfx = $Sfx

static func now() -> float:
	return _clock

func _enter_tree() -> void:
	# Dev aid: SL_LOAD=<path> starts the match from that save file.
	# Dev aid: SL_NEURAL=1 plays against the trained neural commander.
	if OS.get_environment("SL_NEURAL") != "":
		GameState.neural_ai = true
	if OS.get_environment("SL_LOAD") != "":
		GameState.load_on_start = true
		GameState.load_save_path = OS.get_environment("SL_LOAD")
	instance = self
	_clock = 0.0
	sim_mode = OS.get_environment("SL_SIM") != ""
	demo_mode = GameState.demo_mode
	# Seed sims here, before any child's _ready draws a random number.
	# SL_SEED (if set) fixes the match randomness independently of the run
	# name, so trainers can replay the same game with different players.
	if sim_mode:
		seed(hash(OS.get_environment("SL_SEED") if OS.get_environment("SL_SEED") != "" else OS.get_environment("SL_SIM")))
	player_id = clampi(GameState.human_player_id, 1, 2)
	for pid in players:
		resources[pid] = Defs.starting_resources(GameState.deathmatch)
		rates[pid] = {}
		_rate_acc[pid] = {}
		researched[pid] = {}
		research[pid] = {}
		research_queue[pid] = []

func _ready() -> void:
	process_physics_priority = -10
	if demo_mode:
		_start_demo()
		return
	# No account controls during a match.
	SignedInLabel.visible = false
	tree_exiting.connect(func(): SignedInLabel.visible = true)
	# Sims and training run on their own clock, not the player's pacing.
	Engine.time_scale = 1.0 if OS.get_environment("SL_SIM") != "" else HUD.TIME_RATE
	RenderingServer.set_default_clear_color(Color("07060f"))
	# Dev aid: SL_LOAD=<path to a save> resumes it, so a save/restore can be
	# checked end to end from the command line.
	if OS.get_environment("SL_LOAD") != "":
		GameState.load_save_path = OS.get_environment("SL_LOAD")
		GameState.load_on_start = true
		# and says what came back, so a restore can be checked without eyes.
		get_tree().create_timer(1.0).timeout.connect(func():
			var ships := get_tree().get_nodes_in_group("ships")
			print("LOADED %d ships, %d heading for or sitting in a bay" % [ships.size(),
				ships.filter(func(x): return x.state == Ship.State.DOCKED or x.state == Ship.State.DOCK_GO).size()]))
	# Resuming a saved match? Its system comes from the save.
	var save_data := {}
	if GameState.load_on_start:
		save_data = SaveGame.read(GameState.load_save_path)
		GameState.system_id = str(save_data.get("system", "orion_reach"))
		GameState.system_seed = int(save_data.get("system_seed", 0))
	# Dev aid: SL_SYSTEM=<id>[:seed] picks the system directly.
	if OS.get_environment("SL_SYSTEM") != "":
		var sp := OS.get_environment("SL_SYSTEM").split(":")
		GameState.system_id = sp[0]
		GameState.system_seed = int(sp[1]) if sp.size() > 1 else int(SystemGen.find(sp[0]).get("seed", 0))
	_build_system()
	var loaded := false
	if GameState.load_on_start:
		GameState.load_on_start = false
		loaded = SaveGame.apply(self, save_data)
	for sb in get_tree().get_nodes_in_group("starbases"):
		(sb as Starbase).died.connect(_on_starbase_died)
	add_child(stats)
	# Dev aid: SL_ECON prints the energy ledger at intervals, which is how the
	# economy's sources and sinks are checked against each other. It sits here
	# rather than with the screenshot hooks so it runs in a sim too.
	if OS.get_environment("SL_ECON") != "":
		for t9 in [60.0, 180.0, 360.0, 600.0]:
			get_tree().create_timer(t9).timeout.connect(func():
				var mine9 := get_tree().get_nodes_in_group("planets").filter(func(p): return p.owner_id == player_id)
				var made := 0.0
				var pops := 0.0
				for p9 in mine9:
					made += p9.energy_out
					pops += p9.pop
				print("ECON t=%ds energy %.0f (%+.2f/s)  plants %.1f/min from %d worlds, %d pops  upkeep %.1f/min  ships %d" % [
					int(Game.now()), resources[player_id]["energy"], rates[player_id].get("energy", 0.0), made, mine9.size(), int(pops),
					upkeep(player_id), ship_count(player_id)]))
	# Balance harness (SL_SIM): the AI plays both sides.
	if OS.get_environment("SL_SIM") != "":
		ai.setup([1, 2])
		if OS.get_environment("SL_NOFOG") == "":
			for p in [1, 2]:
				_add_vision(p, false)
		add_child(SimRunner.new())
		hud.visible = false
		hud.process_mode = Node.PROCESS_MODE_DISABLED
		sfx.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		ai.setup([3 - player_id])
		# Fog of war for the human player (SL_NOFOG=1 turns it off for dev shots).
		if OS.get_environment("SL_NOFOG") == "":
			vision = _add_vision(player_id, true)
			_add_vision(3 - player_id, false)
			if loaded:
				vision.import_state(save_data.get("fog", {}))
	if not loaded:
		# Starting barges go straight to work.
		for s in get_tree().get_nodes_in_group("ships"):
			if s.is_miner():
				var rock := nearest_asteroid(s.global_position, 900.0)
				if rock:
					s.order_mine(rock)
		var home := nearest_starbase(player_id, Vector2.ZERO)
		if home:
			camera.global_position = home.global_position
	camera.zoom = Vector2.ONE * ZOOM_LEVELS[_zoom_index]
	Music.play_game_playlist()
	if loaded:
		notify("Saved game loaded.", "note_save")
	else:
		# The arrival lines linger: they are the player's briefing.
		message_long.emit(system_settings.get("arrival", "You arrive in uncharted space."), Color("e8d6a8"), ARRIVAL_LINGER)
		message_long.emit("Grow your worlds, mine the belts, find spice, destroy the enemy starbase.", Color("c3cde4"), ARRIVAL_LINGER)
	_enter_dev_capture()

## The title screen's background match (demo_mode): build the system, hand
## both sides to the AI and set the barges working, then let a DemoDirector
## run the camera. No HUD, sound, music, fog or briefing.
func _start_demo() -> void:
	_build_system()
	for sb in get_tree().get_nodes_in_group("starbases"):
		(sb as Starbase).died.connect(_on_starbase_died)
	add_child(stats)
	ai.setup([1, 2])
	hud.visible = false
	hud.process_mode = Node.PROCESS_MODE_DISABLED
	sfx.process_mode = Node.PROCESS_MODE_DISABLED
	for s in get_tree().get_nodes_in_group("ships"):
		if s.is_miner():
			var rock := nearest_asteroid(s.global_position, 900.0)
			if rock:
				s.order_mine(rock)
	# Close in, so the ships read as ships behind the menu.
	_zoom_index = 3
	camera.zoom = Vector2.ONE * ZOOM_LEVELS[_zoom_index]
	add_child(DemoDirector.new())

# ---------------------------------------------------------------- system

## Extra real-time seconds the arrival lines stay up beyond a normal message.
const ARRIVAL_LINGER := 15.0

## The current system's settings (star, background, arrival line...).
var system_settings: Dictionary = {}

## Star type and name, and the background palette, for this system.
func _apply_system_look(st: Dictionary) -> void:
	var star: Star = $World/Star
	star.set_type(st.get("star", "yellow"))
	star.star_name = st.get("star_name", "Orion")
	var bg: Dictionary = SystemGen.BACKGROUNDS.get(st.get("bg", "violet"), SystemGen.BACKGROUNDS["violet"])
	var mat := $Background/Space.material as ShaderMaterial
	mat.set_shader_parameter("base_color", bg["base"])
	mat.set_shader_parameter("nebula_tint", bg["nebula"])
	RenderingServer.set_default_clear_color(bg["base"])

## Swaps Main.tscn's hand-made Orion Reach for a generated system when a
## different one is picked (see SystemGen). Orion Reach keeps the scene as-is.
func _build_system() -> void:
	# The edge of the playable area, shaded off and outlined.
	world.add_child(MapEdge.new())
	system_settings = SystemGen.settings(GameState.system_id, GameState.system_seed)
	_apply_system_look(system_settings)
	if GameState.system_id == "orion_reach":
		# Hand-built in Main.tscn, so its nebulae are laid out here against
		# the starbases that are already in the scene.
		var p1 := starbases_root.get_children().filter(func(b): return b.owner_id == 1)
		if not p1.is_empty() and system_settings.has("nebula"):
			for ft in SystemGen.nebulae(str(system_settings["nebula"]), p1[0].position, GameState.system_seed):
				_add_nebula(ft)
		return
	var layout := SystemGen.generate(GameState.system_seed, system_settings)
	for root in [$World/Planets, $World/Asteroids, starbases_root, ships_root]:
		for n in root.get_children():
			root.remove_child(n)
			n.free()
	for p in layout["planets"]:
		var pl: Planet = PLANET_SCENE.instantiate()
		pl.name = p["name"]
		pl.planet_name = p["name"]
		pl.kind = p["kind"]
		pl.size_variant = p.get("size", "")
		pl.owner_id = p["owner"]
		pl.position = p["pos"]
		$World/Planets.add_child(pl)
	for a in layout["asteroids"]:
		var r: Asteroid = ASTEROID_SCENE.instantiate()
		r.name = a["name"]
		r.variant = a["variant"]
		r.position = a["pos"]
		$World/Asteroids.add_child(r)
	for s in layout["starbases"]:
		var sb: Starbase = STARBASE_SCENE.instantiate()
		sb.owner_id = s["owner"]
		sb.position = s["pos"]
		starbases_root.add_child(sb)
	for s in layout["ships"]:
		var ship := spawn_ship(s["type"], s["owner"], s["pos"])
		ship.rotation = s["rot"]
	for ft in layout.get("features", []):
		if ft["type"] == "storms":
			var storm := IonStorm.new()
			storm.inner = ft["inner"]
			storm.phase = ft["phase"]
			world.add_child(storm)
		if ft["type"] == "rings":
			var ring := DebrisRing.new()
			ring.radius = ft["radius"]
			ring.width = ft["width"]
			ring.gap_half = ft["gap_half"]
			ring.gaps = ft["gaps"]
			world.add_child(ring)
			world.move_child(ring, 0)
			_build_nav()
		if ft["type"] == "binary":
			var a: Star = $World/Star
			var b := Star.new()
			b.name = "Star2"
			world.add_child(b)
			world.move_child(b, a.get_index() + 1)
			b.set_type(a.star_type)
			var base: String = a.star_name
			a.star_name = base + " A"
			b.star_name = base + " B"
			for k in 2:
				var s: Star = [a, b][k]
				s.orbit_radius = ft["orbit"]
				s.orbit_phase = PI * k
				s.orbit_speed = TAU / ft["period"]
				s.position = s.orbit_position(now())
		if ft["type"] == "spice_nebula":
			_add_nebula(ft)

## Puts one spice nebula into the world, under everything else.
func _add_nebula(ft: Dictionary) -> void:
	var neb := SpiceNebula.from_feature(ft)
	world.add_child(neb)
	world.move_child(neb, 0)

## Amber heads-up (no alarm) when your shielded ships are in a nebula, at
## most every NEBULA_WARN_MS, with a minimap flare where it happened.
const NEBULA_WARN_MS := 20000
var _nebula_warn_ms: int = -100000
const NEBULA_ALARM_DB := -2.5

func warn_nebula(at: Vector2) -> void:
	var t := Time.get_ticks_msec()
	if t - _nebula_warn_ms < NEBULA_WARN_MS:
		return
	_nebula_warn_ms = t
	add_flare(at, Color("ffae4a"))
	message.emit("Your ships are in the Spice Nebula: shields drain and won't recharge inside.", Color("ffae4a"))
	# The radiation alarm, 25% quieter (-2.5 dB) so it isn't obtrusive; shares
	# the alert cooldown (at most one alarm per ALERT_COOLDOWN).
	if t - _last_alert_ms >= int(ALERT_COOLDOWN * 1000.0):
		_last_alert_ms = t
		sfx.play_ui("alert_ships", NEBULA_ALARM_DB)
		alert_sounds += 1

# ---------------------------------------------------------------- navigation

## Only systems with debris rings need routing; elsewhere nav stays null and
## ships fly straight as before.
const NAV_CELL := 40.0
var nav: AStarGrid2D = null

## Solid debris at p (grown by margin).
func is_blocked(p: Vector2, margin: float = 0.0) -> bool:
	for r in ring_list:
		if r.blocks(p, margin):
			return true
	return false

## No debris along the straight line a -> b (sampled every 16 px).
func line_clear(a: Vector2, b: Vector2, margin: float = 12.0) -> bool:
	var steps := int(a.distance_to(b) / 16.0) + 1
	for i in steps + 1:
		if is_blocked(a.lerp(b, float(i) / steps), margin):
			return false
	return true

func _build_nav() -> void:
	# Runs during setup, before the first tick has filled the cached lists.
	ring_list = get_tree().get_nodes_in_group("debris_rings")
	nav = AStarGrid2D.new()
	nav.region = Rect2i(0, 0, int(ceil(MAP_RECT.size.x / NAV_CELL)), int(ceil(MAP_RECT.size.y / NAV_CELL)))
	nav.cell_size = Vector2(NAV_CELL, NAV_CELL)
	nav.offset = MAP_RECT.position + Vector2.ONE * NAV_CELL / 2.0
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	for x in nav.region.size.x:
		for y in nav.region.size.y:
			if is_blocked(nav.offset + Vector2(x, y) * NAV_CELL, NAV_CELL * 0.45):
				nav.set_point_solid(Vector2i(x, y), true)

func _nav_cell(p: Vector2) -> Vector2i:
	var c := ((p - MAP_RECT.position) / NAV_CELL).floor()
	return Vector2i(clampi(int(c.x), 0, nav.region.size.x - 1), clampi(int(c.y), 0, nav.region.size.y - 1))

## Nearest open cell to `c` (for starts / goals that sit on debris).
func _open_cell(c: Vector2i) -> Vector2i:
	if not nav.is_point_solid(c):
		return c
	for r in range(1, 6):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var q := c + Vector2i(dx, dy)
				if nav.is_in_boundsv(q) and not nav.is_point_solid(q):
					return q
	return c

## Waypoints from a to b around debris (b last), string-pulled so ships cut
## straight across open space instead of hugging grid cells.
func find_path(a: Vector2, b: Vector2) -> PackedVector2Array:
	if nav == null or line_clear(a, b):
		return PackedVector2Array([b])
	var raw := nav.get_point_path(_open_cell(_nav_cell(a)), _open_cell(_nav_cell(b)))
	if raw.is_empty():
		return PackedVector2Array([b])
	raw.append(b)
	var out := PackedVector2Array()
	var anchor := a
	var i := 0
	while i < raw.size():
		var j := raw.size() - 1
		while j > i and not line_clear(anchor, raw[j]):
			j -= 1
		out.append(raw[j])
		anchor = raw[j]
		i = j + 1
	return out

## Whether side `pid` is run by the computer (both sides in balance sims).
func is_ai(pid: int) -> bool:
	return ai.players.has(pid)

## Whether `p` is inside an active ion-storm arm (ships crawl there).
func in_storm(p: Vector2) -> bool:
	for s in storm_list:
		if s.contains(p):
			return true
	return false

## Whether `p` is inside a spice nebula (shields drain there).
func in_nebula(p: Vector2) -> bool:
	for n in nebula_list:
		if n.contains(p):
			return true
	return false

# ---------------------------------------------------------------- economy

func add_resources(pid: int, amounts: Dictionary) -> void:
	if not resources.has(pid):
		return
	for k in amounts:
		resources[pid][k] = resources[pid].get(k, 0.0) + amounts[k]
		_rate_acc[pid][k] = _rate_acc[pid].get(k, 0.0) + amounts[k]

func _deduct(pid: int, k: String, amount: float) -> void:
	resources[pid][k] -= amount
	_rate_acc[pid][k] = _rate_acc[pid].get(k, 0.0) - amount

## Pays `per_sec` (resource -> amount per second) for `dt` seconds.
## Any food/minerals/energy shortfall is covered 1:1 from spice. If even
## spice can't cover it, pays the largest fraction it can. Returns that
## fraction (0..1), so callers advance progress by dt * fraction.
func pay_over_time(pid: int, per_sec: Dictionary, dt: float) -> float:
	var r: Dictionary = resources[pid]
	var need := {}
	for k in per_sec:
		need[k] = per_sec[k] * dt
	var f := 1.0
	if _spice_needed(r, need, 1.0) > r["spice"] + 0.000001:
		# Spice need is monotonic in the fraction; bisect for the max we can pay.
		var lo := 0.0
		var hi := 1.0
		for i in 14:
			var mid := (lo + hi) * 0.5
			if _spice_needed(r, need, mid) <= r["spice"]:
				lo = mid
			else:
				hi = mid
		f = lo
	if f <= 0.0:
		return 0.0
	for k in need:
		var take: float = need[k] * f
		if k in SUBSTITUTABLE:
			var from_stock := minf(maxf(r[k], 0.0), take)
			_deduct(pid, k, from_stock)
			if take > from_stock:
				_deduct(pid, "spice", take - from_stock)
		else:
			_deduct(pid, k, take)
	return f

func _spice_needed(r: Dictionary, need: Dictionary, f: float) -> float:
	var s: float = need.get("spice", 0.0) * f
	for k in need:
		if k in SUBSTITUTABLE:
			s += maxf(0.0, need[k] * f - maxf(r[k], 0.0))
	return s

func ship_count(pid: int) -> int:
	var n := 0
	for s in get_tree().get_nodes_in_group("ships"):
		if s.owner_id == pid:
			n += 1
	return n

func starbase_count(pid: int) -> int:
	var n := 0
	for sb in get_tree().get_nodes_in_group("starbases"):
		if sb.owner_id == pid:
			n += 1
	return n

## Multiplier on every starbase's upkeep (sites under construction count).
func starbase_upkeep_multiplier(pid: int, count: int = -1) -> float:
	var k := (starbase_count(pid) if count < 0 else count) / Defs.STARBASE_UPKEEP_SCALE
	return 1.0 + k * k * k

## Multiplier on every ship's upkeep, growing with fleet size.
func upkeep_multiplier(pid: int) -> float:
	var k := ship_count(pid) / Defs.UPKEEP_SCALE_SHIPS
	return 1.0 + k * k

## The share of its hull a construct is founded with: a tenth, unless Rapid
## Assembly (Constructs) has it standing further along before the first shot.
func construct_start_frac(pid: int) -> float:
	return clampf(0.1 * mod(pid, "construct_start"), 0.1, 0.9)

## Summed research bonus for `key` (e.g. "damage") as a multiplier.
func mod(pid: int, key: String) -> float:
	var m := 1.0
	for t in researched.get(pid, {}):
		m += Defs.TECHS[t]["effects"].get(key, 0.0)
	return m

## How many marks a warship class has earned for this player, 0-3 (see
## Defs.HULL_MARKS): Mk I through Mk IV.
func mark_level(pid: int, ship_type: String) -> int:
	var d: Dictionary = Defs.SHIPS.get(ship_type, {})
	var base: String = d.get("base", ship_type)
	if not Defs.MARK_LINES.has(base):
		return 0
	var n := 0
	for t in researched.get(pid, {}):
		n += int(Defs.TECHS[t]["effects"].get("mark_" + base, 0.0))
	return n

## Research multiplier for `key` including this class's hull marks.
func hull_mod(pid: int, ship_type: String, key: String) -> float:
	return mod(pid, key) * (1.0 + mark_level(pid, ship_type) * float(Defs.MARK_STEP.get(key, 0.0)))

## The class's current name for this player, e.g. "Mk III Corvette".
func ship_name(pid: int, ship_type: String) -> String:
	return Defs.marked_name(ship_type, mark_level(pid, ship_type))

func has_tech(pid: int, tech_id: String) -> bool:
	return researched.get(pid, {}).has(tech_id)

func total_pop(pid: int) -> float:
	var n := 0.0
	for p in get_tree().get_nodes_in_group("planets"):
		if p.owner_id == pid:
			n += p.pop
	return n

## Out of energy (stockpile at or below 0): starbases can't produce ships
## and ships move and fire at ENERGY_STARVED_FACTOR speed.
func energy_starved(pid: int) -> bool:
	return resources.has(pid) and resources[pid]["energy"] <= 0.0001

## Speed multiplier for a player's ships (1.0, or the starved factor).
func ship_speed_factor(pid: int) -> float:
	return Defs.ENERGY_STARVED_FACTOR if energy_starved(pid) else 1.0

func upkeep(pid: int) -> float:
	var u := 0.0
	for s in get_tree().get_nodes_in_group("ships"):
		if s.owner_id == pid:
			u += s.def["upkeep"]
	# Research can make a fleet thirstier (overcharged weapons) or cheaper to
	# run, which is what gives those techs a real cost.
	u *= upkeep_multiplier(pid) * mod(pid, "upkeep")
	u += starbase_count(pid) * Defs.STARBASE["upkeep"] * starbase_upkeep_multiplier(pid)
	for dp in get_tree().get_nodes_in_group("depots"):
		if dp.owner_id == pid:
			u += Defs.WEAPONS_DEPOT["upkeep"]
	return u

# ---------------------------------------------------------------- research

## "done", "active", "queued", "available" or "locked".
func tech_state(pid: int, tech_id: String) -> String:
	if has_tech(pid, tech_id):
		return "done"
	if research[pid].get("id", "") == tech_id:
		return "active"
	if tech_id in research_queue[pid]:
		return "queued"
	for req in Defs.TECHS[tech_id]["requires"]:
		if not has_tech(pid, req) and research[pid].get("id", "") != req and req not in research_queue[pid]:
			return "locked"
	return "available"

## Queues a tech (prerequisites may be earlier in the queue). Returns "" or
## a reason it can't be queued.
func queue_research(pid: int, tech_id: String) -> String:
	match tech_state(pid, tech_id):
		"done": return "Already researched"
		"active", "queued": return "Already in the research queue"
		"locked": return "Requires " + ", ".join(Defs.TECHS[tech_id]["requires"].map(func(r): return Defs.TECHS[r]["name"]))
	# One project at a time: finish or cancel the current one first.
	if not research[pid].is_empty() or not research_queue[pid].is_empty():
		return "Already researching something else"
	research_queue[pid].append(tech_id)
	return ""

func cancel_research(pid: int, tech_id: String) -> void:
	# Drop it and anything queued that depended on it. Energy already spent is lost.
	if research[pid].get("id", "") == tech_id:
		research[pid] = {}
	research_queue[pid].erase(tech_id)
	var changed := true
	while changed:
		changed = false
		for t in research_queue[pid].duplicate():
			if tech_state(pid, t) == "locked":
				research_queue[pid].erase(t)
				changed = true

func _tick_research(pid: int, dt: float) -> void:
	if research[pid].is_empty():
		if research_queue[pid].is_empty():
			return
		research[pid] = {"id": research_queue[pid].pop_front(), "progress": 0.0, "stalled": false}
	var cur: Dictionary = research[pid]
	var t: Dictionary = Defs.TECHS[cur["id"]]
	var per_sec := {}
	for k in t["cost"]:
		per_sec[k] = t["cost"][k] / t["time"]
	var f := pay_over_time(pid, per_sec, dt)
	cur["stalled"] = f < 0.999
	cur["progress"] += dt * f
	if cur["progress"] >= t["time"]:
		researched[pid][cur["id"]] = true
		research[pid] = {}
		_on_tech_done(pid, cur["id"])

func _on_tech_done(pid: int, tech_id: String) -> void:
	for s in get_tree().get_nodes_in_group("entities"):
		if s.owner_id == pid and s.has_method("refresh_stats"):
			s.refresh_stats()
	if pid == player_id:
		notify("Research complete: %s." % Defs.TECHS[tech_id]["name"], "note_tech")
	tech_completed.emit(pid, tech_id)

# ---------------------------------------------------------------- queries

func _physics_process(delta: float) -> void:
	# Rebuild the ship spatial hashes once per tick: a fine one for
	# separation, a coarse one for target searches.
	_grid.clear()
	_grid_big.clear()
	for s in get_tree().get_nodes_in_group("ships"):
		# Ships inside a Weapons Depot are out of the world: no collisions, no
		# targeting (see Ship.enter_depot).
		if s.docked:
			continue
		var key := Vector2i((s.global_position / CELL).floor())
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(s)
		var big := Vector2i((s.global_position / BIG_CELL).floor())
		if not _grid_big.has(big):
			_grid_big[big] = []
		_grid_big[big].append(s)
	# Per-frame snapshots of small groups that ships query constantly (a group
	# lookup allocates a fresh array every call).
	stars_list = get_tree().get_nodes_in_group("stars")
	# Ships by job (see Abilities), for cheap nearby-effect checks.
	job_ships.clear()
	for s in get_tree().get_nodes_in_group("ships"):
		var jid: String = s.def.get("job", "")
		if jid != "" and s.is_alive():
			if not job_ships.has(jid):
				job_ships[jid] = []
			job_ships[jid].append(s)
	starbase_list = get_tree().get_nodes_in_group("starbases")
	nebula_list = get_tree().get_nodes_in_group("nebulae")
	storm_list = get_tree().get_nodes_in_group("storms")
	ring_list = get_tree().get_nodes_in_group("debris_rings")
	if is_over:
		return
	for pid in players:
		# Upkeep is a per-minute figure (Defs.PER_MIN).
		pay_over_time(pid, {"energy": upkeep(pid) / Defs.PER_MIN}, delta)
		_tick_research(pid, delta)
	# Any other resource hitting zero.
	for k in ["food", "minerals", "spice"]:
		var empty: bool = resources[player_id][k] <= 0.0001
		if empty and not _was_empty.get(k, false):
			alert("Out of %s!" % Defs.RESOURCE_NAMES[k].to_lower(), "alert_resource")
		_was_empty[k] = empty
	var starved := energy_starved(player_id)
	if starved and not _was_starved:
		alert("Out of energy! Ship production halted and ships slowed to 25%.", "alert_energy")
	_was_starved = starved
	_rate_timer += delta
	if _rate_timer >= 1.0:
		for pid in players:
			var snap := {}
			for k in Defs.RESOURCES:
				snap[k] = _rate_acc[pid].get(k, 0.0) / _rate_timer
			rates[pid] = snap
			_rate_acc[pid] = {}
			if not _rate_hist.has(pid):
				_rate_hist[pid] = {}
			for k in Defs.RESOURCES:
				var h: Array = _rate_hist[pid].get(k, [])
				h.append(float(snap[k]))
				if h.size() > RATE_WINDOW:
					h.remove_at(0)
				_rate_hist[pid][k] = h
		_rate_timer = 0.0

## Average change per minute over the last RATE_WINDOW seconds. The HUD shows
## this as a rising or falling arrow, so a single delivery does not flip it.
func avg_rate(pid: int, key: String) -> float:
	var h: Array = _rate_hist.get(pid, {}).get(key, [])
	if h.is_empty():
		return rates.get(pid, {}).get(key, 0.0) * Defs.PER_MIN
	var sum := 0.0
	for v in h:
		sum += v
	return sum / h.size() * Defs.PER_MIN

func ships_near(pos: Vector2, r: float) -> Array:
	var out := []
	var lo := Vector2i(((pos - Vector2(r, r)) / CELL).floor())
	var hi := Vector2i(((pos + Vector2(r, r)) / CELL).floor())
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			for s in _grid.get(Vector2i(x, y), []):
				if is_instance_valid(s) and s.global_position.distance_to(pos) <= r:
					out.append(s)
	return out

func nearest_enemy(from: SpaceEntity, max_dist: float) -> SpaceEntity:
	# Walks the coarse grid directly (no temporary arrays); compares squared
	# distances until a candidate is close enough to matter.
	var best: SpaceEntity = null
	var best_d := max_dist
	var fp := from.global_position
	var pid := from.owner_id
	var reach := max_dist + 40.0
	var lo := Vector2i(((fp - Vector2(reach, reach)) / BIG_CELL).floor())
	var hi := Vector2i(((fp + Vector2(reach, reach)) / BIG_CELL).floor())
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var cell = _grid_big.get(Vector2i(x, y))
			if cell == null:
				continue
			for s in cell:
				# Ships destroyed earlier this tick are still in the grid.
				if not is_instance_valid(s) or s.owner_id == pid or not s.is_enemy_of(pid) or not s.is_alive():
					continue
				var d: float = fp.distance_to(s.global_position) - s.radius
				# Prefer warships over civilian hulls at similar range.
				if s.def["role"] != "warship":
					d += 40.0
				if d < best_d:
					best_d = d
					best = s
	for sb in starbase_list:
		if is_instance_valid(sb) and sb.is_enemy_of(pid) and sb.is_alive():
			var d: float = fp.distance_to(sb.global_position) - sb.radius
			if d < best_d:
				best_d = d
				best = sb
	return best

## `known`: only rocks that player's sensors have explored (the AI passes
## its own Vision so it can't pick rocks it has never seen).
func nearest_asteroid(pos: Vector2, max_dist: float, resource: String = "minerals", known: Vision = null) -> Asteroid:
	var best: Asteroid = null
	var best_d := max_dist
	for a in get_tree().get_nodes_in_group("asteroids"):
		if a.is_queued_for_deletion() or a.amount <= 0 or a.resource != resource:
			continue
		if known and not known.is_explored_at(a.global_position):
			continue
		var d := pos.distance_to(a.global_position)
		if d < best_d:
			best_d = d
			best = a
	return best

## The closest enemy colony within `max_dist` of `pos` (surface distance), or
## null. Planets are not SpaceEntities, so nearest_enemy never sees them;
## warships use this to open fire on a colony they drift into range of.
func nearest_enemy_planet(pid: int, pos: Vector2, max_dist: float) -> Planet:
	var best: Planet = null
	var best_d := max_dist
	for p in get_tree().get_nodes_in_group("planets"):
		if not p.is_enemy_of(pid):
			continue
		var d: float = pos.distance_to(p.global_position) - p.radius
		if d < best_d:
			best_d = d
			best = p
	return best

func nearest_gas_giant(pos: Vector2, max_dist: float, known: Vision = null) -> Planet:
	var best: Planet = null
	var best_d := max_dist
	for p in get_tree().get_nodes_in_group("planets"):
		if p.is_habitable() or p.amount <= 0 or (known and known.known_owner(p) < 0):
			continue
		var d := pos.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best

func nearest_starbase(pid: int, pos: Vector2, include_sites: bool = false) -> Starbase:
	var best: Starbase = null
	var best_d := INF
	for sb in get_tree().get_nodes_in_group("starbases"):
		if sb.owner_id == pid and sb.is_alive() and (include_sites or not sb.under_construction):
			var d := pos.distance_to(sb.global_position)
			if d < best_d:
				best_d = d
				best = sb
	return best

func entity_at(world_pos: Vector2) -> SpaceEntity:
	var best: SpaceEntity = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("entities"):
		if not e.is_alive():
			continue
		var d := world_pos.distance_to(e.global_position)
		if d <= e.radius + 4.0 and d < best_d:
			best_d = d
			best = e
	return best

func asteroid_at(world_pos: Vector2) -> Asteroid:
	for a in get_tree().get_nodes_in_group("asteroids"):
		if world_pos.distance_to(a.global_position) <= a.radius + 4.0:
			return a
	return null

func planet_at(world_pos: Vector2) -> Planet:
	for p in get_tree().get_nodes_in_group("planets"):
		if world_pos.distance_to(p.global_position) <= p.radius + 4.0:
			return p
	return null

## "" if a starbase may be founded at pos, otherwise the reason.
## Where a construct may be built. Every construct keeps a ring of clear
## space scaled to its size (Defs.PLACEMENT_RING), and two rings may not
## overlap, so the same rule covers starbases, depots and Mining Stations.
func site_problem(kind: String, pos: Vector2) -> String:
	if not MAP_RECT.grow(-60).has_point(pos):
		return "Too close to the edge of the system"
	var ring := Defs.placement_ring(kind)
	for n in get_tree().get_nodes_in_group("starbases") + get_tree().get_nodes_in_group("depots") + get_tree().get_nodes_in_group("mining_stations"):
		if n.global_position.distance_to(pos) < ring + n.radius * Defs.PLACEMENT_RING:
			return "Too close to another construct"
	for p in get_tree().get_nodes_in_group("planets"):
		if p.global_position.distance_to(pos) < p.radius + 40.0:
			return "Too close to a planet"
	for s in get_tree().get_nodes_in_group("stars"):
		if s.global_position.distance_to(pos) < s.radiation_radius + 40.0:
			return "Too close to the star"
	if is_blocked(pos, 50.0):
		return "Blocked by the debris ring"
	return ""

func starbase_site_problem(pos: Vector2) -> String:
	return site_problem("starbase", pos)

func depot_site_problem(pos: Vector2) -> String:
	return site_problem("depot", pos)

func station_site_problem(pos: Vector2) -> String:
	return site_problem("station", pos)

# ---------------------------------------------------------------- spawning

func spawn_ship(ship_type: String, pid: int, pos: Vector2) -> Ship:
	var s: Ship = SHIP_SCENE.instantiate()
	s.ship_type = ship_type
	s.owner_id = pid
	s.position = pos
	ships_root.add_child(s)
	# Destroyed in battle (not used up colonizing / founding a starbase).
	s.died.connect(func(e): if e.hp <= 0.0: stats.count(e.owner_id, "ships_lost"))
	return s

func found_starbase(pid: int, pos: Vector2) -> Starbase:
	var sb: Starbase = STARBASE_SCENE.instantiate()
	sb.owner_id = pid
	sb.under_construction = true
	sb.position = pos
	starbases_root.add_child(sb)
	sb.died.connect(_on_starbase_died)
	if pid == player_id:
		notify("Starbase construction started.", "note_starbase", pos)
	return sb

func fire(from: Node2D, to: Node2D, weapon: String, damage: float) -> void:
	var p := Projectile.new()
	fx_root.add_child(p)
	p.setup(from, to, weapon, damage * mod(from.owner_id, "damage") * (Abilities.damage_mult(from) if from is Ship else 1.0))
	if not sim_mode:
		sfx.play_at("laser" if weapon == "laser" else "torpedo", from.global_position, -8.0)

func spawn_explosion(pos: Vector2, scale_mult: float = 1.0) -> void:
	if sim_mode:
		return
	var e := Effect.new()
	e.texture = Defs.tex("explosion")
	e.hframes = 8
	e.fps = 14.0
	e.global_position = pos
	e.rotation = randi_range(0, 3) * PI / 2.0
	e.scale = Vector2.ONE * clampf(snappedf(scale_mult, 0.5), 0.5, 3.0) / Defs.ART_SCALE
	fx_root.add_child(e)
	sfx.play_at("boom_big" if scale_mult >= 1.0 else "boom", pos, -6.0)

func spawn_shield_hit(pos: Vector2, r: float, from_pos: Vector2) -> void:
	if sim_mode:
		return
	var e := Effect.new()
	e.texture = Defs.tex("shield_hit")
	e.fps = 16.0
	e.modulate = Color("7fd8ff")
	e.global_position = pos
	e.rotation = (from_pos - pos).angle()
	e.scale = Vector2.ONE * maxf(1.0, round(r / 8.0)) / Defs.ART_SCALE
	fx_root.add_child(e)
	sfx.play_at("shield", pos, -12.0)

# ---------------------------------------------------------------- events

func planet_claimed(p: Planet, old_owner: int) -> void:
	stats.count(p.owner_id, "planets_won")
	if old_owner > 0:
		stats.count(old_owner, "planets_lost")
	if p.owner_id == player_id:
		notify(("%s colonized." if old_owner == 0 else "%s conquered.") % p.planet_name, "note_colony", p.global_position)
	elif old_owner == player_id:
		alert("%s lost to the enemy!" % p.planet_name, "alert_planet_lost", true, p.global_position)
	selection_changed.emit()

## A bombarded planet ran out of pops and went neutral.
func planet_depopulated(p: Planet, old_owner: int, attacker: int) -> void:
	stats.count(old_owner, "planets_lost")
	if old_owner == player_id:
		alert("%s has been depopulated and lost!" % p.planet_name, "alert_planet_lost", true, p.global_position)
	elif attacker == player_id:
		notify("%s depopulated. It can now be colonized." % p.planet_name, "note_colony", p.global_position)
	selection_changed.emit()

func _on_starbase_died(sb: SpaceEntity) -> void:
	selection.erase(sb)
	if not (sb as Starbase).under_construction:
		stats.count(sb.owner_id, "starbases_lost")
	if sb.owner_id == player_id and not (sb as Starbase).under_construction:
		alert("A starbase has been destroyed!", "alert_starbase_lost", true, sb.global_position)
	await get_tree().process_frame
	var mine := false
	var theirs := false
	for s in get_tree().get_nodes_in_group("starbases"):
		if s == sb or not s.is_alive() or s.under_construction:
			continue
		if s.owner_id == player_id:
			mine = true
		else:
			theirs = true
	if not mine:
		_end_match(false)
	elif not theirs:
		_end_match(true)

## Light-blue notification for good news / progress (ship built, planet
## colonized, research done...). Not rate limited.
const NOTIFY_COLOR := Color("7fd8ff")

func notify(text: String, sound: String = "", at: Variant = null) -> void:
	if at is Vector2:
		add_flare(at, NOTIFY_COLOR)
	message.emit(text, NOTIFY_COLOR)
	if sound != "":
		sfx.play_ui(sound)

## Red alert + alarm sound for being attacked or running out of a
## resource. At most one every ALERT_COOLDOWN seconds of REAL time (so game
## speed and pause don't change how often you hear them), whatever raised it.
const ALERT_COOLDOWN := 15.0
const ALERT_COLOR := Color("ff6a5a")

## Minimap flares: where an alert or notification happened. Each is
## {pos, color, ms} and lives FLARE_MS of real time. A new flare within
## FLARE_MERGE_PX of a live one of the same color just refreshes it, so a
## ship sitting in radiation doesn't stack dozens of rings.
const FLARE_MS := 6000
const FLARE_MERGE_PX := 250.0
var flares: Array = []

func add_flare(pos: Vector2, color: Color) -> void:
	var t := Time.get_ticks_msec()
	flares = flares.filter(func(f): return t - f["ms"] < FLARE_MS)
	for f in flares:
		if f["color"] == color and f["pos"].distance_to(pos) < FLARE_MERGE_PX:
			if t - f["ms"] > FLARE_MS / 2:
				f["ms"] = t
			return
	flares.append({"pos": pos, "color": color, "ms": t})
var _last_alert_ms: int = -1000000
## Alarm sounds played this match (dev check for the cooldown).
var alert_sounds: int = 0

## `sound` names the alert's own alarm (see Sfx.NAMES), so each kind of
## trouble is recognisable by ear.
## `critical` alerts (a planet lost, a starbase destroyed) always show their
## message, but inside the cooldown they stay silent: never more than one
## alarm sound per ALERT_COOLDOWN.
func alert(text: String, sound: String = "alert", critical: bool = false, at: Variant = null) -> void:
	# The minimap flare shows even when the cooldown silences the alarm.
	if at is Vector2:
		add_flare(at, ALERT_COLOR)
	var t := Time.get_ticks_msec()
	var ready := t - _last_alert_ms >= int(ALERT_COOLDOWN * 1000.0)
	if not ready and not critical:
		return
	message.emit(text, ALERT_COLOR)
	if ready:
		_last_alert_ms = t
		sfx.play_ui(sound)
		alert_sounds += 1

func _end_match(won: bool) -> void:
	if is_over:
		return
	is_over = true
	stats.finish()
	# Freeze the battlefield exactly as it ended (ships, shots, planets, AI);
	# the camera, HUD and View Map selection keep working.
	$World.process_mode = Node.PROCESS_MODE_DISABLED
	ai.process_mode = Node.PROCESS_MODE_DISABLED
	if vision:
		vision.reveal_all()
	if not demo_mode:
		sfx.play_ui("victory" if won else "defeat")
	match_over.emit(won)

# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if paused_menu or (is_over and not map_view) or demo_mode:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		if _mouse_down and not _dragging and event.position.distance_to(_drag_start_screen) > 6.0:
			_dragging = true
		if _dragging:
			hud.set_drag_rect(Rect2(_drag_start_screen, event.position - _drag_start_screen).abs())
		if _mid_drag:
			camera.global_position -= event.relative / camera.zoom.x
			_clamp_camera()
	elif event is InputEventKey and event.pressed and not event.echo and not is_over:
		_handle_key(event)

func _handle_mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			if placing_starbase or placing_depot or placing_station:
				if e.pressed:
					if placing_depot:
						_place_depot(get_global_mouse_position())
					elif placing_station:
						_place_station(get_global_mouse_position())
					else:
						_place_starbase(get_global_mouse_position())
				return
			if e.pressed:
				_mouse_down = true
				_dragging = false
				_drag_start_screen = e.position
			elif _mouse_down:
				_mouse_down = false
				if _dragging:
					_box_select(Rect2(_drag_start_screen, e.position - _drag_start_screen).abs(), e.shift_pressed)
					hud.set_drag_rect(Rect2())
				else:
					_click_select(get_global_mouse_position(), e.shift_pressed)
				_dragging = false
		MOUSE_BUTTON_RIGHT:
			if e.pressed and not is_over:
				if placing_starbase or placing_depot or placing_station:
					placing_starbase = false
					placing_depot = false
					placing_station = false
				else:
					_issue_command(get_global_mouse_position(), e.ctrl_pressed, e.shift_pressed)
		MOUSE_BUTTON_MIDDLE:
			_mid_drag = e.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				_zoom_step(1, e.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				_zoom_step(-1, e.position)

func _handle_key(e: InputEventKey) -> void:
	var k := e.keycode
	if k == KEY_ESCAPE:
		if placing_starbase or placing_depot or placing_station:
			placing_starbase = false
			placing_depot = false
			placing_station = false
		elif hud.research_open():
			# The research screen sits on top, so it closes first.
			hud.toggle_research()
		elif is_instance_valid(focused_planet) or is_instance_valid(focused_asteroid) or is_instance_valid(focused_star):
			clear_planet_focus()
		elif not selection.is_empty():
			# Esc clears the selection first; with nothing selected it opens the
			# in-match menu.
			_set_selection([], false)
		else:
			hud.show_pause(true)
		return
	if k >= KEY_1 and k <= KEY_9:
		var n := k - KEY_0
		if e.ctrl_pressed:
			control_groups[n] = selection.duplicate()
			message.emit("Group %d set (%d)." % [n, selection.size()], Color("c3cde4"))
		else:
			var group: Array = control_groups.get(n, []).filter(func(x): return is_instance_valid(x) and x.is_alive())
			if group.is_empty():
				return
			_set_selection(group, e.shift_pressed)
			if _last_group_key == n and now() - _last_group_time < 0.35:
				center_on(_centroid(group))
			_last_group_key = n
			_last_group_time = now()
		return
	# The selection panel's own grid keys (Q W E / A S D / Z X C ...) come
	# first: they always match the buttons on screen.
	if hud.press_panel_key(k):
		return
	# The same letter with nothing of yours selected: select every ship of that
	# class you own (Q barges, W skimmers, ... just like the build grid). With
	# a starbase, ship or planet selected the panel owns these keys.
	var bt := hud.build_type_for_key(k)
	if bt != "" and selection.is_empty() and not is_instance_valid(focused_planet):
		select_all_of_type(bt)
		return
	# The rest are rebindable (Options > Hotkeys; see Defs.HOTKEYS).
	if k == KEY_KP_SUBTRACT:
		hud.set_speed_index(hud.speed_index() - 1)
		return
	if k == KEY_KP_ADD:
		hud.set_speed_index(hud.speed_index() + 1)
		return
	match Defs.action_for_key(k):
		"next_world":
			cycle_planet()
		"build_here":
			if not hud.planet_view.open_build_picker():
				sfx.play_ui("deny")
		"speed_down":
			hud.set_speed_index(hud.speed_index() - 1)
		"speed_up":
			hud.set_speed_index(hud.speed_index() + 1)
		"speed_normal":
			hud.set_speed_index(HUD.NORMAL_SPEED)
		"pause":
			hud.toggle_play()
		"research":
			hud.toggle_research()
		"home":
			cycle_starbase()
		"stop":
			for s in _own_ships_selected():
				s.order_stop()
		"warships":
			# Select every combat ship you own.
			var all: Array = get_tree().get_nodes_in_group("ships").filter(func(s): return s.owner_id == player_id and s.def["role"] == "warship")
			_set_selection(all, false)

## Writes the match to a new save file (Esc menu > Save Game).
func save_game() -> void:
	var label: String = {"single": "Single-Player", "multi": "Multi-Player", "campaign": "Campaign"}.get(GameState.game_mode, "Game")
	var t := int(now())
	var path := SaveGame.write(self, "%s · %02d:%02d match time" % [label, t / 60, t % 60])
	if path == "":
		message.emit("Couldn't write the save file.", ALERT_COLOR)
	else:
		notify("Game saved.", "note_save")

func request_build(sb: Starbase, ship_type: String) -> void:
	var why := sb.enqueue(ship_type)
	if why != "":
		message.emit(why + ".", Color("ff8a5a"))
		sfx.play_ui("deny")
	else:
		sfx.play_ui("click")

func request_research(tech_id: String) -> void:
	if tech_state(player_id, tech_id) in ["active", "queued"]:
		cancel_research(player_id, tech_id)
		sfx.play_ui("click")
		return
	var why := queue_research(player_id, tech_id)
	if why != "":
		message.emit(why + ".", Color("ff8a5a"))
		sfx.play_ui("deny")
	else:
		sfx.play_ui("click")

func start_starbase_placement() -> void:
	placing_starbase = true
	var n := starbase_count(player_id)
	message.emit("Left-click open space to found starbase #%d (%s over %ds; each starbase's upkeep becomes x%.1f). Right-click to cancel." % [n + 1, Defs.cost_text(Defs.STARBASE["cost"]), Defs.STARBASE["build_time"], starbase_upkeep_multiplier(player_id, n + 1)], Color("c3cde4"))

func start_station_placement() -> void:
	placing_station = true
	message.emit("Left-click open space for a Mining Station (%s over %ds): harvesters unload there instead of flying home. Right-click to cancel." % [
		Defs.cost_text(Defs.MINING_STATION["cost"]), int(Defs.MINING_STATION["build_time"])], Color("c3cde4"))

func _place_station(pos: Vector2) -> void:
	var why := station_site_problem(pos)
	if why != "":
		message.emit(why + ".", Color("ff8a5a"))
		sfx.play_ui("deny")
		return
	var builders2: Array = _own_ships_selected().filter(func(s): return s.def["role"] == "constructor")
	if builders2.is_empty():
		placing_station = false
		return
	builders2.sort_custom(func(a, b): return a.global_position.distance_to(pos) < b.global_position.distance_to(pos))
	builders2[0].order_build_station(pos)
	placing_station = false
	hud.ping(pos, Color("ffd46b"))
	sfx.play_ui("click")

func _place_starbase(pos: Vector2) -> void:
	var why := starbase_site_problem(pos)
	if why != "":
		message.emit(why + ".", Color("ff8a5a"))
		sfx.play_ui("deny")
		return
	var builders: Array = _own_ships_selected().filter(func(s): return s.def["role"] == "constructor")
	if builders.is_empty():
		placing_starbase = false
		return
	builders.sort_custom(func(a, b): return a.global_position.distance_to(pos) < b.global_position.distance_to(pos))
	builders[0].order_build_starbase(pos)
	placing_starbase = false
	hud.ping(pos, Color("ffd46b"))
	sfx.play_ui("click")

func _process(delta: float) -> void:
	if not is_over:
		_clock += delta
	var now_us := Time.get_ticks_usec()
	var real_dt := minf((now_us - _last_real_us) / 1000000.0, 0.1) if _last_real_us > 0 else 0.0
	_last_real_us = now_us
	_update_background()
	if paused_menu or (is_over and not map_view) or demo_mode:
		return
	var dir := Vector2(
		Input.get_axis("cam_left", "cam_right"),
		Input.get_axis("cam_up", "cam_down"))
	var vp := get_viewport()
	var m := vp.get_mouse_position()
	var size := vp.get_visible_rect().size
	if DisplayServer.window_is_focused() and Rect2(Vector2.ZERO, size).has_point(m):
		if m.x <= EDGE_PAN_MARGIN: dir.x = -1
		elif m.x >= size.x - EDGE_PAN_MARGIN: dir.x = 1
		if m.y <= EDGE_PAN_MARGIN: dir.y = -1
		elif m.y >= size.y - EDGE_PAN_MARGIN: dir.y = 1
	if dir != Vector2.ZERO:
		camera.global_position += dir.normalized() * PAN_SPEED * real_dt / sqrt(camera.zoom.x)
		_clamp_camera()

func _zoom_step(dir: int, screen_pos: Vector2) -> void:
	var before := get_global_mouse_position()
	_zoom_index = clampi(_zoom_index + dir, 0, ZOOM_LEVELS.size() - 1)
	camera.zoom = Vector2.ONE * ZOOM_LEVELS[_zoom_index]
	# Keep the point under the cursor fixed.
	var after := camera.get_screen_center_position() + (screen_pos - get_viewport().get_visible_rect().size / 2.0) / camera.zoom.x
	camera.global_position += before - after
	_clamp_camera()

func _clamp_camera() -> void:
	camera.global_position = camera.global_position.clamp(MAP_RECT.position, MAP_RECT.end)

func center_on(pos: Vector2) -> void:
	camera.global_position = pos
	_clamp_camera()

# ---------------------------------------------------------------- selection

func _set_selection(list: Array, additive: bool) -> void:
	list = list.filter(func(e): return is_instance_valid(e))
	if not additive:
		for e in selection:
			if is_instance_valid(e):
				e.selected = false
		selection.clear()
		_focus_planet(null)
		_focus_asteroid(null)
		_focus_star(null)
	for e in list:
		if e not in selection:
			selection.append(e)
			e.selected = true
			if not e.died.is_connected(_on_selected_died):
				e.died.connect(_on_selected_died)
	placing_starbase = false
	selection_changed.emit()

func _focus_star(s: Star) -> void:
	if is_instance_valid(focused_star):
		focused_star.focused = false
	focused_star = s
	if s:
		s.focused = true

func star_at(world_pos: Vector2) -> Star:
	for s in get_tree().get_nodes_in_group("stars"):
		if s is Star and world_pos.distance_to(s.global_position) <= s.core_radius + 6.0:
			return s
	return null

func _focus_asteroid(a: Asteroid) -> void:
	if is_instance_valid(focused_asteroid):
		focused_asteroid.focused = false
	focused_asteroid = a
	if a:
		a.focused = true

## Opens the planet close-up. The camera stays where the player put it:
## the close-up grows in place around the planet.
func _focus_planet(p: Planet) -> void:
	if is_instance_valid(focused_planet):
		focused_planet.focused = false
	focused_planet = p
	if p:
		p.focused = true
	hud.show_planet(p)

## Closes the planet view (and its selection-panel summary).
func clear_planet_focus() -> void:
	_focus_asteroid(null)
	_focus_star(null)
	_focus_planet(null)
	selection_changed.emit()

func _on_selected_died(e: SpaceEntity) -> void:
	selection.erase(e)
	selection_changed.emit()

func _click_select(world_pos: Vector2, additive: bool) -> void:
	var e := entity_at(world_pos)
	if e and vision and not vision.can_see(e):
		e = null
	if e == null:
		var p := planet_at(world_pos)
		if not additive:
			_set_selection([], false)
		if p:
			_focus_planet(p)
			selection_changed.emit()
		else:
			var rock := asteroid_at(world_pos)
			if rock:
				_focus_asteroid(rock)
				selection_changed.emit()
			else:
				var sun := star_at(world_pos)
				if sun:
					_focus_star(sun)
					selection_changed.emit()
		return
	if e.owner_id != player_id:
		_set_selection([e], false)
		return
	if e is Ship and now() - _last_click_time < 0.3 and selection.size() == 1 and selection[0] == e:
		# Double-click: every ship of this class on screen.
		var view := _visible_world_rect()
		var same: Array = get_tree().get_nodes_in_group("ships").filter(func(s): return s.owner_id == player_id and s.ship_type == e.ship_type and view.has_point(s.global_position))
		_set_selection(same, additive)
	elif additive and e in selection:
		e.selected = false
		selection.erase(e)
		selection_changed.emit()
	else:
		_set_selection([e], additive)
	_last_click_time = now()

func _box_select(screen_rect: Rect2, additive: bool) -> void:
	var xf := get_viewport().get_canvas_transform().affine_inverse()
	var a: Vector2 = xf * screen_rect.position
	var b: Vector2 = xf * screen_rect.end
	var r := Rect2(a, b - a).abs()
	var picked: Array = get_tree().get_nodes_in_group("ships").filter(func(s): return s.owner_id == player_id and r.grow(s.radius * 0.5).has_point(s.global_position))
	# Box-selecting a mixed group keeps only warships, like most RTS games.
	var warships := picked.filter(func(s): return s.def["role"] == "warship")
	if not warships.is_empty():
		picked = warships
	if picked.is_empty():
		for sb in get_tree().get_nodes_in_group("starbases"):
			if sb.owner_id == player_id and r.has_point(sb.global_position):
				picked.append(sb)
	_set_selection(picked, additive)

func _visible_world_rect() -> Rect2:
	var size := get_viewport().get_visible_rect().size / camera.zoom
	return Rect2(camera.get_screen_center_position() - size / 2.0, size)

func _own_ships_selected() -> Array:
	return selection.filter(func(e): return is_instance_valid(e) and e is Ship and e.owner_id == player_id)

func _selected_role(role: String) -> bool:
	return _own_ships_selected().any(func(s): return s.def["role"] == role)

func selected_starbase() -> Starbase:
	for e in selection:
		if is_instance_valid(e) and e is Starbase and e.owner_id == player_id and not e.under_construction:
			return e
	return null

func _centroid(list: Array) -> Vector2:
	var c := Vector2.ZERO
	for e in list:
		c += e.global_position
	return c / maxf(list.size(), 1)

# ---------------------------------------------------------------- orders

func _issue_command(world_pos: Vector2, attack_move: bool, queued: bool = false) -> void:
	var ships := _own_ships_selected()
	var sb := selected_starbase()
	if ships.is_empty():
		if sb:
			# Rally onto an object: new ships act on it when they launch
			# (barges mine rocks, colony ships settle free planets, warships
			# attack enemy ships/starbases or bombard enemy planets).
			var obj: Node2D = null
			var kind := ""
			var foe := entity_at(world_pos)
			if foe and foe.is_enemy_of(player_id):
				obj = foe
				kind = "attack"
			elif asteroid_at(world_pos):
				obj = asteroid_at(world_pos)
			else:
				var rp := planet_at(world_pos)
				if rp:
					obj = rp
					if rp.is_enemy_of(player_id):
						kind = "attack"
					elif rp.owner_id == 0 and rp.is_habitable():
						kind = "colonize"
			sb.set_rally(obj.global_position if obj else world_pos, obj)
			if obj:
				hud.flash_target(obj, kind)
			else:
				hud.ping(world_pos, Color.WHITE)
		return
	var target := entity_at(world_pos)
	var rock := asteroid_at(world_pos)
	var planet := planet_at(world_pos)
	if target and target.is_enemy_of(player_id):
		for s in ships:
			if s.def["role"] == "warship":
				s.do_or_queue(queued, "order_attack", [target])
			else:
				s.do_or_queue(queued, "order_move", [world_pos])
		hud.flash_target(target, "attack")
		return
	if rock:
		for s in ships:
			if s.is_miner():
				s.do_or_queue(queued, "order_mine", [rock])
			else:
				s.do_or_queue(queued, "order_move", [rock.global_position])
		hud.flash_target(rock, "")
		return
	if planet and not planet.is_habitable():
		var handled := false
		for s in ships.duplicate():
			if s.can_mine(planet):
				s.do_or_queue(queued, "order_mine", [planet])
				ships.erase(s)
				handled = true
		if ships.any(func(s): return s.def["role"] == "colony"):
			message.emit("Gas giants are uninhabitable.", Color("ff8a5a"))
		if handled:
			hud.flash_target(planet, "")
			if ships.is_empty():
				return
	# Skimmers harvest spice gas where you click inside a spice nebula.
	if not planet and not rock and in_nebula(world_pos) and ships.any(func(s): return s.def["role"] == "skimmer"):
		var pocket := nebula_pocket_at(world_pos)
		for s in ships.duplicate():
			if s.def["role"] == "skimmer":
				s.do_or_queue(queued, "order_mine", [pocket])
				ships.erase(s)
		hud.ping(world_pos, Color("ffae4a"))
		if ships.is_empty():
			return
	if planet and planet.is_enemy_of(player_id):
		# Bombard: warships fire on the planet until its pops are gone.
		for s in ships:
			if s.def["role"] == "warship":
				s.do_or_queue(queued, "order_bombard", [planet])
			else:
				s.do_or_queue(queued, "order_move", [world_pos])
		hud.flash_target(planet, "attack")
		return
	if planet and planet.owner_id == 0:
		var colonists: Array = ships.filter(func(s): return s.def["role"] == "colony")
		if not colonists.is_empty():
			colonists.sort_custom(func(a, b): return a.global_position.distance_to(planet.global_position) < b.global_position.distance_to(planet.global_position))
			colonists[0].do_or_queue(queued, "order_colonize", [planet])
			ships.erase(colonists[0])
			hud.flash_target(planet, "colonize")
			if ships.is_empty():
				return
	# A friendly drop-off: harvesters take their loads there, whether or not
	# it is the nearest one, and go back to the rock they were working.
	if (target is Starbase or target is MiningStation) and target.owner_id == player_id and not target.under_construction:
		var sent := 0
		for s in ships.duplicate():
			if s is Ship and (s as Ship).is_miner():
				# Carrying something: unload it here. Empty: fly here anyway,
				# so the order never looks like it did nothing.
				if (s as Ship).cargo > 0:
					s.do_or_queue(queued, "order_return", [target])
				else:
					s.do_or_queue(queued, "order_move", [target.global_position + (s.global_position - target.global_position).normalized() * (target.radius + 18.0)])
				ships.erase(s)
				sent += 1
		if sent > 0:
			hud.flash_target(target, "")
			for s in ships:
				s.do_or_queue(queued, "order_move", [world_pos])
			return

	# A friendly carrier: send what it can take into its bays to be mended.
	if target is Ship and target.owner_id == player_id and (target as Ship).is_carrier():
		var carrier := target as Ship
		var berthed := 0
		for s in ships.duplicate():
			if s is Ship and s != carrier and (s as Ship).fits_bay():
				s.do_or_queue(queued, "order_dock", [carrier])
				ships.erase(s)
				berthed += 1
			else:
				s.do_or_queue(queued, "order_move", [world_pos])
		hud.flash_target(carrier, "")
		if berthed == 0:
			message.emit("Carrier bays are corvette-sized: bigger hulls will not fit.", Color("ff8a5a"))
		return
	if target is WeaponsDepot and target.owner_id == player_id and not target.under_construction:
		var sent := 0
		for s in ships.duplicate():
			if s is Ship and s.can_refit(target.variant):
				s.do_or_queue(queued, "order_refit", [target.variant, target])
				ships.erase(s)
				sent += 1
			else:
				s.do_or_queue(queued, "order_move", [world_pos])
		hud.flash_target(target, "")
		if sent == 0:
			message.emit("Only generalist warships can be refitted, and only once.", Color("ff8a5a"))
		return
	if target is Starbase and target.owner_id == player_id:
		# Manual drop-off: loaded harvesters unload here instead of being
		# ordered to fly to the spot and forget their cargo.
		var unloading := 0
		for s in ships.duplicate():
			if s.is_miner() and s.cargo > 0:
				s.do_or_queue(queued, "order_return", [])
				ships.erase(s)
				unloading += 1
		hud.flash_target(target, "")
		if unloading > 0 and ships.is_empty():
			return
	var slots := _formation(ships, world_pos)
	for i in ships.size():
		ships[i].do_or_queue(queued, "order_attack_move" if attack_move else "order_move", [slots[i]])
	hud.ping(world_pos, Color("ff5a5a") if attack_move else Color.WHITE)

## Grid formation facing the direction of travel, biggest hulls in front.
func _formation(ships: Array, goal: Vector2) -> Array:
	ships.sort_custom(func(a, b): return a.radius > b.radius)
	var n := ships.size()
	var spacing := 0.0
	for s in ships:
		spacing = maxf(spacing, s.radius * 2.6)
	var cols := int(ceil(sqrt(n)))
	var fwd := (goal - _centroid(ships)).normalized()
	if fwd == Vector2.ZERO:
		fwd = Vector2.RIGHT
	var side := fwd.orthogonal()
	var out := []
	for i in n:
		var row := i / cols
		var col := i % cols
		var in_row := mini(cols, n - row * cols)
		var off := side * (col - (in_row - 1) / 2.0) * spacing - fwd * row * spacing
		out.append(goal + off)
	return out

# ---------------------------------------------------------------- dev capture

## Dev aid: set SL_SHOT="<seconds>[,<time_scale>[,<zoom_index>[,x,y]]]" to
## save a screenshot to user://shot.png after that many game seconds and
## quit. SL_SHOT_OPEN=research|starbase|planet opens that view first.
func _enter_dev_capture() -> void:
	var spec := OS.get_environment("SL_SHOT")
	if spec == "":
		return
	var parts := spec.split(",")
	var secs := float(parts[0])
	if parts.size() > 1:
		var want := float(parts[1])
		var idx := HUD.SPEEDS.find(want)
		if idx >= 0:
			hud.set_speed_index(idx)
		else:
			Engine.time_scale = want
	if parts.size() > 2:
		_zoom_index = int(parts[2])
		camera.zoom = Vector2.ONE * ZOOM_LEVELS[_zoom_index]
	if parts.size() > 4:
		center_on(Vector2(float(parts[3]), float(parts[4])))
	if OS.get_environment("SL_SHOT_OPEN") == "victory":
		# Play a while, destroy the enemy starbases, then capture the end
		# screen (end.png), the Stats window (stats.png) and View Map (map.png).
		await get_tree().create_timer(secs).timeout
		for sb in get_tree().get_nodes_in_group("starbases"):
			if (sb.owner_id == player_id) == (OS.get_environment("SL_SHOT_LOSE") != ""):
				sb._die()
		await get_tree().create_timer(1.0).timeout
		Engine.time_scale = 1.0
		var probe: Node2D = get_tree().get_nodes_in_group("ships")[0]
		var p0 := probe.global_position
		print("VICTORY TEST sound at end: ", sfx._ui.stream.resource_path, " playing=", sfx._ui.playing, " vol=", sfx._ui.volume_db)
		var c0 := Game.now()
		await get_tree().create_timer(2.0).timeout
		print("VICTORY TEST frozen: ship moved %.2f px, clock moved %.2f s" % [probe.global_position.distance_to(p0), Game.now() - c0])
		print("VICTORY TEST sound: ", sfx._ui.stream.resource_path, " playing=", sfx._ui.playing, " vol=", sfx._ui.volume_db)
		for step in ["end", "stats", "map"]:
			if step == "stats":
				hud._show_stats(true)
			elif step == "map":
				hud._show_stats(false)
				hud._enter_map_view()
			await get_tree().create_timer(0.4).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://%s.png" % step)
		print("VICTORY TEST built ", stats.counters, " samples ", stats.samples.size())
		get_tree().quit()
		return
	if OS.get_environment("SL_SHOT_OPEN") == "planet":
		var hp0: Planet = get_tree().get_nodes_in_group("planets").filter(func(p): return p.owner_id == player_id)[0]
		hp0.order_build(0, "farm")
		hp0.order_build(1, "mine")
		hp0.order_build(2, "farm")
	if OS.get_environment("SL_SHOT_OPEN") == "starve":
		resources[player_id]["energy"] = 0.0
		resources[player_id]["spice"] = 0.0
		var sb0 := nearest_starbase(player_id, Vector2.ZERO)
		sb0.enqueue("corvette")
		_set_selection([sb0], false)
	if OS.get_environment("SL_SHOT_OPEN") == "desert":
		var dp: Planet = get_tree().get_nodes_in_group("planets").filter(func(p): return p.kind == "planet_desert")[0]
		dp.colonize(player_id)
		dp.pop = 600.0
		dp.buildings[0] = "farm"
		dp.buildings[1] = "spice_extractor"
		dp.buildings[2] = "spice_extractor"
		if OS.get_environment("SL_DRY") != "":
			dp.spice_reserve = 10.0
		get_tree().create_timer(20.0).timeout.connect(func(): print("DESERT reserve ", dp.spice_reserve, " spice_out ", dp.spice_out, " pop mult ", dp.pop_output_mult(), " spice ", resources[player_id]["spice"]))
	if OS.get_environment("SL_SHOT_OPEN") == "rally2":
		var sb2 := nearest_starbase(player_id, Vector2.ZERO)
		var enemy_p: Planet = get_tree().get_nodes_in_group("planets").filter(func(p): return p.is_enemy_of(player_id))[0]
		var free_p: Planet = get_tree().get_nodes_in_group("planets").filter(func(p): return p.owner_id == 0 and p.is_habitable())[0]
		resources[player_id]["spice"] = 500.0
		sb2.set_rally(enemy_p.global_position, enemy_p)
		sb2.enqueue("corvette")
		get_tree().create_timer(9.0).timeout.connect(func():
			sb2.set_rally(free_p.global_position, free_p)
			sb2.enqueue("colony"))
		get_tree().create_timer(30.0).timeout.connect(func():
			for s in get_tree().get_nodes_in_group("ships"):
				if s.owner_id == player_id and s.state in [Ship.State.BOMBARD, Ship.State.COLONIZE]:
					print("RALLY2 ", s.ship_type, " state ", Ship.State.keys()[s.state])
			print("RALLY2 done"))
	if OS.get_environment("SL_SHOT_OPEN") == "rally":
		var sbr := nearest_starbase(player_id, Vector2.ZERO)
		var spr := nearest_asteroid(sbr.global_position, 5000.0, "spice")
		sbr.set_rally(spr.global_position, spr)
		sbr.enqueue("miner")
		sbr.enqueue("miner")
		get_tree().create_timer(40.0).timeout.connect(func():
			for s in get_tree().get_nodes_in_group("ships"):
				if s.owner_id == player_id and s.is_miner() and is_instance_valid(s.mine_target):
					print("RALLYTEST miner -> ", s.mine_target.name, " (", s.mine_target.resource, ") state ", s.state))
	if OS.get_environment("SL_SHOT_OPEN") == "siege":
		var ep: Planet = get_tree().get_nodes_in_group("planets").filter(func(p): return p.is_enemy_of(player_id))[0]
		for i in 8:
			spawn_ship("corvette", player_id, ep.global_position + Vector2(-200 - i * 12, 60 + i * 14)).order_bombard(ep)
		var np: Planet = get_tree().get_nodes_in_group("planets").filter(func(p): return p.owner_id == 0 and p.is_habitable())[0]
		spawn_ship("colony", player_id, np.global_position + Vector2(-120, 0)).order_colonize(np)
		hud.flash_target(np, "colonize")
		print("SIEGE target ", ep.planet_name, " pop ", ep.pop, "  colonize ", np.planet_name)
	if OS.get_environment("SL_SHOT_OPEN") == "battle":
		# Dev: two 28-ship fleets meet in view, for mix loudness checks.
		var foe: int = 2 if player_id == 1 else 1
		var c := Vector2(0, 700)
		for i in 28:
			var k: String = "cruiser" if i < 2 else ("destroyer" if i < 8 else "corvette")
			var off := Vector2(i % 7 * 16, i / 7 * 18)
			spawn_ship(k, player_id, c + Vector2(-260, -40) + off).order_attack_move(c + Vector2(200, 0))
			spawn_ship(k, foe, c + Vector2(160, -40) + off).order_attack_move(c - Vector2(200, 0))
		center_on(c)
		if OS.get_environment("SL_SELECT_FLEET") != "":
			# Dev: select the whole fleet a few seconds in, so the panel can be
			# checked once ships have taken damage.
			get_tree().create_timer(float(OS.get_environment("SL_SHOT").split(",")[0]) * 0.6).timeout.connect(func():
				_set_selection(get_tree().get_nodes_in_group("ships").filter(func(s): return s.owner_id == player_id and s.is_alive()), false))
		if OS.get_environment("SL_FLARE_TEST") != "":
			spawn_ship("corvette", player_id, Vector2(60, 0)).order_stop()
			resources[player_id]["minerals"] = 2000.0
			resources[player_id]["spice"] = 500.0
			nearest_starbase(player_id, Vector2.ZERO).enqueue("corvette")
			get_tree().create_timer(1.0, true, false, true).timeout.connect(func(): nearest_starbase(player_id, Vector2.ZERO)._launch("corvette"))
	if OS.get_environment("SL_SHOT_OPEN") == "sunai":
		# Dev: AI ships crossing the sun; one healthy + one damaged AI going
		# after a player ship parked inside the radiation zone.
		var foe: int = 2 if player_id == 1 else 1
		var crossers: Array = []
		var st0: Star = get_tree().get_nodes_in_group("stars")[0]
		var edge: float = st0.orbit_radius + st0.radiation_radius + 160.0
		for i in 3:
			var s := spawn_ship("corvette", foe, Vector2(-edge, -20 + i * 20))
			s.order_move(Vector2(edge, -20 + i * 20))
			crossers.append(s)
		var bait := spawn_ship("cruiser", player_id, Vector2(0, 90))
		bait.order_stop()
		bait.def = bait.def.duplicate()
		bait.def["weapon"] = ""
		bait.max_hp = 1e9
		bait.hp = 1e9
		var healthy := spawn_ship("corvette", foe, Vector2(0, 420))
		healthy.order_attack(bait)
		var hurt := spawn_ship("corvette", foe, Vector2(40, 420))
		hurt.hp = hurt.max_hp * 0.3
		hurt.order_attack(bait)
		var closest := {}
		var tk := Timer.new()
		tk.wait_time = 0.1
		add_child(tk)
		tk.timeout.connect(func():
			var all := crossers + [healthy, hurt]
			for i in all.size():
				if is_instance_valid(all[i]):
					closest[i] = minf(closest.get(i, 1e9), all[i].global_position.length())
					if i >= 3:
						closest["hp%d" % i] = all[i].hp / all[i].max_hp)
		tk.start()
		get_tree().create_timer(25.0).timeout.connect(func():
			for i in 3:
				var cs = crossers[i]
				print("CROSSER %d closest %.0f (zone %.0f) hull %s  at %s" % [i, closest.get(i, -1.0), get_tree().get_nodes_in_group("stars")[0].radiation_radius, ("%.0f%%" % (100.0 * cs.hp / cs.max_hp)) if is_instance_valid(cs) else "dead", str(cs.global_position.round()) if is_instance_valid(cs) else "-"])
			print("HEALTHY closest %.0f hp %.0f%%   HURT closest %.0f hp %.0f%%" % [closest.get(3, -1.0), 100 * closest.get("hp3", 0.0), closest.get(4, -1.0), 100 * closest.get("hp4", 0.0)]))
		center_on(Vector2.ZERO)
	if OS.get_environment("SL_SYSTEM_TEST") != "":
		# Dev: prints the system, then (mode "save") saves after 20s.
		var names := get_tree().get_nodes_in_group("planets").map(func(p): return "%s:%s%s:%d(%dpx,%d fields)" % [p.planet_name, p.kind.trim_prefix("planet_"), p.size_variant, p.owner_id, int(p.radius * 2), p.fields])
		print("SYSTEM %s seed %d  planets %d rocks %d  %s" % [GameState.system_id, GameState.system_seed, names.size(), get_tree().get_nodes_in_group("asteroids").size(), ", ".join(names)])
		get_tree().create_timer(20.0).timeout.connect(func():
			var mine := get_tree().get_nodes_in_group("ships").filter(func(s): return s.is_miner() and s.state != Ship.State.IDLE).size()
			print("AFTER 20s: working miners %d, ships p1 %d p2 %d, p2 minerals %.0f" % [mine, get_tree().get_nodes_in_group("ships").filter(func(s): return s.owner_id == 1).size(), get_tree().get_nodes_in_group("ships").filter(func(s): return s.owner_id == 2).size(), resources[2]["minerals"]])
			if OS.get_environment("SL_SYSTEM_TEST") == "save":
				var path := SaveGame.write(self, "system test")
				print("SAVED ", path))
	if OS.get_environment("SL_SHOT_OPEN") == "nebula":
		# Dev: cruiser in the nebula vs one outside; idle AI corvette inside.
		var neb = get_tree().get_nodes_in_group("nebulae")[0]
		var mid: float = (neb.inner + neb.outer) / 2.0
		var c_in := spawn_ship("cruiser", player_id, Vector2(0, mid))
		c_in.order_stop()
		c_in.shield = c_in.max_shield * 0.5
		var c_out := spawn_ship("cruiser", player_id, Vector2(0, neb.outer + 120.0))
		c_out.order_stop()
		c_out.shield = c_out.max_shield * 0.5
		var foe: int = 2 if player_id == 1 else 1
		var ai_s := spawn_ship("corvette", foe, Vector2(mid, -60))
		ai_s.order_stop()
		print("NEB start: in %.0f/%.0f  out %.0f/%.0f  ai dist %.0f (ring %.0f-%.0f)" % [c_in.shield, c_in.max_shield, c_out.shield, c_out.max_shield, ai_s.global_position.length(), neb.inner, neb.outer])
		get_tree().create_timer(12.0).timeout.connect(func():
			print("NEB 12s: in %.0f/%.0f  out %.0f/%.0f  ai dist %.0f  ai in nebula %s  alarms %d" % [c_in.shield, c_in.max_shield, c_out.shield, c_out.max_shield, ai_s.global_position.length(), str(in_nebula(ai_s.global_position)), alert_sounds]))
		center_on(Vector2(0, mid - 200))
	if OS.get_environment("SL_SHOT_OPEN") == "rings":
		# Dev: ships inside the ring ordered straight out through solid debris.
		var ring = get_tree().get_nodes_in_group("debris_rings")[0]
		var ang := 0.0
		var best := -1.0
		for k in 64:
			var a := TAU * k / 64.0
			var clear := 9.0
			for gp in ring.gaps:
				clear = minf(clear, absf(angle_difference(a, gp)))
			if clear > best:
				best = clear
				ang = a
		var foe: int = 2 if player_id == 1 else 1
		var testers: Array = []
		for i in 4:
			var dir := Vector2.from_angle(ang + (PI if i >= 2 else 0.0) + (i % 2 - 0.5) * 0.04)
			var s := spawn_ship("corvette", player_id if i < 2 else foe, dir * (ring.radius - 150.0))
			s.max_hp = 1e6
			s.hp = 1e6
			s.order_move(dir * (ring.radius + 250.0))
			testers.append(s)
		var stats := {"in_debris": 0}
		var tk := Timer.new()
		tk.wait_time = 0.1
		add_child(tk)
		tk.timeout.connect(func():
			for s in testers:
				if is_instance_valid(s) and is_blocked(s.global_position):
					stats["in_debris"] += 1)
		tk.start()
		get_tree().create_timer(40.0).timeout.connect(func():
			for i in testers.size():
				var s = testers[i]
				if not is_instance_valid(s):
					print("RING ship %d destroyed" % i)
					continue
				print("RING ship %d (%s): dist to goal %.0f, state %s" % [i, "player" if i < 2 else "ai", s.global_position.distance_to(s.move_goal), Ship.State.keys()[s.state]])
			print("RING samples inside debris: %d" % stats["in_debris"]))
		center_on(Vector2.from_angle(ang) * ring.radius)
	if OS.get_environment("SL_SHOT_OPEN") == "storm":
		# Dev: a corvette parked on an arm vs one well away; logs stage + speed.
		var storm = get_tree().get_nodes_in_group("storms")[0]
		var t_on := 60.0
		var arm_dir := Vector2.from_angle(storm.arm_angle(t_on))
		var off_dir := Vector2.from_angle(storm.arm_angle(t_on) + PI / 2.0)
		var a := spawn_ship("corvette", player_id, arm_dir * 800.0)
		var b := spawn_ship("corvette", player_id, off_dir * 800.0)
		for s in [a, b]:
			s.order_stop()
			s.max_hp = 1e6
			s.hp = 1e6
		for t in [5.0, 50.0, 60.0, 80.0]:
			get_tree().create_timer(t).timeout.connect(func():
				print("STORM t=%.0f stage %s  in-arm ship speed %.0f (in storm %s)  control speed %.0f" % [now(), storm.stage(now()), a.max_speed(), str(in_storm(a.global_position)), b.max_speed()]))
		center_on(arm_dir * 800.0)
	if OS.get_environment("SL_NEURAL") != "":
		get_tree().create_timer(58.0).timeout.connect(func():
			var nn = ai._state.get(2, {}).get("nn")
			print("NEURAL side 2 active: %s  actions: %s" % [str(nn != null), str(nn.counts) if nn else "-"]))
	if OS.get_environment("SL_STRESS") != "":
		# Dev benchmark: N warships per side clash away from the star; logs real
		# frame times (run headless with --fixed-fps 60 so frames go flat out).
		var n := int(OS.get_environment("SL_STRESS"))
		var kinds := ["corvette", "corvette", "destroyer", "cruiser"]
		for i in n:
			var off := Vector2(i % 12 * 18, i / 12 * 18)
			spawn_ship(kinds[i % 4], 1, Vector2(-900, -780) + off).order_attack_move(Vector2(600, -600))
			spawn_ship(kinds[i % 4], 2, Vector2(700, -780) + off).order_attack_move(Vector2(-700, -600))
		var frames: Array = []
		var last := [Time.get_ticks_usec()]
		var on_frame := func():
			var t := Time.get_ticks_usec()
			if now() > 3.0:
				frames.append((t - last[0]) / 1000.0)
			last[0] = t
		get_tree().process_frame.connect(on_frame)
		get_tree().create_timer(18.0).timeout.connect(func():
			frames.sort()
			var sum := 0.0
			for f in frames:
				sum += f
			print("STRESS ships %d  frames %d  avg %.2f ms  p95 %.2f ms  max %.2f ms  projectiles %d" % [get_tree().get_nodes_in_group("ships").size(), frames.size(), sum / maxf(frames.size(), 1), frames[int(frames.size() * 0.95)] if frames.size() > 0 else 0.0, frames[-1] if frames.size() > 0 else 0.0, fx_root.get_child_count()])
			get_tree().quit())
	if OS.get_environment("SL_SHOT_OPEN") == "shots":
		# Dev: shot colors. Rows of generalist, Ion, Breacher and Reaver corvettes
		# fire at enemy destroyers.
		var foe := 3 - player_id
		var kinds := ["corvette", "plasma_corvette", "breacher_corvette", "reaver_corvette", "slip_corvette", "disruptor_corvette"] if OS.get_environment("SL_SHOTS_ALL") != "" else ["corvette", "plasma_corvette", "breacher_corvette", "reaver_corvette"]
		for i in kinds.size():
			var y := (420.0 if kinds.size() > 4 else 560.0) + i * 70.0
			for j in 8:
				spawn_ship(kinds[i], player_id, Vector2(-150 + (j % 4) * 18, y - 12 + (j / 4) * 24)).order_stop()
			var t := spawn_ship("destroyer", foe, Vector2(-20, y))
			t.max_hp = 1e6
			t.hp = 1e6
			t.order_stop()
	if OS.get_environment("SL_SHOT_OPEN") == "sbcycle":
		var home2 := nearest_starbase(player_id, Vector2.ZERO)
		var second := found_starbase(player_id, home2.global_position + Vector2(700, 0))
		second.under_construction = false
		second.construct_progress = 999.0
		var where := func(): return "%.0f,%.0f" % [camera.global_position.x, camera.global_position.y]
		center_on(Vector2(1500, 900))
		cycle_starbase()
		var a: String = where.call()
		cycle_starbase()
		var b: String = where.call()
		cycle_starbase()
		var c2: String = where.call()
		var cv := spawn_ship("corvette", player_id, home2.global_position + Vector2(0, 80))
		_set_selection([cv], false)
		var e1 := InputEventKey.new()
		e1.keycode = KEY_ESCAPE
		_handle_key(e1)
		var cleared := selection.is_empty() and not hud._pause.visible
		_handle_key(e1)
		print("ESC selection cleared=%s then menu=%s" % [str(cleared), str(hud._pause.visible)])
		hud.show_pause(false)
		print("SBCYCLE main=%.0f,%.0f second=%.0f,%.0f -> %s then %s then %s" % [home2.global_position.x, home2.global_position.y, second.global_position.x, second.global_position.y, a, b, c2])
	if OS.get_environment("SL_SHOT_OPEN") == "marks":
		# Dev: one row per class, Mk I to Mk IV left to right.
		var c0 := Vector2(-520, -260)
		for row in [["corvette", 0], ["destroyer", 1], ["cruiser", 2]]:
			for lvl in 4:
				var s := spawn_ship(str(row[0]), player_id, c0 + Vector2(lvl * 230, int(row[1]) * 170))
				s.order_stop()
				s.set_meta("force_mark", lvl)
		# Fake each ship's mark by handing it that mark's hull directly.
		await get_tree().process_frame
		for s in get_tree().get_nodes_in_group("ships"):
			if not s.has_meta("force_mark"):
				continue
			var lvl: int = s.get_meta("force_mark")
			var mk: Sprite2D = s.get_node("Mark")
			mk.texture = Defs.tex("ship_mark_%s_%d" % [s.ship_type, clampi(lvl, 1, 3)]) if lvl > 0 else null
			mk.scale = Vector2.ONE / Defs.ART_SCALE
			mk.visible = lvl > 0
		center_on(c0 + Vector2(345, 170))
	if OS.get_environment("SL_SHOT_OPEN") == "ctorpanel":
		# Dev: the Constructor's build options as square icon buttons.
		var hb4 := nearest_starbase(player_id, Vector2.ZERO)
		researched[player_id]["depots"] = true
		var c4 := spawn_ship("constructor", player_id, hb4.global_position + Vector2(90, 90))
		_set_selection([c4], false)
	if OS.get_environment("SL_SHOT_OPEN") == "sbbuild":
		# Dev: a Constructor founds a starbase. With SL_BROKE=1 the treasury is
		# emptied so the site stalls, then refilled to prove it resumes.
		var hb3 := nearest_starbase(player_id, Vector2.ZERO)
		var spot3 := hb3.global_position + Vector2(620, 240)
		var con3 := spawn_ship("constructor", player_id, hb3.global_position + Vector2(120, 60))
		print("SBBUILD site=%s problem='%s'" % [str(spot3.round()), site_problem("starbase", spot3)])
		con3.order_build_starbase(spot3)
		_set_selection([con3], false)
		center_on(spot3)
		if OS.get_environment("SL_BROKE") != "":
			resources[player_id]["minerals"] = 0.0
			resources[player_id]["spice"] = 0.0
		var seen := {"built": false}
		for t in [10.0, 25.0, 45.0, 70.0, 95.0]:
			get_tree().create_timer(t).timeout.connect(func():
				var sites := get_tree().get_nodes_in_group("starbases").filter(func(s): return s.owner_id == player_id and s != hb3)
				var site = sites[0] if sites.size() > 0 else null
				if site == null:
					print("SBBUILD t=%d no site yet (constructor state=%s)" % [int(t), Ship.State.keys()[con3.state] if is_instance_valid(con3) else "gone"])
					return
				print("SBBUILD t=%d progress=%.0f/%ds stalled=%s hp=%d/%d under_construction=%s minerals=%d" % [
					int(t), site.construct_progress, int(Defs.STARBASE["build_time"]), str(site.build_stalled),
					int(site.hp), int(site.max_hp), str(site.under_construction), int(resources[player_id]["minerals"])])
				if not site.under_construction and not seen["built"]:
					seen["built"] = true
					print("SBBUILD finished, can_queue corvette='%s'" % site.can_queue("corvette")))
		if OS.get_environment("SL_BROKE") != "":
			get_tree().create_timer(30.0).timeout.connect(func():
				resources[player_id]["minerals"] = 900.0
				resources[player_id]["spice"] = 200.0
				print("SBBUILD treasury refilled at t=30"))
	if OS.get_environment("SL_SHOT_OPEN") == "placering":
		# Dev: the placement ring is the same rule for every construct.
		var hb2 := nearest_starbase(player_id, Vector2.ZERO)
		for kind in ["starbase", "depot", "station"]:
			print("RINGS %-9s radius=%d ring=%d" % [kind, int(Defs.construct_def(kind)["radius"]), int(Defs.placement_ring(kind))])
		var base_ring := Defs.placement_ring("starbase")
		for kind2 in ["starbase", "depot", "station"]:
			var need: float = base_ring + Defs.placement_ring(kind2)
			var just_in := hb2.global_position + Vector2(need + 6.0, 0)
			var just_out := hb2.global_position + Vector2(need - 6.0, 0)
			print("RINGS %-9s beside starbase: at %dpx ok=%s | at %dpx ok=%s (want true/false)" % [
				kind2, int(need + 6.0), str(site_problem(kind2, just_in) == ""),
				int(need - 6.0), str(site_problem(kind2, just_out) == "")])
	if OS.get_environment("SL_SHOT_OPEN") == "station":
		# Dev: a Constructor builds a Mining Station beside a far belt, then a
		# barge unloads there instead of flying home.
		var hs := nearest_starbase(player_id, Vector2.ZERO)
		var far := nearest_asteroid(hs.global_position + Vector2(1200, 0), 3000.0, "minerals", null)
		var spot: Vector2 = (far.global_position + Vector2(-120, 0)) if far else hs.global_position + Vector2(900, 0)
		var con := spawn_ship("constructor", player_id, spot + Vector2(-60, 0))
		con.order_build_station(spot)
		var bg2 := spawn_ship("miner", player_id, spot + Vector2(40, 40))
		if far:
			bg2.order_mine(far)
		print("STATION site problem=%s" % str(station_site_problem(spot)))
		get_tree().create_timer(26.0).timeout.connect(func():
			var sts := get_tree().get_nodes_in_group("mining_stations")
			var st = sts[0] if sts.size() > 0 else null
			if st:
				print("STATION built=%s hp=%d/%d open=%s" % [str(not st.under_construction), int(st.hp), int(st.max_hp), str(st.is_open())])
				if is_instance_valid(bg2):
					var drop := nearest_dropoff(player_id, bg2.global_position)
					print("STATION barge state=%s cargo=%d nearest drop-off is station=%s (%.0f px vs starbase %.0f px)" % [
						Ship.State.keys()[bg2.state], bg2.cargo, str(drop == st),
						bg2.global_position.distance_to(st.global_position),
						bg2.global_position.distance_to(hs.global_position)]))
		get_tree().create_timer(70.0).timeout.connect(func():
			print("STATION minerals=%d (deliveries land)" % int(resources[player_id]["minerals"])))
	if OS.get_environment("SL_SHOT_OPEN") == "rclose":
		# Dev: the research screen closes on Esc and on a click outside it.
		hud.toggle_research()
		await get_tree().process_frame
		print("RCLOSE opened=%s" % str(hud.research_open()))
		var out := InputEventMouseButton.new()
		out.button_index = MOUSE_BUTTON_LEFT
		out.pressed = true
		out.position = Vector2(60, 60)
		hud._research_modal.gui_input.emit(out)
		await get_tree().process_frame
		print("RCLOSE after outside click=%s" % str(hud.research_open()))
		hud.toggle_research()
		await get_tree().process_frame
		var inside := InputEventMouseButton.new()
		inside.button_index = MOUSE_BUTTON_LEFT
		inside.pressed = true
		inside.position = get_viewport().get_visible_rect().size / 2.0
		var panel: Control = hud._research_modal.get_child(0).get_child(0)
		print("RCLOSE panel rect=%s center click inside=%s" % [str(panel.get_global_rect()), str(panel.get_global_rect().has_point(inside.position))])
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		_handle_key(esc)
		await get_tree().process_frame
		print("RCLOSE after esc=%s" % str(hud.research_open()))
	if OS.get_environment("SL_SHOT_OPEN") == "qmini":
		# Dev: minimap right-clicks, plain and shift-held, must behave like
		# right-clicks on the map.
		var hb := nearest_starbase(player_id, Vector2.ZERO)
		var sh := spawn_ship("corvette", player_id, hb.global_position + Vector2(-100, 100))
		_set_selection([sh], false)
		await get_tree().process_frame
		var mini: Minimap = hud.minimap
		var to_ui := func(world: Vector2) -> Vector2:
			return mini._map_to_ui(world)
		var a := hb.global_position + Vector2(400, 0)
		var b := hb.global_position + Vector2(400, 400)
		var e1 := InputEventMouseButton.new()
		e1.button_index = MOUSE_BUTTON_RIGHT
		e1.pressed = true
		e1.position = to_ui.call(a)
		mini._gui_input(e1)
		var after_plain := sh.order_queue.size()
		var e2 := InputEventMouseButton.new()
		e2.button_index = MOUSE_BUTTON_RIGHT
		e2.pressed = true
		e2.shift_pressed = true
		e2.position = to_ui.call(b)
		mini._gui_input(e2)
		print("QMINI plain: state=%s queue=%d | after shift: queue=%d" % [
			Ship.State.keys()[sh.state], after_plain, sh.order_queue.size()])
		var pts := sh.queued_points()
		if pts.size() > 0:
			print("QMINI queued point err=%.0f px (want ~0)" % pts[0].distance_to(b))
		# Ctrl+Shift queues an attack-move; a rock target queues a mine order;
		# a multi-ship selection queues one leg each, in formation.
		var e3 := InputEventMouseButton.new()
		e3.button_index = MOUSE_BUTTON_RIGHT
		e3.pressed = true
		e3.shift_pressed = true
		e3.ctrl_pressed = true
		e3.position = to_ui.call(hb.global_position + Vector2(-600, 200))
		mini._gui_input(e3)
		print("QMINI ctrl+shift: queue=%d last=%s" % [sh.order_queue.size(), str(sh.order_queue[-1][0])])
		var rock2 := nearest_asteroid(hb.global_position, 2500.0, "minerals", null)
		var bg := spawn_ship("miner", player_id, hb.global_position + Vector2(60, 60))
		_set_selection([bg], false)
		var e4 := InputEventMouseButton.new()
		e4.button_index = MOUSE_BUTTON_RIGHT
		e4.pressed = true
		e4.position = to_ui.call(hb.global_position + Vector2(-300, -300))
		mini._gui_input(e4)
		if rock2:
			var e5 := InputEventMouseButton.new()
			e5.button_index = MOUSE_BUTTON_RIGHT
			e5.pressed = true
			e5.shift_pressed = true
			e5.position = to_ui.call(rock2.global_position)
			mini._gui_input(e5)
			print("QMINI rock leg: queue=%d kind=%s hits_rock=%s" % [
				bg.order_queue.size(), str(bg.order_queue[-1][0]),
				str(bg.order_queue[-1][1][0] == rock2 if bg.order_queue[-1][1].size() > 0 else false)])
		var t1 := spawn_ship("corvette", player_id, hb.global_position + Vector2(-60, 300))
		var t2 := spawn_ship("corvette", player_id, hb.global_position + Vector2(20, 300))
		_set_selection([t1, t2], false)
		var e6 := InputEventMouseButton.new()
		e6.button_index = MOUSE_BUTTON_RIGHT
		e6.pressed = true
		e6.position = to_ui.call(hb.global_position + Vector2(500, 500))
		mini._gui_input(e6)
		var e7 := InputEventMouseButton.new()
		e7.button_index = MOUSE_BUTTON_RIGHT
		e7.pressed = true
		e7.shift_pressed = true
		e7.position = to_ui.call(hb.global_position + Vector2(700, 300))
		mini._gui_input(e7)
		var p1 := t1.queued_points()
		var p2 := t2.queued_points()
		print("QMINI pair: queues=%d,%d spread=%.0f px (formation, not stacked)" % [
			t1.order_queue.size(), t2.order_queue.size(),
			p1[0].distance_to(p2[0]) if p1.size() > 0 and p2.size() > 0 else -1.0])
	if OS.get_environment("SL_SHOT_OPEN") == "qfull":
		# Dev: a long mixed chain, a save/restore round trip, and the rules
		# around clearing and overriding a queue.
		var hq := nearest_starbase(player_id, Vector2.ZERO)
		var c1 := hq.global_position
		var rock1 := nearest_asteroid(c1, 2500.0, "minerals", null)
		var m1 := spawn_ship("miner", player_id, c1 + Vector2(-120, 160))
		m1.order_move(c1 + Vector2(-260, 220))
		m1.do_or_queue(true, "order_move", [c1 + Vector2(-80, 320)])
		if rock1:
			m1.do_or_queue(true, "order_mine", [rock1])
		m1.do_or_queue(true, "order_return", [])
		print("QFULL chain legs=%d kinds=%s" % [m1.order_queue.size(), str(m1.order_queue.map(func(o): return o[0]))])
		# A plain order wipes the queue; T wipes it too.
		var m2 := spawn_ship("miner", player_id, c1 + Vector2(120, 160))
		m2.order_move(c1 + Vector2(200, 200))
		m2.do_or_queue(true, "order_move", [c1 + Vector2(300, 300)])
		var before2 := m2.order_queue.size()
		m2.do_or_queue(false, "order_move", [c1 + Vector2(-200, -200)])
		print("QFULL plain order clears: %d -> %d" % [before2, m2.order_queue.size()])
		var m3 := spawn_ship("miner", player_id, c1 + Vector2(160, -160))
		m3.order_move(c1 + Vector2(240, -200))
		m3.do_or_queue(true, "order_move", [c1 + Vector2(320, -260)])
		var before3 := m3.order_queue.size()
		m3.order_stop()
		print("QFULL stop clears: %d -> %d, state=%s" % [before3, m3.order_queue.size(), Ship.State.keys()[m3.state]])
		# A leg whose target dies is skipped rather than stalling the ship.
		var m4 := spawn_ship("miner", player_id, c1 + Vector2(-160, -160))
		var doomed := spawn_ship("corvette", 3 - player_id, c1 + Vector2(-400, -400))
		m4.order_move(c1 + Vector2(-200, -200))
		m4.do_or_queue(true, "order_attack", [doomed])
		m4.do_or_queue(true, "order_move", [c1 + Vector2(-300, -100)])
		doomed.queue_free()
		# Save/restore round trip on the chain.
		var snap := SaveGame.capture(self, "qfull")
		var saved: Array = snap["ships"].map(func(x): return x.get("queue", []).size())
		print("QFULL saved queues=%s" % str(saved.filter(func(n): return n > 0)))
		get_tree().create_timer(18.0).timeout.connect(func():
			if is_instance_valid(m1) and is_instance_valid(m4):
				print("QFULL t=18 chain state=%s left=%d | dead-target ship state=%s left=%d" % [
					Ship.State.keys()[m1.state], m1.order_queue.size(),
					Ship.State.keys()[m4.state], m4.order_queue.size()]))
	if OS.get_environment("SL_SHOT_OPEN") == "qtest":
		# Dev: waypoints in a known square around the ship, with the screen
		# position of each pip printed so a capture can be checked by pixel.
		var home2 := nearest_starbase(player_id, Vector2.ZERO)
		var at := home2.global_position + Vector2(0, 420)
		var t0 := spawn_ship("corvette", player_id, at)
		t0.order_move(at + Vector2(120, 0))
		for p in [Vector2(120, 120), Vector2(-120, 120), Vector2(-120, 0)]:
			t0.do_or_queue(true, "order_move", [at + p])
		_set_selection([t0], false)
		center_on(at)
		await get_tree().process_frame
		await get_tree().process_frame
		var xf := get_viewport().get_canvas_transform()
		for p in t0.queued_points():
			var sp: Vector2 = xf * p
			print("QTEST pip world=%s screen=%d,%d" % [str(p.round()), int(sp.x), int(sp.y)])
		print("QTEST ship screen=%s goal=%s legs=%d" % [str((xf * t0.global_position).round()), str((xf * t0.move_goal).round()), t0.order_queue.size()])
		# Save and reload the queue to prove it survives a round trip.
		var sd := SaveGame.capture(self, "qtest")
		var legs: int = sd["ships"].filter(func(x): return x.get("queue", []).size() > 0).size()
		print("QTEST saved ships with queues=%d, first queue=%s" % [legs, str(sd["ships"].filter(func(x): return x.get("queue", []).size() > 0).map(func(x): return x["queue"].size()))])
	if OS.get_environment("SL_SHOT_OPEN") == "queue":
		# Dev: shift-queued orders. A barge gets three waypoints plus a rock
		# to mine; a corvette gets a patrol. Prints the queue as it drains.
		var home := nearest_starbase(player_id, Vector2.ZERO)
		var c0 := home.global_position
		var barge := spawn_ship("miner", player_id, c0 + Vector2(-160, 120))
		var rock := nearest_asteroid(c0, 2000.0, "minerals", null)
		barge.order_move(c0 + Vector2(-320, 40))
		for p in [Vector2(-260, 260), Vector2(-40, 320), Vector2(220, 240)]:
			barge.do_or_queue(true, "order_move", [c0 + p])
		if rock:
			barge.do_or_queue(true, "order_mine", [rock])
		var cor := spawn_ship("corvette", player_id, c0 + Vector2(200, -160))
		cor.order_move(c0 + Vector2(340, -60))
		for p in [Vector2(420, 120), Vector2(180, 200)]:
			cor.do_or_queue(true, "order_attack_move", [c0 + p])
		_set_selection([barge, cor], false)
		center_on(c0 + Vector2(60, 120))
		await get_tree().process_frame
		print("QUEUE barge=%d legs, corvette=%d legs, barge points=%s" % [
			barge.order_queue.size(), cor.order_queue.size(), str(barge.queued_points().size())])
		print("QUEUE barge pos=%s goal=%s rot=%.2f scale=%s" % [str(barge.global_position.round()), str(barge.move_goal.round()), barge.global_rotation, str(barge.global_scale)])
		for p in barge.queued_points():
			print("QUEUE   wp global=%s local=%s" % [str(p.round()), str(barge.to_local(p).round())])
		# Manual drop-off: a loaded barge told to visit the starbase unloads.
		var hauler := spawn_ship("miner", player_id, c0 + Vector2(240, -240))
		hauler.cargo = 7
		hauler.cargo_type = "minerals"
		_set_selection([hauler], false)
		_issue_command(home.global_position, false, false)
		print("QUEUE dropoff state=%s cargo=%d" % [Ship.State.keys()[hauler.state], hauler.cargo])
		get_tree().create_timer(20.0).timeout.connect(func():
			if is_instance_valid(hauler):
				print("QUEUE dropoff t=20 state=%s cargo=%d" % [Ship.State.keys()[hauler.state], hauler.cargo]))
		_set_selection([barge, cor], false)
		for t in [6.0, 14.0, 26.0, 40.0]:
			get_tree().create_timer(t).timeout.connect(func():
				if is_instance_valid(barge) and is_instance_valid(cor):
					print("QUEUE t=%ds barge state=%s left=%d | corvette state=%s left=%d" % [
						int(t), Ship.State.keys()[barge.state], barge.order_queue.size(),
						Ship.State.keys()[cor.state], cor.order_queue.size()]))
	if OS.get_environment("SL_SHOT_OPEN") == "keys":
		# Dev: the panel grid keys press the buttons they are drawn on.
		var sb0 := nearest_starbase(player_id, Vector2.ZERO)
		_set_selection([sb0], false)
		await get_tree().process_frame
		var before := sb0.queue.size()
		var okq := hud.press_panel_key(KEY_Q)
		var okd := hud.press_panel_key(KEY_D)
		await get_tree().process_frame
		print("KEYS starbase Q=%s D=%s queue %d -> %s" % [str(okq), str(okd), before, str(sb0.queue)])
		var con2 := spawn_ship("constructor", player_id, sb0.global_position + Vector2(60, 0))
		_set_selection([con2], false)
		await get_tree().process_frame
		var okw := hud.press_panel_key(KEY_W)
		print("KEYS constructor W=%s placing_depot=%s variant=%s" % [str(okw), str(placing_depot), placing_depot_variant])
		placing_depot = false
		var hp3: Planet = get_tree().get_nodes_in_group("planets").filter(func(p): return p.owner_id == player_id)[0]
		_focus_planet(hp3)
		selection_changed.emit()
		await get_tree().process_frame
		print("KEYS build picker F=%s" % str(hud.planet_view.open_build_picker()))
		_set_selection([], false)
		clear_planet_focus()
		await get_tree().process_frame
		_handle_key(InputEventKey.new())
		select_all_of_type("miner")
		print("KEYS select-all miners: %d selected, key maps to %s" % [selection.size(), hud.build_type_for_key(KEY_Q)])
		# Rebinding: panel button 1 moved to key 1, then reset to defaults.
		GameState.hotkeys = Defs.default_hotkeys()
		GameState.hotkeys["panel1"] = KEY_J
		_set_selection([sb0], false)
		await get_tree().process_frame
		var q_after := hud.press_panel_key(KEY_Q)
		var j_after := hud.press_panel_key(KEY_J)
		print("KEYS rebound panel1 to J: Q=%s J=%s queue=%s" % [str(q_after), str(j_after), str(sb0.queue)])
		GameState.hotkeys = {}
		_set_selection([sb0], false)
		await get_tree().process_frame
		print("KEYS after reset: Q=%s first key=%s" % [str(hud.press_panel_key(KEY_Q)), OS.get_keycode_string(HUD.panel_keys()[0])])
	if OS.get_environment("SL_SHOT_OPEN") == "depot":
		# Dev: a Constructor builds a Weapons Depot, two corvettes refit to Slip,
		# then a refit of a specialist is refused.
		var home := nearest_starbase(player_id, Vector2.ZERO)
		resources[player_id]["minerals"] = 2000.0
		resources[player_id]["spice"] = 200.0
		var site: Vector2 = ai._depot_site(home.global_position, self)
		var con := spawn_ship("constructor", player_id, home.global_position + Vector2(50, 0))
		con.order_build_depot(site, "plasma")
		var cvs: Array = []
		for i in 3:
			cvs.append(spawn_ship("corvette", player_id, home.global_position + Vector2(-40, 30 * i)))
		get_tree().create_timer(45.0).timeout.connect(func():
			var dep := nearest_depot(player_id, site, "plasma")
			print("DEPOT finished: ", dep != null, " type ", dep.label() if dep else "-")
			for c in cvs:
				c.order_refit("plasma", dep)
			_set_selection([dep], false))
		get_tree().create_timer(58.0).timeout.connect(func():
			var dep2 := nearest_depot(player_id, site, "plasma")
			print("DEPOT docked: ", dep2.bays.size(), " ships hidden: ", cvs.map(func(c): return not c.visible))
			dep2.cancel(cvs[2])
			print("DEPOT after cancel: bays ", dep2.bays.size(), " ejected type ", cvs[2].ship_type, " docked ", cvs[2].docked))
		get_tree().create_timer(85.0).timeout.connect(func():
			print("DEPOT refitted: ", cvs.map(func(c): return c.ship_type if is_instance_valid(c) else "gone"), "  can refit again: ", cvs[0].can_refit("slip"))
			center_on(site))
	if OS.get_environment("SL_SHOT_OPEN") == "variants":
		# Dev: base damage each variant needs to destroy each generalist,
		# relative to a generalist attacker (1.00 = same, lower = faster).
		var line := "VARIANTS %-10s" % "target"
		for v in Defs.VARIANTS:
			line += "%10s" % v
		print(line)
		for tgt in ["corvette", "destroyer", "cruiser"]:
			var row := "VARIANTS %-10s" % tgt
			var gen := 0.0
			for v in [""] + Defs.VARIANTS.keys():
				var s := spawn_ship(tgt, 3 - player_id, Vector2(-1500, -900))
				var prof := Defs.damage_profile({"variant": v}) if v != "" else {}
				var per: float = Defs.VARIANTS[v]["damage"] if v != "" else 1.0
				var used := 0.0
				while s.hp > 0.0:
					s.take_damage(per, null, prof)
					used += 1.0
				if v == "":
					gen = used
				else:
					row += "%10.2f" % (used / gen)
			print(row)
	if OS.get_environment("SL_SHOT_OPEN") == "armor":
		# Dev: damage runs shields -> armor -> hull; a Tender restores hull, then armor.
		var d := spawn_ship("destroyer", player_id, Vector2(-1400, 0))
		d.order_stop()
		var show := func(tag): print("ARMOR %-10s shield %3d  armor %3d  hull %3d" % [tag, d.shield, d.armor, d.hp])
		show.call("new")
		for hit in [60, 60, 60, 60]:
			d.take_damage(hit)
			show.call("-%d" % hit)
		var t := spawn_ship("tender", player_id, Vector2(-1440, 30))
		t.order_stop()
		get_tree().create_timer(12.0).timeout.connect(func(): show.call("repaired"))
	if OS.get_environment("SL_SHOT_OPEN") == "skim":
		# Dev: a skimmer harvesting spice gas in the nearest spice nebula.
		var home := nearest_starbase(player_id, Vector2.ZERO)
		var neb: Node2D = get_tree().get_nodes_in_group("nebulae")[0]
		var spot: Vector2 = neb.heart_toward(home.global_position)
		var sk := spawn_ship("skimmer", player_id, home.global_position + Vector2(40, 40))
		sk.order_mine(nebula_pocket_at(spot))
		var trips := [0]
		var last := [0]
		var poll := func():
			if not is_instance_valid(sk):
				return
			if last[0] > 0 and sk.cargo == 0:
				trips[0] += 1
			last[0] = sk.cargo
		get_tree().physics_frame.connect(poll)
		get_tree().create_timer(float(OS.get_environment("SL_SHOT").split(",")[0]) - 0.2).timeout.connect(func():
			print("SKIM trips home %d, state %s, cargo %d %s, spot %.0f px from home" % [trips[0], Ship.State.keys()[sk.state], sk.cargo, sk.cargo_type, spot.distance_to(home.global_position)]))
	if OS.get_environment("SL_SHOT_OPEN") == "jobs":
		# Dev: job ships at work. Heat Shield + 3 corvettes inside the sun's
		# radiation (right) vs 3 unprotected corvettes (left); a Tender beside
		# three half-hull destroyers; a Scout dropping a beacon.
		var star: Node2D = get_tree().get_nodes_in_group("stars")[0]
		var rr: float = star.radiation_radius - 50.0
		var hs := spawn_ship("heatshield", player_id, star.global_position + Vector2(rr, 0))
		var shielded: Array = []
		var bare: Array = []
		for i in 3:
			shielded.append(spawn_ship("corvette", player_id, star.global_position + Vector2(rr, -30 + i * 30)))
			bare.append(spawn_ship("corvette", player_id, star.global_position + Vector2(-rr, -30 + i * 30)))
		var tender := spawn_ship("tender", player_id, star.global_position + Vector2(0, 520))
		var hurt: Array = []
		for i in 3:
			var d := spawn_ship("destroyer", player_id, star.global_position + Vector2(-60 + i * 60, 470))
			d.hp = d.max_hp * 0.5
			hurt.append(d)
		var sc := spawn_ship("scout", player_id, star.global_position + Vector2(0, -420))
		for s in shielded + bare + hurt + [hs, tender, sc]:
			s.order_stop()
		get_tree().create_timer(0.5).timeout.connect(func(): print("JOBS beacon: ", Abilities.use(sc)))
		get_tree().create_timer(float(OS.get_environment("SL_SHOT").split(",")[0]) - 0.2).timeout.connect(func():
			var f := func(arr): return ", ".join(arr.map(func(s): return "%d/%d" % [int(s.hp), int(s.max_hp)]))
			print("JOBS shielded corvettes %s | bare corvettes %s | repaired destroyers %s | beacons %d" % [f.call(shielded), f.call(bare), f.call(hurt), get_tree().get_nodes_in_group("beacons").size()]))
	if OS.get_environment("SL_SHOT_OPEN") == "sun":
		var c1 := spawn_ship("corvette", player_id, Vector2(52, 0))
		c1.order_stop()
		var c2 := spawn_ship("corvette", player_id, Vector2(-150, 0))
		c2.order_stop()
	if OS.get_environment("SL_SHOT_OPEN") == "rock":
		# A barge working the rock, so the harvesting beam is in the capture.
		# It is ordered out HERE rather than in the match below, which only
		# runs once the capture timer has already elapsed.
		var rk0 := nearest_asteroid(nearest_starbase(player_id, Vector2.ZERO).global_position, 2000.0)
		var bg0 := spawn_ship("miner", player_id, rk0.global_position + Vector2(90, 40))
		bg0.order_mine(rk0)
		if OS.get_environment("SL_DROPOFF") != "":
			# Dev: a loaded barge sent to a station that is NOT the nearest
			# drop-off, to prove a hand-picked one is honoured.
			var st9 := found_station(player_id, rk0.global_position + Vector2(420, -260))
			st9.under_construction = false
			st9.hp = st9.max_hp
			var hauler := spawn_ship("miner", player_id, rk0.global_position + Vector2(60, -40))
			hauler.cargo_type = "minerals"
			hauler.cargo = hauler.cargo_cap()
			hauler.order_return(st9)
			get_tree().create_timer(maxf(float(OS.get_environment("SL_SHOT").split(",")[0]) - 0.3, 0.5)).timeout.connect(func():
				print("DROPOFF hauler state=%s cargo=%d dist_to_station=%.0f dist_to_base=%.0f" % [Ship.State.keys()[hauler.state], hauler.cargo,
					hauler.global_position.distance_to(st9.global_position),
					hauler.global_position.distance_to(nearest_starbase(player_id, hauler.global_position).global_position)]))
		# A second barge told to stop: it should find its own work within
		# Ship.IDLE_RETASK seconds.
		var idle0 := spawn_ship("miner", player_id, rk0.global_position + Vector2(-260, 180))
		var held0 := spawn_ship("miner", player_id, rk0.global_position + Vector2(-320, 240))
		held0.order_stop()
		get_tree().create_timer(maxf(float(OS.get_environment("SL_SHOT").split(",")[0]) - 0.3, 0.5)).timeout.connect(func():
			print("ROCK barge state=%s dist=%.0f vel=%.0f on-bearing=%s cargo=%d" % [Ship.State.keys()[bg0.state],
				bg0.global_position.distance_to(rk0.global_position), bg0.velocity.length(),
				str(bg0.bears_on(rk0.global_position, Ship.HARVEST_ARC)), bg0.cargo])
			print("ROCK idle barge state=%s target=%s | held barge state=%s held=%s" % [Ship.State.keys()[idle0.state],
				"none" if not is_instance_valid(idle0.mine_target) else str(idle0.mine_target.name),
				Ship.State.keys()[held0.state], str(held0.held)]))
	if OS.get_environment("SL_SHOT_OPEN") == "gas":
		researched[player_id]["gas_skimming"] = true
		resources[player_id]["minerals"] = 2000.0
		resources[player_id]["spice"] = 200.0
		var gas_p: Planet = get_tree().get_nodes_in_group("planets").filter(func(p): return not p.is_habitable())[0]
		gas_p.amount = 12
		var sk := spawn_ship("skimmer", player_id, gas_p.global_position + Vector2(-260, 120))
		sk.order_mine(gas_p)
		center_on(gas_p.global_position)
	if OS.get_environment("SL_SHOT_OPEN") == "research":
		queue_research(player_id, "ion_cannons")
		queue_research(player_id, "particle_lances")
	if OS.get_environment("SL_SHOT_OPEN") == "sbdps":
		# Dev: park enemy corvettes inside starbase range and report how much
		# damage the starbase lands, to compare across game speeds.
		var sb9 := nearest_starbase(player_id, Vector2.ZERO)
		for i in 3:
			var e9 := spawn_ship("corvette", 2 if player_id == 1 else 1, sb9.global_position + Vector2(170 + i * 30, 60))
			e9.order_stop()
			e9.set_meta("sbtest", true)
		center_on(sb9.global_position)
	if OS.get_environment("SL_SHOT_OPEN") == "carrier":
		# Dev: a carrier of the requested mark with damaged corvettes docking.
		var lvl9: int = int(OS.get_environment("SL_CARRIER_MARK"))
		researched[player_id]["carriers"] = true
		for mk9 in range(2, 2 + lvl9):
			researched[player_id]["carrier_mk%d" % mk9] = true
		var c9 := spawn_ship("carrier", player_id, Vector2(-200, 0))
		c9.order_stop()
		for i9 in 6:
			var cv := spawn_ship("corvette", player_id, Vector2(-40 + i9 * 40, -160 + i9 * 60))
			cv.hp = cv.max_hp * 0.3
			cv.armor = 0.0
			cv.order_dock(c9)
		# An enemy off the bow so the turrets have something to swing onto.
		var foe9 := spawn_ship("corvette", 2 if player_id == 1 else 1, Vector2(-200, -220))
		foe9.order_stop()
		center_on(Vector2(-200, 0))
		# Selected, so the capture shows the hangar panel too.
		_set_selection([c9], false)
		# Dev: prove the bays survive a save. Prints what is docked now and
		# writes a save; reload it with SL_LOAD=<path> to see them come back.
		get_tree().create_timer(float(OS.get_environment("SL_SHOT").split(",")[0]) - 0.3).timeout.connect(func():
			var in_bays := get_tree().get_nodes_in_group("ships").filter(func(x): return x.state == Ship.State.DOCKED or x.state == Ship.State.DOCK_GO)
			print("CARRIER docked/inbound %d, bays filled %d" % [in_bays.size(), c9.bay_craft.filter(func(x): return x != null and is_instance_valid(x)).size()])
			if OS.get_environment("SL_SAVE_TEST") != "":
				print("CARRIER saved ", SaveGame.write(self, "carrier dock test")))
	if OS.get_environment("SL_SHOT_OPEN") == "resbtn":
		# Dev: the research button while a project is running (green glow).
		queue_research(player_id, "ion_cannons")
	await get_tree().create_timer(secs).timeout
	if OS.get_environment("SL_SHOT_OPEN") == "sbdps":
		var tot := 0.0
		var full: float = 3.0 * (Defs.SHIPS["corvette"]["hp"] + Defs.SHIPS["corvette"]["shield"] + Defs.SHIPS["corvette"]["armor"])
		var alive := 0
		for e9 in get_tree().get_nodes_in_group("ships"):
			if e9.has_meta("sbtest"):
				alive += 1
				tot += e9.hp + e9.shield + e9.armor
		print("  survivors %d of 3" % alive)
		print("SBDPS scale=%s after %.0fs: enemy pools %.0f/%.0f (damage %.0f)" % [OS.get_environment("SL_SHOT"), secs, tot, full, full - tot])
		var sbx := nearest_starbase(player_id, Vector2.ZERO)
		var tgt := nearest_enemy(sbx, Defs.STARBASE["range"])
		for e8 in get_tree().get_nodes_in_group("ships"):
			if e8.owner_id != player_id:
				print("  enemy %s at %.0f px, hp %.0f" % [e8.ship_type, e8.global_position.distance_to(sbx.global_position), e8.hp])
		print("  starbase target: %s" % ("none" if tgt == null else str(tgt.ship_type)))
	match OS.get_environment("SL_SHOT_OPEN"):
		"pause":
			hud.show_pause(true)
		"codex":
			hud.show_pause(true)
			hud.open_codex()
		"research":
			hud.toggle_research()
			# Dev: SL_RESEARCH_TAB opens one page, so each can be checked for fit.
			var want_tab := OS.get_environment("SL_RESEARCH_TAB")
			if want_tab != "" and hud._research_tabs.has(want_tab):
				(hud._research_tabs[want_tab] as Button).pressed.emit()
		"research_def":
			queue_research(player_id, "composite_plating")
			hud.toggle_research()
			hud._defs_tab.pressed.emit()
		"picker":
			var hp2: Planet = get_tree().get_nodes_in_group("planets").filter(func(p): return p.owner_id == player_id)[0]
			_focus_planet(hp2)
			selection_changed.emit()
			await get_tree().process_frame
			hud.planet_view._on_field_pressed(5)
		"gas":
			_focus_planet(get_tree().get_nodes_in_group("planets").filter(func(p): return not p.is_habitable())[0])
			selection_changed.emit()
		"bigbar":
			resources[player_id] = {"food": 123456.0, "minerals": 98765.0, "energy": 54321.0, "spice": 9999.0}
			queue_research(player_id, "dark_matter")
			research[player_id] = {"id": "dark_matter", "progress": 30.0, "stalled": true}
		"rock":
			var r0 := nearest_asteroid(nearest_starbase(player_id, Vector2.ZERO).global_position, 2000.0)
			_focus_asteroid(r0)
			center_on(r0.global_position)
			selection_changed.emit()
		"desert":
			_focus_planet(get_tree().get_nodes_in_group("planets").filter(func(p): return p.kind == "planet_desert")[0])
			selection_changed.emit()
		"molten":
			# Dev: a Molten world, to check its traits line.
			var mw := get_tree().get_nodes_in_group("planets").filter(func(p): return p.kind == "planet_lava")
			if not mw.is_empty():
				_focus_planet(mw[0])
				center_on(mw[0].global_position)
				selection_changed.emit()
			print("MOLTEN worlds here: %d" % mw.size())
		"sun":
			var sun0: Star = get_tree().get_nodes_in_group("stars")[0]
			_focus_star(sun0)
			center_on(sun0.global_position)
			selection_changed.emit()
		"flash":
			var en: SpaceEntity = get_tree().get_nodes_in_group("starbases").filter(func(s): return s.owner_id != player_id)[0]
			center_on(en.global_position)
			hud.flash_target(en, "attack")
			var rk := nearest_asteroid(en.global_position, 900.0)
			hud.flash_target(rk, "")
		"paused":
			hud.toggle_play()
		"save":
			save_game()
			_focus_planet(get_tree().get_nodes_in_group("planets").filter(func(p): return p.owner_id == player_id)[0])
			selection_changed.emit()
		"starbase":
			_set_selection([nearest_starbase(player_id, Vector2.ZERO)], false)
			for t in ["miner", "corvette", "corvette"]:
				nearest_starbase(player_id, Vector2.ZERO).enqueue(t)
		"planet":
			var home_p: Planet = get_tree().get_nodes_in_group("planets").filter(func(p): return p.owner_id == player_id)[0]
			home_p.order_build(3, "generator")
			home_p.order_build(4, "habitat")
			_focus_planet(home_p)
			selection_changed.emit()
	await get_tree().create_timer(0.05 if OS.get_environment("SL_SHOT_OPEN") == "flash" else 0.3 * Engine.time_scale).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://shot.png")
	get_tree().quit()

## Feeds the camera into the parallax background shader. FRAGCOORD is in
## window pixels, so fold the stretch factor into the zoom.
func _update_background() -> void:
	var mat := ($Background/Space as ColorRect).material as ShaderMaterial
	var win := Vector2(DisplayServer.window_get_size())
	var stretch := win.y / get_viewport().get_visible_rect().size.y
	mat.set_shader_parameter("cam", camera.get_screen_center_position())
	mat.set_shader_parameter("zoom", camera.zoom.x * stretch)
	mat.set_shader_parameter("screen_size", win)

## Adds a player's sensors (see Vision); `render` only for the human.
func _add_vision(pid: int, render: bool) -> Vision:
	var v := Vision.new()
	v.render = render
	$World.add_child(v)
	v.setup(self, pid)
	visions[pid] = v
	return v

## Q: every selected ship of yours with a ready ability uses it (see
## Abilities); a "deny" click if none could.
func use_abilities() -> void:
	var used := 0
	var why := ""
	for s in _own_ships_selected():
		if Defs.JOBS.get(s.def.get("job", ""), {}).get("active", false):
			var r := Abilities.use(s)
			if r == "":
				used += 1
			else:
				why = r
	if used == 0:
		sfx.play_ui("deny")
		if why != "":
			message.emit(why, Color("ff6a5a"))
	else:
		sfx.play_ui("click")

## A spice-gas harvest spot in a nebula at p (reusing one within 60 px).
func nebula_pocket_at(p: Vector2) -> NebulaPocket:
	for n in get_tree().get_nodes_in_group("nebula_pockets"):
		if n.global_position.distance_to(p) < 60.0:
			return n
	var pk := NebulaPocket.new()
	pk.position = p
	fx_root.add_child(pk)
	return pk

func nearest_pocket(p: Vector2, max_dist: float) -> NebulaPocket:
	var best: NebulaPocket = null
	var best_d := max_dist
	for n in get_tree().get_nodes_in_group("nebula_pockets"):
		var d: float = n.global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = n
	return best

# ---------------------------------------------------------------- weapons depots

## "" if a Weapons Depot can go at pos, else why not. Like a starbase site,
## but it only needs a little room from other stations.
## Where a harvester can unload: a starbase or a Mining Station, whichever
## is nearer. Null when the player has neither.
func nearest_dropoff(pid: int, pos: Vector2) -> SpaceEntity:
	var best: SpaceEntity = nearest_starbase(pid, pos)
	var best_d: float = pos.distance_to(best.global_position) if best else INF
	for st in get_tree().get_nodes_in_group("mining_stations"):
		if st.owner_id == pid and st.is_open():
			var d: float = pos.distance_to(st.global_position)
			if d < best_d:
				best_d = d
				best = st
	return best

func found_station(pid: int, pos: Vector2) -> MiningStation:
	var st := MiningStation.new()
	st.owner_id = pid
	st.position = pos
	starbases_root.add_child(st)
	if pid == player_id:
		notify("Mining Station construction started.", "note_starbase", pos)
	return st

func found_depot(pid: int, pos: Vector2, v: String) -> WeaponsDepot:
	var d := WeaponsDepot.new()
	d.owner_id = pid
	d.variant = v
	d.position = pos
	starbases_root.add_child(d)
	if pid == player_id:
		notify("%s Depot construction started." % Defs.VARIANTS[v]["label"], "note_starbase", pos)
	return d

## The nearest finished Weapons Depot of pid (of variant `v`, or any when v
## is ""). Null if there is none.
func nearest_depot(pid: int, pos: Vector2, v: String = "") -> WeaponsDepot:
	var best: WeaponsDepot = null
	var best_d := INF
	for d in get_tree().get_nodes_in_group("depots"):
		if d.owner_id == pid and d.is_alive() and not d.under_construction and (v == "" or d.variant == v):
			var dd: float = d.global_position.distance_to(pos)
			if dd < best_d:
				best_d = dd
				best = d
	return best

## Which variant the depot being placed will fit (see start_depot_placement).
var placing_depot_variant := "plasma"

func start_depot_placement(v: String = "") -> void:
	if not has_tech(player_id, str(Defs.WEAPONS_DEPOT["requires"])):
		message.emit("Weapons Depots need the %s tech." % Defs.TECHS[Defs.WEAPONS_DEPOT["requires"]]["name"], Color("ffb24a"))
		return
	if v != "":
		placing_depot_variant = v
	placing_depot = true
	placing_starbase = false
	message.emit("Left-click open space for an %s Depot (%s over %ds): generalists sent here are refitted into %s ships. Right-click to cancel." % [
		Defs.VARIANTS[placing_depot_variant]["label"], Defs.cost_text(Defs.WEAPONS_DEPOT["cost"]), Defs.WEAPONS_DEPOT["build_time"], Defs.VARIANTS[placing_depot_variant]["label"]], Color("c3cde4"))

func _place_depot(pos: Vector2) -> void:
	var why := depot_site_problem(pos)
	if why != "":
		message.emit(why + ".", Color("ff8a5a"))
		sfx.play_ui("deny")
		return
	var builders: Array = _own_ships_selected().filter(func(s): return s.def["role"] == "constructor")
	placing_depot = false
	if builders.is_empty():
		return
	builders.sort_custom(func(a, b): return a.global_position.distance_to(pos) < b.global_position.distance_to(pos))
	builders[0].order_build_depot(pos, placing_depot_variant)
	hud.ping(pos, Defs.VARIANTS[placing_depot_variant]["color"])
	sfx.play_ui("click")

## Sends every selected generalist of yours that can take variant `v` to a
## depot of that variant (see Ship.order_refit).
func refit_selected(v: String) -> void:
	if nearest_depot(player_id, Vector2.ZERO, v) == null:
		message.emit("You have no %s Depot. A Constructor builds one (E)." % Defs.VARIANTS[v]["label"], Color("ff8a5a"))
		sfx.play_ui("deny")
		return
	var n := 0
	for s in _own_ships_selected():
		if s.can_refit(v):
			s.order_refit(v)
			n += 1
	sfx.play_ui("click" if n > 0 else "deny")

## P: steps through your worlds, centering the camera on each and opening its
## panel (the same as clicking it).
var _planet_cycle: int = 0

func cycle_planet() -> void:
	var mine: Array = get_tree().get_nodes_in_group("planets").filter(func(p): return p.owner_id == player_id)
	if mine.is_empty():
		sfx.play_ui("deny")
		message.emit("You have no worlds yet: settle one with a Colony Ship.", Color("ff8a5a"))
		return
	mine.sort_custom(func(a, b): return String(a.planet_name) < String(b.planet_name))
	_planet_cycle = (_planet_cycle + 1) % mine.size()
	var p: Planet = mine[_planet_cycle]
	center_on(p.global_position)
	_set_selection([], false)
	_focus_planet(p)
	selection_changed.emit()
	sfx.play_ui("click")

## Selects every living ship of one type you own (the build-grid letter with
## no starbase selected). Centers on them if none are on screen.
func select_all_of_type(t: String) -> void:
	var all: Array = get_tree().get_nodes_in_group("ships").filter(
		func(s): return s.owner_id == player_id and s.ship_type == t and s.is_alive() and not s.docked)
	if all.is_empty():
		sfx.play_ui("deny")
		message.emit("No %s in your fleet." % Defs.SHIPS[t]["name"], Color("ff8a5a"))
		return
	_set_selection(all, false)
	var view := _visible_world_rect()
	if not all.any(func(s): return view.has_point(s.global_position)):
		var c := Vector2.ZERO
		for s in all:
			c += s.global_position
		center_on(c / all.size())
	sfx.play_ui("click")

## Space: jumps to your main starbase, and each press after that (while the
## camera is still parked on one) steps to the next one you built, looping.
var _starbase_cycle: int = 0

func cycle_starbase() -> void:
	var mine: Array = []
	for sb in starbases_root.get_children():
		if sb is Starbase and sb.owner_id == player_id and sb.is_alive():
			mine.append(sb)
	if mine.is_empty():
		sfx.play_ui("deny")
		return
	# Already looking at the one we jumped to last: step on. Otherwise start
	# again at the main (first built) starbase.
	var at: int = _starbase_cycle if _starbase_cycle < mine.size() else 0
	if camera.global_position.distance_to(mine[at].global_position) < 200.0:
		_starbase_cycle = (at + 1) % mine.size()
	else:
		_starbase_cycle = 0
	center_on(mine[_starbase_cycle].global_position)
	sfx.play_ui("click")
