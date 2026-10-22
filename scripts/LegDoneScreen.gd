class_name LegDoneScreen
extends Control
## "LEG N LANDED": the balloon rests on the meadow under a sunrise sky, a card shows the propane carried into the next leg's tank
## (with the gold 30 % tick) and the Flight's three star goals so far, then a big NEXT LEG button and a quiet ad pill.
## Storybook Sky; built once, refreshed with show_leg().

signal next_pressed
signal boost_pressed

const K := 2.769                       # the canvas is 390 wide; this screen is 1080
var title: Label
var place: Label
var card: Panel
var pct: Label
var next_btn: Button
var boost_btn: Button
var rows: Array[Label] = []             # [text, progress] per star goal
var row_icons: Array[IconView] = []
var frac := 0.0
var _shown := 0.0
var _t := 0.0
var _gauge: Control
var _scene: Control
var _tick := 0.3

func _ready() -> void:
	size = Vector2(Lanes.W, Lanes.H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_scene = _Scene.new()
	_scene.size = size
	_scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scene)
	place = Ui.label("", 40, HORIZONTAL_ALIGNMENT_CENTER, Vector2(240, 130), Vector2(600, 72))
	place.add_theme_constant_override("outline_size", 0)
	place.add_theme_stylebox_override("normal", Style.box(Color(0.078, 0.129, 0.239, 0.82), Color(0, 0, 0, 0), 36, 0, false))
	add_child(place)
	title = Ui.label("", 124, HORIZONTAL_ALIGNMENT_CENTER, Vector2(0, 206), Vector2(Lanes.W, 160))
	title.add_theme_constant_override("outline_size", 20)
	add_child(title)
	card = Panel.new()
	card.position = Vector2(80, 420)
	card.size = Vector2(920, 740)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", Style.box(Style.SURFACE_DARK, Color(1, 1, 1, 0.2), 80, 8, true))
	add_child(card)
	var l1 := Ui.label("Propane carried to leg 3", 42, HORIZONTAL_ALIGNMENT_LEFT, Vector2(56, 48), Vector2(620, 60))
	l1.add_theme_constant_override("outline_size", 0)
	card.add_child(l1)
	_carry_label = l1
	pct = Ui.label("64%", 62, HORIZONTAL_ALIGNMENT_RIGHT, Vector2(640, 36), Vector2(224, 80))
	pct.add_theme_color_override("font_color", Style.SUCCESS)
	pct.add_theme_constant_override("outline_size", 0)
	card.add_child(pct)
	_gauge = _Gauge.new()
	_gauge.owner_screen = self
	_gauge.position = Vector2(56, 130)
	_gauge.size = Vector2(808, 124)
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_gauge)
	var head := Ui.label("FLIGHT STARS SO FAR", 36, HORIZONTAL_ALIGNMENT_LEFT, Vector2(56, 300), Vector2(808, 50))
	head.add_theme_color_override("font_color", Style.TEXT_SOFT)
	head.add_theme_constant_override("outline_size", 0)
	card.add_child(head)
	for i in 3:
		var iv := Ui.icon("star", 66, Vector2(56, 378.0 + float(i) * 104.0))
		card.add_child(iv)
		row_icons.append(iv)
		var a := Ui.label("", 42, HORIZONTAL_ALIGNMENT_LEFT, Vector2(140, 380.0 + float(i) * 104.0), Vector2(520, 62))
		a.add_theme_constant_override("outline_size", 0)
		card.add_child(a)
		rows.append(a)
		var b := Ui.label("", 42, HORIZONTAL_ALIGNMENT_RIGHT, Vector2(560, 380.0 + float(i) * 104.0), Vector2(304, 62))
		b.add_theme_color_override("font_color", Style.TEXT_SOFT)
		b.add_theme_constant_override("outline_size", 0)
		card.add_child(b)
		rows.append(b)
	next_btn = Ui.button("NEXT LEG", 100, Vector2(80, 1540), Vector2(920, 220), Color(0.95, 0.5, 0.15), "play")
	next_btn.pressed.connect(func(): next_pressed.emit())
	add_child(next_btn)
	boost_btn = Button.new()
	boost_btn.text = "Watch for +50% propane next leg"
	boost_btn.position = Vector2(180, 1790)
	boost_btn.size = Vector2(720, 120)
	boost_btn.focus_mode = Control.FOCUS_NONE
	boost_btn.add_theme_font_override("font", Style.font_for("Nunito", 38))
	boost_btn.add_theme_font_size_override("font_size", 38)
	for st in ["normal", "hover", "pressed", "focus"]:
		boost_btn.add_theme_stylebox_override(st, Style.box(Color(0.078, 0.129, 0.239, 0.85), Color(0, 0, 0, 0), 60, 0, false))
	Ui.hook_press(boost_btn, "ad")
	boost_btn.pressed.connect(func(): boost_pressed.emit())
	add_child(boost_btn)
	Ui.add_icon(boost_btn, "ad", 50.0)

var _carry_label: Label

## Fill the screen: `leg_done` legs are finished (so "LEG n LANDED" is n = leg_done), the carried propane as a share of the tank,
## the Flight's three star goals [text, progress, lit], and whether the ad pill is offered.
func show_leg(region_name: String, flight_no: int, leg_done: int, legs: int, carry: float, star_rows: Array, can_boost: bool) -> void:
	place.text = "%s  ·  FLIGHT %d" % [region_name.to_upper(), flight_no]
	title.text = "LEG %d LANDED" % leg_done
	_carry_label.text = "Propane carried to leg %d" % (leg_done + 1)
	frac = clampf(carry, 0.0, 1.0)
	_shown = 0.0
	_t = 0.0
	pct.text = "%d%%" % roundi(frac * 100.0)
	for i in 3:
		var r: Array = star_rows[i] if i < star_rows.size() else ["", "", false]
		rows[i * 2].text = r[0]
		rows[i * 2 + 1].text = r[1]
		rows[i * 2 + 1].add_theme_color_override("font_color", Style.SUCCESS if r[1] == "on track" else Style.TEXT_SOFT)
		row_icons[i].set_icon("star" if r[2] else "star_off")
	boost_btn.visible = can_boost
	_gauge.queue_redraw()
	_scene.queue_redraw()
	set_process(true)

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var v := frac * Style.ease_out_cubic(clampf((_t - 0.2) / 0.6, 0.0, 1.0))
	if absf(v - _shown) > 0.001:
		_shown = v
		_gauge.queue_redraw()

class _Gauge extends Control:
	var owner_screen: LegDoneScreen
	func _draw() -> void:
		Icons.draw(self, "propane", Vector2(46, size.y * 0.5), 46.0)
		var track := Rect2(110, 34, size.x - 110.0, 56)
		draw_colored_polygon(SvgArt.rrect(track.position.x, track.position.y, track.size.x, track.size.y, 28.0), Color(1, 1, 1, 0.12))
		var fw := track.size.x * owner_screen._shown
		if fw > 14.0:
			draw_colored_polygon(SvgArt.rrect(track.position.x, track.position.y, fw, track.size.y, 28.0), Style.SUCCESS)
		var tx := track.position.x + track.size.x * Tuning.star_propane_frac
		draw_colored_polygon(SvgArt.rrect(tx - 4.0, track.position.y - 14.0, 8.0, track.size.y + 28.0, 4.0), Style.ACCENT)

## The meadow, the sky and the landed balloon (static).
class _Scene extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([Color("5f9fe0"), Color("5f9fe0"), Color("ffd59a"), Color("ffd59a")]))
		for c in [Vector2(170, 560), Vector2(880, 380), Vector2(760, 1190)]:   # clouds
			var cc: Vector2 = c
			for part in [Vector2(0, 0), Vector2(56, -22), Vector2(116, 6), Vector2(176, -8)]:
				draw_circle(cc + part, 40.0 + absf(part.x - 60.0) * -0.08, Color(1, 1, 1, 0.8))
		var k := LegDoneScreen.K
		SvgArt.fill(self, "M0 640C80 620 160 650 240 630C310 614 360 636 390 628V844H0Z", Color("7cc06a"), Vector2(0, -118.0), k)
		SvgArt.fill(self, "M0 700C100 684 220 708 390 690V844H0Z", Color("62a957"), Vector2(0, -118.0), k)
		draw_set_transform(Vector2(w * 0.5, 1300.0), -0.05, Vector2(1.94, 1.94))
		BalloonArt.shared().draw_body(self, Save.equipped(0), Save.equipped(1), Save.equipped(2), 4.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var seed_v := 5
		for i in 18:   # confetti
			seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
			var cx := float(seed_v % 1000) + 40.0
			seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
			var cy := 1180.0 + float(seed_v % 330)
			var col: Color = [Style.ACCENT, Style.SUCCESS, Style.DANGER, Style.PRIMARY][i % 4]
			draw_set_transform(Vector2(cx, cy), float(i) * 0.7, Vector2.ONE)
			draw_rect(Rect2(-9, -15, 18, 30), col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
