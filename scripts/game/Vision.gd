class_name Vision
extends Node2D
## Sensors / line of sight (fog of war) for the human player.
##
## The map is a grid of CELL-sized cells, kept as two small images drawn
## stretched (and softly filtered) over the world:
##   - _dark: black where never explored; sensors clear it for good.
##   - _sight: dimmed everywhere, cleared where sensors currently reach
##     (rebuilt every UPDATE seconds).
## Each sensor circle is written as one native fill per grid row, which
## keeps big fleets cheap.
##
## Enemy ships and shots are only shown while in sight; enemy starbases once
## seen stay on the map (as last seen). Terrain matters: ships in an active
## ion storm see half as far, and ships inside a spice nebula can only be
## seen from close by (NEBULA_SPOT).

const CELL := 32.0
const UPDATE := 0.12
## Default sensor ranges (px) by ship role; a ship def can set "sensor".
## Civilian ships see less than warships (room for a dedicated scout).
const ROLE_SENSOR := {"miner": 220.0, "skimmer": 220.0, "colony": 240.0, "constructor": 260.0, "warship": 300.0}
const STARBASE_SENSOR := 640.0
const STARBASE_BUILDING_SENSOR := 260.0
const PLANET_SENSOR := 280.0
## An enemy inside a spice nebula is only visible within this distance.
const NEBULA_SPOT := 160.0
const STORM_SENSOR_MULT := 0.5

const FOG_COLOR := Color(0.015, 0.015, 0.015, 1.0)
const EXPLORED_ALPHA := 0.55

var game: Game
var pid: int = 1
## False once the match is over (everything is revealed) or in dev modes.
var enabled := true
var cols: int
var rows: int
## [position, range] of every sensor this update (for can_see checks).
var _sources: Array = []
var _dark: Image
var _sight: Image
var _dark_tex: ImageTexture
var _sight_tex: ImageTexture
var _timer := 0.0
const CLEAR := Color(0, 0, 0, 0)

func setup(g: Game, player: int) -> void:
	game = g
	pid = player
	cols = int(ceil(Game.MAP_RECT.size.x / CELL))
	rows = int(ceil(Game.MAP_RECT.size.y / CELL))
	_dark = Image.create(cols, rows, false, Image.FORMAT_LA8)
	_dark.fill(FOG_COLOR)
	_sight = Image.create(cols, rows, false, Image.FORMAT_LA8)
	# Nothing is known about other planets yet.
	for pl in get_tree().get_nodes_in_group("planets"):
		pl.seen_owner = 0
		pl.in_sight = false
	# Stars shine across the system: their surroundings start explored.
	for star in get_tree().get_nodes_in_group("stars"):
		_stamp(_dark, star.global_position, star.radiation_radius + 60.0)
	_dark_tex = ImageTexture.create_from_image(_dark)
	_sight_tex = ImageTexture.create_from_image(_sight)
	z_index = 50
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_refresh()

func _process(delta: float) -> void:
	if not enabled:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = UPDATE
		_refresh()

## Lifts the fog for good (match over).
func reveal_all() -> void:
	enabled = false
	visible = false
	for s in get_tree().get_nodes_in_group("ships"):
		s.visible = true
	for sb in get_tree().get_nodes_in_group("starbases"):
		sb.visible = true
	for p in game.fx_root.get_children():
		p.visible = true
	for pl in get_tree().get_nodes_in_group("planets"):
		pl.seen_owner = -1
		pl.in_sight = true
		pl.queue_redraw()

func _cell(p: Vector2) -> Vector2i:
	var q := (p - Game.MAP_RECT.position) / CELL
	return Vector2i(clampi(int(q.x), 0, cols - 1), clampi(int(q.y), 0, rows - 1))

func is_visible_at(p: Vector2) -> bool:
	if not enabled:
		return true
	var c := _cell(p)
	return _sight.get_pixel(c.x, c.y).a == 0.0

func is_explored_at(p: Vector2) -> bool:
	if not enabled:
		return true
	var c := _cell(p)
	return _dark.get_pixel(c.x, c.y).a == 0.0

## Can the player see this entity right now? Own entities always; enemy
## ships in a spice nebula only up close.
func can_see(e: Node2D) -> bool:
	if not enabled or e.get("owner_id") == pid:
		return true
	if not is_visible_at(e.global_position):
		return false
	if e is Ship and game.in_nebula(e.global_position):
		for s in _sources:
			if e.global_position.distance_to(s[0]) <= NEBULA_SPOT:
				return true
		return false
	return true

func sensor_range(e: Node2D) -> float:
	var r := 0.0
	if e is Starbase:
		r = STARBASE_BUILDING_SENSOR if e.under_construction else STARBASE_SENSOR
	elif e is Ship:
		r = e.def.get("sensor", ROLE_SENSOR.get(e.def["role"], 260.0))
	else:
		r = PLANET_SENSOR + e.radius
	if game.in_storm(e.global_position):
		r *= STORM_SENSOR_MULT
	return r

func _refresh() -> void:
	_sources.clear()
	var tree := get_tree()
	# Ships bunched in a fleet share one sensor per cell (the longest range),
	# so a 100-ship blob costs about as much as a handful of ships.
	var per_cell := {}
	for s in tree.get_nodes_in_group("ships"):
		if s.owner_id == pid and s.is_alive():
			var key := _cell(s.global_position)
			var r := sensor_range(s)
			if r > per_cell.get(key, [null, 0.0])[1]:
				per_cell[key] = [s.global_position, r]
	_sources.append_array(per_cell.values())
	for sb in tree.get_nodes_in_group("starbases"):
		if sb.owner_id == pid and sb.is_alive():
			_sources.append([sb.global_position, sensor_range(sb)])
	for p in tree.get_nodes_in_group("planets"):
		if p.owner_id == pid:
			_sources.append([p.global_position, sensor_range(p)])
	_sight.fill(Color(FOG_COLOR.r, FOG_COLOR.g, FOG_COLOR.b, EXPLORED_ALPHA))
	for src in _sources:
		_stamp(_sight, src[0], src[1])
		_stamp(_dark, src[0], src[1])
	_hide_unseen()
	_dark_tex.update(_dark)
	_sight_tex.update(_sight)
	queue_redraw()

## Clears every cell whose center is within range of p, one row span at a
## time.
func _stamp(img: Image, p: Vector2, r: float) -> void:
	var c0 := _cell(p - Vector2(r, r))
	var c1 := _cell(p + Vector2(r, r))
	var ox := Game.MAP_RECT.position.x
	for y in range(c0.y, c1.y + 1):
		var dy := Game.MAP_RECT.position.y + (y + 0.5) * CELL - p.y
		if absf(dy) > r:
			continue
		var half := sqrt(r * r - dy * dy)
		var x0 := maxi(int(ceil((p.x - half - ox) / CELL - 0.5)), 0)
		var x1 := mini(int(floor((p.x + half - ox) / CELL - 0.5)), cols - 1)
		if x1 >= x0:
			img.fill_rect(Rect2i(x0, y, x1 - x0 + 1, 1), CLEAR)

## Shows / hides enemy units by what the player can currently see.
func _hide_unseen() -> void:
	var tree := get_tree()
	for s in tree.get_nodes_in_group("ships"):
		if s.owner_id != pid:
			s.visible = can_see(s)
			if not s.visible and s.selected:
				game.selection.erase(s)
				s.selected = false
	# Enemy starbases: shown once seen, then remembered.
	for sb in tree.get_nodes_in_group("starbases"):
		if sb.owner_id != pid:
			if can_see(sb):
				sb.set_meta("seen", true)
			sb.visible = sb.get_meta("seen", false)
	for p in game.fx_root.get_children():
		if p is Projectile:
			p.visible = is_visible_at(p.global_position)
	# Planets: remember the owner last seen; hide sieges / colonizing out of sight.
	for pl in tree.get_nodes_in_group("planets"):
		var sight: bool = pl.owner_id == pid or is_visible_at(pl.global_position)
		var so: int = pl.owner_id if sight else pl.seen_owner
		if sight != pl.in_sight or so != pl.seen_owner:
			pl.in_sight = sight
			pl.seen_owner = so
			pl.queue_redraw()

func _draw() -> void:
	if enabled:
		draw_fog(self, Rect2(Game.MAP_RECT.position, Vector2(cols, rows) * CELL))

## Draws the fog (both layers) onto any canvas item, stretched over `rect`
## (the world here, the minimap there).
func draw_fog(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_texture_rect(_sight_tex, rect, false)
	ci.draw_texture_rect(_dark_tex, rect, false)

## Dev aid: SL_FOG_TEST=1 prints how many enemy ships / starbases are shown.
func _ready() -> void:
	if OS.get_environment("SL_FOG_TEST") != "":
		_fog_test.call_deferred()

func _fog_test() -> void:
	await get_tree().create_timer(3.0).timeout
	var shown := 0
	var total := 0
	for s in get_tree().get_nodes_in_group("ships"):
		if s.owner_id != pid:
			total += 1
			shown += int(s.visible)
	var sb_shown := 0
	for sb in get_tree().get_nodes_in_group("starbases"):
		if sb.owner_id != pid:
			sb_shown += int(sb.visible)
	var ex := 0
	for y in rows:
		for x in cols:
			ex += int(_dark.get_pixel(x, y).a == 0.0)
	var home: Node2D = game.nearest_starbase(pid, Vector2.ZERO)
	var rocks := 0
	var rocks_seen := 0
	for a in get_tree().get_nodes_in_group("asteroids"):
		if a.global_position.distance_to(home.global_position) < 900.0 and game.nearest_starbase(3 - pid, a.global_position).global_position.distance_to(a.global_position) > a.global_position.distance_to(home.global_position):
			rocks += 1
			rocks_seen += int(is_explored_at(a.global_position))
	var near_planet := 1e9
	for p in get_tree().get_nodes_in_group("planets"):
		if p.owner_id == 0:
			near_planet = minf(near_planet, p.global_position.distance_to(home.global_position))
	print("FOG TEST %s home rocks seen %d / %d, nearest free planet %.0f px" % [GameState.system_id, rocks_seen, rocks, near_planet])
	var leaks := 0
	for pl in get_tree().get_nodes_in_group("planets"):
		if pl.owner_id != 0 and pl.owner_id != pid and pl.shown_owner() == pl.owner_id and not pl.in_sight:
			leaks += 1
	var enemy_planets := get_tree().get_nodes_in_group("planets").filter(func(pl): return pl.owner_id != 0 and pl.owner_id != pid)
	print("FOG TEST enemy planets %d, shown as enemy %d, out-of-sight leaks %d" % [enemy_planets.size(), enemy_planets.filter(func(pl): return pl.shown_owner() == pl.owner_id).size(), leaks])
	print("FOG TEST enemy ships shown %d / %d, enemy starbases shown %d, explored %.0f%%" % [shown, total, sb_shown, 100.0 * ex / (cols * rows)])
	get_tree().quit()
