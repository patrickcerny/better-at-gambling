class_name NotifyDot
extends Control
## A red dot with a number on a button's top-right corner (Patrick 2026-11-16: "Show message point
## badge on shop if you can unlock something"): how many rewards wait in the shop's COLLECT tab.
## Hidden at 0. `attach` puts one on a button; `count` sets the number.

const DIAMETER: float = 26.0

var count: int = 0:
	set(v):
		count = maxi(v, 0)
		visible = count > 0
		queue_redraw()
var _font: Font


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(DIAMETER, DIAMETER)
	size = custom_minimum_size
	visible = false


## A dot on `button`'s top-right corner, half over its edge; with `by_text` right after the
## button's (centred) text instead, for wide menu entries.
static func attach(button: Control, by_text: bool = false) -> NotifyDot:
	var dot := NotifyDot.new()
	dot.name = "NotifyDot"
	button.add_child(dot)
	if by_text and button is Button:
		var b: Button = button
		var place := func() -> void:
			var font: Font = b.get_theme_font(&"font")
			var w: float = font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size(&"font_size")).x
			dot.position = Vector2(b.size.x * 0.5 + w * 0.5 + 4.0, b.size.y * 0.5 - DIAMETER * 1.1)
		b.resized.connect(place)
		place.call_deferred()
		return dot
	dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	dot.offset_left = -DIAMETER * 0.7
	dot.offset_right = DIAMETER * 0.3
	dot.offset_top = -DIAMETER * 0.3
	dot.offset_bottom = DIAMETER * 0.7
	return dot


func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.5
	var c: Vector2 = size * 0.5
	draw_circle(c + Vector2(0, 2), r, Color(0, 0, 0, 0.35))
	draw_circle(c, r, Palette.CREAM)
	draw_circle(c, r - 2.0, Palette.CASINO_RED)
	if _font == null:
		_font = get_theme_default_font()
	var text: String = "9+" if count > 9 else str(count)
	var fs: int = 16 if text.length() == 1 else 14
	var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc: float = _font.get_ascent(fs)
	var desc: float = _font.get_descent(fs)
	draw_string(_font, Vector2(c.x - w * 0.5, c.y + (asc - desc) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.CREAM)
