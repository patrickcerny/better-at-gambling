extends SceneTree
## Generates ui/theme/main_theme.tres from the palette and Barlow Condensed fonts.
## Run: tools/godot/godot --headless --path . -s tools/gen_theme.gd
##
## Look (docs/ART_DIRECTION.md): printed casino signage, not a mobile casino. Near-black warm panels
## with a gold hairline and a soft drop shadow, cream text, gold headings, buttons that read like
## brass plaques (darker bottom edge), Casino Red for "pressed", Felt Green / Money Green for "on".

const OUT: String = "res://ui/theme/main_theme.tres"

## Dark gold for idle borders; bright gold is reserved for focus/hover so it means something.
const DIM_GOLD := Color("#8A6D35")
const PANEL_BG := Color("#1C1917")
const BUTTON_BG := Color("#2B2522")
const BUTTON_HOVER := Color("#3A3029")
const MUTED_TEXT := Color("#A99C84")
const DISABLED_TEXT := Color("#6B625A")


func _init() -> void:
	var t := Theme.new()
	var black: FontFile = load("res://assets/fonts/BarlowCondensed-Black.ttf")
	var bold: FontFile = load("res://assets/fonts/BarlowCondensed-ExtraBold.ttf")
	var semi: FontFile = load("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	var medium: FontFile = load("res://assets/fonts/BarlowCondensed-Medium.ttf")
	t.default_font = semi
	t.default_font_size = 24

	# Panels: warm near-black, gold hairline, soft shadow so they lift off the 3D casino.
	var panel := _box(Color(PANEL_BG, 0.96), Palette.WARM_GOLD, 2, 6, 22, 16)
	panel.shadow_color = Color(0, 0, 0, 0.55)
	panel.shadow_size = 14
	panel.shadow_offset = Vector2(0, 4)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "PanelContainer", panel)
	var popup := _box(Palette.CASINO_BLACK, Palette.WARM_GOLD, 2, 6, 8, 8)
	popup.shadow_color = Color(0, 0, 0, 0.5)
	popup.shadow_size = 10
	t.set_stylebox("panel", "PopupPanel", popup)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(Palette.VIP_BURGUNDY, Color(0, 0, 0, 0), 0, 4, 8, 4))
	t.set_stylebox("separator", "PopupMenu", _line(DIM_GOLD, 1))
	t.set_font("font", "PopupMenu", semi)
	t.set_font_size("font_size", "PopupMenu", 24)
	t.set_color("font_color", "PopupMenu", Palette.CREAM)
	t.set_color("font_hover_color", "PopupMenu", Palette.VIP_GOLD)
	t.set_color("font_disabled_color", "PopupMenu", DISABLED_TEXT)
	t.set_constant("v_separation", "PopupMenu", 8)

	# Buttons: brass plaques. Darker 4 px bottom edge, gold border on hover/focus, red when pressed.
	var b_normal := _plaque(BUTTON_BG, DIM_GOLD)
	var b_hover := _plaque(BUTTON_HOVER, Palette.WARM_GOLD)
	var b_pressed := _plaque(Palette.VIP_BURGUNDY, Palette.VIP_GOLD, true)  # also the "selected" look of toggles
	var b_focus := _box(Color(0, 0, 0, 0), Palette.VIP_GOLD, 3, 7, 14, 6)
	b_focus.set_expand_margin_all(2)
	var b_disabled := _plaque(Color("#1E1B19"), Color("#3A3430"))
	for cls: String in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", cls, b_normal)
		t.set_stylebox("hover", cls, b_hover)
		t.set_stylebox("pressed", cls, b_pressed)
		t.set_stylebox("hover_pressed", cls, b_pressed)
		t.set_stylebox("focus", cls, b_focus)
		t.set_stylebox("disabled", cls, b_disabled)
		t.set_font("font", cls, bold)
		t.set_font_size("font_size", cls, 26)
		t.set_color("font_color", cls, Palette.CREAM)
		t.set_color("font_hover_color", cls, Palette.VIP_GOLD)
		t.set_color("font_pressed_color", cls, Palette.VIP_GOLD)
		t.set_color("font_hover_pressed_color", cls, Palette.VIP_GOLD)
		t.set_color("font_focus_color", cls, Palette.VIP_GOLD)
		t.set_color("font_disabled_color", cls, DISABLED_TEXT)
		t.set_color("font_outline_color", cls, Palette.CASINO_BLACK)
		t.set_constant("h_separation", cls, 10)
	t.set_icon("arrow", "OptionButton", _arrow_icon())
	t.set_constant("arrow_margin", "OptionButton", 12)

	# CheckButton / CheckBox: a flat row, the switch itself is drawn here (gold knob, felt green on).
	var flat := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, 6, 4)
	var flat_hover := _box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 6, 6, 4)
	for cls: String in ["CheckButton", "CheckBox"]:
		t.set_stylebox("normal", cls, flat)
		t.set_stylebox("pressed", cls, flat)
		t.set_stylebox("hover", cls, flat_hover)
		t.set_stylebox("hover_pressed", cls, flat_hover)
		t.set_stylebox("disabled", cls, flat)
		t.set_stylebox("focus", cls, b_focus)
		t.set_font("font", cls, semi)
		t.set_font_size("font_size", cls, 24)
		t.set_color("font_color", cls, Palette.CREAM)
		t.set_color("font_hover_color", cls, Palette.VIP_GOLD)
		t.set_color("font_pressed_color", cls, Palette.CREAM)
		t.set_color("font_hover_pressed_color", cls, Palette.VIP_GOLD)
		t.set_color("font_focus_color", cls, Palette.VIP_GOLD)
	t.set_icon("checked", "CheckButton", _switch_icon(true, false))
	t.set_icon("unchecked", "CheckButton", _switch_icon(false, false))
	t.set_icon("checked_disabled", "CheckButton", _switch_icon(true, true))
	t.set_icon("unchecked_disabled", "CheckButton", _switch_icon(false, true))
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked", "CheckBox", _check_icon(false))

	t.set_font("font", "Label", semi)
	t.set_color("font_color", "Label", Palette.CREAM)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_color("font_outline_color", "Label", Palette.CASINO_BLACK)
	t.set_font("normal_font", "RichTextLabel", medium)
	t.set_font("bold_font", "RichTextLabel", bold)
	t.set_color("default_color", "RichTextLabel", Palette.CREAM)

	var line := _box(Palette.CASINO_BLACK, DIM_GOLD, 2, 6, 12, 8)
	t.set_stylebox("normal", "LineEdit", line)
	t.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0), Palette.VIP_GOLD, 3, 6, 12, 8))
	t.set_stylebox("read_only", "LineEdit", _box(Palette.CASINO_BLACK, Color("#3A3430"), 2, 6, 12, 8))
	t.set_color("font_color", "LineEdit", Palette.CREAM)
	t.set_color("font_placeholder_color", "LineEdit", Color(Palette.CREAM, 0.38))
	t.set_color("caret_color", "LineEdit", Palette.VIP_GOLD)
	t.set_color("selection_color", "LineEdit", Color(Palette.VIP_BURGUNDY, 0.9))
	t.set_font("font", "LineEdit", medium)
	t.set_font_size("font_size", "LineEdit", 26)

	# Sliders: dark groove, gold fill, a gold chip as the grabber.
	t.set_stylebox("slider", "HSlider", _box(Palette.CASINO_BLACK, Color("#3A3430"), 1, 4, 0, 4))
	t.set_stylebox("grabber_area", "HSlider", _box(Palette.WARM_GOLD, Color(0, 0, 0, 0), 0, 4, 0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(Palette.VIP_GOLD, Color(0, 0, 0, 0), 0, 4, 0, 4))
	t.set_icon("grabber", "HSlider", _chip_icon(Palette.WARM_GOLD))
	t.set_icon("grabber_highlight", "HSlider", _chip_icon(Palette.VIP_GOLD))
	t.set_icon("grabber_disabled", "HSlider", _chip_icon(DISABLED_TEXT))
	t.set_constant("center_grabber", "HSlider", 1)

	t.set_stylebox("background", "ProgressBar", _box(Palette.CASINO_BLACK, DIM_GOLD, 1, 4, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _box(Palette.WARM_GOLD, Color(0, 0, 0, 0), 0, 4, 0, 0))
	t.set_color("font_color", "ProgressBar", Palette.CREAM)

	# Scrollbars: thin, gold grabber.
	for cls: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", cls, _box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 4, 4, 4))
		t.set_stylebox("grabber", cls, _box(DIM_GOLD, Color(0, 0, 0, 0), 0, 4, 4, 4))
		t.set_stylebox("grabber_highlight", cls, _box(Palette.WARM_GOLD, Color(0, 0, 0, 0), 0, 4, 4, 4))
		t.set_stylebox("grabber_pressed", cls, _box(Palette.VIP_GOLD, Color(0, 0, 0, 0), 0, 4, 4, 4))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	# Separators: a gold rule.
	t.set_stylebox("separator", "HSeparator", _line(DIM_GOLD, 2))
	t.set_constant("separation", "HSeparator", 10)
	t.set_stylebox("separator", "VSeparator", _line(DIM_GOLD, 2, true))

	t.set_stylebox("panel", "TooltipPanel", _box(Palette.CASINO_BLACK, Palette.WARM_GOLD, 1, 4, 10, 6))
	t.set_color("font_color", "TooltipLabel", Palette.CREAM)
	t.set_font("font", "TooltipLabel", medium)
	t.set_font_size("font_size", "TooltipLabel", 20)

	# Named variations.
	_label_var(t, "TitleLabel", black, 64, Palette.CREAM)
	t.set_color("font_shadow_color", "TitleLabel", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_y", "TitleLabel", 4)
	t.set_constant("shadow_offset_x", "TitleLabel", 0)
	_label_var(t, "HeadingLabel", bold, 36, Palette.WARM_GOLD)
	_label_var(t, "MoneyLabel", black, 48, Palette.CREAM)
	_label_var(t, "SmallLabel", medium, 20, Palette.CREAM)
	_label_var(t, "MutedLabel", medium, 20, MUTED_TEXT)
	# Logo lines (BETTER / AT / GAMBLING) and the big menu entries.
	_label_var(t, "LogoLabel", black, 120, Palette.CREAM)
	t.set_color("font_shadow_color", "LogoLabel", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_y", "LogoLabel", 5)
	t.set_constant("shadow_offset_x", "LogoLabel", 3)
	t.set_constant("line_spacing", "LogoLabel", -18)

	var clear := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 18, 2)
	var entry_hover := _box(Color(Palette.CASINO_BLACK, 0.55), Color(0, 0, 0, 0), 0, 0, 18, 2)
	entry_hover.border_color = Palette.WARM_GOLD
	entry_hover.border_width_left = 5
	t.add_type("MenuEntry")
	t.set_type_variation("MenuEntry", "Button")
	t.set_stylebox("normal", "MenuEntry", clear)
	t.set_stylebox("hover", "MenuEntry", entry_hover)
	t.set_stylebox("pressed", "MenuEntry", entry_hover)
	t.set_stylebox("hover_pressed", "MenuEntry", entry_hover)
	t.set_stylebox("focus", "MenuEntry", entry_hover)
	t.set_stylebox("disabled", "MenuEntry", clear)
	t.set_font("font", "MenuEntry", black)
	t.set_font_size("font_size", "MenuEntry", 52)
	t.set_color("font_color", "MenuEntry", Palette.CREAM)
	t.set_color("font_hover_color", "MenuEntry", Palette.VIP_GOLD)
	t.set_color("font_focus_color", "MenuEntry", Palette.VIP_GOLD)
	t.set_color("font_pressed_color", "MenuEntry", Palette.CASINO_RED)
	t.set_color("font_hover_pressed_color", "MenuEntry", Palette.VIP_GOLD)
	t.set_color("font_outline_color", "MenuEntry", Palette.CASINO_BLACK)
	t.set_constant("outline_size", "MenuEntry", 6)

	t.add_type("ChipButton")
	t.set_type_variation("ChipButton", "Button")
	t.set_stylebox("normal", "ChipButton", _box(Palette.CASINO_RED, Palette.CREAM, 3, 32, 6, 6))
	t.set_stylebox("hover", "ChipButton", _box(Color("#E04A4A"), Palette.VIP_GOLD, 3, 32, 6, 6))
	t.set_stylebox("pressed", "ChipButton", _box(Palette.VIP_BURGUNDY, Palette.VIP_GOLD, 3, 32, 6, 6))
	t.set_stylebox("hover_pressed", "ChipButton", _box(Palette.VIP_BURGUNDY, Palette.VIP_GOLD, 3, 32, 6, 6))
	t.set_stylebox("focus", "ChipButton", _box(Color(0, 0, 0, 0), Palette.VIP_GOLD, 4, 32, 6, 6))
	t.set_stylebox("disabled", "ChipButton", _box(Color("#3A3430"), Color("#6B625A"), 3, 32, 6, 6))
	t.set_font("font", "ChipButton", black)
	t.set_font_size("font_size", "ChipButton", 22)

	# Big table action (HIT / STAND, Ready): felt green plaque.
	t.add_type("ActionButton")
	t.set_type_variation("ActionButton", "Button")
	t.set_stylebox("normal", "ActionButton", _plaque(Palette.FELT_GREEN, Palette.WARM_GOLD))
	t.set_stylebox("hover", "ActionButton", _plaque(Palette.FELT_GREEN.lightened(0.12), Palette.VIP_GOLD))
	t.set_stylebox("pressed", "ActionButton", _plaque(Palette.CASINO_RED, Palette.VIP_GOLD, true))
	t.set_font("font", "ActionButton", black)
	t.set_font_size("font_size", "ActionButton", 30)

	# Panels for specific jobs.
	var sign_panel := _box(Color(Palette.VIP_BURGUNDY.darkened(0.35), 0.97), Palette.VIP_GOLD, 3, 6, 24, 16)
	sign_panel.shadow_color = Color(0, 0, 0, 0.55)
	sign_panel.shadow_size = 16
	sign_panel.shadow_offset = Vector2(0, 5)
	_panel_var(t, "SignPanel", sign_panel)
	var plate := _box(Color(Palette.CASINO_BLACK, 0.72), Color(Palette.WARM_GOLD, 0.55), 1, 6, 16, 6)
	_panel_var(t, "HudPlate", plate)
	var row := _box(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 0, 4, 12, 6)
	row.border_color = Color(DIM_GOLD, 0.6)
	row.border_width_bottom = 1
	_panel_var(t, "RowPanel", row)
	var row_me := _box(Color(Palette.VIP_BURGUNDY, 0.55), Color(0, 0, 0, 0), 0, 4, 12, 6)
	row_me.border_color = Palette.VIP_GOLD
	row_me.border_width_left = 4
	_panel_var(t, "RowPanelHighlight", row_me)

	var err: Error = ResourceSaver.save(t, OUT)
	print("theme written to %s (err=%d)" % [OUT, err])
	quit(0 if err == OK else 1)


func _label_var(t: Theme, name: String, font: Font, size: int, color: Color) -> void:
	t.add_type(name)
	t.set_type_variation(name, "Label")
	t.set_font("font", name, font)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)


func _panel_var(t: Theme, name: String, box: StyleBox) -> void:
	t.add_type(name)
	t.set_type_variation(name, "PanelContainer")
	t.set_stylebox("panel", name, box)


func _box(bg: Color, border: Color, border_w: int, radius: int, pad_x: int = 12, pad_y: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	s.anti_aliasing = true
	return s


## A button face: a 2 px border with a thicker darker bottom edge (a brass plaque / chip edge).
## Pressed faces sit "down" (thin bottom, text nudged one pixel lower).
func _plaque(bg: Color, border: Color, pressed: bool = false) -> StyleBoxFlat:
	var s := _box(bg, border, 2, 7, 16, 8)
	s.border_width_bottom = 2 if pressed else 5
	s.content_margin_top = 10 if pressed else 8
	s.content_margin_bottom = 7 if pressed else 8
	return s


func _line(color: Color, thickness: int, vertical: bool = false) -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.color = color
	l.thickness = thickness
	l.vertical = vertical
	return l


# --- Procedural icons (embedded in the .tres; no image files to keep in sync) -----------------

func _switch_icon(on: bool, disabled: bool) -> ImageTexture:
	var w: int = 56
	var h: int = 30
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track: Color = Palette.FELT_GREEN.lightened(0.1) if on else Color("#3A3430")
	var knob: Color = Palette.VIP_GOLD if on else Palette.CREAM.darkened(0.25)
	if disabled:
		track = track.darkened(0.5)
		knob = knob.darkened(0.5)
	var r: float = h * 0.5
	for y: int in h:
		for x: int in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx: float = clampf(p.x, r, w - r)
			var d: float = p.distance_to(Vector2(cx, r))
			var a: float = clampf(r - d, 0.0, 1.0)
			var c: Color = track
			var border: float = clampf(r - d, 0.0, 2.0)
			if border < 1.6:
				c = DIM_GOLD if not on else Palette.WARM_GOLD
			var knob_c := Vector2(w - r if on else r, r)
			var kd: float = p.distance_to(knob_c)
			var ka: float = clampf(r - 4.0 - kd, 0.0, 1.0)
			c = c.lerp(knob, ka)
			c.a = a
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _check_icon(on: bool) -> ImageTexture:
	var s: int = 28
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y: int in s:
		for x: int in s:
			var edge: bool = x < 2 or y < 2 or x >= s - 2 or y >= s - 2
			var c: Color = Palette.WARM_GOLD if edge else Palette.CASINO_BLACK
			if on and not edge and x >= 7 and x < s - 7 and y >= 7 and y < s - 7:
				c = Palette.VIP_GOLD
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## A casino chip seen from above: gold ring with notches and a cream centre.
func _chip_icon(color: Color) -> ImageTexture:
	var s: int = 26
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c0 := Vector2(s * 0.5, s * 0.5)
	var r: float = s * 0.5
	for y: int in s:
		for x: int in s:
			var p := Vector2(x + 0.5, y + 0.5)
			var d: float = p.distance_to(c0)
			var a: float = clampf(r - d, 0.0, 1.0)
			var c: Color = color
			if d > r - 2.0:
				c = Palette.CASINO_BLACK
			elif d < r * 0.45:
				c = Palette.CREAM
			else:
				var ang: float = atan2(p.y - c0.y, p.x - c0.x)
				if fmod(ang + TAU, TAU / 6.0) < 0.35:
					c = Palette.CREAM
			c.a = a
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _arrow_icon() -> ImageTexture:
	var w: int = 18
	var h: int = 12
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in h:
		for x: int in w:
			var half: float = (h - 1 - y) * (w * 0.5) / float(h)
			var inside: bool = absf(x + 0.5 - w * 0.5) <= half
			img.set_pixel(x, y, Palette.WARM_GOLD if inside else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
