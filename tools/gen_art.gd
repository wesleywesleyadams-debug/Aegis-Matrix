extends SceneTree
## Procedural pixel-art generator for Star Lords' placeholder sprites.
## Run headless from the project root:
##   Godot --headless --path . --script res://tools/gen_art.gd
## Writes PNGs into res://assets/pixel/. Re-running overwrites them, so
## hand-edited replacements should get new file names.
##
## Ships face +X (right). Each ship/station has two layers: <name>.png
## (hull, fixed colors) and <name>_team.png (grayscale-shaded white pixels
## that the game tints with the owner's color via modulate).

const OUT := "res://assets/pixel/"

const OUTLINE := Color("0e0d1c")
const HULL := [Color("20233a"), Color("363d5c"), Color("566184"), Color("8490b3"), Color("c3cde4")]
const TEAM := [Color(0.45, 0.45, 0.45), Color(0.7, 0.7, 0.7), Color(0.92, 0.92, 0.92), Color(1, 1, 1)]
const GLASS := [Color("1b4f7a"), Color("3fa7d6"), Color("a8f0ff")]
const ENGINE := [Color("ff7a3d"), Color("ffd46b"), Color("fff6d0")]
const ROCK := [Color("241c24"), Color("3b2f36"), Color("5d4a4f"), Color("8a7069"), Color("b39a86")]
const MINERAL := [Color("1f7a6a"), Color("3fd6b0"), Color("b8ffe9")]
const SPICE := [Color("a3461f"), Color("ff9a2e"), Color("ffe08a")]

const BAYER := [
	[0, 8, 2, 10],
	[12, 4, 14, 6],
	[3, 11, 1, 9],
	[15, 7, 13, 5],
]

var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.seed = 7331
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# ART_ONLY=ships regenerates just the ship sprites.
	if OS.get_environment("ART_ONLY") == "ships":
		_gen_ships()
		_gen_job_ships()
		_gen_variants()
		_gen_depot()
		_gen_mining_station()
		_gen_hull_marks()
		_gen_layer_art()
		quit()
		return
	_gen_ships()
	_gen_job_ships()
	_gen_variants()
	_gen_depot()
	_gen_mining_station()
	_gen_hull_marks()
	_gen_layer_art()
	_gen_starbase()
	_gen_planets()
	_gen_star()
	_gen_asteroids()
	_gen_fx()
	_gen_backgrounds()
	_gen_icons()
	_gen_icons2()
	_gen_buildings()
	_gen_title()
	print("Star Lords art generated.")
	quit()

# ---------------------------------------------------------------- helpers

func _img(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img

func _save(img: Image, name: String) -> void:
	img.save_png(OUT + name + ".png")
	# Planets also get small and large versions, re-rendered from the same
	# shading at other diameters (even sizes keep the sphere centered).
	if name.begins_with("planet_"):
		for pair in [["_s", 0.78], ["_l", 1.25]]:
			var s := int(round(img.get_width() * pair[1] / 2.0)) * 2
			_sphere(s, _last_shade, _last_atmo).save_png(OUT + name + pair[0] + ".png")

func _dither(value: float, x: int, y: int, steps: int) -> int:
	## Maps value in [0,1] to an index in [0, steps-1] with 4x4 ordered dither.
	var t: float = (BAYER[y % 4][x % 4] + 0.5) / 16.0 - 0.5
	return clampi(int(floor(value * (steps - 1) + 0.5 + t * 0.9)), 0, steps - 1)

func _inside(pts: PackedVector2Array, x: int, y: int) -> bool:
	return Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts)

func _outline(img: Image, color: Color = OUTLINE) -> void:
	var src := img.duplicate()
	for y in img.get_height():
		for x in img.get_width():
			if src.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p: Vector2i = Vector2i(x, y) + d
				if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height() and src.get_pixelv(p).a > 0.0 and src.get_pixelv(p) != color:
					img.set_pixel(x, y, color)
					break

func _pts(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(Vector2(p[0], p[1]))
	return out

# ---------------------------------------------------------------- ships

## A ship is a stack of mirrored trapezoid "parts" along its centerline:
## [x0, x1, half_width_at_x0, half_width_at_x1, y_offset]. y_offset != 0
## places the part twice (above and below the keel), for claws/pylons.
## team_fn(x, dy) says which hull pixels get the owner's color.
## glass: [x, w]; engines: stern pixel rows (dy values).
func _ship(name: String, w: int, h: int, parts: Array, team_fn: Callable, glass: Array, engines: Array, panels: Array, extras: Callable = Callable()) -> void:
	var img := _img(w + 2, h + 2)
	var tim := _img(w + 2, h + 2)
	var cy := h / 2.0
	var mask := {}
	var shade := {}
	for part in parts:
		var off: float = part[4] if part.size() > 4 else 0.0
		for sgn in ([1.0, -1.0] if off != 0.0 else [1.0]):
			for x in range(part[0], part[1]):
				var t: float = (x + 0.5 - part[0]) / maxf(part[1] - part[0], 1.0)
				var hw: float = lerpf(part[2], part[3], t)
				for y in h:
					var dy: float = y + 0.5 - cy - off * sgn
					if absf(dy) <= hw:
						var key := Vector2i(x, y)
						mask[key] = true
						# Rounded-cylinder shading, lit from above.
						var n: float = dy / maxf(hw, 0.5)
						shade[key] = maxf(shade.get(key, -9.0), 0.62 - n * 0.4)
	for key in mask:
		var x: int = key.x
		var y: int = key.y
		var dy := y + 0.5 - cy
		var v: float = shade[key]
		var idx := clampi(int(v * HULL.size()), 1, HULL.size() - 2)
		if not mask.has(Vector2i(x, y - 1)):
			idx = HULL.size() - 1
		elif not mask.has(Vector2i(x, y + 1)):
			idx = 0
		elif x in panels:
			idx = maxi(idx - 1, 1)
		if team_fn.call(x, dy):
			tim.set_pixel(x + 1, y + 1, TEAM[clampi(idx - 1, 0, TEAM.size() - 1)])
			img.set_pixel(x + 1, y + 1, HULL[1])
		else:
			img.set_pixel(x + 1, y + 1, HULL[idx])
	# Cockpit glass on the centerline.
	for gx in glass[1]:
		img.set_pixel(glass[0] + gx + 1, int(cy) , GLASS[2])
		img.set_pixel(glass[0] + gx + 1, int(cy) + 1, GLASS[0] if gx == 0 else GLASS[1])
	for e in engines:
		img.set_pixel(1, int(cy + e) + 1, ENGINE[1])
	# Job details (sensor dishes, shield plates, glow strips...) drawn on top.
	if extras.is_valid():
		extras.call(img, cy + 1.0)
	_outline(img)
	_save(img, "ship_" + name)
	_save(tim, "ship_" + name + "_team")

func _gen_ships() -> void:
	# Corvette: swept-wing interceptor.
	_ship("corvette", 18, 13,
		[[3, 18, 2.5, 0.4], [2, 10, 6.5, 1.0], [0, 4, 2.0, 2.0]],
		func(x: int, dy: float) -> bool: return absf(dy) > 4.0,
		[11, 3], [-1.0, 0.0], [7])
	# Destroyer: long gun spine with mid wings.
	_ship("destroyer", 28, 15,
		[[2, 28, 2.5, 0.6], [4, 20, 4.0, 2.5], [6, 13, 7.5, 3.0], [0, 5, 3.0, 3.0], [18, 26, 1.0, 0.5, 3.5]],
		func(x: int, dy: float) -> bool: return absf(dy) > 5.0 or (x >= 14 and x <= 15 and absf(dy) < 3.0),
		[16, 3], [-2.0, -1.0, 0.0, 1.0], [10, 14])
	# Cruiser: capital hull, broad hangar wings, twin prow.
	_ship("cruiser", 38, 23,
		[[3, 32, 6.0, 4.0], [30, 38, 3.5, 0.6], [6, 17, 11.5, 5.0], [0, 5, 5.0, 5.0], [24, 34, 1.2, 0.6, 5.5], [10, 15, 2.0, 2.0, 9.0]],
		func(x: int, dy: float) -> bool: return absf(dy) > 8.0 or (x >= 21 and x <= 23),
		[26, 4], [-4.0, -3.0, -1.0, 0.0, 2.0, 3.0], [9, 13, 18, 28])
	# Colony ship: fat habitat drum with a small bridge.
	_ship("colony", 18, 15,
		[[2, 14, 4.0, 4.0], [4, 11, 6.5, 6.5], [13, 18, 2.5, 0.6], [0, 3, 2.0, 2.0]],
		func(x: int, dy: float) -> bool: return (x == 6 or x == 9) and absf(dy) > 1.5,
		[14, 2], [-1.0, 0.0], [5, 10])
	# Gas skimmer: long intake scoop up front, tanks behind.
	_ship("skimmer", 20, 15,
		[[2, 12, 3.5, 3.5], [3, 10, 1.6, 1.6, 5.0], [11, 20, 2.0, 5.5], [0, 3, 2.0, 2.0]],
		func(x: int, dy: float) -> bool: return absf(dy) > 3.4 and x < 11,
		[8, 2], [-1.0, 0.0], [6, 14])
	# Constructor: boxy yard hull carrying its tools up front — a hammer head
	# above the nose and a pickaxe below it, so it never reads as a barge.
	_ship("constructor", 20, 17,
		[[2, 13, 4.5, 4.5], [3, 10, 2.0, 2.0, 5.5], [0, 3, 2.2, 2.2]],
		func(x: int, dy: float) -> bool: return absf(dy) > 4.0 and x < 11,
		[9, 2], [-1.0, 0.0], [6],
		func(img: Image, cy: float) -> void:
			var steel := HULL[3]
			var lit := HULL[4]
			var dark := HULL[1]
			# Hammer: a short shaft off the nose carrying a square head high.
			for x in range(13, 17):
				_px(img, x, cy - 4, steel)
			for x in range(16, 20):
				for y in range(-7, -3):
					_px(img, x, cy + y, steel)
			for y in range(-7, -2):
				_px(img, 19, cy + y, dark)
			for x in range(16, 19):
				_px(img, x, cy - 7, lit)
			# Pickaxe: a haft below the nose with a swept double point.
			for y in range(1, 5):
				_px(img, 15, cy + y, steel)
			for k in 3:
				_px(img, 12 + k, cy + 4 - k, steel)
				_px(img, 12 + k, cy + 5 - k, dark)
				_px(img, 18 - k, cy + 4 - k, steel)
				_px(img, 18 - k, cy + 5 - k, dark)
			_px(img, 11, cy + 5, dark)
			_px(img, 19, cy + 5, dark)
			_px(img, 15, cy + 5, lit))
	# Mining barge: cargo pods and a forward grab claw.
	_ship("miner", 16, 15,
		[[2, 11, 3.5, 3.5], [3, 9, 1.5, 1.5, 5.0], [10, 16, 1.5, 0.6, 3.0], [0, 3, 2.0, 2.0]],
		func(x: int, dy: float) -> bool: return absf(dy) > 3.6 and x < 10,
		[7, 2], [-1.0, 0.0], [6])

func _gen_starbase() -> void:
	var s := 56
	var img := _img(s, s)
	var tim := _img(s, s)
	var c := Vector2(s / 2.0, s / 2.0)
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5) - c
			var r := p.length()
			var ang := atan2(p.y, p.x)
			var lit := clampf(0.5 - (p.x + p.y) / (s * 0.9), 0.0, 1.0)
			var draw := false
			var v := lit
			# Outer habitat ring.
			if r >= 19.0 and r <= 24.0:
				draw = true
				v = lit * 0.8 + (1.0 - absf(r - 21.5) / 2.5) * 0.25
				# Segment seams.
				if fposmod(ang * 12.0 / TAU, 1.0) < 0.12:
					v -= 0.3
			# Spokes.
			elif r < 19.0 and r > 8.0 and fposmod(ang + PI / 4.0, PI / 2.0) < 0.22:
				draw = true
				v = lit * 0.6
			# Hub.
			elif r <= 8.5:
				draw = true
				v = lit * 0.7 + (1.0 - r / 8.5) * 0.4
			if draw:
				img.set_pixel(x, y, HULL[_dither(clampf(v, 0, 1), x, y, HULL.size())])
			# Team-colored beacon pads on the ring at 8 points.
			if r >= 20.0 and r <= 23.0 and fposmod(ang * 8.0 / TAU + 0.5, 1.0) < 0.22 and fposmod(ang * 8.0 / TAU + 0.5, 1.0) > 0.0:
				tim.set_pixel(x, y, TEAM[_dither(clampf(lit + 0.3, 0, 1), x, y, TEAM.size())])
			# Hub team core.
			if r <= 3.5:
				tim.set_pixel(x, y, TEAM[3 if r < 2 else 2])
	# Docking arms sticking out on the diagonals.
	for k in 4:
		var dir := Vector2.from_angle(PI / 4.0 + k * PI / 2.0)
		for t in range(24, 27):
			var q := c + dir * t
			img.set_pixel(int(q.x), int(q.y), HULL[3])
			img.set_pixel(int(q.x + 1), int(q.y), HULL[2])
	_outline(img)
	_save(img, "starbase")
	_save(tim, "starbase_team")

# ---------------------------------------------------------------- planets

var _last_shade: Callable
var _last_atmo: Color

func _sphere(size: int, shade_fn: Callable, atmo: Color = Color(0, 0, 0, 0)) -> Image:
	_last_shade = shade_fn
	_last_atmo = atmo
	var img := _img(size, size)
	var r := size / 2.0 - 1.0
	var light := Vector3(-0.55, -0.5, 0.67).normalized()
	for y in size:
		for x in size:
			var px := (x + 0.5 - size / 2.0) / r
			var py := (y + 0.5 - size / 2.0) / r
			var d2 := px * px + py * py
			if d2 > 1.0:
				continue
			var n := Vector3(px, py, sqrt(1.0 - d2))
			var l := clampf(n.dot(light) * 0.9 + 0.2, 0.0, 1.0)
			var c: Color = shade_fn.call(n, l, x, y)
			if atmo.a > 0.0 and d2 > 0.86:
				c = c.lerp(atmo, 0.55 * clampf(l + 0.3, 0.0, 1.0))
			img.set_pixel(x, y, c)
	_outline(img, Color("07060f"))
	return img

func _ramp_pick(ramp: Array, v: float, x: int, y: int) -> Color:
	return ramp[_dither(v, x, y, ramp.size())]

func _gen_planets() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 4
	noise.frequency = 1.6

	# Terran world: oceans, continents, cloud cover.
	var ocean := [Color("0d1b3d"), Color("163a6b"), Color("2466a0"), Color("3d8fc8")]
	var land := [Color("1b3320"), Color("2f5a2c"), Color("4f8a3a"), Color("8fb85a")]
	var cloud := [Color("7e8ca8"), Color("c9d4e6"), Color("ffffff")]
	noise.seed = 11
	var terran := _sphere(72, func(n: Vector3, l: float, x: int, y: int) -> Color:
		var h := noise.get_noise_3d(n.x, n.y, n.z)
		var cl := noise.get_noise_3d(n.x * 2.0 + 9.0, n.y * 3.5, n.z * 2.0)
		if cl > 0.28:
			return _ramp_pick(cloud, l, x, y)
		if h > 0.05:
			return _ramp_pick(land, l, x, y)
		return _ramp_pick(ocean, l, x, y)
	, Color("8fd3ff"))
	_save(terran, "planet_terran")

	# Desert world.
	var sand := [Color("3a1f14"), Color("6e3b1f"), Color("b06a33"), Color("e0a85a"), Color("f5d58f")]
	noise.seed = 23
	_save(_sphere(56, func(n: Vector3, l: float, x: int, y: int) -> Color:
		var h := noise.get_noise_3d(n.x * 1.4, n.y * 1.4, n.z * 1.4)
		return _ramp_pick(sand, clampf(l + h * 0.35, 0, 1), x, y)
	, Color("ffd9a0")), "planet_desert")

	# Ice world.
	var ice := [Color("1e2c4a"), Color("4a6a93"), Color("9ec3e0"), Color("e6f4ff")]
	noise.seed = 37
	_save(_sphere(48, func(n: Vector3, l: float, x: int, y: int) -> Color:
		var h := noise.get_noise_3d(n.x * 2.0, n.y * 2.0, n.z * 2.0)
		return _ramp_pick(ice, clampf(l + h * 0.25, 0, 1), x, y)
	), "planet_ice")

	# Lava world.
	var rock := [Color("120a0e"), Color("2a171a"), Color("4a2a26")]
	var lava := [Color("a3261f"), Color("ff6a2b"), Color("ffc85a")]
	noise.seed = 51
	_save(_sphere(44, func(n: Vector3, l: float, x: int, y: int) -> Color:
		var h := absf(noise.get_noise_3d(n.x * 1.8, n.y * 1.8, n.z * 1.8))
		if h < 0.06:
			return lava[clampi(int((0.06 - h) / 0.02), 0, 2)]
		return _ramp_pick(rock, l, x, y)
	), "planet_lava")

	# Gas giant: banded, with a storm spot.
	var gas := [Color("2b1a3a"), Color("5a3563"), Color("9a5e7e"), Color("d59a8a"), Color("f2d2b0")]
	noise.seed = 67
	_save(_sphere(104, func(n: Vector3, l: float, x: int, y: int) -> Color:
		var band := sin(n.y * 14.0 + noise.get_noise_3d(n.x, n.y * 0.3, n.z) * 3.0) * 0.5 + 0.5
		var storm := Vector2(n.x - 0.25, (n.y - 0.3) * 1.8).length() < 0.16
		var v := clampf(l * 0.75 + band * 0.3 - 0.1, 0, 1)
		if storm:
			return Color("c9573f") if l > 0.35 else Color("7a2f2a")
		return _ramp_pick(gas, v, x, y)
	), "planet_gas")

	# Barren moon.
	var grey := [Color("1a1a22"), Color("3a3a46"), Color("6a6a78"), Color("a4a4b0")]
	noise.seed = 79
	_save(_sphere(28, func(n: Vector3, l: float, x: int, y: int) -> Color:
		var h := noise.get_noise_3d(n.x * 3.0, n.y * 3.0, n.z * 3.0)
		return _ramp_pick(grey, clampf(l - (0.25 if h > 0.3 else 0.0), 0, 1), x, y)
	), "planet_moon")

func _gen_star() -> void:
	_star_art("star", 160, 34.0, [Color("ff5a1f"), Color("ff9a2e"), Color("ffd35a"), Color("fff3b8"), Color("ffffff")], [Color("5a1a2e"), Color("8a2a2a"), Color("c8522a")])
	# Other star types (see Star.STAR_TYPES).
	_star_art("star_red", 120, 24.0, [Color("5a0f12"), Color("a3261f"), Color("e0502a"), Color("ff8a5a"), Color("ffc8a0")], [Color("3a0f1a"), Color("6a1a22"), Color("a3301f")])
	_star_art("star_white", 150, 30.0, [Color("8a9ab8"), Color("c9d4e6"), Color("e8eef8"), Color("ffffff"), Color("ffffff")], [Color("1a2a4a"), Color("2e4a7a"), Color("6a8ab8")])
	_star_art("star_orange", 164, 36.0, [Color("c8401a"), Color("ff7a2a"), Color("ffae4a"), Color("ffe0a0"), Color("fff8e0")], [Color("4a1a1a"), Color("7a2e1f"), Color("b8521f")])
	_star_art("star_blue", 208, 46.0, [Color("1f3a9a"), Color("3a6ad8"), Color("7ab0ff"), Color("c8e0ff"), Color("ffffff")], [Color("101a4a"), Color("1f3a8a"), Color("3a6ad8")])

func _star_art(name: String, s: int, core: float, ramp: Array, halo: Array) -> void:
	var img := _img(s, s)
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.08
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5 - s / 2.0, y + 0.5 - s / 2.0)
			var r := p.length()
			if r <= core:
				var v := 1.0 - r / core * 0.6 + noise.get_noise_2d(x, y) * 0.25
				img.set_pixel(x, y, _ramp_pick(ramp, clampf(v, 0, 1), x, y))
			else:
				# Corona: sparse dithered glow falling off with distance.
				var f := 1.0 - (r - core) / (s / 2.0 - core)
				f += noise.get_noise_2d(x * 0.5, y * 0.5) * 0.2
				if f <= 0.0:
					continue
				var t: float = (BAYER[y % 4][x % 4] + 0.5) / 16.0
				if f * f > t:
					var idx := clampi(int(f * 3.0), 0, 2)
					var c: Color = halo[idx]
					c.a = 1.0
					img.set_pixel(x, y, c)
	_save(img, name)

# ---------------------------------------------------------------- asteroids

func _rock(size: int, seed_v: int, mineral: bool, glint: Array = MINERAL) -> Image:
	var img := _img(size, size)
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 1.3
	var r0 := size / 2.0 - 1.5
	var light := Vector2(-0.7, -0.7).normalized()
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5 - size / 2.0, y + 0.5 - size / 2.0)
			var ang := atan2(p.y, p.x)
			var rr := r0 * (0.72 + 0.28 * (noise.get_noise_2d(cos(ang) * 1.5, sin(ang) * 1.5) + 1.0) * 0.5)
			if p.length() > rr:
				continue
			var nrm: Vector2 = p / maxf(rr, 0.01)
			var l := clampf(0.55 - nrm.dot(-light) * 0.5 + (1.0 - nrm.length()) * 0.2, 0, 1)
			var crater := noise.get_noise_2d(x * 3.1, y * 3.1)
			if crater > 0.35:
				l -= 0.25
			var c: Color = _ramp_pick(ROCK, clampf(l, 0, 1), x, y)
			if mineral and noise.get_noise_2d(x * 2.3 + 40.0, y * 2.3) > 0.32:
				c = glint[clampi(int(l * 3.0), 0, 2)]
			img.set_pixel(x, y, c)
	_outline(img, Color("07060f"))
	return img

func _gen_asteroids() -> void:
	for i in 4:
		_save(_rock(16, 100 + i, true), "asteroid_%d" % i)
	for i in 2:
		_save(_rock(26, 200 + i, true), "asteroid_big_%d" % i)
	for i in 3:
		_save(_rock(10, 300 + i, false), "debris_%d" % i)
	for i in 2:
		_save(_rock(18, 400 + i, true, SPICE), "spice_%d" % i)

# ---------------------------------------------------------------- fx

func _gen_fx() -> void:
	# Explosion: 8 frames of 32x32 in one horizontal strip.
	var frames := 8
	var s := 32
	var sheet := _img(s * frames, s)
	var fire := [Color("ffffff"), Color("fff3a0"), Color("ffc03a"), Color("ff7a2a"), Color("c8362a"), Color("5a2a3a"), Color("2a1a2a")]
	var noise := FastNoiseLite.new()
	noise.seed = 9
	noise.frequency = 0.25
	for f in frames:
		var t := float(f) / (frames - 1)
		var radius := 4.0 + t * 12.0
		for y in s:
			for x in s:
				var p := Vector2(x + 0.5 - s / 2.0, y + 0.5 - s / 2.0)
				var r := p.length() + noise.get_noise_3d(x, y, f * 6.0) * 3.0
				if r > radius:
					continue
				# Hot center early, hollow smoky ring late.
				var heat := (1.0 - r / radius) * (1.0 - t) * 1.6 + (1.0 - t) * 0.2
				if t > 0.5 and r < radius * (t - 0.4) * 1.4:
					continue
				var idx := clampi(int((1.0 - clampf(heat, 0, 1)) * (fire.size() - 1) + t * 2.0), 0, fire.size() - 1)
				sheet.set_pixel(f * s + x, y, fire[idx])
	_save(sheet, "explosion")

	# Laser bolt (tinted by owner in-game) and torpedo.
	var laser := _img(7, 3)
	for x in 7:
		laser.set_pixel(x, 1, Color(1, 1, 1))
		if x > 1 and x < 6:
			laser.set_pixel(x, 0, Color(1, 1, 1, 0.45))
			laser.set_pixel(x, 2, Color(1, 1, 1, 0.45))
	_save(laser, "bolt_laser")
	var torp := _img(6, 6)
	for y in 6:
		for x in 6:
			var d := Vector2(x - 2.5, y - 2.5).length()
			if d < 1.4:
				torp.set_pixel(x, y, Color(1, 1, 1))
			elif d < 2.8:
				torp.set_pixel(x, y, Color(1, 1, 1, 0.5))
	_save(torp, "bolt_torpedo")

	# Engine flame: 2 frames, 6x4 each.
	var flame := _img(12, 4)
	for f in 2:
		var length := 6 if f == 0 else 4
		for x in length:
			var i := 6 - 1 - x + f * 6
			var c: Color = ENGINE[clampi(2 - int(x * 3 / length), 0, 2)]
			flame.set_pixel(i, 1, c)
			flame.set_pixel(i, 2, c)
			if x < length - 2:
				flame.set_pixel(i, 0, ENGINE[0])
				flame.set_pixel(i, 3, ENGINE[0])
	_save(flame, "engine_flame")

	# Shield hit ripple: 12x12 arc.
	var shield := _img(16, 16)
	for y in 16:
		for x in 16:
			var r := Vector2(x + 0.5 - 8, y + 0.5 - 8).length()
			if r > 6.0 and r < 7.6 and x > 7:
				shield.set_pixel(x, y, Color(1, 1, 1, 0.85))
			elif r > 5.0 and r <= 6.0 and x > 9:
				shield.set_pixel(x, y, Color(1, 1, 1, 0.35))
	_save(shield, "shield_hit")

# ---------------------------------------------------------------- backgrounds

func _gen_backgrounds() -> void:
	# Far starfield (tileable because stars are placed per-pixel).
	var s := 512
	var stars := _img(s, s)
	var tints := [Color("ffffff"), Color("cfe0ff"), Color("ffe6c2"), Color("ffc2c2"), Color("a8c8ff")]
	for i in 900:
		var x := rng.randi_range(0, s - 1)
		var y := rng.randi_range(0, s - 1)
		var c: Color = tints[rng.randi_range(0, tints.size() - 1)]
		c.a = rng.randf_range(0.25, 0.9)
		stars.set_pixel(x, y, c)
	for i in 14:
		var x := rng.randi_range(2, s - 3)
		var y := rng.randi_range(2, s - 3)
		var c: Color = tints[rng.randi_range(0, tints.size() - 1)]
		stars.set_pixel(x, y, Color(1, 1, 1))
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			stars.set_pixel(x + d.x, y + d.y, Color(c, 0.6))
	_save(stars, "bg_stars")

	# Nebula: seamless noise quantized into a few dithered translucent bands.
	var noise := FastNoiseLite.new()
	noise.seed = 404
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 5
	noise.frequency = 0.004
	var src := noise.get_seamless_image(s, s)
	var noise2 := FastNoiseLite.new()
	noise2.seed = 808
	noise2.frequency = 0.006
	var src2 := noise2.get_seamless_image(s, s)
	var neb := _img(s, s)
	var purple := [Color("1d1238"), Color("33195a"), Color("5a2a7a"), Color("8a3a8a")]
	var teal := [Color("0d2233"), Color("12404f"), Color("1d6a6a")]
	for y in s:
		for x in s:
			var a := src.get_pixel(x, y).r
			var b := src2.get_pixel(x, y).r
			var t: float = (BAYER[y % 4][x % 4] + 0.5) / 16.0
			if a > 0.55:
				var v := clampf((a - 0.55) / 0.35, 0, 1)
				if v * 1.3 > t * 0.6:
					var c: Color = purple[_dither(v, x, y, purple.size())]
					c.a = 0.55
					neb.set_pixel(x, y, c)
			elif b > 0.6:
				var v := clampf((b - 0.6) / 0.3, 0, 1)
				if v * 1.3 > t * 0.6:
					var c: Color = teal[_dither(v, x, y, teal.size())]
					c.a = 0.5
					neb.set_pixel(x, y, c)
	_save(neb, "bg_nebula")

	# Near dust layer: very sparse bright specks.
	var dust := _img(s, s)
	for i in 120:
		dust.set_pixel(rng.randi_range(0, s - 1), rng.randi_range(0, s - 1), Color(0.8, 0.85, 1.0, rng.randf_range(0.3, 0.7)))
	_save(dust, "bg_dust")

# ---------------------------------------------------------------- ui icons

func _gen_icons() -> void:
	# Minerals: teal crystal cluster.
	var m := _img(12, 12)
	for y in 12:
		for x in 12:
			var inside := absf(x - 5.5) * 0.9 + absf(y - 6.0) * 0.45 < 3.3 or (absf(x - 8.5) + absf(y - 7.5) * 0.6 < 2.2)
			if inside:
				m.set_pixel(x, y, MINERAL[2] if x < 5 and y < 6 else (MINERAL[1] if x < 7 else MINERAL[0]))
	_outline(m)
	_save(m, "icon_minerals")
	# Energy: yellow bolt.
	var e := _img(12, 12)
	var bolt := _pts([[7, 0], [2, 7], [6, 7], [4, 12], [10, 4], [6, 4], [8, 0]])
	for y in 12:
		for x in 12:
			if _inside(bolt, x, y):
				e.set_pixel(x, y, ENGINE[2] if x < 6 else ENGINE[1])
	_outline(e)
	_save(e, "icon_energy")
	# Fleet capacity: tiny chevron ship.
	var f := _img(12, 12)
	var chev := _pts([[11, 6], [3, 1], [5, 6], [3, 11]])
	for y in 12:
		for x in 12:
			if _inside(chev, x, y):
				f.set_pixel(x, y, HULL[4] if y < 6 else HULL[3])
	_outline(f)
	_save(f, "icon_fleet")

# ---------------------------------------------------------------- title

## 480x270 menu backdrop (shown at 4x), composed from the sprites above.
func _gen_title() -> void:
	var w := 480
	var h := 270
	var img := _img(w, h)
	img.fill(Color("07060f"))
	var stars := Image.load_from_file(OUT + "bg_stars.png")
	var neb := Image.load_from_file(OUT + "bg_nebula.png")
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var n := neb.get_pixel(x % 512, y % 512)
			c = c.lerp(Color(n.r, n.g, n.b), n.a * 0.45)
			var s := stars.get_pixel((x + 100) % 512, (y + 60) % 512)
			c = c.lerp(Color(s.r, s.g, s.b), s.a)
			img.set_pixel(x, y, c)
	_paste(img, "planet_gas", 330, 120)
	_paste(img, "planet_moon", 300, 118)
	_paste(img, "planet_terran", 40, 190)
	_paste(img, "starbase", 96, 176, Color("4fb4ff"))
	# Two fleets closing on each other.
	var blue := Color("4fb4ff")
	var red := Color("ff4f5e")
	for p in [[150, 120, "cruiser"], [128, 100, "destroyer"], [132, 146, "destroyer"], [110, 88, "corvette"], [112, 160, "corvette"], [96, 124, "corvette"]]:
		_paste(img, "ship_" + p[2], p[0], p[1], blue)
	for p in [[300, 60, "destroyer"], [322, 44, "corvette"], [326, 78, "corvette"], [344, 58, "corvette"]]:
		_paste(img, "ship_" + p[2], p[0], p[1], red, true)
	# Crossfire and a kill.
	for i in 3:
		for t in 10:
			img.set_pixel(190 + i * 30 + t, 104 - i * 12 - t / 3, Color("9fd8ff"))
	var boom := Image.load_from_file(OUT + "explosion.png").get_region(Rect2i(96, 0, 32, 32))
	img.blend_rect(boom, Rect2i(0, 0, 32, 32), Vector2i(272, 50))
	img.save_png(OUT + "title_bg.png")

func _paste(dst: Image, name: String, cx: int, cy: int, team: Color = Color.WHITE, flip: bool = false) -> void:
	var src := Image.load_from_file(OUT + name + ".png")
	if FileAccess.file_exists(OUT + name + "_team.png"):
		var t := Image.load_from_file(OUT + name + "_team.png")
		for y in t.get_height():
			for x in t.get_width():
				var c := t.get_pixel(x, y)
				if c.a > 0.0:
					src.set_pixel(x, y, team * c.r)
	if flip:
		src.flip_x()
	dst.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i(cx - src.get_width() / 2, cy - src.get_height() / 2))

func _gen_icons2() -> void:
	# Food: green sprout.
	var f := _img(12, 12)
	var leaf_l := _pts([[6, 7], [1, 3], [2, 1], [6, 4]])
	var leaf_r := _pts([[6, 5], [11, 1], [10, 5], [7, 7]])
	for y in 12:
		for x in 12:
			if _inside(leaf_l, x, y) or _inside(leaf_r, x, y):
				f.set_pixel(x, y, Color("8fe060") if y < 4 else Color("4fa83a"))
			elif x == 6 and y >= 5:
				f.set_pixel(x, y, Color("4fa83a"))
	for x in range(3, 10):
		f.set_pixel(x, 11, Color("8a5a3a"))
	_outline(f)
	_save(f, "icon_food")
	# Spice: glowing orange grain cluster.
	var s := _img(12, 12)
	for y in 12:
		for x in 12:
			for c in [Vector2(4, 7), Vector2(8, 6), Vector2(6, 3.5)]:
				var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
				if d < 2.6:
					s.set_pixel(x, y, SPICE[2] if d < 1.0 else (SPICE[1] if x + y < 13 else SPICE[0]))
	_outline(s)
	_save(s, "icon_spice")

## 16x16 building icons for planet fields.
func _gen_buildings() -> void:
	var specs := {
		"farm": func(x: int, y: int) -> Color:
			if y >= 3 and y <= 13 and x >= 2 and x <= 13:
				return Color("8fe060") if (y - 3) % 3 == 0 else (Color("4fa83a") if (y - 3) % 3 == 1 else Color("5a3f2a"))
			return Color(0, 0, 0, 0),
		"generator": func(x: int, y: int) -> Color:
			if x >= 5 and x <= 10 and y >= 4 and y <= 14:
				return Color("566184") if x < 8 else Color("363d5c")
			if absf(x - 7.5) + absf(y - 3.0) < 3.0:
				return Color("ffd46b")
			return Color(0, 0, 0, 0),
		"mine": func(x: int, y: int) -> Color:
			if y >= 10 and y <= 14 and x >= 1 and x <= 14:
				return Color("8a7069") if y < 12 else Color("5d4a4f")
			if x >= 6 and x <= 9 and y >= 2 and y <= 10:
				return Color("c3cde4") if x < 8 else Color("8490b3")
			if y == 11 and (x == 4 or x == 11):
				return Color("3fd6b0")
			return Color(0, 0, 0, 0),
		"habitat": func(x: int, y: int) -> Color:
			var d := Vector2(x + 0.5 - 8.0, (y + 0.5 - 12.0) * 1.2).length()
			if y <= 12 and d < 7.0:
				return Color("a8f0ff") if d < 4.0 and y < 9 else Color("3fa7d6")
			if y > 12 and y <= 14 and x >= 1 and x <= 14:
				return Color("566184")
			return Color(0, 0, 0, 0),
		"spice_extractor": func(x: int, y: int) -> Color:
			if (x == 4 or x == 11) and y >= 3 and y <= 14:
				return Color("8490b3")
			if y == 3 and x >= 4 and x <= 11:
				return Color("8490b3")
			if x >= 6 and x <= 9 and y >= 6 and y <= 14:
				return Color("ff9a2e") if y < 10 else Color("a3461f")
			return Color(0, 0, 0, 0),
	}
	for name in specs:
		var img := _img(16, 16)
		for y in 16:
			for x in 16:
				var c: Color = specs[name].call(x, y)
				if c.a > 0.0:
					img.set_pixel(x, y, c)
		_outline(img)
		_save(img, "bld_" + name)

# ---------------------------------------------------------------- job ships

## Each job ship has its own silhouette plus a glowing accent color that
## matches its ability's in-game effect, so it reads at a glance.
const ACCENT := {
	"scout": [Color("1d6f8a"), Color("7fe8ff"), Color("e6fbff")],
	"heatshield": [Color("8a5a12"), Color("ffc24a"), Color("fff0b8")],
	"tender": [Color("1f6a2a"), Color("6fe07a"), Color("d8ffd8")],
	"pathfinder": [Color("7a3a10"), Color("ff8a2a"), Color("ffd6a0")],
	"stormrider": [Color("4a2a8a"), Color("b48cff"), Color("f0e6ff")],
	"harvester": [Color("a3461f"), Color("ff9a2e"), Color("ffe08a")],
	"interdictor": [Color("7a1a66"), Color("ff5ad2"), Color("ffd6f4")],
	"monitor": [Color("7a1a14"), Color("ff4a3a"), Color("ffc8b8")],
	"carrier": [Color("7a5a10"), Color("ffb347"), Color("fff0c8")],
	"battleship": [Color("7a6a30"), Color("ffe08a"), Color("ffffff")],
}

static func _px(img: Image, x: float, y: float, c: Color) -> void:
	var xi := int(round(x))
	var yi := int(round(y))
	if xi >= 0 and yi >= 0 and xi < img.get_width() and yi < img.get_height():
		img.set_pixel(xi, yi, c)

## Straight line of pixels from a to b.
static func _line(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		_px(img, p.x, p.y, c)

func _gen_job_ships() -> void:
	var A := ACCENT
	# Scout: a thin needle carrying a big, thick sensor dish and a forward
	# antenna mast.
	_ship("scout", 20, 13,
		[[2, 20, 1.6, 0.3], [4, 10, 3.5, 1.0], [0, 4, 1.5, 1.5]],
		func(x: int, dy: float) -> bool: return absf(dy) > 2.2,
		[8, 2], [0.0], [],
		func(img: Image, cy: float) -> void:
			for dy in range(-6, 7):
				var x := 15.0 - dy * dy / 12.0
				_px(img, x - 1, cy + dy, A["scout"][0])
				_px(img, x, cy + dy, A["scout"][1])
				if absf(dy) < 5:
					_px(img, x + 1, cy + dy, A["scout"][2] if absf(dy) < 2 else A["scout"][1])
			_line(img, Vector2(16, cy), Vector2(20, cy), A["scout"][0])
			_px(img, 21, cy, A["scout"][2]))
	# Heat Shield Frigate: compact hull behind a huge curved gold plate.
	_ship("heatshield", 26, 21,
		[[2, 19, 3.5, 2.5], [6, 14, 5.0, 3.0], [0, 4, 2.5, 2.5]],
		func(x: int, dy: float) -> bool: return absf(dy) > 3.2,
		[14, 2], [-1.0, 0.0], [9],
		func(img: Image, cy: float) -> void:
			for dy in range(-9, 10):
				var x := 24.0 - dy * dy / 14.0
				_px(img, x, cy + dy, A["heatshield"][1])
				_px(img, x - 1, cy + dy, A["heatshield"][0])
				if absf(dy) < 7:
					_px(img, x + 1, cy + dy, A["heatshield"][2])
			_line(img, Vector2(19, cy - 2), Vector2(22, cy - 5), A["heatshield"][0])
			_line(img, Vector2(19, cy + 2), Vector2(22, cy + 5), A["heatshield"][0]))
	# Repair Tender: boxy workshop with side pods, green cross and two
	# forward repair arms.
	_ship("tender", 24, 19,
		[[2, 16, 4.5, 4.5], [15, 21, 3.0, 1.0], [0, 3, 2.5, 2.5], [5, 12, 1.8, 1.8, 6.5]],
		func(x: int, dy: float) -> bool: return absf(dy) > 5.0,
		[17, 2], [-1.0, 0.0], [8],
		func(img: Image, cy: float) -> void:
			for d in range(-2, 3):
				_px(img, 9 + d, cy, A["tender"][1])
				_px(img, 9, cy + d, A["tender"][1])
			_px(img, 9, cy, A["tender"][2])
			for s in [-1, 1]:
				_line(img, Vector2(12, cy + s * 6), Vector2(21, cy + s * 7), Color("8490b3"))
				_px(img, 22, cy + s * 7, A["tender"][2])
				_px(img, 21, cy + s * 8, A["tender"][1]))
	# Pathfinder: armored hull with a big conical drill prow (orange grooves)
	# and two plough blades that shove debris aside.
	_ship("pathfinder", 26, 15,
		[[2, 16, 4.5, 4.5], [15, 25, 5.0, 0.6], [0, 3, 2.5, 2.5]],
		func(x: int, dy: float) -> bool: return absf(dy) > 3.5 and x < 15,
		[11, 2], [-1.0, 0.0], [7],
		func(img: Image, cy: float) -> void:
			for k in 4:
				var h := 4.5 - k * 1.1
				_line(img, Vector2(17 + k * 2, cy - h), Vector2(18 + k * 2, cy + h), A["pathfinder"][1])
			_px(img, 26, cy, A["pathfinder"][2])
			for s in [-1, 1]:
				_line(img, Vector2(12, cy + s * 5), Vector2(17, cy + s * 7), A["pathfinder"][0])
				_px(img, 18, cy + s * 7, A["pathfinder"][1]))
	# Storm Rider: slim hull, swept fins, violet lightning rods.
	_ship("stormrider", 24, 15,
		[[2, 22, 2.5, 0.5], [3, 12, 6.5, 1.5], [0, 3, 2.0, 2.0]],
		func(x: int, dy: float) -> bool: return absf(dy) > 3.0,
		[15, 2], [0.0], [],
		func(img: Image, cy: float) -> void:
			for s in [-1, 1]:
				var pts := [Vector2(5, cy + s * 6), Vector2(9, cy + s * 5), Vector2(11, cy + s * 6), Vector2(15, cy + s * 4)]
				for i in 3:
					_line(img, pts[i], pts[i + 1], A["stormrider"][1])
				_px(img, 16, cy + s * 4, A["stormrider"][2])
			_px(img, 20, cy, A["stormrider"][2]))
	# Nebula Harvester: tanker with a wide collector fan up front.
	_ship("harvester", 24, 23,
		[[3, 16, 4.5, 4.5], [14, 19, 3.0, 2.0], [0, 4, 2.5, 2.5]],
		func(x: int, dy: float) -> bool: return absf(dy) > 3.0 and x < 14,
		[16, 2], [-1.0, 0.0], [7, 11],
		func(img: Image, cy: float) -> void:
			for dy in [-10, -7, -4, 4, 7, 10]:
				_line(img, Vector2(18, cy + dy * 0.2), Vector2(23, cy + dy), A["harvester"][0])
				_px(img, 23, cy + dy, A["harvester"][2])
			for dy in range(-10, 11):
				_px(img, 24, cy + dy, A["harvester"][1] if dy % 3 != 0 else A["harvester"][2])
			for x in [6, 9, 12]:
				_px(img, x, cy - 3, A["harvester"][1])
				_px(img, x, cy + 3, A["harvester"][1]))
	# Interdictor: core hull threaded through a gravity-well ring.
	_ship("interdictor", 26, 23,
		[[2, 23, 3.5, 1.0], [0, 3, 2.5, 2.5]],
		func(x: int, dy: float) -> bool: return absf(dy) > 2.0 and x < 8,
		[18, 2], [-1.0, 0.0], [],
		func(img: Image, cy: float) -> void:
			for i in 48:
				var a := TAU * i / 48.0
				var p := Vector2(12 + cos(a) * 4.0, cy + sin(a) * 10.0)
				if i % 12 != 0:
					_px(img, p.x, p.y, A["interdictor"][1] if cos(a) > -0.3 else A["interdictor"][0])
			_px(img, 12, cy - 10, A["interdictor"][2])
			_px(img, 12, cy + 10, A["interdictor"][2]))
	# Siege Monitor: stubby armored body carrying one huge spinal cannon.
	_ship("monitor", 36, 17,
		[[2, 16, 7.0, 6.0], [0, 4, 4.0, 4.0], [14, 36, 1.6, 1.2]],
		func(x: int, dy: float) -> bool: return absf(dy) > 4.0 and x < 16,
		[10, 2], [-3.0, -2.0, 1.0, 2.0], [6, 12],
		func(img: Image, cy: float) -> void:
			for x in range(18, 34, 4):
				_px(img, x, cy - 1, A["monitor"][1])
				_px(img, x, cy + 1, A["monitor"][0])
			_px(img, 36, cy, A["monitor"][2])
			_px(img, 36, cy + 1, A["monitor"][1]))
	# Carrier: long flat hull with an open launch deck down the middle (dark
	# runway, amber guide lights, small fighters parked on it) and lit
	# hangar bays down both sides.
	_ship("carrier", 42, 27,
		[[3, 38, 10.0, 7.0], [36, 42, 4.0, 1.0], [0, 5, 6.0, 6.0]],
		func(x: int, dy: float) -> bool: return absf(dy) > 8.0,
		[36, 2], [-4.0, -2.0, 0.0, 2.0, 4.0], [],
		func(img: Image, cy: float) -> void:
			for x in range(8, 37):
				for dy in range(-2, 3):
					_px(img, x, cy + dy, Color("1b1d30"))
				if x % 3 == 0:
					_px(img, x, cy, A["carrier"][0])
			for x in [12, 20, 28]:
				# A parked fighter: tiny chevron pointing forward.
				_px(img, x + 1, cy, A["carrier"][2])
				_px(img, x, cy - 1, A["carrier"][1])
				_px(img, x, cy + 1, A["carrier"][1])
				_px(img, x - 1, cy - 2, A["carrier"][1])
				_px(img, x - 1, cy + 2, A["carrier"][1])
			for x in range(9, 35, 5):
				for s in [-1, 1]:
					_px(img, x, cy + s * 5, Color("0e0d1c"))
					_px(img, x + 1, cy + s * 5, Color("0e0d1c"))
					_px(img, x, cy + s * 6, A["carrier"][1]))
	# Battleship: the biggest hull, stepped decks, gold command lights.
	_ship("battleship", 52, 31,
		[[3, 44, 9.0, 6.0], [42, 52, 4.5, 0.8], [8, 24, 14.0, 8.0], [0, 6, 7.0, 7.0], [26, 40, 2.0, 1.5, 8.0], [30, 46, 1.2, 0.8, 4.0]],
		func(x: int, dy: float) -> bool: return absf(dy) > 10.0 or (x >= 30 and x <= 32),
		[40, 4], [-5.0, -3.0, -1.0, 0.0, 2.0, 4.0, 5.0], [14, 22, 36],
		func(img: Image, cy: float) -> void:
			# Gun turrets: round mounts with barrels facing forward, on the
			# spine and on both wings.
			for t in [[12, 0], [20, 0], [16, -9], [16, 9], [26, -5], [26, 5]]:
				var c := Vector2(t[0], cy + t[1])
				for dx in range(-2, 3):
					for dy in range(-2, 3):
						if absf(dx) + absf(dy) <= 3:
							_px(img, c.x + dx, c.y + dy, Color("0e0d1c") if absf(dx) == 2 or absf(dy) == 2 else Color("c3cde4"))
				_px(img, c.x, c.y, Color("566184"))
				_line(img, c + Vector2(3, 0), c + Vector2(5, 0), Color("c3cde4"))
			# Raised bridge tower (outlined, lit window band) behind the prow.
			for x in range(35, 41):
				for dy in range(-3, 4):
					_px(img, x, cy + dy, Color("0e0d1c") if absf(dy) == 3 or x == 35 or x == 40 else Color("c3cde4"))
			for x in range(36, 40):
				_px(img, x, cy - 1, A["battleship"][1])
			_px(img, 39, cy - 1, A["battleship"][2])
			_px(img, 38, cy, A["battleship"][2])
			for s in [-1, 1]:
				for x in range(12, 22, 3):
					_px(img, x, cy + s * 11, A["battleship"][0]))

# ---------------------------------------------------------------- variants

## Specialist variants (Defs.VARIANTS) of the generalist warships: the base
## sprite with markings in the variant's color: a glowing emitter at the
## nose, a stripe down the spine and lit wingtips, so a Plasma Corvette reads
## differently from a Slip or Disruptor Corvette at a glance.
const VARIANT_COLORS := {
	"plasma": [Color("1d5f8a"), Color("7fd8ff"), Color("e6fbff")],
	"breacher": [Color("7a1414"), Color("ff4a4a"), Color("ffc8c8")],
	"reaver": [Color("1f6a2a"), Color("58e07a"), Color("d8ffd8")],
	"slip": [Color("8a4a10"), Color("ffa43a"), Color("ffe0b0")],
	"disruptor": [Color("1f6a2a"), Color("58e07a"), Color("d8ffd8")],
}
const VARIANT_BASES := {
	"corvette": ["plasma", "breacher", "reaver", "slip", "disruptor"],
	"destroyer": ["plasma", "breacher", "reaver", "slip", "disruptor"],
	"cruiser": ["plasma", "breacher", "reaver", "slip", "disruptor"],
}

func _gen_variants() -> void:
	for base in VARIANT_BASES:
		var hull := Image.load_from_file(ProjectSettings.globalize_path(OUT + "ship_%s.png" % base))
		var team := Image.load_from_file(ProjectSettings.globalize_path(OUT + "ship_%s_team.png" % base))
		for v in VARIANT_BASES[base]:
			var tim := team.duplicate() as Image
			_mark_variant(hull, tim, v)
			_save(hull.duplicate() as Image, "ship_%s_%s" % [v, base])
			_save(tim, "ship_%s_%s_team" % [v, base])

## Variant markings go on the TEAM layer, so they always show the owner's
## color. That means the pattern alone has to say which variant it is:
##   plasma     - one solid line down the spine
##   breacher  - two ribs across the hull
##   reaver    - saw teeth along both edges
##   slip      - two long stripes either side of the spine
##   disruptor - a row of V chevrons
func _mark_variant(hull: Image, tim: Image, v: String) -> void:
	var w := hull.get_width()
	var h := hull.get_height()
	var cy := h / 2
	var lit: Color = TEAM[TEAM.size() - 1]
	var mid: Color = TEAM[TEAM.size() - 2]
	var is_hull := func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h and hull.get_pixel(x, y).a > 0.0 and hull.get_pixel(x, y) != OUTLINE
	var mark := func(x: int, y: int, c: Color) -> void:
		if is_hull.call(x, y):
			tim.set_pixel(x, y, c)
	var tail := int(w * 0.66)
	match v:
		"plasma":
			for x in range(2, tail):
				mark.call(x, cy, lit)
		"breacher":
			# Two ribs across the hull, from edge to edge.
			for k in 2:
				var x := int(w * (0.30 + k * 0.16))
				for y in h:
					if absi(y - cy) <= 1:
						continue
					mark.call(x, y, lit)
					mark.call(x + 1, y, mid)
		"reaver":
			for x in w:
				if x % 2 == 1:
					continue
				for dir in [1, -1]:
					var y := 0 if dir == 1 else h - 1
					while y >= 0 and y < h and hull.get_pixel(x, y).a == 0.0:
						y += dir
					var inner: int = y + dir
					if absi(inner - cy) >= 2:
						mark.call(x, inner, lit)
		"slip":
			for s in [-2, 2]:
				for x in range(2, tail):
					mark.call(x, cy + s, lit)
		"disruptor":
			for x0 in range(3, tail - 2, 5):
				for k in 3:
					for s in [-1, 1]:
						mark.call(x0 + k, cy + s * (2 - k), lit)
				mark.call(x0 + 2, cy, mid)

## Weapons Depots: a hub with docking arms and weapon racks. The racks and
## the variant marking are drawn on the TEAM layer, so a depot always wears
## its owner's color like every other structure; which variant it fits is
## said by the marking pattern alone — the same language the ships use
## (one line, two ribs, saw teeth, two stripes, chevrons).
func _gen_depot() -> void:
	_ship("depot_base", 34, 34,
		[[10, 24, 7.0, 7.0], [2, 32, 2.2, 2.2], [14, 20, 2.0, 2.0, 11.0], [6, 10, 3.0, 3.0, 8.0], [24, 28, 3.0, 3.0, 8.0]],
		func(x: int, dy: float) -> bool: return absf(dy) > 11.0,
		[0, 0], [], [13, 20])
	var hull := Image.load_from_file(ProjectSettings.globalize_path(OUT + "ship_depot_base.png"))
	var team := Image.load_from_file(ProjectSettings.globalize_path(OUT + "ship_depot_base_team.png"))
	var lit: Color = TEAM[TEAM.size() - 1]
	var mid: Color = TEAM[TEAM.size() - 2]
	for v in VARIANT_BASES["corvette"]:
		var tim := team.duplicate() as Image
		var cy := 17
		var mark := func(x: int, y: int, col: Color) -> void:
			if x >= 0 and y >= 0 and x < hull.get_width() and y < hull.get_height() and hull.get_pixel(x, y).a > 0.0 and hull.get_pixel(x, y) != OUTLINE:
				tim.set_pixel(x, y, col)
		# Weapon racks down both docking arms.
		for i in 5:
			var x := 8 + i * 5
			mark.call(x, cy - 9, lit)
			mark.call(x, cy + 9, lit)
			mark.call(x + 1, cy - 9, mid)
			mark.call(x + 1, cy + 9, mid)
		# The variant's marking, across the hub.
		if v == "plasma":
			for x in range(12, 24):
				mark.call(x, cy, lit)
		elif v == "breacher":
			for x in [14, 20]:
				for dy in range(-5, 6):
					mark.call(x, cy + dy, lit)
		elif v == "reaver":
			for k in 6:
				var x := 11 + k * 2
				mark.call(x, cy - 6, lit)
				mark.call(x, cy + 6, lit)
		elif v == "slip":
			for s in [-3, 3]:
				for x in range(12, 24):
					mark.call(x, cy + s, lit)
		else:
			for x0 in [12, 17, 22]:
				for k in 3:
					for s in [-1, 1]:
						mark.call(x0 + k, cy + s * (2 - k), lit)
				mark.call(x0 + 2, cy, mid)
		_save(hull.duplicate() as Image, "ship_depot_" + v)
		_save(tim, "ship_depot_" + v + "_team")


## Mining Station: a small ore silo with a docking collar and a stub gun.
## Reads as a lesser cousin of the starbase, not a warship.
func _gen_mining_station() -> void:
	_ship("mining_station", 26, 26,
		[[8, 18, 6.0, 6.0], [3, 23, 1.6, 1.6], [11, 15, 2.0, 2.0, 9.0], [18, 22, 2.2, 2.2, 6.0]],
		func(x: int, dy: float) -> bool: return absf(dy) > 9.0,
		[0, 0], [], [10, 16])
	var hull := Image.load_from_file(ProjectSettings.globalize_path(OUT + "ship_mining_station.png"))
	var team := Image.load_from_file(ProjectSettings.globalize_path(OUT + "ship_mining_station_team.png"))
	var lit: Color = TEAM[TEAM.size() - 1]
	var mid: Color = TEAM[TEAM.size() - 2]
	var cy := 13
	var mark := func(x: int, y: int, col: Color) -> void:
		if x >= 0 and y >= 0 and x < hull.get_width() and y < hull.get_height() and hull.get_pixel(x, y).a > 0.0 and hull.get_pixel(x, y) != OUTLINE:
			team.set_pixel(x, y, col)
	# Ore hopper bands across the silo, and a lit docking collar.
	for x in range(9, 18):
		mark.call(x, cy - 4, mid)
		mark.call(x, cy + 4, mid)
	for dy in range(-3, 4):
		mark.call(18, cy + dy, lit)
		mark.call(19, cy + dy, mid)
	_save(hull, "ship_mining_station")
	_save(team, "ship_mining_station_team")

# ---------------------------------------------------------------- hull marks

## Mark trim (Defs.HULL_MARKS): Wisp hulls are bare, and each mark researched
## adds a layer of finish — a bright top rail, then a matching keel line and
## nose studs, then a full rim and lit engine blocks. One overlay per class
## serves every variant of it, since they share a silhouette.
const MARK_TRIM := [Color("dbe6ff"), Color("ffc24a"), Color("fff6d8")]

func _gen_hull_marks() -> void:
	for cls in ["corvette", "destroyer", "cruiser"]:
		var hull := Image.load_from_file(ProjectSettings.globalize_path(OUT + "ship_%s.png" % cls))
		var w := hull.get_width()
		var h := hull.get_height()
		# Column-wise top and bottom edges of the hull, ignoring the outline.
		var top := {}
		var bot := {}
		for x in w:
			for y in h:
				var c := hull.get_pixel(x, y)
				if c.a > 0.0 and c != OUTLINE:
					if not top.has(x):
						top[x] = y
					bot[x] = y
		var xs: Array = top.keys()
		xs.sort()
		if xs.is_empty():
			continue
		var nose: int = xs[xs.size() - 1]
		var stern: int = xs[0]
		for level in [1, 2, 3]:
			var img := _img(w - 2, h - 2)
			var tint: Color = MARK_TRIM[level - 1]
			for x in xs:
				var t: float = float(x - stern) / maxf(nose - stern, 1)
				# Top rail from the first mark on.
				_px(img, x - 1, top[x] - 1, tint)
				if level >= 2 and bot[x] - top[x] > 2:
					_px(img, x - 1, bot[x] - 1, tint)
				# Phantom: a full rim, so the hull reads lit all round.
				if level >= 3 and bot[x] - top[x] > 3:
					# Phantom: the rim reads lit all round, with an inner sheen.
					_px(img, x - 1, top[x], tint.darkened(0.15))
					if t > 0.2 and t < 0.9:
						_px(img, x - 1, bot[x] - 2, Color("ffe9a8"))
			# Nose studs: one per mark.
			for k in level:
				var sx: int = nose - 1 - k * 2
				if top.has(sx + 1):
					var mid: int = int(round((top[sx + 1] + bot[sx + 1]) / 2.0))
					_px(img, sx, mid - 1, tint)
			# Phantom: lit engine blocks at the stern.
			if level >= 3:
				for k in 2:
					var ex: int = stern + k
					if top.has(ex):
						_px(img, ex - 1, top[ex], MARK_TRIM[2])
						_px(img, ex - 1, bot[ex] - 2, MARK_TRIM[2])
			_save(img, "ship_mark_%s_%d" % [cls, level])

# ---------------------------------------------------------------- layer art

## "bolt_v": a V-shaped laser (a chevron pointing the way it flies) for
## shots that bypass defense layers (Slip, Disruptor); white, tinted in game.
## Layer icons (12x12, in Defs.LAYER_COLORS): shields = a bubble dome,
## armor = a riveted plate, hull = a ship's frame.
func _gen_layer_art() -> void:
	var v := _img(9, 9)
	for i in 5:
		for t in 2:
			var a := Color(1, 1, 1, 1.0 if t == 0 else 0.45)
			v.set_pixel(3 + i - t, 4 - i, a)
			v.set_pixel(3 + i - t, 4 + i, a)
	v.set_pixel(8, 0, Color(1, 1, 1, 0.8))
	v.set_pixel(8, 8, Color(1, 1, 1, 0.8))
	# Tip at the front (right side, like the other bolts).
	v.flip_x()
	_save(v, "bolt_v")
	var sh := _img(12, 12)
	for y in 12:
		for x in 12:
			var d := Vector2(x + 0.5 - 6.0, y + 0.5 - 8.0).length()
			if y <= 8 and d <= 5.6 and d >= 3.8:
				sh.set_pixel(x, y, Color("7fd8ff") if d < 4.8 else Color("c8f0ff"))
	for x in range(1, 11):
		sh.set_pixel(x, 9, Color("3fa7d6"))
	_outline(sh)
	_save(sh, "icon_layer_shield")
	var ar := _img(12, 12)
	for y in range(1, 11):
		for x in range(1, 11):
			if not ((x == 1 or x == 10) and (y == 1 or y == 10)):
				ar.set_pixel(x, y, Color("ff4a4a") if (x + y) % 2 == 0 or y < 4 else Color("c83232"))
	for p in [Vector2i(3, 3), Vector2i(8, 3), Vector2i(3, 8), Vector2i(8, 8)]:
		ar.set_pixel(p.x, p.y, Color("ffc8c8"))
	_outline(ar)
	_save(ar, "icon_layer_armor")
	var hu := _img(12, 12)
	var frame := _pts([[1, 6], [5, 2], [11, 6], [5, 10]])
	for y in 12:
		for x in 12:
			if _inside(frame, x, y):
				hu.set_pixel(x, y, Color("58e07a") if y < 6 else Color("38a85a"))
	for x in range(3, 9):
		hu.set_pixel(x, 6, Color("d8ffd8"))
	_outline(hu)
	_save(hu, "icon_layer_hull")
