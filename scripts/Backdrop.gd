class_name Backdrop
extends Node2D
## Everything in the sky that never moves during a leg: the layer bands, the scenery, the goal strip and the cables.
## Drawn ONCE when a leg is set up (redraw()), never per frame.

var lanes: Lanes
var draws := 0          # how many times it has been drawn (a leg start redraws it; play must not)

func redraw() -> void:
	queue_redraw()

func _draw() -> void:
	draws += 1
	var L := lanes
	var c_low: Color = Regions.SKY_LOW[L.region]
	var c_mid: Color = Regions.SKY_MID[L.region]
	var c_high: Color = Regions.SKY_HIGH[L.region]
	draw_rect(Rect2(0, 0, Lanes.W, Lanes.BAND_TOP), Regions.SKY_TOP[L.region])
	draw_rect(Rect2(0, Lanes.BAND_BOTTOM, Lanes.W, Lanes.H - Lanes.BAND_BOTTOM), c_low)
	for i in L.n_lanes:
		var t := (float(i) + 0.5) / float(L.n_lanes)
		var col := c_low.lerp(c_mid, minf(t * 2.0, 1.0)) if t < 0.5 else c_mid.lerp(c_high, (t - 0.5) * 2.0)
		if i % 2 == 1:
			col = col.lightened(0.07)
		draw_rect(Rect2(0, Lanes.BAND_BOTTOM - float(i + 1) * L.lane_h, Lanes.W, L.lane_h + 1.0), col)
	for s in L._scn[L.region]:
		draw_colored_polygon(s[0], s[2])
		draw_polyline(s[1], Lanes.FX_BLACK, 4.0)
	for i in L.n_lanes:   # the cables the cable cars hang from
		if L.lane_kind[i] == Lanes.CABLE:
			var cy := L._lane_cy(i) - 44.0 * L.lane_scale[i]
			draw_line(Vector2(0, cy), Vector2(Lanes.W, cy), Lanes.FX_BLACK, 5.0)
	# The goal strip: two rows of black and white squares.
	var size := 34.0
	for row in 2:
		for c in int(Lanes.W / size) + 1:
			var col2 := Lanes.FX_BLACK if (c + row) % 2 == 0 else Color.WHITE
			draw_rect(Rect2(float(c) * size, Lanes.GOAL_Y - 2.0 * size + float(row) * size, size, size), col2)
	draw_rect(Rect2(0, Lanes.GOAL_Y - 2.0 * size, Lanes.W, 2.0 * size), Lanes.FX_BLACK, false, 4.0)
