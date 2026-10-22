class_name TitleScreen
extends Control
## The living title screen: balloons drifting over a valley at dawn. A gradient sky with a rising sun, three parallax rows of
## hills that creep past, clouds, and a handful of balloons (each a different cosmetic) bobbing upward. Everything is drawn
## ONCE; `_process` only moves the pieces (their `position`) while the screen is visible. PLAY is the one primary button.

signal play_pressed
signal daily_pressed
signal shop_pressed

const SKY_TOP := Color("2b3f7a")
const SKY_MID := Color("e8728a")
const SKY_LOW := Color("ffb36b")
const SKY_HORIZON := Color("ffe2a6")
const HILL_COLS := [Color("7a5aa6"), Color("4f6fb0"), Color("3f9a62"), Color("2f7d4d")]   # purple, blue, two greens: layered hills
const HILL_Y := [1370.0, 1480.0, 1610.0, 1740.0]
const HILL_SPEED := [4.0, 8.0, 14.0, 22.0]
const WIDE := 2160.0

var play_btn: Button
var logo_a: Label
var logo_b: Label
var tagline: Label
var _hills: Array[Control] = []
var _clouds: Array[Control] = []
var _cloud_speed := PackedFloat32Array()
var _balloons: Array[Control] = []
var _b_base := PackedVector2Array()
var _b_phase := PackedFloat32Array()
var _b_speed := PackedFloat32Array()
var _t := 0.0

func _ready() -> void:
	size = Vector2(Lanes.W, Lanes.H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for i in 4:
		var h := _HillRow.new()
		h.size = Vector2(WIDE, Lanes.H)
		h.seed_v = 11 + i * 7
		h.base_y = HILL_Y[i]
		h.col = HILL_COLS[i]
		h.amp = 110.0 - 20.0 * float(i)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(h)
		_hills.append(h)
	# balloons between the far and the near hills (so the near hills pass in front of them)
	var picks := [[2, 0, 0, 1.0, 40.0, 900.0], [1, 3, 0, 0.8, 800.0, 560.0], [3, 4, 0, 0.5, 660.0, 1280.0], [0, 0, 1, 1.9, 300.0, 700.0]]   # purple, blue, a small green far away, and the big red one in front
	for p in picks:
		var bs := _BalloonSprite.new()
		bs.env = p[0]
		bs.basket = p[1]
		bs.pas = p[2]
		bs.k = p[3]
		bs.size = Vector2(240.0 * maxf(float(p[3]), 1.0), 300.0 * maxf(float(p[3]), 1.0))
		bs.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bs.position = Vector2(p[4], p[5])
		add_child(bs)
		move_child(bs, 4 + _balloons.size())
		_balloons.append(bs)
		_b_base.append(bs.position)
		_b_phase.append(float(_balloons.size()) * 1.7)
		_b_speed.append(14.0 + 7.0 * float(_balloons.size()))
	for i in 5:
		var c := _Cloud.new()
		c.size = Vector2(300, 120)
		c.k = 0.6 + 0.25 * float(i % 3)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.position = Vector2(float(i) * 260.0 - 100.0, 260.0 + float((i * 97) % 520))
		add_child(c)
		move_child(c, 1)
		_clouds.append(c)
		_cloud_speed.append(8.0 + 5.0 * float(i % 3))
	logo_a = Ui.label("WIND", 236, HORIZONTAL_ALIGNMENT_CENTER, Vector2(0, 150), Vector2(Lanes.W, 260))
	logo_b = Ui.label("LAYERS", 236, HORIZONTAL_ALIGNMENT_CENTER, Vector2(0, 370), Vector2(Lanes.W, 260))
	for l in [logo_a, logo_b]:
		l.add_theme_constant_override("outline_size", 30)
	logo_b.add_theme_color_override("font_color", Style.ACCENT)
	add_child(logo_a)
	add_child(logo_b)
	tagline = Ui.label("RIDE THE WIND AROUND THE WORLD", 36, HORIZONTAL_ALIGNMENT_CENTER, Vector2(140, 650), Vector2(800, 72))
	tagline.add_theme_constant_override("outline_size", 0)
	tagline.add_theme_stylebox_override("normal", Style.box(Color(0.078, 0.129, 0.239, 0.85), Color(0, 0, 0, 0), 36, 0, false))
	add_child(tagline)
	play_btn = Ui.button("FLY", 124, Vector2(83, 1440), Vector2(914, 266), Color(0.95, 0.5, 0.15), "play")
	play_btn.pressed.connect(func(): play_pressed.emit())
	add_child(play_btn)
	var pill_x := 140.0
	for spec in [["Daily flight", "daily", 420.0], ["Shop", "shop", 300.0]]:
		var pb := Button.new()
		pb.text = spec[0]
		pb.position = Vector2(pill_x, 1760)
		pb.size = Vector2(spec[2], 120)
		pb.focus_mode = Control.FOCUS_NONE
		pb.add_theme_font_override("font", Style.font_for("Nunito", 40))
		pb.add_theme_font_size_override("font_size", 40)
		for st in ["normal", "hover", "pressed", "focus"]:
			pb.add_theme_stylebox_override(st, Style.box(Color(0.078, 0.129, 0.239, 0.88), Color(0, 0, 0, 0), 60, 0, false))
		Ui.hook_press(pb, "")
		Ui.add_icon(pb, spec[1], 52.0)
		var kind: String = spec[1]
		pb.pressed.connect(func(): daily_pressed.emit() if kind == "daily" else shop_pressed.emit())
		add_child(pb)
		pill_x += float(spec[2]) + 40.0
	Ui.fit_safe(self)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	for i in 4:
		_hills[i].position.x = -fposmod(_t * HILL_SPEED[i], 1080.0)
	for i in _balloons.size():   # a gentle sway and bob (the balloons stay where the picture put them)
		_balloons[i].position = _b_base[i] + Vector2(sin(_t * 0.35 + _b_phase[i]) * 18.0, sin(_t * 0.8 + _b_phase[i]) * 14.0)
	for i in _clouds.size():
		var c := _clouds[i]
		c.position.x += _cloud_speed[i] * delta
		if c.position.x > Lanes.W + 40.0:
			c.position.x = -340.0
	play_btn.scale = Vector2.ONE * (1.0 + 0.012 * sin(_t * 3.0)) if not play_btn.is_pressed() else play_btn.scale

func _draw() -> void:
	# sky: a vertical gradient (sunset: deep blue, rose, orange, cream at the horizon), drawn once
	var bands := 64
	for i in bands:
		var u := float(i) / float(bands - 1)
		var col: Color
		if u < 0.45:
			col = SKY_TOP.lerp(SKY_MID, u / 0.45)
		elif u < 0.75:
			col = SKY_MID.lerp(SKY_LOW, (u - 0.45) / 0.3)
		else:
			col = SKY_LOW.lerp(SKY_HORIZON, (u - 0.75) / 0.25)
		draw_rect(Rect2(0, 1500.0 * float(i) / float(bands), Lanes.W, 1500.0 / float(bands) + 1.0), col)
	draw_rect(Rect2(0, 1500, Lanes.W, Lanes.H - 1500.0), Color("2f7d4d"))
	for r in [[Vector2(60, 330), 400.0], [Vector2(540, 540), 380.0], [Vector2(700, 800), 380.0]]:   # soft wind ribbons
		var o: Vector2 = r[0]
		var pts := PackedVector2Array()
		for k in 9:
			pts.append(o + Vector2(float(k) * float(r[1]) / 8.0, sin(float(k) * 0.9) * 14.0))
		draw_polyline(pts, Color(1, 1, 1, 0.5), 8.0, true)
	var sun := Vector2(750, 1250)   # the setting sun with soft halos
	draw_circle(sun, 250.0, Color(1.0, 0.95, 0.78, 0.3))
	draw_circle(sun, 166.0, Color("fff6dc"))

## A row of rolling hills, drawn once, twice the screen wide so it can wrap while it creeps.
class _HillRow extends Control:
	var seed_v := 1
	var base_y := 1100.0
	var col := Color.WHITE
	var amp := 100.0

	func _draw() -> void:
		var pts := PackedVector2Array()
		pts.append(Vector2(0, size.y))
		var n := 54
		for i in n + 1:
			var x := size.x * float(i) / float(n)
			var u := x / 1080.0 * TAU   # a whole number of periods across 1080 px: the row repeats seamlessly
			var y := base_y - amp * (0.5 + 0.35 * sin(u + float(seed_v)) + 0.15 * sin(u * 2.0 + float(seed_v) * 2.0))
			pts.append(Vector2(x, y))
		pts.append(Vector2(size.x, size.y))
		draw_colored_polygon(pts, col)

## A balloon of the catalogue, drawn once; the screen moves it.
class _BalloonSprite extends Control:
	var env := 0
	var basket := 0
	var pas := 0
	var k := 0.6

	func _draw() -> void:
		draw_set_transform(Vector2(size.x * 0.5, 60.0 * k * 1.9), 0.0, Vector2(k * 1.9, k * 1.9))
		BalloonArt.shared().draw_body(self, env, basket, pas, 4.0)   # (flat and still: no burner flame in the picture)

## A soft cloud, drawn once.
class _Cloud extends Control:
	var k := 0.8

	func _draw() -> void:
		var base := Vector2(size.x * 0.5, size.y * 0.7)
		for p in [[-70.0, 0.0, 50.0], [-20.0, -26.0, 62.0], [40.0, -10.0, 54.0], [92.0, 6.0, 40.0]]:
			draw_circle(base + Vector2(p[0], p[1]) * k, p[2] * k, Color(1, 1, 1, 0.7))
		draw_rect(Rect2(base + Vector2(-110.0, 0.0) * k, Vector2(250.0, 42.0) * k), Color(1, 1, 1, 0.7))
