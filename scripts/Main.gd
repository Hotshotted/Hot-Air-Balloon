class_name Main
extends Node2D
## Wind Layers: climb a hot air balloon through layers of wind to the goal at the top, Frogger style.
## One scene for the whole session. Restarting is IN PLACE: the pooled hazards, effects and UI nodes
## stay alive (and warm); only the game state is reset.

enum { SCREEN_MENU, SCREEN_PLAY, SCREEN_CLEAR, SCREEN_DEAD, SCREEN_RESULT, SCREEN_MAP }
## Seconds the "leg cleared" banner holds before the next leg starts.
const CLEAR_HOLD := 1.3

var screen := SCREEN_MENU
var selected := 0                   # the Flight the menu points at
var flight_id := 0                  # the Flight being flown
var flight_region := 0
var flight_index := 0
var flight_seed := 0
var leg := 0                        # 0-based leg of the Flight
var fuel := 0.0                     # ONE tank for the whole Flight: what is left carries into the next leg
var score := 0
var flight_coins := 0               # coins earned so far this Flight
var coins_picked := 0               # floating coins collected this Flight (the third star)
var leg_time := 0.0
var leg_started := false            # the clock starts when the balloon leaves the ground
var clear_left := 0.0
var last_reason := ""
var last_bonus := 0
var last_stars := 0
var last_propane_bonus := 0
var burn_override := -1             # tests: 1 = burner held, 0 = released, -1 = read the real input
var tune_panel: TunePanel
var lanes: Lanes
var balloon: Balloon
var hud: Hud
var sim_time := 0.0                 # seconds of simulation this Flight (should track the wall clock minus pauses)
var _warming := false
var _prog_key := -1
var _air_pct := -1
static var _warmed := false         # the pre-warm only ever runs once per page load

func _ready() -> void:
	Engine.max_physics_steps_per_frame = 1   # no physics here: a stall must never trigger catch-up steps
	lanes = $Lanes
	balloon = $Balloon
	hud = $Hud
	if DebugFlags.tune_enabled():
		tune_panel = TunePanel.new()
		add_child(tune_panel)
		tune_panel.build()
		tune_panel.restart_requested.connect(func(): tune_panel.close(); start_flight(flight_id))
		tune_panel.save_changed.connect(_refresh_menu)
	hud.fly_pressed.connect(func(): start_flight(selected))
	hud.prev_pressed.connect(func(): _select(selected - 1))
	hud.next_pressed.connect(func(): _select(selected + 1))
	hud.again_pressed.connect(func(): start_flight(flight_id))
	hud.menu_pressed.connect(_show_map)
	hud.back_pressed.connect(_show_map)
	hud.flight_chosen.connect(func(id: int): selected = id; _show_menu())
	hud.next_flight_pressed.connect(_on_next_flight)
	selected = Save.suggested_flight()
	_set_flight(selected)
	lanes.setup(Flights.eff_level(flight_region, flight_index, 0), false, Flights.leg_seed(flight_seed, 0), flight_region)
	balloon.reset()
	fuel = Tuning.propane_start
	hud.set_fuel(1.0)
	if not _warmed:
		_warmed = true
		if DebugFlags.prewarm_enabled():
			_prewarm()
			return
	_show_map()
	if tune_panel:
		tune_panel.set_available(true)

func _set_flight(id: int) -> void:
	flight_id = id
	flight_region = Flights.region_of(id)
	flight_index = Flights.index_of(id)
	flight_seed = Flights.seed_of(id)

func _flight_name(id: int) -> String:
	return "%s %d" % [String(Regions.NAMES[Flights.region_of(id)]).to_upper(), Flights.index_of(id) + 1]

# ---- map and Flight screen ----

func _select(id: int) -> void:
	selected = clampi(id, 0, Flights.TOTAL - 1)
	_refresh_menu()

## The world map (the home screen).
func _show_map() -> void:
	screen = SCREEN_MAP
	get_tree().paused = false
	lanes.visible = false
	balloon.visible = false
	hud.set_flight_title("")
	hud.set_score(0)
	hud.set_flight_coins(0)
	hud.set_air("")
	hud.show_map()

## The Flight screen: name, stars, what each star needs, FLY.
func _show_menu() -> void:
	screen = SCREEN_MENU
	lanes.visible = true
	balloon.visible = true
	_set_flight(selected)
	lanes.setup(Flights.eff_level(flight_region, flight_index, 0), false, Flights.leg_seed(flight_seed, 0), flight_region)
	balloon.reset()
	hud.set_flight_title("")
	hud.set_air("")
	_refresh_menu()

func _refresh_menu() -> void:
	if screen != SCREEN_MENU:
		return
	var id := selected
	var st := Save.stars_of(id)
	var open := Save.flight_unlocked(id)
	var info := "Locked: complete the Flight before it." if not open else "* Finish all %d legs\n* Finish with %d propane or more\n* Collect %d of %d coins\nbest score %s     coins %s" % [
		int(Tuning.legs_per_flight), int(Flights.propane_target()), Flights.coin_target(), Flights.coin_total(),
		Tuning.fmt(float(Save.best_score_of(id))), Tuning.fmt(float(Save.coins))]
	var r := Flights.region_of(id)
	hud.show_menu(Regions.NAMES[r], Regions.BLURB[r], "FLIGHT %d" % (Flights.index_of(id) + 1), st >= 1, st >= 2, st >= 3, info,
		Flights.index_of(id) > 0, Flights.index_of(id) < Flights.PER_REGION - 1, open)

func _on_next_flight() -> void:
	var nxt := flight_id + 1
	if nxt < Flights.TOTAL and Flights.region_of(nxt) == Flights.region_of(flight_id) and Save.flight_unlocked(nxt):
		selected = nxt
		start_flight(nxt)
	else:
		_show_map()

## First-use stutter fix: GL shaders / buffers / font glyphs set themselves up the first time they are
## used. So at boot, behind a splash screen, draw EVERY shape for real (all hazard kinds in both
## directions, pickups, streamers, the burner flame, a spark burst, every label and the tune panel)
## and KEEP drawing until frame times settle. Then hide it all. Skip with ?noprewarm.
func _prewarm() -> void:
	_warming = true
	hud.begin_prewarm()
	lanes.setup(1, true)
	lanes.visible = true
	balloon.visible = true
	if tune_panel:
		tune_panel.prewarm_show(true)
	var t_start := Time.get_ticks_msec()
	var t_last := t_start
	var t_burst := -100000
	var calm_frames := 0
	while true:
		var now := Time.get_ticks_msec()
		if now - t_burst > 350:
			t_burst = now
			lanes.burst(Vector2(300, 900), Lanes.C_TANK, 12, 300.0)
			lanes.burst(Vector2(780, 900), Color(1.0, 0.5, 0.15), 12, 300.0)
		balloon.heat = 1.0
		balloon.queue_redraw()
		lanes.update(minf(get_process_delta_time(), 0.05))
		await get_tree().process_frame
		var t := Time.get_ticks_msec()
		calm_frames = calm_frames + 1 if (t - t_last) < Tuning.prewarm_stable_ms else 0
		t_last = t
		var elapsed_s := (t - t_start) / 1000.0
		if elapsed_s >= Tuning.prewarm_max_seconds:
			break
		if elapsed_s >= Tuning.prewarm_min_seconds and calm_frames >= Tuning.prewarm_stable_frames:
			break
	lanes.clear_fx()
	balloon.heat = 0.0
	lanes.setup(Flights.eff_level(0, 0, 0), false, Flights.leg_seed(Flights.seed_of(0), 0), 0)
	hud.end_prewarm()
	if tune_panel:
		tune_panel.prewarm_show(false)
		tune_panel.set_available(true)
	_warming = false
	_show_map()

# ---------------------------------------------------------------------------------------------------------
# Flight flow
# ---------------------------------------------------------------------------------------------------------

## Start a Flight IN PLACE: a fresh tank, leg 1. Nothing is reloaded, created or freed.
func start_flight(id: int) -> void:
	_set_flight(id)
	leg = 0
	score = 0
	flight_coins = 0
	coins_picked = 0
	fuel = Tuning.propane_start
	sim_time = 0.0
	_run_start_ms = Time.get_ticks_msec()
	_paused_total_ms = 0
	_skip_frames = 0
	if tune_panel and tune_panel.is_open:
		tune_panel.close()
	get_tree().paused = false
	hud.set_score(0)
	hud.set_flight_coins(0)
	_begin_leg()

func _begin_leg() -> void:
	lanes.setup(Flights.eff_level(flight_region, flight_index, leg), false, Flights.leg_seed(flight_seed, leg), flight_region)
	lanes.visible = true
	lanes.clear_fx()
	balloon.reset()
	balloon.visible = true
	leg_time = 0.0
	leg_started = false
	hud.hide_overlays()
	hud.set_flight_title("%s   LEG %d/%d" % [_flight_name(flight_id), leg + 1, int(Tuning.legs_per_flight)])
	hud.set_fuel(fuel / Tuning.propane_start)
	_air_pct = -1
	_prog_key = -1
	_update_progress()
	hud.show_banner("LEG %d / %d" % [leg + 1, int(Tuning.legs_per_flight)], 1.0)
	screen = SCREEN_PLAY

func _update_progress() -> void:
	var key := int(fuel) * 1000 + coins_picked * 10 + leg
	if key != _prog_key:
		_prog_key = key
		hud.set_progress(leg, int(Tuning.legs_per_flight), fuel, coins_picked, Flights.coin_target())

## The Flight ends here: a failed leg (crash, or stranded without propane). Coins already earned are kept.
func _fail(reason: String) -> void:
	screen = SCREEN_DEAD
	last_reason = reason
	last_stars = 0
	Save.add_coins(flight_coins)
	hud.show_dead("Leg %d of %d\n%s\nCoins kept: %d" % [leg + 1, int(Tuning.legs_per_flight), reason, flight_coins])

func _crash(kind: int) -> void:
	lanes.burst(balloon.position, Color(1.0, 0.45, 0.15), 18, 420.0)
	lanes.burst(balloon.position, Color(1.0, 0.9, 0.4), 10, 300.0)
	balloon.visible = false
	_fail("Crashed into %s" % Lanes.KIND_NAME[kind])

func _clear_leg() -> void:
	var par := Tuning.par_base + Tuning.par_per_layer * float(lanes.n_lanes)
	last_bonus = roundi(maxf(par - leg_time, 0.0) * Tuning.speed_bonus_per_s)
	score += roundi(Tuning.level_points) + last_bonus
	flight_coins += roundi(Tuning.leg_coins)
	hud.set_score(score)
	hud.set_flight_coins(flight_coins)
	lanes.burst(balloon.position, Color(1.0, 0.85, 0.3), 14, 380.0)
	lanes.burst(balloon.position, Color(0.4, 0.9, 1.0), 14, 380.0)
	fuel = minf(fuel + Tuning.leg_refill, Tuning.propane_start)
	leg += 1
	if leg >= int(Tuning.legs_per_flight):
		_finish_flight()
		return
	hud.show_banner("LEG %d CLEARED\n+%d  speed +%d" % [leg, roundi(Tuning.level_points), last_bonus], CLEAR_HOLD)
	_update_progress()
	clear_left = CLEAR_HOLD
	screen = SCREEN_CLEAR

func _finish_flight() -> void:
	last_propane_bonus = roundi(fuel * Tuning.propane_coins)
	flight_coins += last_propane_bonus
	last_stars = Flights.stars_for(true, fuel, coins_picked)
	var had := Save.stars_of(flight_id)
	Save.record_flight(flight_id, last_stars, score)
	Save.add_coins(flight_coins)
	screen = SCREEN_RESULT
	var tgt_p := int(Flights.propane_target())
	var summary := "Score %s\nCoins earned: %d   (propane bonus %d)" % [Tuning.fmt(float(score)), flight_coins, last_propane_bonus]
	hud.show_result("Flight completed",
		"Propane left %d  (needs %d)" % [int(fuel), tgt_p],
		"Coins collected %d  (needs %d)" % [coins_picked, Flights.coin_target()],
		true, last_stars >= 2 and fuel >= Flights.propane_target(), coins_picked >= Flights.coin_target(),
		summary + ("\nNEW BEST: %d stars" % last_stars if last_stars > had else "") + _region_news(),
		flight_id + 1 < Flights.TOTAL and Flights.region_of(flight_id + 1) == flight_region and Save.flight_unlocked(flight_id + 1))

## "NEW REGION UNLOCKED" for the result screen, once per region.
func _region_news() -> String:
	var r := Save.take_new_region()
	return "\nNEW REGION UNLOCKED: %s!" % Regions.NAMES[r] if r >= 0 else ""

func _holding() -> bool:
	if burn_override >= 0:
		return burn_override == 1
	if tune_panel and tune_panel.is_open:
		return false
	if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP):
		return true
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not TunePanel.button_hit(get_viewport().get_mouse_position())

## One simulation step of `dt` seconds.
func sim(dt: float) -> void:
	sim_time += dt
	hud.tick(dt)
	match screen:
		SCREEN_PLAY:
			_play(dt)
		SCREEN_CLEAR:
			lanes.update(dt)
			clear_left -= dt
			if clear_left <= 0.0:
				_begin_leg()
		_:
			lanes.update(dt)

func _play(dt: float) -> void:
	lanes.focus_lane = lanes.lane_of(balloon.position.y)
	var climb_mult := lanes.climb_mult_at(balloon.position.y)
	balloon.step(dt, _holding(), fuel > 0.0, lanes.wind_at(balloon.position.y), lanes.thermal_lift(balloon.position.x), climb_mult)
	if lanes.thin_air:
		var pct := int(climb_mult * 100.0)
		if pct != _air_pct:
			_air_pct = pct
			hud.set_air("thin air: burner at %d%%" % pct)
	if not leg_started and not balloon.on_ground:
		leg_started = true
	if leg_started:
		leg_time += dt
	if balloon.burning:
		fuel = maxf(fuel - Tuning.burn_rate * dt, 0.0)
	lanes.update(dt)
	var got := lanes.collect(balloon)
	if got > 0:
		fuel = minf(fuel + Tuning.propane_refill * float(got), Tuning.propane_start)
	var cn := lanes.collect_coins(balloon)
	if cn > 0:
		coins_picked += cn
		flight_coins += cn * roundi(Tuning.coin_value)
		hud.set_flight_coins(flight_coins)
	hud.set_fuel(fuel / Tuning.propane_start)
	_update_progress()
	if not DebugFlags.god and lanes.hits(balloon):
		_crash(lanes.last_hit_kind)
	elif balloon.position.y <= Lanes.GOAL_Y:
		_clear_leg()
	elif fuel <= 0.0 and balloon.on_ground:
		_fail("Out of propane: stranded on the ground")

# ---------------------------------------------------------------------------------------------------------
# Frame time: the simulation can never run ahead of the clock
# ---------------------------------------------------------------------------------------------------------
## However long the real frame was, the simulation advances by at most Tuning.max_frame_delta; a stall (a tab
## switch, a long hitch) is dropped, not simulated; and a couple of frames are skipped after a stall or the
## window coming back, so nothing catches up. While the window is in the background no time accumulates.
## ?perf logs every frame over 50 ms.

var _skip_frames := 0            # frames still to skip after a resume
var _suspended := false          # the window / tab is in the background: the world stands still
var _run_start_ms := 0
var _paused_since_ms := 0
var _paused_total_ms := 0
var _event := ""
var _event_frame := -100

func _note_event(what: String) -> void:
	_event = what
	_event_frame = Engine.get_process_frames()

## The part of this real frame (`raw` seconds) the simulation may use: 0 to skip it.
func _frame_delta(raw: float) -> float:
	var used := 0.0
	var why := ""
	if _suspended:
		why = "window in the background"
	elif _skip_frames > 0:
		_skip_frames -= 1
		why = "skipped (resuming)"
	elif raw > Tuning.stall_delta:
		_skip_frames = Tuning.resume_skip_frames
		why = "stall dropped"
	else:
		used = minf(raw, Tuning.max_frame_delta)
		why = "clamped" if raw > Tuning.max_frame_delta else ""
	if raw > 0.05 and DebugFlags.perf_enabled():
		hud.note_hitch(raw, used, why, _hitch_context())
	return used

func _hitch_context() -> String:
	if Engine.get_process_frames() - _event_frame <= 4 and _event != "":
		return _event
	return "screen %d, flight %d leg %d" % [screen, flight_id + 1, leg + 1]

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			if not _suspended:
				_suspended = true
				_paused_since_ms = Time.get_ticks_msec()
				_note_event("window went to the background")
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			if _suspended:
				_suspended = false
				_paused_total_ms += Time.get_ticks_msec() - _paused_since_ms
				_skip_frames = Tuning.resume_skip_frames
				_note_event("window came back")

## Seconds of this run on the wall clock, without the time spent in the background.
func run_wall_time() -> float:
	return maxf((Time.get_ticks_msec() - _run_start_ms - _paused_total_ms) / 1000.0, 0.0)

func _process(raw_delta: float) -> void:
	if _warming:
		return
	var delta := _frame_delta(raw_delta)
	if DebugFlags.perf_enabled():
		hud.update_perf(raw_delta)
		hud.set_perf_extra("sim %.1f s / wall %.1f s\nflight %d  leg %d/%d  layer %d/%d  wind %.0f px/s\nfuel %.0f  coins %d  hazards %d" % [
			sim_time, run_wall_time(), flight_id + 1, leg + 1, int(Tuning.legs_per_flight), lanes.lane_of(balloon.position.y) + 1, lanes.n_lanes,
			lanes.wind_at(balloon.position.y), fuel, coins_picked, _hazard_total()])
	if delta > 0.0:
		sim(delta)

func _hazard_total() -> int:
	var n := 0
	for i in lanes.n_lanes:
		n += lanes.lane_count[i]
	return n

