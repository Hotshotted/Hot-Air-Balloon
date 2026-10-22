class_name SvgArt
extends RefCounted
## Tiny SVG path reader so the "Storybook Sky" art can be ported straight from the design canvas: M L H V C Q Z (absolute),
## curves flattened to short segments. Paths are parsed once and cached (as polygons), never while playing.

static var _cache := {}

## Parse `d` into one polygon per sub-path; `off` is added to every point and the sum is multiplied by `sc`.
static func path(d: String, off: Vector2 = Vector2.ZERO, sc: float = 1.0) -> Array:
	var key := "%s|%s|%s" % [d, off, sc]
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	var cur := PackedVector2Array()
	var toks := _tokens(d)
	var i := 0
	var cmd := ""
	var p := Vector2.ZERO
	var start := Vector2.ZERO
	while i < toks.size():
		var t: String = toks[i]
		if t.length() == 1 and "MLHVCQZ".contains(t):
			cmd = t
			i += 1
			if cmd == "Z":
				if cur.size() > 0:
					out.append(cur)
				cur = PackedVector2Array()
				p = start
				continue
		match cmd:
			"M":
				if cur.size() > 1:
					out.append(cur)
				cur = PackedVector2Array()
				p = Vector2(float(toks[i]), float(toks[i + 1]))
				start = p
				cur.append(_tx(p, off, sc))
				i += 2
				cmd = "L"
			"L":
				p = Vector2(float(toks[i]), float(toks[i + 1]))
				cur.append(_tx(p, off, sc))
				i += 2
			"H":
				p = Vector2(float(toks[i]), p.y)
				cur.append(_tx(p, off, sc))
				i += 1
			"V":
				p = Vector2(p.x, float(toks[i]))
				cur.append(_tx(p, off, sc))
				i += 1
			"C":
				var c1 := Vector2(float(toks[i]), float(toks[i + 1]))
				var c2 := Vector2(float(toks[i + 2]), float(toks[i + 3]))
				var e := Vector2(float(toks[i + 4]), float(toks[i + 5]))
				for k in range(1, 9):
					var u := float(k) / 8.0
					var q := _cubic(p, c1, c2, e, u)
					cur.append(_tx(q, off, sc))
				p = e
				i += 6
			"Q":
				var c1q := Vector2(float(toks[i]), float(toks[i + 1]))
				var eq := Vector2(float(toks[i + 2]), float(toks[i + 3]))
				for k in range(1, 7):
					var u2 := float(k) / 6.0
					cur.append(_tx(p.lerp(c1q, u2).lerp(c1q.lerp(eq, u2), u2), off, sc))
				p = eq
				i += 4
			_:
				i += 1
	if cur.size() > 1:
		out.append(cur)
	_cache[key] = out
	return out

static func _tx(p: Vector2, off: Vector2, sc: float) -> Vector2:
	return (p + off) * sc

static func _cubic(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t

static func _tokens(d: String) -> PackedStringArray:
	var out := PackedStringArray()
	var num := ""
	for ch in d:
		if ch == " " or ch == ",":
			if num != "":
				out.append(num)
				num = ""
		elif "MLHVCQZ".contains(ch):
			if num != "":
				out.append(num)
				num = ""
			out.append(ch)
		elif ch == "-" and num != "" and not num.ends_with("e"):
			out.append(num)
			num = "-"
		else:
			num += ch
	if num != "":
		out.append(num)
	return out

## Fill every sub-path of `d`.
static func fill(ci: CanvasItem, d: String, col: Color, off: Vector2 = Vector2.ZERO, sc: float = 1.0) -> void:
	for poly in path(d, off, sc):
		if poly.size() >= 3:
			ci.draw_colored_polygon(poly, col)

## Stroke every sub-path of `d` as an open line.
static func stroke(ci: CanvasItem, d: String, col: Color, w: float, off: Vector2 = Vector2.ZERO, sc: float = 1.0, closed: bool = false) -> void:
	for poly in path(d, off, sc):
		if closed:
			var c: PackedVector2Array = poly.duplicate()
			c.append(poly[0])
			ci.draw_polyline(c, col, w, true)
		else:
			ci.draw_polyline(poly, col, w, true)

## A rounded rectangle as a polygon.
static func rrect(x: float, y: float, w: float, h: float, r: float, off: Vector2 = Vector2.ZERO, sc: float = 1.0) -> PackedVector2Array:
	r = minf(r, minf(w, h) * 0.5)
	var pts := PackedVector2Array()
	for corner in 4:
		var cx: float = x + (w - r if corner == 0 or corner == 1 else r)
		var cy: float = y + (r if corner == 0 or corner == 3 else h - r)
		var a0: float = [-PI * 0.5, 0.0, PI * 0.5, PI][corner]
		for k in 5:
			var a: float = a0 + PI * 0.5 * float(k) / 4.0
			pts.append((Vector2(cx + cos(a) * r, cy + sin(a) * r) + off) * sc)
	return pts

## An ellipse as a polygon.
static func ellipse(c: Vector2, rx: float, ry: float, rot: float = 0.0, n: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n:
		var a := TAU * float(k) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts
