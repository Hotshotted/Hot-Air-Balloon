class_name BalloonFlame
extends Node2D
## The burner flame of the game balloon: a separate node so the (much bigger) balloon body is not redrawn every frame.

var balloon: Balloon

func _draw() -> void:
	if balloon != null:
		BalloonArt.shared().draw_flame(self, balloon.heat, balloon.flicker_time())
