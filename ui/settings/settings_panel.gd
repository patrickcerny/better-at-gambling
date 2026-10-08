class_name SettingsPanel
extends PanelContainer
## Settings screen (Patrick: "settings, better UI: sounds, sensitivity etc."; "Different tabs for
## the settings"; "Settings resume button at the bottom"), shared by the main menu and the in-game
## pause menu. Four tabs: GAME (mouse, field of view), VIDEO, AUDIO (volumes, voice chat) and
## CONTROLS (key remapping: click a binding, press a key or mouse button, Esc cancels). Every
## control applies at once through `Settings`; the file is written when the panel closes. BACK
## (and Esc) returns to whoever opened it; in game RESUME also goes straight back to play.

## BACK / Esc: back to the menu that opened the panel.
signal closed
## In game, RESUME: close the panel and the pause menu and play on.
signal resume_requested

## Bus each volume slider previews its click on (music is audible already).
const PREVIEW_BUS: Dictionary = {"master": &"SFX", "sfx": &"SFX", "ui": &"UI", "voice": &"Voice"}
const TABS: Array[String] = ["GAME", "VIDEO", "AUDIO", "CONTROLS"]
const CAPTURE_TEXT: String = "Press a key…"

var in_game: bool = false
## Index into `TABS` of the page showing.
var current_tab: int = 0
## The tab buttons, in `TABS` order.
var tab_buttons: Array[Button] = []
## The tab pages, in `TABS` order (only the current one is visible).
var pages: Array[VBoxContainer] = []
## Action whose binding is waiting for a key press (&"" when none).
var capturing: StringName = &""
## The CONTROLS tab's binding button for each remappable action.
var bind_buttons: Dictionary[StringName, Button] = {}
var _resume: Button
var _back: Button
var _reset_keys: Button
var _mutes: VoiceMuteList


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -400
	offset_right = 400
	offset_top = -410
	offset_bottom = 400  # clear of the item bar at the bottom of the HUD
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	add_child(v)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override(&"separation", 8)
	v.add_child(tabs)
	var group := ButtonGroup.new()
	for i: int in TABS.size():
		var b := Button.new()
		b.name = "Tab%s" % TABS[i].capitalize()
		b.text = TABS[i]
		b.theme_type_variation = &"ChipButton"
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(170, 48)
		b.pressed.connect(select_tab.bind(i))
		tabs.add_child(b)
		tab_buttons.append(b)
	v.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(holder)
	for t: String in TABS:
		var page := VBoxContainer.new()
		page.name = t.capitalize()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override(&"separation", 6)
		holder.add_child(page)
		pages.append(page)
	_build_game(pages[0])
	_build_video(pages[1])
	_build_audio(pages[2])
	_build_controls(pages[3])
	var bottom := HBoxContainer.new()
	bottom.name = "Bottom"
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override(&"separation", 12)
	v.add_child(bottom)
	_back = _button(bottom, "BACK", close)
	_resume = _button(bottom, "RESUME", func() -> void:
		close()
		resume_requested.emit())
	_resume.theme_type_variation = &"ActionButton"
	select_tab(0)


func _build_game(page: VBoxContainer) -> void:
	page.add_child(_heading("MOUSE"))
	_slider(page, "Mouse sensitivity", "controls", "mouse_sensitivity", 0.2, 3.0, 0.05, false)
	_check(page, "Invert mouse Y", "controls", "invert_y")
	page.add_child(_heading("CAMERA"))
	_slider(page, "Field of view", "video", "fov", 70.0, 110.0, 1.0, false)


func _build_video(page: VBoxContainer) -> void:
	page.add_child(_heading("DISPLAY"))
	_check(page, "Fullscreen", "video", "fullscreen")
	_check(page, "VSync", "video", "vsync")
	var fps_row := _row(page, "Frame limit")
	var fps := OptionButton.new()
	for cap: int in Settings.FPS_CAPS:
		fps.add_item("Unlimited" if cap == 0 else "%d FPS" % cap)
	fps.selected = maxi(Settings.FPS_CAPS.find(int(Settings.get_value("video", "max_fps"))), 0)
	fps.item_selected.connect(func(i: int) -> void: Settings.change("video", "max_fps", Settings.FPS_CAPS[i]))
	fps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_row.add_child(fps)


func _build_audio(page: VBoxContainer) -> void:
	page.add_child(_heading("SOUND"))
	_slider(page, "Master volume", "audio", "master", 0.0, 1.0, 0.05, true)
	_slider(page, "Music", "audio", "music", 0.0, 1.0, 0.05, true)
	_slider(page, "Effects", "audio", "sfx", 0.0, 1.0, 0.05, true)
	_slider(page, "Menus", "audio", "ui", 0.0, 1.0, 0.05, true)
	page.add_child(_heading("VOICE CHAT"))
	_slider(page, "Voice volume", "audio", "voice", 0.0, 1.0, 0.05, true)
	var voice_row := _row(page, "Microphone")
	var voice_mode := OptionButton.new()
	for label: String in VoiceChannel.MODE_LABELS:
		voice_mode.add_item(label)
	voice_mode.selected = maxi(VoiceChannel.MODE_KEYS.find(str(Settings.get_value("voice", "mode"))), 0)
	voice_mode.item_selected.connect(func(i: int) -> void: Settings.change("voice", "mode", VoiceChannel.MODE_KEYS[i]))
	voice_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_row.add_child(voice_mode)
	_mutes = VoiceMuteList.new()
	page.add_child(_mutes)


func _build_controls(page: VBoxContainer) -> void:
	page.add_child(_heading("KEYBOARD & MOUSE"))
	var hint := Label.new()
	hint.theme_type_variation = &"SmallLabel"
	hint.text = "Click a binding, then press a key or mouse button. Esc cancels. Saved on this PC."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(hint)
	for action: StringName in Settings.KEYBINDS:
		var h: HBoxContainer = _row(page, Settings.KEYBINDS[action])
		var b := Button.new()
		b.name = "Bind_%s" % action
		b.custom_minimum_size = Vector2(220, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(start_capture.bind(action))
		h.add_child(b)
		bind_buttons[action] = b
	_reset_keys = _button(page, "Reset to defaults", func() -> void:
		cancel_capture()
		Settings.reset_keybinds()
		refresh_bindings())
	_reset_keys.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	refresh_bindings()


## Shows the panel on its current tab; `p_in_game` adds RESUME next to BACK.
func open(p_in_game: bool = false) -> void:
	in_game = p_in_game
	_resume.visible = in_game
	_mutes.refresh()
	refresh_bindings()
	_back.text = "BACK %s" % InputGlyphs.hint(&"ui_cancel")
	visible = true
	select_tab(current_tab)
	tab_buttons[current_tab].grab_focus()


func close() -> void:
	if not visible:
		return
	cancel_capture()
	visible = false
	Settings.save()
	closed.emit()


## Shows tab `i` (`TABS` order).
func select_tab(i: int) -> void:
	cancel_capture()
	current_tab = clampi(i, 0, TABS.size() - 1)
	for j: int in pages.size():
		pages[j].visible = j == current_tab
		tab_buttons[j].set_pressed_no_signal(j == current_tab)


## Waits for the next key or mouse button press to bind to `action`.
func start_capture(action: StringName) -> void:
	cancel_capture()
	capturing = action
	bind_buttons[action].text = CAPTURE_TEXT


## Stops waiting for a key (the binding stays as it was).
func cancel_capture() -> void:
	if capturing == &"":
		return
	capturing = &""
	refresh_bindings()


## Rewrites every binding button from the live InputMap (remapped keys in gold).
func refresh_bindings() -> void:
	for action: StringName in bind_buttons:
		var b: Button = bind_buttons[action]
		b.text = Settings.binding_label(action)
		if Settings.is_rebound(action):
			b.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		else:
			b.remove_theme_color_override(&"font_color")


## While a binding waits for a key, every key and mouse button goes to it (before the GUI and the
## game): Esc cancels, anything else bindable becomes the new binding.
func _input(event: InputEvent) -> void:
	if capturing == &"" or not visible:
		return
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and (event as InputEventKey).pressed and ((event as InputEventKey).keycode == KEY_ESCAPE or (event as InputEventKey).physical_keycode == KEY_ESCAPE):
		var b: Button = bind_buttons[capturing]
		cancel_capture()
		b.grab_focus()
		return
	if Settings.is_bindable(event):
		var action: StringName = capturing
		capturing = &""
		Settings.bind_key(action, event)
		refresh_bindings()
		bind_buttons[action].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and capturing == &"" and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		get_viewport().set_input_as_handled()
		close()


func _row(parent: Control, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 12)
	parent.add_child(h)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(260, 0)
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
		if section == "audio" and key != "music":
			Audio.play(&"ui_click", PREVIEW_BUS.get(key, &"SFX"), -6.0))
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
	b.custom_minimum_size = Vector2(220, 52)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _heading(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"HeadingLabel"
	l.text = text
	l.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	return l
