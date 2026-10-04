extends SceneTree
## Generates ui/theme/main_theme.tres from the palette and Barlow Condensed fonts.
## Run: tools/godot/godot --headless --path . -s tools/gen_theme.gd

const OUT: String = "res://ui/theme/main_theme.tres"


func _init() -> void:
	var t := Theme.new()
	var black: FontFile = load("res://assets/fonts/BarlowCondensed-Black.ttf")
	var bold: FontFile = load("res://assets/fonts/BarlowCondensed-ExtraBold.ttf")
	var semi: FontFile = load("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	var medium: FontFile = load("res://assets/fonts/BarlowCondensed-Medium.ttf")
	t.default_font = semi
	t.default_font_size = 24

	# Panels: dark, rounded, gold hairline.
	var panel := _box(Palette.WARM_CHARCOAL, Palette.WARM_GOLD, 2, 10)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "PanelContainer", panel)
	var popup := _box(Palette.CASINO_BLACK, Palette.WARM_GOLD, 2, 12)
	t.set_stylebox("panel", "PopupPanel", popup)

	# Buttons: cream on charcoal, gold focus, red pressed.
	var b_normal := _box(Color("#2E2A27"), Color("#6B5A33"), 2, 8, 10, 6)
	var b_hover := _box(Color("#3A3430"), Palette.WARM_GOLD, 2, 8, 10, 6)
	var b_pressed := _box(Palette.CASINO_RED, Palette.VIP_GOLD, 2, 8, 10, 6)
	var b_focus := _box(Color(0, 0, 0, 0), Palette.VIP_GOLD, 3, 8, 10, 6)
	var b_disabled := _box(Color("#1E1B19"), Color("#3A3430"), 2, 8, 10, 6)
	for cls: String in ["Button", "CheckButton", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", cls, b_normal)
		t.set_stylebox("hover", cls, b_hover)
		t.set_stylebox("pressed", cls, b_pressed)
		t.set_stylebox("focus", cls, b_focus)
		t.set_stylebox("disabled", cls, b_disabled)
		t.set_font("font", cls, bold)
		t.set_font_size("font_size", cls, 26)
		t.set_color("font_color", cls, Palette.CREAM)
		t.set_color("font_hover_color", cls, Palette.VIP_GOLD)
		t.set_color("font_pressed_color", cls, Palette.CREAM)
		t.set_color("font_focus_color", cls, Palette.VIP_GOLD)
		t.set_color("font_disabled_color", cls, Color("#6B625A"))

	t.set_font("font", "Label", semi)
	t.set_color("font_color", "Label", Palette.CREAM)
	t.set_font("normal_font", "RichTextLabel", medium)
	t.set_color("default_color", "RichTextLabel", Palette.CREAM)

	var line := _box(Palette.CASINO_BLACK, Color("#6B5A33"), 2, 6, 8, 4)
	t.set_stylebox("normal", "LineEdit", line)
	t.set_stylebox("focus", "LineEdit", _box(Palette.CASINO_BLACK, Palette.WARM_GOLD, 2, 6, 8, 4))
	t.set_color("font_color", "LineEdit", Palette.CREAM)
	t.set_font("font", "LineEdit", medium)

	t.set_stylebox("slider", "HSlider", _box(Color("#3A3430"), Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("grabber_area", "HSlider", _box(Palette.WARM_GOLD, Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(Palette.VIP_GOLD, Color(0, 0, 0, 0), 0, 4))

	t.set_stylebox("panel", "ProgressBar", _box(Palette.CASINO_BLACK, Color("#6B5A33"), 1, 4))
	t.set_stylebox("fill", "ProgressBar", _box(Palette.WARM_GOLD, Color(0, 0, 0, 0), 0, 4))

	# Named variations.
	t.add_type("TitleLabel")
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", black)
	t.set_font_size("font_size", "TitleLabel", 64)
	t.set_color("font_color", "TitleLabel", Palette.CREAM)
	t.add_type("HeadingLabel")
	t.set_type_variation("HeadingLabel", "Label")
	t.set_font("font", "HeadingLabel", bold)
	t.set_font_size("font_size", "HeadingLabel", 36)
	t.set_color("font_color", "HeadingLabel", Palette.WARM_GOLD)
	t.add_type("MoneyLabel")
	t.set_type_variation("MoneyLabel", "Label")
	t.set_font("font", "MoneyLabel", black)
	t.set_font_size("font_size", "MoneyLabel", 48)
	t.set_color("font_color", "MoneyLabel", Palette.CREAM)
	t.add_type("SmallLabel")
	t.set_type_variation("SmallLabel", "Label")
	t.set_font("font", "SmallLabel", medium)
	t.set_font_size("font_size", "SmallLabel", 18)
	t.add_type("MenuButton")
	t.set_type_variation("MenuButton", "Button")
	t.set_stylebox("normal", "MenuButton", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 12, 4))
	t.set_stylebox("hover", "MenuButton", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 12, 4))
	t.set_stylebox("pressed", "MenuButton", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 12, 4))
	t.set_stylebox("focus", "MenuButton", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 12, 4))
	t.set_font("font", "MenuButton", black)
	t.set_font_size("font_size", "MenuButton", 44)
	t.set_color("font_color", "MenuButton", Palette.CREAM)
	t.set_color("font_hover_color", "MenuButton", Palette.WARM_GOLD)
	t.set_color("font_focus_color", "MenuButton", Palette.WARM_GOLD)
	t.add_type("ChipButton")
	t.set_type_variation("ChipButton", "Button")
	t.set_stylebox("normal", "ChipButton", _box(Palette.CASINO_RED, Palette.CREAM, 3, 32, 6, 6))
	t.set_stylebox("hover", "ChipButton", _box(Color("#E04A4A"), Palette.VIP_GOLD, 3, 32, 6, 6))
	t.set_stylebox("pressed", "ChipButton", _box(Palette.VIP_BURGUNDY, Palette.VIP_GOLD, 3, 32, 6, 6))
	t.set_stylebox("focus", "ChipButton", _box(Color(0, 0, 0, 0), Palette.VIP_GOLD, 4, 32, 6, 6))
	t.set_stylebox("disabled", "ChipButton", _box(Color("#3A3430"), Color("#6B625A"), 3, 32, 6, 6))
	t.set_font("font", "ChipButton", black)
	t.set_font_size("font_size", "ChipButton", 22)

	var err: Error = ResourceSaver.save(t, OUT)
	print("theme written to %s (err=%d)" % [OUT, err])
	quit(0 if err == OK else 1)


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
	return s
