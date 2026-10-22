class_name LayerPill
extends Node2D
## The small navy pill at the left edge of a wind layer: chevrons in the wind's direction (one slow, two steady, three fast),
## "calm" when it hardly blows, and "<> n" with a countdown while the layer is about to reverse. Redrawn only when its
## state changes (a reversing layer once a second).

const H := 52.0
var text := ""
var _w := 120.0

## Set from the layer's wind and its reversal countdown (seconds, 0 = steady). Returns without redrawing if nothing changed.
func set_state(wind: float, countdown: int) -> void:
	var t := ""
	if countdown > 0:
		t = "<> %d" % countdown
	else:
		var a := absf(wind)
		if a < 30.0:
			t = "calm"
		else:
			var n := 1 if a < 90.0 else (2 if a < 170.0 else 3)
			t = (">" if wind > 0.0 else "<").repeat(n)
	if t != text:
		text = t
		queue_redraw()

func _draw() -> void:
	var f := Style.font_for("Fredoka", 26)
	_w = 110.0 if text == "calm" else (30.0 + 28.0 * float(text.length()) if not text.begins_with("<>") else 150.0)
	draw_colored_polygon(SvgArt.rrect(0.0, 0.0, _w, H, H * 0.5), Color(0.078, 0.129, 0.239, 0.82))
	if text == "calm":
		draw_string(f, Vector2(0, H * 0.5 + 9.0), "calm", HORIZONTAL_ALIGNMENT_CENTER, _w, 26, Color.WHITE)
	elif text.begins_with("<>"):
		_chevron(Vector2(26.0, H * 0.5), -1.0)
		_chevron(Vector2(50.0, H * 0.5), 1.0)
		draw_string(f, Vector2(70, H * 0.5 + 9.0), text.substr(3), HORIZONTAL_ALIGNMENT_LEFT, 70, 28, Color("ffc933"))
	else:
		var d := 1.0 if text.begins_with(">") else -1.0
		for k in text.length():
			_chevron(Vector2(26.0 + 28.0 * float(k), H * 0.5), d)

func _chevron(c: Vector2, d: float) -> void:
	var pts := PackedVector2Array([c + Vector2(-7.0 * d, -11.0), c + Vector2(7.0 * d, 0.0), c + Vector2(-7.0 * d, 11.0)])
	draw_polyline(pts, Color.WHITE, 5.0, true)
