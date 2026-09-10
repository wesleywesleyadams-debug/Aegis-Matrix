shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

// Stylized sci-fi hologram look: flat rim-lit glow, horizontal scanlines
// that scroll upward, and a subtle flicker -- deliberately NOT using the
// model's own base color texture at all, which sidesteps the UV-transfer
// fidelity/streaking issues real skin texture has been fighting (see this
// project's appearance-system history). Applied as a material_override,
// so it replaces whatever surface material (skin/shorts/etc.) is normally
// there.

uniform vec4 hologram_color : source_color = vec4(0.25, 0.85, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
uniform float scanline_density : hint_range(5.0, 200.0) = 40.0;
uniform float scanline_speed : hint_range(0.0, 5.0) = 0.6;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.35;
uniform float flicker_speed : hint_range(0.0, 20.0) = 6.0;
uniform float flicker_strength : hint_range(0.0, 0.5) = 0.08;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.55;

varying vec3 world_normal;
varying vec3 view_dir;
varying vec3 world_pos;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = normalize(cam_pos - world_pos);
	float rim = 1.0 - clamp(dot(world_normal, to_cam), 0.0, 1.0);
	rim = pow(rim, rim_power);

	float scan = sin(world_pos.y * scanline_density - TIME * scanline_speed * 10.0);
	scan = smoothstep(0.6, 1.0, scan) * scanline_strength;

	float flicker = 1.0 - flicker_strength * 0.5 + flicker_strength * sin(TIME * flicker_speed);

	float glow = clamp(rim + scan, 0.0, 1.5) * flicker;
	ALBEDO = hologram_color.rgb;
	EMISSION = hologram_color.rgb * (0.4 + glow);
	ALPHA = clamp(base_alpha * flicker + rim * 0.5 + scan, 0.05, 1.0);
}
