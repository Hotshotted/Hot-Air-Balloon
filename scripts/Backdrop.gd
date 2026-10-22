class_name Backdrop
extends Node2D
## The sky that never moves during a leg: a slightly different tone for every wind layer (lighter toward the ground) blended into
## one gradient, small tick marks at the screen edges where the layers meet, and the sun or stars. Storybook Sky: no flat bands with black lines. BackdropFront draws
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
	# One sky gradient: each layer has its own tone (lighter toward the ground) and the tones blend smoothly into each other over a
	# short band around every boundary: no hard seams, no divider lines.
	var cols: Array = [L.tinted(Regions.SKY_TOP[r], Lanes.BAND_TOP * 0.5)]
	for k in n:   # from the top layer down
		var i := n - 1 - k
		var t := (float(i) + 0.5) / float(n)   # 0 = the lowest layer
		var col := c_low.lerp(c_mid, minf(t * 2.0, 1.0)) if t < 0.5 else c_mid.lerp(c_high, (t - 0.5) * 2.0)
		cols.append(L.tinted(col, Lanes.BAND_BOTTOM - (float(i) + 0.5) * L.lane_h))
	cols.append(cols[n])
	var bh := minf(L.lane_h * 0.26, 46.0)   # half the height of a blend band
	var y_prev := 0.0
	for k in n + 1:   # the boundary k lies between cols[k] and cols[k+1]
		var yb := Lanes.BAND_TOP + float(k) * L.lane_h
		var c0: Color = cols[k]
		var c1: Color = cols[k + 1]
		draw_rect(Rect2(0, y_prev, Lanes.W, yb - bh - y_prev + 1.0), c0)
		draw_polygon(PackedVector2Array([Vector2(0, yb - bh), Vector2(Lanes.W, yb - bh), Vector2(Lanes.W, yb + bh), Vector2(0, yb + bh)]), PackedColorArray([c0, c0, c1, c1]))
		y_prev = yb + bh
	draw_rect(Rect2(0, y_prev, Lanes.W, Lanes.H - y_prev), cols[n + 1])
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
	for i in range(1, n):   # small tick marks at both screen edges: where one layer ends and the next begins
		var yt := Lanes.BAND_BOTTOM - float(i) * L.lane_h
		draw_colored_polygon(SvgArt.rrect(0.0, yt - 5.0, 46.0, 10.0, 5.0), Color(1, 1, 1, 0.85))
		draw_colored_polygon(SvgArt.rrect(Lanes.W - 46.0, yt - 5.0, 46.0, 10.0, 5.0), Color(1, 1, 1, 0.85))
