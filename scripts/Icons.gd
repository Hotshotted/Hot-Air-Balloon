class_name Icons
extends RefCounted
## The one vector icon set (docs/style.md): bold filled silhouettes with an ink outline, round proportions, no text and no
## emoji. Two-tone only where the colour is the meaning (coin / star gold, danger red). Every button, tool, goal type, region
## and stat uses the same icon everywhere. `draw` paints icon `id` in a box of radius `r` around `c` on any CanvasItem; it
## is called from `IconView._draw` (once per change), never per frame. Strokes are r / 6 (at least 3 px).

const IDS := [
	"coin", "star", "star_off", "propane", "flame", "balloon", "wind", "cloud", "storm", "bolt",
	"play", "pause", "restart", "home", "back", "next", "check", "close", "lock", "speaker", "note", "shop", "daily", "map", "album", "ad",
	"sandbag", "anchor", "vent",
	"goal_climb", "goal_stars", "goal_mail", "goal_storm", "goal_land",
	"region_0", "region_1", "region_2", "region_3",
	"cat_env", "cat_basket", "cat_pass", "legs",
]

static func has_icon(id: String) -> bool:
	return IDS.has(id)

static func _w(r: float) -> float:
	return maxf(r / 6.0, 3.0)

## A filled polygon with the ink outline.
static func _poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, r: float) -> void:
	ci.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, Style.INK, _w(r), true)

static func _circle(ci: CanvasItem, c: Vector2, rad: float, fill: Color, r: float) -> void:
	ci.draw_circle(c, rad + _w(r) * 0.5, Style.INK)
	ci.draw_circle(c, rad - _w(r) * 0.5, fill)

static func _rect(ci: CanvasItem, rect: Rect2, fill: Color, r: float) -> void:
	ci.draw_rect(rect, fill)
	ci.draw_rect(rect, Style.INK, false, _w(r))

static func _line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, r: float, mult: float = 1.0) -> void:
	ci.draw_line(a, b, Style.INK, _w(r) * mult + _w(r) * 0.9, true)
	ci.draw_line(a, b, col, _w(r) * mult, true)

static func _pl(ci: CanvasItem, pts: PackedVector2Array, col: Color, r: float, mult: float = 1.0) -> void:
	ci.draw_polyline(pts, Style.INK, _w(r) * mult + _w(r) * 0.9, true)
	ci.draw_polyline(pts, col, _w(r) * mult, true)

static func _arc_pts(c: Vector2, rad: float, a0: float, a1: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / float(n))
		out.append(c + Vector2(cos(a), sin(a)) * rad)
	return out

static func _star_pts(c: Vector2, rad: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + TAU * float(i) / 10.0
		out.append(c + Vector2(cos(a), sin(a)) * rad * (1.0 if i % 2 == 0 else 0.45))
	return out

static func _v(x: float, y: float, c: Vector2, r: float) -> Vector2:
	return c + Vector2(x, y) * r

## Draw icon `id` at `c` in a box of radius `r`. `col` tints single-colour icons (white by default); icons whose colour is the
## meaning (coin, star, flame, bolt) keep their own.
static func draw(ci: CanvasItem, id: String, c: Vector2, r: float, col: Color = Color.WHITE) -> void:
	var gold := Style.ACCENT
	match id:
		"coin":
			_circle(ci, c, r * 0.92, gold, r)
			ci.draw_arc(c, r * 0.6, 0.0, TAU, 20, Style.ACCENT_DARK, _w(r) * 0.8, true)
			ci.draw_line(_v(-0.2, -0.28, c, r), _v(-0.2, 0.28, c, r), Color(1, 1, 1, 0.8), _w(r) * 0.8, true)
		"star", "star_off":
			var fill := gold if id == "star" else Color(0.3, 0.33, 0.42)
			_poly(ci, _star_pts(c + Vector2(0, r * 0.06), r * 1.05), fill, r)
		"propane":
			_rect(ci, Rect2(_v(-0.5, -0.5, c, r), Vector2(r, r * 1.35)), Style.SUCCESS, r)
			_rect(ci, Rect2(_v(-0.28, -0.82, c, r), Vector2(r * 0.56, r * 0.32)), Style.TEXT_SOFT, r)
			ci.draw_line(_v(-0.5, 0.05, c, r), _v(0.5, 0.05, c, r), Style.SUCCESS_DARK, _w(r) * 0.8)
			ci.draw_rect(Rect2(_v(-0.35, -0.38, c, r), Vector2(r * 0.22, r * 0.8)), Color(1, 1, 1, 0.35))
		"flame":
			_poly(ci, PackedVector2Array([_v(0, -0.95, c, r), _v(0.45, -0.25, c, r), _v(0.6, 0.35, c, r), _v(0.3, 0.85, c, r), _v(-0.3, 0.85, c, r), _v(-0.6, 0.35, c, r), _v(-0.4, -0.2, c, r)]), Style.WARNING, r)
			_poly(ci, PackedVector2Array([_v(0, -0.2, c, r), _v(0.28, 0.35, c, r), _v(0.12, 0.7, c, r), _v(-0.12, 0.7, c, r), _v(-0.28, 0.35, c, r)]), gold, r * 0.6)
		"balloon":
			_poly(ci, PackedVector2Array([_v(0, -0.95, c, r), _v(0.55, -0.7, c, r), _v(0.72, -0.15, c, r), _v(0.5, 0.35, c, r), _v(0.18, 0.62, c, r), _v(-0.18, 0.62, c, r), _v(-0.5, 0.35, c, r), _v(-0.72, -0.15, c, r), _v(-0.55, -0.7, c, r)]), Style.DANGER, r)
			ci.draw_line(_v(0, -0.9, c, r), _v(0, 0.6, c, r), Color(1, 1, 1, 0.55), _w(r) * 0.7)
			_rect(ci, Rect2(_v(-0.2, 0.78, c, r), Vector2(r * 0.4, r * 0.24)), Style.ACCENT_DARK, r * 0.8)
		"wind":
			for k in 3:
				var y := -0.55 + 0.55 * float(k)
				var x1 := 0.7 - 0.12 * float(k)
				_pl(ci, PackedVector2Array([_v(-0.85, y, c, r), _v(x1 - 0.1, y, c, r)]), col, r)
				_pl(ci, _arc_pts(_v(x1 - 0.1, y - 0.2, c, r), r * 0.2, PI * 0.5, -PI * 1.2, 8), col, r)
		"cloud":
			_cloud(ci, c, r, col, r)
		"storm":
			_cloud(ci, c + Vector2(0, -r * 0.2), r * 0.9, Color(0.55, 0.6, 0.78), r)
			_poly(ci, PackedVector2Array([_v(0.1, 0.1, c, r), _v(-0.28, 0.62, c, r), _v(-0.02, 0.6, c, r), _v(-0.18, 1.0, c, r), _v(0.36, 0.42, c, r), _v(0.08, 0.44, c, r)]), gold, r * 0.8)
		"bolt":
			_poly(ci, PackedVector2Array([_v(0.2, -1.0, c, r), _v(-0.5, 0.15, c, r), _v(-0.05, 0.12, c, r), _v(-0.25, 1.0, c, r), _v(0.55, -0.2, c, r), _v(0.1, -0.15, c, r)]), gold, r)
		"play":
			_poly(ci, PackedVector2Array([_v(-0.5, -0.78, c, r), _v(0.82, 0.0, c, r), _v(-0.5, 0.78, c, r)]), col, r)
		"pause":
			_rect(ci, Rect2(_v(-0.62, -0.75, c, r), Vector2(r * 0.46, r * 1.5)), col, r)
			_rect(ci, Rect2(_v(0.16, -0.75, c, r), Vector2(r * 0.46, r * 1.5)), col, r)
		"restart":
			_pl(ci, _arc_pts(c, r * 0.62, -PI * 0.35, PI * 1.4, 18), col, r, 1.5)
			_poly(ci, PackedVector2Array([_v(0.78, -0.1, c, r), _v(0.28, -0.12, c, r), _v(0.62, -0.62, c, r)]), col, r * 0.8)
		"home":
			_poly(ci, PackedVector2Array([_v(0, -0.9, c, r), _v(0.95, 0.0, c, r), _v(0.68, 0.0, c, r), _v(0.68, 0.82, c, r), _v(-0.68, 0.82, c, r), _v(-0.68, 0.0, c, r), _v(-0.95, 0.0, c, r)]), col, r)
			ci.draw_rect(Rect2(_v(-0.2, 0.2, c, r), Vector2(r * 0.4, r * 0.62)), Style.SURFACE_DARK_2)
		"back":
			_pl(ci, PackedVector2Array([_v(0.4, -0.8, c, r), _v(-0.45, 0.0, c, r), _v(0.4, 0.8, c, r)]), col, r, 1.8)
		"next":
			_pl(ci, PackedVector2Array([_v(-0.4, -0.8, c, r), _v(0.45, 0.0, c, r), _v(-0.4, 0.8, c, r)]), col, r, 1.8)
		"check":
			_pl(ci, PackedVector2Array([_v(-0.8, 0.05, c, r), _v(-0.25, 0.6, c, r), _v(0.8, -0.6, c, r)]), Style.SUCCESS if col == Color.WHITE else col, r, 2.0)
		"close":
			_line(ci, _v(-0.62, -0.62, c, r), _v(0.62, 0.62, c, r), col, r, 1.8)
			_line(ci, _v(0.62, -0.62, c, r), _v(-0.62, 0.62, c, r), col, r, 1.8)
		"lock":
			_pl(ci, _arc_pts(_v(0, -0.2, c, r), r * 0.42, PI, TAU, 10), Style.TEXT_SOFT, r, 1.3)
			_rect(ci, Rect2(_v(-0.62, -0.2, c, r), Vector2(r * 1.24, r * 1.0)), Style.TEXT_SOFT, r)
			ci.draw_circle(_v(0, 0.28, c, r), r * 0.14, Style.INK)
		"speaker":
			_poly(ci, PackedVector2Array([_v(-0.85, -0.3, c, r), _v(-0.4, -0.3, c, r), _v(0.1, -0.75, c, r), _v(0.1, 0.75, c, r), _v(-0.4, 0.3, c, r), _v(-0.85, 0.3, c, r)]), col, r)
			_pl(ci, _arc_pts(c + Vector2(r * 0.1, 0), r * 0.5, -PI * 0.32, PI * 0.32, 6), col, r, 0.9)
			_pl(ci, _arc_pts(c + Vector2(r * 0.1, 0), r * 0.85, -PI * 0.32, PI * 0.32, 6), col, r, 0.9)
		"note":
			_circle(ci, _v(-0.35, 0.55, c, r), r * 0.36, col, r)
			_line(ci, _v(-0.05, 0.5, c, r), _v(-0.05, -0.8, c, r), col, r, 1.2)
			_poly(ci, PackedVector2Array([_v(-0.05, -0.8, c, r), _v(0.7, -0.5, c, r), _v(0.7, -0.1, c, r), _v(-0.05, -0.4, c, r)]), col, r * 0.8)
		"shop":
			_poly(ci, PackedVector2Array([_v(-0.8, -0.35, c, r), _v(0.8, -0.35, c, r), _v(0.68, 0.9, c, r), _v(-0.68, 0.9, c, r)]), Style.SUCCESS, r)
			_pl(ci, _arc_pts(_v(0, -0.35, c, r), r * 0.36, PI, TAU, 8), col, r, 1.1)
			ci.draw_circle(_v(0, 0.2, c, r), r * 0.12, Style.INK)
		"daily":
			_rect(ci, Rect2(_v(-0.8, -0.62, c, r), Vector2(r * 1.6, r * 1.5)), Style.TEXT, r)
			ci.draw_rect(Rect2(_v(-0.8, -0.62, c, r), Vector2(r * 1.6, r * 0.45)), Style.DANGER)
			ci.draw_rect(Rect2(_v(-0.8, -0.62, c, r), Vector2(r * 1.6, r * 1.5)), Style.INK, false, _w(r))
			for k in 3:
				ci.draw_circle(_v(-0.4 + 0.4 * float(k), 0.2, c, r), r * 0.1, Style.INK)
				ci.draw_circle(_v(-0.4 + 0.4 * float(k), 0.55, c, r), r * 0.1, Style.INK)
		"map":
			_poly(ci, PackedVector2Array([_v(-0.9, -0.6, c, r), _v(-0.3, -0.8, c, r), _v(0.3, -0.6, c, r), _v(0.9, -0.8, c, r), _v(0.9, 0.6, c, r), _v(0.3, 0.8, c, r), _v(-0.3, 0.6, c, r), _v(-0.9, 0.8, c, r)]), Style.TEXT_SOFT, r)
			ci.draw_line(_v(-0.3, -0.8, c, r), _v(-0.3, 0.6, c, r), Style.INK, _w(r) * 0.7)
			ci.draw_line(_v(0.3, -0.6, c, r), _v(0.3, 0.8, c, r), Style.INK, _w(r) * 0.7)
			ci.draw_circle(_v(0.55, -0.1, c, r), r * 0.14, Style.DANGER)
		"album":
			_rect(ci, Rect2(_v(-0.8, -0.55, c, r), Vector2(r * 1.6, r * 1.2)), Style.TEXT, r)
			_rect(ci, Rect2(_v(0.2, -0.4, c, r), Vector2(r * 0.45, r * 0.5)), Style.PRIMARY, r * 0.7)
			ci.draw_line(_v(-0.6, 0.0, c, r), _v(0.0, 0.0, c, r), Style.INK, _w(r) * 0.7)
			ci.draw_line(_v(-0.6, 0.3, c, r), _v(0.0, 0.3, c, r), Style.INK, _w(r) * 0.7)
		"ad":
			_rect(ci, Rect2(_v(-0.88, -0.6, c, r), Vector2(r * 1.76, r * 1.3)), Style.SURFACE_DARK_2, r)
			_poly(ci, PackedVector2Array([_v(-0.2, -0.3, c, r), _v(0.42, 0.05, c, r), _v(-0.2, 0.4, c, r)]), gold, r * 0.7)
		"sandbag":
			_poly(ci, PackedVector2Array([_v(-0.3, -0.45, c, r), _v(0.3, -0.45, c, r), _v(0.78, 0.2, c, r), _v(0.55, 0.88, c, r), _v(-0.55, 0.88, c, r), _v(-0.78, 0.2, c, r)]), Color(0.85, 0.65, 0.35), r)
			_rect(ci, Rect2(_v(-0.32, -0.7, c, r), Vector2(r * 0.64, r * 0.3)), Color(0.65, 0.45, 0.2), r * 0.8)
			ci.draw_line(_v(-0.4, 0.3, c, r), _v(0.4, 0.3, c, r), Color(0.6, 0.4, 0.2), _w(r) * 0.7)
		"anchor":
			_circle(ci, _v(0, -0.7, c, r), r * 0.2, col, r * 0.8)
			_line(ci, _v(0, -0.5, c, r), _v(0, 0.8, c, r), col, r, 1.1)
			_line(ci, _v(-0.35, -0.2, c, r), _v(0.35, -0.2, c, r), col, r, 1.0)
			_pl(ci, _arc_pts(_v(0, 0.1, c, r), r * 0.7, PI * 0.1, PI * 0.9, 10), col, r, 1.2)
		"vent":
			_poly(ci, PackedVector2Array([_v(-0.7, -0.85, c, r), _v(0.7, -0.85, c, r), _v(0.5, -0.1, c, r), _v(-0.5, -0.1, c, r)]), Style.DANGER, r)
			_pl(ci, PackedVector2Array([_v(-0.45, 0.2, c, r), _v(0, 0.6, c, r), _v(0.45, 0.2, c, r)]), col, r, 1.3)
			_pl(ci, PackedVector2Array([_v(-0.45, 0.62, c, r), _v(0, 1.0, c, r), _v(0.45, 0.62, c, r)]), col, r, 1.3)
		"goal_climb":
			_poly(ci, PackedVector2Array([_v(0, -0.95, c, r), _v(0.7, -0.1, c, r), _v(0.28, -0.1, c, r), _v(0.28, 0.9, c, r), _v(-0.28, 0.9, c, r), _v(-0.28, -0.1, c, r), _v(-0.7, -0.1, c, r)]), Style.SUCCESS, r)
		"goal_stars":
			_poly(ci, _star_pts(_v(-0.28, -0.2, c, r), r * 0.7), gold, r * 0.8)
			_poly(ci, _star_pts(_v(0.4, 0.4, c, r), r * 0.55), gold, r * 0.8)
		"goal_mail":
			_rect(ci, Rect2(_v(-0.88, -0.55, c, r), Vector2(r * 1.76, r * 1.2)), Style.TEXT, r)
			_pl(ci, PackedVector2Array([_v(-0.88, -0.55, c, r), _v(0, 0.12, c, r), _v(0.88, -0.55, c, r)]), Style.INK, r, 0.7)
			ci.draw_circle(_v(0.5, 0.3, c, r), r * 0.14, Style.DANGER)
		"goal_storm":
			_cloud(ci, c + Vector2(0, -r * 0.25), r * 0.9, Color(0.5, 0.5, 0.72), r)
			for k in 3:
				_line(ci, _v(-0.5 + 0.5 * float(k), 0.35, c, r), _v(-0.62 + 0.5 * float(k), 0.85, c, r), Style.PRIMARY, r)
		"goal_land":
			_poly(ci, PackedVector2Array([_v(-0.9, 0.5, c, r), _v(0.9, 0.5, c, r), _v(0.6, 0.85, c, r), _v(-0.6, 0.85, c, r)]), Style.TEXT_SOFT, r)
			_pl(ci, PackedVector2Array([_v(0, -0.85, c, r), _v(0, 0.2, c, r)]), Style.SUCCESS, r, 1.3)
			_poly(ci, PackedVector2Array([_v(-0.4, -0.05, c, r), _v(0.4, -0.05, c, r), _v(0, 0.42, c, r)]), Style.SUCCESS, r * 0.8)
		"region_0":   # countryside: a green hill and the sun
			ci.draw_circle(_v(0.4, -0.45, c, r), r * 0.3, gold)
			_poly(ci, PackedVector2Array([_v(-0.95, 0.8, c, r), _v(-0.6, 0.1, c, r), _v(-0.1, -0.1, c, r), _v(0.5, 0.15, c, r), _v(0.95, 0.8, c, r)]), Style.SUCCESS, r)
		"region_1":   # alps: two peaks with snow
			_poly(ci, PackedVector2Array([_v(-1.0, 0.8, c, r), _v(-0.35, -0.75, c, r), _v(0.15, 0.1, c, r), _v(0.45, -0.3, c, r), _v(1.0, 0.8, c, r)]), Color(0.55, 0.65, 0.85), r)
			_poly(ci, PackedVector2Array([_v(-0.35, -0.75, c, r), _v(-0.62, -0.25, c, r), _v(-0.35, -0.38, c, r), _v(-0.12, -0.25, c, r)]), Color.WHITE, r * 0.6)
		"region_2":   # sahara: a dune under a hot sun
			ci.draw_circle(_v(-0.4, -0.4, c, r), r * 0.32, Style.WARNING)
			_poly(ci, PackedVector2Array([_v(-1.0, 0.8, c, r), _v(-0.5, 0.2, c, r), _v(0.1, 0.05, c, r), _v(0.6, 0.3, c, r), _v(1.0, 0.8, c, r)]), Color(0.9, 0.7, 0.35), r)
		"region_3":   # himalayas: one tall peak with a flag
			_poly(ci, PackedVector2Array([_v(-0.95, 0.85, c, r), _v(-0.1, -0.8, c, r), _v(0.95, 0.85, c, r)]), Color(0.62, 0.55, 0.78), r)
			_poly(ci, PackedVector2Array([_v(-0.1, -0.8, c, r), _v(-0.32, -0.35, c, r), _v(-0.1, -0.45, c, r), _v(0.12, -0.35, c, r)]), Color.WHITE, r * 0.6)
			_line(ci, _v(-0.1, -0.8, c, r), _v(-0.1, -1.05, c, r), Style.DANGER, r, 0.7)
		"cat_env":
			draw(ci, "balloon", c, r, col)
		"cat_basket":
			_poly(ci, PackedVector2Array([_v(-0.75, -0.3, c, r), _v(0.75, -0.3, c, r), _v(0.55, 0.8, c, r), _v(-0.55, 0.8, c, r)]), Color(0.75, 0.5, 0.25), r)
			ci.draw_line(_v(-0.65, 0.1, c, r), _v(0.65, 0.1, c, r), Color(0.45, 0.28, 0.12), _w(r) * 0.7)
			ci.draw_line(_v(-0.6, 0.45, c, r), _v(0.6, 0.45, c, r), Color(0.45, 0.28, 0.12), _w(r) * 0.7)
			_line(ci, _v(-0.5, -0.3, c, r), _v(-0.3, -0.9, c, r), col, r, 0.6)
			_line(ci, _v(0.5, -0.3, c, r), _v(0.3, -0.9, c, r), col, r, 0.6)
		"cat_pass":
			_circle(ci, c + Vector2(0, r * 0.1), r * 0.62, Color(0.95, 0.5, 0.15), r)
			_poly(ci, PackedVector2Array([_v(-0.55, -0.35, c, r), _v(-0.35, -0.95, c, r), _v(-0.05, -0.5, c, r)]), Color(0.95, 0.5, 0.15), r * 0.8)
			_poly(ci, PackedVector2Array([_v(0.55, -0.35, c, r), _v(0.35, -0.95, c, r), _v(0.05, -0.5, c, r)]), Color(0.95, 0.5, 0.15), r * 0.8)
			ci.draw_circle(_v(-0.2, 0.0, c, r), r * 0.08, Style.INK)
			ci.draw_circle(_v(0.2, 0.0, c, r), r * 0.08, Style.INK)
		"legs":
			draw(ci, "balloon", c, r, col)

static func _cloud(ci: CanvasItem, c: Vector2, rad: float, fill: Color, r: float) -> void:
	var pts := PackedVector2Array()
	pts.append_array(_arc_pts(c + Vector2(-rad * 0.5, rad * 0.1), rad * 0.4, PI * 0.5, PI * 1.5, 6))
	pts.append_array(_arc_pts(c + Vector2(-rad * 0.05, -rad * 0.2), rad * 0.5, PI * 1.1, PI * 1.9, 6))
	pts.append_array(_arc_pts(c + Vector2(rad * 0.5, rad * 0.1), rad * 0.4, -PI * 0.5, PI * 0.5, 6))
	_poly(ci, pts, fill, r)
