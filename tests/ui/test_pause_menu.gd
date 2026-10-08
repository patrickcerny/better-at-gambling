extends GutTest
## Pause menu (Patrick: "When pressed Escape you dont get into the settings directly"): RESUME,
## LEAVE, QUIT GAME in that order, the settings behind a gear in the bottom-right corner; Esc
## resumes, and the settings return here on BACK / Esc or straight to play on RESUME.

var menu: PauseMenu


func before_each() -> void:
	menu = PauseMenu.new()
	add_child_autofree(menu)
	await wait_process_frames(1)


func _esc() -> void:
	var k := InputEventAction.new()
	k.action = &"ui_cancel"
	k.pressed = true
	get_tree().root.push_input(k)
	await wait_process_frames(2)


func test_buttons_in_order_with_the_gear_bottom_right() -> void:
	menu.open()
	await wait_process_frames(2)
	assert_true(menu.visible)
	assert_true(menu.resume_button.has_focus(), "RESUME is focused")
	var col: Node = menu.resume_button.get_parent()
	assert_eq(menu.resume_button.text, "RESUME")
	assert_lt(menu.resume_button.get_index(), menu.leave_button.get_index())
	assert_lt(menu.leave_button.get_index(), menu.quit_button.get_index())
	assert_eq(menu.quit_button.text, "QUIT GAME")
	assert_eq(menu.leave_button.get_parent(), col)
	var gear: Rect2 = menu.settings_button.get_global_rect()
	var box: Rect2 = menu.panel.get_global_rect()
	assert_gt(gear.position.y, menu.quit_button.get_global_rect().end.y - 1.0, "gear below the buttons")
	assert_almost_eq(gear.end.x, box.end.x, 40.0, "gear in the right corner")
	assert_almost_eq(gear.end.y, box.end.y, 40.0, "gear at the bottom")
	assert_false(menu.settings.visible, "Escape does not open the settings directly")


func test_escape_resumes() -> void:
	menu.open()
	watch_signals(menu)
	await _esc()
	assert_false(menu.visible)
	assert_signal_emitted(menu, "resumed")


func test_settings_return_to_the_pause_menu() -> void:
	menu.open()
	watch_signals(menu)
	menu.settings_button.pressed.emit()
	assert_true(menu.settings.visible)
	assert_false(menu.panel.visible, "the settings replace the pause panel")
	assert_true(menu.settings._resume.visible, "RESUME in the settings in game")
	await _esc()
	assert_false(menu.settings.visible)
	assert_true(menu.visible, "Esc in the settings goes back to the pause menu")
	assert_true(menu.panel.visible)
	assert_signal_not_emitted(menu, "resumed")
	menu.open_settings()
	menu.settings._back.pressed.emit()
	assert_true(menu.panel.visible, "BACK too")
	assert_signal_not_emitted(menu, "resumed")
	menu.open_settings()
	menu.settings._resume.pressed.emit()
	assert_false(menu.visible, "RESUME in the settings goes straight back to play")
	assert_signal_emitted(menu, "resumed")


func test_leave_and_quit_emit() -> void:
	menu.open()
	watch_signals(menu)
	menu.leave_button.pressed.emit()
	assert_signal_emitted(menu, "leave_requested")
	assert_false(menu.visible)
	menu.open()
	menu.quit_button.pressed.emit()
	assert_signal_emitted(menu, "quit_requested")
	assert_signal_not_emitted(menu, "resumed")
