extends SceneTree
## Bakes Star Lords' procedural audio into res://assets/audio/*.wav:
## 8-bit style SFX (sfx_*.wav) and ambient music loops (music_*.wav).
## Run headless from the project root:
##   Godot --headless --path . --script res://tools/gen_audio.gd
## The game only loads the WAVs; tweak the recipes here and re-run.

const OUT := "res://assets/audio/"
const RATE := 22050
const CHORD_SECONDS := 6.0

## Per track: chords in semitones from A2 (110 Hz), arpeggio notes per
## chord (0 = none), and shimmer brightness.
const TRACKS := {
	"title": {"chords": [[0, 7, 15], [-4, 3, 12], [-7, 0, 8], [-2, 5, 14]], "arp": 0, "bright": 0.6},
	"lobby": {"chords": [[0, 7, 12], [5, 12, 16], [3, 10, 15], [-2, 5, 10]], "arp": 4, "bright": 0.8},
	"game": {"chords": [[0, 3, 7], [-4, 0, 3], [-2, 2, 5], [-5, -2, 2]], "arp": 8, "bright": 0.45},
}

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var sfx := {
		"laser": _sweep(0.09, 1800.0, 500.0, 0.35, true),
		"torpedo": _noise_sweep(0.35, 0.8, 0.15, 0.4),
		"shield": _sweep(0.07, 2600.0, 3400.0, 0.2, false),
		"boom": _explosion(0.45, 0.55),
		"boom_big": _explosion(1.1, 0.8),
		"build": _arp([523.0, 659.0, 784.0], 0.07, 0.25),
		"claim": _arp([392.0, 523.0, 659.0, 1047.0], 0.09, 0.25),
		"alert": _arp([330.0, 247.0, 330.0, 247.0], 0.1, 0.25),
		"click": _sweep(0.03, 900.0, 700.0, 0.15, true),
		"deny": _sweep(0.15, 180.0, 120.0, 0.25, true),
		# Alerts, escalating with severity.
		# Minor: short and mild.
		"alert_ships": _seq([[740, 0.07, 0.14, "tri"], [740, 0.07, 0.14, "tri"]], 0.06),
		"alert_resource": _seq([[196, 0.12, 0.17, "sq"], [185, 0.16, 0.17, "sq"]], 0.06),
		# Serious: sirens and klaxons.
		"alert_planet": _join([_sweep(0.35, 900.0, 380.0, 0.24, true), _sweep(0.35, 900.0, 380.0, 0.24, true)]),
		"alert_starbase": _seq([[220, 0.22, 0.3, "sq"], [165, 0.22, 0.3, "sq"], [220, 0.22, 0.3, "sq"], [165, 0.3, 0.3, "sq"]], 0.03),
		"alert_energy": _sweep(0.7, 700.0, 70.0, 0.3, false),
		"alert_starved": _seq([[110, 0.9, 0.32, "trem"]], 0.0),
		# Critical: long, low, dissonant, with a deep thump.
		"alert_planet_lost": _doom(2.2, [98.0, 138.6, 196.0]),
		"alert_starbase_lost": _doom(2.6, [82.4, 116.5, 164.8]),
		# Notifications: quiet, soft, pleasant (major intervals, light echo).
		"note_ship": _echo(_seq([[587, 0.06, 0.07, "tri"], [880, 0.1, 0.07, "tri"]], 0.01)),
		"note_tech": _echo(_seq([[660, 0.08, 0.065, "tri"], [880, 0.08, 0.065, "tri"], [1320, 0.18, 0.065, "tri"]], 0.01)),
		"note_building": _echo(_seq([[392, 0.07, 0.08, "tri"], [523, 0.12, 0.08, "tri"]], 0.02)),
		"note_colony": _echo(_seq([[392, 0.09, 0.07, "tri"], [494, 0.09, 0.07, "tri"], [587, 0.09, 0.07, "tri"], [784, 0.22, 0.07, "tri"]], 0.0)),
		"note_starbase": _echo(_seq([[523, 0.1, 0.075, "tri"], [659, 0.1, 0.075, "tri"], [784, 0.1, 0.075, "tri"], [1047, 0.26, 0.075, "tri"]], 0.02)),
		"note_save": _echo(_seq([[1047, 0.07, 0.06, "tri"]], 0.0)),
		# Match won: a bright brass fanfare over a timpani roll.
		"victory": _fanfare(),
		# Match lost: a slow, falling minor lament.
		"defeat": _lament(),
	}
	# GEN_ONLY=a,b bakes just those SFX (and no music), leaving the rest as is.
	var only := OS.get_environment("GEN_ONLY").split(",", false)
	for name in sfx:
		if only.is_empty() or name in only:
			_save("sfx_" + name, sfx[name])
	for name in ([] if not only.is_empty() else TRACKS.keys()):
		var t0 := Time.get_ticks_msec()
		_save("music_" + name, _music(TRACKS[name]))
		print("music_%s: %d ms" % [name, Time.get_ticks_msec() - t0])
	print("Star Lords audio generated.")
	quit()

func _save(name: String, s: PackedFloat32Array) -> void:
	var peak := 0.0
	for v in s:
		peak = maxf(peak, absf(v))
	var gain := 0.9 / peak if peak > 0.9 else 1.0
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i] * gain, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = bytes
	w.save_to_wav(OUT + name + ".wav")
	print("%-16s %.2fs peak %.2f gain %.2f" % [name, float(s.size()) / RATE, peak, gain])

## Square (or triangle) wave with an exponential pitch sweep and linear fade.
func _sweep(dur: float, f0: float, f1: float, amp: float, square: bool) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := f0 * pow(f1 / f0, t)
		phase = fmod(phase + f / RATE, 1.0)
		var v := (1.0 if phase < 0.5 else -1.0) if square else (4.0 * absf(phase - 0.5) - 1.0)
		s[i] = v * amp * (1.0 - t)
	return s

## Filtered noise whose cutoff sweeps from c0 to c1 (0..1), with a swell.
func _noise_sweep(dur: float, c0: float, c1: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / n
		var k := lerpf(c0, c1, t) * 0.5
		y += (randf_range(-1.0, 1.0) - y) * k
		s[i] = y * amp * sin(t * PI) * 2.0
	return s

## Crunchy explosion: low-passed noise with a sub thump and fast decay,
## bit-crushed for the 8-bit feel.
func _explosion(dur: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	var hold := 0.0
	for i in n:
		var t := float(i) / n
		if i % 4 == 0:
			hold = randf_range(-1.0, 1.0)
		var k := lerpf(0.5, 0.04, t)
		y += (hold - y) * k
		var thump := sin(TAU * lerpf(90.0, 35.0, t) * i / RATE) * (1.0 - t) * 0.6
		var v := (y * 1.6 + thump) * pow(1.0 - t, 2.0) * amp
		s[i] = round(v * 12.0) / 12.0
	return s

## Short square-wave arpeggio for UI/event cues.
func _arp(freqs: Array, note_dur: float, amp: float) -> PackedFloat32Array:
	var per := int(note_dur * RATE)
	var s := PackedFloat32Array()
	s.resize(per * freqs.size())
	for ni in freqs.size():
		var f: float = freqs[ni]
		for i in per:
			var phase := fmod(f * i / RATE, 1.0)
			var env := 1.0 - float(i) / per * 0.7
			s[ni * per + i] = (0.5 if phase < 0.5 else -0.5) * amp * env
	return s

static func _hz(semi: float) -> float:
	return 110.0 * pow(2.0, semi / 12.0)

func _music(spec: Dictionary) -> PackedFloat32Array:
	var chords: Array = spec["chords"]
	var per := int(CHORD_SECONDS * RATE)
	var n := per * chords.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var bright: float = spec["bright"]
	var arp_n: int = spec["arp"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(spec)

	for ci in chords.size():
		var chord: Array = chords[ci]
		var next: Array = chords[(ci + 1) % chords.size()]
		var base := ci * per
		for i in per:
			var t := float(i) / RATE
			var u := float(i) / per
			# Crossfade envelope so chords overlap smoothly across the loop.
			var env := clampf(u * 4.0, 0.0, 1.0) * clampf((1.0 - u) * 4.0, 0.0, 1.0)
			var v := 0.0
			for semi in chord:
				var f := _hz(semi + 12.0)
				# Two slightly detuned partials plus a soft octave shimmer.
				v += sin(TAU * f * t) + sin(TAU * f * 1.004 * t) + bright * 0.3 * sin(TAU * f * 2.0 * t + sin(t * 0.7))
			v *= 0.05 * (0.55 + 0.45 * env)
			# Sub bass on the root, gliding into the next chord's root.
			var bass_semi := lerpf(chord[0], next[0], smoothstep(0.85, 1.0, u)) - 12.0
			v += sin(TAU * _hz(bass_semi) * t) * 0.12 * env
			out[base + i] += v

		# Sparse arpeggio: soft triangle blips on chord tones.
		if arp_n > 0:
			var step := per / arp_n
			for k in arp_n:
				if rng.randf() < 0.3:
					continue
				var semi: float = chord[rng.randi_range(0, chord.size() - 1)] + 24.0
				var f := _hz(semi)
				var len := int(0.35 * RATE)
				for i in len:
					var idx := base + k * step + i
					if idx >= n:
						break
					var ph := fmod(f * i / RATE, 1.0)
					var tri := 4.0 * absf(ph - 0.5) - 1.0
					out[idx] += tri * 0.05 * exp(-float(i) / RATE * 7.0)

	# Cheap echo for space.
	var d := int(0.37 * RATE)
	for i in range(d, n):
		out[i] += out[i - d] * 0.35

	return out

## Note sequence: each note is [freq, seconds, amp, wave] where wave is
## "sq" (square), "tri" (triangle) or "trem" (triangle with tremolo).
## Short fade in/out per note to avoid clicks; `gap` seconds of silence
## between notes.
func _seq(notes: Array, gap: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for n in notes:
		var f: float = n[0]
		var count := int(float(n[1]) * RATE)
		var amp: float = n[2]
		var wave: String = n[3]
		for i in count:
			var ph := fmod(f * i / RATE, 1.0)
			var v := (1.0 if ph < 0.5 else -1.0) if wave == "sq" else 4.0 * absf(ph - 0.5) - 1.0
			if wave == "trem":
				v *= 0.6 + 0.4 * sin(TAU * 7.0 * i / RATE)
			var env := minf(1.0, float(i) / (0.005 * RATE)) * minf(1.0, float(count - i) / (0.03 * RATE))
			out.append(v * amp * env)
		for i in int(gap * RATE):
			out.append(0.0)
	return out

func _join(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p)
	return out

## Adds a soft 120 ms echo tail.
func _echo(s: PackedFloat32Array) -> PackedFloat32Array:
	var d := int(0.12 * RATE)
	var out := s.duplicate()
	for i in d * 2:
		out.append(0.0)
	for i in range(d, out.size()):
		out[i] += out[i - d] * 0.35
	return out

## Worst-case alarm: a detuned, dissonant low chord that slowly sags in
## pitch, over a sub-bass impact, fading out over `dur` seconds.
func _doom(dur: float, freqs: Array) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phases := []
	for f in freqs:
		phases.append(0.0)
		phases.append(0.0)
	for i in n:
		var t := float(i) / n
		var bend := 1.0 - 0.18 * t
		var v := 0.0
		for j in freqs.size():
			for k in 2:
				var idx := j * 2 + k
				var f: float = freqs[j] * bend * (1.0 + 0.006 * k)
				phases[idx] = fmod(phases[idx] + f / RATE, 1.0)
				# Saw-ish tone for grit.
				v += (2.0 * phases[idx] - 1.0) * 0.5
		v /= freqs.size() * 2.0
		var thump := sin(TAU * lerpf(70.0, 30.0, minf(t * 4.0, 1.0)) * i / RATE) * exp(-t * 9.0) * 1.2
		var env := minf(1.0, t * 40.0) * pow(1.0 - t, 1.3)
		out[i] = (v * 0.9 + thump) * 0.45 * env
	return out

## Victory fanfare: "ta-ta-ta TAAA" pickups, then a rising major arpeggio
## into a long, swelling C major chord, in a brassy tone (a few detuned
## harmonics with vibrato), over a timpani roll and a final boom, with a
## hall-like echo.
func _fanfare() -> PackedFloat32Array:
	var dur := 3.6
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	# [start s, length s, freqs...]
	var notes := [
		[0.00, 0.12, [392.0]], [0.15, 0.12, [392.0]], [0.30, 0.12, [392.0]],
		[0.45, 0.55, [523.3, 659.3]],
		[1.05, 0.14, [523.3]], [1.20, 0.14, [659.3]], [1.35, 0.14, [784.0]],
		[1.50, 2.10, [523.3, 659.3, 784.0, 1046.5]],
	]
	for nt in notes:
		var s0 := int(float(nt[0]) * RATE)
		var len := int(float(nt[1]) * RATE)
		for f in nt[2]:
			for i in len:
				if s0 + i >= n:
					break
				var t := float(i) / RATE
				var vib := 1.0 + 0.004 * sin(TAU * 5.5 * t) * minf(t * 3.0, 1.0)
				var v := 0.0
				for h in [[1.0, 1.0], [2.0, 0.5], [3.0, 0.3], [4.0, 0.15]]:
					v += sin(TAU * f * h[0] * vib * t) * h[1]
				var attack := minf(1.0, t / 0.02)
				var release := minf(1.0, float(len - i) / (0.06 * RATE))
				var swell := 1.0 + 0.4 * minf(t / 1.2, 1.0) if len > RATE else 1.0
				out[s0 + i] += v * 0.12 * attack * release * swell
	# Timpani: soft roll under the pickups, a hit on each chord, a big finish.
	for hit in [[0.0, 0.25], [0.15, 0.25], [0.3, 0.25], [0.45, 0.7], [1.5, 1.0], [3.0, 0.5]]:
		var s0 := int(float(hit[0]) * RATE)
		for i in int(0.8 * RATE):
			if s0 + i >= n:
				break
			var t := float(i) / RATE
			out[s0 + i] += sin(TAU * lerpf(110.0, 65.0, minf(t * 6.0, 1.0)) * t) * exp(-t * 5.0) * 0.35 * float(hit[1])
	# Hall echo.
	var d := int(0.18 * RATE)
	for i in range(d, n):
		out[i] += out[i - d] * 0.3
	# Final fade.
	for i in int(0.5 * RATE):
		out[n - 1 - i] *= float(i) / (0.5 * RATE)
	return out

## Defeat: a slow brass lament falling through C minor (G, E-flat, D, C)
## into a dark, low C minor chord that sags and fades, with muffled
## timpani and a long, distant echo.
func _lament() -> PackedFloat32Array:
	var dur := 4.4
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var notes := [
		[0.00, 0.60, [392.0, 196.0]], [0.65, 0.60, [311.1, 155.6]],
		[1.30, 0.45, [293.7, 146.8]], [1.80, 2.60, [261.6, 130.8, 155.6, 196.0]],
	]
	for nt in notes:
		var s0 := int(float(nt[0]) * RATE)
		var len := int(float(nt[1]) * RATE)
		for f in nt[2]:
			for i in len:
				if s0 + i >= n:
					break
				var t := float(i) / RATE
				# The last chord slowly sags in pitch.
				var sag := 1.0 - 0.03 * minf(t / 2.5, 1.0) if len > RATE else 1.0
				var vib := 1.0 + 0.003 * sin(TAU * 4.0 * t) * minf(t * 2.0, 1.0)
				var v := 0.0
				for h in [[1.0, 1.0], [2.0, 0.35], [3.0, 0.12]]:
					v += sin(TAU * f * h[0] * vib * sag * t) * h[1]
				var attack := minf(1.0, t / 0.08)
				var release := minf(1.0, float(len - i) / (0.25 * RATE))
				out[s0 + i] += v * 0.11 * attack * release
	for hit in [[0.0, 0.6], [1.8, 1.0]]:
		var s0 := int(float(hit[0]) * RATE)
		for i in int(1.2 * RATE):
			if s0 + i >= n:
				break
			var t := float(i) / RATE
			out[s0 + i] += sin(TAU * lerpf(70.0, 45.0, minf(t * 3.0, 1.0)) * t) * exp(-t * 3.0) * 0.3 * float(hit[1])
	var d := int(0.3 * RATE)
	for i in range(d, n):
		out[i] += out[i - d] * 0.3
	for i in int(1.0 * RATE):
		out[n - 1 - i] *= float(i) / RATE
	return out
