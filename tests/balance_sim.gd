extends SceneTree
## Balance autopilot:  godot --headless --path . --script res://tests/balance_sim.gd -- [levels=1,3,5] [runs=12]
## A look-ahead bot plays whole levels (it rolls the real simulation forward under a few burner plans and
## picks the best survivor), to show roughly how hard each level is for a careful player. Not part of CI.

var MainS: GDScript

func snapshot(m: Node) -> Dictionary:
	var b = m.balloon
	var l = m.lanes
	return {
		"fuel": m.fuel, "screen": m.screen, "lt": m.level_time, "sim": m.sim_time, "clear_left": m.clear_left,
		"pos": b.position, "rise": b.rise, "vx": b.vx, "heat": b.heat, "sway": b.sway, "burning": b.burning, "ground": b.on_ground, "bt": b._t,
		"hx": l.hz_x.duplicate(), "hy": l.hz_y.duplicate(), "pkx": l.pk_x.duplicate(), "pky": l.pk_y.duplicate(), "pko": l.pk_on.duplicate(), "lt2": l._t,
		"score": m.score, "level": m.level,
	}

func restore(m: Node, s: Dictionary) -> void:
	var b = m.balloon
	var l = m.lanes
	m.fuel = s["fuel"]; m.screen = s["screen"]; m.level_time = s["lt"]; m.sim_time = s["sim"]; m.clear_left = s["clear_left"]
	b.position = s["pos"]; b.rise = s["rise"]; b.vx = s["vx"]; b.heat = s["heat"]; b.sway = s["sway"]; b.burning = s["burning"]; b.on_ground = s["ground"]; b._t = s["bt"]
	l.hz_x = s["hx"].duplicate(); l.hz_y = s["hy"].duplicate(); l.pk_x = s["pkx"].duplicate(); l.pk_y = s["pky"].duplicate(); l.pk_on = s["pko"].duplicate(); l._t = s["lt2"]
	m.score = s["score"]; m.level = s["level"]
	b.visible = true

## Roll `steps` ahead holding for `hold_steps`, then released. Returns [survived, goal, altitude, steps_survived].
func rollout(m: Node, hold_steps: int, steps: int) -> Array:
	var s := snapshot(m)
	var alive_steps := 0
	var goal := false
	var ok := true
	for i in steps:
		m.burn_override = 1 if i < hold_steps else 0
		m.sim(1.0 / 60.0)
		if m.screen == 2:   # SCREEN_CLEAR
			goal = true
			break
		if m.screen == 3:   # SCREEN_DEAD
			ok = false
			break
		alive_steps += 1
	var alt: float = m.balloon.position.y
	restore(m, s)
	return [ok, goal, alt, alive_steps]

func play(m: Node, lv: int, seed_i: int) -> String:
	DebugFlags.parse(["level=%d" % lv])
	m.lanes.rng.seed = lv * 7919 + seed_i
	m.restart()
	var plans := [0, 12, 24, 40, 70, 9999]
	var t := 0.0
	var tick := 0
	while t < 150.0:
		if tick % 4 == 0:
			var best_plan := 0
			var best_key := -1.0e9
			for p in plans:
				var r := rollout(m, p, 80)
				var key: float = (1.0e6 if r[0] else 0.0) + (1.0e5 if r[1] else 0.0) + float(r[3]) * 100.0 - float(r[2]) * 0.1
				if key > best_key:
					best_key = key
					best_plan = p
			m.balloon.set_meta("plan", best_plan)
			m.set_meta("plan_left", best_plan)
		var left: int = m.get_meta("plan_left")
		m.burn_override = 1 if left > 0 else 0
		m.set_meta("plan_left", left - 1)
		m.sim(1.0 / 60.0)
		t += 1.0 / 60.0
		tick += 1
		if m.screen == 2:
			return "clear %.1f" % m.level_time if false else "clear"
		if m.screen == 3:
			return m.last_reason
	return "timeout"

func _initialize() -> void:
	MainS = load("res://scripts/Main.gd")
	var levels: Array = [1, 3, 5, 8]
	var runs := 12
	for a in OS.get_cmdline_user_args():
		if a.begins_with("levels="):
			levels = []
			for x in a.substr(7).split(","):
				levels.append(int(x))
		elif a.begins_with("runs="):
			runs = int(a.substr(5))
	var m: Node = load("res://scenes/main.tscn").instantiate()
	m.persist = false
	root.add_child(m)
	DebugFlags.parse(["noprewarm"])
	await process_frame
	while m._warming:
		await process_frame
	m.set_process(false)
	for lv in levels:
		var res := {}
		var times: Array[float] = []
		for i in runs:
			var r := play(m, lv, i)
			var key := r
			if r.begins_with("Crashed"):
				key = "crash"
			elif r.begins_with("Out of"):
				key = "propane"
			res[key] = res.get(key, 0) + 1
			if r == "clear":
				times.append(m.level_time)
		var avg := 0.0
		for x in times:
			avg += x
		print("level %d: %s  avg clear time %.1f s" % [lv, str(res), avg / maxf(times.size(), 1)])
	quit(0)
