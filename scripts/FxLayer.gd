class_name FxLayer
extends Node2D
## The pooled sparks (square bursts). Redrawn only while some spark is alive.

var lanes: Lanes
var _was_live := false
var draws := 0

func tick() -> void:
	var live := false
	for f in Lanes.FX_MAX:
		if lanes.fx_life[f] > 0.0:
			live = true
			break
	for r in Lanes.RING_MAX:
		if lanes.rg_age[r] >= 0.0:
			live = true
			break
	if live or _was_live:
		queue_redraw()
	_was_live = live

func _draw() -> void:
	draws += 1
	for f in Lanes.FX_MAX:
		if lanes.fx_life[f] > 0.0:
			draw_rect(Rect2(lanes.fx_x[f] - 5.0, lanes.fx_y[f] - 5.0, 10.0, 10.0), lanes.fx_col[f])
	for r in Lanes.RING_MAX:
		if lanes.rg_age[r] >= 0.0:
			var k: float = lanes.rg_age[r] / lanes.rg_life[r]
			var e := 1.0 - pow(1.0 - k, 3.0)
			var col: Color = lanes.rg_col[r]
			var p := Vector2(lanes.rg_x[r], lanes.rg_y[r])
			var rad: float = lanes.rg_max[r] * e
			draw_arc(p, rad, 0.0, TAU, 28, Color(0, 0, 0, 1.0 - k), 12.0 * (1.0 - k) + 2.0)
			draw_arc(p, rad, 0.0, TAU, 28, Color(col.r, col.g, col.b, 1.0 - k), 7.0 * (1.0 - k) + 1.0)
