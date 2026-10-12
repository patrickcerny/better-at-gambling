extends GutTest
## Horse race overlay: four horse buttons in the lane colours with the round's names, one horse
## per race (the others lock once you back one), and the leader / winner line under the status.

const NAMES: Array = ["Neigh Sayer", "Hay Fever", "Oat Couture", "Mane Event"]

var root: Control
var ui: HorseRaceUi
var st: ClientMatchState


func before_each() -> void:
	root = Control.new()
	root.size = Vector2(1920, 1080)
	add_child_autofree(root)
	ui = HorseRaceUi.new()
	root.add_child(ui)
	st = ClientMatchState.new()
	st.stations[&"horse_race_1"] = {"game": &"horse_race", "state": HorseRaceLogic.State.BETTING, "timer": 12.0, "counting": false, "players": [1], "bets": [], "names": NAMES}
	st.balances[1] = 1000
	ui.open(&"horse_race_1", 1, st)
	await wait_process_frames(3)


func test_four_horses_with_names_and_odds() -> void:
	assert_eq(ui.horse_buttons.size(), 4)
	for i: int in 4:
		assert_string_contains(ui.horse_buttons[i].text, String(NAMES[i]).to_upper())
		assert_string_contains(ui.horse_buttons[i].text, "1:4")
		assert_false(ui.horse_buttons[i].disabled, "open for bets")
	assert_true(ui.wants_camera_lock(), "the head stays on the table while betting")
	assert_lt(ui.panel.get_global_rect().size.y, 420.0, "a strip at the bottom, the track stays in view")
	assert_eq(ui.bet_panel.chip_value(), Registry.balance.horse_min_bet, "the smallest chip first")


func test_backing_a_horse_locks_the_others() -> void:
	var pub: Dictionary = (st.stations[&"horse_race_1"] as Dictionary).duplicate()
	pub["counting"] = true
	pub["bets"] = [{"player": 1, "horse": 1, "amount": 25}, {"player": 2, "horse": 3, "amount": 10}]
	ui.update_state(pub, {})
	assert_false(ui.horse_buttons[1].disabled, "more chips on your own horse")
	for i: int in [0, 2, 3]:
		assert_true(ui.horse_buttons[i].disabled, "horse %d locked: one horse per race" % i)
	assert_string_contains(ui.my_bets.text, "$25")
	assert_string_contains(ui.my_bets.text, "Hay Fever")
	assert_string_contains(ui.status_label.text, "12")
	assert_true(ui._dots[3].visible, "someone else is on horse 4")


func test_race_and_result_lines() -> void:
	var pub: Dictionary = (st.stations[&"horse_race_1"] as Dictionary).duplicate()
	pub["state"] = HorseRaceLogic.State.RACING
	pub["progress"] = [0.4, 0.55, 0.5, 0.3]
	ui.update_state(pub, {})
	assert_eq(ui.race_label.text, "Leading: 2 Hay Fever")
	for b: Button in ui.horse_buttons:
		assert_true(b.disabled, "bets are closed once the gates open")
	pub["state"] = HorseRaceLogic.State.RESULT
	pub["winner"] = 2
	ui.update_state(pub, {})
	assert_eq(ui.race_label.text, "WINNER: 3 OAT COUTURE")
	assert_eq(StationUi.rejection_text(&"one_horse_only"), "One horse per race")
