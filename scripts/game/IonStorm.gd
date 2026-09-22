class_name IonStorm
extends Node2D
## Sable Verge's signature feature: two ion-storm arms, opposite each other,
## sweeping around the star like lighthouse beams. They blow in cycles:
## ACTIVE seconds of storm out of every CYCLE, with a WARN-second build-up
## (a faint outline) before each. Ships inside an active arm move at SLOW of
## their speed. Everything is driven by the match clock (Game.now()), so it
## stays in step across saves and for both players.

const SLOW := 0.4
const CYCLE := 100.0
const ACTIVE := 45.0
const WARN := 10.0
const PERIOD := 240.0
const HALF_WIDTH := 0.23
const REACH := 2200.0

var inner: float = 420.0
var phase: float = 0.0
var _was := ""

func _ready() -> void:
	add_to_group("storms")
	z_index = -1

func arm_angle(t: float) -> float:
	return phase + t * TAU / PERIOD

## "active", "warning" or "calm" at match time t.
func stage(t: float) -> String:
	# Matches open calm: first warning at 45 s, first storm at 55 s.
	var c := fposmod(t + ACTIVE, CYCLE)
	if c < ACTIVE:
		return "active"
	if c > CYCLE - WARN:
		return "warning"
	return "calm"

func contains(p: Vector2) -> bool:
	if stage(Game.now()) != "active":
		return false
	var v := p - global_position
	if v.length() < inner:
		return false
	var a := arm_angle(Game.now())
	return absf(angle_difference(v.angle(), a)) < HALF_WIDTH or absf(angle_difference(v.angle(), a + PI)) < HALF_WIDTH

func _process(_delta: float) -> void:
	var s := stage(Game.now())
	if s != _was and is_instance_valid(Game.instance):
		if s == "warning":
			Game.instance.message.emit("An ion storm is building. Ships caught in its arms will crawl.", Color("9ad8ff"))
		elif s == "active" and _was != "":
			Game.instance.message.emit("Ion storms are sweeping the system: ships inside move at 40% speed.", Color("9ad8ff"))
	_was = s
	queue_redraw()

func _draw() -> void:
	var s := stage(Game.now())
	if s == "calm":
		return
	var a := arm_angle(Game.now())
	var flicker := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.02)
	for arm in 2:
		var mid := a + PI * arm
		if s == "warning":
			# Forecast: dashed edges where the arm will blow.
			for side in [-1.0, 1.0]:
				var d := Vector2.from_angle(mid + side * HALF_WIDTH)
				for k in 24:
					var r0 := inner + (REACH - inner) * k / 24.0
					draw_line(d * r0, d * (r0 + 30.0), Color(0.6, 0.85, 1.0, 0.35), 2.0)
			continue
		# Active: translucent wedge plus streaks of lightning-blue static.
		var pts := PackedVector2Array()
		for k in 9:
			pts.append(Vector2.from_angle(mid - HALF_WIDTH + 2.0 * HALF_WIDTH * k / 8.0) * inner)
		for k in 9:
			pts.append(Vector2.from_angle(mid + HALF_WIDTH - 2.0 * HALF_WIDTH * k / 8.0) * REACH)
		draw_colored_polygon(pts, Color(0.45, 0.7, 1.0, 0.1 * flicker))
		var rng := RandomNumberGenerator.new()
		rng.seed = int(Game.now() * 8.0) + arm * 997
		for k in 70:
			var r := rng.randf_range(inner, REACH)
			var th := mid + rng.randf_range(-HALF_WIDTH, HALF_WIDTH)
			var p := Vector2.from_angle(th) * r
			var q := p + Vector2.from_angle(th + PI / 2.0) * rng.randf_range(8.0, 26.0)
			draw_line(p, q, Color(0.75, 0.9, 1.0, 0.45 * flicker), 2.0)
