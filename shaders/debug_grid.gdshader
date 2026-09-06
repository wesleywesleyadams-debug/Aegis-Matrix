shader_type spatial;
// Reference grid drawn over the ground so movement direction and formation
// spacing can be judged by eye while testing -- purely visual, units don't
// snap to these cells. Line spacing defaults to FORMATION_SPACING so a
// tight formation's slots line up with it.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform float cell_size : hint_range(0.1, 20.0) = 2.6;
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.45);
uniform vec4 major_line_color : source_color = vec4(1.0, 0.85, 0.2, 0.6);
uniform int major_every : hint_range(1, 20) = 5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 coord = world_pos.xz / cell_size;
	vec2 deriv = max(fwidth(coord), vec2(0.0001));

	vec2 grid = fract(coord);
	vec2 dist_to_line = min(grid, 1.0 - grid);
	vec2 line = dist_to_line / deriv;
	float alpha = 1.0 - clamp(min(line.x, line.y), 0.0, 1.0);

	// Thicker, brighter line every `major_every` cells (e.g. every 5th
	// formation-spacing line) so distances are easier to count by eye.
	vec2 major_coord = coord / float(major_every);
	vec2 major_deriv = max(fwidth(major_coord), vec2(0.0001));
	vec2 major_grid = fract(major_coord);
	vec2 major_dist = min(major_grid, 1.0 - major_grid);
	vec2 major_line = major_dist / major_deriv;
	float major_alpha = 1.0 - clamp(min(major_line.x, major_line.y), 0.0, 1.0);

	vec3 color = mix(line_color.rgb, major_line_color.rgb, major_alpha);
	float final_alpha = max(alpha * line_color.a, major_alpha * major_line_color.a);

	ALBEDO = color;
	ALPHA = final_alpha;
}
