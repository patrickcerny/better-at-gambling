class_name VoteRaceMarquee
extends PanelContainer
## The big game-show marquee over the Vote Race set: a wine panel in a gold frame ringed with warm
## incandescent bulbs that chase slowly (two bulbs in three lit). Holds the kicker line and the
## question / headline; the stage sets the texts.

const BULB_STEP: float = 30.0
const BULB_R: float = 5.0
const BULB_ON: Color = Color("#FFE7B0")
const BULB_OFF: Color = Color("#7A5A2A")
const CHASE_TIME: float = 0.35

const BLACK_FONT: Font = preload("res://assets/fonts/BarlowCondensed-Black.ttf")
const BOLD_FONT: Font = preload("res://assets/fonts/BarlowCondensed-ExtraBold.ttf")

var kicker: Label
var headline: Label
var subline: Label
var _phase: int = 0
var _t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2(1180, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.VIP_BURGUNDY.darkened(0.25)
	sb.border_color = Palette.WARM_GOLD
	sb.set_border_width_all(14)
	sb.set_corner_radius_all(26)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 24
	sb.shadow_offset = Vector2(0, 8)
	sb.content_margin_left = 60
	sb.content_margin_right = 60
	sb.content_margin_top = 22
	sb.content_margin_bottom = 24
	sb.anti_aliasing = true
	add_theme_stylebox_override(&"panel", sb)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", -6)
	add_child(col)
	kicker = _label(BOLD_FONT, 28, Palette.WARM_GOLD)
	col.add_child(kicker)
	headline = _label(BLACK_FONT, 76, Palette.CREAM)
	headline.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.6))
	headline.add_theme_constant_override(&"shadow_offset_y", 5)
	col.add_child(headline)
	subline = _label(BOLD_FONT, 26, Color(Palette.CREAM, 0.8))
	col.add_child(subline)


func _label(font: Font, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", color)
	return l


func set_texts(p_kicker: String, p_headline: String, p_subline: String) -> void:
	kicker.text = p_kicker
	headline.text = p_headline
	subline.text = p_subline
	subline.visible = p_subline != ""


func _process(delta: float) -> void:
	_t += delta
	if _t >= CHASE_TIME:
		_t = 0.0
		_phase = (_phase + 1) % 3
		queue_redraw()


## Bulbs round the frame, on the middle of the gold border.
func _draw() -> void:
	var inset: float = 7.0
	var r := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
	var pts: Array[Vector2] = []
	var nx: int = maxi(int(r.size.x / BULB_STEP), 2)
	var ny: int = maxi(int(r.size.y / BULB_STEP), 2)
	var corner: float = 18.0
	for i: int in nx + 1:
		var x: float = lerpf(r.position.x + corner, r.end.x - corner, float(i) / float(nx))
		pts.append(Vector2(x, r.position.y))
	for i: int in range(1, ny):
		var y: float = lerpf(r.position.y + corner, r.end.y - corner, float(i) / float(ny))
		pts.append(Vector2(r.end.x, y))
	for i: int in nx + 1:
		var x: float = lerpf(r.end.x - corner, r.position.x + corner, float(i) / float(nx))
		pts.append(Vector2(x, r.end.y))
	for i: int in range(1, ny):
		var y: float = lerpf(r.end.y - corner, r.position.y + corner, float(i) / float(ny))
		pts.append(Vector2(r.position.x, y))
	for i: int in pts.size():
		var on: bool = (i + _phase) % 3 != 0
		if on:
			draw_circle(pts[i], BULB_R * 2.0, Color(BULB_ON, 0.16), true, -1.0, true)
		draw_circle(pts[i], BULB_R, BULB_ON if on else BULB_OFF, true, -1.0, true)
