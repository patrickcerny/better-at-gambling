class_name VoteRaceSet
extends Control
## Warm spotlights over the Vote Race cards (the 3D set behind them is `VoteRaceTrack`): a soft
## cone from the rig onto each card in `spots` (the leader while voting, the racers who step
## forward at the reveal, the winner at the end). Drawn, no assets.

const LIGHT: Color = Color("#FFE2A0")

## Card rects in this control's coordinates that get a spotlight.
var spots: Array[Rect2] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_spots(rects: Array[Rect2]) -> void:
	if rects == spots:
		return
	spots = rects
	queue_redraw()


func _draw() -> void:
	# A soft shade from the top so the marquee and cards sit off the curtain behind.
	_vgrad(Rect2(0, 0, size.x, size.y * 0.55), Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.0))
	# Spotlights: a soft cone from the rig above and a warm pool on the floor.
	for r: Rect2 in spots:
		var cx: float = r.get_center().x
		var top_w: float = r.size.x * 0.18
		var bot_w: float = r.size.x * 0.85
		var bot_y: float = r.end.y + 26.0
		var cone := PackedVector2Array([Vector2(cx - top_w, -10), Vector2(cx + top_w, -10), Vector2(cx + bot_w, bot_y), Vector2(cx - bot_w, bot_y)])
		draw_polygon(cone, PackedColorArray([Color(LIGHT, 0.20), Color(LIGHT, 0.20), Color(LIGHT, 0.05), Color(LIGHT, 0.05)]))
		for i: int in 5:
			var k: float = 1.0 - float(i) / 5.0
			_ellipse(Vector2(cx, bot_y - 6.0), Vector2(bot_w * (0.55 + 0.45 * k), 26.0 * (0.55 + 0.45 * k)), Color(LIGHT, 0.06))


func _vgrad(r: Rect2, a: Color, b: Color) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_polygon(pts, PackedColorArray([a, a, b, b]))


func _ellipse(c: Vector2, radii: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i: int in 32:
		var t: float = TAU * float(i) / 32.0
		pts.append(c + Vector2(cos(t) * radii.x, sin(t) * radii.y))
	draw_colored_polygon(pts, color)
