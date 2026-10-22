class_name PostcardView
extends Control
## A postcard of a region, built from primitives: the region's backdrop, a landmark, a balloon, a stamp and
## a title. Gold postcards (every Flight of the region 3-starred) get a gold frame and sparkles. A card that
## has not been earned yet is a grey silhouette. Used by the album, its zoom view and the award screen.

signal tapped

const GREETINGS := ["Greetings from the Countryside", "Greetings from the Alps", "Greetings from the Sahara", "Greetings from the Himalayas"]
const GOLD := Color(1.0, 0.82, 0.15)
const PAPER := Color(0.98, 0.95, 0.86)

var region := 0
var state := 0              # 0 = not earned, 1 = postcard, 2 = gold postcard
var title: Label
var hint: Label
var _pts := PackedVector2Array()
var stamp_amt := 1.0        # the round postmark: 0 = not yet stamped, 1 = stamped (it slams down with an overshoot)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	title = Ui.label("", 30, HORIZONTAL_ALIGNMENT_CENTER, Vector2.ZERO, Vector2.ONE)
	title.add_theme_color_override("font_color", Color(0.15, 0.12, 0.1))
	title.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0))
	title.add_theme_constant_override("outline_size", 0)
	add_child(title)
	hint = Ui.label("", 26, HORIZONTAL_ALIGNMENT_CENTER, Vector2.ZERO, Vector2.ONE)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	_pts.resize(12)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if title == null:
		return
	var fs := maxi(int(size.y * 0.075), 16)
	title.add_theme_font_size_override("font_size", fs)
	title.position = Vector2(10.0, size.y - fs * 1.9)
	title.size = Vector2(size.x - 20.0, fs * 1.6)
	hint.add_theme_font_size_override("font_size", maxi(int(size.y * 0.075), 16))
	hint.position = Vector2(30.0, size.y * 0.36)
	hint.size = Vector2(size.x - 60.0, size.y * 0.3)

## Show region r's card in state 0 (not earned), 1 (postcard) or 2 (gold).
func set_card(r: int, st: int, requirement: String = "") -> void:
	region = r
	state = st
	title.text = GREETINGS[r] if st > 0 else "???"
	hint.text = requirement if st == 0 else ""
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit()

func _draw() -> void:
	var s := size
	var u := s.y / 330.0   # drawing unit: everything scales with the card height
	draw_rect(Rect2(Vector2.ZERO, s), PAPER)
	var pic := Rect2(Vector2(14.0 * u, 14.0 * u), Vector2(s.x - 28.0 * u, s.y - 28.0 * u - 62.0 * u))
	if state == 0:
		draw_rect(pic, Color(0.42, 0.44, 0.5))
		draw_rect(pic, Color.BLACK, false, 4.0 * u)
		draw_rect(Rect2(Vector2.ZERO, s), Color.BLACK, false, 6.0 * u)
		return
	Regions.draw_backdrop(self, region, pic, 4.0 * u)
	_landmark(pic, u)
	_balloon(Vector2(pic.position.x + pic.size.x * 0.5, pic.position.y + pic.size.y * 0.34), u * 0.95)
	# Stamp, top right.
	var st := Rect2(Vector2(s.x - 92.0 * u, 22.0 * u), Vector2(60.0 * u, 70.0 * u))
	draw_rect(st, Color(1, 1, 1))
	draw_rect(st, Color.BLACK, false, 3.0 * u)
	draw_rect(st.grow(-8.0 * u), Regions.SKY_HIGH[region])
	Ui.draw_star(self, st.get_center(), 14.0 * u, GOLD)
	if state == 2:   # gold: a thick gold frame, corner stars and a ribbon
		draw_rect(Rect2(Vector2.ZERO, s), GOLD, false, 12.0 * u)
		for c in [Vector2(0, 0), Vector2(s.x, 0), Vector2(0, s.y), Vector2(s.x, s.y)]:
			Ui.draw_star(self, c, 22.0 * u, GOLD)
		var rb := Rect2(Vector2(16.0 * u, 22.0 * u), Vector2(110.0 * u, 34.0 * u))
		draw_rect(rb, GOLD)
		draw_rect(rb, Color.BLACK, false, 3.0 * u)
		Ui.draw_star(self, rb.get_center() - Vector2(28.0 * u, 0), 10.0 * u, Color.WHITE)
		Ui.draw_star(self, rb.get_center(), 10.0 * u, Color.WHITE)
		Ui.draw_star(self, rb.get_center() + Vector2(28.0 * u, 0), 10.0 * u, Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, s), Color.BLACK, false, 5.0 * u)
	if stamp_amt > 0.01:
		_postmark(Vector2(s.x * 0.2, s.y * 0.56), u)

## A round red postmark with wavy cancel lines and a star: the card has been stamped into the album.
func _postmark(c: Vector2, u: float) -> void:
	var k := 1.0 + (1.0 - Style.ease_out_back(stamp_amt)) * 1.8
	var a := clampf(stamp_amt * 1.6, 0.0, 1.0) * 0.88
	var col := Color(0.8, 0.15, 0.15, a)
	draw_set_transform(c, -0.21, Vector2(k * u, k * u))
	draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 28, col, 4.0)
	draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 24, col, 2.0)
	var star := PackedVector2Array()
	for i in 10:
		var ang := -PI * 0.5 + TAU * float(i) / 10.0
		star.append(Vector2(cos(ang), sin(ang)) * 12.0 * (1.0 if i % 2 == 0 else 0.45))
	draw_colored_polygon(star, Color(0.8, 0.15, 0.15, a))
	for i in 3:
		var pts := PackedVector2Array()
		for j in 9:
			pts.append(Vector2(44.0 + float(j) * 9.0, -14.0 + float(i) * 14.0 + sin(float(j) * 1.4) * 3.0))
		draw_polyline(pts, col, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## The award animation: the card flips over (a quick turn about its middle), then the postmark slams down with a thud.
func play_award() -> void:
	if has_meta("pw"):
		var old: Tween = get_meta("pw")
		if old != null and old.is_valid():
			old.kill()
	pivot_offset = size * 0.5
	scale = Vector2(0.0, 1.0)
	rotation = -0.12
	stamp_amt = 0.0
	var tw := create_tween()
	set_meta("pw", tw)
	tw.tween_property(self, "scale:x", 1.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "rotation", 0.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): Sfx.ui("whoosh"))
	tw.tween_interval(0.12)
	tw.tween_method(func(v: float): stamp_amt = v; queue_redraw(), 0.0, 1.0, 0.32)
	tw.tween_callback(func(): Sfx.ui("slam"))

## The card slides into the album button (shrinking as it goes), then `done` runs.
func slide_to(target_center: Vector2, done: Callable) -> void:
	pivot_offset = size * 0.5
	var tw := create_tween()
	var end := target_center - size * 0.5
	tw.set_parallel(true)
	tw.tween_property(self, "position", end, Style.T_BASE * 1.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "scale", Vector2(0.12, 0.12), Style.T_BASE * 1.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(done)
	Sfx.ui("whoosh")

func _poly(points: Array, fill: Color, w: float) -> void:
	_pts.resize(points.size())
	for i in points.size():
		_pts[i] = points[i]
	draw_colored_polygon(_pts, fill)
	_pts.resize(points.size() + 1)
	_pts[points.size()] = _pts[0]
	draw_polyline(_pts, Color.BLACK, w)

func _balloon(c: Vector2, u: float) -> void:
	var w := 3.5 * u
	_poly([c + Vector2(-26, -4) * u, c + Vector2(-16, -34) * u, c + Vector2(0, -42) * u, c + Vector2(16, -34) * u, c + Vector2(26, -4) * u, c + Vector2(12, 22) * u, c + Vector2(-12, 22) * u], Color(1.0, 0.45, 0.16), w)
	_poly([c + Vector2(-8, -40) * u, c + Vector2(8, -40) * u, c + Vector2(6, 22) * u, c + Vector2(-6, 22) * u], Color(1.0, 0.94, 0.78), w * 0.7)
	_poly([c + Vector2(-8, 34) * u, c + Vector2(8, 34) * u, c + Vector2(7, 46) * u, c + Vector2(-7, 46) * u], Color(0.62, 0.4, 0.2), w)
	draw_line(c + Vector2(-9, 22) * u, c + Vector2(-8, 34) * u, Color.BLACK, w * 0.7)
	draw_line(c + Vector2(9, 22) * u, c + Vector2(8, 34) * u, Color.BLACK, w * 0.7)

## The landmark of each region, at the bottom of the picture.
func _landmark(pic: Rect2, u: float) -> void:
	var w := 3.5 * u
	var base := pic.position.y + pic.size.y * 0.82
	var x0 := pic.position.x
	var pw := pic.size.x
	match region:
		0:   # a windmill and the sun
			draw_circle(Vector2(x0 + pw * 0.14, pic.position.y + pic.size.y * 0.2), 26.0 * u, Color(1.0, 0.88, 0.3))
			var mx := x0 + pw * 0.78
			_poly([Vector2(mx - 22 * u, base), Vector2(mx - 12 * u, base - 90 * u), Vector2(mx + 12 * u, base - 90 * u), Vector2(mx + 22 * u, base)], Color(0.95, 0.9, 0.8), w)
			_poly([Vector2(mx - 16 * u, base - 90 * u), Vector2(mx, base - 108 * u), Vector2(mx + 16 * u, base - 90 * u)], Color(0.7, 0.25, 0.2), w)
			var hub := Vector2(mx, base - 74 * u)
			for a in [0.5, 2.07, 3.64, 5.21]:
				draw_line(hub, hub + Vector2(cos(a), sin(a)) * 46.0 * u, Color.BLACK, 6.0 * u)
				draw_line(hub, hub + Vector2(cos(a), sin(a)) * 44.0 * u, Color(1, 1, 1), 2.5 * u)
			draw_circle(hub, 6.0 * u, Color.BLACK)
		1:   # a chalet and a cable car
			var hx := x0 + pw * 0.2
			_poly([Vector2(hx - 34 * u, base), Vector2(hx - 34 * u, base - 36 * u), Vector2(hx + 34 * u, base - 36 * u), Vector2(hx + 34 * u, base)], Color(0.7, 0.45, 0.25), w)
			_poly([Vector2(hx - 42 * u, base - 36 * u), Vector2(hx, base - 70 * u), Vector2(hx + 42 * u, base - 36 * u)], Color(0.65, 0.2, 0.2), w)
			var cy0 := pic.position.y + pic.size.y * 0.14
			var cy1 := pic.position.y + pic.size.y * 0.5
			draw_line(Vector2(x0, cy0), Vector2(x0 + pw, cy1), Color.BLACK, 4.0 * u)
			var cx := x0 + pw * 0.72
			var cy := cy0 + (cy1 - cy0) * 0.72
			draw_line(Vector2(cx, cy), Vector2(cx, cy + 16 * u), Color.BLACK, 3.0 * u)
			_poly([Vector2(cx - 22 * u, cy + 16 * u), Vector2(cx + 22 * u, cy + 16 * u), Vector2(cx + 22 * u, cy + 44 * u), Vector2(cx - 22 * u, cy + 44 * u)], Color(0.9, 0.25, 0.25), w)
		2:   # pyramids and a palm
			draw_circle(Vector2(x0 + pw * 0.84, pic.position.y + pic.size.y * 0.24), 30.0 * u, Color(1.0, 0.86, 0.3))
			_poly([Vector2(x0 + pw * 0.14, base), Vector2(x0 + pw * 0.3, base - 90 * u), Vector2(x0 + pw * 0.46, base)], Color(0.92, 0.76, 0.4), w)
			_poly([Vector2(x0 + pw * 0.34, base), Vector2(x0 + pw * 0.5, base - 62 * u), Vector2(x0 + pw * 0.64, base)], Color(0.85, 0.68, 0.34), w)
			var px := x0 + pw * 0.8
			draw_line(Vector2(px, base), Vector2(px + 6 * u, base - 70 * u), Color.BLACK, 8.0 * u)
			for a in [-2.6, -2.0, -1.2, -0.55]:
				draw_line(Vector2(px + 6 * u, base - 70 * u), Vector2(px + 6 * u, base - 70 * u) + Vector2(cos(a), sin(a)) * 34.0 * u, Color(0.2, 0.55, 0.25), 7.0 * u)
		3:   # a temple, prayer flags and a moon
			draw_circle(Vector2(x0 + pw * 0.12, pic.position.y + pic.size.y * 0.2), 20.0 * u, Color(0.95, 0.95, 1.0))
			var tx := x0 + pw * 0.74
			_poly([Vector2(tx - 40 * u, base), Vector2(tx - 40 * u, base - 28 * u), Vector2(tx + 40 * u, base - 28 * u), Vector2(tx + 40 * u, base)], Color(0.95, 0.9, 0.85), w)
			_poly([Vector2(tx - 30 * u, base - 28 * u), Vector2(tx - 30 * u, base - 52 * u), Vector2(tx + 30 * u, base - 52 * u), Vector2(tx + 30 * u, base - 28 * u)], Color(0.85, 0.2, 0.2), w)
			_poly([Vector2(tx - 40 * u, base - 52 * u), Vector2(tx, base - 78 * u), Vector2(tx + 40 * u, base - 52 * u)], Color(0.95, 0.75, 0.2), w)
			var fy := pic.position.y + pic.size.y * 0.5
			draw_line(Vector2(x0 + pw * 0.04, fy), Vector2(x0 + pw * 0.5, fy + 20 * u), Color.BLACK, 3.0 * u)
			var cols := [Color(0.9, 0.2, 0.2), Color(0.95, 0.85, 0.2), Color(0.2, 0.6, 0.9), Color(0.3, 0.8, 0.4)]
			for i in 4:
				var fx := x0 + pw * (0.1 + 0.1 * float(i))
				var fyy := fy + 20.0 * u * (0.1 + 0.1 * float(i)) / 0.46
				_poly([Vector2(fx, fyy), Vector2(fx + 18 * u, fyy), Vector2(fx + 9 * u, fyy + 24 * u)], cols[i], 2.5 * u)
