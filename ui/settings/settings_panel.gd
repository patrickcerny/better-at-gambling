class_name SettingsPanel
extends PanelContainer
## Settings screen (Patrick: "settings, better UI: sounds, sensitivity etc."; "Different tabs for
## the settings"; "Settings resume button at the bottom"), shared by the main menu and the in-game
## pause menu. Four tabs: GAME (field of view), VIDEO, AUDIO (volumes, voice chat, mic volume and
## test) and CONTROLS (key bindings grouped Movement / Interaction / Social / Camera & system:
## click a binding, press a key or mouse button, Esc cancels; then mouse and gamepad look). Every
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
## The mic test tries a microphone that would not open again this often.
const MIC_RETRY_SECONDS: float = 2.0
## The CONTROLS tab's sections (Patrick: "structure the controls tab better, into movement,
## interaction etc"), each listing its remappable actions (`Settings.KEYBINDS`) in order.
const CONTROL_SECTIONS: Dictionary[String, Array] = {
	"MOVEMENT": [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"jump"],
	"INTERACTION": [&"interact", &"grab", &"shove", &"shake", &"item_1", &"item_2", &"item_3", &"leave_station"],
	"SOCIAL": [&"emote_wheel", &"emote_1", &"emote_2", &"emote_3", &"emote_4", &"push_to_talk", &"ping", &"leaderboard"],
	"CAMERA & SYSTEM": [&"toggle_camera", &"toggle_fullscreen", &"pause"],
}

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
## The CONTROLS tab's gamepad button next to each binding (read only).
var pad_labels: Dictionary[StringName, Label] = {}
## The CONTROLS tab's section headings, by `CONTROL_SECTIONS` title.
var control_headings: Dictionary[String, Label] = {}
## VIDEO tab: the frame limit list (`Settings.FPS_CAPS` order).
var fps_option: OptionButton
## VIDEO tab: the pixel look on/off (`video/pixel_look`, switches the world's resolution live).
var pixel_look_check: CheckButton
## Every on/off row, by "section/key", kept in step with the settings (F11 flips fullscreen anywhere).
var checks: Dictionary[String, CheckButton] = {}
## AUDIO tab: voice mode, microphone choice (`input_devices[i]` is item i), mic volume and the
## small input level meter next to TEST MICROPHONE.
var voice_mode: OptionButton
var input_device: OptionButton
var input_devices: PackedStringArray = PackedStringArray()
var mic_gain_slider: HSlider
var mic_meter: ProgressBar
## The microphone the meter reads when no match is running (main menu): started while the AUDIO
## tab shows, stopped when it closes. In a match the meter reads the voice channel's capture.
var mic_test: VoiceCapture = null
## TEST MICROPHONE: records 3 s and plays it back through the real voice path (`VoiceMicTest`).
var mic_check_button: Button
var mic_check_result: Label
var mic_check: VoiceMicTest = null
var _mutes: VoiceMuteList
var _meter_fill: StyleBoxFlat
var _mic_retry: float = 0.0


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
		style_tab(b)
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
	Settings.changed.connect(_sync_checks)


func _build_game(page: VBoxContainer) -> void:
	page.add_child(_heading("CAMERA"))
	_slider(page, "Field of view", "video", "fov", 70.0, 110.0, 1.0, false)


func _build_video(page: VBoxContainer) -> void:
	page.add_child(_heading("DISPLAY"))
	_check(page, "Fullscreen", "video", "fullscreen")
	_check(page, "VSync", "video", "vsync")
	var fps_row := _row(page, "Frame limit")
	fps_option = OptionButton.new()
	fps_option.name = "FrameLimit"
	for cap: int in Settings.FPS_CAPS:
		fps_option.add_item(Settings.fps_label(cap))
	fps_option.selected = maxi(Settings.FPS_CAPS.find(int(Settings.get_value("video", "max_fps"))), 0)
	fps_option.item_selected.connect(func(i: int) -> void: Settings.change("video", "max_fps", Settings.FPS_CAPS[i]))
	fps_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_row.add_child(fps_option)
	page.add_child(_heading("LOOK"))
	pixel_look_check = _check(page, "Pixel look", "video", "pixel_look")
	pixel_look_check.name = "PixelLook"
	var hint := Label.new()
	hint.name = "PixelLookHint"
	hint.text = "On: the casino in big, chunky pixels (retro). Off: full resolution, smooth and crisp."
	hint.theme_type_variation = &"MutedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(hint)


func _build_audio(page: VBoxContainer) -> void:
	page.add_child(_heading("SOUND"))
	_slider(page, "Master volume", "audio", "master", 0.0, 1.0, 0.05, true)
	_slider(page, "Music", "audio", "music", 0.0, 1.0, 0.05, true)
	_slider(page, "Effects", "audio", "sfx", 0.0, 1.0, 0.05, true)
	_slider(page, "Menus", "audio", "ui", 0.0, 1.0, 0.05, true)
	page.add_child(_heading("VOICE CHAT"))
	_slider(page, "Voice volume (others)", "audio", "voice", 0.0, 1.0, 0.05, true)
	var voice_row := _row(page, "Voice chat")
	voice_mode = OptionButton.new()
	voice_mode.name = "VoiceMode"
	for label: String in VoiceChannel.MODE_LABELS:
		voice_mode.add_item(label)
	voice_mode.selected = maxi(VoiceChannel.MODE_KEYS.find(str(Settings.get_value("voice", "mode"))), 0)
	voice_mode.item_selected.connect(func(i: int) -> void: Settings.change("voice", "mode", VoiceChannel.MODE_KEYS[i]))
	voice_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_row.add_child(voice_mode)
	var device_row := _row(page, "Microphone")
	input_device = OptionButton.new()
	input_device.name = "InputDevice"
	input_device.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_device.clip_text = true
	input_device.custom_minimum_size = Vector2(200, 0)
	input_device.item_selected.connect(func(i: int) -> void: Settings.change("voice", "input_device", input_devices[i]))
	device_row.add_child(input_device)
	mic_gain_slider = _slider(page, "Mic volume (your voice)", "voice", "mic_gain", 0.0, Settings.MAX_MIC_GAIN, 0.05, true)
	mic_gain_slider.name = "MicGain"
	var check_row := _row(page, "Hear yourself")
	mic_check_button = Button.new()
	mic_check_button.name = "TestMic"
	mic_check_button.text = "TEST MICROPHONE"
	mic_check_button.tooltip_text = "Records %d s and plays it back to you." % roundi(VoiceMicTest.RECORD_SECONDS)
	mic_check_button.custom_minimum_size = Vector2(220, 42)
	mic_check_button.pressed.connect(start_mic_check)
	check_row.add_child(mic_check_button)
	mic_meter = ProgressBar.new()
	mic_meter.name = "MicMeter"
	mic_meter.min_value = 0.0
	mic_meter.max_value = 1.0
	mic_meter.step = 0.0
	mic_meter.show_percentage = false
	mic_meter.custom_minimum_size = Vector2(90, 12)
	mic_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#2A1A1A")
	bg.border_color = Color(Palette.WARM_GOLD, 0.35)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(6)
	_meter_fill = StyleBoxFlat.new()
	_meter_fill.bg_color = Palette.MONEY_GREEN
	_meter_fill.set_corner_radius_all(6)
	mic_meter.add_theme_stylebox_override(&"background", bg)
	mic_meter.add_theme_stylebox_override(&"fill", _meter_fill)
	check_row.add_child(mic_meter)
	mic_check_result = Label.new()
	mic_check_result.name = "MicTestResult"
	mic_check_result.theme_type_variation = &"SmallLabel"
	mic_check_result.clip_text = true
	mic_check_result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check_row.add_child(mic_check_result)
	_mutes = VoiceMuteList.new()
	page.add_child(_mutes)


func _build_controls(page: VBoxContainer) -> void:
	var hint := Label.new()
	hint.theme_type_variation = &"SmallLabel"
	hint.text = "Click a key, then press the new key or mouse button. Esc cancels. Gamepad buttons are on the right."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(hint)
	for title: String in CONTROL_SECTIONS:
		var heading: Label = _heading(title)
		page.add_child(heading)
		control_headings[title] = heading
		if title == "MOVEMENT":
			_info_row(page, "Look", "Mouse", "Right stick")
		for action: StringName in CONTROL_SECTIONS[title]:
			_bind_row(page, action)
	_reset_keys = _button(page, "Reset keys to defaults", func() -> void:
		cancel_capture()
		Settings.reset_keybinds()
		refresh_bindings())
	_reset_keys.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	page.add_child(_heading("MOUSE"))
	_slider(page, "Mouse sensitivity", "controls", "mouse_sensitivity", 0.2, 3.0, 0.05, false)
	_check(page, "Invert mouse Y", "controls", "invert_y")
	page.add_child(_heading("GAMEPAD"))
	_slider(page, "Look speed (right stick)", "controls", "stick_sensitivity", 0.2, 3.0, 0.05, false)
	refresh_bindings()


## One remappable action: its name, the key button (click to rebind) and the gamepad button.
func _bind_row(page: VBoxContainer, action: StringName) -> void:
	var h: HBoxContainer = _row(page, Settings.KEYBINDS[action])
	var b := Button.new()
	b.name = "Bind_%s" % action
	b.custom_minimum_size = Vector2(220, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(start_capture.bind(action))
	h.add_child(b)
	bind_buttons[action] = b
	pad_labels[action] = _pad_label(h)


## A row that is not remappable (look): what drives it on each device.
func _info_row(page: VBoxContainer, text: String, keys: String, pad: String) -> void:
	var h: HBoxContainer = _row(page, text)
	var l := Label.new()
	l.text = keys
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(220, 40)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	_pad_label(h).text = pad


func _pad_label(h: HBoxContainer) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"SmallLabel"
	l.custom_minimum_size = Vector2(130, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override(&"font_color", Color(Palette.CREAM, 0.7))
	h.add_child(l)
	return l


## Shows the panel on its current tab; `p_in_game` adds RESUME next to BACK.
func open(p_in_game: bool = false) -> void:
	in_game = p_in_game
	_resume.visible = in_game
	_mutes.refresh()
	voice_mode.selected = maxi(VoiceChannel.MODE_KEYS.find(str(Settings.get_value("voice", "mode"))), 0)
	refresh_devices()
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
	_stop_mic_test()
	Settings.save()
	closed.emit()


## Shows tab `i` (`TABS` order).
## Tab look (Patrick: "the selected tab should look lit, not darker"): the tabs you are not on
## sit back as dim plaques; the selected one lights up, bright red with a gold rim, a warm glow
## and gold text. Hover brightens a dim tab a little.
static func style_tab(b: Button) -> void:
	var dim := _tab_box(Color("#3A2424"), Color(Palette.WARM_GOLD, 0.35), 2)
	var hover := _tab_box(Color("#5A2C2C"), Color(Palette.WARM_GOLD, 0.8), 2)
	var lit := _tab_box(Palette.CASINO_RED.lightened(0.12), Palette.VIP_GOLD, 3)
	lit.shadow_color = Color(Palette.VIP_GOLD, 0.45)
	lit.shadow_size = 10
	b.add_theme_stylebox_override(&"normal", dim)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"pressed", lit)
	b.add_theme_stylebox_override(&"hover_pressed", lit)
	b.add_theme_color_override(&"font_color", Color(Palette.CREAM, 0.6))
	b.add_theme_color_override(&"font_hover_color", Palette.CREAM)
	b.add_theme_color_override(&"font_pressed_color", Palette.VIP_GOLD)
	b.add_theme_color_override(&"font_hover_pressed_color", Palette.VIP_GOLD)
	b.add_theme_color_override(&"font_focus_color", Palette.CREAM)


static func _tab_box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(32)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func select_tab(i: int) -> void:
	cancel_capture()
	current_tab = clampi(i, 0, TABS.size() - 1)
	for j: int in pages.size():
		pages[j].visible = j == current_tab
		tab_buttons[j].set_pressed_no_signal(j == current_tab)
	if not _audio_showing():
		_stop_mic_test()


## Lists the microphones (`devices` defaults to the audio driver's list; "Default" always comes
## first) and selects the saved one, or Default when it is not plugged in.
func refresh_devices(devices: PackedStringArray = AudioServer.get_input_device_list()) -> void:
	input_devices = PackedStringArray([VoiceMicSource.DEFAULT_DEVICE])
	for d: String in devices:
		if d != VoiceMicSource.DEFAULT_DEVICE and not d in input_devices:
			input_devices.append(d)
	input_device.clear()
	for d: String in input_devices:
		input_device.add_item("System default" if d == VoiceMicSource.DEFAULT_DEVICE else d)
	var saved: String = str(Settings.get_value("voice", "input_device"))
	input_device.selected = maxi(input_devices.find(Settings.pick_input_device(saved, input_devices)), 0)


func _audio_showing() -> bool:
	return visible and current_tab == TABS.find("AUDIO")


## The live voice channel when it is reading the microphone (online, voice on), else null.
static func _live_channel() -> VoiceChannel:
	var ch: VoiceChannel = VoiceChannel.current
	if ch != null and is_instance_valid(ch) and ch.is_active():
		return ch
	return null


## The capture the level meter reads: the match's voice channel while voice is on, else our own
## mic test (main menu, Practice, voice switched off).
func meter_capture() -> VoiceCapture:
	var ch: VoiceChannel = _live_channel()
	return ch.capture if ch != null else mic_test


func _process(delta: float) -> void:
	if not _audio_showing():
		return
	if _live_channel() != null:
		if not mic_checking():
			_stop_meter_capture()
	elif mic_test == null:
		mic_test = VoiceCapture.new()
		mic_test.name = "MicTest"
		mic_test.mode = VoiceCapture.Mode.OFF  # level only, nothing is sent
		add_child(mic_test)
		mic_test.start_microphone()
		_mic_retry = MIC_RETRY_SECONDS
	elif not mic_test.mic_active and not mic_checking():
		_mic_retry -= delta
		if _mic_retry <= 0.0:
			_mic_retry = MIC_RETRY_SECONDS
			mic_test.start_microphone()  # plugged in / another device picked since
	var cap: VoiceCapture = meter_capture()
	var lvl: float = cap.meter_level() if cap != null else 0.0
	# -60 dBFS (room hiss) .. 0 dBFS on the bar: gold below the open-mic gate, green above it.
	var db: float = linear_to_db(lvl) if lvl > 0.00001 else -100.0
	mic_meter.value = clampf((db + 60.0) / 60.0, 0.0, 1.0)
	_meter_fill.bg_color = Palette.MONEY_GREEN if db >= VoiceCapture.OPEN_MIC_THRESHOLD_DB else Palette.WARM_GOLD
	if mic_check != null:
		mic_check_result.text = mic_check.verdict
	mic_check_button.disabled = mic_checking()
	mic_check_button.text = "TESTING…" if mic_checking() else "TEST MICROPHONE"


## TEST MICROPHONE: 3 s from the microphone the meter reads, played back through voice chat.
func start_mic_check() -> void:
	if mic_check == null:
		mic_check = VoiceMicTest.new()
		mic_check.name = "MicCheck"
		add_child(mic_check)
	if not mic_check.finished.is_connected(_on_mic_check_finished):
		mic_check.finished.connect(_on_mic_check_finished)
	mic_check.start(meter_capture())
	mic_check_result.text = mic_check.verdict


func _on_mic_check_finished(text: String) -> void:
	mic_check_result.text = text


func mic_checking() -> bool:
	return mic_check != null and mic_check.is_running()


func _stop_mic_test() -> void:
	if mic_check != null:
		mic_check.stop()
	_stop_meter_capture()


func _stop_meter_capture() -> void:
	if mic_test != null:
		mic_test.stop_microphone()
		mic_test.queue_free()
		mic_test = null


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


## Rewrites every binding button from the live InputMap (remapped keys in gold) and the gamepad
## button next to it (`InputGlyphs`, "-" for actions with none).
func refresh_bindings() -> void:
	for action: StringName in pad_labels:
		var pad: PackedStringArray = InputGlyphs.labels(action, true)
		pad_labels[action].text = " / ".join(pad) if not pad.is_empty() else "-"
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
	checks["%s/%s" % [section, key]] = c
	return c


## Shows each on/off row as the setting stands (changed elsewhere, e.g. F11 for fullscreen).
func _sync_checks() -> void:
	for path: String in checks:
		var parts: PackedStringArray = path.split("/")
		checks[path].set_pressed_no_signal(bool(Settings.get_value(parts[0], parts[1])))


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
