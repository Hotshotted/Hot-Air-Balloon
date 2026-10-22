class_name Regions
extends RefCounted
## The four regions of the world: name, palette, hazard set and special mechanics. Pure data (plus the
## backdrop drawing shared by the map, the Flight screen and the postcards). Nothing here allocates while playing.

const COUNT := 4
const NAMES := ["Countryside", "Alps", "Sahara", "Himalayas"]
const BLURB := ["gentle winds", "strong steady winds, eagles, cable cars", "thermals and sand haze", "thin air and a jet stream"]
## Hazard kinds (Lanes.BIRD...) in the order they are introduced across a region's six Flights.
const KINDS := [[0, 1, 2, 3], [4, 5, 0, 1], [0, 6, 2, 3], [4, 7, 0, 3]]
## Sky bands from the lowest layer to the highest, the strip above the goal, ground and scenery colours.
const SKY_LOW := [Color("9acaf1"), Color("a6d0f4"), Color("fbdcaa"), Color("8a78b8")]
const SKY_MID := [Color("79b4ea"), Color("6aa6e8"), Color("f7c680"), Color("4d4a94")]
const SKY_HIGH := [Color("6aa9e6"), Color("4c8fe0"), Color("f3b56d"), Color("2f3478")]
const SKY_TOP := [Color("5f9fe0"), Color("3d7fd6"), Color("efa95f"), Color("232860")]
const GROUND := [Color("7cc06a"), Color("86b878"), Color("e0a85c"), Color("c8d0e8")]
const PEAK_A := [Color("5aa05a"), Color("c3cfe6"), Color("d99a52"), Color("4a4f86")]
const PEAK_B := [Color("8cc58a"), Color("9fb4d8"), Color("e8b06a"), Color("6a64a8")]
const GROUND2 := [Color("62a957"), Color("6aa263"), Color("d99a52"), Color("aeb8d8")]
const SNOW := [Color(1, 1, 1, 0.0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.0), Color(0.95, 0.97, 1.0, 1)]   # alpha 0 = no snow cap
## Mechanics.
const THERMALS := [false, false, true, false]
const HAZE := [false, false, true, false]
const THIN_AIR := [false, false, false, true]
const JET := [false, false, false, true]


## Hazard kinds open at difficulty `lv` in a region: two at first, one more every 1.6 levels, up to four.
static func kinds_open(region: int, lv: float) -> int:
	return clampi(2 + int((lv - float(Flights.REGION_BASE[region])) / 1.6), 2, 4)

## A little picture of a region inside `r` (the shop preview, the postcards): a sky gradient, far ridges, rolling hills in the
## region's colours. Flat shapes, no outlines (Storybook Sky). `line_w` is kept for old call sites.
static func draw_backdrop(ci: CanvasItem, region: int, r: Rect2, _line_w: float = 4.0) -> void:
	var x0 := r.position.x
	var y0 := r.position.y
	var w := r.size.x
	var h := r.size.y
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(x0 + w, y0), Vector2(x0 + w, y0 + h), Vector2(x0, y0 + h)]),
		PackedColorArray([SKY_HIGH[region], SKY_HIGH[region], SKY_LOW[region], SKY_LOW[region]]))
	var base_y := y0 + h * 0.8
	var mh := h * 0.5
	match region:
		1, 3:   # peaks with snow caps
			for pk in [[0.18, 0.8, PEAK_B[region]], [0.5, 1.0, PEAK_A[region]], [0.84, 0.7, PEAK_B[region]]]:
				var cx: float = x0 + w * float(pk[0])
				var ph: float = mh * float(pk[1])
				var half := ph * 0.9
				ci.draw_colored_polygon(PackedVector2Array([Vector2(cx - half, base_y + 4.0), Vector2(cx, base_y - ph), Vector2(cx + half, base_y + 4.0)]), pk[2])
				ci.draw_colored_polygon(PackedVector2Array([Vector2(cx - half * 0.3, base_y - ph * 0.7), Vector2(cx, base_y - ph), Vector2(cx + half * 0.3, base_y - ph * 0.7)]), Color(1, 1, 1, 0.95))
		2:   # a sun and dunes
			ci.draw_circle(Vector2(x0 + w * 0.78, y0 + h * 0.26), h * 0.12, Color("fff1c8"))
			var dune := PackedVector2Array()
			for k in 25:
				var u := float(k) / 24.0
				dune.append(Vector2(x0 + w * u, base_y - mh * 0.35 * (0.5 + 0.5 * sin(u * TAU * 1.5 + 1.0))))
			dune.append(Vector2(x0 + w, base_y + 4.0))
			dune.append(Vector2(x0, base_y + 4.0))
			ci.draw_colored_polygon(dune, PEAK_B[region])
		_:   # gentle far hills
			var far := PackedVector2Array()
			for k in 25:
				var u2 := float(k) / 24.0
				far.append(Vector2(x0 + w * u2, base_y - mh * 0.45 * (0.5 + 0.5 * sin(u2 * TAU * 1.2 + 0.4))))
			far.append(Vector2(x0 + w, base_y + 4.0))
			far.append(Vector2(x0, base_y + 4.0))
			ci.draw_colored_polygon(far, PEAK_B[region])
	var near := PackedVector2Array()
	for k in 25:
		var u3 := float(k) / 24.0
		near.append(Vector2(x0 + w * u3, base_y + h * 0.02 - h * 0.08 * (0.5 + 0.5 * sin(u3 * TAU + 2.0))))
	near.append(Vector2(x0 + w, y0 + h))
	near.append(Vector2(x0, y0 + h))
	ci.draw_colored_polygon(near, GROUND[region])
	var front := PackedVector2Array()
	for k in 25:
		var u4 := float(k) / 24.0
		front.append(Vector2(x0 + w * u4, y0 + h * 0.93 - h * 0.05 * (0.5 + 0.5 * sin(u4 * TAU * 1.4))))
	front.append(Vector2(x0 + w, y0 + h))
	front.append(Vector2(x0, y0 + h))
	ci.draw_colored_polygon(front, GROUND2[region])
