class_name ConfirmDialog
extends Control
## "Are you sure?" before leaving or quitting (Patrick: "Are you sure Dialog after quit game or
## leave game (so you dont misclick)"): a dimmed full-screen overlay with a small panel, the
## question, CANCEL (focused, so a stray Enter does nothing harmful) and the action's own button.
## Esc, the pause key or a click on the dim cancels. `ask` builds one over `parent` and frees it
## again once answered: `on_yes` runs only for the action button.

## The action button was pressed.
signal confirmed
## CANCEL, Esc or a click outside the panel.
signal cancelled

var panel: PanelContainer
var title_label: Label
var text_label: Label
var yes_button: Button
var cancel_button: Button
## The control that had the focus before; it gets it back on cancel.
var _return_focus: Control


## Opens a dialog over `parent` (full rect). `on_yes` runs after CONFIRM; the dialog frees itself.
static func ask(parent: Node, title: String, text: String, yes_label: String, on_yes: Callable) -> ConfirmDialog:
	var d := ConfirmDialog.new()
	d.name = "ConfirmDialog"
	parent.add_child(d)
	d.setup(title, text, yes_label)
	d.confirmed.connect(func() -> void: on_yes.call(), CONNECT_ONE_SHOT)
	return d


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(Palette.CASINO_BLACK, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			cancel())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 16)
	panel.add_child(v)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.theme_type_variation = &"HeadingLabel"
	title_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title_label)
	text_label = Label.new()
	text_label.name = "Text"
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.custom_minimum_size = Vector2(480, 0)
	v.add_child(text_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 16)
	v.add_child(row)
	cancel_button = Button.new()
	cancel_button.name = "Cancel"
	cancel_button.text = "CANCEL"
	cancel_button.custom_minimum_size = Vector2(190, 56)
	cancel_button.pressed.connect(cancel)
	row.add_child(cancel_button)
	yes_button = Button.new()
	yes_button.name = "Yes"
	yes_button.custom_minimum_size = Vector2(190, 56)
	yes_button.add_theme_color_override(&"font_color", Palette.LOSS_RED)
	yes_button.add_theme_color_override(&"font_hover_color", Palette.LOSS_RED)
	yes_button.add_theme_color_override(&"font_focus_color", Palette.LOSS_RED)
	yes_button.pressed.connect(confirm)
	row.add_child(yes_button)


func setup(title: String, text: String, yes_label: String) -> void:
	_return_focus = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	title_label.text = title
	text_label.text = text
	text_label.visible = text != ""
	yes_button.text = yes_label
	cancel_button.grab_focus.call_deferred()
	cancel_button.grab_focus()


## The action: says so and goes.
func confirm() -> void:
	if is_queued_for_deletion():
		return
	visible = false
	confirmed.emit()
	queue_free()


## CANCEL / Esc / outside click: nothing happens, the focus goes back where it was.
func cancel() -> void:
	if is_queued_for_deletion():
		return
	visible = false
	cancelled.emit()
	if _return_focus != null and is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()
	queue_free()


## Whether a dialog under `parent` is waiting for an answer.
static func open_in(parent: Node) -> ConfirmDialog:
	for c: Node in parent.get_children():
		if c is ConfirmDialog and not c.is_queued_for_deletion():
			return c as ConfirmDialog
	return null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		cancel()
