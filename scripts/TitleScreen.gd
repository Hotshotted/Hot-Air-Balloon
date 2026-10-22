class_name TitleScreen
extends Control
## The living title screen: balloons drifting over a valley at dawn. A gradient sky with a rising sun, three parallax rows of
## hills that creep past, clouds, and a handful of balloons (each a different cosmetic) bobbing upward. Everything is drawn
## ONCE; `_process` only moves the pieces (their `position`) while the screen is visible. PLAY is the one primary button.

signal play_pressed

const SKY_TOP := Color("1b2a5e")
const SKY_MID := Color("c4627f")
const SKY_LOW := Color("ffb36b")
const SKY_HORIZON := Color("ffe2a0")
const HILL_COLS := [Color("5b4a8c"), Color("3f5f8c"), Color("2f7a5c")]
const HILL_Y := [1040.0, 1180.0, 1340.0]
const HILL_SPEED := [5.0, 12.0, 24.0]
const WIDE := 2160.0

var play_btn: Button
var logo_a: Label
var logo_b: Label
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
	for i in 3:
		var h := _HillRow.new()
		h.size = Vector2(WIDE, Lanes.H)
		h.seed_v = 11 + i * 7
		h.base_y = HILL_Y[i]
		h.col = HILL_COLS[i]
		h.amp = 120.0 - 22.0 * float(i)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(h)
		_hills.append(h)
	# balloons between the far and the near hills (so the near hills pass in front of them)
	var picks := [[0, 0, 0, 0.55, 300.0, 880.0], [3, 1, 0, 0.8, 760.0, 700.0], [6, 2, 0, 0.62, 520.0, 560.0], [9, 3, 1, 0.45, 880.0, 980.0], [1, 4, 2, 0.7, 150.0, 800.0]]
	for p in picks:
		var bs := _BalloonSprite.new()
		bs.env = p[0]
		bs.basket = p[1]
		bs.pas = p[2]
		bs.k = p[3]
		bs.size = Vector2(240, 300)
		bs.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bs.position = Vector2(p[4], p[5])
		add_child(bs)
		move_child(bs, 2 + _balloons.size())
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
	logo_a = Ui.label("WIND", 190, HORIZONTAL_ALIGNMENT_CENTER, Vector2(0, 230), Vector2(Lanes.W, 220))
	logo_b = Ui.label("LAYERS", 190, HORIZONTAL_ALIGNMENT_CENTER, Vector2(0, 410), Vector2(Lanes.W, 220))
	logo_b.add_theme_color_override("font_color", Style.ACCENT)
	add_child(logo_a)
	add_child(logo_b)
	play_btn = Ui.button("PLAY", 96, Vector2(190, 1500), Vector2(700, 190), Color(0.95, 0.5, 0.15), "play")
	play_btn.pressed.connect(func(): play_pressed.emit())
	add_child(play_btn)
	Ui.fit_safe(self)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	for i in 3:
		_hills[i].position.x = -fposmod(_t * HILL_SPEED[i], 1080.0)
	for i in _balloons.size():
		var up := fposmod(_t * _b_speed[i] * 0.4 + _b_phase[i] * 90.0, 520.0)
		_balloons[i].position = Vector2(_b_base[i].x + sin(_t * 0.35 + _b_phase[i]) * 40.0 + _t * 0.0, _b_base[i].y - up + 120.0 + sin(_t * 0.9 + _b_phase[i]) * 8.0)
		_balloons[i].modulate.a = clampf(minf(up / 90.0, (520.0 - up) / 90.0), 0.0, 1.0)
	for i in _clouds.size():
		var c := _clouds[i]
		c.position.x += _cloud_speed[i] * delta
		if c.position.x > Lanes.W + 40.0:
			c.position.x = -340.0
	play_btn.scale = Vector2.ONE * (1.0 + 0.012 * sin(_t * 3.0)) if not play_btn.is_pressed() else play_btn.scale

func _draw() -> void:
	# sky: horizontal bands from the top to the horizon (drawn once)
	var bands := 48
	for i in bands:
		var u := float(i) / float(bands - 1)
		var col: Color
		if u < 0.5:
			col = SKY_TOP.lerp(SKY_MID, u * 2.0)
		elif u < 0.85:
			col = SKY_MID.lerp(SKY_LOW, (u - 0.5) / 0.35)
		else:
			col = SKY_LOW.lerp(SKY_HORIZON, (u - 0.85) / 0.15)
		draw_rect(Rect2(0, 1100.0 * float(i) / float(bands), Lanes.W, 1100.0 / float(bands) + 1.0), col)
	draw_rect(Rect2(0, 1100, Lanes.W, Lanes.H - 1100.0), Color("2f7a5c"))
	# the rising sun with soft halos
	var sun := Vector2(760, 1010)
	for k in 4:
		draw_circle(sun, 330.0 - 70.0 * float(k), Color(1.0, 0.85, 0.5, 0.10 + 0.04 * float(k)))
	draw_circle(sun, 120.0, Color("fff0b8"))

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
		var line := pts.slice(1, pts.size() - 1)
		draw_polyline(line, Color(Style.INK, 0.8), 5.0, true)

## A balloon of the catalogue, drawn once; the screen moves it.
class _BalloonSprite extends Control:
	var env := 0
	var basket := 0
	var pas := 0
	var k := 0.6

	func _draw() -> void:
		draw_set_transform(Vector2(size.x * 0.5, 130.0 * k * 1.9), 0.0, Vector2(k * 1.9, k * 1.9))
		BalloonArt.shared().draw(self, env, basket, pas, 0.7, 0.0, 4.0 / (k * 1.9))

## A soft cloud, drawn once.
class _Cloud extends Control:
	var k := 0.8

	func _draw() -> void:
		var base := Vector2(size.x * 0.5, size.y * 0.7)
		for p in [[-70.0, 0.0, 50.0], [-20.0, -26.0, 62.0], [40.0, -10.0, 54.0], [92.0, 6.0, 40.0]]:
			draw_circle(base + Vector2(p[0], p[1]) * k, p[2] * k, Color(1, 1, 1, 0.7))
		draw_rect(Rect2(base + Vector2(-110.0, 0.0) * k, Vector2(250.0, 42.0) * k), Color(1, 1, 1, 0.7))
