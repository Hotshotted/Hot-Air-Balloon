class_name Hud
extends CanvasLayer
## All on-screen text and the propane gauge. Every node is created once in _ready (and drawn during the
## start-up pre-warm); after that labels are only re-texted when a value changes and shown / hidden.

var level_label: Label
var score_label: Label
var best_label: Label
var stamp_label: Label
var banner: Label
var title: Label
var info: Label
var tap_label: Label
var over_header: Label
var over_text: Label
var splash: ColorRect
var gauge: Control
var fuel_frac := 1.0
var fuel_low := false
var _banner_left := 0.0
var _clock := 0.0
var _perf_label: Label
var _perf_worst := 0.0
var _perf_window_start := 0
var _perf_shown := 0.0
var _perf_extra := ""
var _hitch_log: Array[String] = []

func _ready() -> void:
	layer = 5
	level_label = _label(46, HORIZONTAL_ALIGNMENT_LEFT, Vector2(30, 24), Vector2(400, 60))
	score_label = _label(46, HORIZONTAL_ALIGNMENT_CENTER, Vector2(340, 24), Vector2(400, 60))
	best_label = _label(30, HORIZONTAL_ALIGNMENT_CENTER, Vector2(340, 74), Vector2(400, 40))
	best_label.modulate = Color(1, 1, 1, 0.8)
	stamp_label = _label(22, HORIZONTAL_ALIGNMENT_RIGHT, Vector2(560, 1870), Vector2(500, 36))
	stamp_label.modulate = Color(1, 1, 1, 0.6)
	var flags := DebugFlags.summary()
	stamp_label.text = "%s  %s%s" % [BuildInfo.COMMIT, BuildInfo.TIME, ("  " + flags) if flags != "" else ""]
	gauge = Control.new()
	gauge.position = Vector2(30, 120)
	gauge.size = Vector2(1020, 34)
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.draw.connect(_draw_gauge)
	add_child(gauge)
	banner = _label(84, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 760), Vector2(1000, 260))
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title = _label(120, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 520), Vector2(1000, 160))
	title.text = "WIND LAYERS"
	info = _label(40, HORIZONTAL_ALIGNMENT_CENTER, Vector2(90, 700), Vector2(900, 330))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "HOLD to fire the burner and rise.\nRELEASE to sink slowly.\nEvery layer of sky blows its own way, and carries birds, kites, balloons and drones.\nClimb to the top. Mind your propane."
	tap_label = _label(70, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 1080), Vector2(1000, 110))
	over_header = _label(76, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 520), Vector2(1000, 200))
	over_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	over_text = _label(52, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 760), Vector2(1000, 280))
	splash = ColorRect.new()
	splash.color = Color(0.06, 0.1, 0.18, 0.97)
	splash.size = Vector2(Lanes.W, Lanes.H)
	splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	splash.visible = false
	add_child(splash)
	var splash_text := Label.new()
	splash_text.text = "WIND LAYERS\nloading..."
	splash_text.add_theme_font_size_override("font_size", 64)
	splash_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	splash_text.position = Vector2(0, 780)
	splash_text.size = Vector2(Lanes.W, 300)
	splash.add_child(splash_text)
	if DebugFlags.perf_enabled():
		_perf_label = _label(26, HORIZONTAL_ALIGNMENT_LEFT, Vector2(14, 170), Vector2(900, 400))
		_perf_label.modulate = Color(0.6, 1, 0.6, 0.95)
	hide_overlays()

func _label(size: int, align: HorizontalAlignment, pos: Vector2, area: Vector2) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(size / 7, 4))
	l.position = pos
	l.size = area
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _draw_gauge() -> void:
	var r := Rect2(0, 0, 1020, 34)
	gauge.draw_rect(r, Color(0.1, 0.12, 0.18, 0.85))
	var col := Color(0.3, 0.9, 0.45)
	if fuel_frac < 0.5:
		col = Color(1.0, 0.75, 0.2)
	if fuel_low:
		col = Color(1.0, 0.25, 0.2) if int(_clock * 6.0) % 2 == 0 else Color(1.0, 0.6, 0.3)
	gauge.draw_rect(Rect2(3, 3, 1014.0 * clampf(fuel_frac, 0.0, 1.0), 28), col)
	gauge.draw_rect(r, Color.BLACK, false, 4.0)

func set_level(n: int) -> void:
	level_label.text = "LEVEL %d" % n

func set_score(v: int) -> void:
	score_label.text = Tuning.fmt(float(v))

func set_best(v: int) -> void:
	best_label.text = "best %s" % Tuning.fmt(float(v)) if v > 0 else ""

func set_fuel(frac: float) -> void:
	var low := frac < Tuning.propane_low_fraction
	if absf(frac - fuel_frac) > 0.0005 or low != fuel_low:
		fuel_frac = frac
		fuel_low = low
		gauge.queue_redraw()

## Short message in the middle ("LEVEL 3", "+120 speed bonus"), gone after `secs`.
func show_banner(text: String, secs: float) -> void:
	banner.text = text
	banner.visible = true
	_banner_left = secs

func tick(dt: float) -> void:
	_clock += dt
	if fuel_low:
		gauge.queue_redraw()
	if _banner_left > 0.0:
		_banner_left -= dt
		if _banner_left <= 0.0:
			banner.visible = false

func hide_overlays() -> void:
	banner.visible = false
	title.visible = false
	info.visible = false
	tap_label.visible = false
	over_header.visible = false
	over_text.visible = false
	_banner_left = 0.0

func show_menu() -> void:
	hide_overlays()
	title.visible = true
	info.visible = true
	tap_label.text = "TAP TO FLY"
	tap_label.visible = true

func show_over(reason: String, score: int, level: int, best: int, new_best: bool) -> void:
	hide_overlays()
	over_header.text = reason
	over_text.text = "Level %d reached\nScore %s%s" % [level, Tuning.fmt(float(score)), "\nNEW BEST!" if new_best else "\nBest %s" % Tuning.fmt(float(best))]
	tap_label.text = "TAP TO RETRY"
	over_header.visible = true
	over_text.visible = true
	tap_label.visible = true

func begin_prewarm() -> void:
	hide_overlays()
	title.visible = true
	info.visible = true
	tap_label.visible = true
	over_header.text = "x"
	over_text.text = "x\nx\nx"
	over_header.visible = true
	over_text.visible = true
	banner.text = "LEVEL 10\n+250 bonus"
	banner.visible = true
	set_level(10)
	set_score(1234567)
	set_best(1234567)
	set_fuel(0.2)
	splash.visible = true

func end_prewarm() -> void:
	splash.visible = false
	hide_overlays()

# ---- ?perf ----

func set_perf_extra(text: String) -> void:
	_perf_extra = text

func note_hitch(raw: float, used: float, why: String, context: String) -> void:
	_hitch_log.append("%.0f ms (sim %.0f): %s | %s" % [raw * 1000.0, used * 1000.0, why, context])
	if _hitch_log.size() > 5:
		_hitch_log.pop_front()

func update_perf(delta: float) -> void:
	if _perf_label == null:
		return
	_perf_worst = maxf(_perf_worst, delta * 1000.0)
	var now := Time.get_ticks_msec()
	if now - _perf_window_start > 3000:
		_perf_shown = _perf_worst
		_perf_worst = 0.0
		_perf_window_start = now
	_perf_label.text = "worst frame (3s): %.0f ms   %d fps\n%s\nhitches (over 50 ms):\n%s" % [_perf_shown, Engine.get_frames_per_second(), _perf_extra, "\n".join(_hitch_log)]
