extends GutTest
## Baccarat (Punto Banco): card values, totals, the drawing tableau, bets and limits, the shared
## round, pushes, the commission, refunds and the public state that only shows turned cards.

var fx: TableFixture
var bc: BaccaratLogic


func before_each() -> void:
	fx = TableFixture.new(1, [1, 2], 1000)
	bc = fx.make(BaccaratLogic.new(), &"bc1") as BaccaratLogic
	bc.join(1)


## Card of a rank (1 = ace … 13 = king).
static func c(rank: int, suit: int = 0) -> int:
	return Card.make(rank, suit)


## Deals the given cards in order (P1 B1 P2 B2, then third cards) as the next hand.
func _stack(cards: Array[int]) -> void:
	bc.shoe.stack_top(cards)


## Runs the round from betting to the result.
func _play_round() -> void:
	bc.tick(bc.timer + 0.01)  # betting closes
	assert_eq(bc.state, BaccaratLogic.State.DEALING)
	for i: int in 20:
		if bc.state != BaccaratLogic.State.DEALING:
			break
		bc.tick(1.0)
	assert_eq(bc.state, BaccaratLogic.State.RESULT)


func test_card_values_and_totals() -> void:
	assert_eq(BaccaratLogic.card_value(c(1)), 1)
	assert_eq(BaccaratLogic.card_value(c(9)), 9)
	for r: int in [10, 11, 12, 13]:
		assert_eq(BaccaratLogic.card_value(c(r)), 0)
	assert_eq(BaccaratLogic.hand_total([c(7), c(8)]), 5)
	assert_eq(BaccaratLogic.hand_total([c(13), c(9)]), 9)
	assert_eq(BaccaratLogic.hand_total([c(5), c(5), c(10)]), 0)
	assert_true(BaccaratLogic.is_pair([c(4, 0), c(4, 2)]))
	assert_false(BaccaratLogic.is_pair([c(10), c(13)]), "ten and king are both 0 but not a pair")


func test_player_tableau() -> void:
	for t: int in 10:
		assert_eq(BaccaratLogic.player_draws(t), t <= 5, "player on %d" % t)


func test_banker_tableau() -> void:
	# Player stood: the banker draws on 0-5.
	for t: int in 8:
		assert_eq(BaccaratLogic.banker_draws(t, -1), t <= 5, "banker %d, player stood" % t)
	# The standard table: banker total → the player's third cards it draws on.
	var draws: Dictionary = {
		0: range(10), 1: range(10), 2: range(10), 3: [0, 1, 2, 3, 4, 5, 6, 7, 9],
		4: [2, 3, 4, 5, 6, 7], 5: [4, 5, 6, 7], 6: [6, 7], 7: [],
	}
	for b: int in draws:
		for third: int in 10:
			assert_eq(BaccaratLogic.banker_draws(b, third), third in draws[b], "banker %d vs player's third %d" % [b, third])


func test_natural_stands_both_hands() -> void:
	_stack([c(9), c(2), c(10), c(3)])  # player 9 natural, banker 5
	bc.place_bet(1, {"type": &"player", "amount": 100})
	_play_round()
	assert_eq(bc.player_cards.size(), 2)
	assert_eq(bc.banker_cards.size(), 2)
	assert_eq(bc.winner, BaccaratLogic.PLAYER)


func test_player_draws_and_banker_follows_tableau() -> void:
	# Player 2+3 = 5 draws a 4 → 9; banker 10+3 = 3 draws (third card not an 8): a 6 → 9: tie.
	_stack([c(2), c(10), c(3), c(3), c(4), c(6)])
	bc.place_bet(1, {"type": &"tie", "amount": 10})
	_play_round()
	assert_eq(bc.player_cards.size(), 3)
	assert_eq(bc.banker_cards.size(), 3)
	assert_eq(bc.winner, BaccaratLogic.TIE)


func test_banker_3_stands_on_players_eight() -> void:
	_stack([c(1), c(10), c(4), c(3), c(8)])  # player 5 draws an 8 → 3; banker 3 stands on an 8
	bc.place_bet(1, {"type": &"banker", "amount": 10})
	_play_round()
	assert_eq(bc.player_cards.size(), 3)
	assert_eq(bc.banker_cards.size(), 2)
	assert_eq(bc.winner, BaccaratLogic.TIE)


func test_limits_and_validation() -> void:
	assert_eq(bc.place_bet(1, {"type": &"player", "amount": 5})["error"], &"below_min")
	assert_eq(bc.place_bet(1, {"type": &"dragon", "amount": 10})["error"], &"invalid_bet_type")
	assert_eq(bc.place_bet(2, {"type": &"player", "amount": 10})["error"], &"not_seated")
	assert_true(bc.place_bet(1, {"type": &"player", "amount": 200})["ok"])
	assert_eq(bc.place_bet(1, {"type": &"banker", "amount": 101})["error"], &"above_max")
	assert_true(bc.place_bet(1, {"type": &"banker", "amount": 100})["ok"])
	assert_eq(fx.economy.balance(1), 700)


func test_bets_close_when_the_cards_come() -> void:
	bc.place_bet(1, {"type": &"player", "amount": 10})
	bc.tick(bc.timer + 0.01)
	assert_eq(bc.place_bet(1, {"type": &"player", "amount": 10})["error"], &"betting_closed")
	assert_eq(bc.player_action(1, &"clear_bets")["error"], &"betting_closed")


func test_clear_bets_gives_the_money_back() -> void:
	bc.place_bet(1, {"type": &"player", "amount": 50})
	bc.place_bet(1, {"type": &"tie", "amount": 10})
	assert_true(bc.player_action(1, &"clear_bets")["ok"])
	assert_eq(fx.economy.balance(1), 1000)
	assert_true(bc.bets.is_empty())


func test_banker_win_pays_less_commission_plus_favour() -> void:
	fx.balance.baccarat_banker_favour = 0.0
	_stack([c(2), c(9), c(10), c(10)])  # player 2 vs banker 9 (natural): no draws
	bc.place_bet(1, {"type": &"banker", "amount": 100})
	_play_round()
	assert_eq(bc.winner, BaccaratLogic.BANKER)
	assert_eq(fx.economy.balance(1), 1000 + 95, "1:1 less 5%")


func test_tie_pushes_player_and_banker_and_pays_tie() -> void:
	fx.balance.baccarat_tie_favour = 0.0
	_stack([c(4), c(4, 1), c(4, 2), c(4, 3)])  # 8 v 8, both naturals and both pairs
	fx.balance.baccarat_pair_favour = 0.0
	bc.place_bet(1, {"type": &"player", "amount": 100})
	bc.place_bet(1, {"type": &"banker", "amount": 100})
	bc.place_bet(1, {"type": &"tie", "amount": 10})
	bc.place_bet(1, {"type": &"player_pair", "amount": 10})
	bc.place_bet(1, {"type": &"banker_pair", "amount": 10})
	_play_round()
	assert_eq(bc.winner, BaccaratLogic.TIE)
	# Player and Banker back (200), tie 10 × 10 = 100, each pair 10 × 12 = 120.
	assert_eq(fx.economy.balance(1), 1000 - 230 + 200 + 100 + 240)
	assert_eq(int(bc.get_public_state()["results"][1]), 310)


func test_losing_bets_lose() -> void:
	fx.balance.baccarat_player_favour = 0.0
	_stack([c(9), c(2), c(10), c(3)])  # player 9 v banker 5
	bc.place_bet(1, {"type": &"banker", "amount": 50})
	bc.place_bet(1, {"type": &"player", "amount": 50})
	bc.place_bet(1, {"type": &"banker_pair", "amount": 10})
	_play_round()
	assert_eq(fx.economy.balance(1), 1000 - 110 + 100)


func test_public_state_shows_only_turned_cards() -> void:
	_stack([c(9), c(2), c(10), c(3)])
	bc.place_bet(1, {"type": &"player", "amount": 10})
	bc.tick(bc.timer + 0.01)
	var pub: Dictionary = bc.get_public_state()
	assert_eq((pub["player_cards"] as Array).size(), 0, "no card up yet")
	bc.tick(fx.balance.baccarat_card_time)
	pub = bc.get_public_state()
	assert_eq((pub["player_cards"] as Array).size(), 1)
	assert_eq((pub["banker_cards"] as Array).size(), 0)
	assert_eq(int(pub["player_total"]), 9)
	assert_eq(StringName(pub["winner"]), &"", "no winner while dealing")
	assert_true(bc.has_stake(1))


func test_two_players_share_the_hand() -> void:
	bc.join(2)
	_stack([c(9), c(2), c(10), c(3)])
	bc.place_bet(1, {"type": &"player", "amount": 10})
	bc.place_bet(2, {"type": &"banker", "amount": 10})
	_play_round()
	var res: Dictionary = bc.get_public_state()["results"]
	assert_gt(int(res[1]), 0)
	assert_eq(int(res[2]), -10)
	assert_eq(bc.history, [BaccaratLogic.PLAYER] as Array[StringName])


func test_refund_all_mid_deal() -> void:
	bc.place_bet(1, {"type": &"player", "amount": 40})
	bc.tick(bc.timer + 0.01)
	bc.refund_all()
	assert_eq(fx.economy.balance(1), 1000)
	assert_eq(bc.state, BaccaratLogic.State.IDLE)
	assert_true(bc.player_cards.is_empty())


func test_auto_resolve_settles_open_bets() -> void:
	bc.place_bet(1, {"type": &"player", "amount": 40})
	bc.auto_resolve()
	assert_eq(bc.state, BaccaratLogic.State.RESULT)
	assert_false(bc.has_stake(1))


func test_empty_window_reopens_without_dealing() -> void:
	bc.tick(bc.timer + 0.01)
	assert_eq(bc.state, BaccaratLogic.State.BETTING)
	assert_true(bc.order.is_empty())


func test_all_in_limits_follow_the_round_total() -> void:
	bc.place_bet(1, {"type": &"player", "amount": 250})
	assert_eq(bc.bet_limits(1, {"type": &"tie", "amount": 10}), Vector2i(10, 50))
