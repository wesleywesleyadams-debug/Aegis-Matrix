class_name TechIcons
## A picture for every technology, painted at runtime from its data so the
## icons can never fall out of step with the tech list:
##   tile    - a rounded square in the tech's group colour (a Defense line's
##             own layer colour), with a faint pattern chosen by its id, so
##             even two techs with the same effect never look the same
##   glyph   - the tech's main effect drawn as a symbol (a crosshair for
##             range, wheat for food...); unlocks and marks show the ship or
##             station they are about
##   badge   - its second effect, small, in the top-right corner
##   pips    - its tier, bottom-right
## Icons are SIZE px square, pixel-art crisp, and cached.

const SIZE := 120
## Drawing scale against the 64-unit grid the pictures are laid out on.
const K := SIZE / 64.0
const GROUP_COLORS := {
	"warships": Color("4fa8ff"), "weapons": Color("ff6a4a"), "defense": Color("7fd8ff"),
	"constructs": Color("ffb347"), "worlds": Color("6fe07a"), "logistics": Color("3fd6b0"),
	"mods": Color("c77dff"),
}

## Non-Mod techs whose (redesigned) art is shown in full colour.
const COLOR_ICONS := ["aegis_matrix", "adaptive_hulls", "glance_plates", "graviton_shunts", "living_metals"]

static var _cache := {}

static func icon(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var tex := ImageTexture.create_from_image(_paint(id))
	_cache[id] = tex
	return tex

static func _paint(id: String) -> Image:
	var t: Dictionary = Defs.TECHS.get(id, {})
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var art := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var fx: Dictionary = t.get("effects", {})
	var main_fx: String = str(fx.keys()[0]) if not fx.is_empty() else ""
	var drawn := TechScenes.paint(id, art)
	if not drawn and (main_fx.begins_with("unlock_") or main_fx.begins_with("mark_") or main_fx.begins_with("mod_")):
		_sprite(art, _sprite_for(main_fx))
		drawn = true
	if drawn:
		_plaque(img, art, BORDER_COLORS.get(t.get("group", ""), GOLD), t.has("mod") or COLOR_ICONS.has(id))
		if main_fx.begins_with("mark_"):
			# As many chevrons as the ship itself shows at that mark (Mk I
			# has one, so Mk II two ... Mk IV four).
			var mk := int(id.get_slice("_mk", 1)) if "_mk" in id else 2
			for k in mk:
				_line(img, Vector2(7 + k * 7, 13) * K, Vector2(10 + k * 7, 9) * K, 2.0 * K, GOLD)
				_line(img, Vector2(10 + k * 7, 9) * K, Vector2(13 + k * 7, 13) * K, 2.0 * K, GOLD)
		for k in (0 if t.has("mod") else int(t.get("tier", 1))):
			_disc(img, Vector2(55 - k * 7, 55) * K, 2.4 * K, GOLD)
		return img
	var col: Color = GROUP_COLORS.get(t.get("group", ""), Color("a8b4d4"))
	var line: String = t.get("line", "")
	if line != "":
		col = Defs.LAYER_COLORS.get(line.trim_suffix("s"), col) if line != "deflectors" else Color("c9b6ff")
	_tile(img, col, hash(id))
	var keys: Array = t.get("effects", {}).keys()
	var main: String = keys[0] if not keys.is_empty() else ""
	# Each tech's own variation, visible at card size: the glyph's hue is
	# nudged and a small emblem sits bottom-left, both chosen by its id.
	var h := absi(hash(id))
	var glyph_col := col.lightened(0.55)
	glyph_col.h = fposmod(glyph_col.h + (float(h % 5) - 2.0) * 0.035, 1.0)
	if main.begins_with("unlock_") or main.begins_with("mark_"):
		_sprite(img, _sprite_for(main))
	else:
		# Techs sharing a main effect each get their own arrangement of its
		# glyph - single, mirrored, a pair, or ringed - so none look alike.
		match _variant(id, main) % 4:
			0:
				_glyph(img, main, Vector2(32, 34), 1.0, glyph_col)
			1:
				_glyph(img, main, Vector2(32, 34), 1.0, glyph_col)
				img.flip_x()
			2:
				_glyph(img, main, Vector2(22, 26), 0.62, glyph_col)
				_glyph(img, main, Vector2(41, 41), 0.62, glyph_col.darkened(0.15))
			3:
				_ring(img, Vector2(32, 34), 23.0, 2.0, glyph_col.darkened(0.35))
				_glyph(img, main, Vector2(32, 34), 0.78, glyph_col)
	# Drawn after the glyph, so a mirrored glyph never moves it.
	_emblem(img, (h / 5) % 6, Vector2(9, 55), col.lightened(0.25))
	if keys.size() > 1:
		# A dark disc to sit the badge on, then the second effect inside it.
		_disc(img, Vector2(51, 13), 10.0, Color(0.03, 0.04, 0.09, 0.92))
		_ring(img, Vector2(51, 13), 10.0, 1.5, col)
		_glyph(img, str(keys[1]), Vector2(51, 13), 0.36, col.lightened(0.4))
	if main.begins_with("mark_"):
		# Mk II-IV: as many chevrons as the ship itself shows at that mark
		# (Mk I has one, so Mk II has two ... Mk IV four).
		var mk := int(id.get_slice("_mk", 1)) if "_mk" in id else 2
		for k in mk:
			_line(img, Vector2(6 + k * 7, 12), Vector2(9 + k * 7, 8), 2.0, Color("ffd84a"))
			_line(img, Vector2(9 + k * 7, 8), Vector2(12 + k * 7, 12), 2.0, Color("ffd84a"))
	for k in (0 if t.has("mod") else int(t.get("tier", 1))):
		_disc(img, Vector2(56 - k * 7, 56), 2.4, Color("ffd84a"))
	return img

# ---------------------------------------------------------------- tile

const GOLD := Color("ffd23a")
## Plaque border per research category.
const BORDER_COLORS := {
	"weapons": Color("ff3a2e"), "defense": Color("8fd8ff"), "worlds": Color("4fd860"),
	"logistics": Color("ffd23a"), "constructs": Color("f2f2f2"), "warships": Color("ff8a1e"),
	"mods": Color("c77dff"),
}

## The house style: a black plaque with a yellow border, and the art on it
## rendered as polished metal - its colours kept faintly, its shape carried
## by hard highlights on top-left edges, deep shadow on bottom-right edges,
## and a chrome sheen band across the surface.
## `full_color`: keep the art's own colours (Mods, whose weapon effects are
## the point) instead of the usual mostly-grey metal plaque.
static func _plaque(img: Image, art: Image, edge: Color = GOLD, full_color := false) -> void:
	img.fill(Color(0, 0, 0, 1))
	for y in range(6, SIZE - 6):
		for x in range(6, SIZE - 6):
			var c := art.get_pixel(x, y)
			if c.a < 0.05:
				# A drop shadow cast down-right onto the black.
				if art.get_pixel(x - 3, y - 3).a > 0.3:
					img.set_pixel(x, y, Color(0.0, 0.0, 0.0))
				continue
			var lum := c.get_luminance()
			var band := 0.5 + 0.5 * sin((lum * 2.2 + float(x + y) / (36.0 * K)) * PI)
			var v := clampf(0.1 + lum * 0.5 + band * 0.5, 0.0, 1.0)
			if art.get_pixel(x - 1, y - 1).a < 0.05:
				v = 1.0
			elif art.get_pixel(x + 1, y + 1).a < 0.05:
				v *= 0.25
			var grey := Color(v, v, v)
			var m := grey.lerp(c * (0.4 + v), 0.3)
			if full_color:
				m = c * (0.75 + 0.35 * v)
			img.set_pixel(x, y, Color(0, 0, 0).lerp(Color(m.r, m.g, m.b), minf(c.a * 1.4, 1.0)))
	for y in SIZE:
		for x in SIZE:
			var d := mini(mini(x, y), mini(SIZE - 1 - x, SIZE - 1 - y))
			if d < 5:
				img.set_pixel(x, y, edge if d >= 1 and d <= 3 else edge.darkened(0.4))

static func _tile(img: Image, col: Color, seed_v: int) -> void:
	var bg := col.darkened(0.78)
	var edge := col.darkened(0.25)
	var pattern := absi(seed_v) % 4
	for y in SIZE:
		for x in SIZE:
			# Rounded corners.
			var cx := clampi(x, 6, SIZE - 7)
			var cy := clampi(y, 6, SIZE - 7)
			var d := Vector2(x - cx, y - cy).length()
			if d > 6.0:
				continue
			var c := bg
			match pattern:
				1:
					if (x + y) % 8 < 2:
						c = bg.lightened(0.06)
				2:
					if x % 6 == 0 and y % 6 == 0:
						c = bg.lightened(0.12)
				3:
					var a := Vector2(x - 32, y - 32).angle()
					if int(floor((a + PI) / (TAU / 16.0))) % 2 == 0:
						c = bg.lightened(0.05)
			if d > 4.5 or x < 2 or y < 2 or x > SIZE - 3 or y > SIZE - 3:
				c = edge
			img.set_pixel(x, y, c)

# ---------------------------------------------------------------- sprites

static func _sprite_for(effect: String) -> String:
	var what := effect.get_slice("_", 1)
	if what == "depot":
		return "ship_depot_plasma"
	if what == "outpost":
		return "ship_frontier_outpost"
	if what == "warp":
		return "ship_warp_gate"
	return "ship_" + what

static func _sprite(img: Image, tex_name: String) -> void:
	var tex := Defs.tex(tex_name)
	if tex == null:
		return
	var src := tex.get_image()
	if src == null:
		return
	src = src.duplicate()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	# Fit inside the tile, crisp.
	var room := 44.0 * K
	var k: float = room / maxf(src.get_width(), src.get_height())
	var w := maxi(1, int(src.get_width() * k))
	var h := maxi(1, int(src.get_height() * k))
	src.resize(w, h, Image.INTERPOLATE_NEAREST)
	var team := Defs.tex(tex_name + "_team")
	var tim: Image = null
	if team:
		tim = team.get_image().duplicate()
		if tim.is_compressed():
			tim.decompress()
		tim.convert(Image.FORMAT_RGBA8)
		tim.resize(w, h, Image.INTERPOLATE_NEAREST)
	var ox := (SIZE - w) / 2
	var oy := (SIZE - h) / 2 + int(2 * K)
	for y in h:
		for x in w:
			var c := src.get_pixel(x, y)
			if tim != null and tim.get_pixel(x, y).a > 0.0:
				c = Defs.team_color(1) * tim.get_pixel(x, y).r
				c.a = 1.0
			if c.a > 0.0:
				img.set_pixel(ox + x, oy + y, img.get_pixel(ox + x, oy + y).blend(c))

# ---------------------------------------------------------------- glyphs

## The symbol for one effect, centred on `c`, at `s` times full size.
static func _glyph(img: Image, effect: String, c: Vector2, s: float, col: Color) -> void:
	var p := func(x: float, y: float) -> Vector2: return c + Vector2(x, y) * s
	var w := maxf(2.0 * s * 1.6, 1.4)
	match effect:
		"damage":
			# A bolt striking a burst.
			_line(img, p.call(-16, 14), p.call(6, -8), w * 1.3, col)
			_burst(img, p.call(8, -10), 10.0 * s, col)
		"fire_rate":
			for k in 3:
				_chevron(img, p.call(-10 + k * 9, 0), 9.0 * s, w, col)
		"range":
			_ring(img, c, 15.0 * s, w, col)
			_ring(img, c, 6.0 * s, w, col)
			_line(img, p.call(-20, 0), p.call(-9, 0), w, col)
			_line(img, p.call(9, 0), p.call(20, 0), w, col)
			_line(img, p.call(0, -20), p.call(0, -9), w, col)
			_line(img, p.call(0, 9), p.call(0, 20), w, col)
		"shield":
			_arc(img, p.call(0, 8), 18.0 * s, PI, TAU, w * 1.4, col)
			_arc(img, p.call(0, 8), 11.0 * s, PI, TAU, w, col.darkened(0.25))
			_line(img, p.call(-20, 8), p.call(20, 8), w, col)
		"armor":
			_poly(img, [p.call(-15, -16), p.call(15, -16), p.call(15, 2), p.call(0, 18), p.call(-15, 2)], col.darkened(0.2))
			_poly(img, [p.call(-10, -11), p.call(10, -11), p.call(10, 0), p.call(0, 11), p.call(-10, 0)], col)
		"hull":
			_hex(img, c, 17.0 * s, w * 1.2, col)
			_line(img, p.call(-14, 0), p.call(14, 0), w, col)
			_line(img, p.call(-7, -12), p.call(7, 12), w, col)
			_line(img, p.call(7, -12), p.call(-7, 12), w, col)
		"damage_taken":
			for k in 3:
				_arc(img, p.call(-14, 0), (10.0 + k * 7.0) * s, -0.9, 0.9, w, col.darkened(k * 0.2))
		"speed":
			_poly(img, [p.call(-6, -12), p.call(16, 0), p.call(-6, 12), p.call(-1, 0)], col)
			for k in 3:
				_line(img, p.call(-18, -8 + k * 8), p.call(-9, -8 + k * 8), w, col.darkened(0.25))
		"cargo":
			_box(img, p.call(-14, -12), p.call(14, 14), col.darkened(0.2))
			_line(img, p.call(-14, -2), p.call(14, -2), w, col)
			_line(img, p.call(0, -12), p.call(0, 14), w, col)
			_frame(img, p.call(-14, -12), p.call(14, 14), w, col)
		"harvest":
			# A drill bit biting a rock.
			_poly(img, [p.call(-16, -14), p.call(-6, -14), p.call(10, 6), p.call(4, 12)], col)
			_disc(img, p.call(12, 12), 7.0 * s, Color("8a7069"))
		"food":
			_line(img, p.call(0, 18), p.call(0, -16), w, col)
			for k in 3:
				_ellipse(img, p.call(-6, -10 + k * 9), Vector2(6, 3) * s, col)
				_ellipse(img, p.call(6, -10 + k * 9), Vector2(6, 3) * s, col)
		"growth":
			_line(img, p.call(0, 16), p.call(0, -6), w, col)
			_ellipse(img, p.call(-7, -6), Vector2(8, 4) * s, col)
			_ellipse(img, p.call(7, -12), Vector2(8, 4) * s, col)
			_chevron_up(img, p.call(0, -16), 7.0 * s, w, col)
		"max_pop":
			for k in 3:
				var o: Vector2 = p.call(-12 + k * 12, 4)
				_disc(img, o + Vector2(0, -9) * s, 4.5 * s, col)
				_arc(img, o + Vector2(0, 8) * s, 8.0 * s, PI, TAU, w * 1.5, col)
		"colony_pop":
			_disc(img, c, 13.0 * s, col.darkened(0.35))
			_disc(img, p.call(0, -4), 5.0 * s, col)
			_arc(img, p.call(0, 10), 9.0 * s, PI, TAU, w * 1.4, col)
		"food_per_pop":
			_arc(img, p.call(0, -2), 16.0 * s, 0.0, PI, w * 1.5, col)
			_line(img, p.call(-17, -2), p.call(17, -2), w, col)
			_ellipse(img, p.call(0, -7), Vector2(9, 4) * s, col.darkened(0.2))
		"energy":
			_poly(img, [p.call(4, -18), p.call(-10, 2), p.call(0, 2), p.call(-4, 18), p.call(10, -2), p.call(0, -2)], col)
		"structure":
			_box(img, p.call(-12, -8), p.call(12, 16), col.darkened(0.2))
			for k in 3:
				_box(img, p.call(-12 + k * 9, -16), p.call(-6 + k * 9, -8), col)
			_frame(img, p.call(-12, -8), p.call(12, 16), w, col)
		"structure_damage":
			_disc(img, p.call(0, 6), 10.0 * s, col.darkened(0.2))
			_line(img, p.call(0, 4), p.call(16, -14), w * 1.6, col)
			_box(img, p.call(-14, 12), p.call(14, 17), col)
		"structure_range":
			_arc(img, p.call(-4, 6), 15.0 * s, -2.4, 0.8, w * 1.3, col)
			_line(img, p.call(-4, 6), p.call(8, -6), w, col)
			_disc(img, p.call(8, -6), 3.0 * s, col)
			_line(img, p.call(-4, 6), p.call(-4, 18), w * 1.3, col)
		"build_speed":
			_gear(img, c, 13.0 * s, col)
			_disc(img, c, 5.0 * s, Color(0.03, 0.04, 0.09))
		"construct_speed":
			_line(img, p.call(-12, 14), p.call(6, -4), w * 1.6, col.darkened(0.25))
			_poly(img, [p.call(0, -16), p.call(16, -2), p.call(10, 4), p.call(-6, -10)], col)
		"construct_start":
			_frame(img, p.call(-14, -14), p.call(14, 14), w, col)
			_line(img, p.call(-14, -14), p.call(14, 14), w, col)
			_line(img, p.call(14, -14), p.call(-14, 14), w, col)
			_box(img, p.call(-14, 4), p.call(14, 14), col.darkened(0.15))
		"planet_shield":
			_disc(img, p.call(0, 4), 10.0 * s, Color("3d8fc8"))
			_arc(img, p.call(0, 4), 17.0 * s, PI, TAU, w * 1.4, col)
			_arc(img, p.call(0, 4), 17.0 * s, 0.0, PI, w * 0.8, col.darkened(0.4))
		"upkeep":
			_ring(img, c, 15.0 * s, w * 1.3, col)
			_line(img, p.call(-8, 0), p.call(8, 0), w * 1.6, col)
		_:
			_disc(img, c, 8.0 * s, col)

## This tech's position among all techs whose main effect is `main`, in the
## order they are defined.
static func _variant(id: String, main: String) -> int:
	var n := 0
	for t in Defs.TECHS:
		if t == id:
			return n
		var ks: Array = Defs.TECHS[t].get("effects", {}).keys()
		if not ks.is_empty() and ks[0] == main:
			n += 1
	return n

## Six small marks, one per tech by id, so two techs with the same effect
## still read as different pictures.
static func _emblem(img: Image, kind: int, c: Vector2, col: Color) -> void:
	match kind:
		0: _disc(img, c, 3.0, col)
		1: _ring(img, c, 3.0, 1.2, col)
		2: _poly(img, [c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)], col)
		3: _box(img, c - Vector2(4, 1), c + Vector2(4, 2), col)
		4: _poly(img, [c + Vector2(0, -4), c + Vector2(4, 3), c + Vector2(-4, 3)], col)
		5:
			_line(img, c - Vector2(3, 3), c + Vector2(3, 3), 1.4, col)
			_line(img, c + Vector2(-3, 3), c + Vector2(3, -3), 1.4, col)

# ---------------------------------------------------------------- primitives
# All bounded to the shape's own box, so painting stays cheap.

static func _put(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
		img.set_pixel(x, y, img.get_pixel(x, y).blend(col))

static func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in range(int(c.y - r) - 1, int(c.y + r) + 2):
		for x in range(int(c.x - r) - 1, int(c.x + r) + 2):
			if Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				_put(img, x, y, col)

static func _ring(img: Image, c: Vector2, r: float, w: float, col: Color) -> void:
	_arc(img, c, r, -PI, PI, w, col)

static func _arc(img: Image, c: Vector2, r: float, a0: float, a1: float, w: float, col: Color) -> void:
	var o := r + w
	for y in range(int(c.y - o) - 1, int(c.y + o) + 2):
		for x in range(int(c.x - o) - 1, int(c.x + o) + 2):
			var v := Vector2(x + 0.5, y + 0.5) - c
			if absf(v.length() - r) > w / 2.0:
				continue
			var a := v.angle()
			if a1 - a0 >= TAU - 0.001 or (a >= a0 and a <= a1) or (a + TAU >= a0 and a + TAU <= a1):
				_put(img, x, y, col)

static func _line(img: Image, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * w
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * w
	for y in range(int(lo.y), int(hi.y) + 1):
		for x in range(int(lo.x), int(hi.x) + 1):
			var pt := Vector2(x + 0.5, y + 0.5)
			var ab := b - a
			var t := clampf((pt - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			if pt.distance_to(a + ab * t) <= w / 2.0:
				_put(img, x, y, col)

static func _poly(img: Image, pts: Array, col: Color) -> void:
	var packed := PackedVector2Array(pts)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in pts:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	for y in range(int(lo.y), int(hi.y) + 1):
		for x in range(int(lo.x), int(hi.x) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), packed):
				_put(img, x, y, col)

static func _box(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	for y in range(int(a.y), int(b.y)):
		for x in range(int(a.x), int(b.x)):
			_put(img, x, y, col)

static func _frame(img: Image, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	_line(img, a, Vector2(b.x, a.y), w, col)
	_line(img, Vector2(b.x, a.y), b, w, col)
	_line(img, b, Vector2(a.x, b.y), w, col)
	_line(img, Vector2(a.x, b.y), a, w, col)

static func _ellipse(img: Image, c: Vector2, r: Vector2, col: Color) -> void:
	for y in range(int(c.y - r.y) - 1, int(c.y + r.y) + 2):
		for x in range(int(c.x - r.x) - 1, int(c.x + r.x) + 2):
			var v := (Vector2(x + 0.5, y + 0.5) - c) / r
			if v.length() <= 1.0:
				_put(img, x, y, col)

static func _chevron(img: Image, c: Vector2, s: float, w: float, col: Color) -> void:
	_line(img, c + Vector2(-s * 0.5, -s), c + Vector2(s * 0.5, 0), w, col)
	_line(img, c + Vector2(s * 0.5, 0), c + Vector2(-s * 0.5, s), w, col)

static func _chevron_up(img: Image, c: Vector2, s: float, w: float, col: Color) -> void:
	_line(img, c + Vector2(-s, s * 0.6), c, w, col)
	_line(img, c, c + Vector2(s, s * 0.6), w, col)

static func _hex(img: Image, c: Vector2, r: float, w: float, col: Color) -> void:
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		_line(img, c + Vector2.from_angle(a0) * r, c + Vector2.from_angle(a1) * r, w, col)

static func _burst(img: Image, c: Vector2, r: float, col: Color) -> void:
	var pts: Array = []
	for k in 16:
		pts.append(c + Vector2.from_angle(TAU * k / 16.0) * (r if k % 2 == 0 else r * 0.45))
	_poly(img, pts, col)

static func _gear(img: Image, c: Vector2, r: float, col: Color) -> void:
	_disc(img, c, r * 0.75, col)
	for k in 8:
		var a := TAU * k / 8.0
		_line(img, c + Vector2.from_angle(a) * r * 0.6, c + Vector2.from_angle(a) * r * 1.1, r * 0.32, col)
