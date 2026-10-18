class_name Main
extends Node2D
## Wind Layers: climb a hot air balloon through layers of wind to the goal at the top, Frogger style.
## One scene for the whole session. Restarting is IN PLACE: the pooled hazards, effects and UI nodes
## stay alive (and warm); only the game state is reset.

enum { SCREEN_MENU, SCREEN_PLAY, SCREEN_CLEAR, SCREEN_DEAD }
const SAVE_PATH := "user://wind_layers.cfg"
## Seconds the "level cleared" banner holds before the next level starts, and the pause before a
## tap restarts after a crash (so a held finger doesn't skip the result).
const CLEAR_HOLD := 1.3
const RETRY_DELAY := 0.5

var screen := SCREEN_MENU
var level := 1
var score := 0
var best := 0
var fuel := 0.0
var level_time := 0.0
var dead_time := 0.0
var clear_left := 0.0
var last_reason := ""
var last_bonus := 0
var persist := true                 # tests switch the save file off
var burn_override := -1             # tests: 1 = burner held, 0 = released, -1 = read the real input
var tune_panel: TunePanel
var lanes: Lanes
var balloon: Balloon
var hud: Hud
var sim_time := 0.0                 # seconds of simulation this run (should track the wall clock minus pauses)
var _warming := false
static var _warmed := false         # the pre-warm only ever runs once per page load

func _ready() -> void:
	Engine.max_physics_steps_per_frame = 1   # no physics here: a stall must never trigger catch-up steps
	lanes = $Lanes
	balloon = $Balloon
	hud = $Hud
	_load_best()
	if DebugFlags.tune_enabled():
		tune_panel = TunePanel.new()
		add_child(tune_panel)
		tune_panel.build()
		tune_panel.restart_requested.connect(func(): tune_panel.close(); restart())
	level = DebugFlags.start_level
	lanes.setup(level)
	balloon.reset()
	hud.set_level(level)
	hud.set_score(0)
	hud.set_best(best)
	hud.set_fuel(1.0)
	fuel = Tuning.propane_start
	if not _warmed:
		_warmed = true
		if DebugFlags.prewarm_enabled():
			_prewarm()
			return
	_show_menu()
	if tune_panel:
		tune_panel.set_available(true)

func _show_menu() -> void:
	screen = SCREEN_MENU
	balloon.visible = true
	hud.show_menu()

## First-use stutter fix: GL shaders / buffers / font glyphs set themselves up the first time they are
## used. So at boot, behind a splash screen, draw EVERY shape for real (all hazard kinds in both
## directions, pickups, streamers, the burner flame, a spark burst, every label and the tune panel)
## and KEEP drawing until frame times settle. Then hide it all. Skip with ?noprewarm.
func _prewarm() -> void:
	_warming = true
	hud.begin_prewarm()
	lanes.setup(1, true)
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
	lanes.setup(level)
	balloon.reset()
	hud.end_prewarm()
	if tune_panel:
		tune_panel.prewarm_show(false)
		tune_panel.set_available(true)
	_warming = false
	_show_menu()

# ---------------------------------------------------------------------------------------------------------
# Run flow
# ---------------------------------------------------------------------------------------------------------

## Start a fresh run IN PLACE. Nothing is reloaded, created or freed.
func restart() -> void:
	level = DebugFlags.start_level
	score = 0
	fuel = Tuning.propane_start
	sim_time = 0.0
	_run_start_ms = Time.get_ticks_msec()
	_paused_total_ms = 0
	_skip_frames = 0
	if tune_panel and tune_panel.is_open:
		tune_panel.close()
	get_tree().paused = false
	hud.set_score(0)
	hud.set_best(best)
	_begin_level()

func _begin_level() -> void:
	lanes.setup(level)
	lanes.clear_fx()
	balloon.reset()
	balloon.visible = true
	level_time = 0.0
	hud.hide_overlays()
	hud.set_level(level)
	hud.set_fuel(fuel / Tuning.propane_start)
	hud.show_banner("LEVEL %d" % level, 1.0)
	screen = SCREEN_PLAY

func _end_run(reason: String) -> void:
	screen = SCREEN_DEAD
	dead_time = 0.0
	last_reason = reason
	var new_best := score > best
	if new_best:
		best = score
		_save_best()
	hud.show_over(reason, score, level, best, new_best)
	hud.set_best(best)

func _crash(kind: int) -> void:
	lanes.burst(balloon.position, Color(1.0, 0.45, 0.15), 18, 420.0)
	lanes.burst(balloon.position, Color(1.0, 0.9, 0.4), 10, 300.0)
	balloon.visible = false
	_end_run("Crashed into %s" % Lanes.KIND_NAME[kind])

func _clear_level() -> void:
	var par := Tuning.par_base + Tuning.par_per_layer * float(lanes.n_lanes)
	last_bonus = roundi(maxf(par - level_time, 0.0) * Tuning.speed_bonus_per_s)
	score += roundi(Tuning.level_points) + last_bonus
	hud.set_score(score)
	lanes.burst(balloon.position, Color(1.0, 0.85, 0.3), 14, 380.0)
	lanes.burst(balloon.position, Color(0.4, 0.9, 1.0), 14, 380.0)
	hud.show_banner("LEVEL %d CLEARED\n+%d  speed +%d" % [level, roundi(Tuning.level_points), last_bonus], CLEAR_HOLD)
	level += 1
	fuel = minf(fuel + Tuning.level_refill, Tuning.propane_start)
	clear_left = CLEAR_HOLD
	screen = SCREEN_CLEAR

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
				_begin_level()
		SCREEN_DEAD:
			dead_time += dt
			lanes.update(dt)
		_:
			lanes.update(dt)

func _play(dt: float) -> void:
	level_time += dt
	balloon.step(dt, _holding(), fuel > 0.0, lanes.wind_at(balloon.position.y))
	if balloon.burning:
		fuel = maxf(fuel - Tuning.burn_rate * dt, 0.0)
	lanes.update(dt)
	var got := lanes.collect(balloon)
	if got > 0:
		fuel = minf(fuel + Tuning.propane_refill * float(got), Tuning.propane_start)
	hud.set_fuel(fuel / Tuning.propane_start)
	if not DebugFlags.god and lanes.hits(balloon):
		_crash(lanes.last_hit_kind)
	elif balloon.position.y <= Lanes.GOAL_Y:
		_clear_level()
	elif fuel <= 0.0 and balloon.on_ground:
		_end_run("Out of propane: stranded on the ground")

func _input(event: InputEvent) -> void:
	if _warming:
		return
	var pressed := false
	var pos := Vector2(-1, -1)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
		pos = event.position
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_UP, KEY_ENTER]:
		pressed = true
	if not pressed:
		return
	if tune_panel and (tune_panel.is_open or TunePanel.button_hit(pos)):
		return   # a tap on the TUNE button (or while its panel is up) is not a game tap
	match screen:
		SCREEN_MENU:
			restart()
		SCREEN_DEAD:
			if dead_time >= RETRY_DELAY:
				restart()

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
	return "screen %d, level %d" % [screen, level]

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
		hud.set_perf_extra("sim %.1f s / wall %.1f s\nlevel %d  layer %d/%d  wind %.0f px/s\nfuel %.0f  hazards %d" % [
			sim_time, run_wall_time(), level, lanes.lane_of(balloon.position.y) + 1, lanes.n_lanes,
			lanes.wind_at(balloon.position.y), fuel, _hazard_total()])
	if delta > 0.0:
		sim(delta)

func _hazard_total() -> int:
	var n := 0
	for i in lanes.n_lanes:
		n += lanes.lane_count[i]
	return n

# ---------------------------------------------------------------------------------------------------------
# Save (best score only)
# ---------------------------------------------------------------------------------------------------------

func _load_best() -> void:
	if not persist:
		return
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best = int(cf.get_value("score", "best", 0))

func _save_best() -> void:
	if not persist:
		return
	var cf := ConfigFile.new()
	cf.set_value("score", "best", best)
	cf.save(SAVE_PATH)
