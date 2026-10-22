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
const NAMES := ["press", "tap", "back", "toggle", "buy", "error", "whoosh", "unlock", "star", "slam", "coin", "pickup", "thunk"]
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

## The music: `mode` 0 off, 1 menu / title / map (louder, calm), 2 flight (quieter). Every change is a glide (never a cut).
func set_music(mode: int) -> void:
	_music_target = [-80.0, MENU_DB, FLIGHT_DB][clampi(mode, 0, 2)]
	if enabled and _music_target > -70.0 and not _music.playing:
		_music.play()

var music_mode_db: float:
	get:
		return _music_target

func _process(delta: float) -> void:
	if not enabled:
		return
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
