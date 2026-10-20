class_name ModScene
extends Control
## A small battle picture for one weapon Mod in the Codex: your ship with the
## Mod against the kind of enemy it is best at, built from the game's own
## hull sprites, with the weapon's effect drawn between them.

const W := 300.0
const H := 150.0
const SIZE := {"corvette": 22.0, "destroyer": 32.0, "cruiser": 44.0, "carrier": 62.0}
const OURS := Color("4fb4ff")
const THEIRS := Color("ff4f5e")

## id -> [best-at caption, our ships [[class, x, y, angle]], their ships, effect]
const SCENES := {
	"mod_proton_torpedoes": ["Corvettes hunting a big ship from range.",
		[["corvette", 50, 45, 0.3], ["corvette", 70, 105, -0.2]], [["carrier", 225, 75, 3.14]], "torpedo"],
	"mod_kinetic_repeaters": ["Close-range dogfights between small ships.",
		[["corvette", 105, 75, 0.0]], [["corvette", 185, 60, 3.0], ["corvette", 195, 95, 3.3]], "kinetic"],
	"mod_arc_emitters": ["Packs of small ships flying close together.",
		[["corvette", 60, 75, 0.0]], [["corvette", 170, 55, 3.14], ["corvette", 200, 85, 3.14], ["corvette", 235, 60, 3.14], ["corvette", 215, 115, 3.14]], "arc"],
	"mod_flak_cannons": ["Shredding a swarm of corvettes.",
		[["destroyer", 60, 75, 0.0]], [["corvette", 180, 50, 3.14], ["corvette", 205, 70, 3.14], ["corvette", 185, 95, 3.14], ["corvette", 225, 100, 3.14], ["corvette", 240, 60, 3.14], ["corvette", 210, 125, 3.14]], "flak"],
	"mod_cluster_bombs": ["A bombing run over a tight formation.",
		[["destroyer", 95, 75, 0.0]], [["corvette", 200, 60, 3.14], ["corvette", 215, 78, 3.14], ["corvette", 200, 96, 3.14], ["corvette", 230, 62, 3.14], ["corvette", 232, 94, 3.14]], "bombs"],
	"mod_homing_missiles": ["Fast targets that dodge ordinary shots.",
		[["destroyer", 55, 75, 0.0]], [["corvette", 210, 35, 2.4], ["corvette", 240, 85, 3.6], ["corvette", 195, 120, 4.0]], "missiles"],
	"mod_ion_lance": ["One big target, held under the beam.",
		[["cruiser", 70, 75, 0.0]], [["carrier", 220, 75, 3.14]], "beam"],
	"mod_rail_cannons": ["Sniping big hulls from beyond their range.",
		[["cruiser", 40, 75, 0.0]], [["cruiser", 255, 75, 3.14]], "rail"],
	"mod_point_defense_lattice": ["Escorting a fleet against torpedoes and missiles.",
		[["cruiser", 110, 75, 0.0], ["destroyer", 70, 40, 0.0], ["destroyer", 70, 110, 0.0]], [["corvette", 250, 50, 3.14], ["corvette", 260, 100, 3.14]], "pd"],
	"mod_interceptor_drones": ["Guarding an area against raiders.",
		[["carrier", 120, 75, 0.0]], [["corvette", 235, 40, 3.5], ["corvette", 245, 110, 2.8]], "drones"],
	"mod_tractor_beams": ["Pinning enemies in place for the fleet.",
		[["carrier", 75, 75, 0.0]], [["corvette", 225, 40, 3.14], ["destroyer", 235, 80, 3.14], ["corvette", 220, 120, 3.14]], "tractor"],
	"mod_missile_barrage": ["Opening a fight on a group from long range.",
		[["carrier", 45, 75, 0.0]], [["destroyer", 230, 55, 3.14], ["corvette", 255, 85, 3.14], ["destroyer", 235, 110, 3.14]], "barrage"],
}

var mod_id := ""
## Holds the hull art so it stays loaded until the frame is drawn.
var _tex := {}

func _init(id: String = "") -> void:
	mod_id = id
	custom_minimum_size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

static func caption(id: String) -> String:
	return SCENES.get(id, [""])[0]

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)), Color("070a18"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(mod_id)
	for k in 40:
		draw_rect(Rect2(Vector2(rng.randf() * W, rng.randf() * H), Vector2.ONE), Color(1, 1, 1, rng.randf_range(0.2, 0.7)))
	if not SCENES.has(mod_id):
		return
	var sc: Array = SCENES[mod_id]
	var ours: Array = sc[1]
	var theirs: Array = sc[2]
	_effect(sc[3], ours, theirs)
	for s in ours:
		_ship(s, OURS)
	for s in theirs:
		_ship(s, THEIRS)
	draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)), Color("2b3a6b"), false, 2.0)

func _ship(s: Array, col: Color) -> void:
	var hull: Texture2D = _art("ship_" + s[0])
	var team: Texture2D = _art("ship_" + s[0] + "_team")
	var sz: float = SIZE[s[0]]
	var k: float = sz / maxf(hull.get_width(), hull.get_height())
	var rect := Rect2(-hull.get_size() * k * 0.5, hull.get_size() * k)
	draw_set_transform(Vector2(s[1], s[2]), float(s[3]))
	draw_texture_rect(hull, rect, false)
	if team:
		draw_texture_rect(team, rect, false, col)
	draw_set_transform(Vector2.ZERO, 0.0)

func _p(s: Array) -> Vector2:
	return Vector2(s[1], s[2])

func _effect(kind: String, ours: Array, theirs: Array) -> void:
	var a := _p(ours[0])
	var b := _p(theirs[0])
	match kind:
		"torpedo":
			for s in ours:
				var o := _p(s)
				var t := o.lerp(b, 0.62)
				_dashes(o, t, Color("8fd8ff"))
				draw_circle(t, 4.5, Color("bfe9ff"))
				draw_circle(t, 2.0, Color.WHITE)
				draw_arc(o + Vector2(-6, 0), 16.0, 1.6, 4.4, 10, Color(OURS, 0.6), 1.5)   # peel-away
		"kinetic":
			for t in theirs:
				for j in 4:
					var p := a.lerp(_p(t), 0.25 + j * 0.15)
					draw_line(p, p + (_p(t) - a).normalized() * 5.0, Color("ffd84a"), 2.0)
		"arc":
			var pts := [a] + theirs.map(func(t): return _p(t))
			for i in pts.size() - 1:
				_zigzag(pts[i], pts[i + 1])
		"flak":
			for t in theirs.slice(0, 4):
				draw_line(a, _p(t), Color(1, 0.85, 0.5, 0.25), 1.0)
			for c in [Vector2(195, 65), Vector2(215, 102)]:
				draw_circle(c, 20.0, Color(1, 0.6, 0.2, 0.25))
				draw_arc(c, 20.0, 0, TAU, 24, Color("ffb347"), 1.5)
		"bombs":
			for j in 6:
				var p := a + Vector2(30 + j * 10, -18 + j * 7)
				draw_circle(p, 2.2, Color("ffd84a") if j % 2 == 0 else Color("c8a04a"))
			draw_circle(Vector2(215, 78), 40.0 * 0.6, Color(1, 0.6, 0.2, 0.2))
			draw_arc(Vector2(215, 78), 24.0, 0, TAU, 24, Color("ffb347"), 1.5)
		"missiles":
			for t in theirs:
				var e := _p(t)
				var mid := a.lerp(e, 0.5) + (e - a).orthogonal().normalized() * 25.0
				var curve := PackedVector2Array()
				for j in 11:
					var u := j / 10.0
					curve.append(a.lerp(mid, u).lerp(mid.lerp(e, u), u))
				draw_polyline(curve, Color(1.0, 0.7, 0.35, 0.8), 1.5)
		"beam":
			draw_line(a + Vector2(14, 0), b, Color(0.5, 0.85, 1.0, 0.45), 9.0)
			draw_line(a + Vector2(14, 0), b, Color.WHITE, 2.5)
		"rail":
			draw_line(a + Vector2(18, 0), b, Color(0.85, 0.9, 1.0, 0.9), 1.2)
			for j in 4:
				draw_arc(a.lerp(b, 0.25 + j * 0.15), 4.0, 0, TAU, 10, Color("7fa8ff"), 1.0)
		"pd":
			for j in 3:
				var m := Vector2(175 + j * 18, 55 + j * 20)
				draw_circle(m, 2.5, Color("ff8a2a"))
				draw_line(a, m, Color("ffd84a"), 1.2)
				draw_line(m + Vector2(-4, -4), m + Vector2(4, 4), Color("ff6a4a"), 1.5)
				draw_line(m + Vector2(-4, 4), m + Vector2(4, -4), Color("ff6a4a"), 1.5)
		"drones":
			draw_arc(a, 45.0, 0, TAU, 32, Color(0.5, 0.85, 1.0, 0.35), 1.0)
			for j in 4:
				var d := a + Vector2.from_angle(TAU * j / 4.0 + 0.5) * 45.0
				draw_colored_polygon(PackedVector2Array([d + Vector2(-3, 3), d + Vector2(0, -4), d + Vector2(3, 3)]), Color("c8d2ea"))
			draw_line(a + Vector2.from_angle(0.5) * 45.0, _p(theirs[1]), Color("ffd84a"), 1.0)
		"tractor":
			for t in theirs:
				var e := _p(t)
				var side := (e - a).orthogonal().normalized() * 8.0
				draw_colored_polygon(PackedVector2Array([a + Vector2(20, 0), e + side, e - side]), Color(0.6, 1.0, 0.7, 0.18))
				draw_line(a + Vector2(20, 0), e, Color(0.6, 1.0, 0.7, 0.7), 1.0)
		"barrage":
			for j in 9:
				var e: Vector2 = _p(theirs[j % theirs.size()])
				var mid := a.lerp(e, 0.5) + Vector2(0, -40 + j * 4)
				var curve := PackedVector2Array()
				for q in 9:
					var u := q / 8.0
					curve.append(a.lerp(mid, u).lerp(mid.lerp(e, u), u))
				draw_polyline(curve, Color(1.0, 0.55, 0.3, 0.5), 1.0)

func _dashes(a: Vector2, b: Vector2, col: Color) -> void:
	for j in 6:
		if j % 2 == 0:
			draw_line(a.lerp(b, j / 6.0), a.lerp(b, (j + 1) / 6.0), col, 1.5)

func _zigzag(a: Vector2, b: Vector2) -> void:
	var pts := PackedVector2Array([a])
	var side := (b - a).orthogonal().normalized()
	for j in range(1, 5):
		pts.append(a.lerp(b, j / 5.0) + side * (5.0 if j % 2 == 0 else -5.0))
	pts.append(b)
	draw_polyline(pts, Color(0.75, 0.9, 1.0, 0.5), 4.0)
	draw_polyline(pts, Color.WHITE, 1.2)

func _art(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = Defs.tex(name)
	return _tex[name]
