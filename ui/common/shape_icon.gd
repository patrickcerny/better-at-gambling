class_name ShapeIcon
extends Control
## A filled ▲ ● ■ ◆ drawn in code (quiz answers, colourblind-safe: shape and colour both differ).

enum Shape { TRIANGLE, CIRCLE, SQUARE, DIAMOND }

@export var shape: Shape = Shape.TRIANGLE:
	set(v):
		shape = v
		queue_redraw()
@export var color: Color = Color.WHITE:
	set(v):
		color = v
		queue_redraw()


func _init(p_shape: Shape = Shape.TRIANGLE, p_color: Color = Color.WHITE) -> void:
	shape = p_shape
	color = p_color
	custom_minimum_size = Vector2(36, 36)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.5
	var c: Vector2 = size * 0.5
	match shape:
		Shape.TRIANGLE:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.95, r * 0.75), c + Vector2(-r * 0.95, r * 0.75)]), color)
		Shape.CIRCLE:
			draw_circle(c, r * 0.9, color)
		Shape.SQUARE:
			draw_rect(Rect2(c - Vector2(r, r) * 0.8, Vector2(r, r) * 1.6), color)
		Shape.DIAMOND:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), color)
