extends Control
class_name ResourceIcon
## A small square icon drawn procedurally (no image assets exist for this
## project's resources/roles yet -- same "stand-in art via primitives"
## reasoning ColorRect swatches used everywhere else in this HUD, just
## detailed enough per-icon_type to actually read as the thing it names
## rather than a flat color). Used by ResourceHUD for its resource/
## villager/idle icons.
##
## Each icon_type draws itself entirely within this Control's own square
## `size` (see _draw()), so the caller only needs to set custom_minimum_size
## to get a consistent, larger square chip -- no separate background node.

@export var icon_type: String = "":
	set(value):
		icon_type = value
		queue_redraw()

## Square backing chip -- a touch darker than the HUD panel itself so each
## icon reads as its own tile, same "distinct square slot per icon" look
## AoE2:DE's own resource bar has.
const CHIP_COLOR: Color = Color(0.35, 0.24, 0.14)
const CHIP_BORDER_COLOR: Color = Color(0.2, 0.13, 0.07)

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	var s: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, s), CHIP_COLOR)
	draw_rect(Rect2(Vector2.ZERO, s), CHIP_BORDER_COLOR, false, 2.0)
	match icon_type:
		"acorns":
			_draw_acorn(s)
		"apples":
			_draw_apple(s)
		"mist":
			_draw_mist(s)
		"crystal":
			_draw_crystal(s)
		"peasant":
			_draw_peasant_portrait(s)
		"idle":
			_draw_idle_silhouette(s)
		"population":
			_draw_population(s)
		"age":
			_draw_age(s)

## Brown nut body (a capsule made of a rect + two circles) with a darker,
## slightly wider cap across the top -- the cap is what actually reads as
## "acorn" rather than just a plain brown oval.
func _draw_acorn(s: Vector2) -> void:
	var c := s / 2.0
	var body_color := Color(0.55, 0.35, 0.15)
	var cap_color := Color(0.32, 0.2, 0.1)
	var body_w := s.x * 0.34
	var body_top := s.y * 0.42
	var body_bottom := s.y * 0.82
	draw_rect(Rect2(c.x - body_w, body_top, body_w * 2.0, body_bottom - body_top), body_color)
	draw_circle(Vector2(c.x, body_bottom), body_w, body_color)
	draw_circle(Vector2(c.x, body_top), body_w, body_color)
	# Cap: wider than the body, flat-bottomed -- drawn as a polygon rather
	# than a circle so its underside reads as a sharp rim, not a round lobe.
	var cap_w := s.x * 0.42
	var cap_top := s.y * 0.2
	var points := PackedVector2Array([
		Vector2(c.x - cap_w, body_top + 2.0),
		Vector2(c.x + cap_w, body_top + 2.0),
		Vector2(c.x + cap_w * 0.75, cap_top),
		Vector2(c.x - cap_w * 0.75, cap_top),
	])
	draw_colored_polygon(points, cap_color)
	# Little stem poking out the top of the cap.
	draw_rect(Rect2(c.x - 1.5, cap_top - s.y * 0.08, 3.0, s.y * 0.08), cap_color)

## Light green apple body with a small notch at top, a brown stem, and a
## darker-green leaf -- the stem+leaf silhouette is what separates it from
## a plain green circle at a glance.
func _draw_apple(s: Vector2) -> void:
	var c := s / 2.0 + Vector2(0, s.y * 0.05)
	var body_color := Color(0.55, 0.85, 0.4)
	var shade_color := Color(0.4, 0.7, 0.3)
	var r := s.x * 0.32
	draw_circle(c + Vector2(-r * 0.35, -r * 0.15), r, body_color)
	draw_circle(c + Vector2(r * 0.35, -r * 0.15), r, body_color)
	draw_circle(c + Vector2(0, r * 0.25), r * 1.05, body_color)
	# Subtle shaded half so the apple doesn't read as perfectly flat.
	draw_circle(c + Vector2(r * 0.4, r * 0.1), r * 0.55, shade_color)
	# Stem.
	var stem_top := c + Vector2(0, -r * 1.05)
	draw_line(stem_top, stem_top + Vector2(1.5, -s.y * 0.14), Color(0.35, 0.22, 0.1), 2.5)
	# Leaf.
	var leaf_base := stem_top + Vector2(1.5, -s.y * 0.09)
	var leaf := PackedVector2Array([
		leaf_base,
		leaf_base + Vector2(s.x * 0.16, -s.y * 0.05),
		leaf_base + Vector2(s.x * 0.05, s.y * 0.05),
	])
	draw_colored_polygon(leaf, Color(0.3, 0.6, 0.25))

## Red cloud silhouette -- several overlapping circles, like a normal
## "cloud" icon glyph but tinted red/maroon so it reads as an ominous
## mist rather than plain weather.
func _draw_mist(s: Vector2) -> void:
	var c := s / 2.0
	var color := Color(0.75, 0.2, 0.2)
	var dark := Color(0.55, 0.12, 0.12)
	var r := s.x * 0.2
	draw_circle(c + Vector2(-r * 1.1, r * 0.35), r * 0.85, color)
	draw_circle(c + Vector2(r * 1.1, r * 0.35), r * 0.85, color)
	draw_circle(c + Vector2(-r * 0.3, -r * 0.25), r, color)
	draw_circle(c + Vector2(r * 0.5, -r * 0.15), r * 0.95, color)
	draw_circle(c + Vector2(0, r * 0.55), r * 1.1, dark)

## Blue faceted gem -- an outer diamond outline with an inner smaller
## diamond offset upward, so it reads as a cut crystal with a visible
## facet highlight rather than a flat rhombus.
func _draw_crystal(s: Vector2) -> void:
	var c := s / 2.0
	var color := Color(0.3, 0.55, 0.95)
	var light := Color(0.65, 0.82, 1.0)
	var w := s.x * 0.32
	var h := s.y * 0.38
	var outer := PackedVector2Array([
		c + Vector2(0, -h),
		c + Vector2(w, -h * 0.15),
		c + Vector2(0, h),
		c + Vector2(-w, -h * 0.15),
	])
	draw_colored_polygon(outer, color)
	var inner := PackedVector2Array([
		c + Vector2(0, -h * 0.7),
		c + Vector2(w * 0.45, -h * 0.2),
		c + Vector2(0, h * 0.1),
		c + Vector2(-w * 0.45, -h * 0.2),
	])
	draw_colored_polygon(inner, light)

## Side-view bust silhouette, waist-up -- a round head with a small nose
## bump facing right, sloped shoulders widening into a torso -- the
## "peasant portrait" stand-in used for the villager count icon.
func _draw_peasant_portrait(s: Vector2) -> void:
	var color := Color(0.75, 0.65, 0.5)
	var c := s / 2.0
	var head_r := s.x * 0.2
	var head_center := c + Vector2(s.x * 0.02, -s.y * 0.28)
	# Torso/shoulders: a rounded trapezoid widening toward the bottom.
	var torso := PackedVector2Array([
		head_center + Vector2(-head_r * 0.9, head_r * 0.6),
		head_center + Vector2(head_r * 0.9, head_r * 0.6),
		c + Vector2(s.x * 0.34, s.y * 0.42),
		c + Vector2(-s.x * 0.34, s.y * 0.42),
	])
	draw_colored_polygon(torso, color)
	draw_circle(head_center, head_r, color)
	# Nose bump -- a tiny triangle off the right side of the head, since
	# this is meant to read as a side profile, not a front-facing bust.
	var nose := PackedVector2Array([
		head_center + Vector2(head_r * 0.85, -head_r * 0.05),
		head_center + Vector2(head_r * 1.35, head_r * 0.15),
		head_center + Vector2(head_r * 0.85, head_r * 0.35),
	])
	draw_colored_polygon(nose, color)

## Tiny full-body silhouette leaning against a short wall segment -- the
## "idle villager" glyph: a vertical wall stub on one side, a slouched
## figure (head + curved body) leaning into it.
func _draw_idle_silhouette(s: Vector2) -> void:
	var color := Color(0.85, 0.8, 0.7)
	var wall_color := Color(0.5, 0.45, 0.4)
	# Wall segment along the right edge.
	var wall_x := s.x * 0.72
	draw_rect(Rect2(wall_x, s.y * 0.15, s.x * 0.14, s.y * 0.7), wall_color)
	# Figure: head + body leaning left, feet near the wall's base.
	var head_r := s.x * 0.13
	var head_center := Vector2(s.x * 0.38, s.y * 0.32)
	draw_circle(head_center, head_r, color)
	var body := PackedVector2Array([
		head_center + Vector2(-head_r * 0.7, head_r * 0.8),
		head_center + Vector2(head_r * 0.9, head_r * 1.1),
		Vector2(wall_x - 1.0, s.y * 0.82),
		Vector2(s.x * 0.28, s.y * 0.85),
	])
	draw_colored_polygon(body, color)

## Population icon: two small overlapping bust silhouettes (a simple
## "group" glyph) -- distinct from the single peasant portrait so the
## two icons don't look identical at a glance.
func _draw_population(s: Vector2) -> void:
	var back := Color(0.45, 0.55, 0.7)
	var front := Color(0.6, 0.68, 0.8)
	_draw_mini_bust(s, Vector2(s.x * 0.38, s.y * 0.4), s.x * 0.16, back)
	_draw_mini_bust(s, Vector2(s.x * 0.6, s.y * 0.45), s.x * 0.18, front)

func _draw_mini_bust(s: Vector2, head_center: Vector2, head_r: float, color: Color) -> void:
	draw_circle(head_center, head_r, color)
	var shoulder_w := head_r * 1.6
	var shoulders := PackedVector2Array([
		head_center + Vector2(-shoulder_w, head_r * 1.1),
		head_center + Vector2(shoulder_w, head_r * 1.1),
		head_center + Vector2(shoulder_w * 1.2, s.y * 0.4),
		head_center + Vector2(-shoulder_w * 1.2, s.y * 0.4),
	])
	draw_colored_polygon(shoulders, color)

## Age icon: a simple laurel-ish chevron/star stand-in -- this game has
## no age/era system yet (see ResourceHUD's own doc comment), so this is
## deliberately generic rather than depicting any specific era symbol.
func _draw_age(s: Vector2) -> void:
	var c := s / 2.0
	var color := Color(0.85, 0.75, 0.4)
	var r := s.x * 0.3
	var points := PackedVector2Array()
	for i in 5:
		var angle := -PI / 2.0 + i * TAU / 5.0
		points.append(c + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, color)
