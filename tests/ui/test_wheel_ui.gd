extends GutTest
## Wheel of Fortune overlay: seven symbol buttons in the wheel's colours with the odds they pay,
## chips on several symbols at once, the countdown, the result and the last spins, a dot per other
## player on a symbol, and the dealer's tip jar.

var root: Control
var ui: WheelUi
var st: ClientMatchState


func before_each() -> void:
	root = Control.new()
	root.size = Vector2(1920, 1080)
	add_child_autofree(root)
	ui = WheelUi.new()
	root.add_child(ui)
	st = ClientMatchState.new()
	st.stations[&"wheel_1"] = {"game": &"wheel", "state": WheelLogic.State.BETTING, "timer": 0.0, "counting": false, "players": [1], "bets": [], "segment": -1, "landing": false, "history": []}
	st.balances[1] = 1000
	ui.open(&"wheel_1", 1, st)
	await wait_process_frames(3)


func _pub() -> Dictionary:
	return (st.stations[&"wheel_1"] as Dictionary).duplicate(true)


func test_seven_symbols_with_their_odds() -> void:
	assert_eq(ui.symbol_buttons.size(), 7)
	var expect: Array[String] = ["$1\n1:1", "$2\n2:1", "$5\n5:1", "$10\n10:1", "$20\n20:1", "JOKER\n40:1", "LOGO\n40:1"]
	for i: int in 7:
		assert_eq(ui.symbol_buttons[i].text, expect[i])
		assert_false(ui.symbol_buttons[i].disabled, "open for bets")
		assert_true(ui.symbol_buttons[i].get_global_rect().size.x > 60.0)
	assert_string_contains(ui.symbol_buttons[0].tooltip_text, "24 of the 54")
	assert_true(ui.wants_camera_lock(), "the head stays on the table while betting")
	assert_lt(ui.panel.get_global_rect().size.y, 460.0, "a strip at the bottom, the wheel stays in view")
	assert_true(ui.panel.get_global_rect().position.y > 1080 * 0.5, "in the lower half of the screen")
	assert_lt(ui.panel.get_global_rect().size.x, 1000.0, "the chips row stays slim: %s" % ui.panel.get_global_rect())
	assert_eq(ui.bet_panel.chip_value(), Registry.balance.wheel_min_bet, "the smallest chip first")
	assert_string_contains(ui.status_label.text, "PICK A SYMBOL")


func test_chips_on_several_symbols() -> void:
	var pub: Dictionary = _pub()
	pub["counting"] = true
	pub["timer"] = 9.2
	pub["bets"] = [{"player": 1, "symbol": 0, "amount": 25}, {"player": 1, "symbol": 5, "amount": 10}, {"player": 1, "symbol": 0, "amount": 10}, {"player": 2, "symbol": 3, "amount": 10}]
	ui.update_state(pub, {})
	assert_string_contains(ui.status_label.text, "10")
	assert_true(ui._badges[0].visible)
	assert_eq(ui._badges[0].text, "$35")
	assert_eq(ui._badges[5].text, "$10")
	assert_false(ui._badges[3].visible, "another player's chips are a dot, not a badge")
	assert_true(ui._dots[3].visible)
	assert_string_contains(ui.my_bets.text, "$45")
	assert_string_contains(ui.my_bets.text, "$1 $35")
	assert_string_contains(ui.my_bets.text, "JOKER $10")
	for b: Button in ui.symbol_buttons:
		assert_false(b.disabled, "every symbol stays open: no one-symbol rule")


func test_spin_result_and_history_lines() -> void:
	var pub: Dictionary = _pub()
	pub["state"] = WheelLogic.State.SPINNING
	ui.update_state(pub, {})
	assert_string_contains(ui.status_label.text, "spinning")
	for b: Button in ui.symbol_buttons:
		assert_true(b.disabled, "bets are closed once the dealer spins")
	assert_false(ui.wants_camera_lock(), "watch the wheel with the head free")
	pub["state"] = WheelLogic.State.RESULT
	pub["segment"] = WheelLogic.LAYOUT.find(5)
	pub["timer"] = 3.0
	pub["history"] = [5, 0, 1]
	ui.update_state(pub, {})
	assert_eq(ui.result_label.text, "THE WHEEL SAYS JOKER  ·  PAYS 40:1")
	pub["state"] = WheelLogic.State.BETTING
	pub["segment"] = -1
	ui.update_state(pub, {})
	assert_eq(ui.result_label.text, "Last spins: JOKER  $1  $2")


func test_clicking_a_symbol_sends_the_bet() -> void:
	# No server attached here: the click goes out and comes back refused, which is what a press
	# without a connection does; the symbol is remembered for Enter either way.
	Net.stop()
	watch_signals(ui)
	ui.symbol_buttons[4].pressed.emit()
	assert_eq(ui.selected_symbol, 4)
	assert_signal_emitted_with_parameters(ui, "rejected", [&"not_connected"])
	assert_eq(StationUi.rejection_text(&"invalid_symbol"), "Pick a symbol")
