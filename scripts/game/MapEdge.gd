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

## Out of bounds is the same sky in a different palette: the starfield and
## nebulae behind it are kept crisp but re-coloured along a navy -> teal ->
## ice ramp by brightness, so it stays pretty while plainly not being the
## map's colours.
const OUTSIDE_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec3 deep : source_color = vec3(0.012, 0.03, 0.075);
uniform vec3 mid : source_color = vec3(0.07, 0.26, 0.38);
uniform vec3 high : source_color = vec3(0.82, 0.95, 1.0);
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	// The sky is dark, so stretch its low end to bring the nebulae out.
	float t = clamp(l * 4.0, 0.0, 1.0);
	vec3 col = t < 0.5 ? mix(deep, mid, t * 2.0) : mix(mid, high, (t - 0.5) * 2.0);
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
