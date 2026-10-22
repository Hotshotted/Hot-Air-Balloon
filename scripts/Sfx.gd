class_name Sfx
extends Node
## All sound is generated in code at start-up (no audio files): the interface sounds (a soft press, a bright tap going forward,
## a falling pair going back, a toggle tick, a purchase ping, a muted error buzz, a swish for sliding screens, an unlock
## fanfare, a rising star arpeggio and a slam for stars landing), the balloon's sounds and a calm music loop with
## crossfades. One-shots go through a small pool of players on the "SFX" bus, loops on their own players ("SFX" / "Music").
## Nothing is created or generated during play; `plays` counts what was triggered (for the tests). `Sfx.instance` is the one
## live copy, so any script can call `Sfx.ui("tap")` without holding a reference.

const RATE := 11025            # effects
const LOOP_RATE := 8000        # loops (lo-fi on purpose)
const POOL := 8
const NAMES := ["press", "tap", "back", "toggle", "buy", "error", "whoosh", "unlock", "star", "slam", "coin", "pickup", "thunk", "deflate", "cheer", "creak", "thunder", "anchor", "vent", "warn"]
const BEAT := 0.6              # music: seconds per beat, 8 beats per loop
const FADE_DB_PER_S := 60.0
const MENU_DB := -17.0
const FLIGHT_DB := -23.0

static var instance: Sfx

var enabled := true
var plays := {}                # sound name -> how many times it was triggered
var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _music_db := -80.0
var _music_target := -80.0
# The flight's living sounds: a burner roar that follows the flame, wind that changes with the layer's speed, a storm rumble
var _burner: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _rumble: AudioStreamPlayer
var _burner_db := -80.0
var _wind_db := -80.0
var _rumble_db := -80.0
var _t_burner := -80.0
var _t_wind := -80.0
var _t_rumble := -80.0
var _wind_pitch := 1.0
var _t_wind_pitch := 1.0
var _burner_pitch := 1.0
var _creak_cd := 0.0
## What the loops are doing right now (for the tests): target levels in dB (-80 = silent).
var burner_target: float:
	get:
		return _t_burner
var wind_target: float:
	get:
		return _t_wind
var rumble_target: float:
	get:
		return _t_rumble

## Play a UI / one-shot sound from anywhere (silently nothing if the audio is not up).
static func ui(sound: String, pitch: float = 1.0) -> void:
	if instance != null:
		instance.play(sound, pitch)

func _ready() -> void:
	instance = self
	for n in NAMES:
		plays[n] = 0
	_ensure_buses()
	apply_volumes()
	if DebugFlags.sound_off():
		enabled = false
		return
	_build_effects()
	for i in POOL:
		_pool.append(_player("SFX"))
	_music = _player("Music")
	_music.stream = _music_loop()
	_music.volume_db = -80.0
	_burner = _player("SFX")
	_burner.stream = _wav(_roar_loop(), LOOP_RATE, true)
	_burner.volume_db = -80.0
	_wind = _player("SFX")
	_wind.stream = _wav(_wind_loop(), LOOP_RATE, true)
	_wind.volume_db = -80.0
	_rumble = _player("SFX")
	_rumble.stream = _wav(_rumble_loop(), LOOP_RATE, true)
	_rumble.volume_db = -80.0

func _exit_tree() -> void:
	if instance == self:
		instance = null

static func _ensure_buses() -> void:
	for name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, name)
			AudioServer.set_bus_send(idx, "Master")

## Put the saved slider values on the two buses (0 = muted).
static func apply_volumes() -> void:
	_ensure_buses()
	var save: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Save")   # (looked up, so this script compiles without the autoload)
	for pair in [["SFX", save.sound_volume()], ["Music", save.music_volume()]]:
		var idx := AudioServer.get_bus_index(pair[0])
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(pair[1], 0.0001)))
		AudioServer.set_bus_mute(idx, pair[1] <= 0.001)

func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p

# ---------- Playing ----------

func play(sound: String, pitch: float = 1.0) -> void:
	plays[sound] = int(plays.get(sound, 0)) + 1
	if not enabled or not _streams.has(sound):
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = _streams[sound]
	p.pitch_scale = pitch
	p.play()

func play_deflate() -> void:
	play("deflate")

## The music: `mode` 0 off, 1 menu / title / map (louder, calm), 2 flight (quieter). Every change is a glide (never a cut).
func set_music(mode: int) -> void:
	_music_target = [-80.0, MENU_DB, FLIGHT_DB][clampi(mode, 0, 2)]
	if enabled and _music_target > -70.0 and not _music.playing:
		_music.play()

var music_mode_db: float:
	get:
		return _music_target

## Every frame of a flight: `power` the burner output 0..1 (`sputter` < 1 while it lights), `wind` the layer's wind at the balloon
## (px/s, signed), `swing_v` how fast the basket swings, `storm` the storm / thunder is near. Everything glides (no clicks).
func fly(dt: float, power: float, sputter: float, wind: float, swing_v: float, storm: bool) -> void:
	_t_burner = lerpf(-60.0, -8.0, pow(clampf(power, 0.0, 1.0), 0.8)) if power > 0.03 else -80.0
	_t_burner -= (1.0 - sputter) * 18.0
	_burner_pitch = 0.82 + 0.34 * power
	var k := clampf(absf(wind) / 260.0, 0.0, 1.0)
	_t_wind = lerpf(-46.0, -16.0, pow(k, 0.7)) if k > 0.01 else -80.0
	_t_wind_pitch = 0.65 + 0.9 * k
	_t_rumble = -22.0 if storm else -80.0
	_creak_cd -= dt
	if absf(swing_v) > 1.6 and _creak_cd <= 0.0:
		_creak_cd = randf_range(0.7, 1.4)
		play("creak", randf_range(0.8, 1.25))

## Silence the flight loops (pause, menus, the failed screen): they fade out.
func quiet() -> void:
	_t_burner = -80.0
	_t_wind = -80.0
	_t_rumble = -80.0

func _process(delta: float) -> void:
	if not enabled:
		return
	_burner_db = move_toward(_burner_db, _t_burner, 140.0 * delta)
	_wind_db = move_toward(_wind_db, _t_wind, 40.0 * delta)
	_rumble_db = move_toward(_rumble_db, _t_rumble, 40.0 * delta)
	_wind_pitch = move_toward(_wind_pitch, _t_wind_pitch, 1.2 * delta)
	for pair in [[_burner, _burner_db], [_wind, _wind_db], [_rumble, _rumble_db]]:
		var pl: AudioStreamPlayer = pair[0]
		pl.volume_db = pair[1]
		if pair[1] > -75.0 and not pl.playing:
			pl.play()
		elif pair[1] <= -75.0 and pl.playing:
			pl.stop()
	_burner.pitch_scale = _burner_pitch
	_wind.pitch_scale = _wind_pitch
	_music_db = move_toward(_music_db, _music_target, FADE_DB_PER_S * delta)
	_music.volume_db = _music_db
	if _music.playing and _music_db <= -75.0 and _music_target <= -70.0:
		_music.stop()

# ---------- Synthesis ----------

func _build_effects() -> void:
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

## Notes [[hz, seconds, volume], ...] one after another with a short decay each. `square` = hollow tone, `bell` = a slow
## decay with an overtone.
func _seq(notes: Array, rate: int, decay: float = 0.6, square: bool = false, bell: bool = false) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for n in notes:
		var count := int(float(n[1]) * rate)
		var base := out.size()
		out.resize(base + count)
		for i in count:
			var t := float(i) / rate
			var env := (1.0 - float(i) / count) if not bell else exp(-t * 6.0)
			env = lerpf(1.0, env, decay) * minf(float(i) / 40.0, 1.0)
			var ph := TAU * float(n[0]) * t
			var v := signf(sin(ph)) * 0.6 if square else sin(ph)
			if bell:
				v += 0.4 * sin(ph * 2.76)
			out[base + i] = v * float(n[2]) * env
	return out

func _sweep(f0: float, f1: float, secs: float, vol: float, rate: int) -> PackedFloat32Array:
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
func _whoosh(secs: float, rate: int) -> PackedFloat32Array:
	var count := int(secs * rate)
	var out := PackedFloat32Array()
	out.resize(count)
	var seed_v := 777
	var lp := 0.0
	for i in count:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		var k := float(i) / count
		lp += (noise - lp) * lerpf(0.05, 0.5, sin(PI * k))
		out[i] = lp * sin(PI * k) * 0.5
	return out

## Noise through a one-pole low-pass (`a` = how open: small = dull), made to loop seamlessly by crossfading its ends.
func _noise_loop(secs: float, a: float, hum: float, hum_hz: float) -> PackedFloat32Array:
	var count := int(secs * LOOP_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var seed_v := 4242
	var lp := 0.0
	for i in count:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		lp += (noise - lp) * a
		var t := float(i) / LOOP_RATE
		out[i] = lp + hum * sin(TAU * hum_hz * t)
	var fade := int(count * 0.12)
	for i in fade:   # blend the tail into the head so the loop has no seam
		var k := float(i) / fade
		out[count - fade + i] = lerpf(out[count - fade + i], out[i], k)
	var peak := 0.001
	for v in out:
		peak = maxf(peak, absf(v))
	for i in count:
		out[i] = out[i] / peak * 0.7
	return out

func _roar_loop() -> PackedFloat32Array:
	var o := _noise_loop(1.5, 0.22, 0.25, 62.5)
	for i in o.size():   # a flutter in the flame
		o[i] *= 0.82 + 0.18 * sin(TAU * 7.0 * float(i) / LOOP_RATE)
	return o

func _wind_loop() -> PackedFloat32Array:
	var o := _noise_loop(3.0, 0.1, 0.0, 1.0)
	for i in o.size():   # slow gusting
		o[i] *= 0.75 + 0.25 * sin(TAU * 0.667 * float(i) / LOOP_RATE)
	return o

func _rumble_loop() -> PackedFloat32Array:
	return _noise_loop(2.0, 0.04, 0.3, 40.0)

## A wooden creak: a falling, wobbling tone with a rasp.
func _creak(secs: float, rate: int) -> PackedFloat32Array:
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
		out[i] = (signf(sin(ph)) * 0.35 + rasp) * sin(PI * k) * 0.55
	return out

## Thunder: a crack, then a long low roll.
func _thunder(secs: float, rate: int) -> PackedFloat32Array:
	var count := int(secs * rate)
	var out := PackedFloat32Array()
	out.resize(count)
	var seed_v := 31337
	var lp := 0.0
	for i in count:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		var k := float(i) / count
		lp += (noise - lp) * lerpf(0.5, 0.05, minf(k * 3.0, 1.0))
		out[i] = lp * (exp(-k * 3.2) + 0.5 * exp(-pow((k - 0.18) * 8.0, 2.0))) * 0.9
	return out

func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(a.size(), b.size()))
	for i in out.size():
		out[i] = (a[i] if i < a.size() else 0.0) + (b[i] if i < b.size() else 0.0)
	return out

## A calm 8-beat loop (C major: C Am F G, two beats each): a soft pad, a slow bass and a few gentle bell notes.
func _music_loop() -> AudioStreamWAV:
	var chords := [[261.6, 329.6, 392.0], [220.0, 261.6, 329.6], [174.6, 220.0, 261.6], [196.0, 246.9, 293.7]]
	var count := int(BEAT * 8.0 * LOOP_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t := float(i) / LOOP_RATE
		var beat := t / BEAT
		var ch: Array = chords[int(beat / 2.0) % 4]
		var v := 0.0
		for f in ch:
			v += 0.16 * sin(TAU * f * t * 0.5) * (0.8 + 0.2 * sin(TAU * 0.25 * t))
		var bt := fmod(beat, 2.0)
		v += 0.26 * sin(TAU * ch[0] * 0.25 * t) * (1.0 - 0.4 * bt)
		var step := fmod(beat * 2.0, 1.0)
		if int(beat * 2.0) % 2 == 0:
			var note: float = ch[int(beat * 2.0 / 2.0) % 3] * 2.0
			v += 0.12 * sin(TAU * note * t) * exp(-step * 4.0)
		out[i] = v * 0.5
	return _wav(out, LOOP_RATE, true)

func _wav(samples: PackedFloat32Array, rate: int, loop: bool = false) -> AudioStreamWAV:
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
