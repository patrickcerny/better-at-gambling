class_name SettingsPanel
extends PanelContainer
## Settings screen (Patrick: "settings, better UI: sounds, sensitivity etc."), shared by the main
## menu and the in-game pause menu. Every control applies at once through `Settings.change`; the
## file is written when the panel closes. In game it also offers Resume and Leave.

signal closed
signal leave_requested

var in_game: bool = false
var _resume: Button
var _leave: Button
var _back: Button
var _first: Control
var _mutes: VoiceMuteList


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -380
	offset_right = 380
	offset_top = -410
	offset_bottom = 400  # clear of the item bar at the bottom of the HUD
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 4)
	add_child(v)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_resume = _button(v, "Resume", close)
	v.add_child(_heading("SOUND"))
	_first = _slider(v, "Master volume", "audio", "master", 0.0, 1.0, 0.05, true)
	_slider(v, "Music", "audio", "music", 0.0, 1.0, 0.05, true)
	_slider(v, "Effects", "audio", "sfx", 0.0, 1.0, 0.05, true)
	_slider(v, "Menus", "audio", "ui", 0.0, 1.0, 0.05, true)
	v.add_child(_heading("VOICE CHAT"))
	_slider(v, "Voice volume", "audio", "voice", 0.0, 1.0, 0.05, true)
	var voice_row := _row(v, "Microphone")
	var voice_mode := OptionButton.new()
	for label: String in VoiceChannel.MODE_LABELS:
		voice_mode.add_item(label)
	voice_mode.selected = maxi(VoiceChannel.MODE_KEYS.find(str(Settings.get_value("voice", "mode"))), 0)
	voice_mode.item_selected.connect(func(i: int) -> void: Settings.change("voice", "mode", VoiceChannel.MODE_KEYS[i]))
	voice_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_row.add_child(voice_mode)
	_mutes = VoiceMuteList.new()
	v.add_child(_mutes)
	v.add_child(_heading("CONTROLS"))
	_slider(v, "Mouse sensitivity", "controls", "mouse_sensitivity", 0.2, 3.0, 0.05, false)
	_check(v, "Invert mouse Y", "controls", "invert_y")
	v.add_child(_heading("VIDEO"))
	_slider(v, "Field of view", "video", "fov", 70.0, 110.0, 1.0, false)
	_check(v, "Fullscreen", "video", "fullscreen")
	_check(v, "VSync", "video", "vsync")
	var fps_row := _row(v, "Frame limit")
	var fps := OptionButton.new()
	for cap: int in Settings.FPS_CAPS:
		fps.add_item("Unlimited" if cap == 0 else "%d FPS" % cap)
	fps.selected = maxi(Settings.FPS_CAPS.find(int(Settings.get_value("video", "max_fps"))), 0)
	fps.item_selected.connect(func(i: int) -> void: Settings.change("video", "max_fps", Settings.FPS_CAPS[i]))
	fps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_row.add_child(fps)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override(&"separation", 12)
	v.add_child(bottom)
	_leave = _button(bottom, "Leave to menu", func() -> void:
		close()
		leave_requested.emit())
	_back = _button(bottom, "Back [Esc]", close)


## Shows the panel; `p_in_game` adds Resume and Leave.
func open(p_in_game: bool = false) -> void:
	in_game = p_in_game
	_resume.visible = in_game
	_leave.visible = in_game
	_mutes.refresh()
	_back.text = "Back %s" % InputGlyphs.hint(&"ui_cancel")
	visible = true
	(_resume if in_game else _first).grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	Settings.save()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		get_viewport().set_input_as_handled()
		close()


func _row(parent: Control, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 12)
	parent.add_child(h)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(240, 0)
	h.add_child(l)
	return h


func _slider(parent: Control, text: String, section: String, key: String, lo: float, hi: float, step: float, percent: bool) -> HSlider:
	var h: HBoxContainer = _row(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(section, key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var val := Label.new()
	val.custom_minimum_size = Vector2(70, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	var show: Callable = func(x: float) -> void:
		val.text = "%d%%" % roundi(x * 100.0) if percent else ("%.2f×" % x if step < 1.0 else "%d°" % roundi(x))
	show.call(s.value)
	s.value_changed.connect(func(x: float) -> void:
		show.call(x)
		Settings.change(section, key, x)
		if section == "audio":
			Audio.play(&"ui_click", &"UI" if key == "ui" else &"SFX", -6.0))
	return s


func _check(parent: Control, text: String, section: String, key: String) -> CheckButton:
	var h: HBoxContainer = _row(parent, text)
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.get_value(section, key))
	c.toggled.connect(func(on: bool) -> void: Settings.change(section, key, on))
	h.add_child(c)
	return c


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 48)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _heading(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"HeadingLabel"
	l.text = text
	l.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	return l
