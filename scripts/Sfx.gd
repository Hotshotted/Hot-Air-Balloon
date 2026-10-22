class_name Sfx
extends Node
## All sound is pre-rendered (assets/audio, made offline by tools/make_audio.gd from AudioSynth): soft, short, rounded. One-shots go
## through a small pool of players on the "SFX" bus (a free player is taken for each one, so a playing sound is never cut off).
## The LOOPS (the calm music, the burner roar, the wind, the storm rumble) are played by the web page itself on the web build
## (PWAudio in web/shell.html: native, gapless AudioBufferSource loops on the browser's audio thread, controlled from here with
## levels in dB); everywhere else (the editor, desktop, the tests) they are ordinary looping players.
## Nothing is created or generated during play; `plays` counts what was triggered (for the tests). `Sfx.instance` is the one live
## copy, so any script can call `Sfx.ui("tap")` without holding a reference.
## Background: `hold()` mutes everything (the page went to the background / the phone was locked) and nothing comes back until
## `release()` (the player tapped Resume).

const POOL := 8
const NAMES := ["press", "tap", "back", "toggle", "buy", "error", "whoosh", "unlock", "star", "slam", "coin", "pickup", "thunk", "deflate", "cheer", "creak", "thunder", "anchor", "vent", "warn"]
const AUDIO_DIR := "res://assets/audio/"            # one-shots
const LOOP_DIR := "res://assets/audio/loops/"       # loops (the web page fetches the same files from audio/)
const LOOPS := ["music", "roar", "wind", "rumble"]
const FADE_DB_PER_S := 60.0
const MENU_DB := -4.0          # the music layer, in the menus
const FLIGHT_DB := -7.0        # ... and while flying
const SFX_TRIM_DB := -14.0     # one-shots sit well under the music: gameplay sounds never peak above it

static var instance: Sfx

var enabled := true
var held := false              # audio is held (the page went to the background): everything is silent until release()
var web_loops := false         # the page plays the loops (web build)
var plays := {}                # sound name -> how many times it was triggered
var unlocked := false          # the first user gesture has happened (browsers keep audio suspended until then)
var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _players := {}             # loop name -> its looping player (not on the web)
var _db := {"music": -80.0, "roar": -80.0, "wind": -80.0, "rumble": -80.0}       # where each layer is now (a glide)
var _target := {"music": -80.0, "roar": -80.0, "wind": -80.0, "rumble": -80.0}   # ...and where it is going
var _sent := {}                # layer -> the level last sent to the page
var _rate := {"roar": 1.0, "wind": 1.0}
var _rate_sent := {"roar": 1.0, "wind": 1.0}
var _wind_pitch := 1.0
var _t_wind_pitch := 1.0
var _burner_pitch := 1.0
var _creak_cd := 0.0
var _rng := RandomNumberGenerator.new()
## What the loops are doing right now (for the tests): target levels in dB (-80 = silent).
var burner_target: float:
	get:
		return _target["roar"]
var wind_target: float:
	get:
		return _target["wind"]
var rumble_target: float:
	get:
		return _target["rumble"]
var music_mode_db: float:
	get:
		return _target["music"]

## Play a UI / one-shot sound from anywhere (silently nothing if the audio is not up).
static func ui(sound: String, pitch: float = 1.0) -> void:
	if instance != null:
		instance.play(sound, pitch)

func _ready() -> void:
	instance = self
	_rng.randomize()
	for n in NAMES:
		plays[n] = 0
	_ensure_buses()
	apply_volumes()
	if DebugFlags.sound_off():
		enabled = false
		return
	web_loops = OS.has_feature("web") and bool(JavaScriptBridge.eval("!!(window.PWAudio && window.PWAudio.enabled)"))
	for n in NAMES:
		_streams[n] = load(AUDIO_DIR + n + ".wav")
	for i in POOL:
		_pool.append(_player("SFX"))
	if not web_loops:
		for n in LOOPS:
			var p := _player("Music" if n == "music" else "SFX")
			p.stream = _loop(n)
			p.volume_db = -80.0
			_players[n] = p

## A pre-rendered loop, set to loop over its whole length.
static func _loop(name: String) -> AudioStreamWAV:
	var w: AudioStreamWAV = load(LOOP_DIR + name + ".wav")
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

## Put the saved slider values on the two buses (0 = muted); the one-shots carry their fixed trim under the music.
static func apply_volumes() -> void:
	_ensure_buses()
	var save: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Save")   # (looked up, so this script compiles without the autoload)
	for pair in [["SFX", save.sound_volume(), SFX_TRIM_DB], ["Music", save.music_volume(), 0.0]]:
		var idx := AudioServer.get_bus_index(pair[0])
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(pair[1], 0.0001)) + pair[2])
		AudioServer.set_bus_mute(idx, pair[1] <= 0.001)
	if instance != null:
		instance._sent.clear()   # (the page's levels carry the sliders too)

func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"   # (a missing bus must never be named: the web build aborts)
	add_child(p)
	return p

# ---------- Playing ----------

## A one-shot. Every play gets a hair of random pitch and level (the sounds stay in key).
func play(sound: String, pitch: float = 1.0) -> void:
	plays[sound] = int(plays.get(sound, 0)) + 1
	if not enabled or held or not _streams.has(sound):
		return
	var p := _pool[_next]
	for k in POOL:   # a free player first: taking over one that is still sounding would cut it off with a click
		var q := _pool[(_next + k) % POOL]
		if not q.playing:
			p = q
			_next = (_next + k) % POOL
			break
	_next = (_next + 1) % POOL
	p.stream = _streams[sound]
	p.pitch_scale = pitch * _rng.randf_range(0.99, 1.01)
	p.volume_db = _rng.randf_range(-0.5, 0.3)
	p.play()

func play_deflate() -> void:
	play("deflate")

## The first touch: browsers only let audio run after a gesture. Loops that were started while the page was still locked are restarted
## now, so they begin cleanly with the audio context running.
func unlock() -> void:
	if unlocked:
		return
	unlocked = true
	if not enabled:
		return
	for p in _players.values():
		if p.playing:
			p.stop()
			p.play()

## The page went to the background (or the phone was locked): hold everything silent. Nothing resumes until `release()`.
func hold() -> void:
	held = true
	AudioServer.set_bus_mute(0, true)
	if web_loops:
		JavaScriptBridge.eval("window.PWAudio && PWAudio.setHeld(true)")

## The player is back and tapped (Resume): sound may run again.
func release() -> void:
	held = false
	AudioServer.set_bus_mute(0, false)
	if web_loops:
		JavaScriptBridge.eval("window.PWAudio && PWAudio.setHeld(false); window.__pwRelease && window.__pwRelease()")

## The music: `mode` 0 off, 1 menu / title / map (calm), 2 flight (quieter). Every change is a glide (never a cut).
func set_music(mode: int) -> void:
	_target["music"] = [-80.0, MENU_DB, FLIGHT_DB][clampi(mode, 0, 2)]

## Every frame of a flight: `power` the burner output 0..1 (`sputter` < 1 while it lights), `wind` the layer's wind at the balloon
## (px/s, signed), `swing_v` how fast the basket swings, `storm` the storm / thunder is near. Everything glides (no clicks).
func fly(dt: float, power: float, sputter: float, wind: float, swing_v: float, storm: bool) -> void:
	var t_burner := lerpf(-60.0, -8.0, pow(clampf(power, 0.0, 1.0), 0.8)) if power > 0.03 else -80.0
	_target["roar"] = t_burner - (1.0 - sputter) * 18.0
	_burner_pitch = 0.82 + 0.34 * power
	var k := clampf(absf(wind) / 260.0, 0.0, 1.0)
	_target["wind"] = lerpf(-46.0, -16.0, pow(k, 0.7)) if k > 0.01 else -80.0
	_t_wind_pitch = 0.65 + 0.9 * k
	_target["rumble"] = -22.0 if storm else -80.0
	_creak_cd -= dt
	if absf(swing_v) > 1.6 and _creak_cd <= 0.0:
		_creak_cd = _rng.randf_range(0.7, 1.4)
		play("creak", _rng.randf_range(0.8, 1.25))

## Silence the flight loops (pause, menus, the failed screen): they fade out.
func quiet() -> void:
	_target["roar"] = -80.0
	_target["wind"] = -80.0
	_target["rumble"] = -80.0

func _process(delta: float) -> void:
	if not enabled:
		return
	_wind_pitch = move_toward(_wind_pitch, _t_wind_pitch, 1.2 * delta)
	_rate["roar"] = _burner_pitch
	_rate["wind"] = _wind_pitch
	var changed := {}
	for n in LOOPS:
		var speed := FADE_DB_PER_S if n == "music" else (140.0 if n == "roar" else 40.0)
		_db[n] = move_toward(_db[n], _target[n], speed * delta)
		var vol_db := _slider_db(n)
		if web_loops:
			var lvl: float = _db[n] + vol_db if _db[n] > -70.0 else -80.0
			if absf(lvl - float(_sent.get(n, 999.0))) > 0.4:
				_sent[n] = lvl
				changed[n] = snappedf(lvl, 0.1)
		else:
			var pl: AudioStreamPlayer = _players[n]
			pl.volume_db = _db[n] if n == "music" else _db[n] + vol_db
			if _db[n] > -75.0 and not pl.playing:
				pl.play()
			elif _db[n] <= -75.0 and pl.playing:
				pl.stop()
	if web_loops:
		if not changed.is_empty():
			var parts: PackedStringArray = []
			for n in changed:
				parts.append("%s: %s" % [n, str(changed[n])])
			JavaScriptBridge.eval("window.PWAudio.setMany({" + ", ".join(parts) + "})")
		for n in ["roar", "wind"]:
			if absf(float(_rate[n]) - float(_rate_sent[n])) > 0.01:
				_rate_sent[n] = _rate[n]
				JavaScriptBridge.eval("window.PWAudio.setRate('%s', %.3f)" % [n, _rate[n]])
	else:
		(_players["roar"] as AudioStreamPlayer).pitch_scale = _burner_pitch
		(_players["wind"] as AudioStreamPlayer).pitch_scale = _wind_pitch

## The saved slider of a layer in dB (the music slider for the music, the sound slider for the ambience); the buses carry their own
## on the desktop, the page's gains carry them on the web.
func _slider_db(n: String) -> float:
	if not web_loops:
		return 0.0
	var save: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Save")
	var v: float = save.music_volume() if n == "music" else save.sound_volume()
	return linear_to_db(maxf(v, 0.0001))
