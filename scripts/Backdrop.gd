class_name Backdrop
extends Node2D
## The sky that never moves during a leg: a slightly different tone for every wind layer (lighter toward the ground), soft
## wavy white cloud seams between them, and the sun or stars. Storybook Sky: no flat bands with black lines. BackdropFront draws
## the hills, the bunting and the cables over the parallax ridges. Drawn ONCE when a leg is set up (redraw()), never per frame.

var lanes: Lanes
var draws := 0          # how many times it has been drawn (a leg start redraws it; play must not)
var front: BackdropFront
var parallax: ParallaxBack

func redraw() -> void:
	queue_redraw()
	if parallax != null:
		parallax.redraw()
	if front != null:
		front.redraw()

func _draw() -> void:
	draws += 1
	var L := lanes
	var r := L.region
	var n := L.n_lanes
	var c_low: Color = Regions.SKY_LOW[r]
	var c_mid: Color = Regions.SKY_MID[r]
	var c_high: Color = Regions.SKY_HIGH[r]
	draw_rect(Rect2(0, 0, Lanes.W, Lanes.BAND_TOP + 1.0), L.tinted(Regions.SKY_TOP[r], Lanes.BAND_TOP * 0.5))
	draw_rect(Rect2(0, Lanes.BAND_BOTTOM - 1.0, Lanes.W, Lanes.H - Lanes.BAND_BOTTOM + 1.0), L.tinted(c_low, Lanes.BAND_BOTTOM + 100.0))
	for i in n:
		var t := (float(i) + 0.5) / float(n)   # 0 = the lowest layer
		var col := c_low.lerp(c_mid, minf(t * 2.0, 1.0)) if t < 0.5 else c_mid.lerp(c_high, (t - 0.5) * 2.0)
		draw_rect(Rect2(0, Lanes.BAND_BOTTOM - float(i + 1) * L.lane_h, Lanes.W, L.lane_h + 1.0), L.tinted(col, Lanes.BAND_BOTTOM - (float(i) + 0.5) * L.lane_h))
	if r == 3:   # Himalayas at dusk: the first stars
		var seed_v := 17
		for k in 40:
			seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
			var sx := float(seed_v % 1080)
			seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
			var sy := 40.0 + float(seed_v % 900)
			draw_circle(Vector2(sx, sy), 2.0 + float(k % 3), Color(1, 1, 1, 0.55 + 0.04 * float(k % 8)))
	if r == 2:   # the Sahara noon sun
		draw_circle(Vector2(860, 560), 150.0, Color(1.0, 0.95, 0.78, 0.35))
		draw_circle(Vector2(860, 560), 96.0, Color("fff1c8"))
	var seam_pts := PackedVector2Array()
	for i in range(1, n):   # the soft wavy white seams between layers
		var y0 := Lanes.BAND_BOTTOM - float(i) * L.lane_h
		seam_pts.clear()
		for k in 48:
			var x := -20.0 + float(k) * 24.0
			seam_pts.append(Vector2(x, y0 + sin(x / 300.0 * TAU + float(i) * 1.7) * 14.0))
		draw_polyline(seam_pts, Color(1, 1, 1, 0.45), 14.0, true)
