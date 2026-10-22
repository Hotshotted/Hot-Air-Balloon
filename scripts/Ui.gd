class_name Ui
extends RefCounted
## Shared UI helpers, all on the Style system (docs/style.md): outlined labels in Fredoka / Nunito, buttons in the shared styles
## (primary = chunky green with a lip, secondary = dark with a light border, ghost = a translucent round chip, accent = gold),
## cards, and icons. Static data (styles) is built once; nothing here runs per frame.

const COL_GOLD := Style.ACCENT
const COL_BTN := Color(0.2, 0.55, 0.95)        # (the default colour argument: a secondary button)
const COL_DIM := Style.TEXT_QUIET

static var _star := PackedVector2Array()
static var _star_c := PackedVector2Array()
static var _boxes := {}

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
	ci.draw_polyline(star_closed(), Style.INK, 3.5 / r)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## An outlined label in the shared type: Fredoka for big text and numbers, Nunito for the rest; the ink outline is size / 8.
static func label(text: String, size: int, align: HorizontalAlignment, pos: Vector2, area: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_override("font", Style.font_for(text, size))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Style.TEXT)
	l.add_theme_color_override("font_outline_color", Style.INK)
	l.add_theme_constant_override("outline_size", maxi(size / 8, 4))
	l.position = pos
	l.size = area
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ---- button styles ----

## Which shared style a legacy colour stands for: orange -> primary (green), purple -> accent (gold), the greys and blues of
## the map nodes keep their meaning (locked / open / played / three stars), everything else is a secondary dark button.
static func kind_of(color: Color) -> String:
	if color.r > 0.85 and color.g > 0.4 and color.g < 0.6 and color.b < 0.3:
		return "primary"
	if color.b > 0.7 and color.r > 0.5 and color.g < 0.45:
		return "accent"
	if color == Color(0.33, 0.35, 0.42):
		return "locked"
	if color == Color(0.2, 0.55, 0.95):
		return "open"
	if color == Color(0.25, 0.7, 0.4):
		return "played"
	if color == Color(0.95, 0.72, 0.1):
		return "gold"
	return "secondary"

## [fill, lip, border, radius, lip height] for a kind.
static func _spec(kind: String) -> Array:
	match kind:
		"primary":
			return [Style.SUCCESS, Style.SUCCESS_DARK, Color(1, 1, 1, 0.55), Style.R_L, Style.LIP]
		"accent":
			return [Style.ACCENT, Style.ACCENT_DARK, Color(1, 1, 1, 0.55), Style.R_L, 8.0]
		"gold":
			return [Style.ACCENT, Style.ACCENT_DARK, Color(1, 1, 1, 0.6), Style.R_M, 7.0]
		"played":
			return [Style.SUCCESS, Style.SUCCESS_DARK, Color(1, 1, 1, 0.5), Style.R_M, 7.0]
		"open":
			return [Style.PRIMARY, Style.PRIMARY_DARK, Color(1, 1, 1, 0.5), Style.R_M, 7.0]
		"locked":
			return [Style.SURFACE_DARK, Style.INK, Color(1, 1, 1, 0.18), Style.R_M, 5.0]
		"ghost":
			return [Color(Style.SURFACE_DARK, 0.7), Color(Style.SURFACE_DARK, 0.0), Color(1, 1, 1, 0.3), Style.R_PILL, 0.0]
		_:
			return [Style.SURFACE_DARK_2, Style.SURFACE_DARK, Color(1, 1, 1, 0.45), Style.R_M, 6.0]

## A button face: the fill with the lip as a thick bottom border; `state` 0 normal, 1 hover, 2 pressed (pushed into the lip), 3 disabled.
static func box(kind: String, state: int) -> StyleBoxFlat:
	var key := "%s%d" % [kind, state]
	if _boxes.has(key):
		return _boxes[key]
	var sp := _spec(kind)
	var fill: Color = sp[0]
	var lip: float = sp[4]
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(sp[3])
	sb.anti_aliasing = true
	sb.set_border_width_all(3)
	sb.border_color = sp[2]
	if state == 1:
		fill = fill.lightened(0.08)
	elif state == 3:
		fill = Color(Style.SURFACE_DARK.r, Style.SURFACE_DARK.g, Style.SURFACE_DARK.b, 0.9)
	sb.bg_color = fill
	if lip > 0.0 and state != 3:
		sb.border_width_bottom = int(lip if state != 2 else lip * 0.35)
		sb.border_color = sp[1] if kind != "secondary" and kind != "locked" else sp[2]
		if kind == "secondary" or kind == "locked":
			sb.border_width_bottom = int(lip if state != 2 else lip * 0.35)
			sb.border_color = Style.INK if state != 3 else sp[2]
		sb.shadow_color = Style.SHADOW_COLOR
		sb.shadow_size = Style.SHADOW_SIZE if state != 2 else 6
		sb.shadow_offset = Style.SHADOW_OFFSET if state != 2 else Vector2(0, 3)
	if state == 2:
		sb.expand_margin_top = -5.0
	_boxes[key] = sb
	return sb

## Give a button the look of `kind` (all four states).
static func style_button(b: Button, kind: String) -> void:
	b.add_theme_stylebox_override("normal", box(kind, 0))
	b.add_theme_stylebox_override("hover", box(kind, 1))
	b.add_theme_stylebox_override("pressed", box(kind, 2))
	b.add_theme_stylebox_override("disabled", box(kind, 3))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.set_meta("kind", kind)

## Legacy: the box for a colour (the map recolours its nodes by star count).
static func apply_color(b: Button, color: Color) -> void:
	style_button(b, kind_of(color))

## A shared-style button: `color` picks the kind (see kind_of), `icon` (optional) is drawn at its left and the text shifts over.
static func button(text: String, size: int, pos: Vector2, area: Vector2, color: Color = COL_BTN, icon: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = area
	b.add_theme_font_override("font", Style.display())
	b.add_theme_font_size_override("font_size", size)
	for k in ["font_color", "font_pressed_color", "font_hover_color"]:
		b.add_theme_color_override(k, Style.TEXT)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	b.add_theme_color_override("font_outline_color", Style.INK)
	b.add_theme_constant_override("outline_size", maxi(size / 8, 3))
	style_button(b, kind_of(color))
	b.focus_mode = Control.FOCUS_NONE
	if icon != "":
		add_icon(b, icon, minf(area.y * 0.5, 64.0))
	return b

## An icon at the left of a button; the text moves right to make room (content margin).
static func add_icon(b: Button, icon: String, px: float) -> IconView:
	var iv := IconView.new(icon, px)
	iv.position = Vector2(px * 0.5 + 10.0, (b.size.y - px) * 0.5 - 2.0)
	b.add_child(iv)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBox = b.get_theme_stylebox(st)
		if sb != null:
			sb = sb.duplicate()
			sb.content_margin_left = px + 16.0
			b.add_theme_stylebox_override(st, sb)
	return iv

## A round "ghost" chip with only an icon (back, home, pause).
static func ghost_button(icon: String, pos: Vector2, px: float = 96.0) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = Vector2(px, px)
	style_button(b, "ghost")
	b.focus_mode = Control.FOCUS_NONE
	var iv := IconView.new(icon, px * 0.56)
	iv.position = Vector2(px * 0.22, px * 0.22)
	b.add_child(iv)
	return b

## A card: the shared panel (fill, light border, soft shadow) with the highlight cap across its top. Returns the panel.
static func card(pos: Vector2, area: Vector2, fill: Color = Style.SURFACE_DARK, radius: int = Style.R_L) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = area
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", Style.box(fill, Color(Style.LINE.r, Style.LINE.g, Style.LINE.b, 0.55), radius))
	var cap := Panel.new()
	cap.position = Vector2(3, 3)
	cap.size = Vector2(area.x - 6.0, minf(area.y * 0.4, 120.0))
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_theme_stylebox_override("panel", Style.sheen(maxi(radius - 3, 4), 0.09))
	p.add_child(cap)
	return p

## An icon node.
static func icon(id: String, px: float, pos: Vector2, color: Color = Color.WHITE) -> IconView:
	var iv := IconView.new(id, px, color)
	iv.position = pos
	return iv

# ---- safe areas ----

## Move what is pinned to the top or bottom edge of `root` (direct children only) in by the device's safe-area insets; full-screen
## backgrounds stay where they are. Idempotent per node: a node is shifted once for each inset value (stored in meta).
static func apply_safe(root: Node, viewport_h: float = 1920.0) -> void:
	for ch in root.get_children():
		if not (ch is Control):
			continue
		var c := ch as Control
		if c.size.y > viewport_h * 0.5:
			continue   # a background / full panel
		var done: float = c.get_meta("safe_applied", 0.0)
		var want := 0.0
		if c.position.y < 400.0:
			want = Style.safe_top
		elif c.position.y + c.size.y > viewport_h - 400.0:
			want = -Style.safe_bottom
		if want != done:
			c.position.y += want - done
			c.set_meta("safe_applied", want)

## Fit a full-screen screen (map, album, shop) into the safe area: scaled a little and moved down / in, so no button hides under a
## notch or the home bar. With no insets it does nothing.
static func fit_safe(screen: Control, viewport: Vector2 = Vector2(1080.0, 1920.0)) -> void:
	var k := minf((viewport.y - Style.safe_top - Style.safe_bottom) / viewport.y, (viewport.x - Style.safe_left - Style.safe_right) / viewport.x)
	screen.pivot_offset = Vector2.ZERO
	screen.scale = Vector2(k, k)
	screen.position = Vector2(Style.safe_left + ((viewport.x - Style.safe_left - Style.safe_right) - viewport.x * k) * 0.5, Style.safe_top)
