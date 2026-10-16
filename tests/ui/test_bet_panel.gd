extends GutTest
## Bet panel navigation with real keyboard and joypad events pushed through the viewport
## (M2 acceptance: "UI navigation test with keyboard and joypad events on bet panel").

var panel: BetPanel


func before_each() -> void:
	panel = BetPanel.new()
	add_child_autofree(panel)
	panel.setup([10, 25, 50, 100], 10, 200, "BET")
	await wait_process_frames(2)


func _press(action: StringName, joypad: bool) -> void:
	for ev: InputEvent in InputMap.action_get_events(action):
		if joypad and ev is InputEventJoypadButton:
			var e: InputEventJoypadButton = ev.duplicate()
			e.pressed = true
			get_tree().root.push_input(e)
			e = e.duplicate()
			e.pressed = false
			get_tree().root.push_input(e)
			return
		if not joypad and ev is InputEventKey:
			var k: InputEventKey = ev.duplicate()
			k.pressed = true
			get_tree().root.push_input(k)
			k = k.duplicate()
			k.pressed = false
			get_tree().root.push_input(k)
			return
	fail_test("no %s binding for %s" % ["joypad" if joypad else "keyboard", action])


func test_keyboard_selects_chip_and_confirms() -> void:
	watch_signals(panel)
	_press(&"bet_chip_2", false)
	assert_eq(panel.selected_chip, 1, "key 2 selects the $25 chip")
	assert_eq(panel.chip_value(), 25)
	_press(&"bet_confirm", false)
	assert_signal_emitted_with_parameters(panel, "confirmed", [25])
	_press(&"bet_chip_4", false)
	_press(&"bet_clear", false)
	_press(&"bet_confirm", false)
	assert_eq(panel.amount, 100, "after a clear, confirm bets the newly selected chip")


func test_keyboard_clear_and_repeat() -> void:
	watch_signals(panel)
	panel.set_amount(50)
	panel.confirm()
	_press(&"bet_clear", false)
	assert_eq(panel.amount, 0, "clear resets the amount")
	assert_signal_emitted(panel, "cleared")
	_press(&"bet_repeat", false)
	assert_eq(panel.amount, 50, "repeat restores the last confirmed bet")


func test_joypad_cycles_chips() -> void:
	panel.select_chip(0)
	_press(&"bet_chip_next", true)
	assert_eq(panel.selected_chip, 1, "RB moves to the next chip")
	_press(&"bet_chip_next", true)
	assert_eq(panel.selected_chip, 2)
	_press(&"bet_chip_prev", true)
	assert_eq(panel.selected_chip, 1, "LB moves back")


func test_focus_navigation_reaches_every_button() -> void:
	var first: Button = panel._chip_buttons[0]
	first.grab_focus()
	var seen: Dictionary = {}
	for i: int in 40:
		var f: Control = get_viewport().gui_get_focus_owner()
		if f != null:
			seen[f.get_instance_id()] = f
		var ev := InputEventAction.new()
		ev.action = &"ui_right" if i % 2 == 0 else &"ui_down"
		ev.pressed = true
		get_tree().root.push_input(ev)
		await wait_process_frames(1)
	var buttons: int = 0
	for n: Node in panel.find_children("*", "Button", true, false):
		buttons += 1
	assert_gt(seen.size(), 4, "focus walks across chips and actions (%d of %d buttons reached)" % [seen.size(), buttons])


func test_instant_mode_confirms_on_chip_press() -> void:
	panel.setup([10, 25, 50, 100], 10, 100, "PULL", true)
	watch_signals(panel)
	_press(&"bet_chip_3", false)
	assert_signal_emitted_with_parameters(panel, "confirmed", [50])


## All-in (Patrick): more than you have bets everything you have, with an ALL IN tag and one toast.
func test_over_the_balance_clamps_to_all_in() -> void:
	var tag: Label = panel.find_child("AllInTag", true, false) as Label
	assert_not_null(tag)
	assert_false(tag.visible, "no tag while the balance is unknown")
	panel.set_amount(150)
	assert_eq(panel.amount, 150, "unknown balance: nothing is clamped")
	panel.set_amount(0)
	watch_signals(panel)
	panel.set_balance(37)
	panel.set_amount(150)
	assert_eq(panel.amount, 37, "the bet drops to everything you have")
	assert_true(panel.all_in)
	assert_true(tag.visible, "the ALL IN tag shows")
	assert_string_contains(tag.text, "ALL IN")
	assert_signal_emit_count(panel, "went_all_in", 1)
	panel._adjust(panel.amount + 25)
	assert_eq(panel.amount, 37, "adding chips stays all-in")
	assert_signal_emit_count(panel, "went_all_in", 1, "the toast fires once per bet")
	assert_eq(panel._chip_buttons[3].text, "$37", "a chip worth more than you have shows what it bets")
	assert_eq(panel._chip_buttons[0].text, "$10")
	panel.set_amount(20)
	assert_false(panel.all_in)
	assert_false(tag.visible)
	_press(&"bet_chip_4", false)
	panel.clear()
	_press(&"bet_confirm", false)
	assert_signal_emitted_with_parameters(panel, "confirmed", [37])


func test_table_max_still_caps() -> void:
	panel.set_balance(5000)
	panel.set_amount(900)
	assert_eq(panel.amount, 200, "the max wins over a big balance")
	assert_false(panel.all_in)


func test_under_the_minimum_is_left_for_the_server_to_refuse() -> void:
	panel.set_balance(7)
	panel.set_amount(50)
	assert_eq(panel.amount, 50, "under the minimum nothing is clamped: the server says not enough money")
	assert_false(panel.all_in)


func test_balance_drop_reclamps_the_bet() -> void:
	panel.set_balance(500)
	panel.set_amount(100)
	assert_false(panel.all_in)
	panel.set_balance(60)
	assert_eq(panel.amount, 60)
	assert_true(panel.all_in)


func test_chip_stake_for_layout_tables() -> void:
	panel.set_balance(30)
	panel.select_chip(3)
	watch_signals(panel)
	assert_eq(panel.chip_stake(), 30, "a $100 chip on the layout bets the $30 you have")
	assert_true(panel.all_in)
	assert_signal_emit_count(panel, "went_all_in", 1)
	assert_eq(panel.chip_stake(200), 30)
	assert_signal_emit_count(panel, "went_all_in", 1)
	panel.set_balance(1000)
	assert_eq(panel.chip_stake(40), 40, "what is left of the table total caps it")
	assert_false(panel.all_in)


func test_instant_mode_goes_all_in() -> void:
	panel.setup([10, 25, 50, 100], 10, 100, "PULL", true)
	panel.set_balance(42)
	watch_signals(panel)
	_press(&"bet_chip_4", false)
	assert_signal_emitted_with_parameters(panel, "confirmed", [42])
	assert_signal_emit_count(panel, "went_all_in", 1)
