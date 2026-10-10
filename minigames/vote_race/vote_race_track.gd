class_name VoteRaceTrack
extends Control
## The race to the cashier along the bottom of the Vote Race set: a felt runner with a stop per
## step, START on the left and the CASHIER on the right, and a token per racer (their colour and
## initial; yours ringed in gold) standing on their step. Tokens glide when someone steps forward.

const TOKEN_R: float = 15.0
const PER_ROW: int = 4
const DARK: Color = Color("#2A211C")
const BOLD_FONT: Font = preload("res://assets/fonts/BarlowCondensed-ExtraBold.ttf")
const BLACK_FONT: Font = preload("res://assets/fonts/BarlowCondensed-Black.ttf")

var track_length: int = 5
var local_id: int = -1
## player → {steps: int, color: Color, initial: String}.
var racers: Dictionary = {}
## player → the step drawn now (glides to `steps`).
var _shown: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 112)


func set_racer(p: int, steps: int, color: Color, initial: String) -> void:
	racers[p] = {"steps": steps, "color": color, "initial": initial}
	if not _shown.has(p):
		_shown[p] = float(steps)
	queue_redraw()


func _process(delta: float) -> void:
	var moving: bool = false
	for p: int in racers:
		var target: float = float(int(racers[p]["steps"]))
		var cur: float = float(_shown.get(p, target))
		if not is_equal_approx(cur, target):
			_shown[p] = move_toward(cur, target, delta * 2.5)
			moving = true
	if moving:
		queue_redraw()


func _stop_x(i: float) -> float:
	var x0: float = 150.0
	var x1: float = size.x - 170.0
	return lerpf(x0, x1, i / float(maxi(track_length, 1)))


func _draw() -> void:
	var y: float = size.y * 0.5 + 6.0
	var x0: float = _stop_x(0)
	var x1: float = _stop_x(track_length)
	var runner := Rect2(Vector2(x0 - 30, y - 22), Vector2(x1 - x0 + 60, 44))
	draw_rect(runner.grow(4), Palette.WARM_GOLD)
	draw_rect(runner, Palette.FELT_GREEN.darkened(0.15))
	draw_line(Vector2(x0, y), Vector2(x1, y), Color(Palette.WARM_GOLD, 0.5), 2.0)
	for i: int in track_length + 1:
		var sx: float = _stop_x(i)
		draw_circle(Vector2(sx, y), 9.0, Palette.WARM_GOLD if i == track_length else Color(Palette.CREAM, 0.35), true, -1.0, true)
		if i > 0 and i < track_length:
			draw_string(BOLD_FONT, Vector2(sx - 30, y + 46), str(i), HORIZONTAL_ALIGNMENT_CENTER, 60, 20, Color(Palette.CREAM, 0.55))
	draw_string(BLACK_FONT, Vector2(x0 - 150, y + 10), "START", HORIZONTAL_ALIGNMENT_CENTER, 110, 28, Color(Palette.CREAM, 0.7))
	draw_string(BLACK_FONT, Vector2(x1 + 36, y + 10), "CASHIER", HORIZONTAL_ALIGNMENT_CENTER, 130, 30, Palette.VIP_GOLD)
	# Tokens, grouped per stop in rows of four, centred on the stop.
	var groups: Dictionary = {}
	var ids: Array = racers.keys()
	ids.sort()
	for p: int in ids:
		var s: int = int(round(float(_shown.get(p, 0.0))))
		if not groups.has(s):
			groups[s] = []
		(groups[s] as Array).append(p)
	for s: int in groups:
		var g: Array = groups[s]
		for k: int in g.size():
			var p: int = g[k]
			var row: int = floori(float(k) / float(PER_ROW))
			var in_row: int = mini(g.size() - row * PER_ROW, PER_ROW)
			var col: int = k % PER_ROW
			var gx: float = (float(col) - float(in_row - 1) * 0.5) * (TOKEN_R * 2.0 + 4.0)
			if s >= track_length:  # at the cashier the group stands before the sign
				gx -= float(in_row - 1) * 0.5 * (TOKEN_R * 2.0 + 4.0)
			var gy: float = (float(row) - 0.5 * float(floori(float(g.size() - 1) / float(PER_ROW)))) * (TOKEN_R * 2.0 + 2.0)
			var frac: float = float(_shown.get(p, 0.0)) - float(s)
			var cx: float = _stop_x(float(s) + frac) + gx
			var c := Vector2(cx, y + gy - 2.0)
			var r: Dictionary = racers[p]
			var col_c: Color = r["color"]
			draw_circle(c + Vector2(0, 3), TOKEN_R, Color(0, 0, 0, 0.4), true, -1.0, true)
			draw_circle(c, TOKEN_R, col_c, true, -1.0, true)
			draw_circle(c, TOKEN_R, Palette.VIP_GOLD if p == local_id else DARK, false, 3.5 if p == local_id else 2.0, true)
			var ink: Color = DARK if col_c.get_luminance() > 0.45 else Palette.CREAM
			draw_string(BLACK_FONT, c + Vector2(-TOKEN_R, 8), str(r["initial"]), HORIZONTAL_ALIGNMENT_CENTER, TOKEN_R * 2.0, 22, ink)
