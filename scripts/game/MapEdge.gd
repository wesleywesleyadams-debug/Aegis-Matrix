class_name MapEdge
extends Node2D
## The edge of the system (a circle of Game.MAP_RADIUS): space beyond it is shaded off, and
## a dashed boundary line with ticks marks where the playable area
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

## Everything beyond the edge, as a wide ring drawn through the shader above.
func _draw_outside() -> void:
	var r0 := Game.MAP_RADIUS
	var n := 128
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		_outside.draw_colored_polygon(PackedVector2Array([
			Vector2.from_angle(a0) * r0, Vector2.from_angle(a1) * r0,
			Vector2.from_angle(a1) * (r0 + BEYOND), Vector2.from_angle(a0) * (r0 + BEYOND)]), Color.WHITE)

func _draw() -> void:
	var r0 := Game.MAP_RADIUS
	# A dashed line along the edge itself.
	var n := int(TAU * r0 / (DASH * 2.0))
	for i in n:
		var a := TAU * i / n
		draw_arc(Vector2.ZERO, r0, a, a + TAU / n * 0.5, 4, LINE, 3.0)
	# Solid ticks every 30 degrees, so the edge reads even when zoomed in.
	for i in 12:
		var a := TAU * i / 12.0
		draw_arc(Vector2.ZERO, r0, a - CORNER / r0, a + CORNER / r0, 8, Color(LINE, 0.9), 5.0)
