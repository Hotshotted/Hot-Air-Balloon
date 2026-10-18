class_name Ui
extends RefCounted
## Small shared UI helpers: the star polygon, outlined labels, flat outlined buttons. Static data is built once.

const COL_BTN := Color(0.2, 0.55, 0.95)
const COL_GOLD := Color(1.0, 0.82, 0.15)
const COL_DIM := Color(0.35, 0.38, 0.45)

static var _star := PackedVector2Array()
static var _star_c := PackedVector2Array()
static var _styles := {}

## A 5-point star of radius 1 (outer) around the origin.
static func star_unit() -> PackedVector2Array:
	if _star.is_empty():
		for i in 10:
			var a := -PI * 0.5 + TAU * float(i) / 10.0
			var r := 1.0 if i % 2 == 0 else 0.45
			_star.append(Vector2(cos(a), sin(a)) * r)
		_star_c = _star.duplicate()
		_star_c.append(_star[0])
	return _star

static func star_closed() -> PackedVector2Array:
	star_unit()
	return _star_c

## Draw an outlined star of radius `r` centred at `p` on any CanvasItem.
static func draw_star(ci: CanvasItem, p: Vector2, r: float, fill: Color) -> void:
	ci.draw_set_transform(p, 0.0, Vector2(r, r))
	ci.draw_colored_polygon(star_unit(), fill)
	ci.draw_polyline(star_closed(), Color.BLACK, 3.5 / r)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func label(text: String, size: int, align: HorizontalAlignment, pos: Vector2, area: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(size / 7, 4))
	l.position = pos
	l.size = area
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func _style(color: Color) -> StyleBoxFlat:
	var key := color.to_html()
	if not _styles.has(key):
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_border_width_all(5)
		sb.border_color = Color.BLACK
		sb.set_corner_radius_all(18)
		_styles[key] = sb
	return _styles[key]

## A flat, outlined button.
static func button(text: String, size: int, pos: Vector2, area: Vector2, color: Color = COL_BTN) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = area
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	b.add_theme_color_override("font_outline_color", Color.BLACK)
	b.add_theme_constant_override("outline_size", maxi(size / 8, 3))
	b.add_theme_stylebox_override("normal", _style(color))
	b.add_theme_stylebox_override("hover", _style(color.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", _style(color.darkened(0.2)))
	b.add_theme_stylebox_override("disabled", _style(COL_DIM))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE
	return b
