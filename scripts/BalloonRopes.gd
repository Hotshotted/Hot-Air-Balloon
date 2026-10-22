class_name BalloonRopes
extends Node2D
## The four ropes between the envelope and the basket: drawn every frame while the balloon moves (it is the envelope's lean
## and the basket's swing that bend them). One line per side, nothing allocated.

var balloon: Balloon

func _draw() -> void:
	if balloon == null:
		return
	var le := balloon.lean
	var sw := balloon.swing
	for sx in [-1.0, 1.0]:
		var top := Vector2(10.0 * sx, 52.0 - Balloon.NECK_Y).rotated(le) + Vector2(0, Balloon.NECK_Y)
		var bot := Vector2(9.0 * sx, 68.0 - Balloon.BASKET_PIVOT).rotated(sw) + Vector2(0, Balloon.BASKET_PIVOT)
		draw_line(top, bot, BalloonArt.ROPE, 1.6, true)
