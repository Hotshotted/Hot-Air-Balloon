class_name Hud
extends CanvasLayer
## All on-screen text, panels and buttons. Every node is created once in _ready (and drawn during the
## start-up pre-warm); after that labels are only re-texted when a value changes and panels are only
## shown / hidden. Buttons emit the signals below; Main decides what they mean.

signal fly_pressed
signal prev_pressed
signal next_pressed
signal again_pressed
signal menu_pressed
signal next_flight_pressed
signal back_pressed
signal album_pressed
signal album_closed
signal shop_pressed
signal shop_closed
signal cosmetics_changed
signal daily_pressed
signal boost_pressed
signal retry_pressed
signal ad_finished(rewarded: bool)
signal flight_chosen(id: int)

var level_label: Label
var score_label: Label
var coins_label: Label
var stamp_label: Label
var banner: Label
var splash: ColorRect
var gauge: Control
var air_label: Label
var goal_label: Label
var hint_label: Label
var tool_btns: Array[Button] = []
var _hint_left := 0.0
var _goal_cache := ""
var map: MapScreen
var album: AlbumScreen
var shop: ShopScreen
var boost_btn: Button
var retry_btn: Button
var ad_p: Control
var ad_title: Label
var ad_sub: Label
var ad_count: Label
var ad_claim: Button
var ad_cancel: Button
var ad_active := false
var ad_left := 0.0
var _ad_secs := -1
var card_p: Control
var card_view: PostcardView
var card_header: Label
var _air_cache := ""
var prog: Control
var prog_labels: Array[Label] = []
var fuel_frac := 1.0
var fuel_low := false
var prog_lit := [false, false, false]
var _prog_cache := ["", "", ""]
# panels
var menu_p: Control
var menu_title: Label
var menu_name: Label
var menu_blurb: Label
var menu_back: Button
var menu_info: Label
var menu_stars: Control
var menu_lit := [false, false, false]
var prev_btn: Button
var next_btn: Button
var fly_btn: Button
var dead_p: Control
var dead_header: Label
var dead_text: Label
var dead_again: Button
var dead_menu: Button
var result_p: Control
var result_header: Label
var result_icons: Control
var result_lit := [false, false, false]
var result_rows: Array[Label] = []
var result_summary: Label
var result_again: Button
var result_next: Button
var result_menu: Button
var _banner_left := 0.0
var _clock := 0.0
var _perf_label: Label
var _perf_worst := 0.0
var _perf_window_start := 0
var _perf_shown := 0.0
var _perf_extra := ""
var _hitch_log: Array[String] = []
var _graph: Control                    # ?perf: rolling frame-time graph
var _ft := PackedFloat32Array()        # the last GRAPH_N frame times (ms), as a ring
var _ft_i := 0
var _gpts := PackedVector2Array()
var _over33 := 0                       # frames over 33 ms in the last window
var _frames_win := 0
var _prof_text := ""
## Where the three tool buttons are (below the ground line). Touches are handled by Main (so a second finger works
## while the first holds the burner); the buttons themselves are only drawn.
const TOOL_RECTS := [Rect2(30, 1742, 320, 110), Rect2(380, 1742, 320, 110), Rect2(730, 1742, 320, 110)]
const TOOL_NAMES := ["SANDBAG", "ANCHOR", "QUICK VENT"]
const GRAPH_N := 120
const GRAPH_MAX_MS := 50.0

func _ready() -> void:
	layer = 5
	level_label = Ui.label("", 34, HORIZONTAL_ALIGNMENT_LEFT, Vector2(30, 22), Vector2(560, 50))
	score_label = Ui.label("", 46, HORIZONTAL_ALIGNMENT_RIGHT, Vector2(440, 14), Vector2(430, 60))
	coins_label = Ui.label("", 30, HORIZONTAL_ALIGNMENT_RIGHT, Vector2(440, 70), Vector2(430, 40))
	coins_label.add_theme_color_override("font_color", Ui.COL_GOLD)
	stamp_label = Ui.label("", 22, HORIZONTAL_ALIGNMENT_RIGHT, Vector2(560, 1870), Vector2(500, 36))
	stamp_label.modulate = Color(1, 1, 1, 0.6)
	var flags := DebugFlags.summary()
	stamp_label.text = "%s  %s  controls=%s%s" % [BuildInfo.COMMIT, BuildInfo.TIME, DebugFlags.controls, ("  " + flags) if flags != "" else ""]
	for l in [level_label, score_label, coins_label, stamp_label]:
		add_child(l)
	gauge = Control.new()
	gauge.position = Vector2(30, 120)
	gauge.size = Vector2(1020, 34)
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.draw.connect(_draw_gauge)
	add_child(gauge)
	prog = Control.new()
	prog.position = Vector2(30, 164)
	prog.size = Vector2(1020, 50)
	prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prog.draw.connect(_draw_prog)
	add_child(prog)
	for i in 3:
		var l := Ui.label("", 28, HORIZONTAL_ALIGNMENT_LEFT, Vector2(36.0 + 345.0 * float(i), 6), Vector2(300, 40))
		prog.add_child(l)
		prog_labels.append(l)
	air_label = Ui.label("", 26, HORIZONTAL_ALIGNMENT_RIGHT, Vector2(560, 214), Vector2(490, 34))
	air_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	air_label.visible = false
	add_child(air_label)
	goal_label = Ui.label("", 26, HORIZONTAL_ALIGNMENT_LEFT, Vector2(30, 214), Vector2(700, 34))
	goal_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	add_child(goal_label)
	hint_label = Ui.label("", 40, HORIZONTAL_ALIGNMENT_CENTER, Vector2(60, 1010), Vector2(960, 220))
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.visible = false
	add_child(hint_label)
	for i in 3:
		var tb := Ui.button(TOOL_NAMES[i], 36, TOOL_RECTS[i].position, TOOL_RECTS[i].size, [Color(0.75, 0.55, 0.25), Color(0.85, 0.6, 0.2), Color(0.35, 0.6, 0.85)][i])
		tb.mouse_filter = Control.MOUSE_FILTER_IGNORE   # (drawn only: Main handles the touches)
		tb.visible = false
		add_child(tb)
		tool_btns.append(tb)
	map = MapScreen.new()
	add_child(map)
	map.flight_chosen.connect(func(id: int): flight_chosen.emit(id))
	map.album_pressed.connect(func(): album_pressed.emit())
	map.shop_pressed.connect(func(): shop_pressed.emit())
	map.daily_pressed.connect(func(): daily_pressed.emit())
	album = AlbumScreen.new()
	add_child(album)
	album.back_pressed.connect(func(): album_closed.emit())
	shop = ShopScreen.new()
	add_child(shop)
	shop.back_pressed.connect(func(): shop_closed.emit())
	shop.changed.connect(func(): cosmetics_changed.emit())
	banner = Ui.label("", 84, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 760), Vector2(1000, 260))
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(banner)
	_build_menu()
	_build_dead()
	_build_result()
	_build_card()
	boost_btn = Ui.button("+50% PROPANE  (AD)", 44, Vector2(240, 1420), Vector2(600, 110), Color(0.6, 0.35, 0.85))
	boost_btn.visible = false
	boost_btn.pressed.connect(func(): boost_pressed.emit())
	add_child(boost_btn)
	_build_ad()
	splash = ColorRect.new()
	splash.color = Color(0.06, 0.1, 0.18, 0.97)
	splash.size = Vector2(Lanes.W, Lanes.H)
	splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	splash.visible = false
	add_child(splash)
	splash.add_child(Ui.label("WIND LAYERS\nloading...", 64, HORIZONTAL_ALIGNMENT_CENTER, Vector2(0, 780), Vector2(Lanes.W, 300)))
	if DebugFlags.perf_enabled():
		_perf_label = Ui.label("", 26, HORIZONTAL_ALIGNMENT_LEFT, Vector2(14, 300), Vector2(900, 400))
		_perf_label.modulate = Color(0.6, 1, 0.6, 0.95)
		add_child(_perf_label)
		_ft.resize(GRAPH_N)
		_gpts.resize(GRAPH_N)
		_graph = Control.new()
		_graph.position = Vector2(14, 1620)
		_graph.size = Vector2(GRAPH_N * 5.0, 150)
		_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_graph.draw.connect(_draw_graph)
		add_child(_graph)
		Lanes.prof_on = true
	hide_overlays()

func _panel() -> Control:
	var p := Control.new()
	p.size = Vector2(Lanes.W, Lanes.H)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.15, 0.72)
	bg.size = p.size
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	p.add_child(bg)
	add_child(p)
	return p

func _build_menu() -> void:
	menu_p = _panel()
	menu_title = Ui.label("", 110, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 200), Vector2(1000, 150))
	menu_p.add_child(menu_title)
	menu_blurb = Ui.label("", 40, HORIZONTAL_ALIGNMENT_CENTER, Vector2(90, 350), Vector2(900, 60))
	menu_p.add_child(menu_blurb)
	menu_name = Ui.label("", 70, HORIZONTAL_ALIGNMENT_CENTER, Vector2(200, 480), Vector2(680, 100))
	menu_p.add_child(menu_name)
	menu_stars = Control.new()
	menu_stars.position = Vector2(340, 590)
	menu_stars.size = Vector2(400, 80)
	menu_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_stars.draw.connect(func(): _draw_three(menu_stars, menu_lit, 40.0, 140.0, 40.0))
	menu_p.add_child(menu_stars)
	menu_info = Ui.label("", 38, HORIZONTAL_ALIGNMENT_CENTER, Vector2(90, 690), Vector2(900, 330))
	menu_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_p.add_child(menu_info)
	prev_btn = Ui.button("<", 70, Vector2(70, 470), Vector2(120, 120))
	next_btn = Ui.button(">", 70, Vector2(890, 470), Vector2(120, 120))
	fly_btn = Ui.button("FLY", 84, Vector2(190, 1100), Vector2(700, 160), Color(0.95, 0.5, 0.15))
	menu_back = Ui.button("MAP", 56, Vector2(190, 1300), Vector2(700, 120))
	prev_btn.pressed.connect(func(): prev_pressed.emit())
	next_btn.pressed.connect(func(): next_pressed.emit())
	fly_btn.pressed.connect(func(): fly_pressed.emit())
	menu_back.pressed.connect(func(): back_pressed.emit())
	for b in [prev_btn, next_btn, fly_btn, menu_back]:
		menu_p.add_child(b)

func _build_ad() -> void:
	ad_p = _panel()
	ad_p.get_child(0).color = Color(0.08, 0.06, 0.14, 0.97)
	ad_title = Ui.label("AD PLAYING", 90, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 400), Vector2(1000, 130))
	ad_p.add_child(ad_title)
	ad_sub = Ui.label("", 56, HORIZONTAL_ALIGNMENT_CENTER, Vector2(60, 560), Vector2(960, 200))
	ad_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ad_p.add_child(ad_sub)
	ad_count = Ui.label("", 60, HORIZONTAL_ALIGNMENT_CENTER, Vector2(60, 780), Vector2(960, 100))
	ad_p.add_child(ad_count)
	ad_claim = Ui.button("CLAIM", 60, Vector2(190, 1000), Vector2(700, 140), Color(0.95, 0.5, 0.15))
	ad_claim.pressed.connect(func(): _end_ad(true))
	ad_p.add_child(ad_claim)
	ad_cancel = Ui.button("NO THANKS", 48, Vector2(190, 1190), Vector2(700, 110))
	ad_cancel.pressed.connect(func(): _end_ad(false))
	ad_p.add_child(ad_cancel)

## The fake ad screen (stub). `secs` before it can be claimed / closed; `can_cancel`: a NO THANKS button (rewarded).
func show_ad(title: String, reward: String, secs: float, claim_text: String, can_cancel: bool) -> void:
	ad_title.text = "AD PLAYING"
	ad_sub.text = "%s\n%s" % [title, reward]
	ad_claim.text = claim_text
	ad_cancel.visible = can_cancel
	ad_left = secs
	_ad_secs = -1
	ad_claim.disabled = secs > 0.0
	ad_count.text = "" if secs <= 0.0 else "..."
	ad_active = true
	ad_p.visible = true

func _end_ad(rewarded: bool) -> void:
	ad_active = false
	ad_p.visible = false
	ad_finished.emit(rewarded)

func _process(delta: float) -> void:
	if ad_active and ad_left > 0.0:
		ad_left -= delta
		var secs := ceili(maxf(ad_left, 0.0))
		if secs != _ad_secs:
			_ad_secs = secs
			ad_count.text = "%d" % secs if secs > 0 else ""
		if ad_left <= 0.0:
			ad_claim.disabled = false

func _build_card() -> void:
	card_p = _panel()
	card_header = Ui.label("NEW POSTCARD!", 84, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 220), Vector2(1000, 120))
	card_p.add_child(card_header)
	card_view = PostcardView.new()
	card_view.position = Vector2(30, 400)
	card_view.size = Vector2(1020, 700)
	card_p.add_child(card_view)
	var cont := Ui.button("CONTINUE", 60, Vector2(190, 1250), Vector2(700, 130), Color(0.95, 0.5, 0.15))
	cont.pressed.connect(func(): card_p.visible = false)
	card_p.add_child(cont)

func _build_dead() -> void:
	dead_p = _panel()
	dead_header = Ui.label("FLIGHT FAILED", 84, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 380), Vector2(1000, 120))
	dead_p.add_child(dead_header)
	dead_text = Ui.label("", 50, HORIZONTAL_ALIGNMENT_CENTER, Vector2(60, 520), Vector2(960, 340))
	dead_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dead_p.add_child(dead_text)
	retry_btn = Ui.button("RETRY THIS LEG  (AD)", 50, Vector2(190, 880), Vector2(700, 120), Color(0.6, 0.35, 0.85))
	retry_btn.pressed.connect(func(): retry_pressed.emit())
	dead_p.add_child(retry_btn)
	dead_again = Ui.button("FLY AGAIN", 70, Vector2(190, 1030), Vector2(700, 140), Color(0.95, 0.5, 0.15))
	dead_menu = Ui.button("MAP", 60, Vector2(190, 1210), Vector2(700, 120))
	dead_again.pressed.connect(func(): again_pressed.emit())
	dead_menu.pressed.connect(func(): menu_pressed.emit())
	dead_p.add_child(dead_again)
	dead_p.add_child(dead_menu)

func _build_result() -> void:
	result_p = _panel()
	result_header = Ui.label("FLIGHT COMPLETE!", 80, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 260), Vector2(1000, 120))
	result_p.add_child(result_header)
	result_icons = Control.new()
	result_icons.position = Vector2(90, 430)
	result_icons.size = Vector2(900, 400)
	result_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_icons.draw.connect(func(): _draw_rows(result_icons, result_lit, 55.0, 130.0))
	result_p.add_child(result_icons)
	for i in 3:
		var l := Ui.label("", 42, HORIZONTAL_ALIGNMENT_LEFT, Vector2(190, 445.0 + 130.0 * float(i)), Vector2(800, 80))
		result_p.add_child(l)
		result_rows.append(l)
	result_summary = Ui.label("", 44, HORIZONTAL_ALIGNMENT_CENTER, Vector2(60, 850), Vector2(960, 440))
	result_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_p.add_child(result_summary)
	result_again = Ui.button("AGAIN", 56, Vector2(90, 1380), Vector2(440, 130))
	result_next = Ui.button("NEXT", 56, Vector2(550, 1380), Vector2(440, 130), Color(0.95, 0.5, 0.15))
	result_menu = Ui.button("MAP", 56, Vector2(190, 1540), Vector2(700, 120))
	result_again.pressed.connect(func(): again_pressed.emit())
	result_next.pressed.connect(func(): next_flight_pressed.emit())
	result_menu.pressed.connect(func(): menu_pressed.emit())
	for b in [result_again, result_next, result_menu]:
		result_p.add_child(b)

## Three stars side by side (lit = gold, otherwise dim).
func _draw_three(ci: Control, lit: Array, r: float, gap: float, y: float) -> void:
	for i in 3:
		Ui.draw_star(ci, Vector2(60.0 + gap * float(i), y), r, Ui.COL_GOLD if lit[i] else Color(0.3, 0.33, 0.4))

## Three stars one under the other, one per row.
func _draw_rows(ci: Control, lit: Array, r: float, gap: float) -> void:
	for i in 3:
		Ui.draw_star(ci, Vector2(55.0, 55.0 + gap * float(i)), r, Ui.COL_GOLD if lit[i] else Color(0.3, 0.33, 0.4))

func _draw_gauge() -> void:
	var r := Rect2(0, 0, 1020, 34)
	gauge.draw_rect(r, Color(0.1, 0.12, 0.18, 0.85))
	var col := Color(0.3, 0.9, 0.45)
	if fuel_frac < 0.5:
		col = Color(1.0, 0.75, 0.2)
	if fuel_low:
		col = Color(1.0, 0.25, 0.2) if int(_clock * 6.0) % 2 == 0 else Color(1.0, 0.6, 0.3)
	gauge.draw_rect(Rect2(3, 3, 1014.0 * clampf(fuel_frac, 0.0, 1.0), 28), col)
	var tx := 3.0 + 1014.0 * Tuning.star_propane_frac   # the second star's propane target
	gauge.draw_line(Vector2(tx, -4), Vector2(tx, 38), Ui.COL_GOLD, 5.0)
	gauge.draw_rect(r, Color.BLACK, false, 4.0)

func _draw_prog() -> void:
	for i in 3:
		Ui.draw_star(prog, Vector2(18.0 + 345.0 * float(i), 25.0), 17.0, Ui.COL_GOLD if prog_lit[i] else Color(0.3, 0.33, 0.4))

# ---- in-flight HUD ----

## Show or hide the in-flight readouts (flight name, score, gauge, star progress): only while flying.
func set_flight_hud(on: bool) -> void:
	for n in [level_label, score_label, coins_label, gauge, prog, goal_label]:
		n.visible = on
	if not on:
		air_label.visible = false
		hint_label.visible = false
		for tb in tool_btns:
			tb.visible = false
	elif _air_cache != "":
		air_label.visible = true


func set_flight_title(text: String) -> void:
	level_label.text = text

func set_score(v: int) -> void:
	score_label.text = Tuning.fmt(float(v))

func set_flight_coins(v: int) -> void:
	coins_label.text = "+%s coins" % Tuning.fmt(float(v)) if v > 0 else ""

func set_fuel(frac: float) -> void:
	var low := frac < Tuning.propane_low_fraction
	if absf(frac - fuel_frac) > 0.0005 or low != fuel_low:
		fuel_frac = frac
		fuel_low = low
		gauge.queue_redraw()

## Progress toward the three stars: legs done, propane (needs the target), coins collected (needs the target).
func set_progress(legs_done: int, legs: int, fuel: float, coins: int, coin_target: int) -> void:
	var t0 := "%d/%d legs" % [legs_done, legs]
	var t1 := "propane %d / %d" % [int(fuel), int(Flights.propane_target())]
	var t2 := "coins %d / %d" % [coins, coin_target]
	var lit1 := fuel >= Flights.propane_target()
	var lit2 := coins >= coin_target
	if t0 != _prog_cache[0] or t1 != _prog_cache[1] or t2 != _prog_cache[2]:
		_prog_cache[0] = t0
		_prog_cache[1] = t1
		_prog_cache[2] = t2
		prog_labels[0].text = t0
		prog_labels[1].text = t1
		prog_labels[2].text = t2
	if lit1 != prog_lit[1] or lit2 != prog_lit[2] or prog_lit[0]:
		prog_lit[0] = false
		prog_lit[1] = lit1
		prog_lit[2] = lit2
		prog.queue_redraw()

## The leg's goal line under the star progress ("Stars 2/4", "Mail on board: ..."); only re-texted when it changes.
func set_goal_text(text: String) -> void:
	if text != _goal_cache:
		_goal_cache = text
		goal_label.text = text

## A tool button: whether it is offered, how many charges are left.
func set_tool(i: int, available: bool, charges: int) -> void:
	var tb := tool_btns[i]
	tb.visible = available
	tb.disabled = charges <= 0
	var t := "%s  x%d" % [TOOL_NAMES[i], charges]
	if tb.text != t:
		tb.text = t

## A one-line intro (a new tool): shown for `secs` seconds.
func show_hint(text: String, secs: float) -> void:
	hint_label.text = text
	hint_label.visible = true
	_hint_left = secs

func show_banner(text: String, secs: float) -> void:
	banner.text = text
	banner.visible = true
	_banner_left = secs

func tick(dt: float) -> void:
	_clock += dt
	if _hint_left > 0.0:
		_hint_left -= dt
		if _hint_left <= 0.0:
			hint_label.visible = false
	if fuel_low:
		gauge.queue_redraw()
	if _banner_left > 0.0:
		_banner_left -= dt
		if _banner_left <= 0.0:
			banner.visible = false

# ---- panels ----

func hide_overlays() -> void:
	banner.visible = false
	map.visible = false
	album.visible = false
	shop.visible = false
	card_p.visible = false
	ad_p.visible = false
	ad_active = false
	boost_btn.visible = false
	menu_p.visible = false
	dead_p.visible = false
	result_p.visible = false
	_banner_left = 0.0

func show_menu(region_name: String, blurb: String, title: String, lit1: bool, lit2: bool, lit3: bool, info: String, can_prev: bool, can_next: bool, can_fly: bool, daily: bool = false) -> void:
	hide_overlays()
	prev_btn.visible = not daily
	next_btn.visible = not daily
	menu_stars.visible = not daily
	menu_title.text = region_name
	menu_blurb.text = blurb
	menu_name.text = title
	menu_lit[0] = lit1
	menu_lit[1] = lit2
	menu_lit[2] = lit3
	menu_stars.queue_redraw()
	menu_info.text = info
	prev_btn.disabled = not can_prev
	next_btn.disabled = not can_next
	fly_btn.disabled = not can_fly
	menu_p.visible = true

func show_map() -> void:
	hide_overlays()
	map.refresh()
	map.visible = true

func show_shop() -> void:
	hide_overlays()
	shop.open()
	shop.visible = true

func show_album() -> void:
	hide_overlays()
	album.refresh()
	album.visible = true

## The award screen: over the result screen. state 1 = postcard, 2 = gold.
func show_postcard(region: int, state: int) -> void:
	card_view.set_card(region, state)
	card_header.text = "GOLD POSTCARD!" if state == 2 else "NEW POSTCARD!"
	card_p.visible = true

func show_dead(text: String, can_retry: bool = false) -> void:
	hide_overlays()
	dead_text.text = text
	retry_btn.visible = can_retry
	dead_p.visible = true

## rows: the three star lines; lit: which stars were earned.
func show_result(row0: String, row1: String, row2: String, lit1: bool, lit2: bool, lit3: bool, summary: String, can_next: bool) -> void:
	hide_overlays()
	result_rows[0].text = row0
	result_rows[1].text = row1
	result_rows[2].text = row2
	result_lit[0] = lit1
	result_lit[1] = lit2
	result_lit[2] = lit3
	result_icons.queue_redraw()
	result_summary.text = summary
	result_next.disabled = not can_next
	result_p.visible = true

func begin_prewarm() -> void:
	hide_overlays()
	map.refresh()
	map.visible = true
	shop.refresh()
	shop.visible = true
	boost_btn.visible = true
	ad_p.visible = true
	ad_sub.text = "Rewarded ad\n+50% propane"
	ad_count.text = "2"
	album.refresh()
	album.visible = true
	album.zoom_p.visible = true
	album.zoom_view.set_card(1, 2)
	card_view.set_card(2, 2)
	card_p.visible = true
	menu_p.visible = true
	dead_p.visible = true
	result_p.visible = true
	menu_title.text = "Countryside"
	menu_blurb.text = "gentle winds"
	menu_name.text = "COUNTRYSIDE 6"
	menu_info.text = "best 123,456"
	menu_lit = [true, true, true]
	result_lit = [true, true, true]
	for r in result_rows:
		r.text = "star row"
	result_summary.text = "coins\ncoins"
	dead_text.text = "Leg 3 of 5\nCrashed into a bird"
	banner.text = "LEG 3 / 5\n+250 bonus"
	banner.visible = true
	set_flight_title("COUNTRYSIDE 6   LEG 3/5")
	set_score(1234567)
	set_flight_coins(88)
	set_fuel(0.2)
	set_progress(2, 5, 12.0, 4, 9)
	set_flight_hud(true)
	splash.visible = true

func end_prewarm() -> void:
	splash.visible = false
	hide_overlays()
	set_flight_hud(false)
	prog_lit = [false, false, false]
	prog.queue_redraw()

## Thin air readout (Himalayas); "" hides it.
func set_air(text: String) -> void:
	if text != _air_cache:
		_air_cache = text
		air_label.text = text
		air_label.visible = text != ""

# ---- ?perf ----

func set_perf_extra(text: String) -> void:
	_perf_extra = text

func note_hitch(raw: float, used: float, why: String, context: String) -> void:
	_hitch_log.append("%.0f ms (sim %.0f): %s | %s" % [raw * 1000.0, used * 1000.0, why, context])
	if _hitch_log.size() > 5:
		_hitch_log.pop_front()

## The rolling frame-time graph: one polyline of the last 120 frames (0-50 ms), with the 16.7 ms (60 fps) and
## 33 ms (30 fps, the target's limit) lines; frames over 33 ms are marked red.
func _draw_graph() -> void:
	var h := _graph.size.y
	var wpx := float(GRAPH_N) * 5.0
	_graph.draw_rect(Rect2(0, 0, wpx, h), Color(0, 0, 0, 0.55))
	for lim in [16.7, 33.0]:
		var y := h - h * float(lim) / GRAPH_MAX_MS
		_graph.draw_line(Vector2(0, y), Vector2(wpx, y), Color(1, 1, 0.4, 0.7) if lim < 20.0 else Color(1, 0.4, 0.3, 0.8), 2.0)
	for i in GRAPH_N:
		var ms := _ft[(_ft_i + i) % GRAPH_N]
		_gpts[i] = Vector2(float(i) * 5.0, h - h * minf(ms, GRAPH_MAX_MS) / GRAPH_MAX_MS)
		if ms > 33.0:
			_graph.draw_line(Vector2(float(i) * 5.0, h), Vector2(float(i) * 5.0, 0.0), Color(1, 0.2, 0.2, 0.85), 4.0)
	_graph.draw_polyline(_gpts, Color(0.5, 1.0, 0.6), 2.0)
	_graph.draw_rect(Rect2(0, 0, wpx, h), Color.WHITE, false, 2.0)

func update_perf(delta: float) -> void:
	if _perf_label == null:
		return
	_ft[_ft_i] = delta * 1000.0
	_ft_i = (_ft_i + 1) % GRAPH_N
	_frames_win += 1
	if delta > 0.033:
		_over33 += 1
	_graph.queue_redraw()
	_perf_worst = maxf(_perf_worst, delta * 1000.0)
	var now := Time.get_ticks_msec()
	if now - _perf_window_start > 3000:
		_perf_shown = _perf_worst
		_perf_worst = 0.0
		_perf_window_start = now
		var n := maxf(float(_frames_win), 1.0)
		_prof_text = "script/frame: sim %.0f us, render %.0f us | over 33 ms: %d of %d frames" % [Lanes.prof_us[0] / n, Lanes.prof_us[1] / n, _over33, _frames_win]
		Lanes.prof_us.fill(0.0)
		_frames_win = 0
		_over33 = 0
	_perf_label.text = "worst frame (3s): %.0f ms   %d fps\n%s\n%s\nhitches (over 50 ms):\n%s" % [_perf_shown, Engine.get_frames_per_second(), _prof_text, _perf_extra, "\n".join(_hitch_log)]
