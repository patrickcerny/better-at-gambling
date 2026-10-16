extends GutTest
## Craps overlay: four bet buttons with the felt's odds, line bets locked once a point is on (and
## the other side once you picked one), the SHOOT button only for the shooter and only when the
## table may throw, the come-out / point line, the shooter's name and the last roll.

var root: Control
var ui: CrapsUi
var st: ClientMatchState


func before_each() -> void:
	root = Control.new()
	root.size = Vector2(1920, 1080)
	add_child_autofree(root)
	ui = CrapsUi.new()
	root.add_child(ui)
	st = ClientMatchState.new()
	st.players[1] = {"name": "Ada", "color": 0}
	st.players[2] = {"name": "Bert", "color": 1}
	st.stations[&"craps_1"] = {"game": &"craps", "state": CrapsLogic.State.BETTING, "timer": 0.0, "counting": false, "players": [1, 2], "shooter": 1, "point": 0, "bets": [], "dice": [], "shoot_in": 0.0}
	st.balances[1] = 1000
	ui.open(&"craps_1", 1, st)
	await wait_process_frames(3)


func _pub() -> Dictionary:
	return (st.stations[&"craps_1"] as Dictionary).duplicate(true)


func test_four_bets_with_the_felt_odds() -> void:
	assert_eq(ui.bet_buttons.size(), 4)
	assert_string_contains(ui.bet_buttons[&"pass"].text, "PASS LINE")
	assert_string_contains(ui.bet_buttons[&"pass"].text, "1:1")
	assert_string_contains(ui.bet_buttons[&"dont_pass"].text, "DON'T PASS")
	assert_string_contains(ui.bet_buttons[&"field"].text, "2 & 12 pay 2:1")
	assert_string_contains(ui.bet_buttons[&"any_seven"].text, "4:1")
	for b: Button in ui.bet_buttons.values():
		assert_false(b.disabled, "open for bets on the come-out")
	assert_true(ui.wants_camera_lock(), "the head stays on the table while betting")
	assert_lt(ui.panel.get_global_rect().size.y, 440.0, "a strip at the bottom, the felt stays in view")
	assert_eq(ui.bet_panel.chip_value(), Registry.balance.craps_min_bet, "the smallest chip first")
	assert_string_contains(ui.status_label.text, "COME-OUT")
	assert_string_contains(ui.roll_label.text, "YOU", "you have the dice")


func test_line_bets_lock_on_the_point_and_one_side_only() -> void:
	var pub: Dictionary = _pub()
	pub["counting"] = true
	pub["timer"] = 9.2
	pub["bets"] = [{"player": 1, "type": &"pass", "amount": 25}, {"player": 2, "type": &"field", "amount": 10}]
	ui.update_state(pub, {})
	assert_true(ui.bet_buttons[&"dont_pass"].disabled, "no betting both sides")
	assert_false(ui.bet_buttons[&"pass"].disabled, "more on your own side")
	assert_true(ui._badges[&"pass"].visible)
	assert_eq(ui._badges[&"pass"].text, "$25")
	assert_true(ui._dots[&"field"].visible, "someone else is on the field")
	assert_string_contains(ui.status_label.text, "DICE IN 10")
	assert_string_contains(ui.my_bets.text, "Pass Line $25")
	pub["point"] = 6
	ui.update_state(pub, {})
	assert_string_contains(ui.status_label.text, "POINT IS 6")
	assert_true(ui.bet_buttons[&"pass"].disabled, "line bets go down on the come-out only")
	assert_true(ui.bet_buttons[&"dont_pass"].disabled)
	assert_false(ui.bet_buttons[&"field"].disabled, "one-roll bets any time")
	assert_false(ui.bet_buttons[&"any_seven"].disabled)


func test_shoot_button_for_the_shooter_only() -> void:
	var pub: Dictionary = _pub()
	ui.update_state(pub, {})
	assert_true(ui.shoot_button.visible)
	assert_true(ui.shoot_button.disabled, "nothing on the felt yet")
	pub["bets"] = [{"player": 2, "type": &"field", "amount": 10}]
	pub["shoot_in"] = 1.4
	ui.update_state(pub, {})
	assert_true(ui.shoot_button.disabled)
	assert_string_contains(ui.shoot_button.text, "in 2", "unlocks in a moment")
	pub["shoot_in"] = 0.0
	ui.update_state(pub, {})
	assert_false(ui.shoot_button.disabled)
	assert_string_contains(ui.shoot_button.text, "SHOOT")
	pub["state"] = CrapsLogic.State.ROLLING
	ui.update_state(pub, {})
	assert_true(ui.shoot_button.disabled, "the dice are out")
	for b: Button in ui.bet_buttons.values():
		assert_true(b.disabled, "no bets with the dice in the air")
	assert_false(ui.wants_camera_lock())
	pub["state"] = CrapsLogic.State.BETTING
	pub["shooter"] = 2
	ui.update_state(pub, {})
	assert_false(ui.shoot_button.visible, "only the shooter gets the button")
	assert_string_contains(ui.roll_label.text, "SHOOTER: Bert")
	pub["shooter"] = -1
	ui.update_state(pub, {})
	assert_string_contains(ui.roll_label.text, "stickman")


func test_the_last_roll_line() -> void:
	var pub: Dictionary = _pub()
	pub["state"] = CrapsLogic.State.RESULT
	pub["dice"] = [5, 2]
	pub["outcome"] = &"seven_out"
	ui.update_state(pub, {})
	assert_eq(ui.roll_label.text, "ROLLED 5 + 2 = 7  ·  SEVEN OUT")
	pub["dice"] = [4, 2]
	pub["outcome"] = &"point_set"
	pub["point"] = 6
	ui.update_state(pub, {})
	assert_eq(ui.roll_label.text, "ROLLED 4 + 2 = 6  ·  THE POINT IS 6")
	assert_eq(StationUi.rejection_text(&"point_is_on"), "Line bets go down on the come-out roll")
	assert_eq(StationUi.rejection_text(&"not_shooter"), "You're not the shooter")
