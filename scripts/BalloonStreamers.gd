class_name BalloonStreamers
extends Node2D
## Two ribbons on the basket's rim that show the wind at the balloon's exact altitude: they fly downwind and are longer and
## stiffer the faster it blows, limp in a layer at rest. Redrawn every frame (two short polylines).

const PTS := 6
var balloon: Balloon
var _pts := PackedVector2Array()
var _pts2 := PackedVector2Array()

func _ready() -> void:
	_pts.resize(PTS)
	_pts2.resize(PTS)

func _draw() -> void:
	if balloon == null:
		return
	var w := balloon.wind_alt
	var d := 1.0 if w >= 0.0 else -1.0
	var strength := clampf(absf(w) / 200.0, 0.0, 1.0)
	var length := 8.0 + 34.0 * strength
	var t := balloon.flicker_time()
	for k in 2:
		var base := Vector2((-14.0 if k == 0 else 14.0), 65.0 - Balloon.BASKET_PIVOT)
		for i in PTS:
			var u := float(i) / float(PTS - 1)
			var flutter := sin(t * (7.0 + 5.0 * strength) - u * 5.0 + float(k) * 1.7) * (1.0 + 4.0 * strength) * u
			# stiff and level in a strong wind, drooping in a weak one
			var droop := (1.0 - strength) * 12.0 * u * u
			var p := base + Vector2(d * length * u, droop + flutter)
			if k == 0:
				_pts[i] = p
			else:
				_pts2[i] = p
	draw_polyline(_pts, Color("ff5c4d"), 3.0, true)
	draw_polyline(_pts2, Color("ffc933"), 3.0, true)
