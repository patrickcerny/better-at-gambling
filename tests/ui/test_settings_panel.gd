extends GutTest
## Settings panel: four tabs (GAME, VIDEO, AUDIO, CONTROLS), BACK / RESUME at the bottom (RESUME
## only in game), changes apply at once, Esc closes it, and the CONTROLS tab remaps keys: click a
## binding, press a key (Esc cancels), saved locally in the settings file and shown by InputGlyphs.

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
