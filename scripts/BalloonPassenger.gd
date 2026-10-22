class_name BalloonPassenger
extends Node2D
## The game balloon's passenger: looks around, cheers on a landing, droops on a crash. It sits behind the basket's front
## and redraws only when its (quantised) pose changes, a few times a second at most.

var balloon: Balloon
var _key := -1

func _ready() -> void:
	show_behind_parent = true

func _draw() -> void:
	if balloon != null and balloon.pass_id > 0:
		draw_set_transform(Vector2(0, -Balloon.BASKET_PIVOT))
		BalloonArt.shared().draw_passenger(self, balloon.pass_id, 4.0 / balloon.s(), balloon.pass_look, balloon.pass_cheer, balloon.pass_sad)

## Called every frame with the pose; redraws when it moved to another quantised step.
func pose_changed() -> void:
	var k := int(roundf(balloon.pass_look * 4.0)) + 8 + 20 * int(roundf(balloon.pass_cheer * 8.0)) + 400 * int(roundf(balloon.pass_sad * 4.0)) + 4000 * balloon.pass_id
	if k != _key:
		_key = k
		queue_redraw()
