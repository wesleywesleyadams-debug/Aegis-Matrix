shader_type canvas_item;
// Full-screen parallax space background. Each layer is a tiling texture
// sampled in world-pixel units, scrolled by a fraction of the camera
// position and snapped to the current zoom so texels stay square.
// The tiles are drawn at art_scale texels per world pixel (see
// Defs.ART_SCALE), so a tile still spans tile_px / art_scale world pixels.

uniform sampler2D stars : repeat_enable, filter_nearest;
uniform sampler2D nebula : repeat_enable, filter_nearest;
uniform sampler2D dust : repeat_enable, filter_nearest;
uniform vec2 cam = vec2(0.0);
uniform float zoom = 3.0;
uniform vec2 screen_size = vec2(1920.0, 1080.0);
uniform vec4 base_color : source_color = vec4(0.027, 0.024, 0.059, 1.0);
uniform float nebula_alpha = 0.35;
// Per-system look: multiplies the nebula layer's color (1,1,1 = as painted).
uniform vec3 nebula_tint = vec3(1.0);

uniform float art_scale = 2.0;
uniform float tile_px = 1024.0;

vec4 layer(sampler2D tex, vec2 px, float factor) {
	vec2 p = floor((px + cam * factor) * art_scale);
	return texture(tex, p / tile_px);
}

void fragment() {
	vec2 px = (FRAGCOORD.xy - screen_size * 0.5) / zoom;
	vec3 c = base_color.rgb;
	vec4 s = layer(stars, px, 0.05);
	c = mix(c, s.rgb, s.a);
	vec4 n = layer(nebula, px, 0.15);
	c = mix(c, clamp(n.rgb * nebula_tint, 0.0, 1.0), n.a * nebula_alpha);
	vec4 d = layer(dust, px, 0.4);
	c = mix(c, d.rgb, d.a);
	COLOR = vec4(c, 1.0);
}
