class_name TrophyButton
extends GearButton
## The leaderboards button (Patrick 2026-11-16: global leaderboards and your own stats, "unten
## rechts"): the gear's square button with a trophy cup drawn in code instead of the cog. Sits in
## the main menu's bottom-right row and opens the `LeaderboardPanel`.


func _init() -> void:
	super()
	tooltip_text = "Leaderboards & stats"


func _draw() -> void:
	var hot: bool = has_focus() or is_hovered() or button_pressed
	var col: Color = Palette.VIP_GOLD if hot else Palette.CREAM
	var c: Vector2 = size * 0.5
	var s: float = minf(size.x, size.y) * 0.5 * 0.72
	# The cup: a bowl narrowing to the stem (unit coordinates, y down, about -1..1).
	var bowl := PackedVector2Array()
	bowl.append(c + Vector2(-0.62, -0.78) * s)
	bowl.append(c + Vector2(0.62, -0.78) * s)
	for i: int in range(0, 9):
		var a: float = PI * float(i) / 8.0  # right rim down round to the left rim
		bowl.append(c + Vector2(cos(a) * 0.62, -0.42 + sin(a) * 0.62) * s)
	draw_colored_polygon(bowl, col)
	# Handles.
	var w: float = maxf(s * 0.13, 2.0)
	draw_arc(c + Vector2(-0.62, -0.42) * s, 0.26 * s, PI * 0.5, PI * 1.5, 16, col, w, true)
	draw_arc(c + Vector2(0.62, -0.42) * s, 0.26 * s, -PI * 0.5, PI * 0.5, 16, col, w, true)
	# Stem and base.
	draw_rect(Rect2(c + Vector2(-0.1, 0.18) * s, Vector2(0.2, 0.42) * s), col)
	draw_rect(Rect2(c + Vector2(-0.44, 0.6) * s, Vector2(0.88, 0.22) * s), col)
