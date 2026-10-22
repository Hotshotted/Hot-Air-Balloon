class_name Backdrop
extends Node2D
## Everything in the sky that never moves during a leg: the layer bands and the sun (BackdropFront draws the scenery, the goal
## strip and the cables over the parallax ridges). Drawn ONCE when a leg is set up (redraw()), never per frame.

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
	if L.region == 2:   # the Sahara sun
		var sun := Lanes._octagon(Vector2(880, 1500), 70.0, 70.0)
		draw_colored_polygon(PackedVector2Array(sun), Color(1.0, 0.84, 0.3))
		sun.append(sun[0])
		draw_polyline(PackedVector2Array(sun), Lanes.FX_BLACK, 4.0)
