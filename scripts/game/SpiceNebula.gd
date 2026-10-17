class_name SpiceNebula
extends Node2D
## A spice nebula: spice-laden gas that Gas Skimmers harvest (anywhere inside
## it, slowly and for ever). Its gas is radioactive like a star's outer zone:
## anything inside takes RADIATION_DPS (shields, then armor, then hull; the
## hits also hold off shield regen) - only a Radiation Sail Array with its
## solar shield up is spared. Ships inside are hidden from sensors that are
## not close by.
##
## Every system has them, in a shape that suits it (see SystemGen.nebulae):
##   "ring"  - a band around the node's position, between `inner` and `outer`
##             px, optionally only an arc of it (`arc_mid` +- `arc_half`).
##   "cloud" - a patch of gas of `radius` px around the node's position.
## Neither is a clean circle or curve: every edge is pushed in and out by a
## seeded noise (_edge), so the gas is amorphous - and contains() follows the
## same wobble, so what you see is exactly where Radiation starts.
## Everything else in the game asks a nebula the same questions (contains,
## heart_toward, exit_from, draw_on_map) and never looks at its shape.

## Low-level radiation: about a Red Dwarf's outer zone (Star.dps_at).
const RADIATION_DPS := 4.0
## The cloud is painted at 1/PIXEL resolution so it matches the pixel art.
const PIXEL := 4
## How far an edge wanders in and out, as a share of its size.
const EDGE_WOBBLE := 0.24

var shape: String = "ring"
var inner: float = 300.0
var outer: float = 700.0
## Ring arcs: the band covers angles arc_mid +- arc_half. PI or more = whole.
var arc_mid: float = 0.0
var arc_half: float = PI
var radius: float = 260.0
## Varies the paint and the outline so mirrored clouds are not identical.
var seed_value: int = 7

var _edge_noise: FastNoiseLite

func _ready() -> void:
	add_to_group("nebulae")
	z_index = -1
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(_paint())
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * PIXEL
	add_child(sprite)

## Builds one from a SystemGen feature dict.
static func from_feature(ft: Dictionary) -> SpiceNebula:
	var n := SpiceNebula.new()
	n.position = ft.get("pos", Vector2.ZERO)
	n.shape = ft.get("shape", "ring")
	n.inner = ft.get("inner", 300.0)
	n.outer = ft.get("outer", 700.0)
	n.arc_mid = ft.get("arc_mid", 0.0)
	n.arc_half = ft.get("arc_half", PI)
	n.radius = ft.get("radius", 260.0)
	n.seed_value = int(ft.get("seed", 7))
	return n

## How far the edge `which` (0 = a cloud's rim or a ring's outer face,
## 1 = a ring's inner face) reaches at angle `a`, as a multiple of its
## nominal size: a smooth, seamless wobble round the circle.
func _edge(a: float, which: int = 0) -> float:
	if _edge_noise == null:
		_edge_noise = FastNoiseLite.new()
		_edge_noise.seed = seed_value * 31 + 5
		_edge_noise.frequency = 0.9
		_edge_noise.fractal_octaves = 3
	# Fractal noise peaks near +-1.75: scaled (not clipped) into +-1, so the
	# outline never flattens where the noise saturates.
	var n := clampf(_edge_noise.get_noise_3d(cos(a) * 1.6, sin(a) * 1.6, which * 7.3) / 1.75, -1.0, 1.0)
	return 1.0 + n * EDGE_WOBBLE * 2.0

func _in_arc(a: float) -> bool:
	if arc_half >= PI:
		return true
	# The ends of a partial band are ragged too.
	return absf(angle_difference(arc_mid, a)) <= arc_half * (1.0 + (_edge(a, 2) - 1.0) * 0.6)

## Inner and outer faces of the gas at angle a (cloud: 0 and its rim).
func _faces(a: float) -> Vector2:
	if shape == "cloud":
		return Vector2(0.0, radius * _edge(a))
	var half := (outer - inner) / 2.0
	var mid := (inner + outer) / 2.0
	# The band's faces wander independently, but it never pinches shut.
	var i := mid - half * _edge(a, 1)
	var o := mid + half * _edge(a, 0)
	return Vector2(i, maxf(o, i + 60.0))

func contains(p: Vector2) -> bool:
	var v := p - global_position
	var a := v.angle()
	var f := _faces(a)
	var d := v.length()
	return d >= f.x and d <= f.y and (shape == "cloud" or _in_arc(a))

## A point well inside the nebula, on the part nearest `from`: where a
## skimmer goes to work, or where the AI sends one.
func heart_toward(from: Vector2) -> Vector2:
	if shape == "cloud":
		return global_position + (from - global_position).limit_length(radius * 0.4)
	var a := (from - global_position).angle()
	if arc_half < PI and absf(angle_difference(arc_mid, a)) > arc_half * 0.7:
		a = arc_mid + clampf(angle_difference(arc_mid, a), -arc_half * 0.7, arc_half * 0.7)
	var f := _faces(a)
	return global_position + Vector2.from_angle(a) * (f.x + f.y) / 2.0

## The nearest point just outside the nebula from a point inside it.
func exit_from(p: Vector2) -> Vector2:
	var v := p - global_position
	var d := maxf(v.length(), 0.001)
	var f := _faces(v.angle())
	if shape == "cloud":
		return global_position + v / d * (f.y + 40.0)
	# A ring band: out through whichever face is closer; an arc can also be
	# left through its ends, but the faces are always near enough.
	var edge: float = f.x - 40.0 if d - f.x < f.y - d else f.y + 40.0
	return global_position + v / d * edge

## Draws the nebula onto a map (the minimap, the lobby preview): `to_map`
## turns a world point into the canvas, `k` is canvas units per world px.
func draw_on_map(canvas: CanvasItem, to_map: Callable, _k: float) -> void:
	# The true, ragged outline (the same _faces contains() uses), filled.
	var col := Color(1.0, 0.6, 0.2, 0.2)
	var seg := 72
	var pts: Array = []
	for i in seg + 1:
		var a := (-PI if arc_half >= PI else arc_mid - arc_half * 1.1) + (TAU if arc_half >= PI else arc_half * 2.2) * i / seg
		var f := _faces(a)
		var ok := shape == "cloud" or _in_arc(a)
		pts.append([to_map.call(position + Vector2.from_angle(a) * f.x), to_map.call(position + Vector2.from_angle(a) * f.y), ok])
	if shape == "cloud":
		var poly := PackedVector2Array()
		for p in pts.slice(0, seg):
			poly.append(p[1])
		canvas.draw_colored_polygon(poly, col)
		return
	for i in seg:
		if pts[i][2] and pts[i + 1][2]:
			canvas.draw_colored_polygon(PackedVector2Array([pts[i][0], pts[i][1], pts[i + 1][1], pts[i + 1][0]]), col)

## The same for a feature dict, so the lobby can draw a system it has not
## built (a throwaway nebula gives the identical outline).
static func draw_feature_on_map(canvas: CanvasItem, to_map: Callable, k: float, ft: Dictionary) -> void:
	var n := from_feature(ft)
	n.draw_on_map(canvas, to_map, k)
	n.free()

## The gas, painted to its true outline: a glowing amber rim right at the
## edge (so the boundary reads at a glance with no line drawn), a body of
## magenta-to-orange gas with brighter spice wisps curling through it, and
## only a faint haze outside.
func _paint() -> Image:
	var reach := (radius if shape == "cloud" else outer) * (1.0 + EDGE_WOBBLE * 2.0) + 30.0
	var n := int(ceil(reach * 2.0 / PIXEL)) + 12
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var wisp := FastNoiseLite.new()
	wisp.seed = seed_value
	wisp.frequency = 0.03
	wisp.fractal_octaves = 5
	var body_n := FastNoiseLite.new()
	body_n.seed = seed_value + 99
	body_n.frequency = 0.02
	body_n.fractal_octaves = 3
	var deep := Color("3a1030")
	var body := Color("8c2a52")
	var warm := Color("d4562e")
	var spice := Color("ffb347")
	var rim := Color("ffcf7a")
	var bayer := [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
	var c := n / 2.0
	for y in n:
		for x in n:
			var off := Vector2(x - c, y - c) * PIXEL
			var d := off.length()
			var a := off.angle()
			var f := _faces(a)
			var dither: float = (bayer[y % 4][x % 4] + 0.5) / 16.0 - 0.5
			var inside := d >= f.x and d <= f.y and (shape == "cloud" or _in_arc(a))
			if not inside:
				# Outside: a thin, fading haze so the edge doesn't look cut.
				var gap := minf(absf(d - f.y), absf(d - f.x) if f.x > 0.0 else INF)
				if gap < 18.0 and (shape == "cloud" or _in_arc(a)):
					var ha := (1.0 - gap / 18.0) * 0.1 + dither * 0.03
					if ha > 0.02:
						img.set_pixel(x, y, Color(warm, ha))
				continue
			# How deep inside the gas, 0 at the edge.
			var depth := d - f.x if f.x > 0.0 else INF
			depth = minf(depth, f.y - d)
			if arc_half < PI and shape != "cloud":
				depth = minf(depth, (arc_half - absf(angle_difference(arc_mid, a))) * d)
			var col: Color
			# The gas body: deep magenta to rose, with soft billows of spice.
			var b := clampf(body_n.get_noise_2d(x, y) * 0.6 + 0.5, 0.0, 1.0)
			col = Color(deep, 0.24).lerp(Color(body, 0.32), b)
			var w := clampf((wisp.get_noise_2d(x, y) - 0.05) * 1.8 + dither * 0.15, 0.0, 1.0)
			col = col.lerp(Color(warm, 0.34), w * 0.6)
			col = col.lerp(Color(spice, 0.38), clampf(w - 0.6, 0.0, 1.0) * 1.2)
			# The rim: a glow that is brightest right at the edge and fades
			# inward, so the boundary reads clearly without a hard band.
			var glow := clampf(1.0 - (depth + dither * 5.0) / 34.0, 0.0, 1.0)
			if glow > 0.0:
				col = col.lerp(Color(rim, 0.5), glow * glow * 0.9)
			img.set_pixel(x, y, col)
	return img
