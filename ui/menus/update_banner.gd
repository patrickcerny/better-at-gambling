class_name UpdateBanner
extends PanelContainer
## The main menu's "your game is out of date" card, top right (`VersionCheck`): a red-bordered
## card with UPDATE AVAILABLE, why, and which version this is. Hidden until a check says so; the
## x hides it for this menu visit.

const WIDTH: float = 460.0

var _text: Label


func _init() -> void:
	name = "UpdateBanner"
	visible = false
	custom_minimum_size = Vector2(WIDTH, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.CASINO_BLACK, 0.92)
	sb.border_color = Palette.LOSS_RED
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	sb.anti_aliasing = true
	add_theme_stylebox_override(&"panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := Label.new()
	title.name = "Title"
	title.text = "UPDATE AVAILABLE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override(&"font_color", Palette.LOSS_RED)
	title.add_theme_font_size_override(&"font_size", 26)
	top.add_child(title)
	var close := Button.new()
	close.name = "Close"
	close.text = "x"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Hide"
	close.pressed.connect(hide)
	top.add_child(close)
	_text = Label.new()
	_text.name = "Text"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(WIDTH - 32.0, 0)
	_text.add_theme_color_override(&"font_color", Palette.CREAM)
	box.add_child(_text)


## Shows the card when `verdict` says the game is behind.
func show_verdict(verdict: Dictionary) -> void:
	if not bool(verdict.get("outdated", false)):
		return
	_text.text = "%s\n\nThis is version %s." % [str(verdict.get("text", "")), Protocol.BUILD_ID]
	show()


func message() -> String:
	return _text.text
