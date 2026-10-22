class_name BalloonEnvelope
extends Node2D
## The game balloon's envelope: drawn once per cosmetics change; leans with the wind (its rotation, about the neck) and
## glows / fills with the air's heat through shaders/balloon_env.gdshader (a uniform, no redraw).

var balloon: Balloon

func _draw() -> void:
	if balloon != null:
		balloon.body_draws += 1
		draw_set_transform(Vector2(0, -Balloon.NECK_Y))
		BalloonArt.shared().draw_envelope(self, balloon.env_id, 4.0 / balloon.s())
