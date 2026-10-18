class_name BalloonArt
extends RefCounted
## Draws a whole balloon (envelope, basket, passenger, burner flame) from pre-built polygons onto any
## CanvasItem: the game balloon, the map marker, the shop preview. Design units: the envelope centre is the
## origin, the basket sits at y 60..84. The caller sets the transform; `w` is the outline width in design units.
## One shared instance; nothing is allocated while drawing.

const HEAD := Vector2(8.0, 54.0)     # where a passenger's head peeks out of the basket

static var _shared: BalloonArt

static func shared() -> BalloonArt:
	if _shared == null:
		_shared = BalloonArt.new()
	return _shared

var _round: Array
var _pat: Array = []                 # per pattern: list of [poly, closed outline, colour slot 0-2]
var _badge: Array
var _cat_head: Array
var _cat_ear_l: Array
var _cat_ear_r: Array
var _bun: Array
var _sausage: Array
var _fish_body: Array
var _fish_tail: Array
var _fish_fin: Array
var _baskets: Array = []             # per basket: list of [poly, closed outline, colour]
var _flame := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _flame_in := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _zig := PackedVector2Array()
var _s3 := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _s4 := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

static func _pair(points: Array) -> Array:
	var poly := PackedVector2Array(points)
	var closed := poly.duplicate()
	closed.append(poly[0])
	return [poly, closed]

# ---- outline of the round envelope (design units) ----
static func _top_y(x: float) -> float:
	return -6.0 - 50.0 * sqrt(maxf(1.0 - pow(x / 42.0, 2.0), 0.0))

static func _bottom_y(x: float) -> float:
	var ax := absf(x)
	if ax <= 16.0:
		return 44.0
	if ax <= 34.0:
		return lerpf(44.0, 22.0, (ax - 16.0) / 18.0)
	return lerpf(22.0, -6.0, (ax - 34.0) / 8.0)

static func _half_width(y: float) -> float:
	if y <= -6.0:
		return 42.0 * sqrt(maxf(1.0 - pow((y + 6.0) / 50.0, 2.0), 0.0))
	if y <= 22.0:
		return lerpf(42.0, 34.0, (y + 6.0) / 28.0)
	return lerpf(34.0, 16.0, (y - 22.0) / 22.0)

## A vertical slice of the envelope between x0 and x1.
static func _gore(x0: float, x1: float) -> Array:
	var pts: Array = []
	for i in 5:
		var x := lerpf(x0, x1, float(i) / 4.0)
		pts.append(Vector2(x, _top_y(x)))
	for i in 5:
		var x := lerpf(x1, x0, float(i) / 4.0)
		pts.append(Vector2(x, _bottom_y(x)))
	return pts

## A horizontal band of the envelope between y0 and y1 (y0 < y1).
static func _band(y0: float, y1: float) -> Array:
	var pts: Array = []
	for i in 5:
		var y := lerpf(y0, y1, float(i) / 4.0)
		pts.append(Vector2(-_half_width(y), y))
	for i in 5:
		var y := lerpf(y1, y0, float(i) / 4.0)
		pts.append(Vector2(_half_width(y), y))
	return pts

func _add(list: Array, pts: Array, slot: int) -> void:
	var p := _pair(pts)
	list.append([p[0], p[1], slot])

func _init() -> void:
	var env := PackedVector2Array()
	for deg in range(180, 361, 30):
		var a := deg_to_rad(float(deg))
		env.append(Vector2(cos(a) * 42.0, -6.0 + sin(a) * 50.0))
	env.append_array(PackedVector2Array([Vector2(34, 22), Vector2(16, 44), Vector2(-16, 44), Vector2(-34, 22)]))
	_round = _pair(env)
	# Patterns (slot 0 = the base colour is drawn first by the caller, these go on top in slots 1 and 2).
	for p in 7:
		_pat.append([])
	# 0: one centre stripe
	_add(_pat[0], _gore(-15.0, 15.0), 1)
	# 1: solid with a band at the bottom
	_add(_pat[1], _band(14.0, 44.0), 1)
	# 2: gores, alternating
	_add(_pat[2], _gore(-42.0, -25.2), 1)
	_add(_pat[2], _gore(-8.4, 8.4), 1)
	_add(_pat[2], _gore(25.2, 42.0), 1)
	# 3: horizontal bands
	_add(_pat[3], _band(-34.0, -18.0), 1)
	_add(_pat[3], _band(-2.0, 14.0), 1)
	_add(_pat[3], _band(30.0, 44.0), 2)
	# 4: diamonds
	for d in [Vector2(0, -34), Vector2(-20, -8), Vector2(20, -8), Vector2(0, 18)]:
		_add(_pat[4], [d + Vector2(0, -14), d + Vector2(14, 0), d + Vector2(0, 14), d + Vector2(-14, 0)], 1)
	_add(_pat[4], [Vector2(0, 8) + Vector2(0, -4), Vector2(10, 18), Vector2(0, 30), Vector2(-10, 18)], 2)
	# 5: dots (octagons)
	for d in [Vector2(-18, -28), Vector2(18, -28), Vector2(0, -12), Vector2(-24, 4), Vector2(24, 4), Vector2(0, 14), Vector2(-10, 32), Vector2(10, 32)]:
		var o: Array = []
		for i in 8:
			var a := TAU * (float(i) + 0.5) / 8.0
			o.append(d + Vector2(cos(a), sin(a)) * 6.5)
		_add(_pat[5], o, 1)
	# 6: a star badge on the front is drawn by the caller; two small side gores here
	_add(_pat[6], _gore(-42.0, -30.0), 1)
	_add(_pat[6], _gore(30.0, 42.0), 1)
	var star := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + TAU * float(i) / 10.0
		star.append(Vector2(0, -14) + Vector2(cos(a), sin(a)) * (20.0 if i % 2 == 0 else 9.0))
	_badge = _pair(star)
	# Novelty shapes.
	_cat_head = _pair([Vector2(-44, -8), Vector2(-36, -34), Vector2(-14, -44), Vector2(14, -44), Vector2(36, -34), Vector2(44, -8), Vector2(36, 22), Vector2(16, 44), Vector2(-16, 44), Vector2(-36, 22)])
	_cat_ear_l = _pair([Vector2(-42, -26), Vector2(-34, -64), Vector2(-10, -42)])
	_cat_ear_r = _pair([Vector2(42, -26), Vector2(34, -64), Vector2(10, -42)])
	_bun = _pair([Vector2(-14, -56), Vector2(14, -56), Vector2(34, -46), Vector2(42, -20), Vector2(42, 16), Vector2(34, 38), Vector2(16, 46), Vector2(-16, 46), Vector2(-34, 38), Vector2(-42, 16), Vector2(-42, -20), Vector2(-34, -46)])
	_sausage = _pair([Vector2(-9, -62), Vector2(9, -62), Vector2(20, -52), Vector2(24, -20), Vector2(24, 16), Vector2(18, 36), Vector2(9, 40), Vector2(-9, 40), Vector2(-18, 36), Vector2(-24, 16), Vector2(-24, -20), Vector2(-20, -52)])
	_zig.resize(9)
	_fish_body = _pair([Vector2(0, -58), Vector2(22, -46), Vector2(40, -16), Vector2(38, 14), Vector2(18, 36), Vector2(-18, 36), Vector2(-38, 14), Vector2(-40, -16), Vector2(-22, -46)])
	_fish_tail = _pair([Vector2(-16, 32), Vector2(0, 24), Vector2(16, 32), Vector2(32, 52), Vector2(0, 42), Vector2(-32, 52)])
	_fish_fin = _pair([Vector2(34, -6), Vector2(58, 6), Vector2(36, 22)])
	# Baskets: parts of [poly, outline, colour]. All fit x -16..16, y 58..86.
	for i in 6:
		_baskets.append([])
	_bk(0, [Vector2(-15, 60), Vector2(15, 60), Vector2(12, 84), Vector2(-12, 84)], Color(0.62, 0.4, 0.2))
	_bk(1, [Vector2(-15, 60), Vector2(15, 60), Vector2(15, 84), Vector2(-15, 84)], Color(0.55, 0.57, 0.62))
	_bk(2, [Vector2(-16, 60), Vector2(16, 60), Vector2(11, 84), Vector2(-11, 84)], Color(0.7, 0.72, 0.78))
	_bk(3, [Vector2(-16, 62), Vector2(16, 62), Vector2(12, 82), Vector2(4, 86), Vector2(-4, 86), Vector2(-12, 82)], Color(0.95, 0.95, 1.0))
	_bk(4, [Vector2(-12, 60), Vector2(12, 60), Vector2(16, 72), Vector2(12, 86), Vector2(-12, 86), Vector2(-16, 72)], Color(0.6, 0.38, 0.2))
	_bk(5, [Vector2(-15, 68), Vector2(15, 68), Vector2(15, 86), Vector2(-15, 86)], Color(0.85, 0.6, 0.35))
	_bk(5, [Vector2(-18, 68), Vector2(0, 54), Vector2(18, 68)], Color(0.7, 0.22, 0.2))

func _bk(i: int, pts: Array, col: Color) -> void:
	var p := _pair(pts)
	_baskets[i].append([p[0], p[1], col])

## Filled triangle / quad through scratch arrays (nothing is allocated per draw).
func _p3(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	_s3[0] = a
	_s3[1] = b
	_s3[2] = c
	ci.draw_colored_polygon(_s3, col)

func _p4(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	_s4[0] = a
	_s4[1] = b
	_s4[2] = c
	_s4[3] = d
	ci.draw_colored_polygon(_s4, col)

func _fill(ci: CanvasItem, pair: Array, fill: Color, w: float) -> void:
	ci.draw_colored_polygon(pair[0], fill)
	ci.draw_polyline(pair[1], Color.BLACK, w)

## Draw the balloon. env / basket / pas: catalogue indices; heat: 0..1 burner heat; t: time for the flame flicker.
func draw(ci: CanvasItem, env: int, basket: int, pas: int, heat: float, t: float, w: float) -> void:
	var c1: Color = Cosmetics.ENV_C1[env]
	var c2: Color = Cosmetics.ENV_C2[env]
	var c3: Color = Cosmetics.ENV_C3[env]
	match int(Cosmetics.ENV_SHAPE[env]):
		0:
			var pat: int = Cosmetics.ENV_PATTERN[env]
			ci.draw_colored_polygon(_round[0], c1)
			for part in _pat[pat]:
				ci.draw_colored_polygon(part[0], c2 if part[2] == 1 else c3)
				ci.draw_polyline(part[1], Color.BLACK, w * 0.6)
			if pat == 6:
				ci.draw_colored_polygon(_badge[0], c2)
				ci.draw_polyline(_badge[1], Color.BLACK, w * 0.6)
			ci.draw_polyline(_round[1], Color.BLACK, w)
		1:   # cat head: ears, face, whiskers
			_fill(ci, _cat_ear_l, c1, w)
			_fill(ci, _cat_ear_r, c1, w)
			_fill(ci, _cat_head, c1, w)
			_p3(ci, Vector2(-34, -26), Vector2(-26, -42), Vector2(-14, -28), c2)   # stripe marks
			_p3(ci, Vector2(34, -26), Vector2(26, -42), Vector2(14, -28), c2)
			ci.draw_circle(Vector2(-17, -8), 9.0, Color.WHITE)
			ci.draw_circle(Vector2(17, -8), 9.0, Color.WHITE)
			ci.draw_circle(Vector2(-17, -7), 4.5, Color.BLACK)
			ci.draw_circle(Vector2(17, -7), 4.5, Color.BLACK)
			_p3(ci, Vector2(-6, 10), Vector2(6, 10), Vector2(0, 18), c3)
			ci.draw_line(Vector2(0, 18), Vector2(0, 24), Color.BLACK, w * 0.6)
			ci.draw_line(Vector2(0, 24), Vector2(-8, 28), Color.BLACK, w * 0.6)
			ci.draw_line(Vector2(0, 24), Vector2(8, 28), Color.BLACK, w * 0.6)
			for sy in [8.0, 16.0]:
				ci.draw_line(Vector2(-22, sy), Vector2(-46, sy - 4.0 + (sy - 12.0)), Color.BLACK, w * 0.5)
				ci.draw_line(Vector2(22, sy), Vector2(46, sy - 4.0 + (sy - 12.0)), Color.BLACK, w * 0.5)
		2:   # hot dog: bun, sausage, mustard
			_fill(ci, _bun, c1, w)
			_fill(ci, _sausage, c2, w)
			for i in 9:
				_zig[i] = Vector2(-9.0 if i % 2 == 0 else 9.0, -52.0 + float(i) * 11.0)
			ci.draw_polyline(_zig, c3, w * 1.4)
		3:   # fish: body, scales, tail, fin, eye
			_fill(ci, _fish_tail, c2, w)
			_fill(ci, _fish_body, c1, w)
			_fill(ci, _fish_fin, c2, w)
			for sy in [-26.0, -8.0, 10.0]:
				ci.draw_arc(Vector2(0, sy + 14.0), 14.0, PI * 1.15, PI * 1.85, 8, Color(1, 1, 1, 0.7), w * 0.6)
			ci.draw_arc(Vector2(8, -22), 22.0, PI * 0.1, PI * 0.5, 8, Color.BLACK, w * 0.6)
			ci.draw_circle(Vector2(18, -34), 7.0, Color.WHITE)
			ci.draw_circle(Vector2(19, -34), 3.5, Color.BLACK)
	# Ropes, burner and flame.
	ci.draw_line(Vector2(-16, 44), Vector2(-12, 60), Color.BLACK, w)
	ci.draw_line(Vector2(16, 44), Vector2(12, 60), Color.BLACK, w)
	ci.draw_rect(Rect2(-4, 52, 8, 6), Color(0.45, 0.47, 0.52))
	ci.draw_rect(Rect2(-4, 52, 8, 6), Color.BLACK, false, w * 0.6)
	if heat > 0.04:
		var f := 0.85 + 0.15 * sin(t * 45.0)
		var flame_len := (6.0 + 24.0 * heat) * f
		_flame[0] = Vector2(-5, 52)
		_flame[1] = Vector2(5, 52)
		_flame[2] = Vector2(0, 52.0 - flame_len)
		ci.draw_colored_polygon(_flame, Color(1.0, 0.55, 0.1))
		_flame_in[0] = Vector2(-2.5, 52)
		_flame_in[1] = Vector2(2.5, 52)
		_flame_in[2] = Vector2(0, 52.0 - flame_len * 0.55)
		ci.draw_colored_polygon(_flame_in, Color(1.0, 0.92, 0.35))
	if pas > 0:   # the passenger peeks over the rim, behind the basket's front
		_passenger(ci, pas, w)
	for part in _baskets[basket]:
		ci.draw_colored_polygon(part[0], part[2])
		ci.draw_polyline(part[1], Color.BLACK, w)
	_basket_detail(ci, basket, w)

func _basket_detail(ci: CanvasItem, basket: int, w: float) -> void:
	match basket:
		0:   # wicker weave
			ci.draw_line(Vector2(-13, 68), Vector2(13, 68), Color.BLACK, w * 0.4)
			ci.draw_line(Vector2(-12, 76), Vector2(12, 76), Color.BLACK, w * 0.4)
		1:   # crate planks and an X
			ci.draw_line(Vector2(-15, 72), Vector2(15, 72), Color.BLACK, w * 0.5)
			ci.draw_line(Vector2(-15, 60), Vector2(15, 84), Color.BLACK, w * 0.4)
		2:   # rim and handle
			ci.draw_line(Vector2(-16, 64), Vector2(16, 64), Color.BLACK, w * 0.7)
			ci.draw_arc(Vector2(0, 60), 14.0, PI, TAU, 8, Color.BLACK, w * 0.5)
		3:   # portholes and a stripe
			ci.draw_circle(Vector2(-7, 71), 3.5, Color(0.4, 0.7, 1.0))
			ci.draw_circle(Vector2(7, 71), 3.5, Color(0.4, 0.7, 1.0))
			ci.draw_line(Vector2(-15, 64), Vector2(15, 64), Color(0.9, 0.2, 0.2), w * 0.8)
		4:   # barrel hoops
			ci.draw_line(Vector2(-13, 66), Vector2(13, 66), Color(0.3, 0.3, 0.35), w * 0.8)
			ci.draw_line(Vector2(-15, 78), Vector2(15, 78), Color(0.3, 0.3, 0.35), w * 0.8)
		5:   # cabin window and door
			ci.draw_rect(Rect2(-10, 72, 7, 7), Color(0.75, 0.92, 1.0))
			ci.draw_rect(Rect2(3, 74, 8, 12), Color(0.45, 0.28, 0.15))

func _passenger(ci: CanvasItem, pas: int, w: float) -> void:
	var c := HEAD
	match pas:
		1:   # cat
			_p3(ci, c + Vector2(-8, -4), c + Vector2(-6, -15), c + Vector2(-1, -7), Color(0.6, 0.6, 0.65))
			_p3(ci, c + Vector2(8, -4), c + Vector2(6, -15), c + Vector2(1, -7), Color(0.6, 0.6, 0.65))
			ci.draw_circle(c, 9.0, Color(0.6, 0.6, 0.65))
			ci.draw_circle(c + Vector2(-3, -1), 1.6, Color.BLACK)
			ci.draw_circle(c + Vector2(3, -1), 1.6, Color.BLACK)
			ci.draw_line(c + Vector2(-4, 3), c + Vector2(-12, 2), Color.BLACK, w * 0.3)
			ci.draw_line(c + Vector2(4, 3), c + Vector2(12, 2), Color.BLACK, w * 0.3)
		2:   # dog: floppy ears
			ci.draw_circle(c + Vector2(-9, 1), 4.5, Color(0.45, 0.28, 0.15))
			ci.draw_circle(c + Vector2(9, 1), 4.5, Color(0.45, 0.28, 0.15))
			ci.draw_circle(c, 9.0, Color(0.78, 0.55, 0.3))
			ci.draw_circle(c + Vector2(-3, -2), 1.6, Color.BLACK)
			ci.draw_circle(c + Vector2(3, -2), 1.6, Color.BLACK)
			ci.draw_circle(c + Vector2(0, 3), 2.4, Color.BLACK)
		3:   # fox
			_p3(ci, c + Vector2(-9, -2), c + Vector2(-6, -17), c + Vector2(-1, -7), Color(0.95, 0.5, 0.15))
			_p3(ci, c + Vector2(9, -2), c + Vector2(6, -17), c + Vector2(1, -7), Color(0.95, 0.5, 0.15))
			ci.draw_circle(c, 9.0, Color(0.95, 0.5, 0.15))
			_p4(ci, c + Vector2(-9, 3), c + Vector2(0, 9), c + Vector2(9, 3), c + Vector2(0, 0), Color.WHITE)
			ci.draw_circle(c + Vector2(-3, -2), 1.5, Color.BLACK)
			ci.draw_circle(c + Vector2(3, -2), 1.5, Color.BLACK)
			ci.draw_circle(c + Vector2(0, 4), 1.8, Color.BLACK)
		4:   # owl
			_p3(ci, c + Vector2(-8, -5), c + Vector2(-7, -14), c + Vector2(-2, -8), Color(0.5, 0.35, 0.2))
			_p3(ci, c + Vector2(8, -5), c + Vector2(7, -14), c + Vector2(2, -8), Color(0.5, 0.35, 0.2))
			ci.draw_circle(c, 9.0, Color(0.5, 0.35, 0.2))
			ci.draw_circle(c + Vector2(-4, -1), 4.2, Color.WHITE)
			ci.draw_circle(c + Vector2(4, -1), 4.2, Color.WHITE)
			ci.draw_circle(c + Vector2(-4, -1), 1.8, Color.BLACK)
			ci.draw_circle(c + Vector2(4, -1), 1.8, Color.BLACK)
			_p3(ci, c + Vector2(-2, 3), c + Vector2(2, 3), c + Vector2(0, 7), Color(1.0, 0.8, 0.2))
		5:   # raccoon: ears and a mask
			ci.draw_circle(c + Vector2(-7, -7), 3.5, Color(0.55, 0.55, 0.6))
			ci.draw_circle(c + Vector2(7, -7), 3.5, Color(0.55, 0.55, 0.6))
			ci.draw_circle(c, 9.0, Color(0.7, 0.7, 0.75))
			ci.draw_rect(Rect2(c + Vector2(-9, -4), Vector2(18, 5)), Color(0.15, 0.15, 0.2))
			ci.draw_circle(c + Vector2(-3.5, -1.5), 1.4, Color.WHITE)
			ci.draw_circle(c + Vector2(3.5, -1.5), 1.4, Color.WHITE)
			ci.draw_circle(c + Vector2(0, 4), 1.8, Color.BLACK)
	ci.draw_arc(c, 9.0, 0.0, TAU, 14, Color.BLACK, w * 0.5)
