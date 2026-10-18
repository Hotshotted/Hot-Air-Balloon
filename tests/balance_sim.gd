extends SceneTree
## Balance autopilot:  godot --headless --path . --script res://tests/balance_sim.gd -- [flights=0,5,11] [runs=12]
## A look-ahead bot plays whole Flights (it rolls the real simulation forward under a few burner plans and
## picks the best survivor; it grabs coins and propane it passes), to show roughly how hard each Flight is and
## what the propane economy gives a careful player. Not part of CI.

var MainS: GDScript

func snapshot(m: Node) -> Dictionary:
	var b = m.balloon
	var l = m.lanes
	return {
		"fuel": m.fuel, "screen": m.screen, "lt": m.leg_time, "sim": m.sim_time, "clear_left": m.clear_left,
		"pos": b.position, "rise": b.rise, "vx": b.vx, "heat": b.heat, "sway": b.sway, "burning": b.burning, "ground": b.on_ground, "bt": b._t,
		"hx": l.hz_x.duplicate(), "hy": l.hz_y.duplicate(), "pkx": l.pk_x.duplicate(), "pky": l.pk_y.duplicate(), "pko": l.pk_on.duplicate(), "lt2": l._t,
		"score": m.score, "leg": m.leg, "fcoins": m.flight_coins, "picked": m.coins_picked,
		"cnx": l.cn_x.duplicate(), "cny": l.cn_y.duplicate(), "cno": l.cn_on.duplicate(),
	}

func restore(m: Node, s: Dictionary) -> void:
	var b = m.balloon
	var l = m.lanes
	m.fuel = s["fuel"]; m.screen = s["screen"]; m.leg_time = s["lt"]; m.sim_time = s["sim"]; m.clear_left = s["clear_left"]
	b.position = s["pos"]; b.rise = s["rise"]; b.vx = s["vx"]; b.heat = s["heat"]; b.sway = s["sway"]; b.burning = s["burning"]; b.on_ground = s["ground"]; b._t = s["bt"]
	l.hz_x = s["hx"].duplicate(); l.hz_y = s["hy"].duplicate(); l.pk_x = s["pkx"].duplicate(); l.pk_y = s["pky"].duplicate(); l.pk_on = s["pko"].duplicate(); l._t = s["lt2"]
	m.score = s["score"]; m.leg = s["leg"]; m.flight_coins = s["fcoins"]; m.coins_picked = s["picked"]
	l.cn_x = s["cnx"].duplicate(); l.cn_y = s["cny"].duplicate(); l.cn_on = s["cno"].duplicate()
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
		if m.screen == 2 or m.screen == 4:   # SCREEN_CLEAR / SCREEN_RESULT: the leg is won
			goal = true
			break
		if m.screen == 3:   # SCREEN_DEAD
			ok = false
			break
		alive_steps += 1
	var alt: float = m.balloon.position.y
	var gain: float = float(m.coins_picked - s["picked"]) * 300.0 + (m.fuel - s["fuel"]) * 6.0
	restore(m, s)
	return [ok, goal, alt, alive_steps, gain]

## Fly a whole Flight. Returns a result string; stats collects stars / fuel / coins.
func play(m: Node, fid: int, seed_i: int, stats: Dictionary) -> String:
	root.get_node("Save").reset_all()
	var plans := [0, 20, 45, 9999]
	var t := 0.0
	var tick := 0
	m.start_flight(fid)
	m.lanes.rng.seed = fid * 7919 + seed_i   # (layouts are fixed by the Flight; the seed only matters for sparks)
	var plan_left := 0
	while t < 400.0:
		if m.screen == 1 and tick % 6 == 0:
			var best_plan := 0
			var best_key := -1.0e9
			for p in plans:
				var r := rollout(m, p, 70)
				var key: float = (1.0e6 if r[0] else 0.0) + (1.0e5 if r[1] else 0.0) + float(r[3]) * 100.0 - float(r[2]) * 0.1 + float(r[4])
				if key > best_key:
					best_key = key
					best_plan = p
			plan_left = best_plan
		m.burn_override = 1 if plan_left > 0 else 0
		plan_left -= 1
		m.sim(1.0 / 60.0)
		t += 1.0 / 60.0
		tick += 1
		if m.screen == 4:
			stats["stars"] = stats.get("stars", 0) + m.last_stars
			stats["fuel"] = stats.get("fuel", 0.0) + m.fuel
			stats["picked"] = stats.get("picked", 0) + m.coins_picked
			stats["coins"] = stats.get("coins", 0) + m.flight_coins
			return "finished"
		if m.screen == 3:
			stats["leg_sum"] = stats.get("leg_sum", 0) + m.leg + 1
			return "failed leg %d: %s" % [m.leg + 1, "crash" if m.last_reason.begins_with("Crashed") else "propane"]
	return "timeout"

func _initialize() -> void:
	MainS = load("res://scripts/Main.gd")
	var flights: Array = [0, 5, 11]
	var runs := 8
	for a in OS.get_cmdline_user_args():
		if a.begins_with("flights="):
			flights = []
			for x in a.substr(8).split(","):
				flights.append(int(x))
		elif a.begins_with("runs="):
			runs = int(a.substr(5))
	root.get_node("Save").persist = false
	var m: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	DebugFlags.parse(["noprewarm"])
	await process_frame
	while m._warming:
		await process_frame
	m.set_process(false)
	for fid in flights:
		var res := {}
		var stats := {}
		for i in runs:
			var r := play(m, fid, i, stats)
			res[r] = res.get(r, 0) + 1
		var fin: int = res.get("finished", 0)
		print("flight %d: %s" % [fid + 1, str(res)])
		if fin > 0:
			print("   finished: avg stars %.2f, propane left %.0f, coins collected %.1f/15, coins earned %.0f" % [float(stats["stars"]) / fin, stats["fuel"] / fin, float(stats["picked"]) / fin, float(stats["coins"]) / fin])
	quit(0)
