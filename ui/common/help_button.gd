class_name HelpButton
extends GearButton
## The tutorial button (Patrick: "theres a questionmark button just like the settings where you
## can see it again"): the gear's square button with a "?" in a ring drawn in code instead of the
## cog. Sits next to the settings gear in the main menu and in the pause menu and opens the
## `HowToPlayPanel`.


func _init() -> void:
	super()
	tooltip_text = "How to play"


func _draw() -> void:
	var hot: bool = has_focus() or is_hovered() or button_pressed
	var col: Color = Palette.VIP_GOLD if hot else Palette.CREAM
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5
	draw_arc(c, r * 0.62, 0.0, TAU, 48, col, maxf(r * 0.1, 2.0), true)
	var font: Font = get_theme_font(&"font")
	var fs: int = int(r * 0.95)
	var baseline: float = c.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	draw_string(font, Vector2(0.0, baseline), "?", HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, col)
