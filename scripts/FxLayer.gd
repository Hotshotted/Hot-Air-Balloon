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
	if live or _was_live:
		queue_redraw()
	_was_live = live

func _draw() -> void:
	draws += 1
	for f in Lanes.FX_MAX:
		if lanes.fx_life[f] > 0.0:
			draw_rect(Rect2(lanes.fx_x[f] - 5.0, lanes.fx_y[f] - 5.0, 10.0, 10.0), lanes.fx_col[f])
