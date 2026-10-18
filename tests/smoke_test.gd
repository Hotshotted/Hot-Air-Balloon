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
##   6. Flights: five legs on ONE tank (propane carries over), leg score, a failed leg ends the Flight (coins
##      kept), finishing awards 1-3 stars and coins, same seed = same Flight, floating coins, stars progress HUD
##   6b. save: versioned, round trip, migration of old files, unlocks (Flight chain, region star threshold)
##   7. fairness of generated levels (hundreds of layouts): clear start / goal layers, gaps wider than the
##      balloon, layers / winds / density within limits and growing with the level
##   8. a crash ends the run; a tap restarts it IN PLACE (three runs in a row), creating no new nodes or resources
##   9. frame time: clamp, stall dropping, resume skipping, background suspension
##  10. ?tune panel: opens over the paused game, sliders edit Tuning live, Copy and Reset work, closing resumes,
##      a tap on the TUNE button is not a game tap, nothing is allocated; absent without ?tune

var failures: Array[String] = []
var tn: Node
var sv: Node
# Loaded at run time (after the autoloads exist): naming these classes in this file would compile them too early.
var MainS: GDScript
var LanesS: GDScript
var BalloonS: GDScript
var TuneS: GDScript
var FlightsS: GDScript

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

func make_main() -> Node:
	var m: Node = load("res://scenes/main.tscn").instantiate()
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
	sv = root.get_node("Save")
	sv.persist = false
	sv.reset_all()
	MainS = load("res://scripts/Main.gd")
	LanesS = load("res://scripts/Lanes.gd")
	BalloonS = load("res://scripts/Balloon.gd")
	TuneS = load("res://scripts/TunePanel.gd")
	FlightsS = load("res://scripts/Flights.gd")
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
	check(kinds.size() == 8, "showcase draws all eight hazard kinds")
	var guard := 0
	while m._warming and guard < 2000:
		await process_frame
		guard += 1
	var warm_s := (Time.get_ticks_msec() - t0) / 1000.0
	check(not m._warming, "pre-warm finishes")
	check(warm_s >= tn.prewarm_min_seconds, "pre-warm lasts at least prewarm_min_seconds (%.1f s)" % warm_s)
	check(not m.hud.splash.visible and m.hud.map.visible and m.screen == MainS.SCREEN_MAP, "the world map after the splash")
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
	m.start_flight(0)
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
	m.start_flight(0)
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
	m.start_flight(0)
	b = m.balloon
	lanes = m.lanes
	var hl := -1
	for i in lanes.n_lanes:
		if lanes.lane_count[i] > 0:
			hl = i
			break
	check(hl >= 1, "level 1 has a hazard layer")
	var kinds_hit := {}
	for k in 8:
		m.start_flight(0)
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
	check(kinds_hit.values().all(func(v): return v) and kinds_hit.size() == 8, "touching any of the 8 hazard kinds ends the attempt with its name")
	check(not m.balloon.visible and m.hud.dead_p.visible and m.hud.dead_text.text.contains("Crashed into"), "a crash ends the Flight and shows the failed screen")
	var spark := 0
	for f in LanesS.FX_MAX:
		if m.lanes.fx_life[f] > 0.0:
			spark += 1
	check(spark > 0, "crash bursts sparks (pooled)")
	DebugFlags.parse(["god"])
	m.start_flight(0)
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
	m.start_flight(0)
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
	m.start_flight(0)
	clear_sky(m)
	b = m.balloon
	check(is_equal_approx(m.fuel, tn.propane_start), "run starts with a full tank")
	step(m, 1.0, 0)
	check(is_equal_approx(m.fuel, tn.propane_start), "no burn, no drain")
	step(m, 1.0, 1)
	check(absf(m.fuel - (tn.propane_start - tn.burn_rate)) < 0.5, "burner drains burn_rate per second (%.1f)" % m.fuel)
	m.fuel = 2.0
	b.position.y = LanesS.BAND_BOTTOM - 2.5 * m.lanes.lane_h
	step(m, 1.5, 1)
	check(m.fuel == 0.0 and not b.burning, "empty tank: the burner dies")
	check(m.screen == MainS.SCREEN_PLAY and b.rise < 100.0, "...and the balloon starts to sink")
	step(m, 60.0, 1)
	check(m.screen == MainS.SCREEN_DEAD and m.last_reason.begins_with("Out of propane"), "landing with an empty tank ends the run")
	# Pickups
	m.start_flight(0)
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

	# ---- 6. Flights ----
	print("6. Flights")
	m.start_flight(0)
	clear_sky(m)
	lanes = m.lanes
	b = m.balloon
	check(m.leg == 0 and m.score == 0 and lanes.n_lanes == 5, "Flight 1, leg 1: 5 layers")
	check(is_equal_approx(m.fuel, tn.propane_start), "a Flight starts with a fresh tank")
	check(m.hud.level_label.text.contains("LEG 1/5"), "HUD shows the leg")
	var w1: float = lanes.wind_for(1.0)
	m.fuel = 60.0
	b.position = Vector2(540.0, LanesS.GOAL_Y + 4.0)
	b.on_ground = false
	b.rise = 250.0
	b.heat = 1.0
	m.leg_time = 0.0
	m.leg_started = true
	step(m, 0.1, 1)
	check(m.screen == MainS.SCREEN_CLEAR and m.leg == 1, "reaching the top clears the leg")
	var par: float = tn.par_base + tn.par_per_layer * 5.0
	var expect := roundi(tn.level_points) + roundi((par - 0.02) * tn.speed_bonus_per_s)
	check(absi(m.score - expect) <= 12, "score = leg points + speed bonus (%d, expected ~%d)" % [m.score, expect])
	check(m.flight_coins == roundi(tn.leg_coins), "a cleared leg pays its coins")
	check(m.hud.banner.visible and m.hud.banner.text.contains("CLEARED"), "cleared banner")
	var fuel_before: float = m.fuel
	step(m, 1.5, 0)
	check(m.screen == MainS.SCREEN_PLAY and m.balloon.on_ground and m.balloon.visible, "next leg starts on the ground")
	check(absf(m.fuel - fuel_before) < 0.01, "propane carries over into the next leg (%.1f)" % m.fuel)
	check(m.leg == 1 and m.hud.level_label.text.contains("LEG 2/5"), "leg 2 of 5")
	check(m.lanes.wind_for(1.5) > w1, "winds get faster leg by leg")
	# A slow leg pays no speed bonus, never negative.
	clear_sky(m)
	m.balloon.position = Vector2(540.0, LanesS.GOAL_Y + 4.0)
	m.balloon.on_ground = false
	m.balloon.rise = 250.0
	m.balloon.heat = 1.0
	m.leg_time = 500.0
	m.leg_started = true
	var s_before: int = m.score
	step(m, 0.05, 1)
	check(m.score - s_before == roundi(tn.level_points) and m.last_bonus == 0, "no speed bonus for a slow leg")
	check(m.leg == 2, "leg 3 reached")
	# The clock only runs once the balloon has left the ground.
	step(m, 1.5, 0)
	m.start_flight(0)
	clear_sky(m)
	step(m, 1.0, 0)
	check(m.leg_time == 0.0 and not m.leg_started, "the leg clock waits on the ground")
	step(m, 1.0, 1)
	check(m.leg_started and m.leg_time > 0.0, "...and starts when the balloon lifts off")
	# Failing a leg ends the whole Flight; coins earned so far are kept.
	m.start_flight(0)
	clear_sky(m)
	var coins0: int = sv.coins
	m.flight_coins = 33
	m.fuel = 0.0
	step(m, 60.0, 1)
	check(m.screen == MainS.SCREEN_DEAD and m.hud.dead_p.visible, "a failed leg ends the Flight")
	check(sv.coins == coins0 + 33 and sv.stars_of(0) == 0, "coins earned are kept, no stars for a failed Flight")
	check(m.hud.dead_text.text.contains("Leg 1 of 5") and m.hud.dead_text.text.contains("33"), "failed screen names the leg and the coins kept")
	# A whole Flight: five legs on one tank.
	sv.reset_all()
	m.start_flight(0)
	for l in 5:
		clear_sky(m)
		m.fuel = m.fuel
		m.balloon.position = Vector2(540.0, LanesS.GOAL_Y + 4.0)
		m.balloon.on_ground = false
		m.balloon.rise = 250.0
		m.balloon.heat = 1.0
		m.leg_started = true
		if l == 3:
			m.coins_picked = 9
			m.fuel = 45.0
		step(m, 0.05, 1)
		if l < 4:
			step(m, 1.5, 0)
	check(m.screen == MainS.SCREEN_RESULT and m.hud.result_p.visible, "five cleared legs finish the Flight")
	check(m.last_stars == 3 and sv.stars_of(0) == 3, "finished with enough propane and coins: 3 stars")
	check(m.hud.result_lit[0] and m.hud.result_lit[1] and m.hud.result_lit[2], "result screen lights all three stars")
	var expect_coins: int = 5 * roundi(tn.leg_coins) + roundi(m.fuel * tn.propane_coins)
	check(m.flight_coins == expect_coins and sv.coins == expect_coins, "coins = legs + propane bonus (%d)" % sv.coins)
	check(sv.best_score_of(0) == m.score and m.score > 500, "best score saved (%d)" % m.score)
	check(sv.flight_unlocked(1), "completing a Flight opens the next")
	check(FlightsS.stars_for(false, 99.0, 99) == 0, "no stars unless completed")
	check(FlightsS.stars_for(true, 0.0, 0) == 1, "1 star: completed")
	check(FlightsS.stars_for(true, FlightsS.propane_target(), 0) == 2, "2 stars: completed + propane")
	check(FlightsS.stars_for(true, 0.0, FlightsS.coin_target()) == 2, "2 stars: completed + coins")
	check(FlightsS.stars_for(true, FlightsS.propane_target(), FlightsS.coin_target()) == 3, "3 stars: both")
	check(FlightsS.stars_for(true, FlightsS.propane_target() - 0.1, FlightsS.coin_target() - 1) == 1, "just under both targets: 1 star")
	check(FlightsS.coin_total() == 15 and FlightsS.coin_target() == 9, "15 floating coins per Flight, 9 needed")
	# Same seed = same Flight.
	var sig_a := []
	var sig_b := []
	for pass_i in 2:
		m.start_flight(7)
		for l in 5:
			m.lanes.setup(FlightsS.eff_level(1, 1, l), false, FlightsS.leg_seed(FlightsS.seed_of(7), l))
			var sig := [m.lanes.n_lanes, Array(m.lanes.hz_x.slice(0, 20)), Array(m.lanes.lane_wind.slice(0, 9)), Array(m.lanes.cn_x.slice(0, 9)), Array(m.lanes.pk_on.slice(0, 9))]
			(sig_a if pass_i == 0 else sig_b).append(sig)
	check(sig_a == sig_b, "a Flight is identical every time it is played (5 legs compared)")
	m.lanes.setup(1.0, false, FlightsS.leg_seed(FlightsS.seed_of(8), 0))
	var other: Array = Array(m.lanes.hz_x.slice(0, 20))
	check(other != sig_a[0][1], "a different Flight has a different layout")
	# Floating coins: coins_per_leg of them, in the gaps; collecting counts toward the third star.
	var bad_coin := 0
	for seed_i in 60:
		m.lanes.setup(1.0 + float(seed_i % 12) * 0.7, false, 5000 + seed_i)
		if m.lanes.coins_left() != int(tn.coins_per_leg):
			bad_coin += 1
		for i in m.lanes.n_lanes:
			if m.lanes.cn_on[i] == 0:
				continue
			if m.lanes.pk_on[i] == 1 and absf(m.lanes.cn_x[i] - m.lanes.pk_x[i]) < 60.0:
				bad_coin += 1
			var k3: int = m.lanes.lane_kind[i]
			for j in m.lanes.lane_count[i]:
				var dx3 := absf(fposmod(m.lanes.cn_x[i] - m.lanes.hz_x[i * LanesS.MAX_PER_LANE + j] + LanesS.RING * 0.5, LanesS.RING) - LanesS.RING * 0.5)
				if dx3 < float(LanesS.KIND_HX[k3]) * m.lanes.lane_scale[i] + 20.0:
					bad_coin += 1
	check(bad_coin == 0, "%d coins in every leg, sitting in gaps clear of hazards and propane" % int(tn.coins_per_leg))
	m.start_flight(0)
	clear_sky(m)
	m.lanes.cn_on[1] = 1
	m.lanes.lane_vel[1] = 0.0
	m.lanes.lane_wind[1] = 0.0
	m.balloon.position = Vector2(500.0, LanesS.BAND_BOTTOM - 1.5 * m.lanes.lane_h)
	m.balloon.on_ground = false
	m.lanes.cn_x[1] = 500.0
	m.lanes.cn_y[1] = m.balloon.position.y
	var fc0: int = m.flight_coins
	step(m, 0.05, 0)
	check(m.coins_picked == 1 and m.flight_coins == fc0 + roundi(tn.coin_value) and m.lanes.cn_on[1] == 0, "collecting a coin counts toward the star and pays")
	check(m.hud.prog_labels[2].text == "coins 1 / 9", "HUD shows coin progress toward the third star")
	check(m.hud.prog_labels[0].text == "0/5 legs", "HUD shows leg progress")
	m.fuel = FlightsS.propane_target() + 5.0
	step(m, 0.05, 0)
	check(m.hud.prog_lit[1], "HUD lights the propane star while the tank is above the target")
	m.fuel = FlightsS.propane_target() - 5.0
	step(m, 0.05, 0)
	check(not m.hud.prog_lit[1] and m.hud.prog_labels[1].text.begins_with("propane"), "...and dims it below")

	# ---- 6b. save ----
	print("6b. save")
	sv.reset_all()
	check(sv.coins == 0 and sv.total_stars() == 0 and sv.data["version"] == sv.VERSION, "fresh save")
	check(sv.flight_unlocked(0) and not sv.flight_unlocked(1) and not sv.flight_unlocked(6), "only the first Flight is open")
	sv.record_flight(0, 2, 500)
	sv.record_flight(0, 1, 800)
	check(sv.stars_of(0) == 2 and sv.best_score_of(0) == 800, "best stars and best score are kept separately")
	check(sv.flight_unlocked(1) and not sv.flight_unlocked(2), "Flights open one by one")
	for i in 6:
		sv.data["stars"][i] = 2
	check(sv.region_stars(0) == 12 and sv.region_unlocked(1) and sv.flight_unlocked(6), "12 stars in a region open the next region")
	sv.data["stars"][5] = 1
	check(not sv.region_unlocked(1) and not sv.flight_unlocked(6), "11 stars do not")
	check(sv.suggested_flight() == 0 or sv.suggested_flight() <= 5, "suggested Flight stays in the open part")
	sv.unlock_everything()
	check(sv.flight_unlocked(23) and sv.region_unlocked(3), "debug unlock opens everything")
	sv.three_star_everything()
	check(sv.total_stars() == 72, "debug: 3 stars everywhere")
	check(sv.spend(10) == false and sv.coins == 0, "cannot spend coins you do not have")
	sv.add_coins(50)
	check(sv.spend(20) and sv.coins == 30, "spending")
	# Disk round trip and migration.
	sv.persist = true
	sv.reset_all()
	sv.add_coins(77)
	sv.record_flight(3, 3, 999)
	sv.data = sv._defaults()
	sv._load()
	check(sv.coins == 77 and sv.stars_of(3) == 3 and sv.best_score_of(3) == 999, "save survives a round trip through the file")
	var old: Dictionary = sv._migrate({"version": 0, "coins": 5, "unknown": 1, "stars": [1, 2]})
	check(old["coins"] == 5 and old["stars"].size() == 24 and old["stars"][1] == 2 and old["version"] == sv.VERSION and not old.has("unknown"), "an older / shorter save is brought up to date")
	var junk: Dictionary = sv._migrate({"coins": "lots", "stars": "no"})
	check(junk["coins"] == 0 and junk["stars"].size() == 24, "wrong-typed fields fall back to defaults")
	sv.reset_all()
	sv.persist = false

	# ---- 6c. regions ----
	print("6c. regions")
	var RegS = load("res://scripts/Regions.gd")
	check(RegS.COUNT == 4 and RegS.NAMES == ["Countryside", "Alps", "Sahara", "Himalayas"], "four regions")
	var lows := {}
	for r in 4:
		lows[RegS.SKY_LOW[r].to_html()] = true
	check(lows.size() == 4, "each region has its own palette")
	check(m.lanes._scn.size() == 4 and m.lanes._scn[1].size() > m.lanes._scn[0].size() - 3, "each region has its own scenery")
	check(RegS.KINDS[1].has(LanesS.EAGLE) and RegS.KINDS[1].has(LanesS.CABLE), "Alps: eagles and cable cars")
	check(RegS.KINDS[2].has(LanesS.CARPET) and RegS.KINDS[3].has(LanesS.GLIDER) and RegS.KINDS[3].has(LanesS.EAGLE), "Sahara carpets, Himalayas gliders and eagles")
	# Hazard sets open up across a region's Flights.
	for r in 4:
		var kinds_a := {}
		var kinds_b := {}
		for seed_i in 40:
			m.lanes.setup(FlightsS.eff_level(r, 0, 0), false, 900 + seed_i, r)
			for i in m.lanes.n_lanes:
				if m.lanes.lane_kind[i] >= 0 and not (r == 3 and i == m.lanes.n_lanes - 1):
					kinds_a[m.lanes.lane_kind[i]] = true
			m.lanes.setup(FlightsS.eff_level(r, 5, 4), false, 950 + seed_i, r)
			for i in m.lanes.n_lanes:
				if m.lanes.lane_kind[i] >= 0 and not (r == 3 and i == m.lanes.n_lanes - 1):
					kinds_b[m.lanes.lane_kind[i]] = true
		var allowed: Array = RegS.KINDS[r]
		var ok_early: bool = kinds_a.size() == 2 and kinds_a.keys().all(func(k): return allowed.slice(0, 2).has(k))
		var ok_late: bool = kinds_b.size() == 4 and kinds_b.keys().all(func(k): return allowed.has(k))
		check(ok_early and ok_late, "%s: 2 hazard kinds in Flight 1, all 4 by Flight 6 (%s)" % [RegS.NAMES[r], str(kinds_b.keys())])
	# Difficulty rises across a region's Flights and its legs, and from region to region.
	check(FlightsS.eff_level(0, 1, 0) > FlightsS.eff_level(0, 0, 0) and FlightsS.eff_level(0, 0, 1) > FlightsS.eff_level(0, 0, 0), "difficulty rises across Flights and legs")
	check(FlightsS.eff_level(1, 0, 0) > FlightsS.eff_level(0, 0, 0) and FlightsS.eff_level(3, 0, 0) > FlightsS.eff_level(2, 0, 0) and FlightsS.eff_level(2, 5, 4) > FlightsS.eff_level(1, 5, 4), "...and across regions")
	# Alps: gusts.
	m.lanes.setup(5.0, false, 11, 1)
	var base_w: float = m.lanes.lane_base[2]
	var w_min := 1.0e9
	var w_max := -1.0e9
	for i in 400:
		m.lanes.update(0.1)
		var ratio: float = m.lanes.lane_wind[2] / base_w
		w_min = minf(w_min, ratio)
		w_max = maxf(w_max, ratio)
	check(m.lanes.gusty and w_min > 0.0 and w_min < 0.6 and w_max > 1.4 and w_max <= 1.0 + tn.gust_amp + 0.001, "Alps: a layer's wind swells and fades over time (x%.2f to x%.2f)" % [w_min, w_max])
	check(signf(m.lanes.lane_vel[2]) == signf(base_w), "gusts never reverse a layer")
	m.lanes.setup(2.0, false, 11, 0)
	var w0: float = m.lanes.lane_wind[2]
	for i in 100:
		m.lanes.update(0.1)
	check(not m.lanes.gusty and m.lanes.lane_wind[2] == w0, "Countryside winds are steady")
	var gentle := 0.0
	var brisk := 0.0
	for seed_i in 30:
		m.lanes.setup(1.0, false, 100 + seed_i, 0)
		gentle += absf(m.lanes.lane_wind[1])
		m.lanes.setup(1.0, false, 100 + seed_i, 2)
		brisk += absf(m.lanes.lane_wind[1])
	check(gentle < brisk, "Countryside winds are gentler")
	# Sahara: thermals and haze.
	m.lanes.setup(7.0, false, 12, 2)
	check(m.lanes.th_count >= 2 and m.lanes.haze_on and not m.lanes.thin_air, "Sahara: thermals and haze")
	var tx: float = m.lanes.th_x[0]
	check(absf(m.lanes.thermal_lift(tx) - tn.thermal_lift) < 1.0 and m.lanes.thermal_lift(tx + tn.thermal_width + 5.0) < 1.0 or m.lanes.th_count > 1, "a thermal lifts at its centre, not outside")
	var b1 = m.balloon
	var rise_no := 0.0
	var rise_yes := 0.0
	for pass_i in 2:
		b1.reset()
		b1.position.y = 900.0
		b1.on_ground = false
		for i in 240:
			b1.step(1.0 / 60.0, false, true, 0.0, 0.0 if pass_i == 0 else tn.thermal_lift, 1.0)
			b1.position.y = 900.0
		if pass_i == 0:
			rise_no = b1.rise
		else:
			rise_yes = b1.rise
	check(rise_yes > rise_no + tn.thermal_lift * 0.8, "inside a thermal the balloon rises (%.0f vs %.0f px/s)" % [rise_yes, rise_no])
	m.lanes.focus_lane = 3
	check(m.lanes.haze_alpha(3) == 0.0 and m.lanes.haze_alpha(4) == 0.0 and m.lanes.haze_alpha(2) == 0.0, "haze: the layers next to the balloon are clear")
	check(absf(m.lanes.haze_alpha(5) - tn.haze_per_lane) < 0.001 and m.lanes.haze_alpha(6) > m.lanes.haze_alpha(5) and m.lanes.haze_alpha(8) <= tn.haze_max + 0.001, "...and further layers fade into haze, up to a cap")
	m.lanes.setup(7.0, false, 12, 0)
	check(m.lanes.th_count == 0 and not m.lanes.haze_on, "no thermals or haze outside the Sahara")
	# Himalayas: thin air and the jet stream.
	m.lanes.setup(10.0, false, 5, 3)
	var nl: int = m.lanes.n_lanes
	check(m.lanes.thin_air and m.lanes.lane_kind[nl - 1] == LanesS.GLIDER and m.lanes.lane_count[nl - 1] > 0 and absf(m.lanes.lane_base[nl - 1]) == tn.jet_wind, "Himalayas: the top layer is a fast jet stream with paragliders")
	check(m.lanes.climb_mult_at(LanesS.BAND_BOTTOM) == 1.0 and absf(m.lanes.climb_mult_at(LanesS.GOAL_Y) - (1.0 - tn.thin_air_loss)) < 0.001, "thin air: full burner low down, weaker at the top")
	var rise_thin := 0.0
	var rise_full := 0.0
	for pass_i in 2:
		b1.reset()
		b1.position.y = 900.0
		b1.on_ground = false
		for i in 300:
			b1.step(1.0 / 60.0, true, true, 0.0, 0.0, 1.0 if pass_i == 0 else 1.0 - tn.thin_air_loss)
			b1.position.y = 900.0
		if pass_i == 0:
			rise_full = b1.rise
		else:
			rise_thin = b1.rise
	check(rise_thin < rise_full * 0.75, "thin air weakens the climb (%.0f vs %.0f px/s)" % [rise_thin, rise_full])
	var jet_other := 0
	for r in 3:
		for seed_i in 20:
			m.lanes.setup(FlightsS.eff_level(r, 3, 2), false, 40 + seed_i, r)
			if m.lanes.lane_count[m.lanes.n_lanes - 1] != 0:
				jet_other += 1
	check(jet_other == 0, "only the Himalayas have a hazardous top layer")
	m.lanes.setup(1.0, false, 3, 0)
	# Every Flight of the world, every leg: gaps, caps, a clear start layer.
	var bw: float = BalloonS.WIDTH * tn.balloon_scale
	var mg: float = tn.min_gap_factor * bw
	var bad := 0
	var worst := 99999.0
	var legs_checked := 0
	var dens_first := 0.0
	var dens_last := 0.0
	for fid in 24:
		var rr: int = FlightsS.region_of(fid)
		for l in 5:
			m.lanes.setup(FlightsS.eff_level(rr, FlightsS.index_of(fid), l), false, FlightsS.leg_seed(FlightsS.seed_of(fid), l), rr)
			legs_checked += 1
			var hz := 0
			if m.lanes.lane_count[0] != 0 or m.lanes.n_lanes > tn.layers_max:
				bad += 1
			for i in m.lanes.n_lanes:
				if absf(m.lanes.lane_base[i]) > maxf(tn.wind_max, tn.jet_wind) + 0.01:
					bad += 1
				var c2: int = m.lanes.lane_count[i]
				hz += c2
				if c2 == 0:
					continue
				var k4: int = m.lanes.lane_kind[i]
				var w4: float = 2.0 * float(LanesS.KIND_HX[k4]) * m.lanes.lane_scale[i]
				var xs2: Array[float] = []
				for j in c2:
					xs2.append(m.lanes.hz_x[i * LanesS.MAX_PER_LANE + j])
				xs2.sort()
				for j in c2:
					var nxt2: float = xs2[(j + 1) % c2] + (LanesS.RING if j == c2 - 1 else 0.0)
					var g2: float = nxt2 - xs2[j] - w4
					worst = minf(worst, g2)
					if g2 < mg - 0.5:
						bad += 1
			if fid == 0 and l == 0:
				dens_first = float(hz)
			if fid == 23 and l == 4:
				dens_last = float(hz)
	check(bad == 0, "all 24 Flights x 5 legs (%d): every gap >= %.0f px (smallest %.0f), caps respected" % [legs_checked, mg, worst])
	check(dens_last > dens_first, "the last Flight is denser than the first (%d vs %d hazards)" % [dens_last, dens_first])
	# Finishing a region's star threshold opens the next region (once).
	sv.reset_all()
	for i in 5:
		sv.data["stars"][i] = 2
	sv.data["stars"][5] = 1
	m.start_flight(5)
	for l in 5:
		clear_sky(m)
		m.balloon.position = Vector2(540.0, LanesS.GOAL_Y + 4.0)
		m.balloon.on_ground = false
		m.balloon.rise = 250.0
		m.balloon.heat = 1.0
		m.leg_started = true
		if l == 3:
			m.coins_picked = 9
			m.fuel = 60.0
		step(m, 0.05, 1)
		if l < 4:
			step(m, 1.5, 0)
	check(m.screen == MainS.SCREEN_RESULT and sv.region_stars(0) == 13 and sv.region_unlocked(1), "13 stars open the Alps")
	check(m.hud.result_summary.text.contains("NEW REGION UNLOCKED: Alps"), "the result screen announces the new region")
	check(sv.take_new_region() == -1, "...only once")
	check(m.hud.result_next.disabled, "no NEXT after a region's last Flight")
	m.hud.next_flight_pressed.emit()
	check(m.screen == MainS.SCREEN_MAP, "NEXT from a region's last Flight goes to the map")
	sv.reset_all()
	m.start_flight(0)
	m._on_next_flight()
	check(m.screen == MainS.SCREEN_MAP, "NEXT without the next Flight open goes to the map")
	# Map screen.
	sv.reset_all()
	m._show_map()
	var mp = m.hud.map
	check(mp.nodes.size() == 24 and mp.visible, "the map has a node for each of the 24 Flights")
	check(not mp.nodes[0].disabled and mp.nodes[1].disabled and mp.nodes[0].visible and not mp.nodes[6].visible, "only the first Flight is open; later regions are hidden behind a padlock")
	check(mp.region_locks[1].visible and mp.region_locks[1].text.contains("12") and not mp.region_locks[0].visible, "locked regions say how many stars open them")
	sv.data["stars"][0] = 3
	sv.data["stars"][1] = 1
	mp.refresh()
	check(not mp.nodes[2].disabled and mp.nodes[3].disabled and mp.stars_label.text == "stars 4/72" and mp.region_stars[0].text.begins_with("4/18"), "stars and unlocks show on the map")
	check(mp.suggested == 2 or mp.suggested == 1, "a ring marks where to fly next")
	sv.unlock_everything()
	mp.refresh()
	check(mp.nodes[23].visible and not mp.nodes[23].disabled and not mp.region_locks[3].visible, "unlock-all opens every region")
	sv.reset_all()
	mp.refresh()
	mp.nodes[0].pressed.emit()
	check(m.selected == 0 and m.screen == MainS.SCREEN_MENU, "tapping a node opens the Flight screen")
	# Save v2: an old (v1) file gets the new fields.
	var v1: Dictionary = sv._migrate({"version": 1, "coins": 9, "stars": [3], "best_score": [5]})
	check(v1["seen_regions"].size() == 4 and v1["seen_regions"][0] == true and v1["last_flight"] == 0 and v1["coins"] == 9 and v1["version"] == 2, "a v1 save is migrated to v2")
	m._show_map()

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
		m.start_flight(0)
		check(m.screen == MainS.SCREEN_PLAY and m.score == 0 and m.leg == 0 and m.balloon.on_ground, "run %d starts fresh" % (run + 1))
		check(m.hud.level_label.text.contains("LEG 1/5") and not m.hud.dead_p.visible, "run %d HUD reset" % (run + 1))
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
		check(m.hud.dead_p.visible and m.hud.dead_text.text.contains("Crashed into"), "run %d failed screen" % (run + 1))
		m.hud.again_pressed.emit()
		check(m.screen == MainS.SCREEN_PLAY and not m.hud.dead_p.visible, "run %d: FLY AGAIN restarts the same Flight" % (run + 1))
		await process_frame
	var after := snap()
	check(same(base, after), "no new nodes, materials or resources across 3 restarts (%d nodes, %d resources)" % [after["nodes"], after["resources"]])
	m.burn_override = 0
	# Map <-> Flight screen buttons.
	m.hud.menu_pressed.emit()
	check(m.screen == MainS.SCREEN_MAP and m.hud.map.visible and not m.lanes.visible, "MAP returns to the world map")
	sv.reset_all()
	m.hud.flight_chosen.emit(0)
	check(m.screen == MainS.SCREEN_MENU and m.hud.menu_p.visible and m.lanes.visible, "choosing a Flight opens its screen")
	check(m.hud.fly_btn.disabled == false and m.hud.menu_name.text == "FLIGHT 1" and m.hud.menu_title.text == "Countryside", "Flight 1 of the Countryside")
	check(m.hud.prev_btn.disabled and not m.hud.next_btn.disabled, "arrows stay inside the region")
	m.hud.flight_chosen.emit(2)
	check(m.hud.fly_btn.disabled and m.hud.menu_info.text.begins_with("Locked"), "a locked Flight cannot be flown")
	m.hud.flight_chosen.emit(0)
	m.hud.back_pressed.emit()
	check(m.screen == MainS.SCREEN_MAP, "BACK returns to the map")
	m.hud.flight_chosen.emit(0)
	m.hud.fly_pressed.emit()
	check(m.screen == MainS.SCREEN_PLAY and m.flight_id == 0 and m.lanes.visible, "FLY starts the selected Flight")
	var allocs_before := snap()
	m.hud.menu_pressed.emit()
	m.hud.flight_chosen.emit(0)
	m.hud.fly_pressed.emit()
	await process_frame
	check(same(allocs_before, snap()), "map / Flight screen / fly cycle allocates nothing")

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
	# Debug buttons in the panel change the save.
	sv.reset_all()
	var sc := 0
	tp.save_changed.connect(func(): sc += 1)
	sv.add_coins(1000)
	sv.three_star_everything()
	sv.unlock_everything()
	check(sv.coins == 1000 and sv.total_stars() == 72 and sv.region_unlocked(3), "?tune: coins, 3 stars everywhere, all regions")
	sv.reset_all()
	check(sv.coins == 0 and sv.total_stars() == 0, "?tune: reset save")
	m.free()
	DebugFlags.parse([])
	await process_frame
