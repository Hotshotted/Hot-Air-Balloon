class_name BalloonFlame
extends Node2D
## The burner flame of the game balloon: a child of the swinging basket (it swings with it), redrawn only while it burns.
## Its size and roar follow the burner output; while the burner is lighting it sputters.

var balloon: Balloon

func _draw() -> void:
	if balloon != null:
		draw_set_transform(Vector2(0, -Balloon.BASKET_PIVOT))
		BalloonArt.shared().draw_flame(self, balloon.flame_power, balloon.flicker_time(), balloon.sputter)
