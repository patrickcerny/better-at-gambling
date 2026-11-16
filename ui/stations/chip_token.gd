class_name ChipToken
extends Button
## A bet chip button drawn as a real casino chip (TableSkin.draw_chip): the face colour follows
## its denomination step, the value sits in the middle, and the selected chip lifts with a gold
## halo. Still a Button (toggle, text, signals), so keys, tests and focus work as before; the
## Button's own text is hidden and drawn on the chip instead.

## Denomination step (0 = the smallest chip), picks the colours.
var step: int = 0
var _lift: float = 0.0


func _ready() -> void:
	flat = true
	for s: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())
	for c: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color", &"font_disabled_color"]:
		add_theme_color_override(c, Color(0, 0, 0, 0))
	add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0))
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	toggled.connect(func(_on: bool) -> void: queue_redraw())


func _process(delta: float) -> void:
	var want: float = 1.0 if button_pressed else (0.45 if is_hovered() and not disabled else 0.0)
	if not is_equal_approx(_lift, want):
		_lift = move_toward(_lift, want, delta * 6.0)
		queue_redraw()


func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.5 - 4.0
	var center: Vector2 = size * 0.5 + Vector2(0, 3.0 - _lift * 5.0)
	if button_pressed:
		draw_circle(center, r + 4.0, Color(Palette.VIP_GOLD, 0.35))
		draw_arc(center, r + 3.0, 0, TAU, 48, Palette.VIP_GOLD, 2.0, true)
	var cols: Array[Color] = TableSkin.chip_colors(step)
	var face: Color = cols[0] if not disabled else Color("#3A3430")
	TableSkin.draw_chip(self, center, r, face, cols[1] if not disabled else Color("#57504A"), button_pressed)
	var font: Font = TableSkin.black_font()
	var t: String = text
	var fs: int = int(clampf(r * (0.78 if t.length() <= 4 else 0.62), 10.0, 30.0))
	var ink: Color = TableSkin.ink_for(face)
	var ts: Vector2 = font.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	var pos: Vector2 = center + Vector2(-ts.x * 0.5, ts.y * 0.32)
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
