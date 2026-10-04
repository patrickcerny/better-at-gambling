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
	# p2 wins with the Dealer Bust Bonus 1.1:1 -> 100 + 110
	assert_eq(fx.economy.balance(2), 1110)


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
