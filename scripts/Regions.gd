class_name Regions
extends RefCounted
## The four regions of the world: name, palette, hazard set and special mechanics. Pure data (plus the
## backdrop drawing shared by the map, the Flight screen and the postcards). Nothing here allocates while playing.

const COUNT := 4
const NAMES := ["Countryside", "Alps", "Sahara", "Himalayas"]
const BLURB := ["gentle winds", "gusty layers, eagles, cable cars", "thermals and sand haze", "thin air and a jet stream"]
## Hazard kinds (Lanes.BIRD...) in the order they are introduced across a region's six Flights.
const KINDS := [[0, 1, 2, 3], [4, 5, 0, 1], [0, 6, 2, 3], [4, 7, 0, 3]]
## Sky bands from the lowest layer to the highest, the strip above the goal, ground and scenery colours.
const SKY_LOW := [Color(1.0, 0.85, 0.55), Color(0.86, 0.93, 1.0), Color(1.0, 0.8, 0.42), Color(0.78, 0.72, 0.92)]
const SKY_MID := [Color(0.62, 0.88, 0.8), Color(0.55, 0.78, 0.98), Color(1.0, 0.9, 0.64), Color(0.46, 0.42, 0.78)]
const SKY_HIGH := [Color(0.3, 0.58, 0.95), Color(0.2, 0.4, 0.84), Color(0.96, 0.58, 0.34), Color(0.12, 0.1, 0.36)]
const SKY_TOP := [Color(0.27, 0.5, 0.88), Color(0.18, 0.34, 0.74), Color(0.9, 0.46, 0.3), Color(0.07, 0.06, 0.24)]
const GROUND := [Color(0.36, 0.62, 0.3), Color(0.62, 0.74, 0.5), Color(0.93, 0.78, 0.45), Color(0.86, 0.9, 0.98)]
const PEAK_A := [Color(0.26, 0.5, 0.36), Color(0.45, 0.52, 0.66), Color(0.88, 0.68, 0.36), Color(0.34, 0.3, 0.55)]
const PEAK_B := [Color(0.2, 0.42, 0.34), Color(0.36, 0.43, 0.58), Color(0.8, 0.58, 0.3), Color(0.26, 0.22, 0.46)]
const SNOW := [Color(1, 1, 1, 0.0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.0), Color(0.95, 0.97, 1.0, 1)]   # alpha 0 = no snow cap
## Mechanics.
const GUSTY := [false, true, false, false]
const THERMALS := [false, false, true, false]
const HAZE := [false, false, true, false]
const THIN_AIR := [false, false, false, true]
const JET := [false, false, false, true]

static var _tri := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
static var _tri_c := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

## Hazard kinds open at difficulty `lv` in a region: two at first, one more every 1.6 levels, up to four.
static func kinds_open(region: int, lv: float) -> int:
	return clampi(2 + int((lv - float(Flights.REGION_BASE[region])) / 1.6), 2, 4)

static func _triangle(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, fill: Color, w: float) -> void:
	_tri[0] = a
	_tri[1] = b
	_tri[2] = c
	ci.draw_colored_polygon(_tri, fill)
	_tri_c[0] = a
	_tri_c[1] = b
	_tri_c[2] = c
	_tri_c[3] = a
	ci.draw_polyline(_tri_c, Color.BLACK, w)

## A little picture of a region (sky bands, scenery, ground) inside `r`: used by the map and the postcards.
static func draw_backdrop(ci: CanvasItem, region: int, r: Rect2, line_w: float = 4.0) -> void:
	var third := r.size.y * 0.4
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, third + 1.0)), SKY_HIGH[region])
	ci.draw_rect(Rect2(r.position + Vector2(0, third), Vector2(r.size.x, third + 1.0)), SKY_MID[region])
	ci.draw_rect(Rect2(r.position + Vector2(0, third * 2.0), Vector2(r.size.x, r.size.y - third * 2.0)), SKY_LOW[region])
	var base_y := r.position.y + r.size.y * 0.82
	var mh := r.size.y * 0.52
	var x0 := r.position.x
	var w := r.size.x
	_peak(ci, region, Vector2(x0 + w * 0.0, base_y), Vector2(x0 + w * 0.22, base_y - mh * 0.8), Vector2(x0 + w * 0.46, base_y), PEAK_A[region], line_w)
	_peak(ci, region, Vector2(x0 + w * 0.3, base_y), Vector2(x0 + w * 0.56, base_y - mh), Vector2(x0 + w * 0.86, base_y), PEAK_B[region], line_w)
	_peak(ci, region, Vector2(x0 + w * 0.66, base_y), Vector2(x0 + w * 0.88, base_y - mh * 0.7), Vector2(x0 + w * 1.0, base_y), PEAK_A[region], line_w)
	ci.draw_rect(Rect2(x0, base_y, w, r.position.y + r.size.y - base_y), GROUND[region])
	ci.draw_line(Vector2(x0, base_y), Vector2(x0 + w, base_y), Color.BLACK, line_w)
	ci.draw_rect(r, Color.BLACK, false, line_w)

static func _peak(ci: CanvasItem, region: int, a: Vector2, p: Vector2, b: Vector2, fill: Color, w: float) -> void:
	_triangle(ci, a, p, b, fill, w)
	if SNOW[region].a > 0.5:
		_triangle(ci, p, p.lerp(a, 0.3), p.lerp(b, 0.3), SNOW[region], w * 0.6)
