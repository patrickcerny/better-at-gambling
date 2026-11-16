class_name GoldPlusButton
extends Button
## The "+" next to the Gold Coins in the shop's wallet (Patrick 2026-11-15: the plain round button
## was "ugly"): drawn in code as a small gold coin, the same rim, face and shine as `CoinIcon`'s
## Gold Coin, with a raised cream "+" in the middle. Brighter and a touch bigger under the mouse,
## pressed in while held or while the GOLD page is open.

const SIZE: float = 40.0


static func make() -> GoldPlusButton:
	var b := GoldPlusButton.new()
	b.custom_minimum_size = Vector2(SIZE, SIZE)
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL  # a gamepad can open the Gold page from here too
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.flat = true
	var empty := StyleBoxEmpty.new()
	for st: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		b.add_theme_stylebox_override(st, empty)
	b.mouse_entered.connect(b.queue_redraw)
	b.mouse_exited.connect(b.queue_redraw)
	b.toggled.connect(func(_on: bool) -> void: b.queue_redraw())
	b.button_down.connect(b.queue_redraw)
	b.focus_entered.connect(b.queue_redraw)
	b.focus_exited.connect(b.queue_redraw)
	b.button_up.connect(b.queue_redraw)
	return b


func _draw() -> void:
	var hover: bool = is_hovered() or has_focus()
	var down: bool = button_pressed or get_draw_mode() == DRAW_PRESSED
	var r: float = minf(size.x, size.y) * 0.5 * (1.04 if hover and not down else 1.0)
	var c: Vector2 = size * 0.5 + (Vector2(0, r * 0.06) if down else Vector2.ZERO)
	var rim: Color = CoinIcon.RIM
	var face: Color = Palette.COIN_GOLD.lightened(0.12 if hover else 0.0)
	if down:
		face = face.darkened(0.08)
	if not down:
		draw_circle(size * 0.5 + Vector2(0, r * 0.1), r, Color(0, 0, 0, 0.35))  # drop shadow
	draw_circle(c, r, rim)
	for i: int in 24:  # milled edge, like the coin
		var a: float = TAU * float(i) / 24.0
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * r * 0.86, c + d * r * 0.98, rim.darkened(0.25), maxf(r * 0.06, 1.0))
	draw_circle(c, r * 0.82, face)
	draw_circle(c + Vector2(0, -r * 0.1), r * 0.62, face.lightened(0.1))  # a soft dome
	draw_arc(c, r * 0.74, PI * 1.05, PI * 1.45, 10, CoinIcon.SHINE, maxf(r * 0.1, 1.0), true)
	# The plus: a dark stamped outline under a cream cross.
	var arm: float = r * 0.36
	var w: float = maxf(r * 0.24, 2.0)
	var ink: Color = rim.darkened(0.45)
	var o := Vector2(0, r * 0.05)
	_cross(c + o, arm + w * 0.25, w + maxf(r * 0.1, 1.5), ink)
	_cross(c, arm, w, Palette.CREAM if not down else Palette.CREAM.darkened(0.08))
	if has_focus():
		draw_arc(c, r + 3.0, 0.0, TAU, 40, Palette.VIP_GOLD, 3.0, true)  # gamepad focus


## A "+" of half-length `arm` and thickness `w` with round ends.
func _cross(at: Vector2, arm: float, w: float, col: Color) -> void:
	draw_line(at - Vector2(arm, 0), at + Vector2(arm, 0), col, w, true)
	draw_line(at - Vector2(0, arm), at + Vector2(0, arm), col, w, true)
	for p: Vector2 in [Vector2(arm, 0), Vector2(-arm, 0), Vector2(0, arm), Vector2(0, -arm)]:
		draw_circle(at + p, w * 0.5, col)
