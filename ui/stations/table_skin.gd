class_name TableSkin
extends RefCounted
## The look of the table overlays (ui/stations, docs/ART_DIRECTION.md): a dark walnut panel in a
## brass frame with an inner hairline and corner studs, an engraved title between two brass rules,
## a felt band for the status, brass plaque buttons in four finishes and drawn casino chips.
## Everything here is code-built (no textures), so every table looks the same and stays sharp at
## any resolution. Warm and luxurious, never neon: gold, cream, felt green, casino red, burgundy.

const WALNUT := Color("#1D1411")
const WALNUT_LIGHT := Color("#2D201A")
const BRASS_DARK := Color("#8A6D35")
const BRASS := Color("#D6A84B")
const FELT_DEEP := Color("#1B4535")
const TEXT_MUTED := Color("#A99C84")
const SHADOW := Color(0, 0, 0, 0.6)

## Chip faces by denomination step (smallest first): cream, red, green, black, burgundy, gold.
const CHIP_FACES: Array[Color] = [Color("#EDE3CB"), Color("#B83434"), Color("#2A6B50"), Color("#1A1716"), Color("#6E1F2E"), Color("#C8963A")]
const CHIP_STRIPES: Array[Color] = [Color("#B83434"), Color("#F2E6C9"), Color("#F2E6C9"), Color("#D6A84B"), Color("#E3B95C"), Color("#1A1716")]


## The panel every table overlay sits in: walnut, a brass border, a deep soft shadow.
static func panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(WALNUT, 0.95)
	sb.border_color = BRASS
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 16
	sb.shadow_color = SHADOW
	sb.shadow_size = 22
	sb.shadow_offset = Vector2(0, 6)
	sb.anti_aliasing = true
	return sb


## Draws the frame's details over a panel (connect to its `draw`): an inner brass hairline, a
## brighter top edge (light from above) and four diamond studs in the corners.
static func draw_frame(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	var inner: Rect2 = r.grow(-7)
	if inner.size.x <= 0 or inner.size.y <= 0:
		return
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = Color(BRASS, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(9)
	sb.anti_aliasing = true
	c.draw_style_box(sb, inner)
	c.draw_line(Vector2(16, 1.5), Vector2(r.size.x - 16, 1.5), Color(Palette.VIP_GOLD, 0.55), 1.0, true)
	for p: Vector2 in [inner.position, Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), inner.end]:
		diamond(c, p, 4.5, BRASS)
		diamond(c, p, 2.0, Palette.CREAM)


## A small filled diamond (rules, studs, bullets).
static func diamond(c: CanvasItem, at: Vector2, r: float, color: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]), color)


## A felt inset (cards, the betting layout, a result): deep green, a thin brass line.
static func felt_box(radius: int = 10, margin: float = 10.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = FELT_DEEP
	sb.border_color = Color(BRASS, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


## A rounded band of `color` with a brass edge (status lines, tags, badges).
static func band_box(color: Color, border: Color = BRASS, radius: int = 18) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 5
	sb.anti_aliasing = true
	return sb


## A brass plaque: `face`, a 1 px rim and a darker 4 px bottom edge (it reads as raised).
static func plaque(face: Color, rim: Color, pressed: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = face
	sb.border_color = rim
	sb.set_border_width_all(1)
	sb.border_width_bottom = 1 if pressed else 4
	if not pressed:
		sb.border_color = rim
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6 + (3 if pressed else 0)
	sb.content_margin_bottom = 6
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 0 if pressed else 4
	sb.shadow_offset = Vector2(0, 2)
	sb.anti_aliasing = true
	return sb


## Styles a table button. Kinds: &"gold" (the main move: bet, spin, drop, cash out), &"felt"
## (a play: hit, higher), &"red" (a risky or closing move: stand, fold, all in), &"ghost" (small
## helpers: clear, repeat, risk levels).
static func style_button(b: Button, kind: StringName = &"felt", font_size: int = -1) -> void:
	var face: Color
	var rim: Color
	var text: Color = Palette.CREAM
	match kind:
		&"gold":
			face = Color("#C9973F")
			rim = Color("#F0CF7A")
			text = Palette.CASINO_BLACK
		&"red":
			face = Color("#8E2A2E")
			rim = Color("#D86A5A")
		&"ghost":
			face = Color(WALNUT_LIGHT, 0.9)
			rim = BRASS_DARK
		_:
			face = Color("#2C6A50")
			rim = Color("#7FBF8F")
	var normal: StyleBoxFlat = plaque(face, rim.darkened(0.25))
	normal.border_color = face.darkened(0.45)
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	var hover: StyleBoxFlat = plaque(face.lightened(0.12), rim)
	hover.border_color = rim
	var pressed: StyleBoxFlat = plaque(face.darkened(0.15), rim, true)
	var disabled: StyleBoxFlat = plaque(Color("#2A2421"), Color("#3A3430"))
	disabled.shadow_size = 0
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Palette.VIP_GOLD
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(10)
	focus.set_expand_margin_all(2)
	if b.toggle_mode:
		# A toggle's "on" look: burgundy with a bright gold rim, so the choice reads at a glance.
		pressed = plaque(Palette.VIP_BURGUNDY, Palette.VIP_GOLD, true)
		pressed.set_border_width_all(2)
	b.add_theme_stylebox_override(&"normal", normal)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"pressed", pressed)
	b.add_theme_stylebox_override(&"hover_pressed", pressed)
	b.add_theme_stylebox_override(&"disabled", disabled)
	b.add_theme_stylebox_override(&"focus", focus)
	b.add_theme_color_override(&"font_color", text)
	b.add_theme_color_override(&"font_hover_color", text if kind == &"gold" else Palette.VIP_GOLD)
	b.add_theme_color_override(&"font_pressed_color", Palette.VIP_GOLD if b.toggle_mode or kind != &"gold" else text)
	b.add_theme_color_override(&"font_hover_pressed_color", Palette.VIP_GOLD if b.toggle_mode or kind != &"gold" else text)
	b.add_theme_color_override(&"font_focus_color", text)
	b.add_theme_color_override(&"font_disabled_color", Color("#6B625A"))
	b.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.0 if kind == &"gold" else 0.45))
	b.add_theme_constant_override(&"outline_size", 0 if kind == &"gold" else 3)
	b.add_theme_font_override(&"font", heavy_font())
	if font_size > 0:
		b.add_theme_font_size_override(&"font_size", font_size)
	if not b.mouse_entered.is_connected(_hover_tick):
		b.mouse_entered.connect(_hover_tick.bind(b))


static func _hover_tick(b: Button) -> void:
	if b.disabled or not b.is_visible_in_tree():
		return
	Audio.play(&"ui_hover", &"UI", -20.0, randf_range(0.97, 1.05))


static var _heavy: Font
static var _black: Font


## Barlow Condensed ExtraBold (buttons, numbers).
static func heavy_font() -> Font:
	if _heavy == null:
		_heavy = load("res://assets/fonts/BarlowCondensed-ExtraBold.ttf")
	return _heavy


## Barlow Condensed Black (titles, big money).
static func black_font() -> Font:
	if _black == null:
		_black = load("res://assets/fonts/BarlowCondensed-Black.ttf")
	return _black


## A label with the table's type: `size`, `color`, a soft dark outline so it reads over anything.
static func label(text: String, size: int, color: Color = Palette.CREAM, heavy: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override(&"outline_size", 4)
	if heavy:
		l.add_theme_font_override(&"font", heavy_font())
	return l


## A small engraved caption ("RISK", "YOUR BETS") between two short brass rules.
static func caption(text: String) -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override(&"separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(DecoRule.new(false, 42.0))
	var l: Label = label(text, 15, BRASS, true)
	l.add_theme_constant_override(&"outline_size", 0)
	h.add_child(l)
	h.add_child(DecoRule.new(true, 42.0))
	return h


## Pops a control in (scale from 0.6 with a little overshoot), pivot at its centre.
static func pop(c: Control, from: float = 0.6) -> void:
	if not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(from, from)
	var tw: Tween = c.create_tween()
	tw.tween_property(c, ^"scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A quick gold flash on a control's modulate (a value just changed).
static func flash(c: CanvasItem, color: Color = Color(1.35, 1.2, 0.8)) -> void:
	if not c.is_inside_tree():
		return
	c.modulate = color
	var tw: Tween = c.create_tween()
	tw.tween_property(c, ^"modulate", Color.WHITE, 0.45).set_trans(Tween.TRANS_SINE)


## Chip colours for the `index`-th denomination: [face, stripe].
static func chip_colors(index: int) -> Array[Color]:
	var i: int = clampi(index, 0, CHIP_FACES.size() - 1)
	return [CHIP_FACES[i], CHIP_STRIPES[i]]


## Draws a casino chip at `center`: rim with six edge inserts, an inner ring, a brass hairline.
static func draw_chip(c: CanvasItem, center: Vector2, radius: float, face: Color, stripe: Color, lifted: bool = false) -> void:
	c.draw_circle(center + Vector2(0, radius * 0.12), radius, Color(0, 0, 0, 0.45))  # drop shadow
	c.draw_circle(center, radius, face)
	var n: int = 6
	for k: int in n:
		var a0: float = TAU * k / n - 0.2 + (0.15 if lifted else 0.0)
		var a1: float = a0 + 0.4
		var pts := PackedVector2Array()
		for s: int in 5:
			var a: float = lerpf(a0, a1, s / 4.0)
			pts.append(center + Vector2(cos(a), sin(a)) * radius)
		for s: int in 5:
			var a: float = lerpf(a1, a0, s / 4.0)
			pts.append(center + Vector2(cos(a), sin(a)) * radius * 0.78)
		c.draw_colored_polygon(pts, stripe)
	c.draw_circle(center, radius * 0.66, face.lightened(0.06))
	c.draw_arc(center, radius * 0.66, 0, TAU, 40, Color(stripe, 0.85), maxf(radius * 0.06, 1.0), true)
	c.draw_arc(center, radius - 0.5, 0, TAU, 48, Color(0, 0, 0, 0.35), 1.0, true)


## Black or cream: whichever reads on a chip/tile of colour `bg`.
static func ink_for(bg: Color) -> Color:
	return Palette.CASINO_BLACK if bg.get_luminance() > 0.45 else Palette.CREAM


## Gives every plain button under `root` the table look: an ActionButton as a felt plaque, the
## rest as quiet ghost plaques. Buttons with their own styles (coloured bet spots, chips) keep them.
static func skin_buttons(root: Node) -> void:
	for n: Node in root.find_children("*", "Button", true, false):
		var b: Button = n as Button
		if b is ChipToken or b.has_theme_stylebox_override(&"normal") or b.flat:
			continue
		style_button(b, &"felt" if b.theme_type_variation == &"ActionButton" else &"ghost")
