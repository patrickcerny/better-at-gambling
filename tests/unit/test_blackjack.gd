extends GutTest

var fx: TableFixture
var bj: BlackjackLogic


func before_each() -> void:
	fx = TableFixture.new(1, [1, 2], 1000)
	bj = fx.make(BlackjackLogic.new(), &"bj1") as BlackjackLogic
	bj.join(1)
	bj.join(2)


func _c(ranks: Array) -> Array[int]:
	var out: Array[int] = []
	for r: int in ranks:
		out.append(Card.make(r))
	return out


## Stacks the shoe for a round with players [1, 2] betting (deal order: p1, p2, dealer up, p1, p2, hole).
func _stack(cards: Array) -> void:
	bj.shoe.stack_top(_c(cards))


func test_seats_limited_to_four() -> void:
	bj.join(3)
	bj.join(4)
	assert_false(bj.can_join(5))
	assert_false(bj.join(5)["ok"])


func test_bet_limits_and_funds() -> void:
	assert_eq(bj.place_bet(1, {"amount": 5})["error"], &"below_min")
	assert_eq(bj.place_bet(1, {"amount": 201})["error"], &"above_max")
	assert_eq(bj.place_bet(9, {"amount": 10})["error"], &"not_seated")
	bj.limits_multiplier = 3.0
	assert_eq(bj.limits(), Vector2i(30, 600))
	assert_eq(bj.place_bet(1, {"amount": 20})["error"], &"below_min")


func test_betting_window_opens_on_first_bet_then_deals() -> void:
	assert_eq(bj.state, BlackjackLogic.State.IDLE)
	bj.place_bet(1, {"amount": 100})
	assert_eq(bj.state, BlackjackLogic.State.BETTING)
	assert_eq(fx.economy.balance(1), 900)
	_stack([10, 9, 6, 7, 8, 10])
	bj.tick(7.9)
	assert_eq(bj.state, BlackjackLogic.State.BETTING)
	bj.place_bet(2, {"amount": 50})
	bj.tick(0.2)
	assert_eq(bj.state, BlackjackLogic.State.ACTING)
	assert_eq(HandEval.total(bj.hands[1]["cards"]), 17)
	assert_eq(HandEval.total(bj.hands[2]["cards"]), 17)


func test_simultaneous_actions_and_dealer_stands_soft_17() -> void:
	bj.place_bet(1, {"amount": 100})
	bj.place_bet(2, {"amount": 100})
	# p1: 10,8 = 18 ; p2: 9,3 = 12 ; dealer: A,6 = soft 17 (stands)
	_stack([10, 9, 1, 8, 3, 6, 5])
	bj.tick(8.0)
	bj.player_action(2, &"hit")  # 12 + 5 = 17
	assert_eq(HandEval.total(bj.hands[2]["cards"]), 17)
	assert_eq(bj.state, BlackjackLogic.State.ACTING)
	bj.player_action(1, &"stand")
	bj.player_action(2, &"stand")
	assert_eq(bj.state, BlackjackLogic.State.PAYOUT)
	assert_eq(HandEval.total(bj.dealer), 17)
	assert_eq(bj.dealer.size(), 2, "dealer stands on soft 17")
	assert_eq(fx.economy.balance(1), 1100)  # 18 beats 17: +100
	assert_eq(fx.economy.balance(2), 1000)  # push


func test_blackjack_pays_3_to_2() -> void:
	bj.place_bet(1, {"amount": 100})
	_stack([1, 9, 13, 10, 9, 7])  # p1 A,K ; dealer 9,7 (not bj)
	bj.tick(8.0)
	assert_eq(fx.economy.balance(1), 1150 + 100 - 100)
	assert_true(bj.hands[1]["blackjack"])


func test_dealer_blackjack_beats_21_and_pushes_blackjack() -> void:
	bj.place_bet(1, {"amount": 100})
	bj.place_bet(2, {"amount": 100})
	_stack([1, 10, 1, 13, 9, 12])  # p1 A,K bj ; p2 10,9 ; dealer A,Q bj
	bj.tick(8.0)
	assert_eq(bj.state, BlackjackLogic.State.PAYOUT)
	assert_eq(fx.economy.balance(1), 1000)
	assert_eq(fx.economy.balance(2), 900)


func test_double_takes_second_stake_and_one_card() -> void:
	bj.place_bet(1, {"amount": 100})
	_stack([6, 10, 5, 7, 10])  # p1 6,5 = 11 ; dealer 10,7 ; double card 10 -> 21
	bj.tick(8.0)
	var r: Dictionary = bj.player_action(1, &"double")
	assert_true(r["ok"])
	assert_eq(bj.state, BlackjackLogic.State.PAYOUT)
	assert_eq(fx.economy.balance(1), 1200)  # staked 200, returned 400


func test_cannot_double_after_hit() -> void:
	bj.place_bet(1, {"amount": 100})
	_stack([2, 10, 3, 7, 2])
	bj.tick(8.0)
	bj.player_action(1, &"hit")
	assert_eq(bj.player_action(1, &"double")["error"], &"cannot_double")


func test_bust_loses_even_if_dealer_busts() -> void:
	bj.place_bet(1, {"amount": 100})
	bj.place_bet(2, {"amount": 100})
	# p1 10,6 ; p2 10,7 ; dealer 10,6 ; p1 hits K -> bust ; dealer draws 10 -> bust
	_stack([10, 10, 10, 6, 7, 6, 13, 10])
	bj.tick(8.0)
	bj.player_action(1, &"hit")
	bj.player_action(2, &"stand")
	assert_eq(fx.economy.balance(1), 900)
	# p2 wins with the Dealer Bust Bonus (1.07:1) -> 100 + 107
	assert_eq(fx.economy.balance(2), 1107)


func test_action_timeout_auto_stands() -> void:
	bj.place_bet(1, {"amount": 100})
	_stack([10, 10, 8, 7])  # p1 18 ; dealer 10,7 = 17
	bj.tick(8.0)
	assert_eq(bj.state, BlackjackLogic.State.ACTING)
	bj.tick(10.0)
	assert_eq(bj.state, BlackjackLogic.State.PAYOUT)
	assert_eq(fx.economy.balance(1), 1100)
	bj.tick(2.0)
	assert_eq(bj.state, BlackjackLogic.State.IDLE)
	assert_eq(bj.rounds_played, 1)


func test_auto_resolve_from_betting() -> void:
	bj.place_bet(1, {"amount": 100})
	bj.auto_resolve()
	assert_eq(bj.state, BlackjackLogic.State.IDLE)
	assert_true(bj.hands.is_empty())
	var settled: int = 0
	for ev: Dictionary in bj.drain_events():
		if ev["type"] == &"round_result":
			settled += 1
	assert_eq(settled, 1)


func test_leaving_mid_round_auto_stands() -> void:
	bj.place_bet(1, {"amount": 100})
	_stack([10, 10, 8, 7])
	bj.tick(8.0)
	bj.leave(1)
	assert_eq(bj.state, BlackjackLogic.State.PAYOUT)
	assert_eq(fx.economy.balance(1), 1100)


func test_hole_card_hidden_unless_peek() -> void:
	bj.place_bet(1, {"amount": 100})
	_stack([10, 10, 8, 7])
	bj.tick(8.0)
	assert_eq((bj.get_public_state()["dealer"] as Array).size(), 1)
	assert_eq(bj.get_private_state(1), {})
	var m := Modifier.new()
	m.id = &"hot_hands"
	m.game_id = &"blackjack"
	m.flags = {&"peek_dealer": true}
	fx.modifiers.add(1, m)
	assert_eq(bj.get_private_state(1)["hole_card"], bj.dealer[1])


func test_shoe_reshuffles_between_rounds_at_penetration() -> void:
	for i: int in 240:
		bj.shoe.draw()
	bj.place_bet(1, {"amount": 10})
	bj.auto_resolve()
	assert_eq(bj.shoe.remaining(), 312)


func test_basic_strategy_samples() -> void:
	assert_eq(BlackjackLogic.basic_strategy(_c([10, 6]), Card.make(10)), &"hit")
	assert_eq(BlackjackLogic.basic_strategy(_c([10, 6]), Card.make(6)), &"stand")
	assert_eq(BlackjackLogic.basic_strategy(_c([6, 5]), Card.make(1)), &"double")
	assert_eq(BlackjackLogic.basic_strategy(_c([1, 7]), Card.make(9)), &"hit")
	assert_eq(BlackjackLogic.basic_strategy(_c([1, 7]), Card.make(2)), &"stand")
	assert_eq(BlackjackLogic.basic_strategy(_c([10, 2]), Card.make(4)), &"stand")


# --- Split (M7) ---


func _results() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev: Dictionary in bj.drain_events():
		if ev["type"] == &"round_result":
			out.append(ev)
	return out


func test_split_takes_equal_stake_and_settles_each_hand() -> void:
	bj.place_bet(1, {"amount": 100})
	# p1 8,8 ; dealer 10,7 ; split cards 3 (hand 1) and 10 (hand 2) ; double card 10
	_stack([8, 10, 8, 7, 3, 10, 10])
	bj.tick(8.0)
	assert_true(bj.get_public_state()["hands"][1]["can_split"])
	assert_true(bj.player_action(1, &"split")["ok"])
	assert_eq(fx.economy.balance(1), 800)
	assert_eq(HandEval.total(bj.hands[1]["cards"]), 11)
	assert_eq(HandEval.total(bj.hands[1]["split"]["cards"]), 18)
	assert_eq(bj.player_action(1, &"split")["error"], &"cannot_split", "one split per round")
	# Double after split on the first hand (11 + 10 = 21), then the second hand stands on 18.
	assert_true(bj.player_action(1, &"double")["ok"])
	assert_eq(fx.economy.balance(1), 700)
	assert_eq(int(bj.hands[1]["active"]), 1)
	assert_eq(bj.state, BlackjackLogic.State.ACTING)
	bj.player_action(1, &"stand")
	assert_eq(bj.state, BlackjackLogic.State.PAYOUT)
	var res: Array[Dictionary] = _results()
	assert_eq(res.size(), 2, "one result per hand")
	assert_eq(int(res[0]["stake"]), 200)
	assert_eq(int(res[0]["returned"]), 400)
	assert_eq(int(res[1]["stake"]), 100)
	assert_eq(int(res[1]["returned"]), 200)
	assert_eq(fx.economy.balance(1), 1300)


func test_split_hands_can_win_and_lose_separately() -> void:
	bj.place_bet(1, {"amount": 100})
	# p1 9,9 ; dealer 10,8 ; split cards 10 (19, wins) and 5 (14) ; hand 2 hits 10 -> bust
	_stack([9, 10, 9, 8, 10, 5, 10])
	bj.tick(8.0)
	bj.player_action(1, &"split")
	bj.player_action(1, &"stand")
	bj.player_action(1, &"hit")
	assert_eq(bj.state, BlackjackLogic.State.PAYOUT)
	var res: Array[Dictionary] = _results()
	assert_eq(res.size(), 2)
	assert_eq(StringName(res[0]["details"]["outcome"]), &"win")
	assert_eq(StringName(res[1]["details"]["outcome"]), &"bust")
	assert_eq(fx.economy.balance(1), 1000)  # +100 -100


func test_split_only_first_two_card_pairs() -> void:
	bj.place_bet(1, {"amount": 100})
	_stack([8, 10, 9, 7, 2])
	bj.tick(8.0)
	assert_false(bj.get_public_state()["hands"][1]["can_split"])
	assert_eq(bj.player_action(1, &"split")["error"], &"cannot_split")
	assert_eq(fx.economy.balance(1), 900)
	assert_false(bj.hands[1].has("split"))


func test_split_tens_of_equal_value() -> void:
	bj.place_bet(1, {"amount": 100})
	_stack([13, 9, 10, 8, 5, 6])  # K,10 count as a pair
	bj.tick(8.0)
	assert_true(bj.player_action(1, &"split")["ok"])


func test_no_split_after_hit() -> void:
	bj.place_bet(1, {"amount": 100})
	_stack([2, 10, 2, 7, 3])
	bj.tick(8.0)
	bj.player_action(1, &"hit")
	assert_eq(bj.player_action(1, &"split")["error"], &"cannot_split")


func test_split_aces_get_one_card_each_and_no_blackjack_bonus() -> void:
	bj.place_bet(1, {"amount": 100})
	# p1 A,A ; dealer 10,8 = 18 ; split cards K (21, not a blackjack) and 5 (16)
	_stack([1, 10, 1, 8, 13, 5])
	bj.tick(8.0)
	assert_true(bj.player_action(1, &"split")["ok"])
	assert_true(bj.hands[1]["done"], "split aces stop after one card")
	assert_eq(bj.state, BlackjackLogic.State.PAYOUT)
	var res: Array[Dictionary] = _results()
	assert_eq(int(res[0]["returned"]), 200, "21 on a split ace pays 1:1")
	assert_eq(int(res[1]["returned"]), 0)
	assert_eq(fx.economy.balance(1), 1000)


func test_split_refused_without_money_for_the_second_stake() -> void:
	bj.place_bet(1, {"amount": 100})
	fx.economy.apply(1, -850, &"test")
	_stack([8, 10, 8, 7])
	bj.tick(8.0)
	assert_eq(bj.player_action(1, &"split")["error"], &"insufficient_funds")
	assert_eq(fx.economy.balance(1), 50)
	assert_false(bj.hands[1].has("split"))
	assert_eq((bj.hands[1]["cards"] as Array).size(), 2)


func test_split_public_state_shows_both_hands() -> void:
	bj.place_bet(1, {"amount": 100})
	_stack([7, 10, 7, 8, 4, 10])
	bj.tick(8.0)
	bj.player_action(1, &"split")
	var h: Dictionary = bj.get_public_state()["hands"][1]
	assert_eq(int(h["active"]), 0)
	assert_eq(h["cards"], [Card.make(7), Card.make(4)])
	assert_eq(h["split"]["cards"], [Card.make(7), Card.make(10)])
	assert_eq(int(h["split"]["total"]), 17)
	assert_eq(int(h["split"]["stake"]), 100)


func test_leaving_after_split_stands_both_hands() -> void:
	bj.place_bet(1, {"amount": 100})
	_stack([8, 10, 8, 9, 10, 10])  # 18 and 18 vs 19
	bj.tick(8.0)
	bj.player_action(1, &"split")
	bj.leave(1)
	assert_eq(bj.state, BlackjackLogic.State.PAYOUT)
	assert_eq(_results().size(), 2)
	assert_eq(fx.economy.balance(1), 800)


func test_split_basic_strategy_chart() -> void:
	assert_eq(BlackjackLogic.basic_strategy(_c([1, 1]), Card.make(10), true), &"split")
	assert_eq(BlackjackLogic.basic_strategy(_c([8, 8]), Card.make(1), true), &"split")
	assert_eq(BlackjackLogic.basic_strategy(_c([10, 13]), Card.make(6), true), &"stand")
	assert_eq(BlackjackLogic.basic_strategy(_c([5, 5]), Card.make(6), true), &"double")
	assert_eq(BlackjackLogic.basic_strategy(_c([9, 9]), Card.make(7), true), &"stand")
	assert_eq(BlackjackLogic.basic_strategy(_c([9, 9]), Card.make(8), true), &"split")
	assert_eq(BlackjackLogic.basic_strategy(_c([8, 8]), Card.make(1), false), &"hit")


## Many random rounds with splits: every round's balance change equals the sum of its results'
## nets, and the results' stakes equal everything that was taken.
func test_split_money_conservation_over_many_rounds() -> void:
	fx.economy.apply(1, 1_000_000, &"test")
	var splits: int = 0
	for i: int in 3000:
		var before: int = fx.economy.balance(1)
		fx.economy.drain_events()
		bj.place_bet(1, {"amount": 100})
		bj.tick(100.0)
		while bj.state == BlackjackLogic.State.ACTING and not bj.hands[1]["done"]:
			var h: Dictionary = bj.hands[1]
			var cur: Dictionary = BlackjackLogic.active_hand(h)
			var a: StringName = BlackjackLogic.basic_strategy(cur["cards"], bj.dealer[0], bj.can_split(h))
			bj.player_action(1, a)
			if a == &"split":
				splits += 1
		bj.auto_resolve()
		var taken: int = 0
		for m: Dictionary in fx.economy.drain_events():
			if m["reason"] == &"bet_blackjack":
				taken -= int(m["amount"])
		var staked: int = 0
		var net: int = 0
		for r: Dictionary in _results():
			staked += int(r["stake"])
			net += int(r["net"])
		if staked != taken or fx.economy.balance(1) - before != net:
			fail_test("round %d: staked %d taken %d net %d change %d" % [i, staked, taken, net, fx.economy.balance(1) - before])
			return
	assert_gt(splits, 20, "basic strategy split some pairs")


## Luck still rerolls each card dealt to a split hand.
func test_luck_rerolls_cards_dealt_to_split_hands() -> void:
	fx.give_luck(1, 3, &"blackjack")
	fx.economy.apply(1, 1_000_000, &"test")
	var flourishes_on_split: int = 0
	for i: int in 400:
		bj.place_bet(1, {"amount": 100})
		# Force a pair of 8s against a 10 so every round splits.
		_stack([8, 10, 8, 7])
		bj.tick(100.0)
		bj.drain_events()
		if bj.state == BlackjackLogic.State.ACTING:
			bj.player_action(1, &"split")
			for ev: Dictionary in bj.drain_events():
				if ev["type"] == &"luck_flourish":
					flourishes_on_split += 1
		bj.auto_resolve()
		bj.drain_events()
	assert_gt(flourishes_on_split, 0)
