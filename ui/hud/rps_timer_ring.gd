class_name RpsTimerRing
extends Control
## The duel's clock: a brass ring that runs down with the seconds left, the number in the middle.
## The last three seconds turn the ring red and make it pulse.

var number: Label
var _left: float = 0.0
var _total: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(76, 76)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	number = TableSkin.label("", 34, Palette.CREAM)
	number.add_theme_font_override(&"font", TableSkin.black_font())
	number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(number)


func set_time(left: float, total: float) -> void:
	_left = left
	_total = total
	number.add_theme_color_override(&"font_color", Palette.LOSS_RED if _urgent() else Palette.CREAM)
	queue_redraw()


func _urgent() -> bool:
	return _total > 0.0 and _left <= 3.0


func _process(_delta: float) -> void:
	if _urgent():
		queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5 - 5.0
	draw_circle(c, r + 4.0, Color(TableSkin.WALNUT, 0.95))
	draw_arc(c, r, 0, TAU, 48, Color(TableSkin.BRASS_DARK, 0.45), 6.0, true)
	if _total <= 0.0:
		return
	var f: float = clampf(_left / _total, 0.0, 1.0)
	var col: Color = Palette.VIP_GOLD
	var w: float = 6.0
	if _urgent():
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		col = Palette.LOSS_RED.lerp(Palette.CREAM, pulse * 0.25)
		w = 6.0 + pulse * 2.0
	if f > 0.0:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * f, maxi(int(48 * f), 3), col, w, true)
		var tip: Vector2 = c + Vector2(cos(-PI * 0.5 + TAU * f), sin(-PI * 0.5 + TAU * f)) * r
		TableSkin.diamond(self, tip, 5.0, Palette.CREAM)
