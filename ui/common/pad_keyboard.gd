class_name PadKeyboard
extends CanvasLayer
## Typing with a gamepad: `PadKeyboard.attach(edit)` makes a LineEdit open a keyboard when A is
## pressed on it (or when the game calls `PadKeyboard.open_for(edit)` itself, as Spy does on your
## turn). Steam's floating keyboard comes first (Steam Deck, Big Picture: its keys arrive as normal
## key presses); where Steam can't show one, this in-game keyboard opens at the bottom of the
## screen: the d-pad or left stick moves over the keys, A types, X deletes, Y is a space, B or
## DONE closes it (DONE also submits the text, like Enter).

const ROWS: Array[String] = ["1234567890", "QWERTYUIOP", "ASDFGHJKL'", "ZXCVBNM-.?"]
const KEY_SIZE: Vector2 = Vector2(78, 66)

## The keyboard open right now (one at a time), null when none.
static var current: PadKeyboard = null

var target: LineEdit
var keys: Array[Button] = []
var done_button: Button
var space_button: Button
var delete_button: Button
var preview: Label
var _panel: PanelContainer
## Steam's keyboard is up instead of ours (nothing here is shown).
var steam_keyboard: bool = false


## Makes `edit` open a keyboard when A is pressed on it with a gamepad.
static func attach(edit: LineEdit) -> void:
	if edit.has_meta(&"pad_keyboard"):
		return
	edit.set_meta(&"pad_keyboard", true)
	edit.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and event.is_action_pressed(&"ui_accept"):
			edit.accept_event()
			open_for(edit))


## Opens a keyboard for `edit` (Steam's if it can, else the in-game one). Returns the in-game
## keyboard, or null when Steam's opened (or `edit` can't take text).
static func open_for(edit: LineEdit) -> PadKeyboard:
	if edit == null or not edit.is_inside_tree() or not edit.editable:
		return null
	close_current()
	edit.grab_focus()
	edit.caret_column = edit.text.length()  # type on at the end
	var r: Rect2 = edit.get_global_rect()
	var xf: Transform2D = edit.get_viewport().get_final_transform() * edit.get_canvas_transform()
	var window_rect := Rect2(xf * r.position, (xf.basis_xform(r.size)).abs())
	if SteamSvc.show_text_keyboard(window_rect):
		return null
	var kb := PadKeyboard.new()
	kb.target = edit
	edit.get_tree().root.add_child(kb)
	current = kb
	return kb


static func close_current() -> void:
	if current != null and is_instance_valid(current):
		current.close(false)
	current = null


func _init() -> void:
	name = "PadKeyboard"
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = load("res://ui/theme/main_theme.tres") as Theme
	add_child(root)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_bottom = -24
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.CASINO_BLACK, 0.96)
	sb.border_color = Palette.VIP_GOLD
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(16)
	_panel.add_theme_stylebox_override(&"panel", sb)
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	_panel.add_child(v)
	preview = Label.new()
	preview.name = "Preview"
	preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview.add_theme_font_size_override(&"font_size", 30)
	preview.add_theme_color_override(&"font_color", Palette.CREAM)
	v.add_child(preview)
	var grid := GridContainer.new()
	grid.name = "Keys"
	grid.columns = ROWS[0].length()
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	v.add_child(grid)
	for row: String in ROWS:
		for i: int in row.length():
			var ch: String = row[i]
			var b := _key(ch, KEY_SIZE)
			b.pressed.connect(func() -> void: type_text(ch))
			grid.add_child(b)
			keys.append(b)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override(&"separation", 6)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bottom)
	delete_button = _key("", Vector2(180, KEY_SIZE.y))
	delete_button.pressed.connect(backspace)
	bottom.add_child(delete_button)
	space_button = _key("", Vector2(300, KEY_SIZE.y))
	space_button.pressed.connect(func() -> void: type_text(" "))
	bottom.add_child(space_button)
	done_button = _key("", Vector2(250, KEY_SIZE.y))
	done_button.theme_type_variation = &"ActionButton"
	done_button.pressed.connect(func() -> void: close(true))
	bottom.add_child(done_button)
	_relabel()
	_update_preview()
	# Up from the bottom row goes back into the letters, down from the letters onto it.
	for i: int in keys.size():
		if i >= keys.size() - ROWS[0].length():
			keys[i].focus_neighbor_bottom = space_button.get_path()
	for b: Button in [delete_button, space_button, done_button]:
		b.focus_neighbor_top = keys[keys.size() - ROWS[0].length() / 2].get_path()
	keys[ROWS[0].length()].grab_focus()  # Q
	if target != null:
		target.text_changed.connect(func(_t: String) -> void: _update_preview())


func _key(text: String, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override(&"font_size", 28)
	return b


func _relabel() -> void:
	delete_button.text = "⌫ DELETE  [%s]" % InputGlyphs.pad_name("X")
	space_button.text = "SPACE  [%s]" % InputGlyphs.pad_name("Y")
	done_button.text = "DONE  [%s]" % InputGlyphs.pad_name("Menu")


## Types `s` into the target at its caret (up to its max length).
func type_text(s: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.max_length > 0 and target.text.length() + s.length() > target.max_length:
		return
	var at: int = target.caret_column
	# Letters come out like a phone keyboard writes them: a capital at the start of a word.
	var word_start: bool = at == 0 or target.text[at - 1] == " "
	if not word_start:
		s = s.to_lower()
	target.text = target.text.insert(at, s)
	target.caret_column = at + s.length()
	target.text_changed.emit(target.text)
	Audio.play(&"ui_click", &"UI", -14.0)


func backspace() -> void:
	if target == null or not is_instance_valid(target) or target.caret_column <= 0:
		return
	var at: int = target.caret_column
	target.text = target.text.substr(0, at - 1) + target.text.substr(at)
	target.caret_column = at - 1
	target.text_changed.emit(target.text)


func _update_preview() -> void:
	if preview == null:
		return
	var t: String = target.text if target != null and is_instance_valid(target) else ""
	preview.text = t + "_" if t.length() < 64 else t


## Closes the keyboard; `submit` sends the text like Enter would (`text_submitted`).
func close(submit: bool) -> void:
	if current == self:
		current = null
	var t: LineEdit = target if target != null and is_instance_valid(target) else null
	queue_free()
	if t != null and t.is_inside_tree():
		t.grab_focus()
		if submit:
			t.text_submitted.emit(t.text)


func _input(event: InputEvent) -> void:
	if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
		close(false)
		return
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var b: JoyButton = (event as InputEventJoypadButton).button_index
		var handled: bool = true
		match b:
			JOY_BUTTON_X:
				backspace()
			JOY_BUTTON_Y:
				type_text(" ")
			JOY_BUTTON_START:
				close(true)
			JOY_BUTTON_B:
				close(false)
			_:
				handled = false
		if handled:
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel"):
		close(false)
		get_viewport().set_input_as_handled()
