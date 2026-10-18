extends SceneTree
## Headless smoke test:  godot --headless --path . --script res://tests/smoke_test.gd
## Exits with code 1 if anything below fails (CI runs this before exporting).
##   1. ?debug flags parse
##   2. boot: the splash pre-warm draws every shape, lasts long enough, then cleans up; menu is up
##   3. balloon (steady scheme, the one the other sections fly with): constant climb / sink speeds with no lag,
##      tethered on the ground, sideways speed exactly the wind of its layer (blend only on a layer change),
##      screen edges wrap / block
##   3b. the three control schemes (lanes hops, drag, steady), propane per scheme, the drift preview, wind labels,
##      constant winds (no gusts), pickups that hang still
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
var test_controls := "steady"

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

## The tests fly with the steady scheme (hold = climb) unless a section picks another one; the scheme tests choose theirs.
func make_main() -> Node:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	DebugFlags.controls = test_controls   # (Main reads the scheme from the flags in _ready)
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
		m.lanes.cn_on[i] = 0
	m.lanes.gs_count = 0

## No twists either (reversing winds, kite beat, lightning): a calm sky for tests of the balloon alone.
func calm(m: Node) -> void:
	clear_sky(m)
	m.lanes.lane_rev.fill(0.0)
	m.lanes.lane_beat.fill(0.0)
	m.lanes.lt_on = false
	m.lanes.lt_state = 0

## Complete the current leg, whatever its goal: collect the stars, deliver the mail, or touch down on the airship.
func win_leg(m: Node) -> void:
	clear_sky(m)
	m.lanes.lt_on = false
	m.lanes.lt_state = 0
	m.leg_started = true
	if m.recipe.goal == 4:   # Precision Landing
		var sc: float = m.balloon.s()
		m.balloon.set_altitude(LanesS.SHIP_DECK_Y - 60.0 * sc)
		m.balloon.position.x = m.lanes.ship_x
		m.balloon.on_ground = false
		step(m, 0.05, 0)
	else:
		for q in m.lanes.gs_count:
			m.lanes.gs_on[q] = 0
		m.lanes.mail_state = 2
		m.lanes.storm_y = 9000.0
		m.balloon.set_altitude(LanesS.GOAL_Y - 2.0)
		m.balloon.position.x = 540.0
		m.balloon.on_ground = false
		step(m, 0.05, 1)

## Fly a whole Flight by completing its five legs (coins / fuel set before the 4th leg).
func win_flight(m: Node, fid: int, coins: int, fuel: float) -> void:
	m.start_flight(fid)
	for l in 5:
		if l == 3:
			m.coins_picked = coins
			m.fuel = fuel
		win_leg(m)
		if l < 4:
			step(m, 1.5, 0)

## All Buttons under `node`, by their text.
func find_buttons(node: Node, out: Dictionary) -> void:
	if node is Button:
		out[(node as Button).text] = node
	for c in node.get_children():
		find_buttons(c, out)

## The save file as it is on disk.
func read_save() -> Dictionary:
	var f := FileAccess.open(sv.PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text()) if f else null
	return parsed if parsed is Dictionary else {}

## Every region, Flight (and with `cards` every postcard) is open: in the live state, on the map, and in the saved file.
func check_everything_open(m: Node, sv: Node, what: String, cards: bool) -> void:
	var live := true
	for r in 4:
		live = live and sv.region_unlocked(r)
	for id in 24:
		live = live and sv.flight_unlocked(id)
	check(live, "%s: every region and Flight is open (live state)" % what)
	var mp = m.hud.map
	var shown := true
	for id in 24:
		shown = shown and mp.nodes[id].visible and not mp.nodes[id].disabled
	for r in 4:
		shown = shown and not mp.region_locks[r].visible
	check(shown, "%s: the map shows them all open, without a reload" % what)
	# The saved file, read back through a fresh load.
	var file_data := read_save()
	var keep: Dictionary = sv.data
	sv.data = sv._defaults()
	sv._load()
	var saved_ok := true
	for r in 4:
		saved_ok = saved_ok and sv.region_unlocked(r)
		if cards:
			saved_ok = saved_ok and sv.postcard_of(r) == 2
	for id in 24:
		saved_ok = saved_ok and sv.flight_unlocked(id)
		if cards:
			saved_ok = saved_ok and sv.stars_of(id) == 3
	sv.data = keep
	check(saved_ok and file_data.get("unlock_all", false) == true, "%s: every region and Flight is open (saved file)" % what)
	if cards:
		check([sv.postcard_of(0), sv.postcard_of(1), sv.postcard_of(2), sv.postcard_of(3)] == [2, 2, 2, 2] and Array(file_data["postcards"]).map(func(v): return int(v)) == [2, 2, 2, 2] and sv.total_stars() == 72 and mp.region_stars[3].text.begins_with("18/18"), "%s: all four postcards are awarded (live, saved, map)" % what)

## The layer a given star index belongs to (tests move stars onto the balloon).
func lanes_of(m: Node, q: int) -> int:
	return m.lanes.lane_of(m.balloon.position.y)

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
	tn.ads_enabled = false   # (the ad section switches them on)
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
	check(kinds.size() == 9, "showcase draws all nine hazard kinds")
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
	print("3. balloon (steady): constant speeds, ground, exact wind, edges")
	m.start_flight(0)
	clear_sky(m)
	var b = m.balloon
	check(b.scheme == BalloonS.STEADY and b.on_ground and is_equal_approx(b.position.y, b.floor_y()), "starts resting on the ground")
	check(is_equal_approx(b.position.x, LanesS.W * 0.5), "...in the middle")
	step(m, 0.1, 1)
	check(absf(b.rise - tn.steady_climb_speed) < 2.0 and b.burning, "no spool-up: the climb speed is constant from the first moment (%.0f px/s)" % b.rise)
	var y_a: float = b.position.y
	step(m, 1.0, 1)
	check(absf((y_a - b.position.y) - tn.steady_climb_speed) < 2.0, "holding rises exactly steady_climb_speed per second")
	step(m, 0.02, 0)
	check(absf(b.rise + tn.steady_sink_speed) < 2.0 and not b.burning, "released: sinks at once at steady_sink_speed, no coasting (%.0f px/s)" % b.rise)
	var y_s: float = b.position.y
	step(m, 1.0, 0)
	check(absf((b.position.y - y_s) - tn.steady_sink_speed) < 2.0, "sink distance matches steady_sink_speed")
	step(m, 30.0, 0)
	check(b.on_ground and is_equal_approx(b.position.y, b.floor_y()), "sinks back to the ground and stops there")
	check(absf(b.vx) < 0.01, "tethered on the ground: no drift")
	# Wind: the balloon's sideways speed is EXACTLY its layer's wind (blending only when it changes layer).
	var lanes = m.lanes
	m.start_flight(0)
	clear_sky(m)
	b = m.balloon
	b.scheme = BalloonS.DRAG
	lanes.lane_wind[2] = 150.0
	lanes.lane_wind[3] = -200.0
	var cy2: float = LanesS.BAND_BOTTOM - 2.5 * lanes.lane_h
	var x0: float = b.position.x
	b.set_altitude(cy2)
	var vmid := 0.0
	for i in 8:   # 0.13 s: still blending from rest
		b.step(1.0 / 60.0, false, true)
		vmid = b.vx
	check(vmid > 0.0 and vmid < 150.0, "a layer change blends the wind in (vx %.0f after 0.13 s)" % vmid)
	for i in 30:
		b.step(1.0 / 60.0, false, true)
	check(b.vx == 150.0, "...then the sideways speed IS the layer's wind exactly (%.3f)" % b.vx)
	var xs3: float = b.position.x
	for i in 60:
		b.step(1.0 / 60.0, false, true)
	check(absf((b.position.x - xs3) - 150.0) < 0.01, "1 s in the layer moves exactly 150 px")
	check(absf(b.position.y - cy2) < 0.5, "(drag scheme holds its altitude when the finger rests)")
	var cy3: float = LanesS.BAND_BOTTOM - 3.5 * lanes.lane_h
	b.set_altitude(cy3)
	b.drag_target = cy3
	check(lanes.lane_of(cy3) == 3 and lanes.wind_at(cy3) < 0.0, "layer lookup by height")
	for i in 60:
		b.step(1.0 / 60.0, false, true)
	check(b.vx == -200.0, "a layer blowing the other way reverses the drift exactly (vx %.0f)" % b.vx)
	# Edges
	var half: float = BalloonS.WIDTH * 0.5 * b.s()
	tn.edge_wrap = true
	b.position.x = -half + 1.0
	b.step(1.0 / 30.0, false, true)
	check(b.position.x > LanesS.W * 0.9, "edges wrap: leaves left, returns on the right")
	tn.edge_wrap = false
	b.position.x = half + 1.0
	b.vx = -200.0
	b.step(1.0 / 30.0, false, true)
	check(is_equal_approx(b.position.x, half) and b.vx >= 0.0, "edges block when edge_wrap is off")
	tn.edge_wrap = true
	b.scheme = BalloonS.STEADY

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
	check(is_equal_approx(m.fuel, tn.propane_start), "no climbing, no drain")
	step(m, 1.0, 1)
	var want_burn: float = tn.steady_climb_speed * tn.climb_burn_per_100px / 100.0
	check(absf(m.fuel - (tn.propane_start - want_burn)) < 0.3, "climbing burns climb_burn_per_100px per 100 px (%.1f used)" % (tn.propane_start - m.fuel))
	m.fuel = 2.0
	b.set_altitude(LanesS.BAND_BOTTOM - 2.5 * m.lanes.lane_h)
	step(m, 1.5, 1)
	check(m.fuel == 0.0 and not b.burning, "empty tank: the climb stops")
	check(m.screen == MainS.SCREEN_PLAY and b.rise < 0.0, "...and the balloon sinks")
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
				# (a coin whose gap is off the screen is held at the screen's edge: hazards move on, coins hang still)
				var edge: bool = m.lanes.cn_x[i] <= LanesS.ITEM_MIN_X + 0.01 or m.lanes.cn_x[i] >= LanesS.W - LanesS.ITEM_MIN_X - 0.01
				if dx3 < float(LanesS.KIND_HX[k3]) * m.lanes.lane_scale[i] + 20.0 and not edge:
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
	# Alps: strong but STEADY winds (no random gusts anywhere).
	m.lanes.setup(5.0, false, 11, 1)
	var calm_w: Array = []
	for i in m.lanes.n_lanes:
		calm_w.append(m.lanes.lane_wind[i])
	var steady_all := true
	for i in 400:
		m.lanes.update(0.1)
		for j in m.lanes.n_lanes:
			if m.lanes.lane_rev[j] == 0.0 and m.lanes.lane_wind[j] != calm_w[j]:
				steady_all = false
	check(steady_all, "Alps: every layer's wind is constant over 40 s (no gusts)")
	var alps_mag := 0.0
	var plain_mag := 0.0
	for seed_i in 30:
		m.lanes.setup(5.0, false, 300 + seed_i, 1)
		alps_mag += absf(m.lanes.lane_base[2])
		m.lanes.setup(5.0, false, 300 + seed_i, 0)
		plain_mag += absf(m.lanes.lane_base[2])
	check(alps_mag > plain_mag, "...the Alps are simply windier")
	m.lanes.setup(2.0, false, 11, 0)
	var w0: float = m.lanes.lane_wind[2]
	for i in 100:
		m.lanes.update(0.1)
	check(m.lanes.lane_wind[2] == w0, "Countryside winds are steady")
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
	b1.scheme = BalloonS.STEADY
	for pass_i in 2:
		b1.reset()
		b1.set_altitude(900.0)
		b1.step(1.0 / 60.0, false, true, 0.0 if pass_i == 0 else tn.thermal_lift)
		if pass_i == 0:
			rise_no = b1.rise
		else:
			rise_yes = b1.rise
	check(rise_yes > rise_no + tn.thermal_lift * 0.95, "inside a thermal the balloon is lifted for free (%.0f vs %.0f px/s)" % [rise_yes, rise_no])
	check(b1.climbed_px == 0.0, "...and a thermal's lift costs no propane")
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
	b1.reset()
	b1.climbed_px = 100.0
	var cost_full: float = b1.take_fuel_cost(1.0)
	b1.climbed_px = 100.0
	var cost_thin: float = b1.take_fuel_cost(1.0 - tn.thin_air_loss)
	check(absf(cost_full - tn.climb_burn_per_100px) < 0.01 and cost_thin > cost_full * 1.5, "thin air makes climbing cost more propane (%.1f vs %.1f per 100 px)" % [cost_thin, cost_full])
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
			m.lanes.setup(FlightsS.eff_level(rr, FlightsS.index_of(fid), l), false, FlightsS.leg_seed(FlightsS.seed_of(fid), l), rr, FlightsS.leg_recipe(fid, l, FlightsS.leg_seed(FlightsS.seed_of(fid), l)))
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
	win_flight(m, 5, 9, 60.0)
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
	check(v1["seen_regions"].size() == 4 and v1["seen_regions"][0] == true and v1["last_flight"] == 0 and v1["coins"] == 9 and v1["version"] == sv.VERSION, "a v1 save is migrated to the current version")
	m._show_map()

	# ---- 6d. postcards ----
	print("6d. postcards")
	sv.reset_all()
	check(sv.postcard_of(0) == 0 and sv.postcard_of(3) == 0, "no postcards at first")
	win_flight(m, 2, 0, 5.0)
	check(m.screen == MainS.SCREEN_RESULT and sv.postcard_of(0) == 0 and not m.hud.card_p.visible, "a Flight in the middle of a region earns no postcard")
	win_flight(m, 5, 0, 5.0)
	check(m.last_stars == 1 and sv.postcard_of(0) == 1, "completing a region's last Flight awards its postcard")
	check(m.hud.card_p.visible and m.hud.card_header.text == "NEW POSTCARD!" and m.hud.card_view.region == 0 and m.hud.card_view.state == 1, "the award screen shows the new postcard")
	check(m.hud.card_view.title.text == "Greetings from the Countryside", "...with its title")
	m.hud.card_p.get_child(m.hud.card_p.get_child_count() - 1).pressed.emit()
	check(not m.hud.card_p.visible and m.hud.result_p.visible, "CONTINUE returns to the result screen")
	win_flight(m, 5, 0, 5.0)
	check(m.last_postcard.is_empty() and not m.hud.card_p.visible and sv.postcard_of(0) == 1, "replaying does not award it again")
	sv.reset_all()
	m.start_flight(5)
	m.fuel = 0.0
	step(m, 60.0, 1)
	check(m.screen == MainS.SCREEN_DEAD and sv.postcard_of(0) == 0, "failing the last Flight earns nothing")
	sv.reset_all()
	for i in 5:
		sv.data["stars"][i] = 3
	win_flight(m, 5, 9, 60.0)
	check(m.last_stars == 3 and sv.postcard_of(0) == 2 and m.hud.card_header.text == "GOLD POSTCARD!" and m.hud.card_view.state == 2, "3 stars on every Flight of a region: the gold postcard")
	sv.reset_all()
	for i in 5:
		sv.data["stars"][i] = 3
	sv.data["stars"][5] = 2
	sv.data["postcards"][0] = 1
	win_flight(m, 5, 9, 60.0)
	check(sv.postcard_of(0) == 2 and m.last_postcard == [0, 2], "improving the last Flight to 3 stars upgrades the postcard to gold")
	sv.reset_all()
	for i in 6:
		sv.data["stars"][6 + i] = 1
	win_flight(m, 11, 0, 5.0)
	check(sv.postcard_of(1) == 1 and sv.postcard_of(0) == 0 and m.hud.card_view.region == 1, "each region has its own postcard (Alps)")
	sv.reset_all()
	sv.three_star_everything()
	check(sv.postcard_of(0) == 2 and sv.postcard_of(1) == 2 and sv.postcard_of(2) == 2 and sv.postcard_of(3) == 2, "debug 3-star everything: all four gold")
	# The album.
	sv.reset_all()
	sv.data["postcards"] = [2, 1, 0, 0]
	m._show_map()
	check(not m.hud.gauge.visible and not m.hud.prog.visible and not m.hud.score_label.visible, "no flight readouts on the map")
	check(m.hud.map.album_btn.text == "ALBUM 2/4", "the map's album button counts postcards")
	var snap_a := snap()
	m.hud.map.album_btn.pressed.emit()
	var al = m.hud.album
	check(m.screen == MainS.SCREEN_ALBUM and al.visible and not m.hud.map.visible, "ALBUM opens the album from the map")
	check(al.views[0].state == 2 and al.views[1].state == 1 and al.views[2].state == 0, "gold, normal and not-yet-earned slots")
	check(al.views[0].title.text.contains("Countryside") and al.views[2].title.text == "???" and al.views[2].hint.text.contains("Sahara"), "titles and hints")
	check(al.captions[1].text.contains("0/6") and al.captions[0].text == "GOLD postcard" and al.count_label.text == "2 / 4 postcards    1 gold", "captions show progress to gold")
	al._zoom(2)
	check(not al.zoom_p.visible, "an unearned slot does not open")
	al.views[1].tapped.emit()
	check(al.zoom_p.visible and al.zoom_view.region == 1 and al.zoom_view.state == 1, "tapping a postcard shows it large")
	al.refresh()
	check(not al.zoom_p.visible, "refresh closes the zoom")
	al.back_pressed.emit()
	check(m.screen == MainS.SCREEN_MAP and not al.visible and m.hud.map.visible, "BACK returns to the map")
	m.hud.map.album_btn.pressed.emit()
	al.views[0].tapped.emit()
	m.hud.album_closed.emit()
	await process_frame
	check(same(snap_a, snap()), "opening and closing the album allocates nothing")
	var titles := {}
	for r in 4:
		al.views[0].set_card(r, 1)
		titles[al.views[0].title.text] = true
	check(titles.size() == 4, "four different postcards")
	check(sv._migrate({"version": 2, "coins": 3})["postcards"] == [0, 0, 0, 0], "a v2 save gets an empty album")
	sv.reset_all()
	m._show_map()

	# ---- 6e. cosmetics ----
	print("6e. cosmetics")
	var CosS = load("res://scripts/Cosmetics.gd")
	var BArtS = load("res://scripts/BalloonArt.gd")
	check(CosS.ENV_NAMES.size() == CosS.ENV_PRICE.size() and CosS.ENV_NAMES.size() == CosS.ENV_C1.size() and CosS.ENV_NAMES.size() == CosS.ENV_SHAPE.size() and CosS.ENV_NAMES.size() == CosS.ENV_PATTERN.size(), "envelope tables line up")
	check(CosS.BASKET_NAMES.size() == CosS.BASKET_PRICE.size() and CosS.PASSENGER_NAMES.size() == CosS.PASSENGER_PRICE.size(), "basket and passenger tables line up")
	var looks := {}
	for i in CosS.ENV_NAMES.size():
		if CosS.ENV_SHAPE[i] == 0:
			looks["%d %s %s" % [CosS.ENV_PATTERN[i], CosS.ENV_C1[i].to_html(), CosS.ENV_C2[i].to_html()]] = true
	check(looks.size() >= 10, "at least 10 envelope patterns / colours (%d)" % looks.size())
	check(CosS.ENV_NAMES.slice(11) == ["Cat", "Hot Dog", "Fish"] and CosS.ENV_SHAPE.slice(11) == [1, 2, 3], "three novelty envelope shapes: cat head, hot dog, fish")
	check(CosS.BASKET_NAMES.size() >= 5, "at least 5 basket styles (%d)" % CosS.BASKET_NAMES.size())
	check(CosS.PASSENGER_NAMES.slice(1) == ["Cat", "Dog", "Fox", "Owl", "Raccoon"], "five animal passengers")
	check(CosS.ENV_PRICE[0] == 0 and CosS.BASKET_PRICE[0] == 0 and CosS.PASSENGER_PRICE[0] == 0, "item 0 of each category is free")
	var cheapest := 99999
	var total := 0
	var all_pos := true
	for cat in 3:
		for i in range(1, CosS.count(cat)):
			var pr: int = CosS.price(cat, i)
			cheapest = mini(cheapest, pr)
			total += pr
			all_pos = all_pos and pr > 0
	var flight_coins: float = CosS.typical_flight_coins()
	check(all_pos and cheapest <= 2.0 * flight_coins and cheapest > 0.5 * flight_coins, "the first cosmetic is affordable after about 2 Flights (%d coins vs ~%d per Flight)" % [cheapest, int(flight_coins)])
	check(float(total) >= 40.0 * flight_coins, "the full set takes many sessions (%d coins = ~%d Flights)" % [total, int(float(total) / flight_coins)])
	# Buying and equipping.
	sv.reset_all()
	check(sv.owns(0, 0) and sv.owns(1, 0) and sv.owns(2, 0) and not sv.owns(0, 1) and sv.equipped(0) == 0, "only the defaults are owned at first")
	check(not sv.buy(0, 1) and sv.coins == 0, "cannot buy without the coins")
	sv.add_coins(1000)
	check(sv.buy(0, 1) and sv.owns(0, 1) and sv.equipped(0) == 1 and sv.coins == 1000 - CosS.ENV_PRICE[1], "buying spends the coins and equips it")
	check(not sv.buy(0, 1) and sv.coins == 1000 - CosS.ENV_PRICE[1], "cannot buy twice")
	check(not sv.equip(0, 2) and sv.equipped(0) == 1, "cannot equip what you do not own")
	check(sv.equip(0, 0) and sv.equipped(0) == 0 and sv.equip(0, 1) and sv.equipped(0) == 1, "equip switches between owned items")
	check(not sv.buy(0, 99) and not sv.buy(5 - 3, -1), "bad indices are refused")
	sv.persist = true
	sv.reset_all()
	sv.add_coins(900)
	sv.buy(1, 3)
	sv.buy(2, 4)
	sv.data = sv._defaults()
	sv._load()
	check(sv.owns(1, 3) and sv.equipped(1) == 3 and sv.owns(2, 4) and sv.equipped(2) == 4 and not sv.owns(1, 2), "owned and equipped items survive a round trip")
	var mig: Dictionary = sv._migrate({"version": 3, "coins": 10, "equipped": [5, 9, 0], "owned": [[true, false]]})
	check(mig["owned"][0].size() == CosS.count(0) and mig["owned"][1].size() == CosS.count(1) and mig["equipped"] == [0, 0, 0] and mig["owned"][2][0] == true, "a v3 save gets the new fields; unowned / invalid equipped items fall back to the default")
	sv.reset_all()
	sv.persist = false
	# Cosmetics are purely visual.
	sv.add_coins(5000)
	m.start_flight(0)
	var ref_pos: Array[Vector2] = []
	var ref_rad: Array[float] = []
	var rise_ref := 0.0
	for pass_i in 2:
		if pass_i == 1:
			sv.buy(0, 11)
			sv.buy(1, 3)
			sv.buy(2, 4)
		m.start_flight(0)
		clear_sky(m)
		check(m.balloon.env_id == sv.equipped(0) and m.balloon.basket_id == sv.equipped(1) and m.balloon.pass_id == sv.equipped(2), "the balloon wears what is equipped")
		step(m, 3.0, 1)
		if pass_i == 0:
			rise_ref = m.balloon.rise
			for c in 3:
				ref_pos.append(m.balloon.hit_pos(c))
				ref_rad.append(m.balloon.hit_radius(c))
		else:
			var same_hit := true
			for c in 3:
				same_hit = same_hit and m.balloon.hit_pos(c).is_equal_approx(ref_pos[c]) and is_equal_approx(m.balloon.hit_radius(c), ref_rad[c])
			check(m.balloon.env_id == 11 and m.balloon.basket_id == 3 and m.balloon.pass_id == 4, "cat envelope, gondola and owl are on the balloon")
			check(same_hit and is_equal_approx(m.balloon.rise, rise_ref), "...and change nothing about hit circles or flight")
	# Every envelope, basket and passenger draws (under real frames).
	m.set_process(true)
	for e in CosS.count(0):
		m.balloon.env_id = e
		m.balloon.heat = 0.8
		m.balloon.queue_redraw()
		await process_frame
	for bk in CosS.count(1):
		m.balloon.basket_id = bk
		m.balloon.queue_redraw()
		await process_frame
	for ps in CosS.count(2):
		m.balloon.pass_id = ps
		m.balloon.queue_redraw()
		await process_frame
	m.set_process(false)
	check(true, "all %d envelopes, %d baskets and %d passengers draw without errors" % [CosS.count(0), CosS.count(1), CosS.count(2)])
	# The shop.
	sv.reset_all()
	sv.add_coins(400)
	m._show_map()
	var shop = m.hud.shop
	var base_s := snap()
	m.hud.map.shop_btn.pressed.emit()
	check(m.screen == MainS.SCREEN_SHOP and shop.visible and not m.hud.map.visible and not m.hud.gauge.visible, "SHOP opens from the map")
	check(shop.coins_label.text == "coins 400" and shop.category == 0, "shows the coins; envelopes first")
	var vis := 0
	for sl in shop.slots:
		vis += 1 if sl.visible else 0
	check(vis == CosS.count(0), "one slot per envelope (%d)" % vis)
	shop._set_category(1)
	vis = 0
	for sl in shop.slots:
		vis += 1 if sl.visible else 0
	check(vis == CosS.count(1) and shop.tabs[1].disabled and not shop.tabs[0].disabled, "baskets tab shows the baskets")
	shop._set_category(0)
	shop._select(11)
	check(shop.preview_ids() == [11, 0, 0], "the preview tries the selected item on")
	check(shop.action_btn.text == "BUY  900" and shop.action_btn.disabled, "too expensive: BUY is disabled")
	shop._select(1)
	check(shop.action_btn.text == "BUY  150" and not shop.action_btn.disabled and shop.slot_prices[1].text == "150", "affordable: BUY is enabled")
	var changed_n := 0
	m.hud.cosmetics_changed.connect(func(): changed_n += 0)
	shop.action_btn.pressed.emit()
	check(sv.owns(0, 1) and sv.equipped(0) == 1 and sv.coins == 250 and shop.action_btn.text == "EQUIPPED" and shop.action_btn.disabled, "BUY buys and equips (250 coins left)")
	check(shop.slot_prices[1].text == "EQUIPPED" and shop.slot_prices[0].text == "owned", "slots show owned / equipped")
	shop._select(0)
	check(shop.action_btn.text == "EQUIP" and not shop.action_btn.disabled, "an owned item offers EQUIP")
	shop.action_btn.pressed.emit()
	check(sv.equipped(0) == 0 and sv.coins == 250, "EQUIP is free")
	shop._set_category(2)
	shop._select(1)
	shop.action_btn.pressed.emit()
	check(sv.owns(2, 1) and sv.coins == 50 and shop.preview_ids() == [0, 0, 1], "a passenger is bought; the preview shows all three equipped")
	m.hud.shop_closed.emit()
	check(m.screen == MainS.SCREEN_MAP, "BACK returns to the map")
	m.hud.map.shop_btn.pressed.emit()
	shop._set_category(1)
	shop._select(1)
	m.hud.shop_closed.emit()
	await process_frame
	check(same(base_s, snap()), "the shop allocates nothing")
	m.start_flight(0)
	check(m.balloon.pass_id == 1, "the passenger rides in the next Flight")
	sv.reset_all()
	m._show_map()

	# ---- 6f. Daily Flight ----
	print("6f. Daily Flight")
	sv.reset_all()
	FlightsS.debug_today = 20000
	check(FlightsS.today() == 20000 and FlightsS.daily_region(20000) == 0 and FlightsS.daily_region(20001) == 1 and FlightsS.daily_region(20003) == 3, "the Daily Flight's region rotates with the date")
	check(FlightsS.daily_seed(20000) != FlightsS.daily_seed(20001), "...and its seed changes every day")
	# Same date = same Flight.
	var d_sigs := []
	for pass_i in 2:
		m.hud.daily_pressed.emit()
		check(m.screen == MainS.SCREEN_MENU and m.selected == -1 and m.flight_id == -1, "DAILY opens the daily Flight screen")
		m.hud.fly_pressed.emit()
		d_sigs.append([m.flight_region, m.flight_index, m.lanes.n_lanes, Array(m.lanes.hz_x.slice(0, 20)), Array(m.lanes.lane_wind.slice(0, 9))])
	check(d_sigs[0] == d_sigs[1], "the Daily Flight is identical every time it is played that day")
	m.start_flight(-1)
	check(m.hud.level_label.text.begins_with("DAILY FLIGHT") and m.flight_region == 0 and m.eff_add == tn.daily_level_bonus, "the Daily Flight is the region's mid Flight, a little harder")
	check(m._eff(0) > FlightsS.eff_level(0, 3, 0), "...harder than the same normal Flight")
	FlightsS.debug_today = 20001
	m.start_flight(-1)
	check(m.flight_region == 1 and m.flight_seed != FlightsS.daily_seed(20000), "tomorrow it is a different Flight")
	FlightsS.debug_today = 20000
	# Completing it: bonus coins and a streak; no stars are recorded; no postcard.
	sv.reset_all()
	win_flight(m, -1, 9, 60.0)
	var base_coins: int = 5 * roundi(tn.leg_coins) + roundi(m.fuel * tn.propane_coins)
	check(m.screen == MainS.SCREEN_RESULT and m.last_daily_bonus == roundi(tn.daily_bonus_coins), "completing the Daily Flight pays the daily bonus (%d)" % m.last_daily_bonus)
	check(sv.daily_done(20000) and sv.daily_streak_now(20000) == 1 and sv.data["daily_streak"] == 1, "streak of 1")
	check(sv.coins == m.flight_coins and m.flight_coins >= base_coins + m.last_daily_bonus, "the coins (with the bonus) are paid into the save (%d)" % sv.coins)
	check(sv.total_stars() == 0 and sv.postcard_of(0) == 0 and not m.hud.card_p.visible, "no stars or postcards from the Daily Flight")
	check(m.hud.result_header.text == "DAILY FLIGHT COMPLETE!" and m.hud.result_summary.text.contains("DAILY BONUS +100") and m.hud.result_next.disabled, "the result screen shows the bonus and the streak")
	var coins_after: int = sv.coins
	win_flight(m, -1, 9, 60.0)
	check(m.last_daily_bonus == 0 and sv.daily_streak_now(20000) == 1 and m.hud.result_summary.text.contains("already claimed"), "replaying the same day pays no second bonus")
	check(sv.coins > coins_after and sv.coins < coins_after + m.flight_coins + 1, "...but the Flight's own coins still count")
	m._show_map()
	check(m.hud.map.daily_btn.text == "DAILY  done  x1", "the map shows the Daily Flight as done")
	# Streak: consecutive days grow it, a missed day resets it, the bonus grows with it (capped).
	FlightsS.debug_today = 20001
	check(sv.daily_streak_now(20001) == 1 and not sv.daily_done(20001), "the next day the streak is still alive")
	m._show_map()
	check(m.hud.map.daily_btn.text == "DAILY  streak 1", "...and the map invites you to play")
	win_flight(m, -1, 0, 5.0)
	check(sv.daily_streak_now(20001) == 2 and m.last_daily_bonus == roundi(tn.daily_bonus_coins + tn.daily_streak_bonus), "day 2: streak 2 and a bigger bonus (%d)" % m.last_daily_bonus)
	FlightsS.debug_today = 20004
	check(sv.daily_streak_now(20004) == 0, "missing a day loses the streak")
	win_flight(m, -1, 0, 5.0)
	check(sv.daily_streak_now(20004) == 1 and m.last_daily_bonus == roundi(tn.daily_bonus_coins), "...and it starts again at 1")
	var bonus_cap: int = roundi(tn.daily_bonus_coins + tn.daily_streak_bonus * (tn.daily_streak_cap - 1.0))
	var got := 0
	for dd in range(20005, 20020):
		FlightsS.debug_today = dd
		got = sv.complete_daily(dd)
	check(got == bonus_cap and sv.data["daily_streak"] == 16, "the streak bonus is capped (%d coins)" % got)
	sv.reset_daily()
	check(sv.data["daily_last"] == -1 and sv.daily_streak_now(20019) == 0 and not sv.daily_done(20019), "?tune: reset daily")
	# A failed Daily Flight is not a completion.
	FlightsS.debug_today = 20000
	sv.reset_all()
	m.start_flight(-1)
	m.fuel = 0.0
	step(m, 60.0, 1)
	check(m.screen == MainS.SCREEN_DEAD and not sv.daily_done(20000), "failing the Daily Flight does not complete it")
	check(sv._migrate({"version": 4})["daily_last"] == -1 and sv._migrate({"version": 4})["ad_counter"] == 0, "a v4 save gets the daily and ad fields")
	FlightsS.debug_today = -1
	sv.reset_all()
	m._show_map()

	# ---- 6g. ads (stubs) ----
	print("6g. ads")
	tn.ads_enabled = true
	tn.ad_fake_seconds = 0.0
	sv.reset_all()
	m.start_flight(0)
	clear_sky(m)
	# Rewarded: +50% propane at the start of a leg.
	check(not m.hud.boost_btn.visible, "no boost offered with a full tank")
	m.fuel = 40.0
	step(m, 0.05, 0)
	check(m.hud.boost_btn.visible and m.balloon.on_ground and not m.leg_started, "+50% propane is offered on the ground at the start of a leg when the tank is low")
	var shown0: int = m.ads.shown
	m.hud.boost_pressed.emit()
	check(m.hud.ad_active and m.ads.last_kind == "boost" and m.hud.ad_p.visible and m.hud.ad_sub.text.contains("+50% propane"), "the fake 'Ad playing' screen comes up")
	var y_frozen: float = m.balloon.position.y
	var t_frozen: float = m.sim_time
	step(m, 1.0, 1)
	check(m.balloon.position.y == y_frozen and m.sim_time == t_frozen, "the world stands still while an ad is up")
	m.hud.ad_cancel.pressed.emit()
	check(not m.hud.ad_active and m.fuel == 40.0 and m.boosts_used == 0, "NO THANKS: no reward")
	m.hud.boost_pressed.emit()
	m.hud.ad_claim.pressed.emit()
	check(is_equal_approx(m.fuel, 40.0 + tn.propane_start * tn.ad_boost_frac) and m.boosts_used == 1 and m.ads.shown == shown0 + 2, "CLAIM: +50%% of the tank (%.0f)" % m.fuel)
	m.fuel = 90.0
	step(m, 0.05, 0)
	check(not m.hud.boost_btn.visible, "no boost button when the tank is nearly full")
	m.fuel = 30.0
	m.boosts_used = 2
	step(m, 0.05, 0)
	check(not m.hud.boost_btn.visible, "at most %d boosts per Flight" % int(tn.ad_boost_max_per_flight))
	m.boosts_used = 0
	step(m, 1.0, 1)
	check(m.leg_started and not m.hud.boost_btn.visible, "the boost is only offered before lift-off")
	# Rewarded: retry the leg.
	m.start_flight(0)
	clear_sky(m)
	m.fuel = 70.0
	m.flight_coins = 25
	m.coins_picked = 2
	m.score = 150
	m.leg = 2
	m._begin_leg()
	var leg_fuel: float = m.fuel
	clear_sky(m)
	m.lanes.lane_kind[2] = 1
	m.lanes.lane_count[2] = 1
	m.lanes.lane_scale[2] = 1.0
	m.lanes.lane_amp[2] = 0.0
	m.lanes.lane_vel[2] = 0.0
	m.balloon.position = Vector2(300.0, LanesS.BAND_BOTTOM - 2.5 * m.lanes.lane_h)
	m.balloon.on_ground = false
	m.lanes.hz_x[2 * LanesS.MAX_PER_LANE] = 300.0
	m.flight_coins = 60
	m.coins_picked = 4
	m.score = 400
	m.fuel = 20.0
	var coins_before_fail: int = sv.coins
	step(m, 0.1, 0)
	check(m.screen == MainS.SCREEN_DEAD and m.hud.retry_btn.visible, "after a failed leg: RETRY THIS LEG (AD) is offered")
	check(sv.coins == coins_before_fail + 60, "the coins earned so far are paid when the Flight ends")
	m.hud.retry_pressed.emit()
	check(m.hud.ad_active and m.ads.last_kind == "retry", "the retry plays a rewarded ad")
	m.hud.ad_cancel.pressed.emit()
	check(m.screen == MainS.SCREEN_DEAD and m.hud.dead_p.visible and m.retries_used == 0, "backing out of the ad leaves the failed screen")
	m.hud.retry_pressed.emit()
	m.hud.ad_claim.pressed.emit()
	check(m.screen == MainS.SCREEN_PLAY and m.leg == 2 and m.retries_used == 1, "CLAIM: the same leg starts again")
	check(is_equal_approx(m.fuel, leg_fuel) and m.flight_coins == 25 and m.coins_picked == 2 and m.score == 150, "...with the propane, coins and score it had at the start of the leg")
	check(m.balloon.on_ground and m.balloon.visible and not m.hud.dead_p.visible, "...balloon back on the ground")
	# The retried leg is the very same leg.
	var sig_leg := [m.lanes.n_lanes, Array(m.lanes.hz_x.slice(0, 20))]
	m.lanes.setup(m._eff(2), false, FlightsS.leg_seed(m.flight_seed, 2), m.flight_region, m.recipe)
	check(sig_leg == [m.lanes.n_lanes, Array(m.lanes.hz_x.slice(0, 20))], "(it is the identical layout)")
	# Retried coins are not paid twice: finish the Flight with the coins re-earned.
	m.flight_coins = 25
	m.credited = 60
	m.flight_coins = 55
	m._credit()
	check(sv.coins == coins_before_fail + 60 and m.credited == 60, "coins already paid are not paid again after a retry")
	m.flight_coins = 75
	m._credit()
	check(sv.coins == coins_before_fail + 75, "...only what goes beyond is")
	# One retry per Flight.
	clear_sky(m)
	m.lanes.lane_kind[2] = 1
	m.lanes.lane_count[2] = 1
	m.lanes.lane_scale[2] = 1.0
	m.lanes.lane_amp[2] = 0.0
	m.lanes.lane_vel[2] = 0.0
	m.balloon.position = Vector2(300.0, LanesS.BAND_BOTTOM - 2.5 * m.lanes.lane_h)
	m.balloon.on_ground = false
	m.lanes.hz_x[2 * LanesS.MAX_PER_LANE] = 300.0
	step(m, 0.1, 0)
	check(m.screen == MainS.SCREEN_DEAD and not m.hud.retry_btn.visible, "only %d retry per Flight" % int(tn.ad_retry_max_per_flight))
	# Interstitial: only between Flights, once every few Flights.
	sv.reset_all()
	var ads_seen: int = m.ads.shown
	var interstitials := 0
	var started := 0
	for n in 9:
		m.start_flight(0)
		started += 1
		clear_sky(m)
		m.fuel = 100.0
		step(m, 1.0, 0)   # (play on the ground; nothing may interrupt it)
		check(not m.hud.ad_active, "no ad during play (Flight %d)" % (n + 1))
		m.fuel = 0.0
		step(m, 60.0, 1)
		check(m.screen == MainS.SCREEN_DEAD, "Flight %d ended" % (n + 1))
		var before: int = m.ads.shown
		m.hud.again_pressed.emit()
		if m.ads.shown > before:
			interstitials += 1
			check(m.ads.last_kind == "interstitial" and m.hud.ad_active and not m.hud.ad_cancel.visible, "the interstitial plays (after Flight %d)" % (n + 1))
			check(m.screen == MainS.SCREEN_DEAD, "...before the next Flight starts")
			m.hud.ad_claim.pressed.emit()
			check(m.screen == MainS.SCREEN_PLAY and not m.hud.ad_active, "closing it starts the next Flight")
	check(interstitials == 3, "9 Flights: none in the first 2, then after Flights 3, 6 and 9 (%d)" % interstitials)
	# Never from the Flight screen or during play.
	sv.data["ad_counter"] = 99
	sv.data["flights_ended"] = 99
	m.start_flight(0)
	var before2: int = m.ads.shown
	m._proceed(func(): pass)
	check(m.ads.shown == before2, "_proceed outside the result / failed screens never shows an ad")
	m.hud.flight_chosen.emit(0)
	m.hud.fly_pressed.emit()
	check(m.ads.shown == before2 and m.screen == MainS.SCREEN_PLAY, "starting a Flight from its screen never shows an ad")
	# A finished Flight counts too, and the result buttons go through the interstitial as well.
	sv.data["ad_counter"] = 2
	win_flight(m, 0, 0, 5.0)
	check(m.screen == MainS.SCREEN_RESULT and sv.interstitial_due(), "finishing a Flight also counts toward the interstitial")
	m.hud.menu_pressed.emit()
	check(m.hud.ad_active and m.ads.last_kind == "interstitial" and m.screen == MainS.SCREEN_RESULT, "MAP from the result screen plays it first")
	m.hud.ad_claim.pressed.emit()
	check(m.screen == MainS.SCREEN_MAP and not sv.interstitial_due(), "...then goes to the map")
	# The fake ad plays for ad_fake_seconds before it can be claimed.
	tn.ad_fake_seconds = 2.0
	m.start_flight(0)
	clear_sky(m)
	m.fuel = 30.0
	step(m, 0.05, 0)
	m.hud.boost_pressed.emit()
	check(m.hud.ad_active and m.hud.ad_claim.disabled and m.hud.ad_cancel.visible, "the claim button waits for the fake ad to finish")
	m.hud._process(1.0)
	check(m.hud.ad_claim.disabled and m.hud.ad_count.text == "1", "(counting down)")
	m.hud._process(1.5)
	check(not m.hud.ad_claim.disabled, "...and opens when it is over")
	m.hud.ad_claim.pressed.emit()
	# ads_enabled = false: no offers at all.
	tn.ads_enabled = false
	tn.ad_fake_seconds = 0.0
	m.start_flight(0)
	clear_sky(m)
	m.fuel = 30.0
	step(m, 0.05, 0)
	check(not m.hud.boost_btn.visible, "ads off: no boost offer")
	m.fuel = 0.0
	step(m, 60.0, 1)
	check(m.screen == MainS.SCREEN_DEAD and not m.hud.retry_btn.visible, "ads off: no retry offer")
	sv.data["ad_counter"] = 99
	sv.data["flights_ended"] = 99
	check(not sv.interstitial_due(), "ads off: no interstitial")
	tn.ads_enabled = false
	sv.reset_all()
	m._show_map()

	# ---- 6h. performance structure ----
	print("6h. performance structure")
	var LRS = load("res://scripts/LaneRender.gd")
	# Hard caps on everything that scales with the level, across every Flight of the world.
	var over_cap := 0
	var max_haz := 0
	var max_total := 0
	for fid in 24:
		var rr2: int = FlightsS.region_of(fid)
		for l in 5:
			m.lanes.setup(FlightsS.eff_level(rr2, FlightsS.index_of(fid), l), false, FlightsS.leg_seed(FlightsS.seed_of(fid), l), rr2, FlightsS.leg_recipe(fid, l, FlightsS.leg_seed(FlightsS.seed_of(fid), l)))
			var sky_total := 0
			for i in m.lanes.n_lanes:
				max_haz = maxi(max_haz, m.lanes.lane_count[i])
				sky_total += m.lanes.lane_count[i]
				if m.lanes.lane_count[i] > LanesS.MAX_PER_LANE:
					over_cap += 1
			max_total = maxi(max_total, sky_total)
			var rd = m.lanes.render
			if rd._streaks.multimesh.visible_instance_count > m.lanes.n_lanes * LanesS.PARTS_PER_LANE or rd._streamers.multimesh.visible_instance_count > m.lanes.n_lanes * LanesS.STREAMERS_PER_LANE or rd._chevs.multimesh.visible_instance_count > m.lanes.n_lanes * LanesS.CHEVRONS_PER_LANE:
				over_cap += 1
	check(over_cap == 0 and max_haz <= 4 and max_total <= LanesS.MAX_HAZ, "hard caps hold in every Flight: at most %d hazards per layer, %d in the sky (cap %d)" % [max_haz, max_total, LanesS.MAX_HAZ])
	check(LanesS.PARTS_PER_LANE <= 8 and LanesS.STREAMERS_PER_LANE <= 1 and LanesS.CHEVRONS_PER_LANE <= 4 and LanesS.FX_MAX <= 24, "wind streaks (8), chevrons (4), streamers (1) per layer and sparks (24) are capped")
	check(tn.density_max <= 3.5 and tn.wind_max <= 180.0 and tn.jet_wind <= 260.0, "density and wind speed are capped at moderate values")
	# The MultiMesh buffers mirror the simulation.
	m.lanes.setup(FlightsS.eff_level(1, 5, 4), false, 4242, 1)
	m.lanes.update(1.0 / 60.0)
	var rnd = m.lanes.render
	var mirrored := true
	var hz_total := 0
	for i in m.lanes.n_lanes:
		for j in m.lanes.lane_count[i]:
			var hidx: int = i * LanesS.MAX_PER_LANE + j
			var buf: PackedFloat32Array = rnd._hz_buf[rnd._hz_mesh[hidx]]
			var bb: int = rnd._hz_slot[hidx] * LRS.HZ_STRIDE
			mirrored = mirrored and is_equal_approx(buf[bb + 3], m.lanes.hz_x[hidx]) and is_equal_approx(buf[bb + 7], m.lanes.hz_y[hidx])
			hz_total += 1
	var inst := 0
	for mi in 11:
		inst += rnd._hz_n[mi]
	check(mirrored and inst == hz_total, "every hazard has exactly one MultiMesh instance, positioned where the simulation says (%d)" % hz_total)
	var kinds_used := {}
	for mi in 11:
		if rnd._hz_n[mi] > 0:
			kinds_used[mi] = true
	check(kinds_used.size() <= 4, "a leg draws with at most four hazard meshes (one MultiMesh each)")
	# Static things are drawn once per leg, not per frame; the balloon body only when it changes; sparks only while alive.
	m.start_flight(0)
	clear_sky(m)
	m.set_process(true)
	await real_wait(0.3)
	m.set_process(false)
	var bd_draws: int = m.lanes.render.backdrop.draws
	var body_draws: int = m.balloon.body_draws
	var fx_draws: int = m.lanes.render.fx.draws
	m.set_process(true)
	m.burn_override = 1
	await real_wait(1.0)
	m.set_process(false)
	m.burn_override = 0
	check(m.lanes.render.backdrop.draws == bd_draws and m.balloon.body_draws == body_draws and m.lanes.render.fx.draws == fx_draws, "no per-frame redraw of the backdrop, the balloon body or the sparks while flying")
	m.lanes.burst(Vector2(500, 900), Color.RED, 8, 200.0)
	m.lanes.update(1.0 / 60.0)
	m.set_process(true)
	await real_wait(0.2)
	m.set_process(false)
	check(m.lanes.render.fx.draws > fx_draws, "...but sparks do draw while some are alive")
	m.lanes.clear_fx()
	m.start_flight(0)
	var bd2: int = m.lanes.render.backdrop.draws
	m.start_flight(0)
	await process_frame
	await process_frame
	check(m.lanes.render.backdrop.draws > bd2 - 1, "the backdrop is redrawn when a leg starts")
	m.set_process(false)

	# ---- 6i. curriculum: goal types mixed within Flights, one new idea at a time ----
	print("6i. curriculum and recipes")
	var cur: Array = FlightsS.CURRICULUM
	var idea_set := {}
	for f in 24:
		if cur[f] != "":
			idea_set[cur[f]] = true
	var order_set := {}
	for idea in FlightsS.IDEA_ORDER:
		order_set[idea] = true
	check(cur.size() == 24 and idea_set.keys().size() == order_set.keys().size() and idea_set.keys().all(func(k): return order_set.has(k)), "the curriculum gives every Flight at most ONE new idea (one entry per Flight, %d ideas in all)" % idea_set.keys().size())
	check(cur[0] == "climb" and cur[6] == "region" and cur[12] == "region" and cur[18] == "region" and cur[7] == "sandbag" and cur[13] == "anchor" and cur[19] == "vent", "regions bring their mechanic first and their tool in their second Flight")
	var bad_avail := 0
	var goal_sets := {}
	var min_distinct := 99
	var twists_max := 0
	var storm_lightning := 0
	var not_det := 0
	var intro_missing: Array[String] = []
	for fid in 24:
		var goals_seen := {}
		var has := {"stars": false, "delivery": false, "storm": false, "landing": false, "kitebeat": false, "reverse": false, "geese": false, "lightning": false}
		for l in 5:
			var sd: int = FlightsS.leg_seed(FlightsS.seed_of(fid), l)
			var rc = FlightsS.leg_recipe(fid, l, sd)
			var rc2 = FlightsS.leg_recipe(fid, l, sd)
			if rc.goal != rc2.goal or rc.kite_beat != rc2.kite_beat or rc.geese != rc2.geese or rc.reverse != rc2.reverse or rc.lightning != rc2.lightning:
				not_det += 1
			goals_seen[rc.goal] = true
			match rc.goal:
				1:
					has["stars"] = true
					bad_avail += 0 if FlightsS.idea_available("stars", fid) else 1
				2:
					has["delivery"] = true
					bad_avail += 0 if FlightsS.idea_available("delivery", fid) else 1
				3:
					has["storm"] = true
					bad_avail += 0 if FlightsS.idea_available("storm", fid) else 1
					if rc.lightning:
						storm_lightning += 1
				4:
					has["landing"] = true
					bad_avail += 0 if FlightsS.idea_available("landing", fid) else 1
			for pair in [["kitebeat", rc.kite_beat], ["reverse", rc.reverse], ["geese", rc.geese], ["lightning", rc.lightning]]:
				if pair[1]:
					has[pair[0]] = true
					bad_avail += 0 if FlightsS.idea_available(pair[0], fid) else 1
			twists_max = maxi(twists_max, rc.twist_count())
		min_distinct = mini(min_distinct, goals_seen.size()) if fid >= 5 else min_distinct
		if cur[fid] in ["stars", "delivery", "storm", "landing", "kitebeat", "reverse", "geese", "lightning"] and not has[cur[fid]]:
			intro_missing.append(cur[fid])
		goal_sets[fid] = goals_seen.size()
	check(bad_avail == 0, "no leg uses an idea before the Flight that introduces it")
	check(intro_missing.is_empty(), "every Flight that introduces a goal or twist actually uses it (%s)" % str(intro_missing))
	check(not_det == 0, "recipes are deterministic (a Flight is the same every time)")
	check(twists_max <= 2 and storm_lightning == 0, "at most two twists on a leg, none on top of a storm")
	check(min_distinct >= 2, "from Flight 6 on every Flight mixes at least 2 goal types (fewest: %d)" % min_distinct)
	var all_climb := true
	for l in 5:
		var rc0 = FlightsS.leg_recipe(0, l, FlightsS.leg_seed(FlightsS.seed_of(0), l))
		all_climb = all_climb and rc0.goal == 0 and rc0.twist_count() == 0
	check(all_climb, "Flight 1 is plain Climbing")
	var types_total := {}
	for fid in 24:
		for l in 5:
			types_total[FlightsS.leg_recipe(fid, l, FlightsS.leg_seed(FlightsS.seed_of(fid), l)).goal] = true
	check(types_total.size() == 5, "all five goal types appear in the world")
	var d_ok := true
	for l in 5:
		var rd = FlightsS.leg_recipe(-1, l, FlightsS.leg_seed(FlightsS.daily_seed(20000), l))
		d_ok = d_ok and rd.goal >= 0 and rd.goal <= 4
	check(d_ok, "the Daily Flight has recipes too (every idea available)")
	check(FlightsS.tools_for(0, 5) == [] and FlightsS.tools_for(1, 0) == [] and FlightsS.tools_for(1, 1) == [0] and FlightsS.tools_for(2, 0) == [0] and FlightsS.tools_for(2, 1) == [0, 1] and FlightsS.tools_for(3, 1) == [0, 1, 2], "tools: Sandbag from Alps 2, Anchor from Sahara 2, Quick Vent from Himalayas 2")

	# ---- 6j. goal mechanics ----
	print("6j. goals")
	var RecS = load("res://scripts/LegRecipe.gd")
	var mkr = func(g: int, kb: bool = false, ge: bool = false, rv: bool = false, lt: bool = false):
		var rr = RecS.new()
		rr.goal = g
		rr.kite_beat = kb
		rr.geese = ge
		rr.reverse = rv
		rr.lightning = lt
		rr.storm_speed = tn.storm_speed
		return rr
	sv.reset_all()
	tn.ads_enabled = false
	# Star Collect: every star before the top counts.
	m.start_flight(0)
	m.recipe = mkr.call(1)
	m.lanes.setup(3.0, false, 321, 0, m.recipe)
	m.balloon.reset()
	check(m.lanes.gs_count == int(tn.stars_per_leg) and m.lanes.stars_left() == m.lanes.gs_count, "Star Collect: %d stars in the leg" % m.lanes.gs_count)
	var star_lanes := {}
	var stars_clear := true
	for q in m.lanes.gs_count:
		star_lanes[m.lanes.gs_lane[q]] = true
		var kk: int = m.lanes.lane_kind[m.lanes.gs_lane[q]]
		for j in m.lanes.lane_count[m.lanes.gs_lane[q]]:
			var dxs := absf(fposmod(m.lanes.gs_x[q] - m.lanes.hz_x[m.lanes.gs_lane[q] * LanesS.MAX_PER_LANE + j] + LanesS.RING * 0.5, LanesS.RING) - LanesS.RING * 0.5)
			if kk >= 0 and dxs < float(LanesS.KIND_HX[kk]) * m.lanes.lane_scale[m.lanes.gs_lane[q]] + 20.0:
				stars_clear = false
	check(star_lanes.size() == m.lanes.gs_count and stars_clear, "...each in its own layer, in a gap")
	m._goal_key = -1
	clear_sky(m)
	m.lanes.gs_count = 0
	m.lanes.setup(3.0, false, 321, 0, m.recipe)
	clear_sky(m)
	m.lanes.gs_count = int(tn.stars_per_leg)
	for q in m.lanes.gs_count:
		m.lanes.gs_lane[q] = 1 + q
		m.lanes.gs_on[q] = 1
		m.lanes.gs_x[q] = 300.0
		m.lanes.lane_vel[1 + q] = 0.0
	m.screen = MainS.SCREEN_PLAY
	m.leg_started = true
	m.balloon.position = Vector2(540.0, LanesS.GOAL_Y + 4.0)
	m.balloon.on_ground = false
	m.balloon.rise = 250.0
	m.balloon.heat = 1.0
	step(m, 0.3, 1)
	check(m.screen == MainS.SCREEN_PLAY and m.balloon.position.y >= LanesS.GOAL_Y + 13.0, "stars left: the top does not count (the balloon is held under it)")
	check(m.hud.goal_label.text.begins_with("Stars 0 / 4"), "the HUD counts the stars")
	for q in 3:
		m.balloon.position = Vector2(300.0, LanesS.BAND_BOTTOM - (float(m.lanes.gs_lane[q]) + 0.5) * m.lanes.lane_h)
		m.balloon.rise = 0.0
		step(m, 0.02, 0)
	check(m.lanes.stars_left() <= 1 and m.screen == MainS.SCREEN_PLAY, "stars are collected by touching them")
	for q in m.lanes.gs_count:
		m.lanes.gs_on[q] = 0
	m.balloon.position = Vector2(540.0, LanesS.GOAL_Y + 12.0)
	m.balloon.rise = 250.0
	m.balloon.heat = 1.0
	step(m, 0.3, 1)
	check(m.screen == MainS.SCREEN_CLEAR, "all stars collected: reaching the top clears the leg")
	# Delivery: pick up at a mooring platform, drop at another, then the top.
	m.start_flight(0)
	m.recipe = mkr.call(2)
	var dock_ok := true
	for seed_i in 40:
		m.lanes.setup(1.0 + float(seed_i % 9) * 0.7, false, 600 + seed_i, 0, m.recipe)
		dock_ok = dock_ok and m.lanes.dl_lane[0] >= 1 and m.lanes.dl_lane[1] > m.lanes.dl_lane[0] and m.lanes.dl_lane[1] <= m.lanes.n_lanes - 2 and absf(m.lanes.dl_x[0] - m.lanes.dl_x[1]) >= 200.0 and m.lanes.dl_x[0] >= 150.0 and m.lanes.dl_x[0] <= 930.0 and m.lanes.dl_x[1] >= 150.0 and m.lanes.dl_x[1] <= 930.0
	check(dock_ok, "Delivery: a pick-up platform low down, a drop-off higher up, far enough apart")
	m.lanes.setup(3.0, false, 77, 0, m.recipe)
	m.balloon.reset()
	clear_sky(m)
	m.screen = MainS.SCREEN_PLAY
	m.leg_started = true
	m._goal_key = -1
	m.balloon.on_ground = false
	m.balloon.position = Vector2(540.0, LanesS.GOAL_Y + 4.0)
	m.balloon.rise = 250.0
	m.balloon.heat = 1.0
	step(m, 0.3, 1)
	check(m.screen == MainS.SCREEN_PLAY and m.lanes.mail_state == 0, "no mail delivered: the top does not count")
	check(m.hud.goal_label.text.contains("GREEN"), "the HUD says where to go")
	var d0: Vector2 = m.lanes.dock_pos(0)
	m.balloon.position = d0 + Vector2(300.0, 0.0)
	step(m, 0.02, 0)
	check(m.lanes.mail_state == 0, "away from the platform: nothing is picked up")
	m.balloon.position = d0 + Vector2(10.0, 0.0)
	m.balloon.rise = 0.0
	step(m, 0.02, 0)
	check(m.lanes.mail_state == 1 and m.hud.banner.text.contains("PICKED UP") and m.hud.goal_label.text.contains("RED"), "touching the pick-up platform takes the mail")
	var d1: Vector2 = m.lanes.dock_pos(1)
	check(m.lanes.dock_target() == d1, "the target ring moves to the drop-off")
	m.balloon.position = d1 + Vector2(-20.0, 5.0)
	step(m, 0.02, 0)
	check(m.lanes.mail_state == 2 and m.lanes.dock_target().x < 0.0, "touching the drop-off delivers it")
	m.balloon.position = Vector2(540.0, LanesS.GOAL_Y + 4.0)
	m.balloon.rise = 250.0
	m.balloon.heat = 1.0
	step(m, 0.1, 1)
	check(m.screen == MainS.SCREEN_CLEAR, "delivered: the top clears the leg")
	# Rising Storm.
	m.start_flight(0)
	m.recipe = mkr.call(3)
	m.lanes.setup(3.0, false, 88, 0, m.recipe)
	m.balloon.reset()
	clear_sky(m)
	m.screen = MainS.SCREEN_PLAY
	check(m.lanes.storm_on and m.lanes.storm_y > LanesS.GROUND_Y and m.lanes.storm_speed == tn.storm_speed, "Rising Storm: the storm starts below the ground")
	var storm0: float = m.lanes.storm_y
	step(m, 5.0, 0)
	check(m.lanes.storm_y == storm0 and not m.leg_started, "it waits while the balloon is on the ground")
	m.leg_started = true
	m.leg_time = 0.0
	m.balloon.on_ground = false
	m.balloon.position.y = 700.0
	step(m, 1.0, 0)
	check(m.lanes.storm_y == storm0, "...and for storm_start_delay seconds after lift-off")
	m.leg_time = tn.storm_start_delay
	step(m, 1.0, 0)
	check(absf((storm0 - m.lanes.storm_y) - tn.storm_speed * 1.0) < 3.0, "then it rises at its set pace (%.0f px/s)" % tn.storm_speed)
	var min_climb: float = (LanesS.BAND_BOTTOM - LanesS.GOAL_Y) / tn.steady_climb_speed
	var storm_time: float = (LanesS.GROUND_Y + 160.0 - LanesS.GOAL_Y) / (tn.storm_speed + tn.storm_speed_per_leg * 4.0)
	check(storm_time > 3.0 * min_climb, "fair: even on the last leg the storm takes %.0f s to reach the top (a straight climb: %.0f s)" % [storm_time, min_climb])
	m.lanes.storm_y = m.balloon.position.y + 20.0
	step(m, 0.05, 0)
	check(m.screen == MainS.SCREEN_DEAD and m.last_reason == "Caught by the storm", "caught by the storm: the Flight ends")
	m.start_flight(0)
	m.recipe = mkr.call(3)
	m.lanes.setup(3.0, false, 88, 0, m.recipe)
	m.balloon.reset()
	clear_sky(m)
	m.screen = MainS.SCREEN_PLAY
	m.leg_started = true
	m.balloon.on_ground = false
	m.balloon.position = Vector2(540.0, LanesS.GOAL_Y + 4.0)
	m.balloon.rise = 250.0
	m.balloon.heat = 1.0
	m.lanes.storm_y = 1700.0
	step(m, 0.1, 1)
	check(m.screen == MainS.SCREEN_CLEAR, "staying above the storm to the top clears the leg")
	# Precision Landing.
	m.start_flight(0)
	m.recipe = mkr.call(4)
	m.lanes.setup(3.0, false, 99, 0, m.recipe)
	m.balloon.reset()
	clear_sky(m)
	m.screen = MainS.SCREEN_PLAY
	m.leg_started = true
	m.balloon.on_ground = false
	var sx0: float = m.lanes.ship_x
	var ship_range_ok := true
	for i in 400:
		m.lanes.update(0.1)
		ship_range_ok = ship_range_ok and m.lanes.ship_x >= LanesS.SHIP_MIN_X - 0.01 and m.lanes.ship_x <= LanesS.SHIP_MAX_X + 0.01
	check(m.lanes.ship_on and ship_range_ok, "Precision Landing: an airship drifts to and fro over the top, inside its range")
	var sx1: float = m.lanes.ship_x
	m.lanes.update(0.5)
	check(absf(absf(m.lanes.ship_x - sx1) - tn.airship_speed * 0.5) < 1.0 or absf(m.lanes.ship_x - sx1) < tn.airship_speed * 0.5 + 1.0, "...slowly (%.0f px/s)" % tn.airship_speed)
	# no goal strip, a higher ceiling
	m.balloon.position = Vector2(540.0, 400.0)
	m.balloon.rise = 300.0
	m.balloon.heat = 1.0
	m.lanes.ship_x = 200.0
	step(m, 1.5, 1)
	check(m.screen == MainS.SCREEN_PLAY and m.balloon.position.y >= LanesS.CEILING_Y - 0.5 and m.balloon.position.y < LanesS.GOAL_Y, "the balloon may fly above the goal strip here, up to the ceiling; reaching the top is not the goal")
	# the hull blocks from below
	m.lanes.ship_dir = 0.0
	m.lanes.ship_x = 540.0
	m.balloon.position = Vector2(540.0, 500.0)
	m.balloon.rise = 300.0
	m.balloon.heat = 1.0
	step(m, 1.5, 1)
	check(m.screen == MainS.SCREEN_PLAY and m.balloon.position.y > LanesS.SHIP_DECK_Y + LanesS.SHIP_HULL_H, "the hull is solid from below: the balloon is held under it, not hurt")
	# landing slowly on the deck
	m.balloon.position = Vector2(m.lanes.ship_x + 40.0, LanesS.SHIP_DECK_Y - 84.0 * m.balloon.s() - 12.0)
	m.balloon.rise = -60.0
	m.balloon.heat = 0.0
	step(m, 0.3, 0)
	check(m.screen == MainS.SCREEN_CLEAR, "touching down on the deck slowly clears the leg")
	# a hard landing
	m.start_flight(0)
	m.recipe = mkr.call(4)
	m.lanes.setup(3.0, false, 99, 0, m.recipe)
	m.balloon.reset()
	clear_sky(m)
	m.screen = MainS.SCREEN_PLAY
	m.leg_started = true
	m.balloon.on_ground = false
	m.lanes.ship_dir = 0.0
	m.balloon.scheme = BalloonS.DRAG   # (steady's sink is slower than land_speed; a finger can plunge)
	m.balloon.set_altitude(LanesS.SHIP_DECK_Y - 84.0 * m.balloon.s() - 40.0)
	m.balloon.position.x = m.lanes.ship_x
	m.balloon.drag_target = m.balloon.position.y + 300.0
	m.balloon.on_ground = false
	step(m, 0.1, 0)
	check(m.screen == MainS.SCREEN_DEAD and m.last_reason.begins_with("Hard landing"), "touching down too fast is a hard landing")
	m.balloon.scheme = BalloonS.STEADY
	# missing the deck
	m.start_flight(0)
	m.recipe = mkr.call(4)
	m.lanes.setup(3.0, false, 99, 0, m.recipe)
	m.balloon.reset()
	clear_sky(m)
	m.screen = MainS.SCREEN_PLAY
	m.leg_started = true
	m.balloon.on_ground = false
	m.lanes.ship_dir = 0.0
	m.balloon.position = Vector2(m.lanes.ship_x + tn.airship_deck_half + 80.0, LanesS.SHIP_DECK_Y - 84.0 * m.balloon.s() - 2.0)
	m.balloon.rise = -50.0
	step(m, 0.1, 0)
	check(m.screen == MainS.SCREEN_PLAY, "beside the airship there is no landing")
	var bd = m.lanes.render.backdrop
	check(bd != null, "(landing legs draw no goal strip)")
	m.start_flight(0)

	# ---- 6k. player tools ----
	print("6k. tools")
	sv.reset_all()
	m.start_flight(0)
	var none_vis := true
	for tb in m.hud.tool_btns:
		none_vis = none_vis and not tb.visible
	check(m.tool_avail.is_empty() and none_vis and not m.use_tool(0), "no tools in the Countryside")
	m.start_flight(6)
	check(m.tool_avail.is_empty(), "...nor in the first Alps Flight")
	m.hud.hint_label.visible = false
	m.start_flight(7)
	check(m.tool_avail == [0] and m.hud.tool_btns[0].visible and not m.hud.tool_btns[1].visible and not m.hud.tool_btns[2].visible, "Alps 2: the Sandbag button appears")
	check(m.hud.hint_label.visible and m.hud.hint_label.text.begins_with("NEW TOOL: SANDBAG") and sv.tool_seen(0), "its one-line intro is shown the first time")
	m.hud.hint_label.visible = false
	m.start_flight(7)
	check(not m.hud.hint_label.visible, "...and only the first time")
	check(m.hud.tool_btns[0].text == "SANDBAG  x2", "the button shows its charges")
	# Sandbag: an instant climb burst, limited per leg.
	calm(m)
	m.balloon.on_ground = false
	m.balloon.position = Vector2(540.0, 1000.0)
	m.leg_started = true
	var y_plain := 0.0
	var y_bag := 0.0
	for pass_i in 2:
		m.balloon.position = Vector2(540.0, 1000.0)
		m.balloon.rise = 0.0
		m.balloon.heat = 0.0
		m.balloon._burst_px = 0.0
		m.lanes.lane_wind[3] = 0.0
		if pass_i == 1:
			check(m.use_tool(0), "the Sandbag can be dropped")
			check(is_equal_approx(m.balloon._burst_px, tn.sandbag_px), "...for a free climb burst of sandbag_px (%.0f px)" % m.balloon._burst_px)
		step(m, 1.0, 0)
		if pass_i == 0:
			y_plain = m.balloon.position.y
		else:
			y_bag = m.balloon.position.y
	check(y_bag < y_plain - 120.0, "the burst carries the balloon higher (%.0f px)" % (y_plain - y_bag))
	check(m.tool_charges[0] == 1 and m.hud.tool_btns[0].text == "SANDBAG  x1" and not m.hud.tool_btns[0].disabled, "one charge left")
	check(m.use_tool(0) and m.tool_charges[0] == 0 and m.hud.tool_btns[0].disabled, "the second one is the last: the button greys out")
	check(not m.use_tool(0), "no charges left: it does nothing")
	m.start_flight(7)
	check(m.tool_charges[0] == 2, "charges come back with every Flight / leg")
	# Anchor: hold position.
	m.start_flight(13)
	check(m.tool_avail == [0, 1] and m.hud.tool_btns[1].visible, "Sahara 2: the Anchor appears too")
	calm(m)
	m.lanes.th_count = 0
	m.balloon.on_ground = false
	m.leg_started = true
	var drift_free := 0.0
	var drift_anchor := 0.0
	var hold_y := 0.0
	for pass_i in 2:
		m.balloon.position = Vector2(300.0, 1000.0)
		m.balloon.vx = 0.0
		m.balloon.rise = 0.0
		m.balloon.heat = 0.0
		m.balloon.anchor_left = 0.0
		m.lanes.lane_base.fill(150.0)
		m.lanes.lane_wind.fill(150.0)
		if pass_i == 1:
			m.tool_charges[1] = 1
			check(m.use_tool(1) and m.balloon.anchor_left == tn.anchor_seconds, "the Anchor drops (%.0f s)" % m.balloon.anchor_left)
		var x_before: float = m.balloon.position.x
		var y_before: float = m.balloon.position.y
		step(m, 1.5, 0)
		if pass_i == 0:
			drift_free = m.balloon.position.x - x_before
		else:
			drift_anchor = m.balloon.position.x - x_before
			hold_y = m.balloon.position.y - y_before
	check(drift_free > 100.0 and drift_anchor < 25.0, "anchored, the balloon stays put in the wind (%.0f px vs %.0f px)" % [drift_anchor, drift_free])
	check(absf(hold_y) < 40.0, "...and neither rises nor sinks (%.0f px)" % hold_y)
	step(m, 2.5, 0)
	check(m.balloon.anchor_left == 0.0, "after anchor_seconds it lets go")
	m.balloon.position.y = 1000.0
	m.balloon.rise = 0.0
	var x_after: float = m.balloon.position.x
	for i in 60:
		m.sim(1.0 / 60.0)
		m.balloon.position.y = 1000.0
	check(m.balloon.position.x - x_after > 25.0, "...and the wind carries the balloon again")
	m.tool_charges[1] = 1
	m.use_tool(1)
	check(m.tool_charges[1] == 0 and not m.use_tool(1), "one Anchor per leg")
	# Quick Vent: a much faster descent.
	m.start_flight(19)
	check(m.tool_avail == [0, 1, 2] and m.hud.tool_btns[2].visible, "Himalayas 2: the Quick Vent appears too")
	calm(m)
	m.balloon.on_ground = false
	m.leg_started = true
	var drop_plain := 0.0
	var drop_vent := 0.0
	for pass_i in 2:
		m.balloon.position = Vector2(540.0, 700.0)
		m.balloon.rise = 0.0
		m.balloon.heat = 0.0
		m.balloon.vent_left = 0.0
		if pass_i == 1:
			m.tool_charges[2] = 2
			check(m.use_tool(2) and m.balloon.vent_left == tn.vent_seconds, "the Quick Vent opens")
		step(m, 1.5, 0)
		if pass_i == 0:
			drop_plain = m.balloon.position.y - 700.0
		else:
			drop_vent = m.balloon.position.y - 700.0
	check(drop_vent > drop_plain * 1.8, "it descends much faster (%.0f px vs %.0f px)" % [drop_vent, drop_plain])
	step(m, 2.0, 0)
	check(m.balloon.vent_left == 0.0 and absf(m.balloon.rise + tn.steady_sink_speed) < 30.0, "then the balloon settles back into its slow sink")
	# Charges per leg; refusals.
	m.start_flight(19)
	check(m.tool_charges[2] == int(tn.vent_charges) and m.tool_charges[1] == int(tn.anchor_charges) and m.tool_charges[0] == int(tn.sandbag_charges), "charges per leg from Tuning")
	m.screen = MainS.SCREEN_DEAD
	check(not m.use_tool(0), "tools only work while flying")
	m.screen = MainS.SCREEN_PLAY
	m.hud.ad_active = true
	check(not m.use_tool(0), "...and not while an ad is up")
	m.hud.ad_active = false
	# Touches: a second finger on a tool button works while the first holds the burner; the emulated mouse of a touch is skipped.
	m.start_flight(7)
	var HudS = load("res://scripts/Hud.gd")
	var ev := InputEventScreenTouch.new()
	ev.index = 1
	ev.pressed = true
	ev.position = HudS.TOOL_RECTS[0].get_center()
	m._input(ev)
	check(m.tool_charges[0] == 1, "a touch on the Sandbag button uses it")
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = true
	ev2.position = HudS.TOOL_RECTS[0].get_center()
	ev2.device = InputEvent.DEVICE_ID_EMULATION
	m._input(ev2)
	check(m.tool_charges[0] == 1, "the emulated mouse of a touch is ignored (no double use)")
	var ev3 := InputEventMouseButton.new()
	ev3.button_index = MOUSE_BUTTON_LEFT
	ev3.pressed = true
	ev3.position = HudS.TOOL_RECTS[0].get_center()
	m._input(ev3)
	check(m.tool_charges[0] == 0, "a real mouse click works too")
	var ev4 := InputEventScreenTouch.new()
	ev4.pressed = true
	ev4.position = Vector2(540, 900)
	m.start_flight(7)
	m._input(ev4)
	check(m.tool_charges[0] == 2, "a touch elsewhere does nothing")
	var ev5 := InputEventScreenTouch.new()
	ev5.pressed = true
	ev5.position = HudS.TOOL_RECTS[2].get_center()
	m._input(ev5)
	check(m.tool_charges[2] == int(tn.vent_charges), "a button that is not on offer does nothing")
	check(m._on_tool_button(HudS.TOOL_RECTS[0].get_center()) and not m._on_tool_button(HudS.TOOL_RECTS[2].get_center()) and not m._on_tool_button(Vector2(500, 900)), "a press on a tool button is not a burner hold")
	var rects_ok := true
	for i in 3:
		rects_ok = rects_ok and HudS.TOOL_RECTS[i].position.y >= LanesS.GROUND_Y + 20.0 and HudS.TOOL_RECTS[i].end.x <= 1080.0
	check(rects_ok, "the tool buttons sit below the ground line, out of the way of the sky")
	sv.reset_all()
	m.start_flight(0)

	# ---- 6l. rhythm hazards and changing winds ----
	print("6l. rhythm hazards and changing winds")
	var HM = load("res://scripts/HazardMeshes.gd")
	var meshes: Array = HM.build_all()
	check(meshes.size() == HM.COUNT and LanesS.GOOSE == 8 and HM.GOOSE == 8, "geese are a hazard kind with their own mesh")
	var gm = meshes[HM.GOOSE]
	check(gm.get_surface_count() == 1 and gm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() > 150, "a V of five geese (%d vertices)" % gm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size())
	var geese_ok := true
	for seed_i in 40:
		m.lanes.setup(3.0 + float(seed_i % 8), false, 1200 + seed_i, seed_i % 4, mkr.call(0, false, true))
		var any_goose := false
		for i in m.lanes.n_lanes:
			if m.lanes.lane_kind[i] == LanesS.GOOSE:
				any_goose = true
				geese_ok = geese_ok and m.lanes.lane_count[i] >= 1
		geese_ok = geese_ok and any_goose
	check(geese_ok, "a geese leg always has a layer of geese in V formation")
	m.start_flight(0)
	clear_sky(m)
	m.lanes.lane_kind[2] = LanesS.GOOSE
	m.lanes.lane_count[2] = 1
	m.lanes.lane_scale[2] = 1.0
	m.lanes.lane_amp[2] = 0.0
	m.lanes.lane_vel[2] = 0.0
	m.lanes.lane_beat[2] = 0.0
	var cyg2: float = LanesS.BAND_BOTTOM - 2.5 * m.lanes.lane_h
	m.lanes.hz_x[2 * LanesS.MAX_PER_LANE] = 300.0
	m.balloon.position = Vector2(300.0, cyg2)
	m.balloon.on_ground = false
	m.screen = MainS.SCREEN_PLAY
	m.leg_started = true
	step(m, 0.05, 0)
	check(m.screen == MainS.SCREEN_DEAD and m.last_reason == "Crashed into a flock of geese", "touching the geese ends the attempt")
	# Kites that dip on a beat.
	var beat_ok := true
	var dips_ok := true
	var shared_ok := true
	var period_ok := true
	var up_share := 0.0
	var tested := 0
	for seed_i in 30:
		m.lanes.setup(4.0, false, 1500 + seed_i, 0, mkr.call(0, true))
		var kl := -1
		for i in m.lanes.n_lanes:
			if m.lanes.lane_kind[i] == LanesS.KITE:
				kl = i
		if kl < 0 or m.lanes.lane_count[kl] < 1:
			beat_ok = false
			continue
		beat_ok = beat_ok and is_equal_approx(m.lanes.lane_beat[kl], tn.kite_beat_period)
		tested += 1
		var cyk: float = LanesS.BAND_BOTTOM - (float(kl) + 0.5) * m.lanes.lane_h
		var amp: float = m.lanes.lane_amp[kl]
		var ys: Array[float] = []
		for step_i in 96:   # two beats
			m.lanes.update(tn.kite_beat_period / 48.0)
			ys.append(m.lanes.hz_y[kl * LanesS.MAX_PER_LANE] - cyk)
		var lo := 1.0e9
		var hi := -1.0e9
		var up := 0
		for v in ys:
			lo = minf(lo, v)
			hi = maxf(hi, v)
			if v < -amp * 0.3:
				up += 1
		dips_ok = dips_ok and (hi - lo) >= amp * 0.5
		up_share += float(up) / 96.0
		for i2 in 48:
			period_ok = period_ok and absf(ys[i2] - ys[i2 + 48]) < 0.5
		if m.lanes.lane_count[kl] >= 2:
			var d_a: float = m.lanes.hz_y[kl * LanesS.MAX_PER_LANE] - cyk
			var d_b: float = m.lanes.hz_y[kl * LanesS.MAX_PER_LANE + 1] - cyk
			shared_ok = shared_ok and absf(d_a - d_b) < 0.01
	check(beat_ok and tested >= 20, "a kite-beat leg has a layer of kites that beat every %.1f s" % tn.kite_beat_period)
	check(dips_ok and period_ok, "the kites dip on a clean, repeating beat")
	check(shared_ok, "all kites of the layer dip together")
	check(up_share / float(tested) > 0.45, "they stay up most of the beat (%.0f%%): a pattern you can read" % (100.0 * up_share / float(tested)))
	m.lanes.setup(4.0, false, 1500, 0, mkr.call(0))
	var plain_beat := true
	for i in m.lanes.n_lanes:
		plain_beat = plain_beat and m.lanes.lane_beat[i] == 0.0
	check(plain_beat, "without the twist kites just bob")
	# Lightning with a warning flash.
	m.start_flight(0)
	m.lanes.setup(4.0, false, 1600, 0, mkr.call(0, false, false, false, true))
	check(m.lanes.lt_on and m.lanes.lt_cols[0] != m.lanes.lt_cols[1] and m.lanes.lt_cols[1] != m.lanes.lt_cols[2] and m.lanes.lt_cols[0] != m.lanes.lt_cols[2], "a lightning leg has three different strike columns")
	var states: Array = []
	var first_warn := -1.0
	var warn_len := 0.0
	var strike_len := 0.0
	var flash_seen := false
	var tt := -3.0
	var prev_state := 0
	var warn_start := 0.0
	var strike_start := 0.0
	var cols_seen := {}
	var periods_ok := true
	var last_strike_start := -1.0
	for i in 1500:
		m.lanes.update(0.02)
		tt += 0.02
		var st: int = m.lanes.lt_state
		if st == 1 and prev_state == 0:
			warn_start = tt
			flash_seen = flash_seen or m.lanes.lt_flash > 0.0
			if first_warn < 0.0:
				first_warn = tt
		if st == 2 and prev_state == 1:
			warn_len = tt - warn_start
			strike_start = tt
			cols_seen[snappedf(m.lanes.lt_x, 1.0)] = true
			if last_strike_start >= 0.0:
				periods_ok = periods_ok and absf((tt - last_strike_start) - tn.lightning_period) < 0.08
			last_strike_start = tt
		if st == 0 and prev_state == 2:
			strike_len = tt - strike_start
		prev_state = st
	check(first_warn > 3.0, "no lightning in the first seconds (first warning after %.1f s)" % (first_warn + 3.0))
	check(flash_seen and absf(warn_len - tn.lightning_warning) < 0.08, "a white flash starts the %.1f s warning" % tn.lightning_warning)
	check(absf(strike_len - tn.lightning_strike) < 0.08 and periods_ok, "then the strike (%.1f s), once every %.0f s on the beat" % [tn.lightning_strike, tn.lightning_period])
	check(cols_seen.size() == 3, "the strikes visit three columns in turn")
	check(tn.lightning_width / LanesS.W < 0.2 and 3.0 * tn.lightning_width / LanesS.W < 0.4, "a column is narrow: it never covers more than a fifth of the sky")
	# The strike hurts only inside its column.
	m.start_flight(0)
	m.recipe = mkr.call(0, false, false, false, true)
	m.lanes.setup(4.0, false, 1600, 0, m.recipe)
	clear_sky(m)
	m.balloon.on_ground = false
	m.leg_started = true
	m.screen = MainS.SCREEN_PLAY
	m.lanes.lt_state = 2
	m.lanes.lt_clock = 0.0
	m.lanes.lt_x = 500.0
	m.balloon.position = Vector2(500.0 + tn.lightning_width, 900.0)
	check(not m.lanes.lightning_hits(m.balloon), "outside the column during a strike: safe")
	m.lanes.lt_state = 1
	m.balloon.position = Vector2(500.0, 900.0)
	check(not m.lanes.lightning_hits(m.balloon), "inside the column during the WARNING: safe")
	m.lanes.lt_state = 2
	check(m.lanes.lightning_hits(m.balloon), "inside the column during the strike: hit")
	DebugFlags.parse(["god"])
	m.lanes.lt_clock = 4.7
	m.sim(0.001)
	check(m.screen == MainS.SCREEN_PLAY, "?god: lightning cannot hurt")
	DebugFlags.parse([])
	m.lanes.lt_clock = 4.7
	m.lanes.lt_state = 2
	m.lanes.lt_x = m.balloon.position.x
	m.lanes.lt_cols[0] = m.balloon.position.x
	m.lanes.lt_cols[1] = m.balloon.position.x
	m.lanes.lt_cols[2] = m.balloon.position.x
	m.lanes.lt_clock = tn.lightning_period - tn.lightning_strike * 0.5
	m.sim(0.001)
	check(m.screen == MainS.SCREEN_DEAD and m.last_reason == "Struck by lightning", "struck by lightning: the Flight ends")
	# Reversing winds with a visible timer.
	m.start_flight(0)
	m.lanes.setup(4.0, false, 1700, 0, mkr.call(0, false, false, true))
	var rl := -1
	for i in m.lanes.n_lanes:
		if is_equal_approx(m.lanes.lane_rev[i], tn.reverse_period):
			rl = i
	check(rl >= 1, "a reversing-wind leg has a layer that flips every %.0f s" % tn.reverse_period)
	var signs := {}
	var flips := 0
	var last_sign := 0.0
	var timer_ok := true
	var prev_timer := 999.0
	var cross_ok := true
	for i in 700:
		m.lanes.update(0.05)
		var w: float = m.lanes.lane_wind[rl]
		var sg := signf(w)
		if sg != 0.0 and last_sign != 0.0 and sg != last_sign:
			flips += 1
		if sg != 0.0:
			last_sign = sg
		var tm: float = m.lanes.rev_timer(rl)
		timer_ok = timer_ok and tm >= 0.0 and tm <= tn.reverse_period + 0.001
		prev_timer = tm
		cross_ok = cross_ok and absf(w) <= absf(m.lanes.lane_base[rl]) + 0.01
	check(flips >= 3 and flips <= 5, "its wind reverses on a timer (%d flips in 35 s)" % flips)
	check(timer_ok and cross_ok, "the countdown stays within 0..%.0f s and the wind never exceeds its speed" % tn.reverse_period)
	var tvals: Array[float] = []
	for i in 40:
		m.lanes.update(0.1)
		tvals.append(m.lanes.rev_timer(rl))
	var counts_down := true
	for i in range(1, 40):
		counts_down = counts_down and (tvals[i] < tvals[i - 1] + 0.001 or tvals[i - 1] < 0.3)
	check(counts_down, "the timer counts down to the flip, then starts again")
	var lab = m.lanes.render._rev_labels[rl]
	m.lanes.update(0.05)
	check(lab.visible and lab.text.begins_with("<> ") and int(lab.text.substr(3)) == ceili(m.lanes.rev_timer(rl)), "a visible countdown label sits on the layer (%s)" % lab.text)
	var other_hidden := true
	for i in m.lanes.n_lanes:
		if m.lanes.lane_rev[i] == 0.0:
			other_hidden = other_hidden and not m.lanes.render._rev_labels[i].visible
	check(other_hidden, "steady layers have no label")
	# Hazards in a reversing layer turn round with the wind and keep their gaps.
	var hz_lane := -1
	for i in m.lanes.n_lanes:
		if m.lanes.lane_rev[i] > 0.0 and m.lanes.lane_count[i] >= 2:
			hz_lane = i
	if hz_lane >= 0:
		var gap0: float = fposmod(m.lanes.hz_x[hz_lane * LanesS.MAX_PER_LANE + 1] - m.lanes.hz_x[hz_lane * LanesS.MAX_PER_LANE], LanesS.RING)
		var v_signs := {}
		var gaps_ok := true
		for i in 400:
			m.lanes.update(0.05)
			v_signs[signf(m.lanes.lane_vel[hz_lane])] = true
			var gnow: float = fposmod(m.lanes.hz_x[hz_lane * LanesS.MAX_PER_LANE + 1] - m.lanes.hz_x[hz_lane * LanesS.MAX_PER_LANE], LanesS.RING)
			gaps_ok = gaps_ok and absf(gnow - gap0) < 0.5
		check(v_signs.has(1.0) and v_signs.has(-1.0) and gaps_ok, "its hazards reverse too, and their gaps never change")
	else:
		check(true, "(no reversing layer with 2+ hazards in this seed)")
	# The pre-warm shows every new thing.
	m.lanes.setup(1.0, true)
	var rdr = m.lanes.render
	var show_kinds := {}
	for i in m.lanes.n_lanes:
		show_kinds[m.lanes.lane_kind[i]] = true
	check(show_kinds.has(LanesS.GOOSE) and rdr._gs.multimesh.visible_instance_count == LanesS.MAX_STARS and rdr._ship.multimesh.visible_instance_count == 1 and rdr._mk.multimesh.visible_instance_count == 1 and rdr._storm.visible and m.lanes.lt_on and m.lanes.lane_rev[3] > 0.0, "the start-up pre-warm draws geese, stars, airship, marker, storm, lightning and a reversing layer")
	m.start_flight(0)

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
	check(dens[10] > dens[1] and dens[25] >= dens[10] - 0.2, "hazard density grows with the level (%.1f -> %.1f -> %.1f)" % [dens[1], dens[10], dens[25]])
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
	tp._sliders["hop_time"].value = 0.5
	check(is_equal_approx(tn.hop_time, 0.5), "a slider edits Tuning live")
	tp._sliders["hop_fuel"].value = 6.5
	tp._toggles["edge_wrap"].button_pressed = false
	check(is_equal_approx(tn.hop_fuel, 6.5) and tn.edge_wrap == false, "more sliders and the edge toggle")
	tp.copy_values()
	check(tp.last_copied_text.contains("hop_time = 0.5") and tp.last_copied_text.contains("hop_fuel = 6.5") and tp.last_copied_text.contains("edge_wrap = false"), "Copy values lists what changed")
	check(not tp.last_copied_text.contains("climb_speed"), "...and only what changed")
	tp.reset_defaults()
	check(is_equal_approx(tn.hop_time, 0.35) and tn.edge_wrap and tp.changed_text() == "(no changes)", "Reset restores the defaults")
	tp.close()
	check(not tp.is_open and not paused, "closing resumes")
	check(same(base2, snap()), "using the panel allocates nothing")
	# Debug buttons in the panel: press each one for real and check the live state, the screen and the saved file.
	sv.persist = true
	sv.reset_all()
	m._show_map()
	var tbtn: Dictionary = {}
	find_buttons(tp, tbtn)
	check(tbtn.has("Add 1000 coins") and tbtn.has("3-star everything") and tbtn.has("Unlock all regions") and tbtn.has("Reset save") and tbtn.has("Reset daily") and tbtn.has("Next day"), "the tune panel has every debug button")
	var mp2 = m.hud.map
	check(not mp2.nodes[23].visible and mp2.region_locks[3].visible, "(a fresh save: later regions are locked on the map)")
	tbtn["Add 1000 coins"].pressed.emit()
	check(sv.coins == 1000 and read_save()["coins"] == 1000 and mp2.coins_label.text == "coins 1,000", "Add 1000 coins: live, saved, and shown on the map")
	# Unlock all regions.
	tbtn["Unlock all regions"].pressed.emit()
	check_everything_open(m, sv, "Unlock all regions", false)
	check(sv.total_stars() == 0, "Unlock all regions does not touch the stars")
	# Reset, then 3-star everything.
	tbtn["Reset save"].pressed.emit()
	check(sv.coins == 0 and sv.total_stars() == 0 and not sv.region_unlocked(1) and not sv.flight_unlocked(1) and read_save()["coins"] == 0 and not read_save()["unlock_all"], "Reset save: everything locked again, live and saved")
	check(not mp2.nodes[23].visible and mp2.region_locks[1].visible and mp2.nodes[1].disabled, "...and the map is locked again without a reload")
	tbtn["3-star everything"].pressed.emit()
	check_everything_open(m, sv, "3-star everything", true)
	tbtn["Reset save"].pressed.emit()
	# Daily buttons.
	sv.data["daily_last"] = 5
	sv.data["daily_streak"] = 4
	tbtn["Reset daily"].pressed.emit()
	check(sv.data["daily_last"] == -1 and sv.data["daily_streak"] == 0 and read_save()["daily_last"] == -1, "Reset daily: live and saved")
	FlightsS.debug_today = 30000
	tbtn["Next day"].pressed.emit()
	check(FlightsS.today() == 30001, "Next day moves the date on")
	FlightsS.debug_today = -1
	# The URL flag: everything open on load, nothing written to the save.
	sv.reset_all()
	DebugFlags.parse(["unlockall"])
	check(DebugFlags.unlockall and DebugFlags.summary().contains("unlockall"), "?unlockall parses and shows in the stamp")
	m._show_map()
	var flag_all := true
	for r in 4:
		flag_all = flag_all and sv.region_unlocked(r)
	for id in 24:
		flag_all = flag_all and sv.flight_unlocked(id) and mp2.nodes[id].visible and not mp2.nodes[id].disabled
	check(flag_all and not mp2.region_locks[3].visible, "?unlockall: every region and Flight is open on the map")
	check(not read_save()["unlock_all"] and sv.total_stars() == 0 and sv.take_new_region() == -1, "...without writing anything to the save (and no spurious 'new region' message)")
	DebugFlags.parse(["tune"])
	m._show_map()
	check(not sv.region_unlocked(1) and not mp2.nodes[23].visible, "without the flag the save decides again")
	sv.reset_all()
	sv.persist = false
	m.free()
	DebugFlags.parse([])
	await process_frame
