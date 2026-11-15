extends GutTest
## "Are you sure?" before quitting or leaving (Patrick: "Are you sure Dialog after quit game or
## leave game (so you dont misclick)"), and developer mode's menu entries (only with `DevMode`).


func before_each() -> void:
	DevMode.forced = -1
	DevMode.used = false


func after_each() -> void:
	DevMode.forced = -1
	DevMode.used = false
	ProfileManager.set_dev_unlock_all(false)


func _menu() -> Control:
	var menu: Control = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
	add_child_autofree(menu)
	await wait_process_frames(3)
	return menu


func test_confirm_dialog_cancel_and_yes() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var said: Array[int] = [0]
	var d: ConfirmDialog = ConfirmDialog.ask(host, "QUIT THE GAME?", "", "QUIT", func() -> void: said[0] += 1)
	await wait_process_frames(1)
	assert_eq(ConfirmDialog.open_in(host), d)
	assert_eq(d.title_label.text, "QUIT THE GAME?")
	assert_eq(d.yes_button.text, "QUIT")
	assert_true(d.cancel_button.has_focus(), "CANCEL focused")
	var k := InputEventAction.new()
	k.action = &"ui_cancel"
	k.pressed = true
	get_tree().root.push_input(k)
	await wait_process_frames(2)
	assert_eq(said[0], 0, "Esc cancels")
	assert_null(ConfirmDialog.open_in(host))
	d = ConfirmDialog.ask(host, "LEAVE?", "x", "LEAVE", func() -> void: said[0] += 1)
	d.yes_button.pressed.emit()
	assert_eq(said[0], 1, "the action button goes")
	await wait_process_frames(1)
	assert_null(ConfirmDialog.open_in(host))


func test_main_menu_quit_asks_first() -> void:
	var menu: Control = await _menu()
	(menu.get_node("Center/Column/VBox/Quit") as Button).pressed.emit()
	await wait_process_frames(1)
	var d: ConfirmDialog = ConfirmDialog.open_in(menu)
	assert_not_null(d, "QUIT asks")
	if d != null:
		d.cancel_button.pressed.emit()
	await wait_process_frames(1)
	assert_null(ConfirmDialog.open_in(menu))
	assert_true((menu.get_node("Center/Column/VBox") as Control).visible, "still in the menu")


func test_lobby_leave_asks_first() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var panel := LobbyPanel.new()
	host.add_child(panel)
	await wait_process_frames(1)
	watch_signals(panel)
	var leave: Button = panel.find_child("LeaveButton", true, false) as Button
	assert_not_null(leave)
	if leave == null:
		return
	leave.pressed.emit()
	assert_signal_not_emitted(panel, "leave_requested")
	var d: ConfirmDialog = ConfirmDialog.open_in(host)
	assert_not_null(d)
	if d != null:
		d.yes_button.pressed.emit()
	assert_signal_emitted(panel, "leave_requested")


func test_no_dev_entry_for_everyone_else() -> void:
	var menu: Control = await _menu()
	assert_null(menu.find_child("DevMode", true, false), "no DEV MODE button")
	assert_null(menu.get("dev_panel"))


func test_dev_entry_for_patrick() -> void:
	DevMode.forced = 1
	var menu: Control = await _menu()
	var entry: Button = menu.find_child("DevMode", true, false) as Button
	assert_not_null(entry, "DEV MODE under TUTORIAL")
	if entry == null:
		return
	assert_eq(entry.get_index(), (menu.get_node("Center/Column/VBox/Tutorial") as Control).get_index() + 1)
	entry.pressed.emit()
	var dev: DevPanel = menu.get("dev_panel")
	assert_true(dev.visible)
	assert_false((menu.get_node("Center/Column/VBox") as Control).visible)
	assert_eq(dev.minigame_tiles.size(), Registry.minigames.size(), "a tile per minigame")
	menu.set(&"load_match", false)
	watch_signals(menu)
	(dev.minigame_tiles[&"bat_heist"] as Button).pressed.emit()
	assert_signal_emitted(menu, "practice_requested")
	assert_eq(SceneRouter.practice_settings.get("minigame_pool"), "bat_heist")
	assert_true(SceneRouter.practice_settings.get("dev", false))
	dev.casino_button.pressed.emit()
	assert_eq(SceneRouter.practice_settings.get("mode"), MatchMode.CASINO)
	assert_eq(int(SceneRouter.practice_settings.get("dummies", -1)), 3)
	dev.back_button.pressed.emit()
	assert_false(dev.visible)
	assert_true((menu.get_node("Center/Column/VBox") as Control).visible)
	SceneRouter.practice_settings = {"mode": MatchMode.CASINO}


func test_pause_menu_dev_button_only_when_available() -> void:
	var pause := PauseMenu.new()
	add_child_autofree(pause)
	await wait_process_frames(1)
	assert_false(pause.dev_button.visible, "hidden by default")
	pause.set_dev_available(true)
	pause.open()
	watch_signals(pause)
	pause.dev_button.pressed.emit()
	assert_signal_emitted(pause, "dev_requested")
	assert_false(pause.visible)


func test_dev_match_panel_builds_every_item() -> void:
	var panel := DevMatchPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	assert_eq(panel.item_buttons.size(), Registry.items.size(), "every item, even the ones only other items make")
	assert_eq(panel.minigame_pick.item_count, Registry.minigames.size() + 1, "every minigame plus 'next in the bag'")
	panel.open()
	panel.give_money(1000)  # no match: nothing happens, nothing breaks
	assert_false(DevMode.used)
	panel.close()
	assert_false(panel.visible)
