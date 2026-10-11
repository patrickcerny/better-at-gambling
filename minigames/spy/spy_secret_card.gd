class_name SpySecretCard
extends PanelContainer
## Your secret card at the top of the Spy panel. A civilian holds a cream card: "THE WORD" and the
## word in big black letters, its category underneath. A spy holds a burgundy card: "YOU ARE THE
## SPY", the category, and the hint once the server sends it (until then when it arrives). A
## little rotated "TOP SECRET" stamp sits on the corner. At the end the spy's card also shows
## the word. Presentation only: the stage calls `show_civilian` / `show_spy` / `reveal_word`.

const CARD_DARK: Color = Color("#2A211C")
const BLACK_FONT: Font = preload("res://assets/fonts/BarlowCondensed-Black.ttf")
const BOLD_FONT: Font = preload("res://assets/fonts/BarlowCondensed-ExtraBold.ttf")

## "civilian", "spy" or "" (watching).
var role: String = ""
var kicker: Label
var big: Label
var line1: Label
var line2: Label
## The "TOP SECRET" stamp on the corner (drawn).
var secret: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(560, 0)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override(&"separation", -4)
	add_child(col)
	kicker = _label(BOLD_FONT, 26)
	col.add_child(kicker)
	big = _label(BLACK_FONT, 66)
	big.clip_text = true
	big.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(big)
	line1 = _label(BOLD_FONT, 28)
	col.add_child(line1)
	line2 = _label(BOLD_FONT, 23)
	line2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(line2)
	show_watching()


func _label(font: Font, size_px: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", size_px)
	return l


func _style(bg: Color, border: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(18)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 6)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	sb.anti_aliasing = true
	add_theme_stylebox_override(&"panel", sb)


func _colors(k: Color, b: Color, l1: Color, l2: Color) -> void:
	kicker.add_theme_color_override(&"font_color", k)
	big.add_theme_color_override(&"font_color", b)
	line1.add_theme_color_override(&"font_color", l1)
	line2.add_theme_color_override(&"font_color", l2)


func show_watching() -> void:
	role = ""
	_style(Palette.WARM_CHARCOAL, Palette.WARM_GOLD)
	_colors(Palette.WARM_GOLD, Palette.CREAM, Color(Palette.CREAM, 0.8), Color(Palette.CREAM, 0.7))
	kicker.text = "THE PANEL"
	big.text = "WATCHING"
	line1.text = "Who is the spy?"
	line2.text = ""
	line2.visible = false
	_set_secret(false)


func show_civilian(word: String, category: String) -> void:
	role = "civilian"
	_style(Palette.CREAM, Palette.WARM_GOLD)
	_colors(Palette.VIP_BURGUNDY, CARD_DARK, Color(CARD_DARK, 0.7), Color(CARD_DARK, 0.6))
	kicker.text = "THE WORD"
	big.text = word.to_upper()
	line1.text = category.to_upper()
	line2.text = "Give clues - don't give it away!"
	line2.visible = true
	_set_secret(true)


## `hint` "" = not yet; `hint_in` the game-clock seconds until it arrives (< 0: not shown).
func show_spy(category: String, hint: String, hint_in: float) -> void:
	role = "spy"
	_style(Palette.VIP_BURGUNDY.darkened(0.15), Palette.VIP_GOLD)
	_colors(Palette.VIP_GOLD, Palette.CREAM, Palette.VIP_GOLD, Color(Palette.CREAM, 0.85))
	kicker.text = "SHHH…"
	big.text = "YOU ARE THE SPY"
	line1.text = "CATEGORY: %s" % category.to_upper()
	if hint != "":
		line2.text = "HINT: %s" % hint
	elif hint_in >= 0.0:
		line2.text = "Your hint arrives in %d s - blend in!" % ceili(hint_in)
	else:
		line2.text = "Blend in - nobody knows it's you."
	line2.visible = true
	_set_secret(true)


## The end: the word is on everyone's card now.
func reveal_word(word: String, category: String) -> void:
	if role == "civilian":
		line2.text = "The word is out!"
		_set_secret(false)
		return
	kicker.text = "THE WORD WAS"
	big.text = word.to_upper()
	line1.text = category.to_upper()
	line2.text = "You were the spy." if role == "spy" else ""
	line2.visible = line2.text != ""
	_set_secret(false)


func _set_secret(on: bool) -> void:
	secret = on
	queue_redraw()


func _draw() -> void:
	if not secret:
		return
	var font_size: int = 20
	var label: String = "TOP SECRET"
	var w: float = BLACK_FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 16.0
	var h: float = 28.0
	draw_set_transform(Vector2(size.x - w * 0.5 - 18.0, 22.0), 0.2)
	var r := Rect2(-w * 0.5, -h * 0.5, w, h)
	draw_rect(r, Color(Palette.CREAM, 0.0 if role == "civilian" else 0.12))
	draw_rect(r, Palette.CASINO_RED, false, 3.0)
	draw_string(BLACK_FONT, Vector2(-w * 0.5, h * 0.5 - 7.0), label, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, Palette.CASINO_RED if role == "civilian" else Palette.VIP_GOLD)
	draw_set_transform(Vector2.ZERO)
