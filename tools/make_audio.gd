extends SceneTree
## Renders every sound to assets/audio/*.wav (the game loads these; nothing is synthesised at run time):
##   godot --headless --path . --script res://tools/make_audio.gd
## then `godot --headless --import` to import them. Re-run after changing scripts/AudioSynth.gd.

func _initialize() -> void:
	var out := "res://assets/audio/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var Synth = load("res://scripts/AudioSynth.gd")
	var n := 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out + "loops/"))
	for pack in [Synth.effects(), Synth.loops()]:
		for name in pack:
			var w: AudioStreamWAV = pack[name]
			var sub := "loops/" if pack.has("music") else ""   # the loops are played by the web page itself (see web/shell.html)
			var err := w.save_to_wav(out + sub + name + ".wav")
			if err != OK:
				printerr("could not write ", name)
			n += 1
	print("rendered %d sounds" % n)
	quit()
