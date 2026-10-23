class_name CodexArt
extends Control
## Small explanatory pictures for the Codex, drawn from the game's own sprites
## and colors, so a player can see a rule instead of reading it. Each kind is
## one picture (see _draw); the Codex puts a one-line caption under it.

const BG := Color("070a18")
const FRAME := Color("2b3a6b")
const INK := Color("e6ecff")
const DIM := Color("8a95b8")
const ARROW := Color("8fb4ff")
const W := 460.0
const H := 150.0

var kind := ""
var _tex := {}
var _font: Font

func _init(k: String = "", size_px: Vector2 = Vector2(W, H)) -> void:
	kind = k
	custom_minimum_size = size_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	_font = get_theme_default_font()

func _art(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = Defs.tex(name)
	return _tex[name]

## A sprite centred at `c`, fitted into a box `box` wide; team trim tinted.
func _sprite(name: String, c: Vector2, box: float, team: Color = Color.TRANSPARENT, rot: float = 0.0) -> void:
	var t := _art(name)
	if t == null:
		return
	var k: float = box / maxf(t.get_width(), t.get_height())
	var r := Rect2(-t.get_size() * k * 0.5, t.get_size() * k)
	draw_set_transform(c, rot)
	draw_texture_rect(t, r, false)
	if team.a > 0.0 and ResourceLoader.exists(Defs.PIXEL + name + "_team.png"):
		draw_texture_rect(_art(name + "_team"), r, false, team)
	draw_set_transform(Vector2.ZERO)

func _text(s: String, at: Vector2, col: Color = INK, size: int = 13, center: bool = true) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_font, at - Vector2(w * 0.5 if center else 0.0, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _arrow(a: Vector2, b: Vector2, col: Color = ARROW, w: float = 2.0) -> void:
	draw_line(a, b, col, w)
	var d := (b - a).normalized()
	draw_colored_polygon(PackedVector2Array([b, b - d * 9.0 + d.orthogonal() * 5.0, b - d * 9.0 - d.orthogonal() * 5.0]), col)

func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Color(col, 0.18))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)

func _draw() -> void:
	var sz := custom_minimum_size
	draw_rect(Rect2(Vector2.ZERO, sz), BG)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	for k in 30:
		draw_rect(Rect2(Vector2(rng.randf() * sz.x, rng.randf() * sz.y), Vector2.ONE), Color(1, 1, 1, rng.randf_range(0.15, 0.5)))
	if has_method("_k_" + kind):
		call("_k_" + kind)
	draw_rect(Rect2(Vector2.ZERO, sz), FRAME, false, 2.0)

const SH := Color("4fb4ff")
const AR := Color("ff4a4a")
const HU := Color("4ade80")
const YOU := Color("4fb4ff")
const FOE := Color("ff4f5e")

# --- Overview -------------------------------------------------------------

## The loop: belts -> harvesters -> starbase -> warships -> the enemy; worlds
## feed and power it all.
func _k_loop() -> void:
	var pts := [Vector2(50, 60), Vector2(140, 60), Vector2(240, 60), Vector2(340, 60), Vector2(420, 60)]
	_sprite("asteroid_big_0", pts[0], 34)
	_sprite("ship_miner", pts[1], 30, YOU)
	_sprite("starbase", pts[2], 44, YOU)
	_sprite("ship_corvette", pts[3], 30, YOU)
	_sprite("planet_terran_s", pts[4], 40)
	for i in 4:
		_arrow(pts[i] + Vector2(22, 0), pts[i + 1] - Vector2(22, 0))
	_text("mine", pts[0] + Vector2(0, 40), DIM)
	_text("haul", pts[1] + Vector2(0, 40), DIM)
	_text("build", pts[2] + Vector2(0, 40), DIM)
	_text("attack", pts[3] + Vector2(0, 40), DIM)
	_text("take worlds", pts[4] + Vector2(0, 40), DIM)
	_sprite("planet_desert_s", Vector2(150, 128), 24)
	_arrow(Vector2(166, 124), Vector2(225, 92), Color("8fe060"))
	_text("your worlds feed and power it all", Vector2(178, 140), Color("8fe060"), 12, false)

## You lose with no worlds, or with no starbase AND no Constructor.
func _k_lose() -> void:
	_sprite("planet_terran_s", Vector2(70, 62), 50)
	_cross(Vector2(70, 62), 30)
	_text("no worlds", Vector2(70, 120), INK)
	_text("or", Vector2(165, 68), DIM, 16)
	_sprite("starbase", Vector2(250, 62), 50, YOU)
	_cross(Vector2(250, 62), 30)
	_text("+", Vector2(310, 68), DIM, 18)
	_sprite("ship_constructor", Vector2(370, 62), 34, YOU)
	_cross(Vector2(370, 62), 24)
	_text("no starbase and no Constructor", Vector2(310, 120), INK)
	_text("= defeat", Vector2(230, 142), FOE, 13)

func _cross(c: Vector2, r: float) -> void:
	draw_line(c - Vector2(r, r), c + Vector2(r, r), FOE, 4.0)
	draw_line(c + Vector2(-r, r), c + Vector2(r, -r), FOE, 4.0)

## Fog of war: unexplored (black), explored (dim terrain), in sight (all).
func _k_fog() -> void:
	var cols := [["Unexplored", "nothing"], ["Explored", "terrain, last owner"], ["In sensor range", "everything"]]
	for i in 3:
		var r := Rect2(Vector2(12 + i * 150, 12), Vector2(138, 100))
		draw_rect(r, Color(0, 0, 0, 1.0) if i == 0 else BG)
		if i >= 1:
			_sprite("planet_desert_s", r.position + Vector2(40, 45), 34)
			_sprite("asteroid_0", r.position + Vector2(95, 30), 16)
			_sprite("asteroid_0", r.position + Vector2(105, 55), 14)
		if i == 2:
			_sprite("ship_corvette", r.position + Vector2(100, 78), 22, FOE, PI)
			draw_line(r.position + Vector2(88, 78), r.position + Vector2(60, 70), Color("ffd84a"), 1.5)
		if i == 1:
			draw_rect(r, Color(0.03, 0.04, 0.1, 0.55))
		draw_rect(r, FRAME, false, 1.0)
		_text(cols[i][0], Vector2(r.position.x + 69, 128), INK)
		_text(cols[i][1], Vector2(r.position.x + 69, 144), DIM, 11)

# --- Combat ---------------------------------------------------------------

## Damage drains shields, then armor, then hull.
func _k_layers() -> void:
	_sprite("ship_corvette", Vector2(40, 75), 34, FOE, PI)
	draw_line(Vector2(60, 75), Vector2(118, 75), Color("ffd84a"), 2.0)
	var x := 130.0
	var labels := [["Shields", SH, "1", "recharge"], ["Armor", AR, "2", "stays down"], ["Hull", HU, "3", "0 = destroyed"]]
	for i in 3:
		var r := Rect2(Vector2(x + i * 108, 58), Vector2(96, 34))
		_bar(r, 0.0 if i == 0 else (0.45 if i == 1 else 1.0), labels[i][1])
		draw_rect(r, labels[i][1], false, 1.5)
		_text(labels[i][2], r.position + Vector2(48, 24), INK, 16)
		_text(labels[i][0], r.position + Vector2(48, -10), labels[i][1])
		_text(labels[i][3], r.position + Vector2(48, 54), DIM, 11)
		if i < 2:
			_arrow(r.position + Vector2(98, 17), r.position + Vector2(110, 17), DIM, 1.5)

## Shields refill only after a quiet spell.
func _k_shield_regen() -> void:
	var base := Vector2(30, 110)
	draw_line(base, base + Vector2(400, 0), DIM, 1.0)
	var pts := PackedVector2Array([base + Vector2(0, -70), base + Vector2(40, -40), base + Vector2(70, -55), base + Vector2(100, -20),
		base + Vector2(220, -20), base + Vector2(400, -75)])
	draw_polyline(pts, SH, 3.0)
	for hx in [40.0, 70.0, 100.0]:
		draw_line(base + Vector2(hx, -82), base + Vector2(hx, -66), FOE, 2.0)
	_text("hits", base + Vector2(20, -88), FOE, 12)
	draw_rect(Rect2(base + Vector2(100, -100), Vector2(120, 100)), Color(1, 1, 1, 0.05))
	_text("%d s with no hits" % int(Defs.SHIELD_REGEN_DELAY), base + Vector2(160, 18), INK, 12)
	_text("then +%s%% a second" % String.num(Defs.SHIELD_REGEN_PER_SEC * 100.0, 1), base + Vector2(320, 18), SH, 12)

## What each variant's shot does to the three layers.
func _k_variants() -> void:
	var rows := [["Generalist", Defs.GENERALIST_SHOT, [1.0, 1.0, 1.0], ""]]
	for v in Defs.VARIANTS:
		var vd: Dictionary = Defs.VARIANTS[v]
		var m := [vd["vs"].get("shield", 1.0) * vd["damage"], vd["vs"].get("armor", 1.0) * vd["damage"], vd["vs"].get("hull", 1.0) * vd["damage"]]
		if vd["pierce"] >= 1:
			m[0] = -1.0
		if vd["pierce"] >= 2:
			m[1] = -1.0
		rows.append([vd["label"], vd["color"], m, ""])
	var lay := [SH, AR, HU]
	_text("Shields", Vector2(205, 16), SH, 12)
	_text("Armor", Vector2(305, 16), AR, 12)
	_text("Hull", Vector2(405, 16), HU, 12)
	for i in rows.size():
		var y := 30.0 + i * 19.0
		_text(rows[i][0], Vector2(14, y + 11), rows[i][1], 12, false)
		draw_line(Vector2(104, y + 7), Vector2(146, y + 7), rows[i][1], 2.0)
		for l in 3:
			var m: float = rows[i][2][l]
			var r := Rect2(Vector2(160 + l * 100, y), Vector2(64, 13))
			if m < 0.0:
				_text("skipped", r.position + Vector2(45, 11), DIM, 11)
			else:
				_bar(r, m / 2.3, lay[l])
				_text("x%.1f" % m, r.position + Vector2(r.size.x + 2, 11), INK if absf(m - 1.0) > 0.05 else DIM, 10, false)

## Generalist -> Weapons Depot -> specialist.
func _k_depot() -> void:
	_sprite("ship_corvette", Vector2(55, 65), 36, YOU)
	_text("generalist", Vector2(55, 108), Defs.GENERALIST_SHOT)
	_arrow(Vector2(85, 65), Vector2(160, 65))
	_text("right-click", Vector2(122, 55), DIM, 11)
	var dep := "ship_depot_plasma" if ResourceLoader.exists(Defs.PIXEL + "ship_depot_plasma.png") else "ship_depot_base"
	_sprite(dep, Vector2(215, 65), 70, YOU)
	_text("Weapons Depot", Vector2(215, 118), INK)
	_text("docks, pays minerals, waits", Vector2(215, 135), DIM, 11)
	_arrow(Vector2(265, 65), Vector2(340, 65))
	_sprite("ship_corvette", Vector2(390, 65), 36, YOU)
	var vc: Color = Defs.VARIANTS[Defs.VARIANTS.keys()[0]]["color"]
	_text("specialist", Vector2(390, 108), vc)
	_text("one variant per depot", Vector2(390, 125), DIM, 11)

## A Mod's card: active -> click -> switched off (yellow) -> click -> back on.
func _k_mod_toggle() -> void:
	var cards := [["Active", Color("4ade80")], ["Switched off", Color("ffd84a")], ["Active", Color("4ade80")]]
	for i in 3:
		var r := Rect2(Vector2(20 + i * 150, 24), Vector2(116, 80))
		draw_rect(r, Color("141b38"))
		draw_rect(r, cards[i][1], false, 2.0)
		_sprite("ship_corvette", r.position + Vector2(58, 32), 30, YOU)
		_text(cards[i][0], r.position + Vector2(58, 68), cards[i][1], 12)
		if i < 2:
			_arrow(r.position + Vector2(120, 40), r.position + Vector2(146, 40))
			_text("click", r.position + Vector2(133, 30), DIM, 11)
	_text("Off = the class fires its standard laser. Switching is free.", Vector2(230, 130), DIM, 12)

func _k_blasts() -> void:
	var k := 1.3
	var items := [["flak", "Flak shell"], ["missile", "Missile"], ["proton", "Proton torpedo"], ["bomblet", "Bomblet"]]
	var x := 60.0
	for it in items:
		var r: float = Defs.AOE_RADIUS[it[0]] * k
		var c := Vector2(x, 70)
		draw_circle(c, r, Color(1, 0.6, 0.2, 0.18))
		draw_arc(c, r, 0, TAU, 32, Color("ffb347"), 1.5)
		_sprite("ship_corvette", c, 22 * k, FOE, PI)
		_text(it[1], Vector2(x, 132), INK, 12)
		_text("radius %d" % int(Defs.AOE_RADIUS[it[0]]), Vector2(x, 147), DIM, 11)
		x += maxf(r * 2.0 + 24.0, 100.0)

# --- Economy --------------------------------------------------------------

## The harvest cycle: park, fill, haul home, return.
func _k_harvest() -> void:
	_sprite("asteroid_big_0", Vector2(60, 60), 40)
	_sprite("ship_miner", Vector2(110, 60), 28, YOU, PI)
	_bar(Rect2(Vector2(90, 84), Vector2(40, 6)), 0.7, Color("3fd6b0"))
	_text("1 fill the hold", Vector2(90, 112), INK, 12)
	_arrow(Vector2(140, 50), Vector2(320, 50))
	_text("2 haul it home", Vector2(230, 40), INK, 12)
	_sprite("starbase", Vector2(370, 60), 56, YOU)
	_arrow(Vector2(320, 80), Vector2(140, 80), DIM, 1.5)
	_text("3 back for more", Vector2(230, 100), DIM, 12)
	_text("Distance costs flying time, not gather rate: build closer drop-offs.", Vector2(230, 138), DIM, 11)

# --- Systems --------------------------------------------------------------

## Radiation: the star's zone hurts everyone inside; a Rad Sail bubble
## shields everything in it.
func _k_radiation() -> void:
	var c := Vector2(120, 75)
	draw_circle(c, 60, Color(1, 0.55, 0.15, 0.16))
	draw_arc(c, 60, 0, TAU, 40, Color("ffae4a"), 1.5)
	draw_circle(c, 14, Color("ffd060"))
	_sprite("ship_corvette", c + Vector2(40, -18), 22, YOU)
	_sprite("ship_corvette", c + Vector2(-38, 26), 22, FOE)
	_text("Radiation hurts everyone inside", Vector2(120, 147), Color("ffae4a"), 11)
	var c2 := Vector2(350, 70)
	draw_circle(c2, 50, Color(0.6, 0.45, 1.0, 0.18))
	draw_arc(c2, 50, 0, TAU, 40, Color("c9a0ff"), 2.0)
	_sprite("ship_heatshield", c2, 30, YOU)
	_sprite("ship_corvette", c2 + Vector2(28, 18), 20, YOU)
	_text("A charged Rad Sail bubble blocks it", Vector2(350, 147), Color("c9a0ff"), 11)


# --- Variants: what each is for ---------------------------------------------

## use_<variant>: a ship in the variant's colors firing at its best targets
## (ticked), with the targets to avoid crossed out underneath.
const VARIANT_USE := {
	"generalist": [["ship_corvette", "ship_destroyer", "ship_cruiser", "starbase"], []],
	"plasma": [["ship_cruiser", "ship_carrier"], ["ship_corvette", "ship_destroyer"]],
	"breacher": [["ship_destroyer"], ["ship_cruiser"]],
	"reaver": [["ship_corvette", "planet_terran_s"], ["ship_carrier"]],
	"disruptor": [["ship_cruiser"], ["ship_destroyer", "ship_corvette"]],
	"inhibitor": [["ship_carrier", "ship_cruiser"], ["ship_corvette", "ship_destroyer"]],
}

func _draw_use(v: String) -> void:
	var col: Color = Defs.GENERALIST_SHOT if v == "generalist" else Defs.VARIANTS[v]["color"]
	_sprite("ship_destroyer", Vector2(34, 75), 44, col)
	draw_line(Vector2(58, 75), Vector2(84, 75), col, 2.5)
	var good: Array = VARIANT_USE[v][0]
	var bad: Array = VARIANT_USE[v][1]
	var gap := 50.0 if good.size() > 2 else 62.0
	_text("best vs", Vector2(98, 22), Color("4ade80"), 11, false)
	for i in good.size():
		var p := Vector2(118 + i * gap, 52)
		_sprite(good[i], p, 44, FOE, PI)
		draw_circle(p + Vector2(17, -17), 7, Color("4ade80"))
		draw_line(p + Vector2(13, -17), p + Vector2(16, -14), Color.BLACK, 2.0)
		draw_line(p + Vector2(16, -14), p + Vector2(21, -21), Color.BLACK, 2.0)
	if not bad.is_empty():
		_text("avoid", Vector2(98, 96), FOE, 11, false)
		for i in bad.size():
			var p := Vector2(118 + i * 62, 120)
			_sprite(bad[i], p, 34, FOE, PI)
			_cross(p, 14)

func _k_use_generalist() -> void: _draw_use("generalist")
func _k_use_plasma() -> void: _draw_use("plasma")
func _k_use_breacher() -> void: _draw_use("breacher")
func _k_use_reaver() -> void: _draw_use("reaver")
func _k_use_disruptor() -> void: _draw_use("disruptor")
func _k_use_inhibitor() -> void: _draw_use("inhibitor")
