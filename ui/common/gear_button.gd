class_name GearButton
extends Button
## The small settings button: a cog drawn in code (no image asset) on a plain square button. It
## sits in a corner (bottom right of the main menu and of the pause menu) and turns gold on hover
## and focus like every other button.

const SIZE: float = 64.0
const TEETH: int = 8


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	tooltip_text = "Settings"
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _notification(what: int) -> void:
	if what in [NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT, NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT]:
		queue_redraw()


func _draw() -> void:
	var hot: bool = has_focus() or is_hovered() or button_pressed
	var col: Color = Palette.VIP_GOLD if hot else Palette.CREAM
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5
	var outer: float = r * 0.66
	var inner: float = r * 0.5
	var pts := PackedVector2Array()
	# Each tooth: a flat top at `outer`, flanks down to `inner` between teeth.
	for i: int in TEETH:
		var a: float = TAU * float(i) / float(TEETH)
		var half: float = TAU / float(TEETH) * 0.22
		var gap: float = TAU / float(TEETH) * 0.24
		pts.append(c + Vector2.from_angle(a - half - gap) * inner)
		pts.append(c + Vector2.from_angle(a - half) * outer)
		pts.append(c + Vector2.from_angle(a + half) * outer)
		pts.append(c + Vector2.from_angle(a + half + gap) * inner)
	draw_colored_polygon(pts, col)
	draw_circle(c, inner * 0.98, col)
	draw_circle(c, r * 0.2, Palette.CASINO_BLACK)
