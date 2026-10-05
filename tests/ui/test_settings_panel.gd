extends GutTest
## Settings panel: changes apply at once, Esc closes it, Resume/Leave only show in game.

var panel: SettingsPanel
var _old_sens: float
var _old_fov: float


func before_each() -> void:
	_old_sens = float(Settings.get_value("controls", "mouse_sensitivity"))
	_old_fov = float(Settings.get_value("video", "fov"))
	panel = SettingsPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(2)


func after_each() -> void:
	Settings.change("controls", "mouse_sensitivity", _old_sens)
	Settings.change("video", "fov", _old_fov)


func test_in_game_shows_resume_and_leave_menu_does_not() -> void:
	panel.open(false)
	assert_true(panel.visible)
	assert_false(panel._resume.visible)
	assert_false(panel._leave.visible)
	panel.close()
	panel.open(true)
	assert_true(panel._resume.visible)
	assert_true(panel._leave.visible)


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
