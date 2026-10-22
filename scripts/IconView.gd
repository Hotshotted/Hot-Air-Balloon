class_name IconView
extends Control
## One icon of the shared set (scripts/Icons.gd) as a node: drawn when its id or colour changes, never per frame.

var id := ""
var col := Color.WHITE

func _init(icon_id: String = "", px: float = 48.0, color: Color = Color.WHITE) -> void:
	id = icon_id
	col = color
	size = Vector2(px, px)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_icon(icon_id: String) -> void:
	if icon_id != id:
		id = icon_id
		queue_redraw()

func _draw() -> void:
	if id != "":
		Icons.draw(self, id, size * 0.5, minf(size.x, size.y) * 0.5 * 0.92, col)
