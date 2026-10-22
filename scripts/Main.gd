class_name Main
extends Node2D
## Wind Layers: climb a hot air balloon through layers of wind to the goal at the top, Frogger style.
## One scene for the whole session. Restarting is IN PLACE: the pooled hazards, effects and UI nodes
## stay alive (and warm); only the game state is reset.

enum { SCREEN_MENU, SCREEN_PLAY, SCREEN_CLEAR, SCREEN_DEAD, SCREEN_RESULT, SCREEN_MAP, SCREEN_ALBUM, SCREEN_SHOP, SCREEN_TITLE, SCREEN_PREP }
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
var last_daily_bonus := 0
var last_postcard: Array = []        # [region, level] awarded by the Flight just finished
var tune_panel: TunePanel
var lanes: Lanes
var balloon: Balloon
var hud: Hud
var sim_time := 0.0                 # seconds of simulation this Flight (should track the wall clock minus pauses)
var _warming := false
var _prog_key := -1
var ads: Ads
var credited := 0                   # coins of this Flight already paid into the save (a retried leg is not paid twice)
var boosts_used := 0
var retries_used := 0
var snap_fuel := 0.0                # the state at the start of the current leg (a rewarded retry goes back to it)
var snap_coins := 0
var snap_picked := 0
var snap_score := 0
var eff_add := 0.0
var recipe: LegRecipe               # this leg's goal and twists
var tool_charges := PackedInt32Array([0, 0, 0])   # sandbag, anchor, quick vent: charges left this leg
const CONTROL_HINT := "HOLD anywhere to fire the burner and rise. Let go to sink."
var _hinted := false
var sfx: Sfx
var planner: LegPlanner            # self-checking generation: every leg is solved by the fairness planner before it is flown
var _plan_wait := false            # a leg is waiting for its plan (a short "preparing" pause)
var _lt_prev := 0
var paused := false                 # the pause menu is up: the world stands still
var burn_override := -1             # tests: 1 = burner held, 0 = released, -1 = read the real input
var tool_avail: Array = []         # the tools this Flight offers
var _goal_key := -1                  # the Daily Flight is a little harder than its region's mid Flight
var _air_pct := -1
static var _warmed := false         # the pre-warm only ever runs once per page load

func _ready() -> void:
	Engine.max_physics_steps_per_frame = 1   # no physics here: a stall must never trigger catch-up steps
	lanes = $Lanes
	balloon = $Balloon
	balloon.lanes = lanes
	sfx = Sfx.new()
	add_child(sfx)
	planner = LegPlanner.new()
	planner.attach(self)
	hud = $Hud
	if DebugFlags.tune_enabled():
		tune_panel = TunePanel.new()
		add_child(tune_panel)
		tune_panel.build()
		tune_panel.restart_requested.connect(func(): tune_panel.close(); start_flight(flight_id))
		tune_panel.save_changed.connect(_on_save_changed)
	hud.fly_pressed.connect(func(): start_flight(selected))
	hud.prev_pressed.connect(func(): _select(selected - 1))
	hud.next_pressed.connect(func(): _select(selected + 1))
	ads = Ads.new(hud)
	hud.again_pressed.connect(func(): _proceed(func(): start_flight(flight_id)))
	hud.menu_pressed.connect(func(): hud.nav_dir = -1; _proceed(_show_map))
	hud.back_pressed.connect(func(): hud.nav_dir = -1; _show_map())
	hud.daily_pressed.connect(_open_daily)
	hud.boost_pressed.connect(_on_boost)
	hud.next_leg_pressed.connect(next_leg)
	hud.retry_pressed.connect(_on_retry)
	hud.album_pressed.connect(_show_album)
	hud.album_closed.connect(func(): hud.nav_dir = -1; _show_map())
	hud.shop_pressed.connect(_show_shop)
	hud.pause_pressed.connect(pause_game)
	hud.resume_pressed.connect(resume_game)
	hud.restart_pressed.connect(func(): resume_game(); start_flight(flight_id))
	hud.quit_pressed.connect(func(): resume_game(); hud.nav_dir = -1; _show_map())
	hud.title_play_pressed.connect(_show_map)
	hud.home_pressed.connect(func(): hud.nav_dir = -1; _show_title())
	hud.logo_finished.connect(_after_logo)
	hud.shop_closed.connect(func(): hud.nav_dir = -1; _show_map())
	hud.flight_chosen.connect(func(id: int): selected = id; _show_menu())
	hud.next_flight_pressed.connect(func(): _proceed(_on_next_flight))
	selected = Save.suggested_flight()
	_set_flight(selected)
	plan_leg(0)
	lanes.daylight = 0.0
	lanes.setup(_eff(0), false, Flights.leg_seed(flight_seed, 0), flight_region)
	balloon.reset()
	fuel = Tuning.propane_start
	hud.set_fuel(1.0)
	if not _warmed:
		_warmed = true
		if DebugFlags.prewarm_enabled():
			_prewarm()
			return
	_after_boot()
	if tune_panel:
		tune_panel.set_available(true)

func _set_flight(id: int) -> void:
	flight_id = id
	if id == Flights.DAILY:   # the Daily Flight: today's seed and region, the region's mid Flight, a bit harder
		var day := Flights.today()
		flight_region = Flights.daily_region(day)
		flight_index = Flights.DAILY_INDEX
		flight_seed = Flights.daily_seed(day)
		eff_add = Tuning.daily_level_bonus
	else:
		flight_region = Flights.region_of(id)
		flight_index = Flights.index_of(id)
		flight_seed = Flights.seed_of(id)
		eff_add = 0.0

func _eff(l: int) -> float:
	return Flights.eff_level(flight_region, flight_index, l) + eff_add

func _flight_name(id: int) -> String:
	if id == Flights.DAILY:
		return "DAILY FLIGHT"
	return "%s %d" % [String(Regions.NAMES[Flights.region_of(id)]).to_upper(), Flights.index_of(id) + 1]

# ---- map and Flight screen ----

func _select(id: int) -> void:
	selected = clampi(id, 0, Flights.TOTAL - 1) if id != Flights.DAILY else id
	_refresh_menu()

## After the start-up pre-warm: the logo intro (skippable) if it is on, then the title screen (or straight to the map).
func _after_boot() -> void:
	if DebugFlags.audiocheck_enabled():   # the web audio check: Flight 1 at once, the script drives burner and sounds
		Tuning.leg_check = false
		start_flight(0)
		return
	if DebugFlags.autoplay_flight() >= 0:   # web checks: straight into a Flight (no logo, title or planning pause)
		Tuning.leg_check = false
		start_flight(DebugFlags.autoplay_flight())
		return
	if Tuning.intro_logo:
		hud.hide_overlays()
		hud.intro.start(Tuning.intro_seconds)
		sfx.set_music(1)
	else:
		_after_logo()

func _after_logo() -> void:
	if Tuning.title_screen:
		_show_title()
	else:
		_show_map()

func _show_title() -> void:
	screen = SCREEN_TITLE
	get_tree().paused = false
	lanes.visible = false
	balloon.visible = false
	hud.set_flight_hud(false)
	hud.show_title()
	sfx.set_music(1)

## The pause menu: the world stands still (the pause button, or the window losing focus).
func pause_game() -> void:
	if screen != SCREEN_PLAY or paused or _warming:
		return
	paused = true
	sfx.quiet()
	hud.show_pause()

func resume_game() -> void:
	if not paused:
		return
	paused = false
	sfx.release()   # (the player tapped Resume: the page's audio may run again)
	hud.hide_pause()

## The world map (the home screen).
func _exit_tree() -> void:
	if planner != null:
		planner.detach()

func _show_map() -> void:
	_plan_wait = false
	screen = SCREEN_MAP
	get_tree().paused = false
	lanes.visible = false
	balloon.visible = false
	hud.set_flight_title("")
	hud.set_score(0)
	hud.set_flight_coins(0)
	hud.set_air("")
	hud.set_flight_hud(false)
	hud.show_map()
	sfx.set_music(1)

func _show_shop() -> void:
	screen = SCREEN_SHOP
	lanes.visible = false
	balloon.visible = false
	hud.set_flight_hud(false)
	hud.show_shop()
	sfx.set_music(1)

func _show_album() -> void:
	screen = SCREEN_ALBUM
	lanes.visible = false
	balloon.visible = false
	hud.set_flight_hud(false)
	hud.show_album()
	sfx.set_music(1)

## The Flight screen: name, stars, what each star needs, FLY.
func _show_menu() -> void:
	screen = SCREEN_MENU
	lanes.visible = true
	balloon.visible = true
	_set_flight(selected)
	lanes.daylight = 0.0
	lanes.setup(_eff(0), false, Flights.leg_seed(flight_seed, 0), flight_region)
	balloon.reset()
	hud.set_flight_title("")
	hud.set_air("")
	hud.set_flight_hud(false)
	_refresh_menu()

## A ?tune debug button changed the save: redraw whatever screen is up, so nothing needs a reload.
func _on_save_changed() -> void:
	match screen:
		SCREEN_MAP:
			hud.map.refresh()
		SCREEN_MENU:
			_refresh_menu()
		SCREEN_ALBUM:
			hud.album.refresh()
		SCREEN_SHOP:
			hud.shop.refresh()

func _open_daily() -> void:
	selected = Flights.DAILY
	_show_menu()

func _refresh_menu() -> void:
	if screen != SCREEN_MENU:
		return
	if selected == Flights.DAILY:
		var day := Flights.today()
		var dr := Flights.daily_region(day)
		var done := Save.daily_done(day)
		var dinfo := "One Flight a day, the same for everyone that day.\n%s\nBonus %d coins, +%d for every day of the streak.\nStreak: %d day%s" % [
			"Completed today: no bonus until tomorrow." if done else "Complete it for the daily bonus!",
			roundi(Tuning.daily_bonus_coins), roundi(Tuning.daily_streak_bonus), Save.daily_streak_now(day), "" if Save.daily_streak_now(day) == 1 else "s"]
		hud.show_menu(Regions.NAMES[dr], Regions.BLURB[dr], "DAILY FLIGHT", false, false, false, dinfo, false, false, true, true)
		return
	var id := selected
	var st := Save.stars_of(id)
	var open := Save.flight_unlocked(id)
	var info := "Locked: complete the Flight before it." if not open else "Finish all %d legs\nFinish with %d propane or more\nCollect %d of %d coins\nbest score %s     coins %s" % [
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
	var shop_tick := 0
	while true:
		var now := Time.get_ticks_msec()
		if now - t_burst > 350:
			t_burst = now
			lanes.burst(Vector2(300, 900), Lanes.C_TANK, 12, 300.0)
			lanes.burst(Vector2(780, 900), Color(1.0, 0.5, 0.15), 12, 300.0)
		balloon.warm_visuals()   # (every part of the rig, the glow, flame, ropes and streamers drawn for real)
		if DebugFlags.preview_enabled():   # (warms the debug preview's meshes too)
			lanes.preview_balloon = balloon
			balloon.predict(true)
		hud.shop.prewarm_show(shop_tick % 26)
		shop_tick += 1
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
	lanes.preview_balloon = null
	balloon.heat = 0.0
	lanes.setup(Flights.eff_level(0, 0, 0), false, Flights.leg_seed(Flights.seed_of(0), 0), 0)
	hud.end_prewarm()
	if tune_panel:
		tune_panel.prewarm_show(false)
		tune_panel.set_available(true)
	_warming = false
	_after_boot()

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
	credited = 0
	boosts_used = 0
	retries_used = 0
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

## Ask the planner to work out leg `l` of the current Flight (while a menu / the leg-complete screen is up).
func plan_leg(l: int) -> void:
	if Tuning.leg_check and l < int(Tuning.legs_per_flight):
		planner.request(_eff(l), Flights.leg_seed(flight_seed, l), flight_region, flight_id, l)

func _begin_leg() -> void:
	var leg_seed_v := Flights.leg_seed(flight_seed, leg)
	var sparse_leg := false
	if Tuning.leg_check:
		var plan = planner.get_plan(_eff(leg), leg_seed_v, flight_region, flight_id, leg)
		if plan == null:   # not planned yet (the player was quicker than the planner): a short pause
			plan_leg(leg)
			_plan_wait = true
			screen = SCREEN_PREP
			hud.show_banner("PREPARING THE SKY...", 60.0)
			return
		leg_seed_v = plan[0]
		sparse_leg = plan[1]
	_plan_wait = false
	recipe = Flights.leg_recipe(flight_id, leg, leg_seed_v)
	lanes.daylight = float(leg) / maxf(Tuning.legs_per_flight - 1.0, 1.0)
	lanes.setup(_eff(leg), false, leg_seed_v, flight_region, recipe, sparse_leg)
	lanes.visible = true
	_goal_key = -1
	tool_avail = Flights.tools_for(flight_region, flight_index)
	tool_charges[0] = int(Tuning.sandbag_charges)
	tool_charges[1] = int(Tuning.anchor_charges)
	tool_charges[2] = int(Tuning.vent_charges)
	lanes.clear_fx()
	balloon.reset()
	balloon.visible = true
	leg_time = 0.0
	leg_started = false
	snap_fuel = fuel
	snap_coins = flight_coins
	snap_picked = coins_picked
	snap_score = score
	hud.set_flight_hud(true)
	hud.reset_goal()
	hud.set_goal_icon(recipe.goal)
	sfx.set_music(2)
	hud.hide_overlays()
	hud.set_flight_title("%s   LEG %d/%d" % [_flight_name(flight_id), leg + 1, int(Tuning.legs_per_flight)])
	hud.set_fuel(fuel / Tuning.propane_start)
	_air_pct = -1
	_prog_key = -1
	_update_progress()
	_sync_tools()
	for t in tool_avail:   # a new tool gets a one-line intro the first time it is on offer
		if not Save.tool_seen(t):
			Save.mark_tool_seen(t)
			hud.show_hint(_tool_intro(t), 5.0)
			break
	if leg == 0 and not _hinted and not hud.hint_label.visible:   # (once per page load)
		_hinted = true
		hud.show_hint(CONTROL_HINT, 4.5)
	screen = SCREEN_PLAY

func _update_progress() -> void:
	var key := int(fuel) * 1000 + coins_picked * 10 + leg
	if key != _prog_key:
		_prog_key = key
		hud.set_progress(leg, int(Tuning.legs_per_flight), fuel, coins_picked, Flights.coin_target())

## The Flight ends here: a failed leg (crash, or stranded without propane). Coins already earned are kept.
func _fail(reason: String) -> void:
	screen = SCREEN_DEAD
	sfx.quiet()
	hud.set_flight_hud(false)
	last_reason = reason
	last_stars = 0
	_credit()
	Save.note_flight_ended()
	var can_retry := Tuning.ads_enabled and retries_used < int(Tuning.ad_retry_max_per_flight)
	hud.show_dead("Leg %d of %d\n%s\nCoins kept: %d" % [leg + 1, int(Tuning.legs_per_flight), reason, flight_coins], can_retry)

func _crash(kind: int) -> void:
	lanes.burst(balloon.position, Color(1.0, 0.45, 0.15), 10, 360.0)
	lanes.burst(balloon.position, Color(0.75, 0.75, 0.8), 8, 200.0)   # a puff of smoke
	lanes.ring(balloon.position, Color(1.0, 0.7, 0.3), 120.0, 0.45)
	balloon.start_deflate()
	sfx.play_deflate()
	_fail("Crashed into %s" % Lanes.KIND_NAME[kind])

func _clear_leg() -> void:
	var par := Tuning.par_base + Tuning.par_per_layer * float(lanes.n_lanes)
	last_bonus = roundi(maxf(par - leg_time, 0.0) * Tuning.speed_bonus_per_s)
	score += roundi(Tuning.level_points) + last_bonus
	flight_coins += roundi(Tuning.leg_coins)
	hud.set_score(score)
	hud.set_flight_coins(flight_coins)
	sfx.play("cheer")
	lanes.burst(balloon.position, Color(1.0, 0.85, 0.3), 14, 380.0)
	lanes.burst(balloon.position, Color(0.4, 0.9, 1.0), 14, 380.0)
	lanes.ring(balloon.position + Vector2(0, 90.0 * balloon.s()), Color(1, 1, 1), 190.0, 0.6)
	lanes.ring(balloon.position + Vector2(0, 90.0 * balloon.s()), Color(1.0, 0.85, 0.3), 120.0, 0.45)
	balloon.cheer(1.6)
	fuel = minf(fuel + Tuning.leg_refill, Tuning.propane_start)
	leg += 1
	if leg >= int(Tuning.legs_per_flight):
		_finish_flight()
		return
	_prog_key = -1
	_update_progress()
	plan_leg(leg)
	hud.set_flight_hud(false)
	hud.show_leg_done(Regions.NAMES[flight_region], flight_index + 1, leg, int(Tuning.legs_per_flight), fuel / Tuning.propane_start, _can_boost())
	sfx.set_music(1)
	clear_left = CLEAR_HOLD
	screen = SCREEN_CLEAR

func _finish_flight() -> void:
	last_propane_bonus = roundi(fuel * Tuning.propane_coins)
	flight_coins += last_propane_bonus
	last_stars = Flights.stars_for(true, fuel, coins_picked)
	var had := Save.stars_of(flight_id)
	var daily := flight_id == Flights.DAILY
	last_daily_bonus = 0
	if daily:   # the Daily Flight: a bonus for the first completion of the day and the streak; no stars are recorded
		last_daily_bonus = Save.complete_daily(Flights.today())
		flight_coins += last_daily_bonus
	else:
		Save.record_flight(flight_id, last_stars, score)
	_credit()
	Save.note_flight_ended()
	hud.set_flight_hud(false)
	screen = SCREEN_RESULT
	var tgt_p := int(Flights.propane_target())
	var summary := "Score %s\nCoins earned: %d   (propane bonus %d)" % [Tuning.fmt(float(score)), flight_coins, last_propane_bonus]
	if daily:
		var day := Flights.today()
		summary += ("\nDAILY BONUS +%d   streak %d day%s" % [last_daily_bonus, Save.daily_streak_now(day), "" if Save.daily_streak_now(day) == 1 else "s"]) if last_daily_bonus > 0 else "\nDaily bonus already claimed today"
	else:
		summary += ("\nNEW BEST: %d stars" % last_stars if last_stars > had else "") + _region_news()
	hud.result_header.text = "DAILY FLIGHT COMPLETE!" if daily else "FLIGHT COMPLETE!"
	hud.show_result("Flight completed",
		"Propane left %d  (needs %d)" % [int(fuel), tgt_p],
		"Coins collected %d  (needs %d)" % [coins_picked, Flights.coin_target()],
		true, last_stars >= 2 and fuel >= Flights.propane_target(), coins_picked >= Flights.coin_target(),
		summary, not daily and flight_id + 1 < Flights.TOTAL and Flights.region_of(flight_id + 1) == flight_region and Save.flight_unlocked(flight_id + 1), fuel / Tuning.propane_start)
	last_postcard = []
	if not daily:
		var pc := Save.update_postcards()   # the region's last Flight earns its postcard; 3 stars on all six make it gold
		if not pc.is_empty():
			last_postcard = pc
			hud.show_postcard(pc[0], pc[1])

## Pay the coins earned so far into the save (only what has not been paid yet).
func _credit() -> void:
	var d := flight_coins - credited
	if d > 0:
		Save.add_coins(d)
		credited = flight_coins

## Between Flights (result / failed screens) an interstitial may come first; then `action` runs.
func _proceed(action: Callable) -> void:
	if (screen == SCREEN_DEAD or screen == SCREEN_RESULT) and Save.interstitial_due() and not ads.is_showing():
		Save.interstitial_shown()
		ads.show("interstitial", func(_ok: bool): action.call())
	else:
		action.call()

## The leg-complete screen's NEXT LEG button.
func next_leg() -> void:
	if screen == SCREEN_CLEAR and clear_left <= 0.0 and not paused:
		_begin_leg()

func _can_boost() -> bool:
	return Tuning.ads_enabled and boosts_used < int(Tuning.ad_boost_max_per_flight) and fuel <= Tuning.ad_boost_below * Tuning.propane_start

## Rewarded: "+50% propane" on the ground at the start of a leg, or on the leg-complete screen for the next one.
func _on_boost() -> void:
	if (screen != SCREEN_PLAY and screen != SCREEN_CLEAR) or ads.is_showing():
		return
	ads.show("boost", func(ok: bool):
		if ok:
			boosts_used += 1
			fuel = minf(fuel + Tuning.propane_start * Tuning.ad_boost_frac, Tuning.propane_start)
			hud.set_fuel(fuel / Tuning.propane_start)
			_update_progress()
			if screen == SCREEN_CLEAR:
				hud.show_leg_done(Regions.NAMES[flight_region], flight_index + 1, leg, int(Tuning.legs_per_flight), fuel / Tuning.propane_start, _can_boost()))

## Rewarded: "Retry this leg" after a failed one: back to the start of the leg with its propane, coins and score.
func _on_retry() -> void:
	if screen != SCREEN_DEAD or ads.is_showing():
		return
	ads.show("retry", func(ok: bool):
		if ok:
			retries_used += 1
			fuel = snap_fuel
			flight_coins = snap_coins
			coins_picked = snap_picked
			score = snap_score
			hud.set_score(score)
			hud.set_flight_coins(flight_coins)
			_begin_leg())

func _update_boost_button() -> void:
	var want := Tuning.ads_enabled and balloon.on_ground and not leg_started and boosts_used < int(Tuning.ad_boost_max_per_flight) and fuel <= Tuning.ad_boost_below * Tuning.propane_start
	if want != hud.boost_btn.visible:
		hud.boost_btn.visible = want

## "NEW REGION UNLOCKED" for the result screen, once per region.
func _region_news() -> String:
	var r := Save.take_new_region()
	return "\nNEW REGION UNLOCKED: %s!" % Regions.NAMES[r] if r >= 0 else ""

func _on_tool_button(pos: Vector2) -> bool:
	for i in 3:
		if tool_avail.has(i) and Hud.TOOL_RECTS[i].has_point(pos):
			return true
	return false

## Is the player holding (a finger or the mouse anywhere on the playfield, Space or Up)? Hold = burn.
func _holding() -> bool:
	if paused:
		return false
	if burn_override >= 0:
		return burn_override == 1
	if (tune_panel and tune_panel.is_open) or hud.ad_active or paused:
		return false
	if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		return true
	var mouse := get_viewport().get_mouse_position()
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _tap_free(mouse)

## Is a touch at pos on the playfield (not on a tool, the boost button or the TUNE button)?
func _tap_free(pos: Vector2) -> bool:
	if (tune_panel and tune_panel.is_open) or hud.ad_active:
		return false
	return not TunePanel.button_hit(pos) and not (hud.boost_btn.visible and hud.boost_btn.get_global_rect().has_point(pos)) and not _on_tool_button(pos)

## One simulation step of `dt` seconds.
func sim(dt: float) -> void:
	if hud.ad_active or paused:   # an ad or the pause menu is up: the world stands still
		return
	sim_time += dt
	hud.tick(dt)
	match screen:
		SCREEN_PLAY:
			_play(dt)
		SCREEN_CLEAR:
			lanes.preview_balloon = null
			lanes.update(dt)
			balloon.idle_step(dt)
			sfx.quiet()
			clear_left = maxf(clear_left - dt, 0.0)
		_:
			lanes.preview_balloon = null
			lanes.update(dt)
			balloon.idle_step(dt)
			sfx.quiet()

func _play(dt: float) -> void:
	lanes.focus_lane = lanes.lane_of(balloon.position.y)
	var goal := recipe.goal
	# Until the leg's goal is met the balloon cannot go through the top; a landing leg lets it fly higher.
	var blocked := (goal == Flights.STARS and lanes.stars_left() > 0) or (goal == Flights.DELIVERY and lanes.mail_state < 2)
	balloon.ceiling_y = Lanes.CEILING_Y if goal == Flights.LANDING else (Lanes.GOAL_Y + 14.0 if blocked else -100000.0)
	lanes.storm_go = leg_started and leg_time >= Tuning.storm_start_delay
	var climb_mult := lanes.climb_mult_at(balloon.position.y)
	var hold := _holding()
	balloon.step(dt, hold, fuel > 0.0, lanes.thermal_lift(balloon.position.x), climb_mult)
	sfx.fly(dt, balloon.flame_power, balloon.sputter, balloon.wind_alt, balloon._swing_v, lanes.storm_on and lanes.storm_go)
	if lanes.lt_state != _lt_prev:
		_lt_prev = lanes.lt_state
		if lanes.lt_state == 1:
			sfx.play("warn")
		elif lanes.lt_state == 2:
			sfx.play("thunder")
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
	lanes.preview_balloon = balloon if DebugFlags.preview_enabled() else null
	if lanes.preview_balloon:
		balloon.predict(fuel > 0.0)
	lanes.update(dt)
	var got := lanes.collect(balloon)
	if got > 0:
		fuel = minf(fuel + Tuning.propane_refill * float(got), Tuning.propane_start)
		sfx.play("pickup")
	var cn := lanes.collect_coins(balloon)
	if cn > 0:
		sfx.play("coin")
		coins_picked += cn
		flight_coins += cn * roundi(Tuning.coin_value)
		hud.set_flight_coins(flight_coins)
	hud.set_fuel(fuel / Tuning.propane_start)
	_update_progress()
	_update_boost_button()
	_update_goal()
	var landed := 0
	if goal == Flights.LANDING:
		landed = lanes.ship_contact(balloon)
	if not DebugFlags.god and lanes.hits(balloon):
		_crash(lanes.last_hit_kind)
	elif not DebugFlags.god and lanes.lightning_hits(balloon):
		_fail("Struck by lightning")
	elif not DebugFlags.god and lanes.storm_hits(balloon):
		_fail("Caught by the storm")
	elif landed == 1:
		_clear_leg()
	elif landed == 2:
		_fail("Hard landing on the airship")
	elif goal != Flights.LANDING and not blocked and balloon.position.y <= Lanes.GOAL_Y:
		_clear_leg()
	elif fuel <= 0.0 and balloon.on_ground:
		_fail("Out of propane: stranded on the ground")

## A mooring handoff: a ring on the platform, sparks, a bell, a cheer from the passenger.
func _handoff(which: int) -> void:
	var dp := lanes.dock_pos(which)
	var col := Color(0.3, 0.8, 0.4) if which == 0 else Color(0.9, 0.3, 0.3)
	lanes.ring(dp, col, 150.0, 0.6)
	lanes.ring(dp, Color(1, 1, 1), 90.0, 0.4)
	lanes.burst(dp, col, 10, 260.0)
	sfx.play("unlock" if which == 1 else "pickup")
	balloon.cheer(1.0)

## Goal progress: collect stars, pick up and deliver the mail; and the goal line of the HUD.
func _update_goal() -> void:
	match recipe.goal:
		Flights.STARS:
			var got := lanes.collect_stars(balloon)
			if got > 0:
				sfx.play("star")
				balloon.cheer(0.7)
				hud.show_banner("STAR!  %d LEFT" % lanes.stars_left() if lanes.stars_left() > 0 else "ALL STARS! GO UP!", 0.8)
			var key := 1 if lanes.stars_left() > 0 else 2   # (no running count on the sky: the star goals live on the leg-complete screen)
			if key != _goal_key:
				_goal_key = key
				hud.set_goal_text("Collect the stars, then climb" if key == 1 else "All stars! Climb to the bunting")
		Flights.DELIVERY:
			if lanes.mail_state == 0 and lanes.at_dock(balloon, 0):
				lanes.mail_state = 1
				_handoff(0)
				hud.show_banner("MAIL PICKED UP!", 1.0)
			elif lanes.mail_state == 1 and lanes.at_dock(balloon, 1):
				lanes.mail_state = 2
				_handoff(1)
				hud.show_banner("DELIVERED! GO UP!", 1.0)
			if lanes.mail_state != _goal_key:
				_goal_key = lanes.mail_state
				hud.set_goal_text(["Mail: pick it up at the GREEN flag", "Mail on board: drop it at the RED flag", "Mail delivered: climb to the bunting"][lanes.mail_state])
		Flights.STORM:
			if _goal_key != 1:
				_goal_key = 1
				hud.set_goal_text("A storm is rising: keep climbing")
		Flights.LANDING:
			if _goal_key != 1:
				_goal_key = 1
				hud.set_goal_text("Land gently on the airship's deck")
		_:
			if _goal_key != 1:
				_goal_key = 1
				hud.set_goal_text("Climb to the bunting")

# ---- player tools ----

func _tool_intro(t: int) -> String:
	match t:
		0:
			return "NEW TOOL: SANDBAG. Tap it for an instant climb burst, free (%d per leg)." % int(Tuning.sandbag_charges)
		1:
			return "NEW TOOL: ANCHOR. Tap it to stop drifting sideways for %d seconds; the burner still works (%d per leg)." % [int(Tuning.anchor_seconds), int(Tuning.anchor_charges)]
	return "NEW TOOL: QUICK VENT. Tap it to dump hot air for a strong descent burst (%d per leg)." % int(Tuning.vent_charges)

func _sync_tools() -> void:
	for i in 3:
		hud.set_tool(i, tool_avail.has(i), tool_charges[i])

## Use tool i (0 sandbag, 1 anchor, 2 quick vent): only while flying, if it is on offer and has a charge left.
func use_tool(i: int) -> bool:
	if screen != SCREEN_PLAY or hud.ad_active or paused or not tool_avail.has(i) or tool_charges[i] <= 0:
		return false
	tool_charges[i] -= 1
	match i:
		0:
			balloon.use_sandbag()
			sfx.play("thunk")
			lanes.burst(balloon.position + Vector2(0, 70), Color(0.85, 0.7, 0.4), 8, 240.0)
		1:
			balloon.use_anchor()
			sfx.play("anchor")
		2:
			balloon.use_vent()
			sfx.play("vent", 1.3)
			lanes.burst(balloon.position + Vector2(0, -50), Color(1, 1, 1), 8, 200.0)
	_sync_tools()
	return true

## Touches on the tool buttons (handled here so a second finger works while the first holds the burner).
func _input(event: InputEvent) -> void:
	if sfx.held and screen != SCREEN_PLAY and ((event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed)):
		sfx.release()   # (menus have no Resume button: the first tap after coming back brings the sound back)
	if not sfx.unlocked and ((event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed)):
		sfx.unlock()
	if _warming or screen != SCREEN_PLAY or paused:
		return
	var pos := Vector2(-1, -1)
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		pos = event.position   # (a mouse click; the emulated mouse of a touch is skipped: the touch itself is handled above)
	if pos.x < 0.0:
		return
	for i in 3:
		if tool_avail.has(i) and Hud.TOOL_RECTS[i].has_point(pos):
			use_tool(i)
			return

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
				pause_game()   # (a flight in progress waits on the pause menu)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			if _suspended:
				_suspended = false
				_paused_total_ms += Time.get_ticks_msec() - _paused_since_ms
				_skip_frames = Tuning.resume_skip_frames
				_note_event("window came back")

## Web: the page went to the background (it flags that itself, even when the engine gets no focus event): hold every sound, pause the
## flight. Sound only returns when the player taps Resume (or, on the menus, the first tap after coming back).
func _audio_background() -> void:
	if not OS.has_feature("web"):
		return
	if not _page_ready:
		_page_ready = true
		JavaScriptBridge.eval("window.__pwGameReady = true")
	if not sfx.held and bool(JavaScriptBridge.eval("!!window.__pwHidden")):
		sfx.hold()
		pause_game()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__pw = window.__pw || {}; window.__pw.paused = %s; window.__pw.held = %s; window.__pw.screen = %d" % [str(paused).to_lower(), str(sfx.held).to_lower(), screen])

var _page_ready := false
var _drv_t := 0.0
var _drv_i := 0
const _DRV_SOUNDS := ["pickup", "coin", "star", "thunk", "slam", "warn", "vent", "cheer"]

## ?audiocheck: pulse the burner and fire a gameplay sound every half second so the web check hears every layer.
func _audio_driver(dt: float) -> void:
	if not DebugFlags.audiocheck_enabled() or screen != SCREEN_PLAY or paused or sfx.held:
		return
	_drv_t += dt
	burn_override = 1 if fmod(_drv_t, 4.0) < 2.2 else 0
	if _drv_t > float(_drv_i + 1) * 0.5:
		_drv_i += 1
		sfx.play(_DRV_SOUNDS[_drv_i % _DRV_SOUNDS.size()])

## Seconds of this run on the wall clock, without the time spent in the background.
func run_wall_time() -> float:
	return maxf((Time.get_ticks_msec() - _run_start_ms - _paused_total_ms) / 1000.0, 0.0)

func _process(raw_delta: float) -> void:
	if _warming:
		return
	_audio_background()
	_audio_driver(raw_delta)
	var delta := _frame_delta(raw_delta)
	if screen != SCREEN_PLAY and planner.busy():   # (never while a leg is being flown: nothing is solved, nothing allocated, during play)
		planner.tick(int(Tuning.plan_budget_ms * 1000.0))
	if _plan_wait and not planner.busy():
		_begin_leg()
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

