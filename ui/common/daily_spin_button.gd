class_name DailySpinButton
extends Button
## The Daily Spin's big button on the main menu (Patrick 2026-11-16: "the wheel is always also a
## button on the bottom right, very highlighted (like super mega) when it's available", the size of
## the three small buttons together, above them). A little prize wheel drawn in code: while a spin
## is free it turns, glows and pulses, its bulbs race, sparkles circle it and a gold SPIN! plaque
## bounces under it; otherwise it rests, dimmed, with the time to the next spin.

## Width and height: the three small corner buttons and their two gaps.
const SIZE: float = GearButton.SIZE * 3.0 + 32.0

## A spin is free now (`DailySpinPanel.ready_now`).
var spin_ready: bool = false
## "19 H 58 M" while waiting.
var wait_text: String = ""
var _t: float = 0.0
var _turn: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	tooltip_text = "Daily Spin"
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	flat = true
	pivot_offset = Vector2(SIZE, SIZE) * 0.5


## Shows a free spin (super highlighted) or the countdown.
func set_state(is_ready: bool, wait: String) -> void:
	spin_ready = is_ready
	wait_text = wait
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var hot: bool = has_focus() or is_hovered()
	if spin_ready:
		_turn += delta * (2.2 if hot else 1.1)
		var s: float = 1.0 + 0.045 * sin(_t * 4.0) + (0.04 if hot else 0.0)
		scale = Vector2(s, s)
	else:
		_turn += delta * (0.6 if hot else 0.05)
		scale = Vector2.ONE
	queue_redraw()


func _draw() -> void:
	var hot: bool = has_focus() or is_hovered() or button_pressed
	var c: Vector2 = size * 0.5 - Vector2(0, size.y * 0.06)
	var r: float = minf(size.x, size.y) * 0.34
	var gold := Palette.VIP_GOLD
	if spin_ready:
		# Halo: warm glow rings breathing out, rays turning behind the wheel.
		var breathe: float = 0.5 + 0.5 * sin(_t * 4.0)
		for k: int in 6:
			var rr: float = r * (1.25 + 0.12 * float(k) + 0.08 * breathe)
			draw_circle(c, rr, Color(1.0, 0.78, 0.35, 0.07 - 0.009 * float(k)))
		for k: int in 12:
			var a: float = -_t * 0.5 + TAU * float(k) / 12.0
			var d := Vector2.from_angle(a)
			var n := Vector2.from_angle(a + PI * 0.5)
			var tip: Vector2 = c + d * r * (1.75 + 0.1 * breathe)
			draw_colored_polygon(PackedVector2Array([c + d * r * 1.05 + n * r * 0.09, c + d * r * 1.05 - n * r * 0.09, tip]), Color(1.0, 0.85, 0.5, 0.16))
	else:
		draw_circle(c + Vector2(0, r * 0.06), r * 1.18, Color(0, 0, 0, 0.35))
	# Rim with bulbs.
	draw_circle(c, r * 1.16, DailyWheelView.LACQUER)
	draw_arc(c, r * 1.16, 0.0, TAU, 64, gold if (spin_ready or hot) else Color(gold, 0.55), maxf(r * 0.04, 2.0), true)
	for k: int in 16:
		var bp: Vector2 = c + Vector2.from_angle(TAU * float(k) / 16.0) * r * 1.08
		var lit: bool = (k + int(_t * 10.0)) % 3 == 0 if spin_ready else (k % 4 == 0)
		if lit and spin_ready:
			draw_circle(bp, r * 0.07, Color(DailyWheelView.BULB_ON, 0.3))
		draw_circle(bp, r * 0.035, DailyWheelView.BULB_ON if lit else DailyWheelView.BULB_OFF)
	# The slices.
	var n: int = DailyWheel.count()
	var stp: float = TAU / float(n)
	var cols: Array[Color] = [DailyWheelView.SLICE_CREAM, DailyWheelView.SLICE_FELT, DailyWheelView.SLICE_BURGUNDY]
	for i: int in n:
		var a0: float = _turn + float(i) * stp
		var pts := PackedVector2Array([c])
		for s: int in 7:
			pts.append(c + Vector2.from_angle(a0 + stp * float(s) / 6.0) * r)
		var col: Color = DailyWheelView.SLICE_JACKPOT if i == 7 else cols[i % 3]
		if not spin_ready:
			col = col.darkened(0.35)
		draw_colored_polygon(pts, col)
		draw_line(c, c + Vector2.from_angle(a0) * r, Color(gold, 0.9 if spin_ready else 0.5), maxf(r * 0.02, 1.0), true)
	CoinIcon.draw_coin(self, c, r * 0.24, true)
	# Pointer on top.
	var pc := Vector2(c.x, c.y - r * 1.2)
	var flick: float = 0.25 * maxf(sin(_t * 18.0), 0.0) if spin_ready else 0.0
	draw_set_transform(pc, -flick, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([Vector2(-r * 0.13, -r * 0.04), Vector2(r * 0.13, -r * 0.04), Vector2(0, r * 0.28)]), gold)
	draw_circle(Vector2.ZERO, r * 0.08, DailyWheelView.RUBY)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if spin_ready:
		# Sparkles circling the wheel, twinkling.
		for k: int in 8:
			var a: float = _t * 0.9 + TAU * float(k) / 8.0
			var sp: Vector2 = c + Vector2(cos(a), sin(a) * 0.9) * r * (1.42 + 0.08 * sin(_t * 3.0 + float(k)))
			var tw: float = 0.5 + 0.5 * sin(_t * 6.0 + float(k) * 1.7)
			_sparkle(sp, r * 0.05 * (0.5 + tw), Color(1.0, 0.92, 0.65, 0.5 + 0.5 * tw))
	# The plaque under it: SPIN! bouncing, or the countdown.
	var font: Font = get_theme_font(&"font", &"HeadingLabel")
	if font == null:
		font = get_theme_default_font()
	var text: String = "SPIN!" if spin_ready else wait_text
	var px: int = int(size.y * (0.15 if spin_ready else 0.095))
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var bounce: float = absf(sin(_t * 4.0)) * size.y * 0.025 if spin_ready else 0.0
	var plaque := Rect2(Vector2(size.x * 0.5 - w * 0.5 - px * 0.45, size.y * 0.8 - px * 0.5 - bounce), Vector2(w + px * 0.9, px * 1.05))
	var pb := StyleBoxFlat.new()
	pb.bg_color = DailyWheelView.SLICE_BURGUNDY if spin_ready else Color("#24211F", 0.92)
	pb.border_color = gold if (spin_ready or hot) else Color(gold, 0.45)
	pb.set_border_width_all(2)
	pb.set_corner_radius_all(int(px * 0.3))
	if spin_ready:
		pb.shadow_color = Color(1.0, 0.78, 0.35, 0.35 + 0.25 * sin(_t * 4.0))
		pb.shadow_size = 8
	draw_style_box(pb, plaque)
	draw_string(font, Vector2(plaque.position.x + px * 0.45, plaque.position.y + px * 0.86), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, gold if spin_ready else (Palette.VIP_GOLD if hot else Palette.CREAM))


func _sparkle(at: Vector2, s: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s * 2.0), at + Vector2(s * 0.4, 0), at + Vector2(0, s * 2.0), at + Vector2(-s * 0.4, 0)]), col)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 2.0, 0), at + Vector2(0, s * 0.4), at + Vector2(s * 2.0, 0), at + Vector2(0, -s * 0.4)]), col)
