extends GutTest
## Wheel of Fortune overlay: seven symbol buttons in the wheel's colours with the odds they pay,
## chips on several symbols at once, the countdown, the result and the last spins, a dot per other
## player on a symbol. The overlay is a column in the right third of the screen (the wheel fills
## the rest), with the rules folded away under the key hint.

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


## The overlay is a column in the right third, top to bottom: nothing of it (no button, label or
## chip) reaches into the left two thirds, where the seat camera frames the table.
func _assert_right_column(what: String) -> void:
	var r: Rect2 = ui.panel.get_global_rect()
	assert_gt(r.position.x, 1920 * 0.6, "%s: the panel starts in the right third: %s" % [what, r])
	assert_lt(r.size.x, 1920 * 0.4, "%s: about a third of the width: %s" % [what, r])
	assert_lte(r.end.x, 1920.0, "%s: on screen" % what)
	assert_gt(r.size.y, 1080 * 0.6, "%s: a column from top to bottom: %s" % [what, r])
	assert_gte(r.position.y, 150.0, "%s: under the HUD's clock" % what)
	assert_lte(r.end.y, 1080.0 - 90.0, "%s: over the HUD's rank" % what)
	var reach: float = INF
	var widest: String = ""
	for n: Node in ui.panel.find_children("*", "Control", true, false):
		var c: Control = n
		if not c.is_visible_in_tree():
			continue
		var cr: Rect2 = c.get_global_rect()
		if cr.position.x < reach:
			reach = cr.position.x
			widest = String(c.name)
		assert_true(r.grow(0.5).encloses(cr), "%s: %s stays inside the panel (%s)" % [what, c.name, cr])
	assert_gt(reach, 1920 * 2.0 / 3.0, "%s: nothing over the left two thirds (%s at %.0f)" % [what, widest, reach])


func test_seven_symbols_with_their_odds() -> void:
	assert_eq(ui.symbol_buttons.size(), 7)
	var expect: Array[String] = ["$1\n1:1", "$2\n2:1", "$5\n5:1", "$10\n10:1", "$20\n20:1", "JOKER\n40:1", "LOGO\n40:1"]
	for i: int in 7:
		assert_eq(ui.symbol_buttons[i].text, expect[i])
		assert_false(ui.symbol_buttons[i].disabled, "open for bets")
		assert_true(ui.symbol_buttons[i].get_global_rect().size.x > 60.0)
	assert_string_contains(ui.symbol_buttons[0].tooltip_text, "24 of the 54")
	assert_true(ui.wants_camera_lock(), "the head stays on the table while betting")
	_assert_right_column("betting")
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
	await wait_process_frames(2)
	_assert_right_column("with chips on three symbols")


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
	await wait_process_frames(2)
	_assert_right_column("with the last spins")


func test_the_rules_fold_away() -> void:
	assert_not_null(ui.rules_toggle, "a HOW IT WORKS line")
	assert_false(ui.rules_label.visible, "folded by default: the explanation takes no space")
	assert_string_contains(ui.rules_toggle.tooltip_text, "odds", "and its tooltip explains")
	assert_false(ui.hint.text.contains("odds"), "the key hint is only keys")
	var folded: float = ui.panel.get_global_rect().size.y
	ui.rules_toggle.button_pressed = true
	await wait_process_frames(2)
	assert_true(ui.rules_label.visible, "one click opens it")
	assert_string_contains(ui.rules_label.text, "%d s" % int(Registry.balance.wheel_countdown))
	assert_eq(ui.panel.get_global_rect().size.y, folded, "the column keeps its size")
	assert_eq(folded, 1080.0 - StationUi.COLUMN_MARGIN.y - StationUi.COLUMN_BOTTOM, "and the open rules fit in it")
	_assert_right_column("rules open")
	ui.rules_toggle.button_pressed = false
	assert_false(ui.rules_label.visible)


func test_clicking_a_symbol_sends_the_bet() -> void:
	# No server attached here: the click goes out and comes back refused, which is what a press
	# without a connection does; the symbol is remembered for Enter either way.
	Net.stop()
	watch_signals(ui)
	ui.symbol_buttons[4].pressed.emit()
	assert_eq(ui.selected_symbol, 4)
	assert_signal_emitted_with_parameters(ui, "rejected", [&"not_connected"])
	assert_eq(StationUi.rejection_text(&"invalid_symbol"), "Pick a symbol")
