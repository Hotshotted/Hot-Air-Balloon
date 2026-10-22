class_name BalloonBasket
extends Node2D
## The game balloon's burner, passenger and basket: drawn once per cosmetics change; it swings on its ropes (its
## rotation, about the rope attachment). Its children (flame, streamers) swing with it.

var balloon: Balloon

func _draw() -> void:
	if balloon != null:
		balloon.body_draws += 1
		draw_set_transform(Vector2(0, -Balloon.BASKET_PIVOT))
		BalloonArt.shared().draw_basket(self, balloon.basket_id, 0, 4.0 / balloon.s())
