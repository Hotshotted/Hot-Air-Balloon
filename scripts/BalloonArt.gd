class_name BalloonArt
extends RefCounted
## "Storybook Sky" balloon: flat, soft-shaded shapes ported from the design canvas (100 x 140 symbol, here centred on the
## envelope: the origin is the envelope's middle, the neck is at y 48, the basket sits at y 64..84). Drawn from cached
## polygons onto any CanvasItem: the game balloon, the map marker, the shop preview. No outlines; depth comes from a
## shaded left side, a white centre gore and a highlight. The caller sets the transform. `w` is kept for old call sites.
## One shared instance; nothing is allocated while drawing.

const O := Vector2(-50.0, -50.0)        # symbol -> centred units
const HEAD := Vector2(4.0, 59.0)        # where a passenger's head peeks over the basket rim
const ENV := "M50 4C78 4 94 24 94 50C94 74 74 88 62 98L38 98C26 88 6 74 6 50C6 24 22 4 50 4Z"
const GORE := "M50 4C62 18 66 60 57 98L43 98C34 60 38 18 50 4Z"
const SHADE := "M50 4C30 10 20 40 27 72L38 98C26 88 6 74 6 50C6 24 22 4 50 4Z"
const BANDS := "M8 38H92V50H8Z M14 70H86V80H14Z"
const INK := Color("0a1020")
const ROPE := Color("6b4423")
const WEAVE := Color("8a5a2e")

static var _shared: BalloonArt

static func shared() -> BalloonArt:
	if _shared == null:
		_shared = BalloonArt.new()
	return _shared

var _env_poly: PackedVector2Array
var _side_gores: Array = []            # clipped side gores (pattern 2)
var _flame := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _flame_in := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _highlight: PackedVector2Array
var _bun: PackedVector2Array
var _sausage: PackedVector2Array
var _zig := PackedVector2Array()

func _init() -> void:
	_env_poly = SvgArt.path(ENV, O)[0]
	for dx in [-24.0, 24.0]:
		var g: PackedVector2Array = SvgArt.path(GORE, O + Vector2(dx, 0.0))[0]
		for part in Geometry2D.intersect_polygons(g, _env_poly):
			_side_gores.append(part)
	_highlight = SvgArt.ellipse(Vector2(72, 30) + O, 7.0, 14.0, deg_to_rad(20.0), 14)
	_bun = SvgArt.path("M50 6C80 6 92 30 92 54C92 78 76 90 62 98L38 98C24 90 8 78 8 54C8 30 20 6 50 6Z", O)[0]
	_sausage = SvgArt.path("M50 14C68 14 76 32 76 54C76 74 66 88 56 94L44 94C34 88 24 74 24 54C24 32 32 14 50 14Z", O)[0]
	_zig.resize(9)

## The envelope with its burner (the game balloon's leaning envelope node draws exactly this).
func draw_envelope(ci: CanvasItem, env: int, _w: float) -> void:
	var c1: Color = Cosmetics.ENV_C1[env]
	var c2: Color = Cosmetics.ENV_C2[env]
	match int(Cosmetics.ENV_SHAPE[env]):
		0:
			var pat: int = Cosmetics.ENV_PATTERN[env]
			SvgArt.fill(ci, ENV, Color.WHITE if pat == 1 else c1, O)
			match pat:
				0:
					SvgArt.fill(ci, GORE, Color(1, 1, 1, 0.92), O)
				1:
					SvgArt.fill(ci, BANDS, c1, O)
				2:
					for g in _side_gores:
						ci.draw_colored_polygon(g, c2)
					SvgArt.fill(ci, GORE, Color(1, 1, 1, 0.92), O)
				3:
					SvgArt.fill(ci, BANDS, c2, O)
					SvgArt.fill(ci, GORE, Color(1, 1, 1, 0.92), O)
			SvgArt.fill(ci, SHADE, Color(INK, 0.14), O)
			ci.draw_colored_polygon(_highlight, Color(1, 1, 1, 0.35))
		1:   # Whiskers: a cat head
			SvgArt.fill(ci, "M14 36L10 6L36 22Z M86 36L90 6L64 22Z", c1, O)
			SvgArt.fill(ci, "M18 30L16 14L30 24Z M82 30L84 14L70 24Z", Color("ffb3c1"), O)
			SvgArt.fill(ci, "M50 14C78 14 94 32 94 56C94 76 76 90 62 98L38 98C24 90 6 76 6 56C6 32 22 14 50 14Z", c1, O)
			SvgArt.fill(ci, "M50 14C34 18 24 34 26 60L38 98C24 90 6 76 6 56C6 32 22 14 50 14Z", Color(INK, 0.14), O)
			ci.draw_circle(Vector2(34, 52) + O, 6.0, INK)
			ci.draw_circle(Vector2(66, 52) + O, 6.0, INK)
			ci.draw_circle(Vector2(32, 50) + O, 2.0, Color.WHITE)
			ci.draw_circle(Vector2(64, 50) + O, 2.0, Color.WHITE)
			SvgArt.fill(ci, "M46 64L54 64L50 70Z", Color("ff8aa0"), O)
			SvgArt.stroke(ci, "M50 70C46 76 40 74 38 72", INK, 2.0, O)
			SvgArt.stroke(ci, "M50 70C54 76 60 74 62 72", INK, 2.0, O)
		2:   # hot dog
			ci.draw_colored_polygon(_bun, c1)
			ci.draw_colored_polygon(_sausage, c2)
			SvgArt.fill(ci, "M50 6C20 6 8 30 8 54C8 78 24 90 38 98L44 98C30 88 22 70 22 54C22 30 34 12 50 6Z", Color(INK, 0.1), O)
			for i in 9:
				_zig[i] = Vector2(-7.0 if i % 2 == 0 else 7.0, -34.0 + float(i) * 8.0)
			ci.draw_polyline(_zig, Cosmetics.ENV_C3[env], 3.0, true)
			ci.draw_colored_polygon(_highlight, Color(1, 1, 1, 0.3))
		3:   # Big Fish
			SvgArt.fill(ci, "M80 50L98 30L98 74Z", c1, O)
			ci.draw_colored_polygon(SvgArt.ellipse(Vector2(46, 52) + O, 42.0, 34.0, 0.0, 28), c1)
			SvgArt.fill(ci, "M38 86L62 86L62 98L38 98Z", c1, O)
			ci.draw_colored_polygon(SvgArt.ellipse(Vector2(32, 60) + O, 26.0, 22.0, 0.0, 20), Color(INK, 0.1))
			SvgArt.stroke(ci, "M30 30C40 44 40 62 30 76", Color(1, 1, 1, 0.5), 4.0, O)
			ci.draw_circle(Vector2(20, 46) + O, 6.0, Color.WHITE)
			ci.draw_circle(Vector2(19, 46) + O, 3.0, INK)
	# the burner hanging at the neck
	ci.draw_colored_polygon(SvgArt.rrect(-13.0, 46.0, 26.0, 6.0, 3.0), Color(INK, 0.55))

## The ropes, as static lines (the map marker and the shop; the game balloon draws moving ropes instead).
func draw_ropes_static(ci: CanvasItem, _w: float) -> void:
	ci.draw_line(Vector2(-10, 52), Vector2(-9, 68), ROPE, 1.6, true)
	ci.draw_line(Vector2(10, 52), Vector2(9, 68), ROPE, 1.6, true)

## The basket, with a passenger if `pas` > 0 (static; the game balloon animates its passenger in its own node).
func draw_basket(ci: CanvasItem, basket: int, pas: int, w: float) -> void:
	if pas > 0:
		_passenger(ci, pas, Vector2.ZERO, 0.0, 0.0)
	match basket:
		0:   # wicker
			_body(ci, Color("c4844a"), Color("8a5a2e"))
			ci.draw_line(Vector2(-13, 72), Vector2(13, 72), WEAVE, 1.2, true)
			ci.draw_line(Vector2(-13, 78), Vector2(13, 78), WEAVE, 1.2, true)
		1:   # crate
			_body(ci, Color("b98f55"), Color("7d5c2e"))
			for x in [-6.0, 0.0, 6.0]:
				ci.draw_line(Vector2(x, 68), Vector2(x, 84), Color(INK, 0.3), 1.2, true)
			ci.draw_line(Vector2(-13, 68), Vector2(13, 84), Color(INK, 0.3), 1.2, true)
		2:   # bucket
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-15, 66), Vector2(15, 66), Vector2(11, 84), Vector2(-11, 84)]), Color("9aa6bd"))
			ci.draw_colored_polygon(SvgArt.rrect(-16.0, 64.0, 32.0, 4.0, 2.0), Color("66728a"))
			ci.draw_line(Vector2(-11, 74), Vector2(11, 74), Color(INK, 0.25), 1.2, true)
			ci.draw_arc(Vector2(0, 66), 14.0, PI, TAU, 10, Color("66728a"), 1.6, true)
		3:   # gondola
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-15, 66), Vector2(15, 66), Vector2(12, 80), Vector2(5, 85), Vector2(-5, 85), Vector2(-12, 80)]), Color("f4f1ea"))
			ci.draw_colored_polygon(SvgArt.rrect(-16.0, 64.0, 32.0, 4.0, 2.0), Color("ff5c4d"))
			ci.draw_circle(Vector2(-6, 74), 3.2, Color("6fb4ff"))
			ci.draw_circle(Vector2(6, 74), 3.2, Color("6fb4ff"))
		4:   # barrel
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-11, 65), Vector2(11, 65), Vector2(15, 74), Vector2(11, 84), Vector2(-11, 84), Vector2(-15, 74)]), Color("a5703c"))
			ci.draw_colored_polygon(SvgArt.rrect(-13.0, 64.0, 26.0, 4.0, 2.0), Color("6b4423"))
			for y in [69.0, 79.0]:
				ci.draw_line(Vector2(-14, y), Vector2(14, y), Color("5a5f6e"), 1.8, true)
		5:   # cabin
			ci.draw_colored_polygon(SvgArt.rrect(-14.0, 68.0, 28.0, 16.0, 3.0), Color("d9955a"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-17, 69), Vector2(0, 57), Vector2(17, 69)]), Color("d94f45"))
			ci.draw_colored_polygon(SvgArt.rrect(-10.0, 72.0, 7.0, 7.0, 1.5), Color("bfe3ff"))
			ci.draw_colored_polygon(SvgArt.rrect(3.0, 74.0, 8.0, 10.0, 1.5), Color("6b4423"))

func _body(ci: CanvasItem, col: Color, rim: Color) -> void:
	ci.draw_colored_polygon(SvgArt.rrect(-13.0, 66.0, 26.0, 18.0, 4.0), col)
	ci.draw_colored_polygon(SvgArt.rrect(-15.0, 64.0, 30.0, 4.0, 2.0), rim)

## The passenger alone (the game balloon's animated passenger node): `look` -1..1 turns the head, `cheer` 0..1 throws
## the paws up and bounces, `sad` 0..1 droops it (a crash).
func draw_passenger(ci: CanvasItem, pas: int, _w: float, look: float, cheer: float, sad: float) -> void:
	if pas > 0:
		_passenger(ci, pas, Vector2(look * 2.5, -cheer * 4.0 + sad * 4.0), cheer, sad)

## Draw the balloon WITHOUT its flame (env / basket / pas: catalogue indices): the map marker and the shop.
func draw_body(ci: CanvasItem, env: int, basket: int, pas: int, w: float) -> void:
	draw_envelope(ci, env, w)
	draw_ropes_static(ci, w)
	draw_basket(ci, basket, pas, w)

## The burner flame (power 0..1 = the burner output, t for the flicker, `sputter` 0..1 cuts it while it lights): a gold
## teardrop with a white core and a faint halo, growing upward from the burner at the neck.
func draw_flame(ci: CanvasItem, heat: float, t: float, sputter: float = 1.0) -> void:
	if heat > 0.04:
		var f := (0.88 + 0.12 * sin(t * 45.0) + 0.05 * sin(t * 97.0)) * sputter
		var len := (7.0 + 30.0 * heat) * f
		var wd := 3.6 + 3.6 * heat
		var by := 46.0
		ci.draw_circle(Vector2(0, by - len * 0.45), 9.0 + 14.0 * heat * f, Color(1.0, 0.8, 0.25, 0.2 * heat * f))
		_flame[0] = Vector2(-wd, by)
		_flame[1] = Vector2(wd, by)
		_flame[2] = Vector2(wd * 0.8, by - len * 0.45)
		_flame[3] = Vector2(sin(t * 31.0) * 1.8, by - len)
		_flame[4] = Vector2(-wd * 0.8, by - len * 0.45)
		ci.draw_colored_polygon(_flame, Color("ffc933"))
		_flame_in[0] = Vector2(-wd * 0.5, by)
		_flame_in[1] = Vector2(wd * 0.5, by)
		_flame_in[2] = Vector2(wd * 0.42, by - len * 0.3)
		_flame_in[3] = Vector2(0, by - len * 0.6)
		_flame_in[4] = Vector2(-wd * 0.42, by - len * 0.3)
		ci.draw_colored_polygon(_flame_in, Color.WHITE)

## The whole balloon: body and flame (the map marker, the shop).
func draw(ci: CanvasItem, env: int, basket: int, pas: int, heat: float, t: float, w: float) -> void:
	draw_body(ci, env, basket, pas, w)
	draw_flame(ci, heat, t)

func _head(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c, r, col)

func _passenger(ci: CanvasItem, pas: int, off: Vector2, cheer: float, sad: float) -> void:
	var c := HEAD + off
	var eye := Color(INK)
	match pas:
		1:   # cat
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -2), c + Vector2(-5, -11), c + Vector2(-1, -5)]), Color("9aa3b2"))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(6, -2), c + Vector2(5, -11), c + Vector2(1, -5)]), Color("9aa3b2"))
			_head(ci, c, 7.0, Color("b5bdca"))
			ci.draw_circle(c + Vector2(-2.5, -0.5), 1.2, eye)
			ci.draw_circle(c + Vector2(2.5, -0.5), 1.2, eye)
			ci.draw_line(c + Vector2(-3, 2.5), c + Vector2(-9, 2), eye, 0.6)
			ci.draw_line(c + Vector2(3, 2.5), c + Vector2(9, 2), eye, 0.6)
		2:   # dog
			ci.draw_circle(c + Vector2(-7, 1), 3.4, Color("7a4a26"))
			ci.draw_circle(c + Vector2(7, 1), 3.4, Color("7a4a26"))
			_head(ci, c, 7.0, Color("c88b4e"))
			ci.draw_circle(c + Vector2(-2.5, -1.5), 1.2, eye)
			ci.draw_circle(c + Vector2(2.5, -1.5), 1.2, eye)
			ci.draw_circle(c + Vector2(0, 2.5), 1.8, eye)
		3:   # fox
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -1), c + Vector2(-5, -13), c + Vector2(-1, -5)]), Color("f2701a"))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(7, -1), c + Vector2(5, -13), c + Vector2(1, -5)]), Color("f2701a"))
			_head(ci, c, 7.0, Color("f2701a"))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-7, 2), c + Vector2(0, 7.5), c + Vector2(7, 2), c + Vector2(0, 0)]), Color.WHITE)
			ci.draw_circle(c + Vector2(-2.5, -1.5), 1.1, eye)
			ci.draw_circle(c + Vector2(2.5, -1.5), 1.1, eye)
			ci.draw_circle(c + Vector2(0, 3.5), 1.3, eye)
		4:   # owl
			_head(ci, c, 7.0, Color("8a5e34"))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -4), c + Vector2(-6, -11), c + Vector2(-1.5, -6)]), Color("8a5e34"))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(6, -4), c + Vector2(6, -11), c + Vector2(1.5, -6)]), Color("8a5e34"))
			ci.draw_circle(c + Vector2(-3.2, -0.5), 3.3, Color.WHITE)
			ci.draw_circle(c + Vector2(3.2, -0.5), 3.3, Color.WHITE)
			ci.draw_circle(c + Vector2(-3.2, -0.5), 1.4, eye)
			ci.draw_circle(c + Vector2(3.2, -0.5), 1.4, eye)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-1.5, 2.5), c + Vector2(1.5, 2.5), c + Vector2(0, 5.5)]), Color("ffc933"))
		5:   # raccoon
			ci.draw_circle(c + Vector2(-5.5, -5.5), 2.8, Color("7a8090"))
			ci.draw_circle(c + Vector2(5.5, -5.5), 2.8, Color("7a8090"))
			_head(ci, c, 7.0, Color("b0b6c4"))
			ci.draw_colored_polygon(SvgArt.rrect(c.x - 7.0, c.y - 3.5, 14.0, 4.5, 2.0), Color("2a2f3e"))
			ci.draw_circle(c + Vector2(-2.7, -1.2), 1.1, Color.WHITE)
			ci.draw_circle(c + Vector2(2.7, -1.2), 1.1, Color.WHITE)
			ci.draw_circle(c + Vector2(0, 3.3), 1.4, eye)
	if cheer > 0.05:   # both paws up over the rim
		var pc := Color("f5d9b8")
		for sx in [-1.0, 1.0]:
			var base := Vector2(HEAD.x + sx * 9.0, 64.0)
			var tip := Vector2(HEAD.x + sx * (11.0 + 2.0 * sin(cheer * 40.0)), 64.0 - 12.0 * cheer)
			ci.draw_line(base, tip, pc, 2.4, true)
			ci.draw_circle(tip, 2.2, pc)
	if sad > 0.05:   # a tear
		ci.draw_circle(c + Vector2(4.0, 3.5 + sad * 3.5), 1.5, Color("6fb4ff"))
