class_name LockIcon
extends Control
## A small padlock (body + shackle) drawn in code: marks a shop piece you can't get yet (too few
## Coins or level not reached), so its picture can stay bright (Patrick 2026-11-16: "warum ist der
## mund ausgegraut").

var color: Color = Color("#E9DCBC")


static func make(px: float = 22.0) -> LockIcon:
	var l := LockIcon.new()
	l.custom_minimum_size = Vector2(px, px)
	l.size = l.custom_minimum_size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	var body := Rect2(Vector2(s * 0.14, s * 0.44), Vector2(s * 0.72, s * 0.52))
	# A dark disc behind, so it reads on any picture.
	draw_circle(Vector2(s, s) * 0.5, s * 0.62, Color(0.08, 0.05, 0.04, 0.75))
	draw_arc(Vector2(s * 0.5, s * 0.44), s * 0.22, PI, TAU, 16, color, maxf(s * 0.1, 2.0), true)
	draw_line(Vector2(s * 0.28, s * 0.44), Vector2(s * 0.28, s * 0.5), color, maxf(s * 0.1, 2.0))
	draw_line(Vector2(s * 0.72, s * 0.44), Vector2(s * 0.72, s * 0.5), color, maxf(s * 0.1, 2.0))
	draw_rect(body, color)
	draw_circle(body.get_center() - Vector2(0, s * 0.03), s * 0.06, Color(0.08, 0.05, 0.04))
