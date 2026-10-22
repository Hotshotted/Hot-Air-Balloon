class_name BackdropFront
extends Node2D
## What stands in front of the parallax ridges: layered rolling hills with a sandy launch pad, the scenery, the cables, the
## mooring platforms and the goal line (colourful bunting strung across the top). Flat shapes, no outlines.
## Drawn ONCE when a leg is set up (redraw()), never per frame.

const BUNTING := [Color("ff5c4d"), Color("ffc933"), Color("3d8bff"), Color("35c98a")]
var lanes: Lanes
var draws := 0

func redraw() -> void:
	queue_redraw()

## A closed rolling-hill polygon: crest around `y0` (amplitude `amp`, wavelength `wl`), down to the bottom of the screen.
func _hill(y0: float, amp: float, wl: float, ph: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 46:
		var x := -20.0 + float(k) * 25.0
		pts.append(Vector2(x, y0 + sin(x / wl * TAU + ph) * amp + sin(x / wl * TAU * 2.3 + ph * 1.9) * amp * 0.3))
	pts.append(Vector2(Lanes.W + 40.0, Lanes.H))
	pts.append(Vector2(-40.0, Lanes.H))
	return pts

func _draw() -> void:
	draws += 1
	var L := lanes
	var r := L.region
	var gy := Lanes.GROUND_Y
	draw_polygon(PackedVector2Array([Vector2(0, gy - 240.0), Vector2(Lanes.W, gy - 240.0), Vector2(Lanes.W, gy), Vector2(0, gy)]), PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.28), Color(1, 1, 1, 0.28)]))   # a soft morning mist over the ridges
	draw_colored_polygon(_hill(gy - 6.0, 22.0, 720.0, 0.8), L.tinted(Regions.GROUND[r], gy))
	_scenery(L, r, gy)
	draw_colored_polygon(_hill(gy + 52.0, 18.0, 520.0, 3.4), L.tinted(Regions.GROUND2[r], gy + 60.0))
	draw_colored_polygon(SvgArt.rrect(450.0, gy - 12.0, 180.0, 28.0, 14.0), L.tinted(Color("d9c48a"), gy))   # the sandy launch pad
	for i in L.n_lanes:   # the cables the cable cars hang from
		if L.lane_kind[i] == Lanes.CABLE:
			var cy := L._lane_cy(i) - HazardMeshes.GONDOLA_TOP * L.lane_scale[i]
			draw_line(Vector2(0, cy), Vector2(Lanes.W, cy), Color("3a3f4a"), 5.0, true)
	if L.goal == Flights.DELIVERY:   # the two mooring platforms: green flag = pick up the mail, red flag = drop it off
		for which in 2:
			var dp := L.dock_pos(which)
			var flag := Color("35c98a") if which == 0 else Color("ff5c4d")
			draw_colored_polygon(SvgArt.rrect(dp.x - 90.0, dp.y + 26.0, 180.0, 22.0, 8.0), Color("b98f55"))
			draw_rect(Rect2(dp.x - 64.0, dp.y + 48.0, 8.0, 22.0), Color("7d5c2e"))
			draw_rect(Rect2(dp.x + 56.0, dp.y + 48.0, 8.0, 22.0), Color("7d5c2e"))
			if which == 0:   # the mail sack waiting to be picked up
				draw_colored_polygon(SvgArt.rrect(dp.x - 66.0, dp.y - 22.0, 64.0, 48.0, 10.0), Color.WHITE)
				draw_polyline(PackedVector2Array([Vector2(dp.x - 66.0, dp.y - 20.0), Vector2(dp.x - 34.0, dp.y + 4.0), Vector2(dp.x - 2.0, dp.y - 20.0)]), Color(0.039, 0.063, 0.125, 0.8), 4.0, true)
			draw_line(Vector2(dp.x + 56.0, dp.y + 26.0), Vector2(dp.x + 56.0, dp.y - 40.0), Color("3a3f4a"), 5.0, true)
			draw_colored_polygon(PackedVector2Array([Vector2(dp.x + 58.0, dp.y - 40.0), Vector2(dp.x + 104.0, dp.y - 28.0), Vector2(dp.x + 58.0, dp.y - 16.0)]), flag)
	if L.goal != Flights.LANDING:   # the airship is the goal there; otherwise colourful bunting across the top
		_bunting(L)

func _scenery(L: Lanes, r: int, gy: float) -> void:
	match r:
		0, 1:
			for tx in [110.0, 250.0, 860.0, 980.0]:
				var tall := 78.0 if r == 1 else 56.0
				if r == 0:
					draw_rect(Rect2(tx - 5.0, gy - 40.0, 10.0, 40.0), L.tinted(Color("6b4423"), gy))
					draw_circle(Vector2(tx, gy - 64.0), 34.0, L.tinted(Color("3e8a48"), gy))
					draw_circle(Vector2(tx + 14.0, gy - 54.0), 24.0, L.tinted(Color("56a65a"), gy))
				else:
					draw_colored_polygon(PackedVector2Array([Vector2(tx - 30, gy - 6), Vector2(tx, gy - tall - 40.0), Vector2(tx + 30, gy - 6)]), L.tinted(Color("2f7d58"), gy))
					draw_colored_polygon(PackedVector2Array([Vector2(tx - 20, gy - 40), Vector2(tx, gy - tall - 52.0), Vector2(tx + 20, gy - 40)]), L.tinted(Color("3c9468"), gy))
		2:
			for cx in [170.0, 800.0]:
				var cc := L.tinted(Color("4c9a5a"), gy)
				draw_colored_polygon(SvgArt.rrect(cx - 12.0, gy - 90.0, 24.0, 92.0, 12.0), cc)
				draw_colored_polygon(SvgArt.rrect(cx + 8.0, gy - 66.0, 30.0, 14.0, 7.0), cc)
				draw_colored_polygon(SvgArt.rrect(cx + 26.0, gy - 90.0, 14.0, 38.0, 7.0), cc)
		3:
			for fx in [120.0, 240.0, 900.0]:   # prayer-flag poles
				draw_line(Vector2(fx, gy - 4.0), Vector2(fx, gy - 120.0), L.tinted(Color("e9edf6"), gy), 6.0, true)
				draw_colored_polygon(PackedVector2Array([Vector2(fx, gy - 120.0), Vector2(fx + 50.0, gy - 106.0), Vector2(fx, gy - 92.0)]), L.tinted(BUNTING[int(fx) % 4], gy))

## The goal line: bunting sagging across the top, a pennant every 90 px in red, gold, blue and green.
func _bunting(L: Lanes) -> void:
	var y0 := Lanes.GOAL_Y - 40.0
	var string := PackedVector2Array()
	for k in 28:
		var x := float(k) * 40.0
		string.append(Vector2(x, y0 + sin(x / Lanes.W * PI) * 34.0))
	draw_polyline(string, Color(0.039, 0.063, 0.125, 0.8), 4.0, true)
	for k in 12:
		var x2 := 40.0 + float(k) * 90.0
		var ys := y0 + sin(x2 / Lanes.W * PI) * 34.0
		draw_colored_polygon(PackedVector2Array([Vector2(x2 - 24.0, ys), Vector2(x2 + 24.0, ys + 4.0), Vector2(x2 + 2.0, ys + 62.0)]), BUNTING[k % 4])
