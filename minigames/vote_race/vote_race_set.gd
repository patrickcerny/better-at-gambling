class_name VoteRaceSet
extends Control
## The Vote Race game-show set behind the cards: a wine velvet backdrop with pleats, a dark stage
## floor with a gold edge and warm spotlights falling on the cards in `spots` (the leader while
## voting, the racers who step forward at the reveal, the winner at the end). Drawn, no assets.

const TOP: Color = Color("#2B0D14")
const BOTTOM: Color = Color("#150B0C")
const FLOOR: Color = Color("#1B1210")
const LIGHT: Color = Color("#FFE2A0")
const PLEAT_W: float = 96.0

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
	var w: float = size.x
	var h: float = size.y
	var floor_y: float = h * 0.8
	# Velvet backdrop: a dark-to-darker gradient with soft vertical pleats.
	_vgrad(Rect2(0, 0, w, floor_y), TOP, BOTTOM)
	var x: float = 0.0
	while x < w:
		var pts := PackedVector2Array([Vector2(x, 0), Vector2(x + PLEAT_W * 0.5, 0), Vector2(x + PLEAT_W * 0.5, floor_y), Vector2(x, floor_y)])
		var lit := Color(Palette.VIP_BURGUNDY, 0.28)
		var dark := Color(0, 0, 0, 0.0)
		draw_polygon(pts, PackedColorArray([dark, lit, lit, dark]))
		var pts2 := PackedVector2Array([Vector2(x + PLEAT_W * 0.5, 0), Vector2(x + PLEAT_W, 0), Vector2(x + PLEAT_W, floor_y), Vector2(x + PLEAT_W * 0.5, floor_y)])
		draw_polygon(pts2, PackedColorArray([lit, dark, dark, lit]))
		x += PLEAT_W
	# Stage floor with a gold lip.
	_vgrad(Rect2(0, floor_y, w, h - floor_y), FLOOR, Palette.CASINO_BLACK)
	draw_rect(Rect2(0, floor_y - 3, w, 4), Palette.WARM_GOLD)
	draw_rect(Rect2(0, floor_y + 1, w, 2), Color(Palette.WARM_GOLD, 0.25))
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
