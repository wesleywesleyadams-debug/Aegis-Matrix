shader_type sky;

// A near-black void with twinkling procedural stars, an occasional
// comet sweeping past, and a couple of slowly-spinning planets -- in
// place of the usual blue sky/horizon gradient. Mostly seen only at
// the very edge of the map (the camera is clamped to stay within the
// ground plane, see RTSCamera._clamp_to_map), but should read as
// "living empty space" rather than a static painted backdrop on the
// rare frame it is.

uniform vec3 void_color : source_color = vec3(0.01, 0.01, 0.03);
uniform float star_density : hint_range(0.0, 1.0) = 0.0025;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.4;
uniform float twinkle_speed : hint_range(0.0, 10.0) = 2.0;

uniform float comet_period : hint_range(1.0, 120.0) = 22.0;
uniform float comet_duration : hint_range(0.5, 10.0) = 3.5;

// Cheap hash -- no texture lookup, just enough pseudo-randomness per
// direction to scatter stars without any visible tiling pattern.
float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 stars(vec3 dir) {
	vec3 cell = floor(dir * 400.0);
	float presence = hash(cell);
	float star = step(1.0 - star_density, presence);
	// Each star gets its own phase (from a second hash) so they don't
	// all twinkle in lockstep, plus its own base brightness so the
	// field isn't perfectly uniform even at full brightness.
	float phase = hash(cell + 7.0) * TAU;
	float twinkle = 0.5 + 0.5 * sin(TIME * twinkle_speed + phase);
	float brightness = 0.6 + 0.4 * hash(cell + 13.0);
	return vec3(star * star_brightness * twinkle * brightness);
}

// A short bright streak that sweeps along a fixed great-circle-ish arc
// once every comet_period seconds, visible for comet_duration of it,
// then gone until the next cycle. `progress` is 0 at the head's start,
// 1 at its end -- the trail is just a handful of samples further back
// along the same path, each dimmer and narrower than the last.
vec3 comet(vec3 dir) {
	float t = mod(TIME, comet_period);
	if (t >= comet_duration) {
		return vec3(0.0);
	}
	float progress = t / comet_duration;
	vec3 comet_start = normalize(vec3(-0.85, 0.55, -0.25));
	vec3 comet_end = normalize(vec3(0.9, 0.15, 0.65));
	vec3 head_pos = normalize(mix(comet_start, comet_end, progress));
	float head_dist = distance(dir, head_pos);
	float glow = smoothstep(0.05, 0.0, head_dist) * 3.0;
	glow += smoothstep(0.012, 0.0, head_dist) * 5.0;

	float trail = 0.0;
	const int TRAIL_STEPS = 8;
	for (int i = 1; i <= TRAIL_STEPS; i++) {
		float trail_progress = progress - float(i) * 0.018;
		if (trail_progress < 0.0) {
			continue;
		}
		vec3 trail_pos = normalize(mix(comet_start, comet_end, trail_progress));
		float d = distance(dir, trail_pos);
		float fade = 1.0 - float(i) / float(TRAIL_STEPS);
		trail += smoothstep(0.01, 0.0, d) * fade * 2.0;
	}
	return vec3(0.75, 0.85, 1.0) * (glow + trail);
}

// One slowly-spinning banded sphere at a fixed sky direction --
// `center`/`radius` place and size it, `rotate_speed` spins the bands
// around its own local "up" axis, `base_color`/`band_color` alternate
// between latitude stripes for a gas-giant-ish look, and a simple
// dot-with-`center` falloff fakes limb darkening at the disc's edge so
// it still reads as a sphere rather than a flat painted circle.
vec3 planet(vec3 dir, vec3 center, float radius, float rotate_speed, vec3 base_color, vec3 band_color) {
	float d = distance(dir, center);
	if (d >= radius) {
		return vec3(0.0);
	}
	vec3 arbitrary = abs(center.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent = normalize(cross(arbitrary, center));
	vec3 bitangent = cross(center, tangent);
	vec3 offset = dir - center * dot(dir, center);
	float local_u = dot(offset, tangent);
	float local_v = dot(offset, bitangent);
	float spin = TIME * rotate_speed;
	float band = sin(local_v * 26.0 + local_u * 4.0 + spin) * 0.5 + 0.5;
	vec3 surface = mix(base_color, band_color, band);
	float limb = smoothstep(radius, radius * 0.2, d);
	return surface * limb;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 color = void_color;
	color += stars(dir);
	color += comet(dir);
	color += planet(dir, normalize(vec3(0.55, 0.35, -0.7)), 0.12, 0.15, vec3(0.55, 0.4, 0.25), vec3(0.75, 0.6, 0.4));
	color += planet(dir, normalize(vec3(-0.4, 0.6, 0.6)), 0.07, -0.25, vec3(0.3, 0.45, 0.6), vec3(0.55, 0.7, 0.8));
	COLOR = color;
}
