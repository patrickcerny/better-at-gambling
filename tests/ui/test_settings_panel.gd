extends GutTest
## Settings panel: four tabs (GAME, VIDEO, AUDIO, CONTROLS), BACK / RESUME at the bottom (RESUME
## only in game), changes apply at once, Esc closes it, and the CONTROLS tab remaps keys: click a
## binding, press a key (Esc cancels), saved locally in the settings file and shown by InputGlyphs.

const FakeMicTest = preload("res://tests/unit/test_voice_mic.gd")

var panel: SettingsPanel
var _old_sens: float
var _old_fov: float


func before_each() -> void:
	_old_sens = float(Settings.get_value("controls", "mouse_sensitivity"))
	_old_fov = float(Settings.get_value("video", "fov"))
	Settings.reset_keybinds()
	InputGlyphs.set_gamepad(false)
	panel = SettingsPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(2)


func after_each() -> void:
	Settings.change("controls", "mouse_sensitivity", _old_sens)
	Settings.change("video", "fov", _old_fov)
	Settings.reset_keybinds()
	Settings.save()


func _key(code: Key, pressed: bool = true) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.keycode = code
	k.pressed = pressed
	return k


func test_four_tabs_and_one_page_at_a_time() -> void:
	assert_eq(SettingsPanel.TABS, ["GAME", "VIDEO", "AUDIO", "CONTROLS"] as Array[String])
	assert_eq(panel.tab_buttons.size(), 4)
	assert_eq(panel.pages.size(), 4)
	panel.open(false)
	for i: int in 4:
		panel.tab_buttons[i].pressed.emit()
		assert_eq(panel.current_tab, i)
		for j: int in 4:
			assert_eq(panel.pages[j].visible, i == j, "tab %d shows page %d only" % [i, i])
			assert_eq(panel.tab_buttons[j].button_pressed, i == j)


## Patrick: "the selected tab should look lit, not darker".
func test_the_selected_tab_looks_lit() -> void:
	panel.open(false)
	panel.select_tab(1)
	await wait_process_frames(1)
	var b: Button = panel.tab_buttons[1]
	var lit: StyleBoxFlat = b.get_theme_stylebox(&"pressed") as StyleBoxFlat
	var dim: StyleBoxFlat = b.get_theme_stylebox(&"normal") as StyleBoxFlat
	assert_not_null(lit)
	assert_not_null(dim)
	if lit == null or dim == null:
		return
	assert_gt(lit.bg_color.get_luminance(), dim.bg_color.get_luminance() + 0.05, "selected is brighter than the others")
	assert_gt(lit.shadow_size, 0, "with a glow")
	assert_eq(b.get_theme_color(&"font_pressed_color"), Palette.VIP_GOLD, "gold text when selected")
	assert_lt(b.get_theme_color(&"font_color").a, 1.0, "the other tabs' text is dimmed")
	assert_eq(b.get_theme_stylebox(&"hover_pressed"), lit, "hovering the selected tab keeps it lit")
	for other: Button in panel.tab_buttons:
		assert_eq(other.get_theme_stylebox(&"pressed"), other.get_theme_stylebox(&"hover_pressed"))


func test_back_and_resume_sit_at_the_bottom() -> void:
	panel.open(false)
	await wait_process_frames(1)
	assert_true(panel.visible)
	assert_false(panel._resume.visible, "no RESUME from the main menu")
	assert_true(panel._back.visible)
	var bottom: Node = panel._back.get_parent()
	assert_eq(bottom.get_index(), bottom.get_parent().get_child_count() - 1, "the button row is last in the panel")
	panel.close()
	panel.open(true)
	await wait_process_frames(1)
	assert_true(panel._resume.visible, "RESUME in game")
	assert_eq(panel._resume.get_parent(), bottom)
	assert_gt(panel._resume.get_global_rect().position.y, panel.pages[0].get_global_rect().end.y - 1.0, "below the page")
	watch_signals(panel)
	panel._resume.pressed.emit()
	assert_false(panel.visible)
	assert_signal_emitted(panel, "closed")
	assert_signal_emitted(panel, "resume_requested")


func test_sensitivity_applies_live() -> void:
	var router := InputRouter.new()
	add_child_autofree(router)
	Settings.change("controls", "mouse_sensitivity", 2.0)
	assert_almost_eq(router.mouse_sensitivity, Settings.BASE_MOUSE * 2.0, 0.00001)


func test_escape_closes_and_emits_closed() -> void:
	panel.open(true)
	watch_signals(panel)
	var k := InputEventAction.new()
	k.action = &"ui_cancel"
	k.pressed = true
	get_tree().root.push_input(k)
	await wait_process_frames(2)
	assert_false(panel.visible)
	assert_signal_emitted(panel, "closed")
	assert_signal_not_emitted(panel, "resume_requested")


func test_controls_tab_lists_every_remappable_action() -> void:
	for action: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"interact", &"shove", &"grab", &"shake", &"item_1", &"item_2", &"item_3", &"emote_wheel", &"leaderboard", &"ping", &"toggle_camera", &"leave_station", &"pause"]:
		assert_true(panel.bind_buttons.has(action), "%s can be remapped" % action)
	assert_eq(panel.bind_buttons[&"jump"].text, "Space")
	assert_eq(panel.bind_buttons[&"interact"].text, "E")
	assert_eq(panel.bind_buttons[&"grab"].text, "LMB")


func test_capture_binds_the_next_key_and_saves_it_locally() -> void:
	panel.open(true)
	panel.select_tab(3)
	panel.bind_buttons[&"jump"].pressed.emit()
	assert_eq(panel.capturing, &"jump")
	assert_eq(panel.bind_buttons[&"jump"].text, SettingsPanel.CAPTURE_TEXT)
	get_tree().root.push_input(_key(KEY_J))
	await wait_process_frames(1)
	assert_eq(panel.capturing, &"", "one key is enough")
	assert_eq(panel.bind_buttons[&"jump"].text, "J")
	assert_true(panel.visible, "the key went to the binding, not the panel")
	# The InputMap follows: J jumps, Space no longer does; the pad button stays.
	assert_true(InputMap.event_is_action(_key(KEY_J), &"jump"), "J is bound")
	assert_false(InputMap.event_is_action(_key(KEY_SPACE), &"jump"), "Space is not jump any more")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	assert_true(InputMap.event_is_action(pad, &"jump"), "gamepad binding untouched")
	assert_eq(InputGlyphs.labels(&"jump", false)[0], "J", "key hints show the new key")
	# Saved in the local settings file (user://), under its own section.
	assert_eq(str(Settings.get_value(Settings.KEYBIND_SECTION, "jump", "")), "key:%d" % KEY_J)
	assert_true(Settings.PATH.begins_with("user://"))
	panel.close()
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(Settings.PATH), OK)
	assert_eq(str(cfg.get_value(Settings.KEYBIND_SECTION, "jump", "")), "key:%d" % KEY_J, "persisted on close")


func test_escape_cancels_a_capture() -> void:
	panel.open(true)
	panel.select_tab(3)
	panel.start_capture(&"interact")
	get_tree().root.push_input(_key(KEY_ESCAPE))
	await wait_process_frames(1)
	assert_eq(panel.capturing, &"")
	assert_true(panel.visible, "Esc cancelled the capture, not the panel")
	assert_eq(panel.bind_buttons[&"interact"].text, "E", "binding unchanged")
	assert_false(Settings.is_rebound(&"interact"))


func test_mouse_buttons_bind_too_and_reset_restores_defaults() -> void:
	panel.open(true)
	panel.start_capture(&"shove")
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_MIDDLE
	m.pressed = true
	get_tree().root.push_input(m)
	await wait_process_frames(1)
	assert_eq(panel.bind_buttons[&"shove"].text, "MMB")
	assert_true(Settings.is_rebound(&"shove"))
	panel._reset_keys.pressed.emit()
	assert_false(Settings.is_rebound(&"shove"))
	assert_eq(panel.bind_buttons[&"shove"].text, "RMB")
	assert_eq(InputGlyphs.labels(&"shove", false)[0], "RMB")
	assert_false(Settings._cfg.has_section(Settings.KEYBIND_SECTION), "nothing left in the file")


func test_saved_bindings_apply_to_the_input_map() -> void:
	Settings.set_value(Settings.KEYBIND_SECTION, "item_1", "key:%d" % KEY_F)
	Settings.set_value(Settings.KEYBIND_SECTION, "move_forward", "key:%d" % KEY_I)
	Settings.apply_keybinds()
	assert_true(InputMap.event_is_action(_key(KEY_F), &"item_1"))
	assert_false(InputMap.event_is_action(_key(KEY_1), &"item_1"))
	assert_true(InputMap.event_is_action(_key(KEY_I), &"move_forward"))
	assert_true(InputMap.event_is_action(_key(KEY_UP), &"move_forward"), "the arrow key stays as a second binding")
	assert_false(InputMap.event_is_action(_key(KEY_W), &"move_forward"))
	assert_eq(InputGlyphs.fill("[{item_1}]"), "[F]")
	Settings.set_value(Settings.KEYBIND_SECTION, "jump", "garbage")
	Settings.apply_keybinds()
	assert_true(InputMap.event_is_action(_key(KEY_SPACE), &"jump"), "a broken entry falls back to the default")


## Patrick: "Input device selector in settings (use default microphone normally but can select in
## settings)".
func test_audio_tab_lists_microphones_with_default_first_and_saves_the_choice() -> void:
	var old: String = str(Settings.get_value("voice", "input_device"))
	panel.open(false)
	panel.select_tab(SettingsPanel.TABS.find("AUDIO"))
	assert_true(panel.input_device.is_visible_in_tree(), "on the AUDIO tab")
	assert_true(panel.voice_mode.is_visible_in_tree(), "next to the voice mode")
	assert_eq(panel.input_devices[0], "Default")
	assert_eq(panel.input_device.get_item_text(0), "System default")
	panel.refresh_devices(PackedStringArray(["Default", "USB Headset", "Webcam Mic"]))
	assert_eq(panel.input_device.item_count, 3)
	assert_eq(panel.input_device.selected, 0, "Default unless the player picked another")
	panel.input_device.select(1)
	panel.input_device.item_selected.emit(1)
	assert_eq(str(Settings.get_value("voice", "input_device")), "USB Headset", "saved in settings.cfg")
	panel.refresh_devices(PackedStringArray(["Default", "Webcam Mic", "USB Headset"]))
	assert_eq(panel.input_devices[panel.input_device.selected], "USB Headset", "the saved one stays selected")
	panel.refresh_devices(PackedStringArray(["Default", "Webcam Mic"]))
	assert_eq(panel.input_device.selected, 0, "unplugged: Default")
	Settings.change("voice", "input_device", old)


func test_voice_mode_option_writes_the_key_the_voice_channel_reads() -> void:
	var old: String = str(Settings.get_value("voice", "mode"))
	panel.open(false)
	for i: int in VoiceChannel.MODE_KEYS.size():
		panel.voice_mode.select(i)
		panel.voice_mode.item_selected.emit(i)
		assert_eq(str(Settings.get_value("voice", "mode")), VoiceChannel.MODE_KEYS[i])
	Settings.change("voice", "mode", old)


func test_mic_meter_tests_the_microphone_while_the_audio_tab_shows() -> void:
	panel.open(false)
	panel.select_tab(SettingsPanel.TABS.find("AUDIO"))
	await wait_process_frames(2)
	assert_not_null(panel.mic_test, "outside a match the panel opens the mic itself")
	assert_eq(panel.meter_capture(), panel.mic_test)
	assert_true(panel.mic_meter.is_visible_in_tree())
	assert_eq(panel.mic_meter.get_parent(), panel.mic_check_button.get_parent(), "a small meter next to TEST MICROPHONE")
	assert_eq(panel.mic_meter.value, 0.0)
	# A microphone that hears something moves the bar.
	panel.mic_test.feed_mono(VoiceWav.tone(300.0, 0.2, 48000, 0.3), 48000)
	await wait_process_frames(1)
	assert_gt(panel.mic_meter.value, 0.5, "speech level fills most of the bar")
	panel.select_tab(0)
	assert_null(panel.mic_test, "leaving the tab closes the microphone")
	panel.select_tab(SettingsPanel.TABS.find("AUDIO"))
	await wait_process_frames(1)
	assert_not_null(panel.mic_test)
	panel.close()
	assert_null(panel.mic_test, "closing the panel closes it too")


## Patrick: "remove all of this unneeded microphone info (was good for testing, now useless)".
func test_audio_tab_has_no_voice_diagnostics_on_screen() -> void:
	panel.open(false)
	panel.select_tab(SettingsPanel.TABS.find("AUDIO"))
	await wait_process_frames(2)
	var texts: Array[String] = []
	_collect_texts(panel, texts)
	for t: String in texts:
		assert_false(t.contains("Voice status"), "no voice status line: %s" % t)
		assert_false(t.contains("Windows privacy"), "no long diagnostics: %s" % t)
		assert_false(t.contains("No microphone"), "no microphone error text: %s" % t)
	assert_eq(panel.mic_check_result.text, "", "nothing next to the button until it is pressed")
	assert_null(panel.find_child("VoiceDiag", true, false))
	assert_null(panel.find_child("MicStatus", true, false))
	panel.close()


func _collect_texts(n: Node, out: Array[String]) -> void:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c: Node in n.get_children():
		_collect_texts(c, out)


func test_test_microphone_without_an_audio_device_says_so() -> void:
	panel.open(false)
	panel.select_tab(SettingsPanel.TABS.find("AUDIO"))
	await wait_process_frames(2)
	assert_true(panel.mic_check_button.is_visible_in_tree())
	panel.mic_check_button.pressed.emit()
	await wait_process_frames(1)
	assert_eq(panel.mic_check_result.text, VoiceMicTest.NOTHING, "one short line")
	assert_false(panel.mic_check_button.disabled, "nothing running: try again any time")
	panel.close()


func test_test_microphone_records_and_plays_back_through_voice_chat() -> void:
	var old_gain: float = float(Settings.get_value("voice", "mic_gain"))
	Settings.change("voice", "mic_gain", 1.0)
	panel.open(false)
	panel.select_tab(SettingsPanel.TABS.find("AUDIO"))
	await wait_process_frames(2)
	var mic: FakeMicTest.FakeMic = FakeMicTest.FakeMic.new()
	mic.tone_hz = 440.0
	panel.mic_check = VoiceMicTest.new()
	panel.mic_check.source_override = mic
	panel.add_child(panel.mic_check)
	panel.mic_check_button.pressed.emit()
	assert_true(panel.mic_checking())
	assert_eq(panel.mic_check_result.text, VoiceMicTest.RECORDING)
	var last: int = Time.get_ticks_msec()
	var waited: int = 0
	while panel.mic_checking() and waited < 10000:
		await get_tree().process_frame
		var now: int = Time.get_ticks_msec()
		mic.speak((now - last) / 1000.0, 0.3)  # the microphone delivers in real time
		waited += now - last
		last = now
	await wait_process_frames(1)
	assert_eq(panel.mic_check_result.text, "Microphone works")
	assert_between(linear_to_db(panel.mic_check.peak), -12.0, -10.0, "a 0.3 tone peaks at -10.5 dBFS")
	var played: int = panel.mic_check.playback.frames_played if panel.mic_check.playback != null else 0
	assert_between(played, 70, 76, "3 s of 40 ms frames came back out of the playback")
	assert_eq(played, panel.mic_check.frames.size(), "every recorded frame was played")
	panel.close()
	assert_false(panel.mic_checking())
	Settings.change("voice", "mic_gain", old_gain)


## Patrick: "change your voice loudness (so like an amplifier if the mic is too loud and stuff)".
func test_mic_volume_slider_goes_to_200_percent_and_drives_the_capture() -> void:
	var old_gain: float = float(Settings.get_value("voice", "mic_gain"))
	panel.open(false)
	panel.select_tab(SettingsPanel.TABS.find("AUDIO"))
	await wait_process_frames(2)
	var s: HSlider = panel.mic_gain_slider
	assert_true(s.is_visible_in_tree(), "on the AUDIO tab")
	assert_eq(s.min_value, 0.0)
	assert_eq(s.max_value, 2.0, "up to 200 %")
	var row: Node = s.get_parent()
	assert_eq((row.get_child(0) as Label).text, "Mic volume (your voice)")
	assert_eq((row.get_child(2) as Label).text, "%d%%" % roundi(s.value * 100.0))
	s.value = 1.5
	assert_almost_eq(float(Settings.get_value("voice", "mic_gain")), 1.5, 0.001, "saved in settings")
	assert_eq((row.get_child(2) as Label).text, "150%")
	assert_almost_eq(panel.mic_test.gain, 1.5, 0.001, "the live capture follows at once")
	s.value = 0.0
	assert_almost_eq(panel.mic_test.gain, 0.0, 0.001)
	panel.close()
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(Settings.PATH), OK)
	assert_almost_eq(float(cfg.get_value("voice", "mic_gain", -1.0)), 0.0, 0.001, "persisted on close")
	# Playback volume stays its own slider, labelled apart.
	var labels: Array[String] = []
	_collect_texts(panel.pages[SettingsPanel.TABS.find("AUDIO")], labels)
	assert_has(labels, "Voice volume (others)")
	Settings.change("voice", "mic_gain", old_gain)
	Settings.save()


## Patrick: "Strucutre the controls tab in the settings better (into movement, interaction etc)".
func test_controls_are_grouped_into_sections() -> void:
	var page: VBoxContainer = panel.pages[SettingsPanel.TABS.find("CONTROLS")]
	assert_eq(panel.control_headings.keys(), ["MOVEMENT", "INTERACTION", "SOCIAL", "CAMERA & SYSTEM"])
	assert_has(SettingsPanel.CONTROL_SECTIONS["MOVEMENT"], &"move_forward")
	assert_has(SettingsPanel.CONTROL_SECTIONS["MOVEMENT"], &"sprint")
	assert_has(SettingsPanel.CONTROL_SECTIONS["MOVEMENT"], &"jump")
	for a: StringName in [&"interact", &"grab", &"shove", &"shake", &"item_1", &"item_2", &"item_3", &"leave_station"]:
		assert_has(SettingsPanel.CONTROL_SECTIONS["INTERACTION"], a)
	for a: StringName in [&"emote_wheel", &"emote_1", &"emote_4", &"push_to_talk", &"ping", &"leaderboard"]:
		assert_has(SettingsPanel.CONTROL_SECTIONS["SOCIAL"], a)
	assert_has(SettingsPanel.CONTROL_SECTIONS["CAMERA & SYSTEM"], &"toggle_camera")
	assert_has(SettingsPanel.CONTROL_SECTIONS["CAMERA & SYSTEM"], &"pause")
	# Every remappable action is listed exactly once, and each sits under its own heading.
	var seen: Array[StringName] = []
	for title: String in SettingsPanel.CONTROL_SECTIONS:
		var heading_at: int = panel.control_headings[title].get_index()
		var next_at: int = page.get_child_count()
		for other: String in panel.control_headings:
			var i: int = panel.control_headings[other].get_index()
			if i > heading_at and i < next_at:
				next_at = i
		for a: StringName in SettingsPanel.CONTROL_SECTIONS[title]:
			assert_false(a in seen, "%s listed once" % a)
			seen.append(a)
			var row_at: int = panel.bind_buttons[a].get_parent().get_index()
			assert_between(row_at, heading_at + 1, next_at - 1, "%s under %s" % [a, title])
	assert_eq(seen.size(), Settings.KEYBINDS.size(), "every remappable action has a section")
	# Mouse and gamepad look have their own small headings on this tab.
	var texts: Array[String] = []
	_collect_texts(page, texts)
	for t: String in ["MOUSE", "GAMEPAD", "Mouse sensitivity", "Invert mouse Y", "Look speed (right stick)"]:
		assert_has(texts, t)
	# The gamepad button shows next to each binding.
	assert_eq(panel.pad_labels[&"jump"].text, "A")
	assert_eq(panel.pad_labels[&"sprint"].text, "L3")


func test_the_controls_tab_scrolls() -> void:
	var page: VBoxContainer = panel.pages[SettingsPanel.TABS.find("CONTROLS")]
	assert_true(page.get_parent().get_parent() is ScrollContainer, "a long tab scrolls")


## Patrick: "Add More frame limits".
func test_frame_limit_choices() -> void:
	var old: int = int(Settings.get_value("video", "max_fps"))
	var items: Array[String] = []
	for i: int in panel.fps_option.item_count:
		items.append(panel.fps_option.get_item_text(i))
	assert_eq(items, ["Off", "30 FPS", "60 FPS", "90 FPS", "120 FPS", "144 FPS", "165 FPS", "240 FPS", "Match monitor"] as Array[String])
	panel.fps_option.select(5)
	panel.fps_option.item_selected.emit(5)
	assert_eq(int(Settings.get_value("video", "max_fps")), 144)
	assert_eq(Engine.max_fps, 144, "applied through Engine.max_fps")
	panel.fps_option.select(0)
	panel.fps_option.item_selected.emit(0)
	assert_eq(Engine.max_fps, 0, "off")
	assert_eq(Settings.fps_limit(Settings.MATCH_MONITOR, 143.9), 144, "match monitor rounds the refresh rate")
	assert_eq(Settings.fps_limit(Settings.MATCH_MONITOR, -1.0), 0, "no limit when the screen will not say")
	Settings.change("video", "max_fps", old)
