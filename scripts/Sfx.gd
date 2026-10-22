class_name Sfx
extends Node
## All sound is generated in code at start-up (no audio files): the interface sounds (a soft press, a bright tap going forward,
## a falling pair going back, a toggle tick, a purchase ping, a muted error buzz, a swish for sliding screens, an unlock
## fanfare, a rising star arpeggio and a slam for stars landing), the balloon's sounds and a calm music loop with
## crossfades. One-shots go through a small pool of players on the "SFX" bus, loops on their own players ("SFX" / "Music").
## Nothing is created or generated during play; `plays` counts what was triggered (for the tests). `Sfx.instance` is the one
## live copy, so any script can call `Sfx.ui("tap")` without holding a reference.

const POOL := 8
const NAMES := ["press", "tap", "back", "toggle", "buy", "error", "whoosh", "unlock", "star", "slam", "coin", "pickup", "thunk", "deflate", "cheer", "creak", "thunder", "anchor", "vent", "warn"]
const AUDIO_DIR := "res://assets/audio/"   # pre-rendered by tools/make_audio.gd (AudioSynth)
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
	for n in NAMES:
		_streams[n] = load(AUDIO_DIR + n + ".wav")
	for i in POOL:
		_pool.append(_player("SFX"))
	_music = _player("Music")
	_music.stream = _loop("music")
	_music.volume_db = -80.0
	_burner = _player("SFX")
	_burner.stream = _loop("roar")
	_burner.volume_db = -80.0
	_wind = _player("SFX")
	_wind.stream = _loop("wind")
	_wind.volume_db = -80.0
	_rumble = _player("SFX")
	_rumble.stream = _loop("rumble")
	_rumble.volume_db = -80.0

## A pre-rendered loop, set to loop over its whole length (on the web the browser's own sample playback loops it gaplessly).
static func _loop(name: String) -> AudioStreamWAV:
	var w: AudioStreamWAV = load(AUDIO_DIR + name + ".wav")
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = w.data.size() / (2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1)
	return w

func _exit_tree() -> void:
	if instance == self:
		instance = null

## The buses come from default_bus_layout.tres (a static layout); this only adds them if that file did not load.
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

## First tap / key of the session (the browser keeps audio locked until a gesture): start whatever music is wanted.
var unlocked := false
func unlock() -> void:
	if unlocked:
		return
	unlocked = true
	if enabled and _music_target > -70.0 and not _music.playing:
		_music.play()

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

