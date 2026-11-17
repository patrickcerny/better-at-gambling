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


## Nothing in the panel takes GUI focus (a focused chip took the d-pad's items and A's bet away
## from a gamepad at the table); the pad reaches everything through its own buttons instead.
func test_no_focus_and_the_pad_reaches_every_action() -> void:
	await wait_process_frames(1)
	assert_null(get_viewport().gui_get_focus_owner(), "no chip grabs the focus")
	for n: Node in panel.find_children("*", "ChipToken", true, false):
		assert_eq((n as Control).focus_mode, Control.FOCUS_NONE)
	for action: StringName in [&"bet_chip_prev", &"bet_chip_next", &"bet_confirm", &"bet_clear", &"bet_repeat"]:
		assert_ne(InputGlyphs.labels(action, true).size(), 0, "%s has a pad button" % action)


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
	assert_signal_emit_count(panel, "went_all_in", 0, "no toast while you are still picking")
	panel._adjust(panel.amount + 25)
	assert_eq(panel.amount, 37, "adding chips stays all-in")
	panel.confirm()
	assert_signal_emit_count(panel, "went_all_in", 1, "the toast fires when the all-in bet goes down")
	assert_signal_emitted_with_parameters(panel, "went_all_in", [37])
	assert_eq(panel._chip_buttons[3].text, "$100", "a chip keeps its own value")
	assert_true(panel._chip_buttons[3].disabled, "and is greyed out when you can't pay it")
	assert_true(panel._chip_buttons[2].disabled)
	assert_false(panel._chip_buttons[1].disabled)
	assert_false(panel._chip_buttons[0].disabled)
	panel.set_amount(20)
	assert_false(panel.all_in)
	assert_false(tag.visible)
	_press(&"bet_chip_4", false)
	assert_eq(panel.selected_chip, 1, "a greyed chip picks the dearest one you can pay")
	panel.clear()
	_press(&"bet_confirm", false)
	assert_signal_emitted_with_parameters(panel, "confirmed", [25])


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
	panel.set_balance(500)
	assert_eq(panel.amount, 100, "the picked bet grows back once the money is there again")
	assert_false(panel.all_in)


## Patrick: "sometimes it tells me I go all in but I have more money (mainly on blackjack)".
## Blackjack takes the stake off the balance when the bet goes down; that update re-clamped the
## bet still in the panel to what was left and toasted ALL IN, although only part was bet.
func test_stake_taken_off_after_a_bet_is_no_all_in_toast() -> void:
	panel.set_balance(300)
	panel.set_amount(200)
	watch_signals(panel)
	panel.confirm()
	assert_signal_emitted_with_parameters(panel, "confirmed", [200])
	panel.set_balance(100)  # the server took the $200 stake
	assert_signal_emit_count(panel, "went_all_in", 0, "a bet of 200 out of 300 is not all-in")
	panel.set_balance(500)  # the hand won
	assert_eq(panel.amount, 200, "the next bet is the 200 picked, not the 100 that was left")
	assert_false(panel.all_in)
	panel.confirm()
	assert_signal_emitted_with_parameters(panel, "confirmed", [200], 1)
	assert_signal_emit_count(panel, "went_all_in", 0)


func test_layout_chip_over_the_balance_toasts_once_placed() -> void:
	panel.set_balance(1000)
	panel.select_chip(3)
	watch_signals(panel)
	assert_eq(panel.chip_stake(), 100)
	assert_signal_emit_count(panel, "went_all_in", 0)
	panel.set_balance(60)  # the chips on the layout were taken off: no toast for that
	assert_signal_emit_count(panel, "went_all_in", 0)


func test_chip_stake_for_layout_tables() -> void:
	panel.set_balance(30)
	panel.select_chip(3)
	assert_eq(panel.chip_stake(), 25, "a $100 chip you can't pay falls back to the $25 you can")
	assert_false(panel.all_in)
	panel.set_balance(1000)
	panel.select_chip(3)
	assert_eq(panel.chip_stake(40), 40, "what is left of the table total caps it")
	assert_false(panel.all_in)


## Slots (Patrick: "gives me invalid amount if I only have 40. Disable the button"): an instant
## panel never pulls with an amount it doesn't list; chips you can't pay are greyed out.
func test_instant_mode_never_bets_an_unlisted_amount() -> void:
	panel.setup([15, 37, 75, 150], 15, 150, "PULL", true)
	panel.select_chip(3)
	panel.set_balance(40)
	assert_eq(panel.selected_chip, 1, "the picked $150 drops to the $37 you can pay")
	assert_true(panel._chip_buttons[2].disabled)
	assert_true(panel._chip_buttons[3].disabled)
	watch_signals(panel)
	_press(&"bet_chip_4", false)
	assert_signal_emitted_with_parameters(panel, "confirmed", [37])
	assert_signal_emit_count(panel, "went_all_in", 0)
	# Nothing affordable: the smallest, and the server says "Not enough money".
	panel.set_balance(10)
	_press(&"bet_chip_2", false)
	assert_signal_emitted_with_parameters(panel, "confirmed", [15], 1)
