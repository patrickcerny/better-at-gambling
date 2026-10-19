extends GutTest
## F11 toggles fullscreen everywhere (0.9.14, Patrick: "On f11 press fullscreen toggle"): the
## `toggle_fullscreen` action (F11, remappable in the Controls tab) flips and saves
## `video/fullscreen`, the window follows through `Settings.apply` (headless here: the setting and
## the window mode it asks for are checked, not a real window), and Settings > Video shows it.

var _file: PackedByteArray = PackedByteArray()
var _had_file: bool = false
var _old_fs: bool


func before_each() -> void:
	_had_file = FileAccess.file_exists(Settings.PATH)
	_file = FileAccess.get_file_as_bytes(Settings.PATH) if _had_file else PackedByteArray()
	_old_fs = bool(Settings.get_value("video", "fullscreen"))
	Settings.set_value("video", "fullscreen", false)


func after_each() -> void:
	Settings.set_value("video", "fullscreen", _old_fs)
	if _had_file:
		var f: FileAccess = FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_buffer(_file)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))


func _f11() -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_F11
	k.keycode = KEY_F11
	k.pressed = true
	return k


func _saved_fullscreen() -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(Settings.PATH) != OK:
		return null
	return cfg.get_value("video", "fullscreen", null)


func test_f11_is_the_action_and_can_be_remapped() -> void:
	assert_true(InputMap.has_action(&"toggle_fullscreen"))
	assert_true(_f11().is_action_pressed(&"toggle_fullscreen"), "F11")
	assert_true(Settings.KEYBINDS.has(&"toggle_fullscreen"), "listed in the Controls tab")
	assert_eq(Settings.binding_label(&"toggle_fullscreen"), "F11")
	for action: StringName in InputMap.get_actions():
		if action == &"toggle_fullscreen" or String(action).begins_with("ui_"):
			continue
		assert_false(_f11().is_action(action, true), "F11 is only fullscreen, not %s" % action)
	assert_false(_f11().is_action_pressed(&"pause"), "Esc stays the pause key")


func test_f11_flips_and_saves_the_setting() -> void:
	watch_signals(Settings)
	Settings._input(_f11())
	assert_true(bool(Settings.get_value("video", "fullscreen")), "on")
	assert_eq(_saved_fullscreen(), true, "saved at once")
	assert_signal_emitted(Settings, "changed", "the settings panel and the window follow")
	Settings._input(_f11())
	assert_false(bool(Settings.get_value("video", "fullscreen")), "off again")
	assert_eq(_saved_fullscreen(), false)
	var release: InputEventKey = _f11()
	release.pressed = false
	Settings._input(release)
	var echo: InputEventKey = _f11()
	echo.echo = true
	Settings._input(echo)
	assert_false(bool(Settings.get_value("video", "fullscreen")), "a held key or a release flips nothing")


func test_the_window_mode_follows_the_setting() -> void:
	assert_eq(Settings.window_mode_for(true, DisplayServer.WINDOW_MODE_WINDOWED), DisplayServer.WINDOW_MODE_FULLSCREEN)
	assert_eq(Settings.window_mode_for(true, DisplayServer.WINDOW_MODE_MAXIMIZED), DisplayServer.WINDOW_MODE_FULLSCREEN)
	assert_eq(Settings.window_mode_for(false, DisplayServer.WINDOW_MODE_FULLSCREEN), DisplayServer.WINDOW_MODE_WINDOWED)
	assert_eq(Settings.window_mode_for(true, DisplayServer.WINDOW_MODE_FULLSCREEN), -1, "already fullscreen")
	assert_eq(Settings.window_mode_for(false, DisplayServer.WINDOW_MODE_MAXIMIZED), -1, "a maximized window stays")


func test_settings_video_tab_shows_the_toggle() -> void:
	var panel := SettingsPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	var check: CheckButton = panel.checks["video/fullscreen"]
	assert_false(check.button_pressed)
	Settings.toggle_fullscreen()
	assert_true(check.button_pressed, "the Video tab shows F11's change")
	check.button_pressed = false  # and the box still works the other way
	assert_false(bool(Settings.get_value("video", "fullscreen")))
	var found: bool = false
	for actions: Array in SettingsPanel.CONTROL_SECTIONS.values():
		found = found or &"toggle_fullscreen" in actions
	assert_true(found, "remappable in the Controls tab")
	assert_true(panel.bind_buttons.has(&"toggle_fullscreen"))
