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
## Everything else in the game asks a nebula the same questions (contains,
## heart_toward, exit_from, draw_on_map) and never looks at its shape.

## Low-level radiation: about a Red Dwarf's outer zone (Star.dps_at).
const RADIATION_DPS := 4.0
## The cloud is painted at 1/PIXEL resolution so it matches the pixel art.
const PIXEL := 4

var shape: String = "ring"
var inner: float = 300.0
var outer: float = 700.0
## Ring arcs: the band covers angles arc_mid +- arc_half. PI or more = whole.
var arc_mid: float = 0.0
var arc_half: float = PI
var radius: float = 260.0
## Varies the paint so mirrored clouds are not pixel-identical.
var seed_value: int = 7

func _ready() -> void:
	add_to_group("nebulae")
	z_index = -1
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(_paint())
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * PIXEL
	add_child(sprite)
	queue_redraw()

## The edge, exactly where Radiation starts (contains()): a dashed amber line,
## so a player can tell inside from out at a glance.
const EDGE := Color(1.0, 0.68, 0.3, 0.55)
const EDGE_DASH := 22.0

func _draw() -> void:
	if shape == "cloud":
		_dashed_arc(radius, 0.0, TAU)
		return
	var a0 := -PI if arc_half >= PI else arc_mid - arc_half
	var a1 := PI if arc_half >= PI else arc_mid + arc_half
	_dashed_arc(inner, a0, a1)
	_dashed_arc(outer, a0, a1)
	if arc_half < PI:
		# Close off the ends of a partial band.
		for a in [a0, a1]:
			draw_line(Vector2.from_angle(a) * inner, Vector2.from_angle(a) * outer, EDGE, 2.0)

func _dashed_arc(r: float, a0: float, a1: float) -> void:
	var step := EDGE_DASH / r
	var a := a0
	while a < a1:
		draw_arc(Vector2.ZERO, r, a, minf(a + step, a1), 6, EDGE, 2.0)
		a += step * 2.0


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

func _in_arc(a: float) -> bool:
	return arc_half >= PI or absf(angle_difference(arc_mid, a)) <= arc_half

func contains(p: Vector2) -> bool:
	var v := p - global_position
	if shape == "cloud":
		return v.length() <= radius
	var d := v.length()
	return d >= inner and d <= outer and _in_arc(v.angle())

## A point well inside the nebula, on the part nearest `from`: where a
## skimmer goes to work, or where the AI sends one.
func heart_toward(from: Vector2) -> Vector2:
	if shape == "cloud":
		return global_position + (from - global_position).limit_length(radius * 0.4)
	var a := (from - global_position).angle()
	if not _in_arc(a):
		a = arc_mid + clampf(angle_difference(arc_mid, a), -arc_half * 0.8, arc_half * 0.8)
	return global_position + Vector2.from_angle(a) * (inner + outer) / 2.0

## The nearest point just outside the nebula from a point inside it.
func exit_from(p: Vector2) -> Vector2:
	var v := p - global_position
	var d := maxf(v.length(), 0.001)
	if shape == "cloud":
		return global_position + v / d * (radius + 40.0)
	# A ring band: out through whichever face is closer; an arc can also be
	# left through its ends, but the faces are always near enough.
	var edge: float = inner - 40.0 if d - inner < outer - d else outer + 40.0
	return global_position + v / d * edge

## Draws the nebula onto a map (the minimap, the lobby preview): `to_map`
## turns a world point into the canvas, `k` is canvas units per world px.
func draw_on_map(canvas: CanvasItem, to_map: Callable, k: float) -> void:
	draw_feature_on_map(canvas, to_map, k, {"pos": global_position, "shape": shape, "inner": inner, "outer": outer,
		"arc_mid": arc_mid, "arc_half": arc_half, "radius": radius})

## The same for a feature dict, so the lobby can draw a system it has not
## built.
static func draw_feature_on_map(canvas: CanvasItem, to_map: Callable, k: float, ft: Dictionary) -> void:
	var col := Color(1.0, 0.6, 0.2, 0.16)
	var c: Vector2 = to_map.call(ft.get("pos", Vector2.ZERO))
	if ft.get("shape", "ring") == "cloud":
		canvas.draw_circle(c, float(ft["radius"]) * k, col)
		return
	var half: float = ft.get("arc_half", PI)
	var mid: float = ft.get("arc_mid", 0.0)
	var a0: float = 0.0 if half >= PI else mid - half
	var a1: float = TAU if half >= PI else mid + half
	canvas.draw_arc(c, (float(ft["inner"]) + float(ft["outer"])) / 2.0 * k, a0, a1, 64, col, (float(ft["outer"]) - float(ft["inner"])) * k)

## Soft orange-magenta haze, densest in the middle of the gas, fading at the
## edges.
func _paint() -> Image:
	var reach := radius if shape == "cloud" else outer
	var n := int(ceil(reach * 2.0 / PIXEL)) + 22
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var cols := [Color("5a1f3a"), Color("8a2e3f"), Color("c8522a"), Color("ff9a2e")]
	var bayer := [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
	var c := n / 2.0
	var mid := (inner + outer) / 2.0
	var half := (outer - inner) / 2.0
	for y in n:
		for x in n:
			var off := Vector2(x - c, y - c) * PIXEL
			var d := off.length()
			var body: float
			if shape == "cloud":
				if d > radius + 40.0:
					continue
				body = 1.0 - clampf(d / (radius + 40.0), 0.0, 1.0)
				body = sqrt(body)
			else:
				if d < inner - 40.0 or d > outer + 40.0:
					continue
				body = 1.0 - clampf(absf(d - mid) / (half + 40.0), 0.0, 1.0)
				if arc_half < PI:
					# Thin out toward the arc's ends instead of stopping dead.
					var off_a := absf(angle_difference(arc_mid, off.angle()))
					body *= clampf((arc_half + 0.12 - off_a) / 0.3, 0.0, 1.0)
			var v := body * 0.8 + noise.get_noise_2d(x, y) * 0.5
			if v <= 0.1:
				continue
			# Color bands picked with a light ordered dither; alpha stays soft.
			var t: float = (bayer[y % 4][x % 4] + 0.5) / 16.0 - 0.5
			var col: Color = cols[clampi(int((v + t * 0.25) * cols.size()), 0, cols.size() - 1)]
			col.a = clampf(v, 0.0, 1.0) * 0.26
			img.set_pixel(x, y, col)
	return img
