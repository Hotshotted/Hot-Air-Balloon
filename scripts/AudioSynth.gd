class_name AudioSynth
extends RefCounted
## All of the game's sound, synthesised in code. This runs OFFLINE only (tools/make_audio.gd renders every sound to a WAV under
## assets/audio/, which is what the game loads: nothing is synthesised on a player's device). Soft, short and rounded, with a calm
## music loop (see docs/style.md: Audio).

const RATE := 44100            # effects (44.1 kHz, like Pattern-Control)
const LOOP_RATE := 44100       # loops
const FS_LOOP := 8000.0 / 44100.0   # the noise filters were tuned at 8 kHz: their coefficients scale with the rate
const FS_FX := 11025.0 / 44100.0
const BEAT := 0.6              # music: seconds per beat, 8 beats per loop

## Every one-shot, name -> stream.

static func effects() -> Dictionary:
	var _streams := {}
	_streams["press"] = _wav(_seq([[420.0, 0.03, 0.25]], RATE, 0.9), RATE)
	_streams["tap"] = _wav(_seq([[740.0, 0.05, 0.35]], RATE), RATE)
	_streams["back"] = _wav(_seq([[560.0, 0.04, 0.3], [415.0, 0.07, 0.3]], RATE), RATE)
	_streams["toggle"] = _wav(_seq([[920.0, 0.03, 0.35]], RATE, 0.8), RATE)
	_streams["buy"] = _wav(_seq([[784.0, 0.06, 0.4], [1047.0, 0.06, 0.4], [1568.0, 0.2, 0.4]], RATE, 0.5, false, true), RATE)
	_streams["error"] = _wav(_seq([[196.0, 0.08, 0.3], [147.0, 0.14, 0.3]], RATE, 0.7, true), RATE)
	_streams["whoosh"] = _wav(_whoosh(0.22, RATE), RATE)
	_streams["unlock"] = _wav(_seq([[523.0, 0.1, 0.4], [659.0, 0.1, 0.4], [784.0, 0.1, 0.4], [1047.0, 0.45, 0.45]], RATE, 0.6, false, true), RATE)
	_streams["star"] = _wav(_seq([[988.0, 0.07, 0.4], [1319.0, 0.07, 0.4], [1760.0, 0.2, 0.4]], RATE, 0.5, false, true), RATE)
	_streams["slam"] = _wav(_mix(_sweep(180.0, 55.0, 0.22, 0.9, RATE), _seq([[1175.0, 0.3, 0.3]], RATE, 0.3, false, true)), RATE)
	_streams["coin"] = _wav(_seq([[1319.0, 0.06, 0.4], [1760.0, 0.16, 0.4]], RATE, 0.5), RATE)
	_streams["pickup"] = _wav(_seq([[660.0, 0.05, 0.4], [990.0, 0.05, 0.4], [1320.0, 0.14, 0.4]], RATE, 0.5, false, true), RATE)
	_streams["deflate"] = _wav(_mix(_sweep(520.0, 90.0, 0.9, 0.5, RATE), _sweep(300.0, 60.0, 1.1, 0.4, RATE)), RATE)
	_streams["cheer"] = _wav(_seq([[660.0, 0.08, 0.4], [880.0, 0.08, 0.4], [1100.0, 0.18, 0.4]], RATE, 0.5, false, true), RATE)
	_streams["creak"] = _wav(_creak(0.28, RATE), RATE)
	_streams["thunder"] = _wav(_thunder(1.6, RATE), RATE)
	_streams["anchor"] = _wav(_mix(_seq([[196.0, 0.12, 0.45], [147.0, 0.2, 0.4]], RATE, 0.4, true), _sweep(90.0, 50.0, 0.25, 0.6, RATE)), RATE)
	_streams["vent"] = _wav(_whoosh(0.5, RATE), RATE)
	_streams["warn"] = _wav(_seq([[880.0, 0.06, 0.3], [660.0, 0.08, 0.3]], RATE, 0.7, true), RATE)
	_streams["thunk"] = _wav(_sweep(200.0, 60.0, 0.2, 0.7, RATE), RATE)
	return _streams

## Notes [[hz, seconds, volume], ...] one after another with a short decay each. `square` = hollow tone, `bell` = a slow
## decay with an overtone.
static func _seq(notes: Array, rate: int, decay: float = 0.6, square: bool = false, bell: bool = false) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for n in notes:
		var count := int(float(n[1]) * rate)
		var base := out.size()
		out.resize(base + count)
		var att := maxi(int(0.004 * rate), 1)                      # every note starts and ends at zero: no clicks between notes
		var rel := maxi(int(minf(0.03, float(n[1]) * 0.4) * rate), 1)
		for i in count:
			var t := float(i) / rate
			var env := (1.0 - float(i) / count) if not bell else exp(-t * 6.0)
			env = lerpf(1.0, env, decay) * minf(float(i) / att, 1.0) * minf(float(count - 1 - i) / rel, 1.0)
			var ph := TAU * float(n[0]) * t
			var v := sin(ph)
			if square:   # a hollow tone (odd harmonics), smooth: no hard steps
				v = (v + 0.35 * sin(3.0 * ph)) * 0.75
			if bell:
				v += 0.4 * sin(ph * 2.76)
			out[base + i] = v * float(n[2]) * env
	return out

static func _sweep(f0: float, f1: float, secs: float, vol: float, rate: int) -> PackedFloat32Array:
	var count := int(secs * rate)
	var out := PackedFloat32Array()
	out.resize(count)
	var ph := 0.0
	for i in count:
		var k := float(i) / count
		ph += TAU * lerpf(f0, f1, k) / rate
		out[i] = sin(ph) * vol * (1.0 - k) * minf(float(i) / 30.0, 1.0)
	return out

## Filtered noise whose brightness rises and falls: a swish.
static func _whoosh(secs: float, rate: int) -> PackedFloat32Array:
	var count := int(secs * rate)
	var out := PackedFloat32Array()
	out.resize(count)
	var seed_v := 777
	var lp := 0.0
	for i in count:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		var k := float(i) / count
		lp += (noise - lp) * lerpf(0.05, 0.5, sin(PI * k)) * (11025.0 / float(rate))
		out[i] = lp * sin(PI * k) * 0.5
	return out

## Noise through a one-pole low-pass (`a` = how open: small = dull), made to loop seamlessly by crossfading its ends.
static func _noise_loop(secs: float, a: float, hum: float, hum_hz: float) -> PackedFloat32Array:
	var count := int(secs * LOOP_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var seed_v := 4242
	var lp := 0.0
	for i in count:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		lp += (noise - lp) * a * FS_LOOP
		var t := float(i) / LOOP_RATE
		out[i] = lp + hum * sin(TAU * hum_hz * t)
	# seamless: the last `fade` samples are crossfaded into the first ones, and the loop starts after them
	var fade := int(count * 0.15)
	for i in fade:
		var k := float(i) / fade
		out[count - fade + i] = lerpf(out[count - fade + i], out[i], k * k * (3.0 - 2.0 * k))
	out = out.slice(fade)
	var peak := 0.001
	for v in out:
		peak = maxf(peak, absf(v))
	for i in out.size():
		out[i] = out[i] / peak * 0.7
	return out

static func _roar_loop() -> PackedFloat32Array:
	var o := _noise_loop(1.5, 0.22, 0.25, 60.0)
	var n := float(o.size())
	for i in o.size():   # a flutter in the flame (whole cycles over the loop: seamless)
		o[i] *= 0.82 + 0.18 * sin(TAU * 6.0 * float(i) / n)
	return o

static func _wind_loop() -> PackedFloat32Array:
	var o := _noise_loop(3.0, 0.1, 0.0, 1.0)
	var n := float(o.size())
	for i in o.size():   # slow gusting (two whole cycles)
		o[i] *= 0.75 + 0.25 * sin(TAU * 2.0 * float(i) / n)
	return o

static func _rumble_loop() -> PackedFloat32Array:
	return _noise_loop(2.0, 0.04, 0.3, 40.0)

## A wooden creak: a falling, wobbling tone with a rasp.
static func _creak(secs: float, rate: int) -> PackedFloat32Array:
	var count := int(secs * rate)
	var out := PackedFloat32Array()
	out.resize(count)
	var ph := 0.0
	var seed_v := 99
	for i in count:
		var k := float(i) / count
		ph += TAU * (210.0 - 70.0 * k + 18.0 * sin(k * 60.0)) / rate
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var rasp := (float(seed_v) / 1073741823.5 - 1.0) * 0.25
		out[i] = ((sin(ph) + 0.5 * sin(2.0 * ph) + 0.3 * sin(3.0 * ph)) * 0.3 + rasp * 0.5) * sin(PI * k) * 0.55
	return out

## Thunder: a crack, then a long low roll.
static func _thunder(secs: float, rate: int) -> PackedFloat32Array:
	var count := int(secs * rate)
	var out := PackedFloat32Array()
	out.resize(count)
	var seed_v := 31337
	var lp := 0.0
	for i in count:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		var k := float(i) / count
		lp += (noise - lp) * lerpf(0.5, 0.05, minf(k * 3.0, 1.0)) * (11025.0 / float(rate))
		out[i] = lp * (exp(-k * 3.2) + 0.5 * exp(-pow((k - 0.18) * 8.0, 2.0))) * 0.9
	return out

static func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(a.size(), b.size()))
	for i in out.size():
		out[i] = (a[i] if i < a.size() else 0.0) + (b[i] if i < b.size() else 0.0)
	return out

## A calm 8-beat loop (C major: C Am F G, two beats each): a soft pad, a slow bass and a few gentle bell notes. Every tone is tuned to
## a whole number of cycles over the loop and the chords crossfade (raised cosine), so the loop has no seam and nothing clicks.
static func music_loop() -> AudioStreamWAV:
	var chords := [[261.6, 329.6, 392.0], [220.0, 261.6, 329.6], [174.6, 220.0, 261.6], [196.0, 246.9, 293.7]]
	var secs := BEAT * 8.0
	var count := int(secs * LOOP_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t := float(i) / LOOP_RATE
		var beat := t / BEAT
		var pos := fposmod(beat / 2.0, 4.0)
		var v := 0.0
		for c in 4:
			var d := pos - (float(c) + 0.5)
			d = fposmod(d + 2.0, 4.0) - 2.0
			if absf(d) >= 1.0:
				continue
			var g := 0.5 + 0.5 * cos(PI * d)
			var ch: Array = chords[c]
			var pad := 0.0
			for f in ch:
				pad += 0.16 * sin(TAU * _q(f * 0.5, secs) * t)
			pad *= 0.8 + 0.2 * sin(TAU * t / secs)
			var bt := fposmod(beat, 2.0)
			var bass := 0.26 * sin(TAU * _q(ch[0] * 0.25, secs) * t) * (0.7 + 0.3 * cos(PI * bt))
			v += (pad + bass) * g
		var half := int(floor(beat * 2.0))
		var step := fposmod(beat * 2.0, 1.0)
		if half % 2 == 0:
			var chn: Array = chords[(half / 4) % 4]
			var note := _q(float(chn[(half / 2) % 3]) * 2.0, secs)
			v += 0.12 * sin(TAU * note * t) * exp(-step * 4.0) * smoothstep(0.0, 0.03, step) * (1.0 - smoothstep(0.9, 1.0, step))
		out[i] = v * 0.5
	return _wav(out, LOOP_RATE, true)

## A frequency tuned to a whole number of cycles over `secs` (so a loop of that length is seamless).
static func _q(f: float, secs: float) -> float:
	return roundf(f * secs) / secs

static func _wav(samples: PackedFloat32Array, rate: int, loop: bool = false) -> AudioStreamWAV:
	if not loop:   # a short fade in and a longer fade out on every one-shot: it can never start or stop with a click
		var fin := int(0.003 * rate)
		var fout := int(0.025 * rate)
		for i in mini(fin, samples.size()):
			samples[i] *= float(i) / fin
		for i in mini(fout, samples.size()):
			samples[samples.size() - 1 - i] *= float(i) / fout
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

## The loops, name -> stream (seamless: the ends are crossfaded).
static func loops() -> Dictionary:
	return {
		"music": music_loop(),
		"roar": _wav(_roar_loop(), LOOP_RATE, true),
		"wind": _wav(_wind_loop(), LOOP_RATE, true),
		"rumble": _wav(_rumble_loop(), LOOP_RATE, true),
	}
