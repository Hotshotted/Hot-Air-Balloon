extends SceneTree
## Headless smoke test:  godot --headless --path . --script res://tests/smoke_test.gd
## Exits with code 1 if anything below fails (CI runs this before exporting).
##   1. ?debug flags parse
##   2. boot: the splash pre-warm draws every shape, lasts long enough, then cleans up; menu is up
##   3. balloon: buoyancy lag (the burner spools up, climb speed follows late), slow sink on release,
##      tethered on the ground, drifts with the wind of its layer (with a lag), screen edges wrap / block
##   4. hazards: touching one ends the attempt, god mode ignores it, gaps are left alone
##   5. propane: drains only while burning, an empty tank kills the burner and a landing ends the run,
##      pickups refill (capped) with a pooled burst
##   6. levels: reaching the top scores level points + speed bonus and starts a harder level
##   7. fairness of generated levels (hundreds of layouts): clear start / goal layers, gaps wider than the
##      balloon, layers / winds / density within limits and growing with the level
##   8. a crash ends the run; a tap restarts it IN PLACE (three runs in a row), creating no new nodes or resources
##   9. frame time: clamp, stall dropping, resume skipping, background suspension
##  10. ?tune panel: opens over the paused game, sliders edit Tuning live, Copy and Reset work, closing resumes,
##      a tap on the TUNE button is not a game tap, nothing is allocated; absent without ?tune

var failures: Array[String] = []
var tn: Node
# Loaded at run time (after the autoloads exist): naming these classes in this file would compile them too early.
var MainS: GDScript
var LanesS: GDScript
var BalloonS: GDScript
var TuneS: GDScript

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures.append(what)

func real_wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		await process_frame

func count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += count_nodes(ch)
	return c

func snap() -> Dictionary:
	return {
		"nodes": count_nodes(root),
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
	}

func same(a: Dictionary, b: Dictionary) -> bool:
	return a["nodes"] == b["nodes"] and a["node_count"] == b["node_count"] and a["resources"] == b["resources"]

func make_main(persist: bool = false) -> Node:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	m.persist = persist
	root.add_child(m)
	return m

func step(m: Node, secs: float, hold: int) -> void:
	m.burn_override = hold
	var n := int(round(secs * 60.0))
	for i in n:
		m.sim(1.0 / 60.0)

## No hazards or pickups anywhere (so a test of the balloon alone can't be disturbed).
func clear_sky(m: Node) -> void:
	for i in LanesS.MAX_LANES:
		m.lanes.lane_count[i] = 0
		m.lanes.lane_kind[i] = -1
		m.lanes.pk_on[i] = 0

func tap(m: Node, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	m._input(ev)

func _initialize() -> void:
	tn = root.get_node("Tuning")
	MainS = load("res://scripts/Main.gd")
	LanesS = load("res://scripts/Lanes.gd")
	BalloonS = load("res://scripts/Balloon.gd")
	TuneS = load("res://scripts/TunePanel.gd")
	await _run()
	if failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		print("SMOKE TEST FAILED (%d): %s" % [failures.size(), "; ".join(failures)])
		quit(1)

func _run() -> void:
	# ---- 1. debug flags ----
	print("1. debug flags")
	DebugFlags.parse(["perf", "tune", "level=4", "god", "v=abc123", "bogus"])
	check(DebugFlags.perf and DebugFlags.tune and DebugFlags.god and DebugFlags.start_level == 4, "flags parse")
	check(DebugFlags.summary().contains("?bogus") and not DebugFlags.summary().contains("?v"), "typos shown, v ignored")
	DebugFlags.parse(["level=500"])
	check(DebugFlags.start_level == 99, "level clamps")
	DebugFlags.parse([])
	check(DebugFlags.summary() == "" and DebugFlags.start_level == 1, "no flags -> empty summary")

	# ---- 2. boot + pre-warm ----
	print("2. boot and pre-warm")
	var t0 := Time.get_ticks_msec()
	var m := make_main()
	await process_frame
	check(m._warming and m.hud.splash.visible, "splash up while warming")
	check(m.lanes.showcase and m.lanes.n_lanes == LanesS.MAX_LANES, "showcase level fills every layer")
	var kinds := {}
	for i in m.lanes.n_lanes:
		if m.lanes.lane_kind[i] >= 0:
			kinds[m.lanes.lane_kind[i]] = true
	check(kinds.size() == 4, "showcase draws all four hazard kinds")
	var guard := 0
	while m._warming and guard < 2000:
		await process_frame
		guard += 1
	var warm_s := (Time.get_ticks_msec() - t0) / 1000.0
	check(not m._warming, "pre-warm finishes")
	check(warm_s >= tn.prewarm_min_seconds, "pre-warm lasts at least prewarm_min_seconds (%.1f s)" % warm_s)
	check(not m.hud.splash.visible and m.hud.title.visible and m.screen == MainS.SCREEN_MENU, "menu after the splash")
	check(not m.lanes.showcase and m.lanes.n_lanes == 5, "real level 1 after warm-up (5 layers)")
	check(m.balloon.heat == 0.0, "balloon cold again")
	var fx_live := 0
	for f in LanesS.FX_MAX:
		if m.lanes.fx_life[f] > 0.0:
			fx_live += 1
	check(fx_live == 0, "pre-warm sparks cleared")
	m.set_process(false)

	# ---- 3. balloon ----
	print("3. balloon: buoyancy, sink, ground, wind, edges")
	m.restart()
	clear_sky(m)
	var b = m.balloon
	check(b.on_ground and is_equal_approx(b.position.y, b.floor_y()), "starts resting on the ground")
	check(is_equal_approx(b.position.x, LanesS.W * 0.5), "...in the middle")
	step(m, 0.15, 1)
	var early: float = b.rise
	check(b.burning and b.heat > 0.0 and b.heat < 0.5, "burner spools up (heat %.2f after 0.15 s)" % b.heat)
	check(early < tn.climb_speed * 0.25, "buoyancy lag: climb is slow at first (%.0f px/s)" % early)
	var y_a: float = b.position.y
	step(m, 3.0, 1)
	check(b.position.y < y_a - 200.0, "holding rises")
	check(b.rise > tn.climb_speed * 0.9, "...up to near climb_speed (%.0f)" % b.rise)
	var y_peak: float = b.position.y
	step(m, 0.3, 0)
	check(b.rise > 0.0 and b.position.y < y_peak, "released: keeps rising a moment (lag)")
	step(m, 4.0, 0)
	check(b.rise < 0.0 and absf(b.rise + tn.sink_speed) < 12.0, "...then settles into a slow sink (%.0f px/s)" % b.rise)
	var y_s: float = b.position.y
	step(m, 1.0, 0)
	check(absf((b.position.y - y_s) - tn.sink_speed) < 15.0, "sink distance matches sink_speed")
	step(m, 30.0, 0)
	check(b.on_ground and is_equal_approx(b.position.y, b.floor_y()), "sinks back to the ground and stops there")
	check(absf(b.vx) < 1.0, "tethered on the ground: no drift")
	# Wind: hold the balloon at a layer's height.
	var lanes = m.lanes
	m.restart()
	clear_sky(m)
	b = m.balloon
	lanes.lane_wind[2] = 150.0
	lanes.lane_wind[3] = -200.0
	var cy2: float = LanesS.BAND_BOTTOM - 2.5 * lanes.lane_h
	var x0: float = b.position.x
	b.position.y = cy2
	b.on_ground = false
	m.burn_override = 0
	for i in 15:
		b.step(1.0 / 60.0, false, true, lanes.wind_at(cy2))
		b.position.y = cy2
	check(b.vx > 0.0 and b.vx < 150.0 * 0.5, "wind pickup lags (vx %.0f after 0.25 s)" % b.vx)
	for i in 180:
		b.step(1.0 / 60.0, false, true, lanes.wind_at(cy2))
		b.position.y = cy2
	check(b.vx > 150.0 * 0.9 and b.position.x > x0 + 200.0, "drifts with a layer's wind (vx %.0f)" % b.vx)
	var cy3: float = LanesS.BAND_BOTTOM - 3.5 * lanes.lane_h
	b.position.y = cy3
	check(lanes.lane_of(cy3) == 3 and lanes.wind_at(cy3) < 0.0, "layer lookup by height")
	for i in 240:
		b.step(1.0 / 60.0, false, true, lanes.wind_at(cy3))
		b.position.y = cy3
	check(b.vx < -200.0 * 0.9, "a layer blowing the other way reverses the drift (vx %.0f)" % b.vx)
	# Edges
	var half: float = BalloonS.WIDTH * 0.5 * b.s()
	tn.edge_wrap = true
	b.position.x = -half + 1.0
	b.vx = -150.0
	b.step(1.0 / 30.0, false, true, -150.0)
	check(b.position.x > LanesS.W * 0.9, "edges wrap: leaves left, returns on the right")
	tn.edge_wrap = false
	b.position.x = half + 1.0
	b.vx = -150.0
	b.step(1.0 / 30.0, false, true, -150.0)
	check(is_equal_approx(b.position.x, half) and b.vx >= 0.0, "edges block when edge_wrap is off")
	tn.edge_wrap = true

	# ---- 4. hazards ----
	print("4. hazards")
	m.restart()
	b = m.balloon
	lanes = m.lanes
	var hl := -1
	for i in lanes.n_lanes:
		if lanes.lane_count[i] > 0:
			hl = i
			break
	check(hl >= 1, "level 1 has a hazard layer")
	var kinds_hit := {}
	for k in 4:
		m.restart()
		clear_sky(m)
		b = m.balloon
		lanes = m.lanes
		var cy: float = LanesS.BAND_BOTTOM - 2.5 * lanes.lane_h
		lanes.lane_kind[2] = k
		lanes.lane_count[2] = 1
		lanes.lane_scale[2] = 1.0
		lanes.lane_amp[2] = 0.0
		lanes.lane_vel[2] = 0.0
		lanes.lane_wind[2] = 0.0
		lanes.hz_x[2 * LanesS.MAX_PER_LANE] = 400.0
		lanes.hz_y[2 * LanesS.MAX_PER_LANE] = cy
		b.position = Vector2(400.0 + 200.0, cy)
		b.on_ground = false
		m.sim(1.0 / 60.0)
		check(m.screen == MainS.SCREEN_PLAY, "%s: a clear gap is safe" % LanesS.KIND_NAME[k])
		b.position = Vector2(400.0 + 10.0, cy)
		m.sim(1.0 / 60.0)
		kinds_hit[k] = m.screen == MainS.SCREEN_DEAD and m.last_reason == "Crashed into %s" % LanesS.KIND_NAME[k]
	check(kinds_hit.values().all(func(v): return v), "touching a bird / kite / balloon / drone ends the attempt with its name")
	check(not m.balloon.visible and m.hud.over_header.visible, "crash shows the game-over screen")
	var spark := 0
	for f in LanesS.FX_MAX:
		if m.lanes.fx_life[f] > 0.0:
			spark += 1
	check(spark > 0, "crash bursts sparks (pooled)")
	DebugFlags.parse(["god"])
	m.restart()
	clear_sky(m)
	lanes = m.lanes
	lanes.lane_kind[2] = 0
	lanes.lane_count[2] = 1
	lanes.lane_scale[2] = 1.0
	lanes.lane_amp[2] = 0.0
	lanes.lane_vel[2] = 0.0
	var cyg: float = LanesS.BAND_BOTTOM - 2.5 * lanes.lane_h
	lanes.hz_x[2 * LanesS.MAX_PER_LANE] = 540.0
	lanes.hz_y[2 * LanesS.MAX_PER_LANE] = cyg
	m.balloon.position = Vector2(540.0, cyg)
	m.sim(1.0 / 60.0)
	check(m.screen == MainS.SCREEN_PLAY, "?god: hazards cannot hurt")
	DebugFlags.parse([])
	# Hazards move with their layer's wind (times the kind's speed) and loop around the screen.
	m.restart()
	lanes = m.lanes
	var ml := -1
	for i in lanes.n_lanes:
		if lanes.lane_count[i] > 0:
			ml = i
			break
	var hx0: float = lanes.hz_x[ml * LanesS.MAX_PER_LANE]
	lanes.update(0.5)
	var moved: float = lanes.hz_x[ml * LanesS.MAX_PER_LANE] - hx0
	if absf(moved) > LanesS.RING * 0.5:
		moved -= signf(moved) * LanesS.RING
	check(absf(moved - lanes.lane_vel[ml] * 0.5) < 1.0 and signf(lanes.lane_vel[ml]) == signf(lanes.lane_wind[ml]), "hazards move with their layer's wind")
	for i in 600:
		lanes.update(0.1)
	var inside := true
	for j in lanes.lane_count[ml]:
		var hx: float = lanes.hz_x[ml * LanesS.MAX_PER_LANE + j]
		inside = inside and hx >= -LanesS.MARGIN and hx < LanesS.W + LanesS.MARGIN
	check(inside, "hazards loop around the screen, never leave the ring")

	# ---- 5. propane ----
	print("5. propane")
	m.restart()
	clear_sky(m)
	b = m.balloon
	check(is_equal_approx(m.fuel, tn.propane_start), "run starts with a full tank")
	step(m, 1.0, 0)
	check(is_equal_approx(m.fuel, tn.propane_start), "no burn, no drain")
	step(m, 1.0, 1)
	check(absf(m.fuel - (tn.propane_start - tn.burn_rate)) < 0.5, "burner drains burn_rate per second (%.1f)" % m.fuel)
	m.fuel = 5.0
	b.position.y = LanesS.BAND_BOTTOM - 2.5 * m.lanes.lane_h
	step(m, 1.5, 1)
	check(m.fuel == 0.0 and not b.burning, "empty tank: the burner dies")
	check(m.screen == MainS.SCREEN_PLAY and b.rise < 100.0, "...and the balloon starts to sink")
	step(m, 60.0, 1)
	check(m.screen == MainS.SCREEN_DEAD and m.last_reason.begins_with("Out of propane"), "landing with an empty tank ends the run")
	# Pickups
	m.restart()
	clear_sky(m)
	lanes = m.lanes
	b = m.balloon
	m.fuel = 30.0
	b.position = Vector2(400.0, LanesS.BAND_BOTTOM - 1.5 * lanes.lane_h)
	b.on_ground = false
	lanes.pk_on[1] = 1
	lanes.pk_x[1] = 400.0
	lanes.pk_y[1] = b.position.y
	lanes.lane_vel[1] = 0.0
	lanes.lane_wind[1] = 0.0
	step(m, 0.05, 0)
	check(lanes.pk_on[1] == 0 and absf(m.fuel - (30.0 + tn.propane_refill)) < 1.0, "a pickup refills propane (%.0f)" % m.fuel)
	var live := 0
	for f in LanesS.FX_MAX:
		if lanes.fx_life[f] > 0.0:
			live += 1
	check(live > 0, "...with a pooled burst")
	m.fuel = tn.propane_start - 5.0
	lanes.pk_on[1] = 1
	lanes.pk_x[1] = b.position.x
	lanes.pk_y[1] = b.position.y
	step(m, 0.05, 0)
	check(m.fuel == tn.propane_start, "refills never exceed the tank")

	# ---- 6. levels ----
	print("6. levels")
	m.restart()
	clear_sky(m)
	lanes = m.lanes
	b = m.balloon
	check(m.level == 1 and m.score == 0 and lanes.n_lanes == 5, "level 1: 5 layers")
	var w1: float = lanes.wind_for(1)
	m.fuel = 60.0
	b.position = Vector2(540.0, LanesS.GOAL_Y + 4.0)
	b.on_ground = false
	b.rise = 250.0
	b.heat = 1.0
	m.level_time = 0.0
	step(m, 0.1, 1)
	check(m.screen == MainS.SCREEN_CLEAR and m.level == 2, "reaching the top clears the level")
	var par: float = tn.par_base + tn.par_per_layer * 5.0
	var expect := roundi(tn.level_points) + roundi((par - 0.02) * tn.speed_bonus_per_s)
	check(absi(m.score - expect) <= 12, "score = level points + speed bonus (%d, expected ~%d)" % [m.score, expect])
	check(m.hud.banner.visible and m.hud.banner.text.contains("CLEARED"), "cleared banner")
	var fuel_before: float = m.fuel
	step(m, 1.5, 0)
	check(m.screen == MainS.SCREEN_PLAY and m.balloon.on_ground and m.balloon.visible, "next level starts on the ground")
	check(m.lanes.n_lanes == 6, "level 2: more layers (%d)" % m.lanes.n_lanes)
	check(m.lanes.wind_for(2) > w1, "...faster winds")
	check(m.fuel > fuel_before - 0.01 and m.fuel <= tn.propane_start, "level refill (%.0f)" % m.fuel)
	check(m.hud.level_label.text == "LEVEL 2", "HUD shows the level")
	# A slow level pays no speed bonus, never negative.
	clear_sky(m)
	m.balloon.position = Vector2(540.0, LanesS.GOAL_Y + 4.0)
	m.balloon.on_ground = false
	m.balloon.rise = 250.0
	m.balloon.heat = 1.0
	m.level_time = 500.0
	var s_before: int = m.score
	step(m, 0.05, 1)
	check(m.score - s_before == roundi(tn.level_points) and m.last_bonus == 0, "no speed bonus for a slow level")

	# ---- 7. fairness ----
	print("7. generated levels")
	var bal_w: float = BalloonS.WIDTH * tn.balloon_scale
	var min_gap: float = tn.min_gap_factor * bal_w
	var bad_gap := 0
	var bad_shape := 0
	var bad_limit := 0
	var min_seen := 99999.0
	var dens := {}
	var checked := 0
	for lv in [1, 2, 3, 4, 5, 6, 8, 10, 15, 25, 40]:
		var sum_h := 0
		var sum_l := 0
		for seed_i in 40:
			lanes.rng.seed = lv * 1000 + seed_i
			lanes.setup(lv)
			var any := false
			if lanes.n_lanes > tn.layers_max or lanes.n_lanes < 3:
				bad_limit += 1
			if lanes.lane_count[0] != 0 or lanes.lane_count[lanes.n_lanes - 1] != 0:
				bad_shape += 1
			for i in lanes.n_lanes:
				if absf(lanes.lane_wind[i]) > tn.wind_max + 0.01 or absf(lanes.lane_wind[i]) < 1.0:
					bad_limit += 1
				var c: int = lanes.lane_count[i]
				if c == 0:
					continue
				any = true
				sum_h += c
				sum_l += 1
				var k: int = lanes.lane_kind[i]
				var w: float = 2.0 * float(LanesS.KIND_HX[k]) * lanes.lane_scale[i]
				var xs: Array[float] = []
				for j in c:
					xs.append(lanes.hz_x[i * LanesS.MAX_PER_LANE + j])
				xs.sort()
				for j in c:
					var nxt: float = xs[(j + 1) % c] + (LanesS.RING if j == c - 1 else 0.0)
					var gap: float = nxt - xs[j] - w
					min_seen = minf(min_seen, gap)
					if gap < min_gap - 0.5:
						bad_gap += 1
					checked += 1
				if c > LanesS.MAX_PER_LANE:
					bad_limit += 1
			if not any:
				bad_shape += 1
		dens[lv] = float(sum_h) / float(maxi(sum_l, 1))
	check(bad_gap == 0, "every gap >= %.0f px in %d gaps (smallest %.0f)" % [min_gap, checked, min_seen])
	check(bad_shape == 0, "start and goal layers are clear; every level has a hazard layer")
	check(bad_limit == 0, "layer count, wind speeds and layer fill within limits")
	check(dens[10] > dens[1] and dens[25] >= dens[10] - 0.01, "hazard density grows with the level (%.1f -> %.1f -> %.1f)" % [dens[1], dens[10], dens[25]])
	check(lanes.layers_for(1) == 5 and lanes.layers_for(3) == 7 and lanes.layers_for(30) == tn.layers_max, "layers: 5 at level 1, +1 per level, capped")
	check(lanes.wind_for(30) == tn.wind_max, "wind speed is capped")
	# Pickups sit in a gap, not on a hazard.
	var on_hazard := 0
	for seed_i in 40:
		lanes.rng.seed = 777 + seed_i
		lanes.setup(3)
		for i in lanes.n_lanes:
			if lanes.pk_on[i] == 0 or lanes.lane_count[i] == 0:
				continue
			var k2: int = lanes.lane_kind[i]
			for j in lanes.lane_count[i]:
				var dx := absf(fposmod(lanes.pk_x[i] - lanes.hz_x[i * LanesS.MAX_PER_LANE + j] + LanesS.RING * 0.5, LanesS.RING) - LanesS.RING * 0.5)
				if dx < float(LanesS.KIND_HX[k2]) * lanes.lane_scale[i] + 20.0:
					on_hazard += 1
	check(on_hazard == 0, "pickups float in the gaps between hazards")

	# ---- 8. restart in place ----
	print("8. restart in place")
	m.set_process(true)
	m.burn_override = -1
	var base := snap()
	for run in 3:
		m.restart()
		check(m.screen == MainS.SCREEN_PLAY and m.score == 0 and m.level == 1 and m.balloon.on_ground, "run %d starts fresh" % (run + 1))
		check(m.hud.level_label.text == "LEVEL 1" and not m.hud.over_header.visible, "run %d HUD reset" % (run + 1))
		m.burn_override = 1
		await real_wait(1.0)
		var s0: float = m.balloon.position.y
		check(s0 < m.balloon.floor_y() - 20.0, "run %d: balloon climbs under real frames" % (run + 1))
		# Kill it on a hazard.
		clear_sky(m)
		m.lanes.lane_kind[2] = 1
		m.lanes.lane_count[2] = 1
		m.lanes.lane_scale[2] = 1.0
		m.lanes.lane_amp[2] = 0.0
		m.lanes.lane_vel[2] = 0.0
		m.burn_override = 0
		m.balloon.position.y = LanesS.BAND_BOTTOM - 2.5 * m.lanes.lane_h
		m.balloon.on_ground = false
		m.lanes.hz_x[2 * LanesS.MAX_PER_LANE] = m.balloon.position.x
		await process_frame
		await process_frame
		check(m.screen == MainS.SCREEN_DEAD, "run %d ends on a crash" % (run + 1))
		check(m.hud.over_header.visible and m.hud.over_header.text.begins_with("Crashed into") and m.hud.tap_label.text == "TAP TO RETRY", "run %d game-over UI" % (run + 1))
		tap(m, Vector2(500, 900))
		check(m.screen == MainS.SCREEN_DEAD, "run %d: a tap during the retry delay is ignored" % (run + 1))
		m.dead_time = 1.0
		tap(m, Vector2(500, 900))
		check(m.screen == MainS.SCREEN_PLAY, "run %d: a tap restarts" % (run + 1))
		await process_frame
	var after := snap()
	check(same(base, after), "no new nodes, materials or resources across 3 restarts (%d nodes, %d resources)" % [after["nodes"], after["resources"]])
	m.burn_override = 0
	# Best score
	m.restart()
	m.score = 340
	m._end_run("test")
	check(m.best >= 340 and m.hud.best_label.text.begins_with("best"), "best score recorded")

	# ---- 9. frame time ----
	print("9. frame time")
	m.set_process(false)
	m._skip_frames = 0
	m._suspended = false
	check(is_equal_approx(m._frame_delta(0.016), 0.016), "normal frame used as is")
	check(is_equal_approx(m._frame_delta(0.15), tn.max_frame_delta), "long frame clamped")
	check(m._frame_delta(0.5) == 0.0, "stall dropped")
	check(m._frame_delta(0.016) == 0.0 and m._frame_delta(0.016) == 0.0, "...and the frames after it skipped")
	check(m._frame_delta(0.016) > 0.0, "...then back to normal")
	m._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(m._frame_delta(0.016) == 0.0, "background: no time passes")
	m._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	check(m._frame_delta(0.016) == 0.0 and m._frame_delta(0.016) == 0.0 and m._frame_delta(0.016) > 0.0, "coming back skips a couple of frames")

	# ---- 10. tune panel ----
	print("10. tune panel")
	check(m.tune_panel == null, "no tune panel without ?tune")
	m.free()
	await process_frame
	DebugFlags.parse(["tune"])
	m = make_main()
	await process_frame
	m.set_process(false)
	var tp = m.tune_panel
	check(tp != null, "?tune builds the panel")
	var base2 := snap()
	check(not tp.is_open, "closed at start")
	tp.open()
	check(tp.is_open and paused, "opening pauses the game")
	tp._sliders["buoyancy_lag"].value = 3.5
	check(is_equal_approx(tn.buoyancy_lag, 3.5), "a slider edits Tuning live")
	tp._sliders["burn_rate"].value = 12.5
	tp._toggles["edge_wrap"].button_pressed = false
	check(is_equal_approx(tn.burn_rate, 12.5) and tn.edge_wrap == false, "more sliders and the edge toggle")
	tp.copy_values()
	check(tp.last_copied_text.contains("buoyancy_lag = 3.5") and tp.last_copied_text.contains("burn_rate = 12.5") and tp.last_copied_text.contains("edge_wrap = false"), "Copy values lists what changed")
	check(not tp.last_copied_text.contains("climb_speed"), "...and only what changed")
	tp.reset_defaults()
	check(is_equal_approx(tn.buoyancy_lag, 2.0) and tn.edge_wrap and tp.changed_text() == "(no changes)", "Reset restores the defaults")
	tp.close()
	check(not tp.is_open and not paused, "closing resumes")
	check(same(base2, snap()), "using the panel allocates nothing")
	# A tap on the TUNE button is not a game tap.
	TuneS._button_rect = Rect2(890, 20, 170, 76)
	m._show_menu()
	tap(m, Vector2(900, 40))
	check(m.screen == MainS.SCREEN_MENU, "a tap on TUNE does not start the game")
	tap(m, Vector2(500, 900))
	check(m.screen == MainS.SCREEN_PLAY, "a tap elsewhere does")
	m.free()
	TuneS._button_rect = Rect2()
	DebugFlags.parse([])
	await process_frame
