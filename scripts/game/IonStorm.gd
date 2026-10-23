class_name IonStorm
extends Node2D
## Sable Verge's signature feature: ion storms - ragged, boiling clouds of
## charged gas that drift around the system, flickering with lightning.
## Ships inside one move at SLOW of their speed and see half as far (see
## Vision). Each storm's path and shape come from its seed and the match
## clock (Game.now()), so they stay in step across saves and for everyone.
##
## The outline is far more irregular than a spice nebula's: several noise
## octaves at a higher frequency push the edge in and out, and the shape
## itself churns slowly over time.

const SLOW := 0.4
## How far the edge wanders in and out, as a share of the storm's radius.
const WOBBLE := 0.5
## Drift: how far from the centre a storm's path reaches, and how slowly it
## travels (radians of its looping path per second).
const DRIFT_SPEED := 0.012

var radius: float = 280.0
var seed_value: int = 1
## Where on its looping path the storm starts.
var phase: float = 0.0
## This storm's drift speed and the two frequencies of its looping path
## (set per system seed; see SystemGen).
var drift_speed: float = DRIFT_SPEED
var loop: Array = []
## The storm's drift is a slow looping figure (two sine waves) that stays
## inside the round system.
var _reach: float = 900.0
var _f1 := 1.0
var _f2 := 1.3
var _noise: FastNoiseLite
var _gas: ColorRect
const EDGE_SAMPLES := 64

## Pixel-art storm gas. The edge comes in each frame from _edge (so it is
## exactly what contains() tests); inside, churning steel-blue billows with
## a bright crackling rim, and lightning flashes light the whole cloud.
const GAS_SHADER := """
shader_type canvas_item;
uniform float edges[64];
uniform float half_size = 400.0;
uniform float flash = 0.0;
uniform float t = 0.0;
uniform float seed = 0.0;
const float PX = 4.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int k = 0; k < 4; k++) { v += a * vnoise(p); p *= 2.1; a *= 0.5; } return v; }
void fragment() {
	// Snap to the pixel grid so the gas matches the pixel art.
	vec2 cell = floor(UV * half_size * 2.0 / PX);
	vec2 local = (cell + 0.5) * PX - half_size;
	float d = length(local);
	float ang = mod(atan(local.y, local.x), 6.2831853);
	float fi = ang / 6.2831853 * 64.0;
	int i0 = int(floor(fi)) % 64;
	int i1 = (i0 + 1) % 64;
	float edge = mix(edges[i0], edges[i1], fract(fi));
	float r = d / edge;
	float dith = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	if (r > 1.0) {
		// A thin fading haze just outside, so the edge isn't cut out.
		float haze = max(1.0 - (d - edge) / 14.0, 0.0);
		COLOR = vec4(0.45, 0.6, 1.0, haze * (0.12 + flash * 0.05));
	} else {
		vec2 q = local / 90.0 + vec2(t * 0.05, -t * 0.03);
		float billow = fbm(q + fbm(q * 1.7 - t * 0.04));
		vec3 deep = vec3(0.10, 0.13, 0.30);
		vec3 steel = vec3(0.30, 0.42, 0.72);
		vec3 pale = vec3(0.62, 0.76, 1.0);
		vec3 col = mix(deep, steel, smoothstep(0.3, 0.7, billow + dith * 0.08));
		col = mix(col, pale, smoothstep(0.62, 0.85, billow) * 0.6);
		float a = 0.32 + billow * 0.2;
		// Rim: bright and crackling right at the edge.
		float rim = smoothstep(0.86, 1.0, r + dith * 0.03);
		col = mix(col, vec3(0.7, 0.85, 1.0), rim * 0.8);
		a = mix(a, 0.6, rim);
		// Lightning lights the cloud from inside.
		col = mix(col, vec3(0.88, 0.94, 1.0), flash * (0.55 - r * 0.25));
		a += flash * 0.25;
		COLOR = vec4(col, clamp(a, 0.0, 0.85));
	}
}
"""

static var _gas_shader: Shader

func _ready() -> void:
	add_to_group("storms")
	z_index = -1
	setup()
	_gas = ColorRect.new()
	var half := radius * (1.0 + WOBBLE) + 24.0
	_gas.position = -Vector2.ONE * half
	_gas.size = Vector2.ONE * half * 2.0
	_gas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gas.show_behind_parent = true
	var mat := ShaderMaterial.new()
	# One shared Shader: compiled once, not once per storm.
	if _gas_shader == null:
		_gas_shader = Shader.new()
		_gas_shader.code = GAS_SHADER
	mat.shader = _gas_shader
	mat.set_shader_parameter("half_size", half)
	mat.set_shader_parameter("seed", float(seed_value % 997))
	_gas.material = mat
	add_child(_gas)
	_process(0.0)

## Path and shape from the seed (also used by the lobby's map preview,
## which never adds the storm to a scene).
func setup() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_f1 = rng.randf_range(0.8, 1.2)
	_f2 = rng.randf_range(1.3, 1.9)
	if loop.size() == 2:
		_f1 = float(loop[0])
		_f2 = float(loop[1])
	_reach = Game.MAP_RADIUS - radius * (1.0 + WOBBLE) - 60.0
	_noise = FastNoiseLite.new()
	_noise.seed = seed_value * 13 + 1
	_noise.frequency = 2.2   # higher than a nebula: a far more ragged edge
	_noise.fractal_octaves = 6
	_noise.fractal_gain = 0.6

## Starts the storm as far from every starting base as its path allows (it
## then roams freely): tries points along its loop and keeps the one whose
## nearest base is furthest away.
func start_clear_of(bases: Array) -> void:
	var base_phase := phase
	var best := phase
	var best_d := -1.0
	for i in 96:
		phase = base_phase + TAU * i / 96.0
		var c := center_at(0.0)
		var near := INF
		for b in bases:
			near = minf(near, c.distance_to(b))
		if near > best_d:
			best_d = near
			best = phase
	phase = best

## Where the storm's centre is at match time t.
func center_at(t: float) -> Vector2:
	var u := phase + t * drift_speed
	return Vector2(sin(u * _f1), sin(u * _f2 + phase * 0.7)).limit_length(1.0) * _reach

## The edge's distance from the centre at angle a and time t: a ragged,
## slowly churning outline.
func _edge(a: float, t: float) -> float:
	var n := _noise.get_noise_3d(cos(a) * 1.3, sin(a) * 1.3, t * 0.015) / 1.6
	return radius * (1.0 + clampf(n, -1.0, 1.0) * WOBBLE)

func contains(p: Vector2) -> bool:
	var t := Game.now()
	var v := p - center_at(t)
	if v.length() > radius * (1.0 + WOBBLE):
		return false
	return v.length() <= _edge(v.angle(), t)

## The outline as points round the centre (local to the centre), for
## drawing here, on the minimap and in the lobby.
func outline(t: float, scale_k: float = 1.0, steps: int = 64) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		var a := TAU * i / steps
		pts.append(Vector2.from_angle(a) * _edge(a, t) * scale_k)
	return pts

func _process(_delta: float) -> void:
	position = center_at(Game.now())
	queue_redraw()

## Lightning: every so often a jagged bolt forks across the cloud and the
## gas lights up for a moment. Strikes come from the clock, not randf, so
## every player sees the same storm.
const FLASH_TIME := 0.18

func _draw() -> void:
	var t := Game.now()
	var slot := int(t * 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + slot
	# About one strike every 1.5 s, at a random moment within its half-second.
	var strike := rng.randf() < 0.35
	var strike_at := slot / 2.0 + rng.randf() * 0.5
	var flash := 0.0
	if strike and t >= strike_at and t < strike_at + FLASH_TIME:
		flash = 1.0 - (t - strike_at) / FLASH_TIME
	# The gas itself is painted by GAS_SHADER from this frame's edge.
	if _gas:
		var edges := PackedFloat32Array()
		for i in EDGE_SAMPLES:
			edges.append(_edge(TAU * i / EDGE_SAMPLES, t))
		var m := _gas.material as ShaderMaterial
		m.set_shader_parameter("edges", edges)
		m.set_shader_parameter("flash", flash)
		m.set_shader_parameter("t", t)
	# Static: short sparks that crackle through the cloud.
	var srng := RandomNumberGenerator.new()
	srng.seed = seed_value * 31 + int(t * 6.0)
	for k in 26:
		var a := srng.randf() * TAU
		var p := Vector2.from_angle(a) * _edge(a, t) * srng.randf_range(0.1, 0.9)
		var q := p + Vector2.from_angle(srng.randf() * TAU) * srng.randf_range(6.0, 18.0)
		draw_line(p, q, Color(0.75, 0.88, 1.0, 0.4), 1.5)
	if flash > 0.0:
		# The bolt: a jagged line across the cloud with a fork or two.
		var a0 := rng.randf() * TAU
		var from := Vector2.from_angle(a0) * _edge(a0, t) * 0.85
		var to := Vector2.from_angle(a0 + PI + rng.randf_range(-0.8, 0.8)) * radius * 0.7
		_bolt(from, to, rng, Color(0.92, 0.97, 1.0, flash), 3.0)
		for f in rng.randi_range(1, 2):
			var mid := from.lerp(to, rng.randf_range(0.3, 0.7))
			_bolt(mid, mid + Vector2.from_angle(rng.randf() * TAU) * radius * 0.35, rng, Color(0.8, 0.9, 1.0, flash * 0.8), 2.0)

func _bolt(a: Vector2, b: Vector2, rng: RandomNumberGenerator, col: Color, w: float) -> void:
	var pts := PackedVector2Array([a])
	var n := 9
	var side := (b - a).orthogonal().normalized()
	for i in range(1, n):
		pts.append(a.lerp(b, float(i) / n) + side * rng.randf_range(-22.0, 22.0))
	pts.append(b)
	draw_polyline(pts, Color(col.r * 0.6, col.g * 0.8, 1.0, col.a * 0.35), w * 3.0, true)
	draw_polyline(pts, col, w, true)

## The storm on a map (minimap, lobby): its outline filled, where it is now.
func draw_on_map(canvas: CanvasItem, to_map: Callable, k: float, t: float) -> void:
	var c: Vector2 = to_map.call(center_at(t))
	var pts := outline(t, k, 40)
	for i in pts.size():
		pts[i] += c
	canvas.draw_colored_polygon(pts, Color(0.5, 0.7, 1.0, 0.28))
