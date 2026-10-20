class_name Sfx
extends Node
## The two balloon sounds, synthesised once at start-up (no asset files): a burner "whoomp" for a hop up and a soft
## vent hiss for a hop down. Two pooled players; nothing is allocated while playing.

const RATE := 22050
var _burner: AudioStreamPlayer
var _vent: AudioStreamPlayer
var plays := 0   # how many sounds were triggered (tests)

func _ready() -> void:
	_burner = _player(_make(0.5, 150.0, 0.9, true))
	_vent = _player(_make(0.3, 0.0, 0.6, false))

func _player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = Tuning.sfx_db
	add_child(p)
	return p

## Noise through a one-pole low-pass, shaped by an envelope; `rumble` > 0 adds a low sine that sinks (the burner's roar).
func _make(secs: float, rumble: float, gain: float, roar: bool) -> AudioStreamWAV:
	var n := int(secs * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var u := t / secs
		var env := (minf(u / 0.08, 1.0) * pow(1.0 - u, 1.6)) if roar else (minf(u / 0.03, 1.0) * pow(1.0 - u, 2.2))
		lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.35 if roar else 0.7)
		var v := lp * 1.6
		if rumble > 0.0:
			v += sin(TAU * rumble * (1.0 - 0.3 * u) * t) * 0.7
		var q := int(clampf(v * env * gain, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, q)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

func burner() -> void:
	plays += 1
	_burner.volume_db = Tuning.sfx_db
	_burner.play()

func vent() -> void:
	plays += 1
	_vent.volume_db = Tuning.sfx_db
	_vent.play()
