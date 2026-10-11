class_name SpyClock
extends Control
## The Spy game clock: a dark brass-rimmed dial with the time the spies still have to survive as
## a gold arc (red in the last 20 s) and big digits in the middle. Drawn, no assets.

const BLACK_FONT: Font = preload("res://assets/fonts/BarlowCondensed-Black.ttf")
const BOLD_FONT: Font = preload("res://assets/fonts/BarlowCondensed-ExtraBold.ttf")
const LOW: float = 20.0

var total: float = 120.0
var left: float = 120.0
## Not counting (reveal, briefing): the digits dim.
var paused: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(220, 220)


func set_time(p_left: float, p_total: float, p_paused: bool) -> void:
	left = maxf(p_left, 0.0)
	total = maxf(p_total, 1.0)
	paused = p_paused
	queue_redraw()


static func format(seconds: float) -> String:
	var s: int = ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [s / 60, s % 60]


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5 - 6.0
	var low: bool = left <= LOW
	draw_circle(c + Vector2(0, 6), r + 4.0, Color(0, 0, 0, 0.45), true, -1.0, true)
	draw_circle(c, r + 4.0, Palette.WARM_GOLD.darkened(0.25), true, -1.0, true)
	draw_circle(c, r, Palette.VIP_BURGUNDY.darkened(0.55), true, -1.0, true)
	# Ticks every 1/12 of the dial.
	for i: int in 12:
		var a: float = TAU * float(i) / 12.0 - PI * 0.5
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (r - 6.0), c + d * (r - 16.0), Color(Palette.CREAM, 0.35), 3.0, true)
	var frac: float = clampf(left / total, 0.0, 1.0)
	draw_arc(c, r - 26.0, 0.0, TAU, 64, Color(0, 0, 0, 0.35), 14.0, true)
	if frac > 0.0:
		var col: Color = Palette.CASINO_RED if low else Palette.WARM_GOLD
		draw_arc(c, r - 26.0, -PI * 0.5, -PI * 0.5 + TAU * frac, maxi(int(64.0 * frac), 2), col, 14.0, true)
	var digits: String = format(left)
	var fs: int = int(r * 0.62)
	var ink: Color = Palette.CREAM if not low else Palette.LOSS_RED.lightened(0.2)
	if paused:
		ink = Color(ink, 0.6)
	draw_string(BLACK_FONT, Vector2(c.x - r, c.y + fs * 0.32), digits, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, ink)
	draw_string(BOLD_FONT, Vector2(c.x - r, c.y - fs * 0.48), "SPIES SAFE", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 19, Color(Palette.WARM_GOLD, 0.9))
	draw_string(BOLD_FONT, Vector2(c.x - r, c.y + fs * 0.32 + 30.0), "PAUSED" if paused else "GAME CLOCK", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 17, Color(Palette.CREAM, 0.55))
