class_name Game
extends Node2D
## Root of scenes/Main.tscn. Owns the match: per-player economy (four
## resources, pay-over-time with spice substitution, upkeep, research),
## spatial queries, spawning, the human player's selection/orders, the
## camera, and win/loss. Everything else reaches it through Game.instance.

signal selection_changed
signal message(text: String, color: Color)
signal match_over(won: bool)
signal tech_completed(pid: int, tech_id: String)

const SHIP_SCENE := preload("res://scenes/Ship.tscn")
const STARBASE_SCENE := preload("res://scenes/Starbase.tscn")
const PLANET_SCENE := preload("res://scenes/Planet.tscn")
const ASTEROID_SCENE := preload("res://scenes/Asteroid.tscn")
const MAP_RECT := Rect2(-1800, -1150, 3600, 2300)
const ZOOM_LEVELS: Array[float] = [1.0, 2.0, 3.0, 4.0, 6.0]
const CELL := 64.0
const PAN_SPEED := 900.0
const EDGE_PAN_MARGIN := 6
const SUBSTITUTABLE := ["food", "minerals", "energy"]

static var instance: Game
## Scaled, pause-aware match clock (seconds). Use this, not wall time.
static var _clock: float = 0.0

var player_id: int = 1
var players: Array[int] = [1, 2]
var resources := {}
## Net change per second over the last second, per player per resource.
var rates := {}
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
## Starbase placement mode for a selected Constructor.
var placing_starbase: bool = false

var _grid := {}
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
	if OS.get_environment("SL_LOAD") != "":
		GameState.load_on_start = true
		GameState.load_save_path = OS.get_environment("SL_LOAD")
	instance = self
	_clock = 0.0
	player_id = clampi(GameState.human_player_id, 1, 2)
	for pid in players:
		resources[pid] = Defs.START.duplicate()
		rates[pid] = {}
		_rate_acc[pid] = {}
		researched[pid] = {}
		research[pid] = {}
		research_queue[pid] = []

func _ready() -> void:
	process_physics_priority = -10
	# No account controls during a match.
	SignedInLabel.visible = false
	tree_exiting.connect(func(): SignedInLabel.visible = true)
	Engine.time_scale = 1.0
	RenderingServer.set_default_clear_color(Color("07060f"))
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
	# Balance harness (SL_SIM): the AI plays both sides.
	if OS.get_environment("SL_SIM") != "":
		seed(hash(OS.get_environment("SL_SIM")))
		ai.setup([1, 2])
		add_child(SimRunner.new())
	else:
		ai.setup([3 - player_id])
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
	Music.play_track(Music.IN_GAME_TRACK)
	if loaded:
		notify("Saved game loaded.", "note_save")
	else:
		message.emit(system_settings.get("arrival", "You arrive in uncharted space."), Color("e8d6a8"))
		message.emit("Grow your worlds, mine the belts, find spice, destroy the enemy starbase.", Color("c3cde4"))
	_enter_dev_capture()

# ---------------------------------------------------------------- system

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
	system_settings = SystemGen.settings(GameState.system_id, GameState.system_seed)
	_apply_system_look(system_settings)
	if GameState.system_id == "orion_reach":
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
			var neb := SpiceNebula.new()
			neb.inner = ft["inner"]
			neb.outer = ft["outer"]
			world.add_child(neb)
			world.move_child(neb, 0)

## Amber heads-up (no alarm) when your shielded ships are in a nebula, at
## most every NEBULA_WARN_MS, with a minimap flare where it happened.
const NEBULA_WARN_MS := 20000
var _nebula_warn_ms: int = -100000
func warn_nebula(at: Vector2) -> void:
	var t := Time.get_ticks_msec()
	if t - _nebula_warn_ms < NEBULA_WARN_MS:
		return
	_nebula_warn_ms = t
	add_flare(at, Color("ffae4a"))
	message.emit("Your ships are in the Spice Nebula: shields drain and won't recharge inside.", Color("ffae4a"))

# ---------------------------------------------------------------- navigation

## Only systems with debris rings need routing; elsewhere nav stays null and
## ships fly straight as before.
const NAV_CELL := 40.0
var nav: AStarGrid2D = null

## Solid debris at p (grown by margin).
func is_blocked(p: Vector2, margin: float = 0.0) -> bool:
	for r in get_tree().get_nodes_in_group("debris_rings"):
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

## Whether `p` is inside an active ion-storm arm (ships crawl there).
func in_storm(p: Vector2) -> bool:
	for s in get_tree().get_nodes_in_group("storms"):
		if s.contains(p):
			return true
	return false

## Whether `p` is inside a spice nebula (shields drain there).
func in_nebula(p: Vector2) -> bool:
	for n in get_tree().get_nodes_in_group("nebulae"):
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

## Summed research bonus for `key` (e.g. "damage") as a multiplier.
func mod(pid: int, key: String) -> float:
	var m := 1.0
	for t in researched.get(pid, {}):
		m += Defs.TECHS[t]["effects"].get(key, 0.0)
	return m

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
	u *= upkeep_multiplier(pid)
	u += starbase_count(pid) * Defs.STARBASE["upkeep"] * starbase_upkeep_multiplier(pid)
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
	# Rebuild the ship spatial hash once per tick for separation/claims.
	_grid.clear()
	for s in get_tree().get_nodes_in_group("ships"):
		var key := Vector2i((s.global_position / CELL).floor())
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(s)
	if is_over:
		return
	for pid in players:
		pay_over_time(pid, {"energy": upkeep(pid)}, delta)
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
		_rate_timer = 0.0

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
	var best: SpaceEntity = null
	var best_d := max_dist
	for s in ships_near(from.global_position, max_dist + 20.0):
		if s.is_enemy_of(from.owner_id) and s.is_alive():
			var d: float = from.global_position.distance_to(s.global_position) - s.radius
			# Prefer warships over civilian hulls at similar range.
			if s.def["role"] != "warship":
				d += 40.0
			if d < best_d:
				best_d = d
				best = s
	for sb in get_tree().get_nodes_in_group("starbases"):
		if sb.is_enemy_of(from.owner_id) and sb.is_alive():
			var d: float = from.global_position.distance_to(sb.global_position) - sb.radius
			if d < best_d:
				best_d = d
				best = sb
	return best

func nearest_asteroid(pos: Vector2, max_dist: float, resource: String = "minerals") -> Asteroid:
	var best: Asteroid = null
	var best_d := max_dist
	for a in get_tree().get_nodes_in_group("asteroids"):
		if a.is_queued_for_deletion() or a.amount <= 0 or a.resource != resource:
			continue
		var d := pos.distance_to(a.global_position)
		if d < best_d:
			best_d = d
			best = a
	return best

func nearest_gas_giant(pos: Vector2, max_dist: float) -> Planet:
	var best: Planet = null
	var best_d := max_dist
	for p in get_tree().get_nodes_in_group("planets"):
		if p.is_habitable() or p.amount <= 0:
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
func starbase_site_problem(pos: Vector2) -> String:
	if not MAP_RECT.grow(-60).has_point(pos):
		return "Too close to the edge of the system"
	for sb in get_tree().get_nodes_in_group("starbases"):
		if sb.global_position.distance_to(pos) < Defs.STARBASE["min_spacing"]:
			return "Too close to another starbase"
	for p in get_tree().get_nodes_in_group("planets"):
		if p.global_position.distance_to(pos) < p.radius + 40.0:
			return "Too close to a planet"
	for s in get_tree().get_nodes_in_group("stars"):
		if s.global_position.distance_to(pos) < s.radiation_radius + 40.0:
			return "Too close to the star"
	if is_blocked(pos, 50.0):
		return "Blocked by the debris ring"
	return ""

# ---------------------------------------------------------------- spawning

func spawn_ship(ship_type: String, pid: int, pos: Vector2) -> Ship:
	var s: Ship = SHIP_SCENE.instantiate()
	s.ship_type = ship_type
	s.owner_id = pid
	s.position = pos
	ships_root.add_child(s)
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

func fire(from: SpaceEntity, to: Node2D, weapon: String, damage: float) -> void:
	var p := Projectile.new()
	fx_root.add_child(p)
	p.setup(from, to, weapon, damage * mod(from.owner_id, "damage"))
	sfx.play_at("laser" if weapon == "laser" else "torpedo", from.global_position, -8.0)

func spawn_explosion(pos: Vector2, scale_mult: float = 1.0) -> void:
	var e := Effect.new()
	e.texture = Defs.tex("explosion")
	e.hframes = 8
	e.fps = 14.0
	e.global_position = pos
	e.rotation = randi_range(0, 3) * PI / 2.0
	e.scale = Vector2.ONE * clampf(snappedf(scale_mult, 0.5), 0.5, 3.0)
	fx_root.add_child(e)
	sfx.play_at("boom_big" if scale_mult >= 1.0 else "boom", pos, -6.0)

func spawn_shield_hit(pos: Vector2, r: float, from_pos: Vector2) -> void:
	var e := Effect.new()
	e.texture = Defs.tex("shield_hit")
	e.fps = 16.0
	e.modulate = Color("7fd8ff")
	e.global_position = pos
	e.rotation = (from_pos - pos).angle()
	e.scale = Vector2.ONE * maxf(1.0, round(r / 8.0))
	fx_root.add_child(e)
	sfx.play_at("shield", pos, -12.0)

# ---------------------------------------------------------------- events

func planet_claimed(p: Planet, old_owner: int) -> void:
	if p.owner_id == player_id:
		notify(("%s colonized." if old_owner == 0 else "%s conquered.") % p.planet_name, "note_colony", p.global_position)
	elif old_owner == player_id:
		alert("%s lost to the enemy!" % p.planet_name, "alert_planet_lost", true, p.global_position)
	selection_changed.emit()

## A bombarded planet ran out of pops and went neutral.
func planet_depopulated(p: Planet, old_owner: int, attacker: int) -> void:
	if old_owner == player_id:
		alert("%s has been depopulated and lost!" % p.planet_name, "alert_planet_lost", true, p.global_position)
	elif attacker == player_id:
		notify("%s depopulated. It can now be colonized." % p.planet_name, "note_colony", p.global_position)
	selection_changed.emit()

func _on_starbase_died(sb: SpaceEntity) -> void:
	selection.erase(sb)
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
	match_over.emit(won)

# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if is_over or paused_menu:
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
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)

func _handle_mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			if placing_starbase:
				if e.pressed:
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
			if e.pressed:
				if placing_starbase:
					placing_starbase = false
				else:
					_issue_command(get_global_mouse_position(), e.ctrl_pressed)
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
		if placing_starbase:
			placing_starbase = false
		elif is_instance_valid(focused_planet) or is_instance_valid(focused_asteroid) or is_instance_valid(focused_star):
			clear_planet_focus()
		elif hud.research_open():
			hud.toggle_research()
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
	if k == KEY_F and _selected_role("constructor"):
		start_starbase_placement()
		return
	if k == KEY_MINUS or k == KEY_KP_SUBTRACT:
		hud.set_speed_index(hud.speed_index() - 1)
		return
	if k == KEY_EQUAL or k == KEY_KP_ADD:
		hud.set_speed_index(hud.speed_index() + 1)
		return
	if k == KEY_BACKSPACE:
		hud.set_speed_index(HUD.NORMAL_SPEED)
		return
	if k == KEY_SPACE:
		hud.toggle_play()
		return
	match k:
		KEY_R:
			hud.toggle_research()
		KEY_H:
			var sb := nearest_starbase(player_id, camera.global_position)
			if sb:
				center_on(sb.global_position)
		KEY_T:
			for s in _own_ships_selected():
				s.order_stop()
		KEY_TAB:
			# Select every combat ship you own.
			var all: Array = get_tree().get_nodes_in_group("ships").filter(func(s): return s.owner_id == player_id and s.def["role"] == "warship")
			_set_selection(all, false)
		_:
			var sb := selected_starbase()
			if sb:
				for t in Defs.BUILD_ORDER:
					if Defs.SHIPS[t]["hotkey"] == k:
						request_build(sb, t)

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
	_clock += delta
	var now_us := Time.get_ticks_usec()
	var real_dt := minf((now_us - _last_real_us) / 1000000.0, 0.1) if _last_real_us > 0 else 0.0
	_last_real_us = now_us
	_update_background()
	if paused_menu or is_over:
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

func _focus_planet(p: Planet) -> void:
	if p and p != focused_planet:
		center_on(p.global_position)
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

func _issue_command(world_pos: Vector2, attack_move: bool) -> void:
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
				s.order_attack(target)
			else:
				s.order_move(world_pos)
		hud.flash_target(target, "attack")
		return
	if rock:
		for s in ships:
			if s.is_miner():
				s.order_mine(rock)
			else:
				s.order_move(rock.global_position)
		hud.flash_target(rock, "")
		return
	if planet and not planet.is_habitable():
		var handled := false
		for s in ships.duplicate():
			if s.can_mine(planet):
				s.order_mine(planet)
				ships.erase(s)
				handled = true
		if ships.any(func(s): return s.def["role"] == "colony"):
			message.emit("Gas giants are uninhabitable.", Color("ff8a5a"))
		if handled:
			hud.flash_target(planet, "")
			if ships.is_empty():
				return
	if planet and planet.is_enemy_of(player_id):
		# Bombard: warships fire on the planet until its pops are gone.
		for s in ships:
			if s.def["role"] == "warship":
				s.order_bombard(planet)
			else:
				s.order_move(world_pos)
		hud.flash_target(planet, "attack")
		return
	if planet and planet.owner_id == 0:
		var colonists: Array = ships.filter(func(s): return s.def["role"] == "colony")
		if not colonists.is_empty():
			colonists.sort_custom(func(a, b): return a.global_position.distance_to(planet.global_position) < b.global_position.distance_to(planet.global_position))
			colonists[0].order_colonize(planet)
			ships.erase(colonists[0])
			hud.flash_target(planet, "colonize")
			if ships.is_empty():
				return
	if target is Starbase and target.owner_id == player_id:
		for s in ships:
			if s.is_miner() and s.cargo > 0:
				s.order_return()
		hud.flash_target(target, "")
	var slots := _formation(ships, world_pos)
	for i in ships.size():
		if attack_move:
			ships[i].order_attack_move(slots[i])
		else:
			ships[i].order_move(slots[i])
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
		get_tree().create_timer(20.0).timeout.connect(func(): print("DESERT reserve ", dp.spice_reserve, " spice_out ", dp.spice_out, " idle_pop ", dp.idle_pop, " spice ", resources[player_id]["spice"]))
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
			print("NEB 12s: in %.0f/%.0f  out %.0f/%.0f  ai dist %.0f  ai in nebula %s" % [c_in.shield, c_in.max_shield, c_out.shield, c_out.max_shield, ai_s.global_position.length(), str(in_nebula(ai_s.global_position))]))
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
	if OS.get_environment("SL_SHOT_OPEN") == "sun":
		var c1 := spawn_ship("corvette", player_id, Vector2(52, 0))
		c1.order_stop()
		var c2 := spawn_ship("corvette", player_id, Vector2(-150, 0))
		c2.order_stop()
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
		queue_research(player_id, "plasma_lances")
	await get_tree().create_timer(secs).timeout
	match OS.get_environment("SL_SHOT_OPEN"):
		"pause":
			hud.show_pause(true)
		"research":
			hud.toggle_research()
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
