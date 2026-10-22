class_name Hud
extends CanvasLayer
## All on-screen text, panels and buttons. Every node is created once in _ready (and drawn during the
## start-up pre-warm); after that labels are only re-texted when a value changes and panels are only
## shown / hidden. Buttons emit the signals below; Main decides what they mean.

## The in-game loading cover (the pre-warm): an opaque brand background, the studio mark spinning, the wordmark and a bar.
## Nothing else: no text, so nothing of the game behind it can show through.
## The leg pips: done green, current gold with a white ring, future faded, on a navy pill.
class _Pips extends Control:
	var legs := 5
	var done := 0
	func _draw() -> void:
		draw_colored_polygon(SvgArt.rrect(0.0, 0.0, size.x, size.y, size.y * 0.5), Color(0.078, 0.129, 0.239, 0.82))
		var gap := 50.0
		var total := float(legs - 1) * gap + 16.0
		var x := (size.x - total) * 0.5 + 8.0
		for i in legs:
			var c := Vector2(x + float(i) * gap, size.y * 0.5)
			if i < done:
				draw_circle(c, 17.0, Style.SUCCESS)
			elif i == done:
				draw_circle(c, 23.0, Color.WHITE)
				draw_circle(c, 18.0, Style.ACCENT)
			else:
				draw_circle(c, 17.0, Color(1, 1, 1, 0.3))

## A navy pill (coins readout).
class _PillBox extends Control:
	func _draw() -> void:
		draw_colored_polygon(SvgArt.rrect(0.0, 0.0, size.x, size.y, size.y * 0.5), Color(0.078, 0.129, 0.239, 0.82))

class SplashDraw extends Control:
	var t := 0.0

	func _process(delta: float) -> void:
		if visible:
			t += delta
			queue_redraw()

	func _draw() -> void:
		var cx := size.x * 0.5
		var cy := size.y * 0.5
		draw_rect(Rect2(Vector2.ZERO, size), Color("0d1a33"))
		draw_circle(Vector2(cx, cy * 0.7), 760.0, Color(Style.SURFACE_DARK_2, 0.55))
		draw_circle(Vector2(cx, cy * 0.7), 520.0, Color(Style.SURFACE_DARK_2, 0.6))
		Style.draw_mark(self, Vector2(cx, cy - 80.0), 110.0, t * 3.0)
		Style.draw_wordmark(self, cx, cy + 110.0, Style.SZ_M)
		var w := 420.0
		var r := Rect2(cx - w * 0.5, cy + 200.0, w, 20.0)
		draw_rect(r, Color(Style.INK, 0.8))
		var f := fposmod(t * 0.9, 1.4) / 1.4
		var x0 := r.position.x + (w + 140.0) * f - 140.0
		var x1 := minf(x0 + 140.0, r.end.x)
		x0 = maxf(x0, r.position.x)
		if x1 > x0:
			draw_rect(Rect2(x0, r.position.y, x1 - x0, r.size.y), Style.ACCENT)

## The logo intro: the studio mark spins up and settles with its wordmark, then the game's name pops in. Any tap skips it.
class IntroDraw extends Control:
	signal finished
	var t := 0.0
	var running := false
	var total := 2.8

	func start(seconds: float) -> void:
		t = 0.0
		total = seconds
		running = true
		visible = true
		modulate.a = 1.0
		queue_redraw()

	func _process(delta: float) -> void:
		if not running:
			return
		t += delta
		if t >= total:
			_finish()
		else:
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if running and ((event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed)):
			_finish()

	func _finish() -> void:
		running = false
		visible = false
		finished.emit()

	func _draw() -> void:
		var cx := size.x * 0.5
		var cy := size.y * 0.5
		draw_rect(Rect2(Vector2.ZERO, size), Color("0d1a33"))
		draw_circle(Vector2(cx, cy * 0.8), 700.0, Color(Style.SURFACE_DARK_2, 0.5))
		var split := total * 0.55
		if t < split:
			var u := t / split
			var pop := Style.ease_out_back(clampf(t / 0.45, 0.0, 1.0))
			var fade := 1.0 - Style.ease_in_cubic(clampf((t - (split - 0.25)) / 0.25, 0.0, 1.0))
			var angle := (1.0 - Style.ease_out_cubic(clampf(t / 1.3, 0.0, 1.0))) * TAU * 3.0
			draw_set_transform(Vector2(cx, cy - 60.0), 0.0, Vector2(pop, pop))
			Style.draw_mark(self, Vector2.ZERO, 130.0, angle, fade)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var wa := clampf((t - 0.35) / 0.3, 0.0, 1.0) * fade
			Style.draw_wordmark(self, cx, cy + 190.0 + (1.0 - Style.ease_out_cubic(clampf((t - 0.35) / 0.3, 0.0, 1.0))) * 30.0, Style.SZ_M, wa)
		else:
			var u2 := (t - split) / (total - split)
			var pop2 := Style.ease_out_back(clampf(u2 / 0.4, 0.0, 1.0))
			var fade2 := 1.0 - Style.ease_in_cubic(clampf((u2 - 0.82) / 0.18, 0.0, 1.0))
			draw_set_transform(Vector2(cx, cy - 40.0), 0.0, Vector2(pop2, pop2))
			var f := Style.display()
			for k in 2:
				var word := "WIND" if k == 0 else "LAYERS"
				var y := -110.0 + 190.0 * float(k)
				var col := Color(Style.TEXT if k == 0 else Style.ACCENT, fade2)
				var wsz := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 190)
				draw_string_outline(f, Vector2(-wsz.x * 0.5, y + 70.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 190, 24, Color(Style.INK, fade2))
				draw_string(f, Vector2(-wsz.x * 0.5, y + 70.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 190, col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

signal pause_pressed
signal next_leg_pressed
signal resume_pressed
signal restart_pressed
signal quit_pressed
signal title_play_pressed
signal home_pressed
signal logo_finished
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
var splash: Control               # the loading cover: the studio mark, a bar, no text (its own CanvasLayer, above everything)
var gauge: Control
var pips: Control
var coin_pill: Control
var coin_value: Label
var tool_badges: Array[Label] = []
var _goal_left := 0.0
var star_rows: Array = []          # the Flight's star goals so far (for the leg-complete screen): [text, progress text, lit]
var air_label: Label
var goal_label: Label
var hint_label: Label
var tool_btns: Array[Button] = []
var propane_icon: IconView
var goal_icon: IconView
var prog_icons: Array[IconView] = []
var menu_region_icon: IconView
var menu_star_icons: Array[IconView] = []
var title: TitleScreen
var intro: IntroDraw
var pause_btn: Button
var pause_p: Control
var sound_slider: HSlider
var music_slider: HSlider
var carry: Control                 # leg-to-leg propane carry-over gauge
var carry_frac := 0.0
var carry_shown := 0.0
var carry_t := 0.0
var result_t := 99.0               # seconds since the result screen came up (the stars slam in one after another)
var result_fuel := 0.0             # the propane left, as a share of the tank (the gauge fills to it)
var result_gauge: Control
var _star_slammed := [false, false, false]
var _shake := 0.0
var nav_dir := 1                  # the next screen slides in from the right (1: forward) or from the left (-1: back)
var _flash: ColorRect             # a quick dim that fades out on every screen change (the cross-fade)
var _g_track: StyleBoxFlat
var _g_fill := {}
var _g_sheen: StyleBoxFlat
var _hint_left := 0.0
var _goal_cache := ""
var map: MapScreen
var legdone: LegDoneScreen
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
static var TOOL_RECTS := [Rect2(554, 1722, 150, 150), Rect2(722, 1722, 150, 150), Rect2(890, 1722, 150, 150)]
const TOOL_FILL := [Color("c4844a"), Color("5a6a8a"), Color("ff5c4d")]   # sandbag tan, anchor slate, vent red
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
	stamp_label.modulate = Color(1, 1, 1, 0.45)
	stamp_label.visible = DebugFlags.stamp_enabled()   # the build stamp is for debugging only: ?debug, ?tune or ?perf
	var flags := DebugFlags.summary()
	stamp_label.text = "%s  %s%s" % [BuildInfo.COMMIT, BuildInfo.TIME, ("  " + flags) if flags != "" else ""]
	for l in [level_label, score_label, coins_label, stamp_label]:
		add_child(l)
	for l in [level_label, score_label, coins_label]:
		l.visible = false   # (kept as data holders; the new HUD shows only four things)
	_g_track = Style.box(Color(1, 1, 1, 0.15), Color(0, 0, 0, 0), 24, 0, false)
	for k in ["ok", "mid", "low_a", "low_b"]:
		var col: Color = {"ok": Style.SUCCESS, "mid": Style.WARNING, "low_a": Style.DANGER, "low_b": Style.WARNING}[k]
		_g_fill[k] = Style.box(col, Color(0, 0, 0, 0), 22, 0, false)
	_g_sheen = Style.sheen(6, 0.3)
	# the four things: pause (top left), leg pips (top centre), coins (top right), the propane tank (bottom left)
	pips = _Pips.new()
	pips.position = Vector2(390, 60)
	pips.size = Vector2(300, 100)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pips)
	coin_pill = _PillBox.new()
	coin_pill.position = Vector2(Lanes.W - 44.0 - 250.0, 56.0)
	coin_pill.size = Vector2(250, 108)
	coin_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(coin_pill)
	coin_pill.add_child(Ui.icon("coin", 74, Vector2(16, 17)))
	coin_value = Ui.label("0", 56, HORIZONTAL_ALIGNMENT_LEFT, Vector2(100, 14), Vector2(140, 80))
	coin_value.add_theme_constant_override("outline_size", 0)
	coin_pill.add_child(coin_value)
	gauge = Control.new()
	gauge.position = Vector2(44, 1742)
	gauge.size = Vector2(490, 130)
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.draw.connect(_draw_gauge)
	add_child(gauge)
	propane_icon = Ui.icon("propane", 78, Vector2(24, 26))
	gauge.add_child(propane_icon)
	prog = Control.new()   # (the old star-progress row: kept hidden; the Flight's star goals live on the leg-complete screen)
	prog.visible = false
	add_child(prog)
	for i in 3:
		var pi := Ui.icon(["legs", "propane", "coin"][i], 32, Vector2.ZERO)
		prog.add_child(pi)
		prog_icons.append(pi)
		var l := Ui.label("", 28, HORIZONTAL_ALIGNMENT_LEFT, Vector2.ZERO, Vector2(255, 40))
		prog.add_child(l)
		prog_labels.append(l)
	air_label = Ui.label("", 34, HORIZONTAL_ALIGNMENT_CENTER, Vector2(140, 330), Vector2(800, 50))
	air_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	air_label.visible = false
	add_child(air_label)
	goal_icon = Ui.icon("goal_climb", 30, Vector2(30, 203))
	goal_icon.visible = false
	add_child(goal_icon)
	goal_label = Ui.label("", 60, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 176), Vector2(1000, 84))
	goal_label.add_theme_constant_override("outline_size", 14)
	goal_label.modulate.a = 0.0
	add_child(goal_label)
	hint_label = Ui.label("", 40, HORIZONTAL_ALIGNMENT_CENTER, Vector2(60, 1010), Vector2(960, 220))
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.visible = false
	add_child(hint_label)
	for i in 3:   # the tools: chunky tiles with a charge badge
		var tb := Button.new()
		tb.position = TOOL_RECTS[i].position
		tb.size = TOOL_RECTS[i].size
		tb.focus_mode = Control.FOCUS_NONE
		tb.mouse_filter = Control.MOUSE_FILTER_IGNORE   # (drawn only: Main handles the touches)
		var fill: Color = TOOL_FILL[i]
		for st in ["normal", "hover", "pressed", "focus"]:
			tb.add_theme_stylebox_override(st, _tile_box(fill))
		tb.add_theme_stylebox_override("disabled", _tile_box(fill.lerp(Color(0.35, 0.38, 0.45), 0.7)))
		Ui.add_icon(tb, ["sandbag", "anchor", "vent"][i], 84.0)
		Ui.hook_press(tb, "")
		var badge := Panel.new()
		badge.position = Vector2(tb.size.x - 46.0, -24.0)
		badge.size = Vector2(66, 66)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_stylebox_override("panel", Style.box(Color.WHITE, Style.INK, 33, 6, false))
		tb.add_child(badge)
		var bl := Ui.label("2", 40, HORIZONTAL_ALIGNMENT_CENTER, Vector2(0, 2), Vector2(66, 60))
		bl.add_theme_color_override("font_color", Style.TEXT_ON_LIGHT)
		bl.add_theme_constant_override("outline_size", 0)
		badge.add_child(bl)
		tool_badges.append(bl)
		tb.visible = false
		add_child(tb)
		tool_btns.append(tb)
	pause_btn = Ui.ghost_button("pause", Vector2(44.0, 44.0), 132.0)
	pause_btn.visible = false
	pause_btn.pressed.connect(func(): pause_pressed.emit())
	add_child(pause_btn)
	carry = _CarryGauge.new()
	carry.hud = self
	carry.size = Vector2(760, 150)
	carry.position = Vector2(160, 1020)
	carry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carry.visible = false
	add_child(carry)
	title = TitleScreen.new()
	title.visible = false
	add_child(title)
	title.play_pressed.connect(func(): title_play_pressed.emit())
	title.daily_pressed.connect(func(): daily_pressed.emit())
	title.shop_pressed.connect(func(): shop_pressed.emit())
	map = MapScreen.new()
	add_child(map)
	map.home_pressed.connect(func(): home_pressed.emit())
	map.flight_chosen.connect(func(id: int): flight_chosen.emit(id))
	map.album_pressed.connect(func(): album_pressed.emit())
	map.shop_pressed.connect(func(): shop_pressed.emit())
	map.daily_pressed.connect(func(): daily_pressed.emit())
	legdone = LegDoneScreen.new()
	legdone.visible = false
	add_child(legdone)
	legdone.next_pressed.connect(func(): next_leg_pressed.emit())
	legdone.boost_pressed.connect(func(): boost_pressed.emit())
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
	boost_btn = Ui.button("+50% PROPANE  (AD)", 40, Vector2(240, 1420), Vector2(600, 110), Color(0.6, 0.35, 0.85), "ad")
	boost_btn.visible = false
	boost_btn.pressed.connect(func(): boost_pressed.emit())
	add_child(boost_btn)
	_build_ad()
	_build_pause()
	var splash_layer := CanvasLayer.new()
	splash_layer.layer = 100
	add_child(splash_layer)
	_flash = ColorRect.new()
	_flash.color = Style.SCRIM
	_flash.size = Vector2(Lanes.W, Lanes.H)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	splash_layer.add_child(_flash)
	intro = IntroDraw.new()
	intro.size = Vector2(Lanes.W, Lanes.H)
	intro.mouse_filter = Control.MOUSE_FILTER_STOP
	intro.visible = false
	intro.finished.connect(func(): logo_finished.emit())
	splash_layer.add_child(intro)
	splash = SplashDraw.new()
	splash.size = Vector2(Lanes.W, Lanes.H)
	splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	splash.visible = false
	splash_layer.add_child(splash)
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
	apply_safe_areas()
	hide_overlays()

## Read the device's safe area and move everything pinned to the top / bottom edge in by it (full-screen backgrounds and the
## map / album / shop screens, which fit themselves, are left alone). Tool-button touch rects follow their buttons.
func apply_safe_areas() -> void:
	Style.detect_safe(Vector2(Lanes.W, Lanes.H))
	_place_safe()

func _place_safe() -> void:
	Ui.apply_safe(self)
	for i in 3:
		TOOL_RECTS[i] = Rect2(tool_btns[i].position, tool_btns[i].size)
	for scr in [map, album, shop]:
		Ui.fit_safe(scr)
	for p in [menu_p, dead_p, result_p, card_p, ad_p]:
		Ui.apply_safe(p)

func _panel() -> Control:
	var p := Control.new()
	p.size = Vector2(Lanes.W, Lanes.H)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(Style.SCRIM, 0.8)
	bg.size = p.size
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	p.add_child(bg)
	add_child(p)
	return p

## A chunky tool tile: a flat colour, an ink border and a thick lip underneath.
func _tile_box(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = Style.INK
	sb.set_border_width_all(8)
	sb.border_width_bottom = 20
	sb.set_corner_radius_all(48)
	sb.anti_aliasing = true
	return sb

func _build_menu() -> void:
	menu_p = _panel()
	menu_p.add_child(Ui.card(Vector2(50, 150), Vector2(980, 1330)))
	menu_region_icon = Ui.icon("region_0", 120, Vector2(80, 215))
	menu_p.add_child(menu_region_icon)
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
	for k in 3:   # the three star conditions: a star icon at the left of each line
		var si := Ui.icon("star", 44, Vector2(170, 692.0 + 56.0 * float(k)))
		menu_p.add_child(si)
		menu_star_icons.append(si)
	menu_info = Ui.label("", 38, HORIZONTAL_ALIGNMENT_LEFT, Vector2(230, 690), Vector2(780, 330))
	menu_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_p.add_child(menu_info)
	prev_btn = Ui.ghost_button("back", Vector2(70, 470), 120.0)
	next_btn = Ui.ghost_button("next", Vector2(890, 470), 120.0)
	fly_btn = Ui.button("FLY", 84, Vector2(190, 1100), Vector2(700, 160), Color(0.95, 0.5, 0.15), "play")
	menu_back = Ui.button("MAP", 56, Vector2(190, 1300), Vector2(700, 120), Ui.COL_BTN, "map")
	prev_btn.pressed.connect(func(): prev_pressed.emit())
	next_btn.pressed.connect(func(): next_pressed.emit())
	fly_btn.pressed.connect(func(): fly_pressed.emit())
	menu_back.pressed.connect(func(): back_pressed.emit())
	for b in [prev_btn, next_btn, fly_btn, menu_back]:
		menu_p.add_child(b)

## The pause menu: Resume (the one primary), Restart, Quit, and the sound and music sliders.
func _build_pause() -> void:
	pause_p = _panel()
	pause_p.add_child(Ui.card(Vector2(90, 330), Vector2(900, 1180)))
	pause_p.add_child(Ui.label("PAUSED", 110, HORIZONTAL_ALIGNMENT_CENTER, Vector2(90, 380), Vector2(900, 150)))
	var resume := Ui.button("RESUME", 80, Vector2(190, 590), Vector2(700, 170), Color(0.95, 0.5, 0.15), "play")
	resume.pressed.connect(func(): resume_pressed.emit())
	pause_p.add_child(resume)
	var restart := Ui.button("RESTART", 56, Vector2(190, 790), Vector2(700, 120), Ui.COL_BTN, "restart")
	restart.pressed.connect(func(): restart_pressed.emit())
	pause_p.add_child(restart)
	var quit := Ui.button("QUIT TO MAP", 56, Vector2(190, 940), Vector2(700, 120), Ui.COL_BTN, "map")
	quit.pressed.connect(func(): quit_pressed.emit())
	pause_p.add_child(quit)
	pause_p.add_child(Ui.icon("speaker", 64, Vector2(150, 1110)))
	sound_slider = _slider(Vector2(240, 1118))
	pause_p.add_child(sound_slider)
	pause_p.add_child(Ui.icon("note", 64, Vector2(150, 1260)))
	music_slider = _slider(Vector2(240, 1268))
	pause_p.add_child(music_slider)
	sound_slider.value_changed.connect(func(v: float): _volumes_changed(true))
	music_slider.value_changed.connect(func(v: float): _volumes_changed(false))

static var _grabber: ImageTexture

func _slider(pos: Vector2) -> HSlider:
	var sl := HSlider.new()
	sl.position = pos
	sl.size = Vector2(700, 48)
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = 1.0
	sl.focus_mode = Control.FOCUS_NONE
	sl.add_theme_stylebox_override("slider", Style.box(Color(Style.INK, 0.85), Color(1, 1, 1, 0.3), 14, 3, false))
	sl.add_theme_stylebox_override("grabber_area", Style.box(Style.SUCCESS, Style.SUCCESS.lightened(0.25), 14, 2, false))
	sl.add_theme_stylebox_override("grabber_area_highlight", Style.box(Style.SUCCESS, Style.SUCCESS.lightened(0.25), 14, 2, false))
	if _grabber == null:   # a round gold knob with an ink outline, built once
		var img := Image.create(56, 56, false, Image.FORMAT_RGBA8)
		for y in 56:
			for x in 56:
				var d := Vector2(x - 27.5, y - 27.5).length()
				if d < 27.0:
					img.set_pixel(x, y, Style.INK if d > 22.0 else Style.ACCENT)
		_grabber = ImageTexture.create_from_image(img)
	sl.add_theme_icon_override("grabber", _grabber)
	sl.add_theme_icon_override("grabber_highlight", _grabber)
	return sl

var _volumes_silent := false

func _volumes_changed(is_sound: bool) -> void:
	if _volumes_silent:
		return
	Save.set_volumes(sound_slider.value, music_slider.value)
	Sfx.apply_volumes()
	if is_sound:
		Sfx.ui("tap")

func show_pause() -> void:
	_volumes_silent = true
	sound_slider.value = Save.sound_volume()
	music_slider.value = Save.music_volume()
	_volumes_silent = false
	pause_p.visible = true
	Motion.pop(pause_p.get_child(1), 0.0)
	_flash.modulate.a = 0.0

func hide_pause() -> void:
	pause_p.visible = false

## The leg-to-leg propane carry-over: a tank gauge that fills to what the next leg starts with.
## The leg-complete screen (see LegDoneScreen).
func show_leg_done(region_name: String, flight_no: int, leg_done: int, legs: int, carry: float, can_boost: bool) -> void:
	legdone.show_leg(region_name, flight_no, leg_done, legs, carry, star_rows, can_boost)
	legdone.visible = true
	_enter(legdone)

func show_carry(frac: float) -> void:
	carry_frac = clampf(frac, 0.0, 1.0)
	carry_shown = 0.0
	carry_t = 0.0
	carry.visible = true
	carry.queue_redraw()

## The propane left at the end of a Flight, as a gauge that fills after the stars have landed (the gold tick is the second star's target).
class _ResultGauge extends Control:
	var hud: Hud

	func _draw() -> void:
		var k := Style.ease_out_cubic(clampf((hud.result_t - 1.7) / 0.9, 0.0, 1.0))
		Icons.draw(self, "propane", Vector2(34, size.y * 0.5), 28.0)
		var track := Rect2(80, 14, size.x - 90.0, 42)
		draw_style_box(Style.box(Color(Style.INK, 0.9), Color(1, 1, 1, 0.3), 21, 3, false), track)
		var fw := (track.size.x - 8.0) * hud.result_fuel * k
		if fw > 12.0:
			draw_style_box(Style.box(Style.SUCCESS, Style.SUCCESS.lightened(0.25), 17, 2, false), Rect2(track.position + Vector2(4, 4), Vector2(fw, 34)))
		var tx := track.position.x + 4.0 + (track.size.x - 8.0) * Tuning.star_propane_frac
		draw_line(Vector2(tx, 8), Vector2(tx, 62), Style.INK, 8.0)
		draw_line(Vector2(tx, 8), Vector2(tx, 62), Style.ACCENT, 4.0)

class _CarryGauge extends Control:
	var hud: Hud

	func _process(delta: float) -> void:
		if not visible or hud == null:
			return
		hud.carry_t += delta
		var k := Style.ease_out_cubic(clampf((hud.carry_t - 0.1) / 0.6, 0.0, 1.0))
		var v := hud.carry_frac * k
		if absf(v - hud.carry_shown) > 0.001:
			hud.carry_shown = v
			queue_redraw()

	func _draw() -> void:
		draw_style_box(Style.box(Color(Style.SURFACE_DARK, 0.95), Color(1, 1, 1, 0.5), Style.R_L), Rect2(0, 0, size.x, size.y))
		Icons.draw(self, "propane", Vector2(70, size.y * 0.5), 38.0)
		var track := Rect2(130, 52, size.x - 190.0, 46)
		draw_style_box(Style.box(Color(Style.INK, 0.9), Color(1, 1, 1, 0.3), 23, 3, false), track)
		var fw := (track.size.x - 8.0) * hud.carry_shown
		if fw > 12.0:
			draw_style_box(Style.box(Style.SUCCESS, Style.SUCCESS.lightened(0.25), 19, 2, false), Rect2(track.position + Vector2(4, 4), Vector2(fw, 38)))
		draw_string(Style.display(), Vector2(130, 36), "NEXT LEG TANK", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Style.TEXT_SOFT)

func _build_ad() -> void:
	ad_p = _panel()
	ad_p.get_child(0).color = Color(Style.SCRIM, 0.97)
	ad_p.add_child(Ui.card(Vector2(60, 330), Vector2(960, 1060)))
	ad_title = Ui.label("AD PLAYING", 90, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 400), Vector2(1000, 130))
	ad_p.add_child(ad_title)
	ad_sub = Ui.label("", 56, HORIZONTAL_ALIGNMENT_CENTER, Vector2(60, 560), Vector2(960, 200))
	ad_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ad_p.add_child(ad_sub)
	ad_count = Ui.label("", 60, HORIZONTAL_ALIGNMENT_CENTER, Vector2(60, 780), Vector2(960, 100))
	ad_p.add_child(ad_count)
	ad_claim = Ui.button("CLAIM", 60, Vector2(190, 1000), Vector2(700, 140), Color(0.95, 0.5, 0.15), "check")
	ad_claim.pressed.connect(func(): _end_ad(true))
	ad_p.add_child(ad_claim)
	ad_cancel = Ui.button("NO THANKS", 48, Vector2(190, 1190), Vector2(700, 110), Ui.COL_BTN, "close")
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
	if result_p.visible and result_t < 3.0:
		result_t += delta
		result_icons.queue_redraw()
		result_gauge.queue_redraw()
		if _shake > 0.0:
			_shake = maxf(_shake - delta, 0.0)
			result_p.position.x = sin(result_t * 90.0) * 10.0 * (_shake / 0.3)
		else:
			result_p.position.x = 0.0
	if ad_active and ad_left > 0.0:
		ad_left -= delta
		var secs := ceili(maxf(ad_left, 0.0))
		if secs != _ad_secs:
			_ad_secs = secs
			ad_count.text = "%d" % secs if secs > 0 else ""
		if ad_left <= 0.0:
			ad_claim.disabled = false

## CONTINUE on the award screen: the postcard slides into the album (towards the album button on the map), then the screen closes.
func _card_to_album() -> void:
	var home_pos := card_view.position
	card_view.slide_to(Vector2(190.0, 1840.0), func():
		card_p.visible = false
		card_view.position = home_pos
		card_view.scale = Vector2.ONE)

func _build_card() -> void:
	card_p = _panel()
	card_p.add_child(Ui.card(Vector2(20, 170), Vector2(1040, 1290)))
	card_header = Ui.label("NEW POSTCARD!", 84, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 220), Vector2(1000, 120))
	card_p.add_child(card_header)
	card_view = PostcardView.new()
	card_view.position = Vector2(30, 400)
	card_view.size = Vector2(1020, 700)
	card_p.add_child(card_view)
	var cont := Ui.button("CONTINUE", 60, Vector2(190, 1250), Vector2(700, 130), Color(0.95, 0.5, 0.15), "check")
	cont.pressed.connect(_card_to_album)
	card_p.add_child(cont)

func _build_dead() -> void:
	dead_p = _panel()
	dead_p.add_child(Ui.card(Vector2(80, 330), Vector2(920, 1030)))
	dead_header = Ui.label("FLIGHT FAILED", 84, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 380), Vector2(1000, 120))
	dead_p.add_child(dead_header)
	dead_text = Ui.label("", 50, HORIZONTAL_ALIGNMENT_CENTER, Vector2(60, 520), Vector2(960, 340))
	dead_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dead_p.add_child(dead_text)
	retry_btn = Ui.button("RETRY THIS LEG  (AD)", 44, Vector2(190, 880), Vector2(700, 120), Color(0.6, 0.35, 0.85), "ad")
	retry_btn.pressed.connect(func(): retry_pressed.emit())
	dead_p.add_child(retry_btn)
	dead_again = Ui.button("FLY AGAIN", 70, Vector2(190, 1030), Vector2(700, 140), Color(0.95, 0.5, 0.15), "restart")
	dead_menu = Ui.button("MAP", 60, Vector2(190, 1210), Vector2(700, 120), Ui.COL_BTN, "map")
	dead_again.pressed.connect(func(): again_pressed.emit())
	dead_menu.pressed.connect(func(): menu_pressed.emit())
	dead_p.add_child(dead_again)
	dead_p.add_child(dead_menu)

func _build_result() -> void:
	result_p = _panel()
	result_p.add_child(Ui.card(Vector2(40, 200), Vector2(1000, 1490)))
	result_header = Ui.label("FLIGHT COMPLETE!", 80, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 260), Vector2(1000, 120))
	result_p.add_child(result_header)
	result_icons = Control.new()
	result_icons.position = Vector2(90, 430)
	result_icons.size = Vector2(900, 400)
	result_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_icons.draw.connect(func(): _draw_rows(result_icons, result_lit, 55.0, 130.0))
	result_p.add_child(result_icons)
	for i in 3:
		var l := Ui.label("", 42, HORIZONTAL_ALIGNMENT_LEFT, Vector2(220, 445.0 + 130.0 * float(i)), Vector2(770, 80))
		result_p.add_child(l)
		result_rows.append(l)
	result_gauge = _ResultGauge.new()
	result_gauge.hud = self
	result_gauge.position = Vector2(110, 830)
	result_gauge.size = Vector2(860, 70)
	result_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_p.add_child(result_gauge)
	result_summary = Ui.label("", 44, HORIZONTAL_ALIGNMENT_CENTER, Vector2(60, 930), Vector2(960, 400))
	result_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_p.add_child(result_summary)
	result_again = Ui.button("AGAIN", 56, Vector2(90, 1380), Vector2(440, 130), Ui.COL_BTN, "restart")
	result_next = Ui.button("NEXT", 56, Vector2(550, 1380), Vector2(440, 130), Color(0.95, 0.5, 0.15), "next")
	result_menu = Ui.button("MAP", 56, Vector2(190, 1540), Vector2(700, 120), Ui.COL_BTN, "map")
	result_again.pressed.connect(func(): again_pressed.emit())
	result_next.pressed.connect(func(): next_flight_pressed.emit())
	result_menu.pressed.connect(func(): menu_pressed.emit())
	for b in [result_again, result_next, result_menu]:
		result_p.add_child(b)

## Three stars side by side (lit = gold, otherwise dim).
func _draw_three(ci: Control, lit: Array, r: float, gap: float, y: float) -> void:
	for i in 3:
		Ui.draw_star(ci, Vector2(60.0 + gap * float(i), y), r, Style.ACCENT if lit[i] else Color(0.3, 0.33, 0.42))

## Three stars one under the other, one per row. On the result screen a lit star SLAMS in (big, shrinking to its place with a
## thud and a ring, a little higher in pitch each time) when its turn comes; unlit ones are simply there, dim.
func _draw_rows(ci: Control, lit: Array, r: float, gap: float) -> void:
	for i in 3:
		var c := Vector2(55.0, 55.0 + gap * float(i))
		if not lit[i]:
			Ui.draw_star(ci, c, r, Color(0.3, 0.33, 0.42))
			continue
		var ts := 0.35 + 0.5 * float(i)
		if result_t < ts:
			Ui.draw_star(ci, c, r, Color(0.3, 0.33, 0.42, 0.5))
			continue
		var u := clampf((result_t - ts) / 0.4, 0.0, 1.0)
		var k := 1.0 + (1.0 - Style.ease_out_cubic(clampf(u / 0.5, 0.0, 1.0))) * 1.9 + sin(u * PI * 3.0) * 0.08 * (1.0 - u)
		Ui.draw_star(ci, c, r * k, Style.ACCENT)
		if u < 0.7:   # the ring of the impact
			ci.draw_arc(c, r * (1.0 + 2.2 * u), 0.0, TAU, 28, Color(Style.ACCENT, 1.0 - u / 0.7), 6.0)
		if not _star_slammed[i]:
			_star_slammed[i] = true
			Sfx.ui("slam", 1.0 + 0.14 * float(i))
			_shake = 0.3

func _draw_gauge() -> void:
	var sz := gauge.size
	gauge.draw_colored_polygon(SvgArt.rrect(0.0, 0.0, sz.x, sz.y, 56.0), Color(0.078, 0.129, 0.239, 0.9))
	var bx := 130.0
	var bw := sz.x - bx - 36.0
	var by := (sz.y - 46.0) * 0.5
	gauge.draw_style_box(_g_track, Rect2(bx, by, bw, 46))
	var key := "ok"
	if fuel_frac < 0.5:
		key = "mid"
	if fuel_low:
		key = "low_a" if int(_clock * 6.0) % 2 == 0 else "low_b"
	var fw := bw * clampf(fuel_frac, 0.0, 1.0)
	if fw > 12.0:
		gauge.draw_style_box(_g_fill[key], Rect2(bx, by, fw, 46))
		gauge.draw_style_box(_g_sheen, Rect2(bx + 6.0, by + 5.0, maxf(fw - 12.0, 0.0), 12))
	var tx := bx + bw * Tuning.star_propane_frac   # the second star's propane target: the gold tick
	gauge.draw_colored_polygon(SvgArt.rrect(tx - 4.0, by - 12.0, 8.0, 70.0, 4.0), Style.ACCENT)

func _draw_prog() -> void:
	for i in 3:
		Ui.draw_star(prog, Vector2(18.0 + 345.0 * float(i), 25.0), 17.0, Style.ACCENT if prog_lit[i] else Color(0.3, 0.33, 0.42))

# ---- in-flight HUD ----

## Show or hide the in-flight readouts (flight name, score, gauge, star progress): only while flying.
func set_flight_hud(on: bool) -> void:
	for n in [coin_pill, pips, gauge, pause_btn]:
		n.visible = on
	goal_label.visible = on
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
	coin_value.text = Tuning.fmt(float(v))

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
	var pips_s: _Pips = pips
	if pips_s.legs != legs or pips_s.done != legs_done:
		pips_s.legs = legs
		pips_s.done = legs_done
		pips.queue_redraw()
	star_rows = [
		["Finish all %d legs" % legs, "%d / %d" % [legs_done, legs], legs_done >= legs],
		["Land with %d%% propane" % roundi(Tuning.star_propane_frac * 100.0), "on track" if fuel >= Flights.propane_target() else "%d / %d" % [int(fuel), int(Flights.propane_target())], lit1],
		["Collect %d coins" % coin_target, "%d / %d" % [coins, coin_target], lit2]]
	if lit1 != prog_lit[1] or lit2 != prog_lit[2] or prog_lit[0]:
		prog_lit[0] = false
		prog_lit[1] = lit1
		prog_lit[2] = lit2
		prog.queue_redraw()

## The leg's goal line under the star progress ("Stars 2/4", "Mail on board: ..."); only re-texted when it changes.
func set_goal_icon(goal: int) -> void:
	goal_icon.set_icon(["goal_climb", "goal_stars", "goal_mail", "goal_storm", "goal_land"][clampi(goal, 0, 4)])

## A new leg: the goal line may be shown again.
func reset_goal() -> void:
	_goal_cache = ""
	_goal_left = 0.0
	goal_label.modulate.a = 0.0

func set_goal_text(text: String) -> void:
	if text != _goal_cache:   # shown once, big, then it fades away
		_goal_cache = text
		goal_label.text = text
		_goal_left = 3.6
		goal_label.modulate.a = 1.0

## A tool button: whether it is offered, how many charges are left.
func set_tool(i: int, available: bool, charges: int) -> void:
	var tb := tool_btns[i]
	tb.visible = available
	tb.disabled = charges <= 0
	var t := str(charges)
	if tool_badges[i].text != t:
		tool_badges[i].text = t
	tb.text = ""

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
	if _goal_left > 0.0:
		_goal_left -= dt
		goal_label.modulate.a = clampf(_goal_left / 0.8, 0.0, 1.0)
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
	title.visible = false
	pause_p.visible = false
	carry.visible = false
	map.visible = false
	legdone.visible = false
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

## A screen arrives: slide in from the side the navigation came from, over a quick cross-fade.
func _enter(panel: Control) -> void:
	Motion.enter(panel, nav_dir)
	nav_dir = 1
	_flash.modulate.a = 0.55
	var tw := _flash.create_tween()
	tw.tween_property(_flash, "modulate:a", 0.0, Style.T_BASE)

func show_title() -> void:
	hide_overlays()
	title.visible = true
	_enter(title)

func show_menu(region_name: String, blurb: String, title: String, lit1: bool, lit2: bool, lit3: bool, info: String, can_prev: bool, can_next: bool, can_fly: bool, daily: bool = false) -> void:
	hide_overlays()
	prev_btn.visible = not daily
	next_btn.visible = not daily
	menu_stars.visible = not daily
	menu_title.text = region_name
	var ri := Regions.NAMES.find(region_name)
	menu_region_icon.set_icon("region_%d" % ri if ri >= 0 else "balloon")
	menu_blurb.text = blurb
	menu_name.text = title
	menu_lit[0] = lit1
	menu_lit[1] = lit2
	menu_lit[2] = lit3
	menu_stars.queue_redraw()
	menu_info.text = info
	for k in 3:
		menu_star_icons[k].visible = info.begins_with("Finish")
		menu_star_icons[k].set_icon("star")
	prev_btn.disabled = not can_prev
	next_btn.disabled = not can_next
	fly_btn.disabled = not can_fly
	menu_p.visible = true
	_enter(menu_p)

func show_map() -> void:
	hide_overlays()
	map.refresh()
	map.visible = true
	_enter(map)

func show_shop() -> void:
	hide_overlays()
	shop.open()
	shop.visible = true
	_enter(shop)

func show_album() -> void:
	hide_overlays()
	album.refresh()
	album.visible = true
	_enter(album)

## The award screen: over the result screen. state 1 = postcard, 2 = gold.
func show_postcard(region: int, state: int) -> void:
	card_view.set_card(region, state)
	card_header.text = "GOLD POSTCARD!" if state == 2 else "NEW POSTCARD!"
	card_p.visible = true
	_enter(card_p)
	card_view.play_award()

func show_dead(text: String, can_retry: bool = false) -> void:
	hide_overlays()
	dead_text.text = text
	retry_btn.visible = can_retry
	dead_p.visible = true
	_enter(dead_p)

## rows: the three star lines; lit: which stars were earned.
func show_result(row0: String, row1: String, row2: String, lit1: bool, lit2: bool, lit3: bool, summary: String, can_next: bool, fuel_frac: float = 0.0) -> void:
	hide_overlays()
	result_t = 0.0
	result_fuel = clampf(fuel_frac, 0.0, 1.0)
	_star_slammed = [false, false, false]
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
	_enter(result_p)

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
	for k in 3:
		menu_star_icons[k].visible = true
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
	title.visible = true
	pause_p.visible = true
	carry.visible = true
	carry_frac = 0.6
	carry_shown = 0.6
	carry.queue_redraw()
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
