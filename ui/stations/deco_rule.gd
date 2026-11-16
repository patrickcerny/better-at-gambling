class_name DecoRule
extends Control
## A brass rule that fades out towards one end and ends in a diamond (the title's and captions'
## flourishes): `toward_right` = the diamond on the left, the line fading off to the right.

var toward_right: bool = true
var color: Color = TableSkin.BRASS


func _init(p_toward_right: bool = true, width: float = 60.0) -> void:
	toward_right = p_toward_right
	custom_minimum_size = Vector2(width, 14)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var y: float = size.y * 0.5
	var w: float = size.x
	var steps: int = 12
	for i: int in steps:
		var t0: float = float(i) / steps
		var t1: float = float(i + 1) / steps
		var fade: float = 1.0 - t0 if toward_right else t1
		var x0: float = lerpf(8.0, w, t0) if toward_right else lerpf(0.0, w - 8.0, t0)
		var x1: float = lerpf(8.0, w, t1) if toward_right else lerpf(0.0, w - 8.0, t1)
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(color, 0.15 + 0.85 * fade), 1.5, true)
	var dx: float = 4.0 if toward_right else w - 4.0
	TableSkin.diamond(self, Vector2(dx, y), 4.0, color)
