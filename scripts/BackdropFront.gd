class_name BackdropFront
extends Node2D
## The scenery in front of the parallax ridges: trees, cacti, ground, launch pad, cables, mooring platforms and the goal strip.
## Drawn ONCE when a leg is set up (redraw()), never per frame.

var lanes: Lanes
var draws := 0

func redraw() -> void:
	queue_redraw()

func _draw() -> void:
	draws += 1
	var L := lanes
	for s in L._scn[L.region]:
		draw_colored_polygon(s[0], L.tinted(s[2], Lanes.GROUND_Y - 40.0))
		draw_polyline(s[1], Lanes.FX_BLACK, 4.0)
	for i in L.n_lanes:   # the cables the cable cars hang from
		if L.lane_kind[i] == Lanes.CABLE:
			var cy := L._lane_cy(i) - 44.0 * L.lane_scale[i]
			draw_line(Vector2(0, cy), Vector2(Lanes.W, cy), Lanes.FX_BLACK, 5.0)
	if L.goal == Flights.DELIVERY:   # the two mooring platforms: green flag = pick up the mail, red flag = drop it off
		for which in 2:
			var dp := L.dock_pos(which)
			var flag := Color(0.3, 0.8, 0.4) if which == 0 else Color(0.9, 0.3, 0.3)
			draw_rect(Rect2(dp.x - 80.0, dp.y + 26.0, 160.0, 16.0), Color(0.62, 0.42, 0.22))
			draw_rect(Rect2(dp.x - 80.0, dp.y + 26.0, 160.0, 16.0), Lanes.FX_BLACK, false, 4.0)
			draw_line(Vector2(dp.x - 60.0, dp.y + 42.0), Vector2(dp.x - 60.0, dp.y + 62.0), Lanes.FX_BLACK, 5.0)
			draw_line(Vector2(dp.x + 60.0, dp.y + 42.0), Vector2(dp.x + 60.0, dp.y + 62.0), Lanes.FX_BLACK, 5.0)
			draw_line(Vector2(dp.x + 50.0, dp.y + 26.0), Vector2(dp.x + 50.0, dp.y - 34.0), Lanes.FX_BLACK, 5.0)
			draw_rect(Rect2(dp.x + 50.0, dp.y - 34.0, 34.0, 22.0), flag)
			draw_rect(Rect2(dp.x + 50.0, dp.y - 34.0, 34.0, 22.0), Lanes.FX_BLACK, false, 3.0)
			draw_rect(Rect2(dp.x - 40.0, dp.y + 6.0, 36.0, 20.0), Color.WHITE)   # a letter
			draw_rect(Rect2(dp.x - 40.0, dp.y + 6.0, 36.0, 20.0), Lanes.FX_BLACK, false, 3.0)
			draw_line(Vector2(dp.x - 40.0, dp.y + 6.0), Vector2(dp.x - 22.0, dp.y + 18.0), Lanes.FX_BLACK, 3.0)
			draw_line(Vector2(dp.x - 4.0, dp.y + 6.0), Vector2(dp.x - 22.0, dp.y + 18.0), Lanes.FX_BLACK, 3.0)
	# The goal strip: two rows of black and white squares.
	if L.goal == Flights.LANDING:   # the airship is the goal here, not the strip
		return
	var size := 34.0
	for row in 2:
		for c in int(Lanes.W / size) + 1:
			var col2 := Lanes.FX_BLACK if (c + row) % 2 == 0 else Color.WHITE
			draw_rect(Rect2(float(c) * size, Lanes.GOAL_Y - 2.0 * size + float(row) * size, size, size), col2)
	draw_rect(Rect2(0, Lanes.GOAL_Y - 2.0 * size, Lanes.W, 2.0 * size), Lanes.FX_BLACK, false, 4.0)
