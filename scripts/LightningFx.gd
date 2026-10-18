class_name LightningFx
extends Node2D
## Periodic lightning: a warning (a white flash, then a blinking column with warning triangles), then the strike
## (a bolt down the column). Draws only while a warning / strike / flash is on; otherwise it costs nothing.

var lanes: Lanes
var draws := 0
var _was_active := false
var _bolt := PackedVector2Array()

func _ready() -> void:
	_bolt.resize(9)

func tick() -> void:
	var active := lanes.lt_on and (lanes.lt_state != 0 or lanes.lt_flash > 0.0)
	if active or _was_active:
		queue_redraw()
	_was_active = active

func _draw() -> void:
	draws += 1
	var L := lanes
	if not L.lt_on:
		return
	var hw := Tuning.lightning_width * 0.5
	if L.lt_flash > 0.0:   # the warning flash: the whole sky blinks
		draw_rect(Rect2(0, 0, Lanes.W, Lanes.H), Color(1, 1, 1, 0.5 * L.lt_flash / 0.18))
	if L.lt_state == 1:   # the warning: a blinking yellow column
		var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)
		draw_rect(Rect2(L.lt_x - hw, Lanes.BAND_TOP - 60.0, hw * 2.0, Lanes.BAND_BOTTOM - Lanes.BAND_TOP + 60.0), Color(1.0, 0.95, 0.3, 0.14 + 0.18 * blink))
		draw_rect(Rect2(L.lt_x - hw, Lanes.BAND_TOP - 60.0, hw * 2.0, Lanes.BAND_BOTTOM - Lanes.BAND_TOP + 60.0), Color(1.0, 0.9, 0.2, 0.9), false, 4.0)
		for ty in [Lanes.BAND_TOP - 30.0, Lanes.BAND_BOTTOM - 40.0]:   # warning triangles at both ends
			draw_colored_polygon(PackedVector2Array([Vector2(L.lt_x, ty - 26.0), Vector2(L.lt_x + 24.0, ty + 18.0), Vector2(L.lt_x - 24.0, ty + 18.0)]), Color(1.0, 0.9, 0.2))
			draw_rect(Rect2(L.lt_x - 3.0, ty - 12.0, 6.0, 16.0), Color.BLACK)
	elif L.lt_state == 2:   # the strike
		draw_rect(Rect2(L.lt_x - hw, 0, hw * 2.0, Lanes.H), Color(1.0, 1.0, 0.85, 0.55))
		for i in 9:
			var jitter := (float((i * 37) % 11) - 5.0) * 7.0 if i > 0 and i < 8 else 0.0
			_bolt[i] = Vector2(L.lt_x + jitter, float(i) * Lanes.BAND_BOTTOM / 8.0)
		draw_polyline(_bolt, Color(0.2, 0.2, 0.4), 16.0)
		draw_polyline(_bolt, Color.WHITE, 8.0)
