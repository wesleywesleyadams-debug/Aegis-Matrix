shader_type spatial;
render_mode blend_mix, cull_back;

// Flat-color/roughness copy of whatever StandardMaterial3D a building's
// mesh normally uses -- Building._apply_construction_shader reads those
// values off the original material at runtime and writes them in here,
// so a building under construction keeps its normal look instead of
// going flat white/grey while this shader is temporarily standing in.
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool use_texture = false;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;

// World-space Y above which fragments are discarded -- see
// Building._update_construction_shader. Building._full_height *
// max(MIN_REVEAL_FRACTION, get_construction_progress()) above the
// building's own base, so raising this over time is what makes the
// building appear to fill in from the ground up.
uniform float reveal_world_y = 0.0;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	if (world_y > reveal_world_y) {
		discard;
	}
	vec4 tex_color = use_texture ? texture(albedo_texture, UV) : vec4(1.0);
	ALBEDO = albedo_color.rgb * tex_color.rgb;
	ALPHA = albedo_color.a * tex_color.a;
	ROUGHNESS = roughness;
}
