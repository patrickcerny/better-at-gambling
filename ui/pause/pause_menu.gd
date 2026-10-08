class_name PauseMenu
extends Control
## The in-match Escape menu (Patrick: "When pressed Escape you dont get into the settings
## directly. You go into the menu where you can press resume, leave, quitgame and settings on
## bottom right"). RESUME first (Esc does the same), then LEAVE (back to the main menu, out of the
## party) and QUIT GAME; a small gear in the panel's bottom-right corner opens the settings, whose
## BACK returns here and whose RESUME goes straight back to play. The match keeps running behind
## it (online games can't pause); the match scene owns the input mode while it is open.

## RESUME, Esc, or RESUME in the settings: back to play.
signal resumed
signal leave_requested
signal quit_requested

var panel: PanelContainer
var settings: SettingsPanel
var resume_button: Button
var leave_button: Button
var quit_button: Button
var settings_button: GearButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(Palette.CASINO_BLACK, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # no clicks through to the casino
	add_child(dim)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 14)
	panel.add_child(v)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	resume_button = _button(v, "RESUME", resume)
	resume_button.theme_type_variation = &"ActionButton"
	leave_button = _button(v, "LEAVE TO MENU", func() -> void:
		close()
		leave_requested.emit())
	quit_button = _button(v, "QUIT GAME", func() -> void:
		close()
		quit_requested.emit())
	var bottom := HBoxContainer.new()
	bottom.name = "Bottom"
	bottom.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(bottom)
	settings_button = GearButton.new()
	settings_button.name = "SettingsButton"
	settings_button.pressed.connect(open_settings)
	bottom.add_child(settings_button)
	settings = SettingsPanel.new()
	settings.name = "Settings"
	add_child(settings)
	settings.closed.connect(_on_settings_closed)
	settings.resume_requested.connect(resume)


func open() -> void:
	visible = true
	panel.visible = true
	resume_button.grab_focus()


## Hides the menu (and the settings) without resuming: the caller sets the input mode.
func close() -> void:
	if not visible:
		return
	visible = false
	settings.close()  # saves; `_on_settings_closed` ignores it now that we are hidden


func resume() -> void:
	close()
	resumed.emit()


## Esc: out of the settings back to this menu, or out of this menu back to play.
func back() -> void:
	if not visible:
		return
	if settings.visible:
		settings.close()
	else:
		resume()


func open_settings() -> void:
	panel.visible = false
	settings.open(true)


func _on_settings_closed() -> void:
	if not visible:
		return
	panel.visible = true
	settings_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and not settings.visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		get_viewport().set_input_as_handled()
		resume()


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 60)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
