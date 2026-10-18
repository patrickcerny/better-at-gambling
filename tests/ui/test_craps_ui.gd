extends GutTest
## Craps overlay: four bet buttons with the felt's odds, line bets locked once a point is on (and
## the other side once you picked one), the SHOOT button only for the shooter and only when the
## table may throw, the come-out / point line, the shooter's name and the last roll. The overlay
## is a column in the right third of the screen (the felt fills the rest), with the rules folded
## away under the key hint.

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
	_assert_right_column("come-out")
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
	await wait_process_frames(2)
	_assert_right_column("point on, chips down")


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
	await wait_process_frames(2)
	_assert_right_column("SHOOT showing")
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
	await wait_process_frames(2)
	_assert_right_column("the last roll")


func test_the_rules_fold_away() -> void:
	assert_not_null(ui.rules_toggle, "a HOW IT WORKS line")
	assert_false(ui.rules_label.visible, "folded by default: the explanation takes no space")
	assert_string_contains(ui.rules_toggle.tooltip_text, "come-out", "and its tooltip explains")
	ui.rules_toggle.button_pressed = true
	await wait_process_frames(2)
	assert_true(ui.rules_label.visible, "one click opens it")
	assert_string_contains(ui.rules_label.text, "Field")
	assert_eq(ui.panel.get_global_rect().size.y, 1080.0 - StationUi.COLUMN_MARGIN.y - StationUi.COLUMN_BOTTOM, "the open rules still fit the column")
	_assert_right_column("rules open")
	ui.rules_toggle.button_pressed = false
	assert_false(ui.rules_label.visible)
