shader_type sky;

// A near-black void with drifting nebula clouds, twinkling procedural
// stars, an occasional comet sweeping past, and a couple of
// slowly-spinning ringed planets with a soft rim-light -- in place of
// the usual blue sky/horizon gradient. Mostly seen only at the very
// edge of the map (the camera is clamped to stay within the ground
// plane, see RTSCamera._clamp_to_map), but should read as "living
// empty space" rather than a static painted backdrop on the rare frame
// it is.

uniform vec3 void_color : source_color = vec3(0.01, 0.01, 0.03);
uniform float star_density : hint_range(0.0, 1.0) = 0.35;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.4;
uniform float star_radius : hint_range(0.01, 0.4) = 0.12;
uniform float twinkle_speed : hint_range(0.0, 10.0) = 2.0;

uniform float comet_period : hint_range(1.0, 120.0) = 22.0;
uniform float comet_duration : hint_range(0.5, 10.0) = 3.5;

uniform float nebula_intensity : hint_range(0.0, 2.0) = 0.55;
uniform float nebula_drift_speed : hint_range(0.0, 0.2) = 0.015;

// Cheap hash -- no texture lookup, just enough pseudo-randomness per
// direction to scatter stars without any visible tiling pattern.
float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

const float STAR_GRID_SCALE = 22.0;

// Projects `dir` onto whichever of the 6 cube faces it points most
// toward, returning that face's local 2D coordinates (roughly -1..1,
// uniform scale near the face center) and a per-face id folded into
// `face_seed` so each face's grid is independently seeded -- avoids the
// two failure modes a naive sphere-to-2D mapping hits: a raw
// 3D-cubic-lattice hash cuts through cells at all sorts of angles
// depending on view direction (stretched streaks, not points), and an
// equirectangular (azimuth/elevation) grid still pinches to a point at
// its poles. Cube-face projection has no such singularity -- only
// mild, bounded stretching near face edges/corners, not a hard pinch
// anywhere. Shared by stars() and nebula() so both stay undistorted.
vec2 cube_face_uv(vec3 dir, out float face_seed) {
	vec3 a = abs(dir);
	if (a.x >= a.y && a.x >= a.z) {
		face_seed = sign(dir.x) > 0.0 ? 0.0 : 1.0;
		return dir.yz / a.x;
	}
	if (a.y >= a.x && a.y >= a.z) {
		face_seed = sign(dir.y) > 0.0 ? 2.0 : 3.0;
		return dir.xz / a.y;
	}
	face_seed = sign(dir.z) > 0.0 ? 4.0 : 5.0;
	return dir.xy / a.z;
}

// Round dots everywhere on the sky -- see cube_face_uv's doc comment
// for why a cube-face projection instead of the two more obvious (but
// distortion-prone) approaches. One candidate star position is
// jittered per grid cell in the chosen face's local UV space, then
// drawn as an actual circle (distance-based falloff, fixed
// star_radius), so it stays round from every direction rather than
// stretching near any particular view angle.
vec3 stars(vec3 dir) {
	float face_seed;
	vec2 face_uv = cube_face_uv(dir, face_seed);
	vec2 uv = face_uv * STAR_GRID_SCALE;
	vec2 cell = floor(uv);
	vec2 local_uv = fract(uv) - 0.5;
	vec3 seed = vec3(cell, face_seed);

	float presence = hash(seed + 1.0);
	if (presence > star_density) {
		return vec3(0.0);
	}
	vec2 jitter = (vec2(hash(seed + 2.0), hash(seed + 3.0)) - 0.5) * 0.7;
	float dist_to_star = length(local_uv - jitter);
	float dot_mask = smoothstep(star_radius, 0.0, dist_to_star);

	// Each star gets its own phase (from a second hash) so they don't
	// all twinkle in lockstep, plus its own base brightness so the
	// field isn't perfectly uniform even at full brightness.
	float phase = hash(seed + 4.0) * TAU;
	float twinkle = 0.5 + 0.5 * sin(TIME * twinkle_speed + phase);
	float brightness = 0.6 + 0.4 * hash(seed + 5.0);
	return vec3(dot_mask * star_brightness * twinkle * brightness);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float a = hash(vec3(cell, 10.0));
	float b = hash(vec3(cell + vec2(1.0, 0.0), 10.0));
	float c = hash(vec3(cell + vec2(0.0, 1.0), 10.0));
	float d = hash(vec3(cell + vec2(1.0, 1.0), 10.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 4-octave fractal noise -- cheap, no texture, just layered value_noise
// at doubling frequency/halving amplitude, giving the soft billowing
// blob shapes nebula() blends colors across.
float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		total += amplitude * value_noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return total;
}

// Soft drifting purple/magenta/blue cloud -- two independent fbm
// samples (offset from each other so they don't just scale together)
// blended into a two-stop gradient, masked so only the denser regions
// show at all rather than tinting the whole sky uniformly. Reuses
// cube_face_uv so the cloud shapes aren't stretched near any view
// direction either, same reasoning as stars().
vec3 nebula(vec3 dir) {
	float face_seed;
	vec2 uv = cube_face_uv(dir, face_seed) * 1.6 + vec2(face_seed * 13.7, face_seed * 5.3);
	uv += TIME * nebula_drift_speed;
	float base = fbm(uv);
	float wisps = fbm(uv * 1.7 + 8.2);
	vec3 color = mix(vec3(0.05, 0.0, 0.09), vec3(0.28, 0.06, 0.4), base);
	color = mix(color, vec3(0.05, 0.08, 0.32), wisps * 0.7);
	float mask = smoothstep(0.32, 0.7, base) * smoothstep(0.2, 0.6, wisps);
	return color * mask * nebula_intensity;
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
// between latitude stripes for a gas-giant-ish look, `rim_color` adds a
// soft backlit-glow rim at the disc's edge (on top of, not instead of,
// the plain limb-darkening falloff that makes it read as a sphere
// rather than a flat painted circle), and `has_ring`/`ring_color` add a
// flattened elliptical ring (a fixed tilt, not physically orbiting)
// around it when set. The ring isn't occlusion-tested against the
// sphere itself (there's no "passes behind the planet" gap) -- an
// acceptable simplification for a background decoration glimpsed only
// at the map's clamped edge.
vec3 planet(vec3 dir, vec3 center, float radius, float rotate_speed, vec3 base_color, vec3 band_color, vec3 rim_color, bool has_ring, vec3 ring_color) {
	float d = distance(dir, center);
	vec3 arbitrary = abs(center.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent = normalize(cross(arbitrary, center));
	vec3 bitangent = cross(center, tangent);
	vec3 offset = dir - center * dot(dir, center);
	float local_u = dot(offset, tangent);
	float local_v = dot(offset, bitangent);

	vec3 color = vec3(0.0);
	if (d < radius) {
		float spin = TIME * rotate_speed;
		float band = sin(local_v * 26.0 + local_u * 4.0 + spin) * 0.5 + 0.5;
		vec3 surface = mix(base_color, band_color, band);
		float limb = smoothstep(radius, radius * 0.2, d);
		color = surface * limb;
		float edge_factor = clamp(d / radius, 0.0, 1.0);
		float rim = pow(edge_factor, 5.0) * limb;
		color += rim_color * rim * 1.6;
	}
	if (has_ring) {
		float ring_dist = length(vec2(local_u, local_v / 0.32));
		float ring_mask = smoothstep(radius * 1.3, radius * 1.38, ring_dist) - smoothstep(radius * 1.85, radius * 1.93, ring_dist);
		color += ring_color * ring_mask;
	}
	return color;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 color = void_color;
	color += nebula(dir);
	color += stars(dir);
	color += comet(dir);
	color += planet(dir, normalize(vec3(0.55, 0.35, -0.7)), 0.12, 0.15, vec3(0.55, 0.4, 0.25), vec3(0.8, 0.65, 0.4), vec3(0.9, 0.6, 0.9), true, vec3(0.7, 0.55, 0.75));
	color += planet(dir, normalize(vec3(-0.4, 0.6, 0.6)), 0.07, -0.25, vec3(0.3, 0.45, 0.6), vec3(0.55, 0.7, 0.8), vec3(0.6, 0.75, 1.0), false, vec3(0.0));
	COLOR = color;
}
