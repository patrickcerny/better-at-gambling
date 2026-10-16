extends GutTest
## Tutorial (Patrick: "add a Tutorial (when you first start the game, you have to click through it
## with buttons. After that, theres a questionmark button just like the settings where you can see
## it again. The Tutorial pops up when you click practise or play for the first time."): picture
## pages with BACK / NEXT / DONE and SKIP; the first PRACTICE or PLAY ONLINE shows it once
## (`tutorial/seen` in user://settings.cfg) and then carries on (PRACTICE: the solo casino match); a "?" next to the gear
## opens it from the main menu and from the pause menu.

var _old_seen: Variant
var _old_practice: Dictionary


func before_each() -> void:
	_old_seen = Settings.get_value("tutorial", "seen", "unset")
	_old_practice = SceneRouter.practice_settings


func after_each() -> void:
	# Put the player's own flag back ("unset": erase the key again).
	Settings.set_value("tutorial", "seen", null if typeof(_old_seen) == TYPE_STRING else _old_seen)
	Settings.save()
	SceneRouter.practice_settings = _old_practice


func _menu() -> Control:
	var menu: Control = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
	add_child_autofree(menu)
	await wait_process_frames(3)
	return menu


func _panel() -> HowToPlayPanel:
	var how := HowToPlayPanel.new()
	add_child_autofree(how)
	await wait_process_frames(1)
	how.open()
	await wait_process_frames(1)
	return how


func _saved_seen() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(Settings.PATH) != OK:
		return false
	return bool(cfg.get_value("tutorial", "seen", false))


func test_next_back_done_and_the_counter() -> void:
	var how: HowToPlayPanel = await _panel()
	var n: int = HowToPlayPanel.PAGES.size()
	assert_eq(how.page, 0)
	assert_eq(how.counter.text, "1 / %d" % n)
	assert_true(how.back_button.disabled, "no BACK on the first page")
	assert_true(how.next_button.visible)
	assert_false(how.done_button.visible, "DONE only on the last page")
	assert_true(how.skip_button.visible, "SKIP from the start")
	assert_true(how.next_button.has_focus(), "NEXT is focused")
	how.next_button.pressed.emit()
	assert_eq(how.page, 1)
	assert_eq(how.counter.text, "2 / %d" % n)
	assert_false(how.back_button.disabled)
	how.back_button.pressed.emit()
	assert_eq(how.page, 0)
	for i: int in n + 2:  # past the end stays on the last page
		if how.next_button.visible:
			how.next_button.pressed.emit()
	assert_eq(how.page, n - 1)
	assert_eq(how.counter.text, "%d / %d" % [n, n])
	assert_false(how.next_button.visible)
	assert_true(how.done_button.visible)
	assert_true(how.done_button.has_focus(), "DONE is focused on the last page")
	watch_signals(how)
	how.done_button.pressed.emit()
	assert_false(how.visible)
	assert_signal_emit_count(how, "closed", 1)
	how.close()
	assert_signal_emit_count(how, "closed", 1, "closing twice says so once")


func test_every_page_has_a_picture_heading_and_text() -> void:
	var how: HowToPlayPanel = await _panel()
	assert_gte(HowToPlayPanel.PAGES.size(), 7)
	for i: int in HowToPlayPanel.PAGES.size():
		how.show_page(i)
		assert_not_null(how.picture.texture, "page %d has its picture" % (i + 1))
		if how.picture.texture != null:
			assert_gt(how.picture.texture.get_width(), 400, "page %d picture is a real screenshot" % (i + 1))
		assert_ne(how.heading.text, "")
		assert_gt(how.body.text.length(), 40)
		assert_false(how.body.text.contains("{"), "page %d key names filled in" % (i + 1))
	assert_eq(how.picture.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "pictures keep their aspect")
	assert_eq((how.find_child("Title", true, false) as Label).text, "HOW TO PLAY")


func test_escape_and_skip_close() -> void:
	var how: HowToPlayPanel = await _panel()
	watch_signals(how)
	var k := InputEventAction.new()
	k.action = &"ui_cancel"
	k.pressed = true
	get_tree().root.push_input(k)
	await wait_process_frames(2)
	assert_false(how.visible, "Esc closes")
	assert_signal_emitted(how, "closed")
	how.open()
	how.skip_button.pressed.emit()
	assert_false(how.visible, "SKIP closes")


func test_first_practice_shows_the_tutorial_then_starts_the_match() -> void:
	Settings.set_value("tutorial", "seen", false)
	Settings.save()
	var menu: Control = await _menu()
	menu.set(&"load_match", false)
	watch_signals(menu)
	var how: HowToPlayPanel = menu.get("how_to_play")
	(menu.get_node("Center/Column/VBox/Practice") as Button).pressed.emit()
	await wait_process_frames(1)
	assert_true(how.visible, "the first PRACTICE opens the tutorial")
	assert_signal_not_emitted(menu, "practice_requested", "the match waits")
	assert_eq(how.page, 0)
	for i: int in HowToPlayPanel.PAGES.size() - 1:
		how.next_button.pressed.emit()
	how.done_button.pressed.emit()
	await wait_process_frames(1)
	assert_false(how.visible)
	assert_signal_emit_count(menu, "practice_requested", 1, "DONE carries on to the match")
	assert_true(bool(Settings.get_value("tutorial", "seen", false)), "remembered")
	assert_true(_saved_seen(), "written to user://settings.cfg")
	menu.call(&"_show_main")
	(menu.get_node("Center/Column/VBox/Practice") as Button).pressed.emit()
	await wait_process_frames(1)
	assert_false(how.visible, "only once")
	assert_signal_emit_count(menu, "practice_requested", 2)


func test_first_practice_skip_also_starts_the_match() -> void:
	Settings.set_value("tutorial", "seen", false)
	var menu: Control = await _menu()
	menu.set(&"load_match", false)
	watch_signals(menu)
	(menu.get_node("Center/Column/VBox/Practice") as Button).pressed.emit()
	await wait_process_frames(1)
	(menu.get("how_to_play") as HowToPlayPanel).skip_button.pressed.emit()
	await wait_process_frames(1)
	assert_signal_emit_count(menu, "practice_requested", 1, "SKIP carries on to the match")


func test_first_play_online_skip_carries_on_to_the_online_box() -> void:
	Settings.set_value("tutorial", "seen", false)
	var menu: Control = await _menu()
	var how: HowToPlayPanel = menu.get("how_to_play")
	(menu.get_node("Center/Column/VBox/PlayOnline") as Button).pressed.emit()
	await wait_process_frames(1)
	assert_true(how.visible, "the first PLAY ONLINE opens the tutorial")
	how.skip_button.pressed.emit()
	await wait_process_frames(1)
	assert_true((menu.find_child("Online", true, false) as Control).visible, "SKIP carries on to PLAY ONLINE")
	assert_true(bool(Settings.get_value("tutorial", "seen", false)))


func test_seen_goes_straight_to_the_match() -> void:
	Settings.set_value("tutorial", "seen", true)
	var menu: Control = await _menu()
	menu.set(&"load_match", false)
	watch_signals(menu)
	(menu.get_node("Center/Column/VBox/Practice") as Button).pressed.emit()
	await wait_process_frames(1)
	assert_false((menu.get("how_to_play") as HowToPlayPanel).visible)
	assert_signal_emit_count(menu, "practice_requested", 1)


func test_question_mark_in_the_main_menu() -> void:
	Settings.set_value("tutorial", "seen", true)
	var menu: Control = await _menu()
	var help: HelpButton = menu.find_child("HelpButton", true, false) as HelpButton
	var tshirt: Button = menu.find_child("ClothesButton", true, false) as Button
	var gear: Button = menu.find_child("SettingsButton", true, false) as Button
	assert_not_null(help, "? button in the main menu")
	if help == null:
		return
	assert_almost_eq(help.size, gear.size, Vector2.ONE, "same size as the gear")
	assert_almost_eq(help.global_position.y, gear.global_position.y, 1.0, "same row as the gear")
	assert_lt(help.global_position.x + help.size.x, tshirt.global_position.x, "left of the T-shirt")
	help.pressed.emit()
	await wait_process_frames(1)
	var how: HowToPlayPanel = menu.get("how_to_play")
	assert_true(how.visible, "? opens the tutorial")
	assert_eq(how.page, 0)
	how.skip_button.pressed.emit()
	await wait_process_frames(1)
	assert_true((menu.get_node("Center/Column/VBox") as Control).visible, "back to the entries")
	assert_false((menu.find_child("Online", true, false) as Control).visible, "nothing else opens")
	assert_true(help.has_focus(), "focus back on ?")


func test_question_mark_in_the_pause_menu() -> void:
	var pause := PauseMenu.new()
	add_child_autofree(pause)
	await wait_process_frames(1)
	pause.open()
	await wait_process_frames(1)
	assert_not_null(pause.help_button)
	assert_eq(pause.help_button.get_parent(), pause.settings_button.get_parent(), "next to the gear")
	assert_lt(pause.help_button.get_index(), pause.settings_button.get_index(), "left of the gear")
	watch_signals(pause)
	pause.help_button.pressed.emit()
	await wait_process_frames(1)
	assert_true(pause.how_to_play.visible, "? opens the tutorial in game")
	assert_false(pause.panel.visible, "in place of the pause panel")
	assert_true(pause.how_to_play.next_button.has_focus())
	var k := InputEventAction.new()
	k.action = &"ui_cancel"
	k.pressed = true
	get_tree().root.push_input(k)
	await wait_process_frames(2)
	assert_false(pause.how_to_play.visible, "Esc closes the tutorial")
	assert_true(pause.visible, "back to the pause menu, not to play")
	assert_true(pause.panel.visible)
	assert_true(pause.help_button.has_focus())
	assert_signal_not_emitted(pause, "resumed")
	pause.help_button.pressed.emit()
	pause.back()  # the match scene's Esc path (the pause action)
	assert_false(pause.how_to_play.visible)
	assert_true(pause.panel.visible)
	assert_signal_not_emitted(pause, "resumed")
	pause.help_button.pressed.emit()
	pause.resume()
	assert_false(pause.visible)
	assert_false(pause.how_to_play.visible, "resuming closes it too")
