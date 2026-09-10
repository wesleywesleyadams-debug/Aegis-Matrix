shader_type sky;

// A near-black void with sparse procedural stars, in place of the usual
// blue sky/horizon gradient -- mostly seen only at the very edge of the
// map (the camera is clamped to stay within the ground plane, see
// RTSCamera._clamp_to_map, so this is now rarely more than a sliver at
// the screen's top edge when fully zoomed out at the map's border), but
// should read as "empty space" rather than daylight when it is.

uniform vec3 void_color : source_color = vec3(0.01, 0.01, 0.03);
uniform float star_density : hint_range(0.0, 1.0) = 0.0025;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.4;

// Cheap hash -- no texture lookup, just enough pseudo-randomness per
// direction to scatter stars without any visible tiling pattern.
float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 dir = EYEDIR;
	float cell = hash(floor(dir * 400.0));
	float star = step(1.0 - star_density, cell) * star_brightness;
	// A second, coarser hash so not every star is the exact same
	// brightness -- avoids a flat "grid of dots" look.
	star *= 0.6 + 0.4 * hash(floor(dir * 400.0) + 7.0);
	COLOR = void_color + vec3(star);
}
