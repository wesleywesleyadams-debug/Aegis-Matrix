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
	_gen_ships()
	_gen_starbase()
	_gen_planets()
	_gen_star()
	_gen_asteroids()
	_gen_fx()
	_gen_backgrounds()
	_gen_icons()
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
func _ship(name: String, w: int, h: int, parts: Array, team_fn: Callable, glass: Array, engines: Array, panels: Array) -> void:
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

func _sphere(size: int, shade_fn: Callable, atmo: Color = Color(0, 0, 0, 0)) -> Image:
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
	var s := 160
	var img := _img(s, s)
	var core := 34.0
	var ramp := [Color("ff5a1f"), Color("ff9a2e"), Color("ffd35a"), Color("fff3b8"), Color("ffffff")]
	var halo := [Color("5a1a2e"), Color("8a2a2a"), Color("c8522a")]
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
	_save(img, "star")

# ---------------------------------------------------------------- asteroids

func _rock(size: int, seed_v: int, mineral: bool) -> Image:
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
				c = MINERAL[clampi(int(l * 3.0), 0, 2)]
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
