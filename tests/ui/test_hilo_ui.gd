extends GutTest
## Hi-Lo panel: the HIGHER / LOWER buttons carry the call's true chance and its pay exactly as the
## server sent them, an impossible call is greyed out, CASH OUT and the ladder appear after a
## right call, and the ante chips show while you have no hand in play.

const SID: StringName = &"hilo_1"

var root: Control
var ui: HiLoUi
var st: ClientMatchState


func before_each() -> void:
	root = Control.new()
	root.size = Vector2(1920, 1080)
	add_child_autofree(root)
	ui = HiLoUi.new()
	root.add_child(ui)
	st = ClientMatchState.new()
	st.stations[SID] = {"game": &"hilo", "state": HiLoLogic.State.IDLE, "seats": [1, 2, -1, -1], "hands": {}, "deck_left": 52}
	st.balances[1] = 1000
	st.players[2] = {"name": "Bob"}
	ui.open(SID, 1, st)
	await wait_process_frames(3)


func _pub(hands: Dictionary) -> Dictionary:
	return {"game": &"hilo", "state": HiLoLogic.State.PLAYING, "seats": [1, 2, -1, -1], "hands": hands, "deck_left": 40}


func _hand(cards: Array, rung: int, odds: Dictionary, pays: Dictionary, pot: int = 20) -> Dictionary:
	return {"stake": 20, "cards": cards, "phase": "play", "rung": rung, "mult": float(pot) / 20.0, "pot": pot, "odds": odds, "pays": pays, "timer": 12.0, "outcome": "", "guess": ""}


func test_no_hand_shows_the_ante_chips() -> void:
	assert_true(ui.bet_panel.visible, "ante first")
	assert_false(ui.actions.visible)
	assert_string_contains(ui.status_label.text, "Ante")
	assert_eq(ui.bet_panel.chips[0], Registry.balance.hilo_min_bet, "the smallest chip is the table minimum")
	assert_true(ui.wants_camera_lock())
	assert_lte(ui.panel.get_global_rect().end.x, 1920.0, "docked on screen")


func test_the_call_buttons_show_the_true_odds_and_pays() -> void:
	var odds: Dictionary = {"higher": 0.5490, "lower": 0.3921, "tie": 0.0588}
	var pays: Dictionary = {"higher": 1.74, "lower": 2.38}
	ui.update_state(_pub({1: _hand([Card.make(7, 1)], 0, odds, pays)}), {})
	assert_true(ui.actions.visible)
	assert_false(ui.bet_panel.visible, "no second ante while the call is open")
	assert_string_contains(ui.higher_btn.text, "HIGHER")
	assert_string_contains(ui.higher_btn.text, "55%")
	assert_string_contains(ui.higher_btn.text, "×1.74")
	assert_string_contains(ui.lower_btn.text, "LOWER")
	assert_string_contains(ui.lower_btn.text, "39%")
	assert_string_contains(ui.lower_btn.text, "×2.38")
	assert_false(ui.higher_btn.disabled)
	assert_false(ui.lower_btn.disabled)
	assert_false(ui.cash_btn.visible, "nothing to cash before a right call")
	assert_string_contains(ui.card_label.text, "7♥")
	assert_string_contains(ui.status_label.text, "12 s")
	assert_string_contains(ui.others_label.text, "Bob: watching")


func test_an_impossible_call_is_greyed_out() -> void:
	var odds: Dictionary = {"higher": 0.0, "lower": 0.94, "tie": 0.06}
	var pays: Dictionary = {"higher": 0.0, "lower": 1.06}
	ui.update_state(_pub({1: _hand([Card.make(1, 2)], 0, odds, pays)}), {})
	assert_true(ui.higher_btn.disabled, "nothing beats an ace")
	assert_false(ui.lower_btn.disabled)
	assert_string_contains(ui.lower_btn.text, "94%")
	assert_eq(HiLoUi.percent(0.004), "<1%")
	assert_eq(HiLoUi.percent(0.996), ">99%")
	assert_eq(StationUi.rejection_text(&"no_chance"), "No card can do that")


func test_after_a_right_call_ride_or_cash_out() -> void:
	var odds: Dictionary = {"higher": 0.31, "lower": 0.63, "tie": 0.06}
	var pays: Dictionary = {"higher": 2.94, "lower": 1.53}
	var hands: Dictionary = {1: _hand([Card.make(5), Card.make(10, 3)], 2, odds, pays, 61), 2: _hand([Card.make(12)], 0, odds, pays)}
	ui.update_state(_pub(hands), {})
	assert_true(ui.cash_btn.visible)
	assert_string_contains(ui.cash_btn.text, "$61")
	assert_string_contains(ui.pot_label.text, "POT $61")
	assert_string_contains(ui.status_label.text, "Ride it or cash out")
	assert_true(ui.ladder_row.visible)
	var lit: int = 0
	for l: Label in ui.ladder_marks:
		var sb: StyleBoxFlat = l.get_theme_stylebox(&"normal") as StyleBoxFlat
		if sb.bg_color == Palette.VIP_GOLD:
			lit += 1
	assert_eq(lit, 2, "two steps up the ladder")
	assert_string_contains(ui.higher_btn.text, "31%", "the next call's odds for the ride")
	assert_string_contains(ui.others_label.text, "Bob: Q♠")


func test_results_read_plainly() -> void:
	var lost: Dictionary = _hand([Card.make(9), Card.make(9, 1)], 0, {}, {})
	lost["phase"] = "done"
	lost["outcome"] = "lose"
	ui.update_state(_pub({1: lost}), {})
	assert_false(ui.actions.visible)
	assert_true(ui.bet_panel.visible, "ante again right away")
	assert_string_contains(ui.status_label.text, "wrong call")
	var won: Dictionary = _hand([Card.make(4), Card.make(8), Card.make(13)], 2, {}, {}, 88)
	won["phase"] = "done"
	won["outcome"] = "cashed"
	ui.update_state(_pub({1: won}), {})
	assert_string_contains(ui.pot_label.text, "+$88")
	assert_string_contains(ui.status_label.text, "2 right calls")
