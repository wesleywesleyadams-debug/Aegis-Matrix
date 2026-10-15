class_name MapEdge
extends Node2D
## The edge of the system (Game.MAP_RECT): space beyond it is shaded off, and
## a dashed boundary line with corner brackets marks where the playable area
## ends. The camera may look past the edge, so without this the background
## simply carried on and nothing said the map had stopped.

const LINE := Color(0.55, 0.65, 0.95, 0.55)
## How far the shade reaches past the edge: further than any zoom can show.
const BEYOND := 4000.0
const DASH := 28.0
const CORNER := 90.0

## Out of bounds is blurred, drained of colour, tinted and striped, so it
## reads as "not part of the map" at a glance - darker fog alone could be
## mistaken for unexplored space.
const OUTSIDE_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.32, 0.08, 0.18, 0.55);
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 3.5).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 d = mix(c, vec3(g), 0.75) * 0.55;
	vec3 col = mix(d, tint.rgb, tint.a);
	// Faint diagonal hazard stripes, fixed to the screen.
	float stripe = step(0.5, fract((FRAGCOORD.x + FRAGCOORD.y) / 28.0));
	col *= 1.0 - stripe * 0.18;
	COLOR = vec4(col, 1.0);
}
"""

var _outside: Node2D

func _ready() -> void:
	# Over the backdrop and nebulae, under everything that moves.
	z_index = 5
	_outside = Node2D.new()
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = OUTSIDE_SHADER
	mat.shader = sh
	_outside.material = mat
	_outside.draw.connect(_draw_outside)
	_outside.show_behind_parent = true
	add_child(_outside)

## The four bands beyond the edge, drawn through the shader above.
func _draw_outside() -> void:
	var r := Game.MAP_RECT
	_outside.draw_rect(Rect2(r.position.x - BEYOND, r.position.y - BEYOND, r.size.x + BEYOND * 2.0, BEYOND), Color.WHITE)
	_outside.draw_rect(Rect2(r.position.x - BEYOND, r.end.y, r.size.x + BEYOND * 2.0, BEYOND), Color.WHITE)
	_outside.draw_rect(Rect2(r.position.x - BEYOND, r.position.y, BEYOND, r.size.y), Color.WHITE)
	_outside.draw_rect(Rect2(r.end.x, r.position.y, BEYOND, r.size.y), Color.WHITE)

func _draw() -> void:
	var r := Game.MAP_RECT
	# A dashed line along the edge itself.
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var t := 0.0
		while t < length:
			draw_line(a + dir * t, a + dir * minf(t + DASH, length), LINE, 3.0)
			t += DASH * 2.0
	# Solid brackets at the corners, so the corners read even when zoomed in.
	for i in 4:
		var c: Vector2 = corners[i]
		var to_next: Vector2 = (corners[(i + 1) % 4] - c).normalized()
		var to_prev: Vector2 = (corners[(i + 3) % 4] - c).normalized()
		draw_line(c, c + to_next * CORNER, Color(LINE, 0.9), 5.0)
		draw_line(c, c + to_prev * CORNER, Color(LINE, 0.9), 5.0)
