extends GutTest
## Casino Hold'em overlay: a column in the right third (the seat camera frames the felt on the
## left). Before a hand: the ante chips, the AA Bonus row (OFF and its sizes) and DEAL, with the
## all-in room keeping the call covered. After the flop: FOLD and CALL with their amounts, your
## cards and hand named live, the others at the table. At the showdown: the dealer's hand, the
## bonus and main results in plain words. The paytables are folded away under HOW IT WORKS.

const SID: StringName = &"holdem_1"

var root: Control
var ui: HoldemUi
var st: ClientMatchState


func before_each() -> void:
	root = Control.new()
	root.size = Vector2(1920, 1080)
	add_child_autofree(root)
	ui = HoldemUi.new()
	root.add_child(ui)
	st = ClientMatchState.new()
	st.players[1] = {"name": "Ada", "color": 0}
	st.players[2] = {"name": "Bert", "color": 1}
	st.stations[SID] = _pub(HoldemLogic.State.IDLE, {})
	st.balances[1] = 1000
	ui.open(SID, 1, st)
	await wait_process_frames(3)


func _pub(state: int, hands: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var pub: Dictionary = {"game": &"holdem", "state": state, "timer": 6.0, "seats": [1, 2, -1, -1], "hands": hands, "board": [], "dealer": [], "dealer_down": 0}
	pub.merge(extra, true)
	return pub


func _flop() -> Array:
	return [Card.make(1, 3), Card.make(9, 1), Card.make(4, 2)]


## Nothing of the overlay reaches into the left two thirds, where the felt is.
func _assert_right_column(what: String) -> void:
	var r: Rect2 = ui.panel.get_global_rect()
	assert_gt(r.position.x, 1920 * 0.6, "%s: the panel starts in the right third: %s" % [what, r])
	assert_lte(r.end.x, 1920.0, "%s: on screen" % what)
	assert_lte(r.end.y, 1080.0, "%s: on screen" % what)
	for n: Node in ui.panel.find_children("*", "Control", true, false):
		var c: Control = n
		if not c.is_visible_in_tree():
			continue
		var cr: Rect2 = c.get_global_rect()
		assert_true(r.grow(0.5).encloses(cr), "%s: %s stays inside the panel (%s)" % [what, c.name, cr])
		assert_gt(cr.position.x, 1920 * 2.0 / 3.0, "%s: %s is right of the felt" % [what, c.name])


func test_ante_and_the_aa_bonus_before_a_hand() -> void:
	assert_true(ui.bet_panel.visible, "ante first")
	assert_true(ui.bonus_row.visible)
	assert_false(ui.actions.visible)
	assert_true(ui.wants_camera_lock())
	assert_string_contains(ui.status_label.text, "Ante")
	assert_eq(ui.bet_panel.chips[0], Registry.balance.holdem_min_bet, "the smallest chip is the table minimum")
	assert_eq(ui.bet_panel.max_bet, Registry.balance.holdem_max_bet)
	assert_eq(ui.bonus_sizes[0], 0, "OFF first")
	assert_eq(ui.bonus_sizes[ui.bonus_sizes.size() - 1], Registry.balance.holdem_bonus_max_bet, "up to the bonus limit")
	assert_eq(ui.bonus_buttons.size(), ui.bonus_sizes.size())
	assert_eq(ui.bonus_buttons[0].text, "OFF")
	assert_true(ui.bonus_buttons[0].button_pressed, "no bonus unless you pick one")
	ui.cycle_bonus()
	assert_eq(ui.bonus, ui.bonus_sizes[1], "[B] steps through the sizes")
	assert_true(ui.bonus_buttons[1].button_pressed)
	assert_false(ui.bonus_buttons[0].button_pressed)
	ui.set_bonus(12345)
	assert_eq(ui.bonus, 0, "an unknown size is off")
	_assert_right_column("betting")


func test_the_aa_bonus_explains_itself() -> void:
	var cfg: BalanceConfig = Registry.balance
	assert_true(ui.bonus_rule.visible, "a rule line before the deal")
	assert_string_contains(ui.bonus_rule.text, "Pair of Aces or better")
	assert_string_contains(ui.bonus_rule.text, "even if you fold")
	assert_true(ui.bonus_table.visible, "and its paytable")
	assert_eq(ui.bonus_table.get_child_count(), HoldemUi.BONUS_ROWS.size() * 3)
	var texts: PackedStringArray = []
	for c: Node in ui.bonus_table.get_children():
		texts.append((c as Label).text)
	var all: String = " | ".join(texts)
	assert_string_contains(all, "Royal Flush | %d:1" % cfg.holdem_bonus_pays[HoldemHand.Rank.ROYAL_FLUSH])
	assert_string_contains(all, "Pair of Aces – Straight | %d:1" % cfg.holdem_bonus_pays[HoldemHand.Rank.STRAIGHT])
	assert_false(all.contains("wins"), "no amounts while OFF")
	ui.set_bonus(ui.bonus_sizes[1])
	texts.clear()
	for c: Node in ui.bonus_table.get_children():
		if not c.is_queued_for_deletion():
			texts.append((c as Label).text)
	assert_has(texts, "wins %s" % HoldemUi.money(ui.bonus * cfg.holdem_bonus_pays[HoldemHand.Rank.FLUSH]), "what the picked size wins")
	await wait_process_frames(2)
	_assert_right_column("bonus paytable")


func test_the_left_stick_picks_the_aa_bonus() -> void:
	InputGlyphs.set_gamepad(true)
	# The table's stick picker (StationUi._pad_step) reads the stick each frame.
	var push := func(v: float) -> void:
		ui._pad_step(Vector2(v, 0.0), 0.016)
	push.call(1.0)
	assert_eq(ui.bonus, ui.bonus_sizes[1], "right: the next size")
	push.call(0.9)
	assert_eq(ui.bonus, ui.bonus_sizes[1], "held: one step per push")
	push.call(0.0)
	push.call(1.0)
	assert_eq(ui.bonus, ui.bonus_sizes[2])
	push.call(0.0)
	push.call(-1.0)
	assert_eq(ui.bonus, ui.bonus_sizes[1], "left: back one")
	ui.update_state(_pub(HoldemLogic.State.IDLE, {}), {})
	assert_string_contains(ui.hint.text, "Left stick] AA bonus")
	InputGlyphs.set_gamepad(false)


func test_the_bonus_result_in_plain_words() -> void:
	var flop: Array = [Card.make(5, 2), Card.make(9, 2), Card.make(4, 2)]
	assert_eq(HoldemUi.bonus_result_text(10, 0, [Card.make(13), Card.make(13, 1)], flop), "AA BONUS lost  ·  no Pair of Aces or better on the flop  ·  −$10", "kings are not enough")
	var won: String = HoldemUi.bonus_result_text(10, 210, [Card.make(2, 2), Card.make(7, 2)], flop + [Card.make(1)])
	assert_string_contains(won, "AA BONUS WINS")
	assert_string_contains(won, "Flush, Nine High  %d:1" % Registry.balance.holdem_bonus_pays[HoldemHand.Rank.FLUSH], "only the flop counts, not the turn")
	assert_string_contains(won, "+$200")
	assert_eq(ui._ribbon_tag({"details": {"type": HoldemLogic.BONUS}}), "AA BONUS")
	assert_eq(ui._ribbon_tag({"details": {"type": HoldemLogic.ANTE}}), "")


func test_all_in_keeps_the_call_covered() -> void:
	st.balances[1] = 70
	ui.set_bonus(ui.bonus_sizes[1])
	ui.update_state(_pub(HoldemLogic.State.IDLE, {}), {})
	assert_eq(ui.bet_panel.balance, (70 - ui.bonus) / 3, "the ante's room: a third of what the bonus leaves")


func test_fold_or_call_after_the_flop() -> void:
	var hands: Dictionary = {
		1: {"ante": 20, "bonus": 10, "hole": [Card.make(1), Card.make(1, 1)], "decision": &"", "hand": "Pair of Aces", "clock": 11.2, "bonus_returned": 80},
		2: {"ante": 10, "hole": [Card.make(12), Card.make(5, 2)], "decision": &"call", "hand": "Queen High"},
	}
	ui.update_state(_pub(HoldemLogic.State.DECIDING, hands, {"board": _flop(), "dealer_down": 2}), {})
	assert_true(ui.actions.visible, "your decision")
	assert_false(ui.bet_panel.visible, "no second ante mid-hand")
	assert_false(ui.bonus_row.visible)
	assert_true(ui.wants_camera_lock(), "locked while you decide")
	assert_string_contains(ui.call_btn.text, "CALL")
	assert_string_contains(ui.call_btn.text, "$40", "twice the ante")
	assert_string_contains(ui.fold_btn.text, "FOLD")
	assert_string_contains(ui.fold_btn.text, "$20")
	assert_false(ui.call_btn.disabled)
	assert_string_contains(ui.status_label.text, "12 s", "your own clock")
	assert_eq(ui.hand_label.text, "Pair of Aces", "named live")
	assert_string_contains(ui.cards_label.text, "A♠")
	assert_string_contains(ui.cards_label.text, "A♥")
	assert_string_contains(ui.cards_label.text, "9♥", "and the flop")
	assert_eq(ui.dealer_label.text, "DEALER  ??  ??", "the dealer's two face down")
	assert_string_contains(ui.result_label.text, "AA BONUS WINS", "the bonus settled with the flop")
	assert_string_contains(ui.result_label.text, "Three Aces  7:1", "names the hand that hit and its odds")
	assert_string_contains(ui.result_label.text, "+$70")
	assert_string_contains(ui.others_label.text, "Bert: called")
	_assert_right_column("deciding")
	st.balances[1] = 30
	ui.update_state(_pub(HoldemLogic.State.DECIDING, hands, {"board": _flop(), "dealer_down": 2}), {})
	assert_true(ui.call_btn.disabled, "the call must be covered")


func test_the_river_bet_or_check() -> void:
	var board: Array = _flop()
	board.append(Card.make(13, 3))
	var hands: Dictionary = {
		1: {"ante": 20, "hole": [Card.make(1), Card.make(1, 1)], "decision": &"call", "call": 40, "river": 0, "river_decision": &"", "hand": "Pair of Aces", "clock": 7.5},
		2: {"ante": 10, "hole": [Card.make(12), Card.make(5, 2)], "decision": &"call", "call": 20, "river": 10, "river_decision": &"river", "hand": "Queen High"},
	}
	ui.update_state(_pub(HoldemLogic.State.RIVER, hands, {"board": board, "dealer_down": 2}), {})
	assert_true(ui.actions.visible, "your river decision")
	assert_true(ui.wants_camera_lock())
	assert_string_contains(ui.call_btn.text, "RIVER BET")
	assert_string_contains(ui.call_btn.text, "$20", "one ante")
	assert_string_contains(ui.fold_btn.text, "CHECK")
	assert_string_contains(ui.status_label.text, "8 s")
	assert_string_contains(ui.cards_label.text, "K♣", "the turn")
	assert_eq(ui.dealer_label.text, "DEALER  ??  ??")
	assert_string_contains(ui.others_label.text, "Bert: bet the river")
	assert_string_contains(ui.rules_label.text, "RIVER BET")
	hands[1]["river_decision"] = &"check"
	ui.update_state(_pub(HoldemLogic.State.RIVER, hands, {"board": board, "dealer_down": 2}), {})
	assert_false(ui.actions.visible, "checked")
	assert_string_contains(ui.status_label.text, "Waiting for the river")


func test_folded_and_the_showdown() -> void:
	var folded: Dictionary = {1: {"ante": 20, "hole": [Card.make(2), Card.make(7, 1)], "decision": &"fold", "hand": "Ace High", "outcome": &"fold", "returned": 0}}
	ui.update_state(_pub(HoldemLogic.State.DECIDING, folded, {"board": _flop(), "dealer_down": 2}), {})
	assert_false(ui.actions.visible)
	assert_false(ui.wants_camera_lock(), "look around while the others decide")
	assert_eq(ui.hand_label.text, "FOLDED")
	assert_string_contains(ui.result_label.text, "Folded")
	assert_string_contains(ui.status_label.text, "Waiting")
	var board: Array = _flop() + [Card.make(13, 2), Card.make(3)]
	var won: Dictionary = {1: {"ante": 20, "call": 40, "hole": [Card.make(1), Card.make(1, 1)], "decision": &"call", "hand": "Three of a Kind, Aces", "outcome": &"win", "returned": 120}}
	ui.update_state(_pub(HoldemLogic.State.PAYOUT, won, {"board": board, "dealer": [Card.make(4), Card.make(4, 1)], "dealer_hand": "Pair of Fours", "qualifies": true}), {})
	assert_eq(ui.status_label.text, "Showdown")
	assert_string_contains(ui.dealer_label.text, "4♠  4♥")
	assert_string_contains(ui.dealer_label.text, "Pair of Fours")
	assert_string_contains(ui.result_label.text, "YOU WIN  ·  +$60")
	var nq: Dictionary = {1: {"ante": 20, "call": 40, "hole": [Card.make(1), Card.make(1, 1)], "decision": &"call", "hand": "Pair of Aces", "outcome": &"no_qualify", "returned": 80}}
	ui.update_state(_pub(HoldemLogic.State.PAYOUT, nq, {"board": board, "dealer": [Card.make(2), Card.make(8, 1)], "dealer_hand": "King High", "qualifies": false}), {})
	assert_string_contains(ui.dealer_label.text, "does not qualify")
	assert_string_contains(ui.result_label.text, "ante pays, call back")
	assert_string_contains(ui.result_label.text, "+$20")
	var lost: Dictionary = {1: {"ante": 20, "call": 40, "bonus": 10, "bonus_returned": 0, "hole": [Card.make(2), Card.make(3, 1)], "decision": &"call", "hand": "Pair of Twos", "outcome": &"lose", "returned": 0}}
	ui.update_state(_pub(HoldemLogic.State.PAYOUT, lost, {"board": board, "dealer": [Card.make(13), Card.make(13, 1)], "dealer_hand": "Three of a Kind, Kings", "qualifies": true}), {})
	assert_string_contains(ui.result_label.text, "AA BONUS lost")
	assert_string_contains(ui.result_label.text, "no Pair of Aces or better")
	assert_string_contains(ui.result_label.text, "Dealer wins  ·  −$60")
	_assert_right_column("showdown")


func test_the_paytables_fold_away() -> void:
	assert_not_null(ui.rules_toggle, "a HOW IT WORKS line")
	assert_false(ui.rules_label.visible, "folded by default")
	ui.rules_toggle.button_pressed = true
	await wait_process_frames(2)
	assert_true(ui.rules_label.visible)
	var cfg: BalanceConfig = Registry.balance
	assert_string_contains(ui.rules_label.text, "pair of 4s")
	assert_string_contains(ui.rules_label.text, "Royal Flush %d:1" % cfg.holdem_ante_pays[HoldemHand.Rank.ROYAL_FLUSH])
	assert_string_contains(ui.rules_label.text, "Flush %d:1" % cfg.holdem_ante_pays[HoldemHand.Rank.FLUSH])
	assert_string_contains(ui.rules_label.text, "Straight or lower 1:1")
	assert_string_contains(ui.rules_label.text, "Pair of Aces to Straight %d:1" % cfg.holdem_bonus_pays[HoldemHand.Rank.STRAIGHT])
	assert_string_contains(ui.rules_label.text, "Out of time = fold")
	_assert_right_column("rules open")
	ui.rules_toggle.button_pressed = false
	assert_false(ui.rules_label.visible)
