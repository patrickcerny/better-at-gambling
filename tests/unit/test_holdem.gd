extends GutTest
## Casino Hold'em table logic (`HoldemLogic`): four seats against one dealer and one board, ante
## (+ the optional AA Bonus), two hole cards and the flop, FOLD or CALL (twice the ante) on each
## player's own clock (out of time = fold), turn, river, the dealer qualifies with fours or
## better; every payout branch, the bonus paytable, refunds at a minigame, standing up, the match
## end, the quiet house rule (never sent) and luck.

var fx: TableFixture
var t: HoldemLogic


func before_each() -> void:
	fx = TableFixture.new(5, [1, 2, 3, 4, 5], 1000)
	fx.balance.holdem_favour = 0.0  # the plain rules unless a test says otherwise
	fx.balance.holdem_bonus_favour = 0.0
	t = fx.make(HoldemLogic.new(), &"holdem_t") as HoldemLogic
	t.join(1)
	t.join(2)


func _c(name: String) -> int:
	var suit: int = "SHDC".find(name.right(1))
	var r: String = name.left(name.length() - 1)
	var rank: int = {"A": 1, "J": 11, "Q": 12, "K": 13}.get(r, 0) if not r.is_valid_int() else int(r)
	return Card.make(rank, suit)


func _h(names: String) -> Array[int]:
	var out: Array[int] = []
	for n: String in names.split(" ", false):
		out.append(_c(n))
	return out


func _types(type: StringName) -> Array[Dictionary]:
	return t.events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _results(p: int) -> Array[Dictionary]:
	return _types(&"round_result").filter(func(e: Dictionary) -> bool: return int(e["player"]) == p)


## Player 1 antes `ante` (+ `bonus`), alone, the deck rigged to `cards` (deal order: hole cards,
## flop, turn, river, the dealer's two), and the window runs out.
func _deal_one(cards: String, ante: int = 10, bonus: int = 0) -> void:
	t.rigged = _h(cards)
	assert_true(t.place_bet(1, {"amount": ante, "bonus": bonus})["ok"])
	t.tick(fx.balance.holdem_betting_window + 0.1)
	assert_eq(t.state, HoldemLogic.State.DECIDING)


func test_seats_limited_to_four() -> void:
	t.join(3)
	t.join(4)
	assert_false(t.can_join(5))
	assert_eq(t.join(5)["error"], &"seat_taken")
	t.leave(4)
	assert_true(t.can_join(5))


func test_bet_limits_and_the_call_must_be_covered() -> void:
	assert_eq(t.place_bet(3, {"amount": 10})["error"], &"not_seated")
	assert_eq(t.place_bet(1, {"amount": 5})["error"], &"below_min")
	assert_eq(t.place_bet(1, {"amount": 500})["error"], &"above_max")
	assert_eq(t.place_bet(1, {"amount": 10, "bonus": 5})["error"], &"below_min", "a bonus is at least the table minimum")
	assert_eq(t.place_bet(1, {"amount": 10, "bonus": 80})["error"], &"above_max")
	fx.economy.apply(2, -975, &"test")  # $25 left: an ante of 10 can't be called (needs 30)
	assert_eq(t.place_bet(2, {"amount": 10})["error"], &"insufficient_funds")
	assert_eq(fx.economy.balance(2), 25, "nothing taken")
	assert_true(t.place_bet(1, {"amount": 20, "bonus": 10})["ok"])
	assert_eq(fx.economy.balance(1), 970, "ante and bonus taken at once")
	assert_eq(t.place_bet(1, {"amount": 20})["error"], &"already_bet")
	var placed: Array[Dictionary] = _types(&"bet_placed")
	assert_eq(placed.size(), 2, "one chip stack on ANTE, one on BONUS")
	assert_eq(StringName(placed[0]["details"]["type"]), &"ante")
	assert_eq(StringName(placed[1]["details"]["type"]), &"bonus")


func test_all_in_keeps_the_call_covered() -> void:
	fx.economy.apply(1, -880, &"test")  # $120
	var b: Dictionary = t.clamp_bet(1, {"amount": 100, "bonus": 30})
	assert_eq(int(b["amount"]), 30, "(120 − 30 bonus) / 3")
	assert_true(bool(b["all_in"]))
	assert_true(t.place_bet(1, b)["ok"])
	assert_eq(fx.economy.balance(1), 60, "the call is still there")
	assert_eq(int(t.clamp_bet(2, {"amount": 500})["amount"]), 100, "over the max bets the max")
	assert_false(t.clamp_bet(2, {"amount": 50, "all_in": true}).has("all_in"), "a client can't fake it")


func test_betting_window_then_the_deal() -> void:
	assert_true(t.place_bet(1, {"amount": 10})["ok"])
	assert_eq(t.state, HoldemLogic.State.BETTING)
	assert_eq(_types(&"round_started").size(), 1)
	t.tick(3.0)
	assert_true(t.place_bet(2, {"amount": 25})["ok"], "others can ante while the window is open")
	t.tick(fx.balance.holdem_betting_window)
	assert_eq(t.state, HoldemLogic.State.DECIDING)
	assert_eq(t.place_bet(3, {"amount": 10})["error"], &"not_seated")
	t.join(3)
	assert_eq(t.place_bet(3, {"amount": 10})["error"], &"betting_closed")
	var pub: Dictionary = t.get_public_state()
	assert_eq((pub["board"] as Array).size(), 3, "the flop")
	assert_eq((pub["dealer"] as Array).size(), 0, "the dealer's cards stay face down")
	assert_eq(int(pub["dealer_down"]), 2)
	assert_false(pub.has("dealer_hand"))
	for p: int in [1, 2]:
		var h: Dictionary = pub["hands"][p]
		assert_eq((h["hole"] as Array).size(), 2)
		assert_true(String(h["hand"]).length() > 0, "the hand is named live")
		assert_almost_eq(float(h["clock"]), fx.balance.holdem_action_time, 0.001)
	# Seven different cards among the hands and the board.
	var seen: Dictionary = {}
	for c: Variant in (pub["board"] as Array) + (pub["hands"][1]["hole"] as Array) + (pub["hands"][2]["hole"] as Array):
		seen[int(c)] = true
	assert_eq(seen.size(), 7)


func test_fold_loses_the_ante() -> void:
	_deal_one("2C 7D 9S 5H KD QC 3S 4C 4D")
	assert_eq(t.player_action(1, &"fold")["ok"], true)
	var r: Array[Dictionary] = _results(1)
	assert_eq(r.size(), 1)
	assert_eq(int(r[0]["returned"]), 0)
	assert_eq(StringName(r[0]["details"]["outcome"]), &"fold")
	assert_eq(fx.economy.balance(1), 990)
	assert_eq(t.state, HoldemLogic.State.PAYOUT, "nobody left to decide: the showdown")
	assert_eq(t.player_action(1, &"call")["error"], &"wrong_state")
	assert_false(t.has_stake(1))


func test_dealer_does_not_qualify_ante_pays_the_paytable_call_pushes() -> void:
	# A flush, ace high; the dealer has king high.
	_deal_one("AH 9H 7H 4H 2H KS 3D QC JD")
	assert_true(t.player_action(1, &"call")["ok"])
	var calls: Array[Dictionary] = _types(&"bet_placed").filter(func(e: Dictionary) -> bool: return StringName(e["details"]["type"]) == &"call")
	assert_eq(int(calls[0]["amount"]), 20, "the call is twice the ante")
	var r: Dictionary = _results(1)[0]
	assert_eq(StringName(r["details"]["outcome"]), &"no_qualify")
	assert_eq(int(r["stake"]), 30)
	assert_eq(int(r["returned"]), 10 + 10 * 2 + 20, "ante 2:1 for the flush, call back")
	assert_eq(fx.economy.balance(1), 1020)
	var pub: Dictionary = t.get_public_state()
	assert_eq((pub["board"] as Array).size(), 5)
	assert_eq(pub["dealer"], _h("QC JD"))
	assert_false(bool(pub["qualifies"]))
	assert_eq(String(pub["dealer_hand"]), "King High")
	assert_eq(String(pub["hands"][1]["hand"]), "Flush, Ace High")
	assert_eq((pub["hands"][1]["best"] as Array).size(), 5)


func test_player_beats_a_qualifying_dealer() -> void:
	_deal_one("AS AD 9C 5H 2S KD 7C 4C 4D")
	t.player_action(1, &"call")
	var r: Dictionary = _results(1)[0]
	assert_eq(StringName(r["details"]["outcome"]), &"win")
	assert_eq(int(r["returned"]), 20 + 40, "ante 1:1 (a pair), call 1:1")
	assert_eq(fx.economy.balance(1), 1030)


func test_a_tie_pushes_both() -> void:
	# Both play the board's aces with king, queen, jack.
	_deal_one("2C 3D AS AD KS QH JC 4C 5D")
	t.player_action(1, &"call")
	var r: Dictionary = _results(1)[0]
	assert_eq(StringName(r["details"]["outcome"]), &"push")
	assert_eq(int(r["returned"]), 30)
	assert_eq(fx.economy.balance(1), 1000)


func test_the_dealer_takes_both() -> void:
	_deal_one("2C 7D 9S 5H KD QC 3S 4C 4D")
	t.player_action(1, &"call")
	var r: Dictionary = _results(1)[0]
	assert_eq(StringName(r["details"]["outcome"]), &"lose")
	assert_eq(int(r["returned"]), 0)
	assert_eq(fx.economy.balance(1), 970)


func test_big_hands_pay_the_ante_paytable() -> void:
	var cfg := BalanceConfig.new()
	var dealer_pair: int = HoldemHand.evaluate(_h("4C 4D 9S 2H 7C"))
	var dealer_nothing: int = HoldemHand.evaluate(_h("AC JD 9S 2H 7C"))
	var cases: Array = [
		["AH KH QH JH 10H", 100], ["9H 8H 7H 6H 5H", 20], ["9S 9D 9H 9C 2S", 10], ["9S 9D 9H 2C 2S", 3],
		["AH 9H 7H 4H 2H", 2], ["9S 8D 7H 6C 5S", 1], ["9S 9D 9H 3C 2S", 1], ["9S 9D 3H 3C 2S", 1], ["9S 9D 7H 3C 2S", 1], ["AS KD 7H 3C 2S", 1],
	]
	for row: Array in cases:
		var s: int = HoldemHand.evaluate(_h(row[0]))
		var pay: int = row[1]
		assert_eq(HoldemLogic.ante_pay(HoldemHand.category(s), cfg), pay, "%s pays %d:1" % [HoldemHand.describe(s), pay])
		assert_eq(HoldemLogic.main_return(10, 20, s, dealer_nothing, cfg), 10 * (1 + pay) + 20, "%s against no dealer hand" % row[0])
		if s > dealer_pair:
			assert_eq(HoldemLogic.main_return(10, 20, s, dealer_pair, cfg), 10 * (1 + pay) + 40, "%s beats the fours" % row[0])
	# The dealer's pair of fours beats ace high; the ace high still beats a dealer who doesn't qualify.
	var ace_high: int = HoldemHand.evaluate(_h("AS KD 7H 3C 2S"))
	assert_eq(HoldemLogic.main_outcome(ace_high, dealer_pair), &"lose")
	assert_eq(HoldemLogic.main_return(10, 20, ace_high, dealer_pair, cfg), 0)
	assert_eq(HoldemLogic.main_outcome(ace_high, HoldemHand.evaluate(_h("3C 3D 9S 2H 7C"))), &"no_qualify", "threes don't qualify")


func test_aa_bonus_paytable() -> void:
	var cfg := BalanceConfig.new()
	var cases: Array = [
		["AS AD 9C 5H 2S", 7], ["KS KD 9C 5H 2S", 0], ["AS KD 9C 5H 2S", 0], ["KS KD 9C 9H 2S", 7], ["4S 4D 4C 9H 2S", 7],
		["9S 8D 7C 6H 5S", 7], ["AH 9H 7H 4H 2H", 20], ["4S 4D 4C 9H 9S", 30], ["4S 4D 4C 4H 9S", 40], ["9H 8H 7H 6H 5H", 50], ["AH KH QH JH 10H", 100],
	]
	for row: Array in cases:
		var s: int = HoldemHand.evaluate(_h(row[0]))
		var pay: int = row[1]
		assert_eq(HoldemLogic.bonus_pay(s, cfg), pay, "%s" % HoldemHand.describe(s))
		assert_eq(HoldemLogic.bonus_return(10, s, cfg), 10 * (1 + pay) if pay > 0 else 0)


func test_bonus_settles_on_the_flop_even_after_a_fold() -> void:
	# Pair of aces in the first five cards: the bonus pays 7:1 at the deal.
	_deal_one("AS AH 9C 5H 2S KD 7C 4C 4D", 10, 10)
	var r: Array[Dictionary] = _results(1)
	assert_eq(r.size(), 1, "the bonus is settled before anyone decides")
	assert_eq(StringName(r[0]["details"]["type"]), &"bonus")
	assert_eq(int(r[0]["returned"]), 80)
	assert_eq(String(r[0]["details"]["hand"]), "Pair of Aces")
	t.player_action(1, &"fold")
	assert_eq(_results(1).size(), 2)
	assert_eq(fx.economy.balance(1), 1000 - 10 - 10 + 80, "ante lost, bonus paid")
	# A bonus with nothing in it is lost at the flop.
	t.tick(fx.balance.holdem_result_time + 0.1)
	t.events.clear()
	_deal_one("KS KH 9C 5H 2S QD 7C 4C 4D", 10, 10)
	assert_eq(int(_results(1)[0]["returned"]), 0, "kings don't pay the AA bonus")
	assert_true(t.has_stake(1), "the ante is still open")


func test_timeout_folds() -> void:
	_deal_one("AS AD 9C 5H 2S KD 7C 4C 4D")
	t.tick(fx.balance.holdem_action_time * 0.5)
	assert_eq(t.state, HoldemLogic.State.DECIDING)
	assert_almost_eq(float(t.get_public_state()["hands"][1]["clock"]), fx.balance.holdem_action_time * 0.5, 0.01)
	t.tick(fx.balance.holdem_action_time * 0.5 + 0.1)
	assert_eq(StringName(_results(1)[0]["details"]["outcome"]), &"fold", "out of time folds, like the real table")
	assert_eq(t.state, HoldemLogic.State.PAYOUT)
	t.tick(fx.balance.holdem_result_time + 0.1)
	assert_eq(t.state, HoldemLogic.State.IDLE)
	assert_true(t.hands.is_empty())


func test_everyone_on_their_own_clock() -> void:
	t.place_bet(1, {"amount": 10})
	t.place_bet(2, {"amount": 10})
	t.tick(fx.balance.holdem_betting_window + 0.1)
	t.player_action(2, &"call")
	assert_eq(t.state, HoldemLogic.State.DECIDING, "player 1 still deciding")
	assert_eq(t.player_action(2, &"fold")["error"], &"no_active_hand", "one decision per hand")
	t.player_action(1, &"call")
	assert_eq(t.state, HoldemLogic.State.PAYOUT)
	assert_eq(_types(&"holdem_showdown").size(), 1)
	assert_eq(_results(1).size(), 1)
	assert_eq(_results(2).size(), 1)
	# Both played the same board against the same dealer.
	var a: Dictionary = _results(1)[0]["details"]
	var b: Dictionary = _results(2)[0]["details"]
	assert_eq(a["dealer"], b["dealer"])
	assert_eq((a["cards"] as Array).slice(2), (b["cards"] as Array).slice(2), "one board")


func test_leaving_mid_hand_folds_and_a_called_hand_plays_on() -> void:
	t.place_bet(1, {"amount": 10})
	t.place_bet(2, {"amount": 10})
	t.tick(fx.balance.holdem_betting_window + 0.1)
	t.player_action(2, &"call")
	t.leave(2)
	assert_eq(t.state, HoldemLogic.State.DECIDING)
	t.leave(1)
	assert_eq(StringName(_results(1)[0]["details"]["outcome"]), &"fold")
	assert_eq(_results(2).size(), 1, "the called hand went to the showdown")
	assert_ne(StringName(_results(2)[0]["details"]["outcome"]), &"fold")


func test_standing_up_before_the_deal_folds_at_the_deal() -> void:
	t.rigged = _h("AS AH 9C 5H 2S")
	t.place_bet(1, {"amount": 10, "bonus": 10})
	t.leave(1)
	assert_true(t.has_stake(1))
	t.tick(fx.balance.holdem_betting_window + 0.1)
	var r: Array[Dictionary] = _results(1)
	assert_eq(r.size(), 2, "the bonus was played, then the ante folded")
	assert_eq(int(r[0]["returned"]), 80)
	assert_eq(StringName(r[1]["details"]["outcome"]), &"fold")
	assert_false(t.has_stake(1))


func test_auto_resolve_from_betting_and_deciding() -> void:
	t.place_bet(1, {"amount": 10})
	t.auto_resolve()
	assert_eq(t.state, HoldemLogic.State.IDLE)
	assert_eq(StringName(_results(1)[0]["details"]["outcome"]), &"fold", "dealt, then the auto rule")
	t.events.clear()
	t.place_bet(1, {"amount": 10})
	t.place_bet(2, {"amount": 10})
	t.tick(fx.balance.holdem_betting_window + 0.1)
	t.player_action(2, &"call")
	t.auto_resolve()
	assert_eq(_results(1).size(), 1)
	assert_eq(_results(2).size(), 1)
	assert_false(t.has_stake(1))
	assert_false(t.has_stake(2))
	assert_eq(t.state, HoldemLogic.State.IDLE)


func test_refund_all_gives_back_every_open_bet() -> void:
	# Before the deal: ante and bonus back.
	t.place_bet(1, {"amount": 20, "bonus": 10})
	t.refund_all()
	assert_eq(fx.economy.balance(1), 1000)
	var refunds: Array[Dictionary] = _types(&"bets_refunded")
	assert_eq(int(refunds[0]["amount"]), 30)
	assert_eq(_types(&"table_reset").size(), 1)
	assert_eq(t.state, HoldemLogic.State.IDLE)


func test_refund_all_mid_decision() -> void:
	t.rigged = _h("AS AH 9C 5H 2S 7D JC")
	t.place_bet(1, {"amount": 20, "bonus": 10})
	t.place_bet(2, {"amount": 10})
	t.tick(fx.balance.holdem_betting_window + 0.1)
	t.player_action(1, &"call")
	t.events.clear()
	t.refund_all()
	assert_eq(fx.economy.balance(1), 1000 - 10 + 80, "ante and call back, the won bonus kept")
	assert_eq(fx.economy.balance(2), 1000, "an undecided ante back")
	var refunds: Array[Dictionary] = _types(&"bets_refunded")
	assert_eq(refunds.size(), 2)
	assert_true(t.hands.is_empty())
	assert_eq(t.state, HoldemLogic.State.IDLE)
	assert_false(t.has_stake(1))
	assert_eq(t.get_public_state()["board"], [])


func test_money_is_conserved_over_many_hands() -> void:
	var r := SeededRng.new(9)
	var house: int = 0
	for i: int in 300:
		for p: int in [1, 2]:
			if fx.economy.balance(p) < 400:
				fx.economy.apply(p, 1000, &"test")
				house -= 1000
		var before: int = fx.economy.balance(1) + fx.economy.balance(2)
		t.place_bet(1, {"amount": 10 * r.range_int(1, 10), "bonus": 10 if r.chance(0.5) else 0})
		t.place_bet(2, {"amount": 10})
		t.tick(fx.balance.holdem_betting_window + 0.1)
		for p: int in [1, 2]:
			var h: Dictionary = t.hands[p]
			t.player_action(p, &"call" if HoldemLogic.simple_call(h["hole"], t.board) else &"fold")
		var paid: int = 0
		for e: Dictionary in t.drain_events():
			if e["type"] == &"round_result":
				paid += int(e["returned"]) - int(e["stake"])
		assert_eq(fx.economy.balance(1) + fx.economy.balance(2) - before, paid, "hand %d: every dollar accounted for" % i)
		t.tick(fx.balance.holdem_result_time + 0.1)
		assert_eq(t.state, HoldemLogic.State.IDLE)


func test_the_house_quietly_favours_the_called_hands() -> void:
	var plain: int = _wins_out_of(400, 0.0, 0)
	var favoured: int = _wins_out_of(400, 1.0, 0)
	gut.p("called hands won or pushed: %d/400 plain, %d/400 with every losing showdown redrawn once" % [plain, favoured])
	assert_gt(favoured, plain + 40, "a redraw of a losing showdown tilts it to the player")
	assert_lt(favoured, 400, "but it is a nudge, not a fix")
	# Nothing on the wire says so.
	for ev: Dictionary in t.events:
		for key: Variant in ev:
			assert_false(String(key).contains("favour") or String(key).contains("redraw"), "%s carries nothing of the draw" % ev["type"])
	assert_false(str(t.get_public_state()).contains("favour"))


func test_the_bonus_favour_redraws_a_dead_flop() -> void:
	var plain: int = _bonus_hits(600, 0.0)
	var favoured: int = _bonus_hits(600, 1.0)
	gut.p("AA bonus hits: %d/600 plain, %d/600 with a dead flop redrawn once" % [plain, favoured])
	assert_gt(favoured, plain + 20)


func test_luck_moves_the_cards() -> void:
	var jinxed: int = _wins_out_of(300, 0.0, -3)
	var lucky: int = _wins_out_of(300, 0.0, 3)
	gut.p("called hands won or pushed by luck: −3 %d/300, +3 %d/300" % [jinxed, lucky])
	assert_gt(lucky, jinxed + 30)
	assert_gt(_types(&"luck_flourish").size(), 0, "a clover or black cat when luck changed a card")


## Called hands (always called) that did not lose, out of `n`.
func _wins_out_of(n: int, favour: float, lk: int) -> int:
	fx = TableFixture.new(41, [1], 100_000_000)
	fx.balance.holdem_favour = favour
	fx.balance.holdem_bonus_favour = 0.0
	t = fx.make(HoldemLogic.new(), &"holdem_t") as HoldemLogic
	t.join(1)
	if lk != 0:
		fx.give_luck(1, lk)
	var won: int = 0
	for i: int in n:
		t.place_bet(1, {"amount": 10})
		t.tick(fx.balance.holdem_betting_window + 0.1)
		t.player_action(1, &"call")
		var r: Array[Dictionary] = _results(1)
		if int(r.back()["returned"]) >= 30:
			won += 1
		t.tick(fx.balance.holdem_result_time + 0.1)
	return won


func _bonus_hits(n: int, favour: float) -> int:
	fx = TableFixture.new(43, [1], 100_000_000)
	fx.balance.holdem_favour = 0.0
	fx.balance.holdem_bonus_favour = favour
	t = fx.make(HoldemLogic.new(), &"holdem_t") as HoldemLogic
	t.join(1)
	var hits: int = 0
	for i: int in n:
		t.place_bet(1, {"amount": 10, "bonus": 10})
		t.tick(fx.balance.holdem_betting_window + 0.1)
		if int(_results(1).back()["returned"]) > 0:
			hits += 1
		t.player_action(1, &"fold")
		t.tick(fx.balance.holdem_result_time + 0.1)
		t.events.clear()
	return hits
