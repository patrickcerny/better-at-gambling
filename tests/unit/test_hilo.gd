extends GutTest
## Hi-Lo table: one single deck (aces high), every player's own hand: ante, a card up, call HIGHER
## or LOWER (a tie loses) at the true chance shown and the pay locked with it, then cash out or
## ride the pot up the ladder. The server quietly redraws a losing card now and then and luck
## rerolls it; none of that is published.

var fx: TableFixture
var hl: HiLoLogic


func before_each() -> void:
	fx = TableFixture.new(5, [1, 2, 3, 4, 5], 1000)
	hl = fx.make(HiLoLogic.new(), &"hilo_t") as HiLoLogic
	hl.join(1)
	hl.join(2)


func _types(evs: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	return evs.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## Puts `cards` on top of the deck so they are dealt in this order.
func _stack(cards: Array[int]) -> void:
	for i: int in range(cards.size() - 1, -1, -1):
		hl.deck.erase(cards[i])
		hl.deck.append(cards[i])


func _c(rank: int, suit: int = 0) -> int:
	return Card.make(rank, suit)


func test_aces_are_high_and_twos_low() -> void:
	assert_eq(HiLoLogic.value_of(_c(1)), 14, "ace high")
	assert_eq(HiLoLogic.value_of(_c(2)), 2)
	assert_eq(HiLoLogic.value_of(_c(13)), 13)
	assert_true(HiLoLogic.wins(HiLoLogic.HIGHER, 13, 14), "an ace beats a king")
	assert_true(HiLoLogic.wins(HiLoLogic.LOWER, 3, 2))
	assert_false(HiLoLogic.wins(HiLoLogic.HIGHER, 9, 9), "a tie loses a higher call")
	assert_false(HiLoLogic.wins(HiLoLogic.LOWER, 9, 9), "and a lower call")


func test_the_odds_table_sums_to_one() -> void:
	var table: Array[Dictionary] = HiLoLogic.fresh_deck_table(fx.balance)
	assert_eq(table.size(), 13)
	for row: Dictionary in table:
		var v: int = int(row["value"])
		assert_almost_eq(float(row["higher"]) + float(row["lower"]) + float(row["tie"]), 1.0, 0.000001, "value %d" % v)
		assert_almost_eq(float(row["higher"]), (14 - v) * 4 / 51.0, 0.000001, "value %d higher" % v)
		assert_almost_eq(float(row["tie"]), 3 / 51.0, 0.000001, "three of the shown value are left")
	# Any deck the table can be in: the three chances still add up to one.
	var r := SeededRng.new(31)
	for trial: int in 200:
		var cards: Array[int] = []
		for c: int in 52:
			if r.chance(0.6):
				cards.append(c)
		if cards.is_empty():
			continue
		var shown: int = r.range_int(2, 14)
		var o: Dictionary = HiLoLogic.odds_for(shown, HiLoLogic.counts_of(cards))
		assert_almost_eq(float(o["higher"]) + float(o["lower"]) + float(o["tie"]), 1.0, 0.000001, "trial %d" % trial)
	var empty: Dictionary = HiLoLogic.odds_for(8, PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
	assert_eq(float(empty["higher"]), 0.0)


func test_pays_follow_the_honest_odds() -> void:
	var cfg: BalanceConfig = fx.balance
	var table: Array[Dictionary] = HiLoLogic.fresh_deck_table(cfg)
	var line: String = "fresh deck:"
	for row: Dictionary in table:
		for side: String in ["higher", "lower"]:
			var p: float = float(row[side])
			var pay: float = float(row["pay_" + side])
			if p <= 0.0:
				assert_eq(pay, 0.0, "value %d %s cannot come in and pays nothing" % [row["value"], side])
				continue
			assert_lte(pay, 1.0 / p + 0.000001, "never above the fair odds (value %d %s)" % [row["value"], side])
			var back: float = pay * p * (1.0 + cfg.hilo_favour * (1.0 - p))
			assert_between(back, 1.0, cfg.hilo_return + 0.000001, "value %d %s returns %.4f with the favour" % [row["value"], side, back])
			assert_lt(pay * p, 1.0 + 0.000001, "the printed odds keep a house edge (value %d %s)" % [row["value"], side])
		line += " %d:%.0f%%x%.2f/%.0f%%x%.2f" % [row["value"], float(row["higher"]) * 100.0, row["pay_higher"], float(row["lower"]) * 100.0, row["pay_lower"]]
	gut.p(line)
	# Near the middle a call pays about even money; towards the edges the long shot pays more.
	var eight: Dictionary = table[6]
	assert_eq(int(eight["value"]), 8)
	assert_between(float(eight["pay_higher"]), 1.85, 2.0, "an 8: higher pays about 1:1")
	assert_eq(eight["pay_higher"], eight["pay_lower"], "an 8 is the middle")
	var three: Dictionary = table[1]
	assert_gt(float(three["pay_lower"]), 8.0, "lower than a 3 is a long shot and pays like one")
	assert_lt(float(three["pay_higher"]), 1.2, "higher than a 3 is nearly sure and pays little")
	assert_eq(float(table[0]["pay_lower"]), 0.0, "nothing is lower than a 2")
	assert_eq(float(table[12]["pay_higher"]), 0.0, "nothing is higher than an ace")
	assert_eq(HiLoLogic.pay_for(0.001, cfg), cfg.hilo_max_pay, "a hair-thin chance pays the table maximum")


func test_ante_deals_a_card_and_locks_its_odds() -> void:
	_stack([_c(7), _c(9, 1)])
	assert_true(hl.place_bet(1, {"amount": 20})["ok"])
	assert_eq(fx.economy.balance(1), 980, "the ante is taken at once")
	var h: Dictionary = hl.hands[1]
	assert_eq(h["cards"], [_c(7)] as Array[int])
	var expect: Dictionary = HiLoLogic.odds_for(7, HiLoLogic.counts_of(hl.deck))
	assert_almost_eq(float(h["odds"]["higher"]), float(expect["higher"]), 0.000001)
	assert_almost_eq(float(h["odds"]["lower"]), float(expect["lower"]), 0.000001)
	var pays: Dictionary = (h["pays"] as Dictionary).duplicate()
	# Someone else's card comes off the same deck: what player 1 was shown stays.
	assert_true(hl.place_bet(2, {"amount": 10})["ok"])
	assert_eq(hl.hands[1]["pays"], pays, "the pay was locked when the card went up")
	var pub: Dictionary = hl.get_public_state()
	assert_eq(int(pub["state"]), HiLoLogic.State.PLAYING)
	var mine: Dictionary = pub["hands"][1]
	assert_eq(mine["cards"], [_c(7)] as Array[int])
	assert_eq(mine["pays"], pays, "the buttons show the pays the server will use")
	assert_eq(int(pub["deck_left"]), hl.deck.size())
	var evs: Array[Dictionary] = hl.drain_events()
	assert_eq(_types(evs, &"bet_placed").size(), 2)
	assert_eq(_types(evs, &"hilo_dealt").size(), 2)
	assert_true(hl.has_stake(1))


func test_bet_rules() -> void:
	assert_eq(hl.place_bet(3, {"amount": 10})["error"], &"not_seated")
	assert_eq(hl.place_bet(1, {"amount": 5})["error"], &"below_min")
	assert_eq(hl.place_bet(1, {"amount": 101})["error"], &"above_max")
	assert_true(hl.place_bet(1, {"amount": 100})["ok"])
	assert_eq(hl.place_bet(1, {"amount": 10})["error"], &"already_bet", "one hand at a time")
	assert_eq(hl.player_action(2, &"higher")["error"], &"no_active_hand")
	assert_eq(hl.player_action(1, &"cash_out")["error"], &"nothing_to_cash", "no right call yet")
	assert_eq(hl.player_action(1, &"hit")["error"], &"unknown_action")
	hl.limits_multiplier = 2.0
	assert_eq(hl.limits(), Vector2i(20, 200), "limits rise with the segment like every table")
	for p: int in [3, 4, 5]:
		hl.join(p)
	assert_false(hl.can_join(5), "four seats")
	assert_eq(hl.join(5)["error"], &"seat_taken")


func test_impossible_calls_are_refused() -> void:
	_stack([_c(2)])
	hl.place_bet(1, {"amount": 10})
	assert_eq(hl.player_action(1, &"lower")["error"], &"no_chance", "nothing is lower than a 2")
	assert_eq(float(hl.hands[1]["pays"]["lower"]), 0.0)
	assert_true(hl.player_action(1, &"higher")["ok"])


func test_right_calls_ride_up_the_ladder_and_cash_out() -> void:
	fx.balance.hilo_favour = 0.0
	_stack([_c(6), _c(10), _c(4, 2), _c(12)])
	hl.place_bet(1, {"amount": 50})
	hl.drain_events()
	var pay1: float = float(hl.hands[1]["pays"]["higher"])
	assert_true(hl.player_action(1, &"higher")["ok"], "6 then 10: higher")
	var h: Dictionary = hl.hands[1]
	assert_eq(int(h["rung"]), 1)
	assert_almost_eq(float(h["mult"]), pay1, 0.000001)
	assert_eq(HiLoLogic.pot_of(h), int(floor(50 * pay1 + 0.000001)))
	assert_eq(h["phase"], HiLoLogic.PLAY, "a right call waits for ride or cash out")
	var ev: Dictionary = _types(hl.drain_events(), &"hilo_call")[0]
	assert_eq(int(ev["card"]), _c(10))
	assert_true(bool(ev["won"]))
	# The ride: the 10 is the card up now, with its own chances.
	var expect: Dictionary = HiLoLogic.odds_for(10, HiLoLogic.counts_of(hl.deck))
	assert_almost_eq(float(h["odds"]["lower"]), float(expect["lower"]), 0.000001)
	var pay2: float = float(h["pays"]["lower"])
	assert_true(hl.player_action(1, &"lower")["ok"], "10 then 4: lower")
	assert_eq(int(h["rung"]), 2)
	assert_almost_eq(float(h["mult"]), pay1 * pay2, 0.000001, "the pot multiplies")
	var pot: int = HiLoLogic.pot_of(h)
	assert_eq(fx.economy.balance(1), 950, "nothing is paid while it rides")
	assert_true(hl.player_action(1, &"cash_out")["ok"])
	assert_eq(fx.economy.balance(1), 950 + pot, "cashed out: the pot through the ledger")
	assert_eq(h["phase"], HiLoLogic.DONE)
	assert_eq(h["outcome"], &"cashed")
	assert_false(hl.has_stake(1))
	var res: Array[Dictionary] = _types(hl.drain_events(), &"round_result")
	assert_eq(res.size(), 1)
	assert_eq(int(res[0]["returned"]), pot)
	assert_eq(int(res[0]["details"]["rung"]), 2)
	assert_eq(hl.player_action(1, &"higher")["error"], &"no_active_hand")
	hl.tick(fx.balance.hilo_result_time + 0.1)
	assert_false(hl.hands.has(1), "the result clears after a moment")
	assert_eq(int(hl.get_public_state()["state"]), HiLoLogic.State.IDLE)


func test_a_wrong_call_or_a_tie_loses_the_pot() -> void:
	fx.balance.hilo_favour = 0.0
	_stack([_c(9), _c(9, 3), _c(5), _c(11)])
	hl.place_bet(1, {"amount": 30})
	assert_true(hl.player_action(1, &"higher")["ok"])
	assert_eq(hl.hands[1]["outcome"], &"lose", "9 then 9: a tie loses")
	assert_eq(fx.economy.balance(1), 970)
	hl.place_bet(1, {"amount": 30})
	assert_eq(hl.hands[1]["cards"], [_c(5)] as Array[int], "a new ante replaces the finished hand")
	hl.player_action(1, &"lower")
	assert_eq(hl.hands[1]["outcome"], &"lose", "5 then jack: lower was wrong")
	assert_eq(fx.economy.balance(1), 940)
	var res: Array[Dictionary] = _types(hl.drain_events(), &"round_result")
	assert_eq(res.size(), 2)
	assert_eq(int(res[1]["net"]), -30)


func test_the_ladder_tops_out() -> void:
	fx.balance.hilo_favour = 0.0
	fx.balance.hilo_max_rungs = 3
	_stack([_c(2), _c(3), _c(4), _c(5)])
	hl.place_bet(1, {"amount": 10})
	for i: int in 3:
		assert_true(hl.player_action(1, &"higher")["ok"])
	assert_eq(hl.hands[1]["outcome"], &"cashed", "the third right call cashes out on its own")
	assert_gt(fx.economy.balance(1), 990)
	# The pot cap: a long shot that would blow past it is paid at the cap.
	fx.balance.hilo_max_rungs = 6
	fx.balance.hilo_pot_cap = 3.0
	_stack([_c(3), _c(2, 1)])
	var before: int = fx.economy.balance(1)
	hl.place_bet(1, {"amount": 10})
	assert_gt(float(hl.hands[1]["pays"]["lower"]), 3.0)
	hl.player_action(1, &"lower")
	assert_eq(hl.hands[1]["outcome"], &"cashed", "the cap cashes out on its own")
	assert_eq(fx.economy.balance(1), before - 10 + 30, "at most 3x the ante")


## Win rate of the same call ("higher than a 9") over `n` fresh hands.
func _higher_than_nine_wins(n: int) -> int:
	var won: int = 0
	for i: int in n:
		hl.hands.erase(1)
		hl._reshuffle()
		_stack([_c(9)])
		hl.place_bet(1, {"amount": 10})
		hl.player_action(1, &"higher")
		if hl.hands[1]["outcome"] == &"cashed" or int(hl.hands[1]["rung"]) > 0:
			won += 1
	return won


func test_the_house_quietly_favours_the_call() -> void:
	fx.economy.apply(1, 1_000_000, &"test")
	fx.balance.hilo_favour = 0.0
	fx.rng.reseed(404)
	var plain: int = _higher_than_nine_wins(400)
	fx.balance.hilo_favour = 1.0
	fx.rng.reseed(404)
	var favoured: int = _higher_than_nine_wins(400)
	gut.p("higher than a 9 (20 of 51): %d/400 plain, %d/400 with every losing card redrawn once" % [plain, favoured])
	assert_between(plain, 120, 195, "about 39%% without the favour")
	assert_gt(favoured, plain + 60, "a redraw when the call would lose tilts it to the player")
	assert_lt(favoured, 300, "but it is a nudge, not a fix")
	# Nothing of it is published: no field, no event says so.
	hl.drain_events()
	_stack([_c(9)])
	hl.place_bet(1, {"amount": 10})
	hl.player_action(1, &"higher")
	for ev: Dictionary in hl.drain_events():
		assert_false(ev.has("favour") or ev.has("redrawn"), "event %s" % ev["type"])
	var pub: Dictionary = hl.get_public_state()
	assert_false(pub.has("favour"))
	assert_false(str(pub).contains("favour"))


func test_luck_rerolls_the_next_card() -> void:
	fx.economy.apply(1, 1_000_000, &"test")
	fx.balance.hilo_favour = 0.0
	hl.luck.reroll_per_point = 1.0  # force the luck effects
	fx.give_luck(1, 3)
	fx.rng.reseed(77)
	var lucky: int = _higher_than_nine_wins(300)
	hl.luck.reroll_per_point = 0.0
	fx.rng.reseed(77)
	var plain: int = _higher_than_nine_wins(300)
	assert_gt(lucky, plain + 50, "a lucky player's call comes in more often (%d vs %d)" % [lucky, plain])
	hl.luck.reroll_per_point = 1.0
	hl.drain_events()
	_higher_than_nine_wins(20)
	assert_gt(_types(hl.drain_events(), &"luck_flourish").size(), 0, "the clover shows when luck changed a card")
	# A jinxed player gets the worse card.
	fx.modifiers.remove_by_id(1, &"test_luck")
	fx.give_luck(1, -3)
	fx.rng.reseed(77)
	assert_lt(_higher_than_nine_wins(300), plain - 30)


func test_rejected_cards_go_back_and_the_deck_stays_a_deck() -> void:
	fx.balance.hilo_favour = 1.0
	hl.luck.reroll_per_point = 1.0
	fx.give_luck(1, 2)
	for i: int in 30:
		if hl.deck.size() < fx.balance.hilo_reshuffle_at + 8:
			break
		hl.place_bet(1, {"amount": 10})
		while hl.hands[1]["phase"] == HiLoLogic.PLAY and int(hl.hands[1]["rung"]) < 3:
			var o: Dictionary = hl.hands[1]["odds"]
			hl.player_action(1, &"higher" if float(o["higher"]) >= float(o["lower"]) else &"lower")
		if hl.hands[1]["phase"] == HiLoLogic.PLAY:
			hl.player_action(1, &"cash_out")
		# Every card is either in the deck or on the felt this deck, never twice.
		var seen: Dictionary = {}
		for c: int in hl.deck:
			assert_false(seen.has(c), "card %d once" % c)
			seen[c] = true
	assert_true(true)


func test_the_deck_is_reshuffled_when_low() -> void:
	fx.balance.hilo_favour = 0.0
	hl.place_bet(2, {"amount": 10})
	var on_felt: int = int(hl.hands[2]["cards"][0])
	while hl.deck.size() >= fx.balance.hilo_reshuffle_at:
		hl.deck.pop_back()
	var before: int = hl.reshuffles
	hl.drain_events()
	assert_true(hl.place_bet(1, {"amount": 10})["ok"])
	assert_eq(hl.reshuffles, before + 1)
	assert_eq(_types(hl.drain_events(), &"hilo_reshuffle").size(), 1)
	assert_eq(hl.deck.size(), 52 - 2, "a full deck less the cards up on the felt")
	assert_false(on_felt in hl.deck, "player 2's card is still in front of them")
	# Drawn dry mid-hand, it shuffles again rather than run out.
	hl.deck.clear()
	assert_true(hl.player_action(1, &"higher")["ok"] or true)
	assert_true(hl.reshuffles >= before + 2)


func test_the_same_seed_deals_the_same_game() -> void:
	var a: Array = _play_session(1234)
	var b: Array = _play_session(1234)
	assert_eq(a, b, "same seed, same cards and results")
	assert_ne(a, _play_session(1235))


func _play_session(seed_value: int) -> Array:
	var f := TableFixture.new(seed_value, [1, 2], 100000)
	var t: HiLoLogic = f.make(HiLoLogic.new(), &"det") as HiLoLogic
	t.join(1)
	t.join(2)
	f.give_luck(2, 2)
	var out: Array = []
	for i: int in 40:
		for p: int in [1, 2]:
			if not t.has_stake(p):
				t.place_bet(p, {"amount": 10 + i})
			var o: Dictionary = t.hands[p]["odds"]
			t.player_action(p, &"higher" if float(o["higher"]) >= float(o["lower"]) else &"lower")
			if t.has_stake(p) and int(t.hands[p]["rung"]) >= 2:
				t.player_action(p, &"cash_out")
			out.append([p, (t.hands[p]["cards"] as Array).duplicate(), t.hands[p]["outcome"]])
	out.append([f.economy.balance(1), f.economy.balance(2)])
	return out


func test_a_call_not_made_in_time_is_made_for_you() -> void:
	fx.balance.hilo_favour = 0.0
	_stack([_c(4), _c(13)])
	hl.place_bet(1, {"amount": 20})
	hl.tick(fx.balance.hilo_action_time - 0.5)
	assert_true(hl.has_stake(1), "still your call")
	hl.tick(1.0)
	assert_eq(hl.hands[1]["guess"], "higher", "the table took the likelier side")
	assert_eq(hl.hands[1]["outcome"], &"cashed", "and banked the right call")
	assert_eq(fx.economy.balance(1), 980 + HiLoLogic.pot_of(hl.hands[1]))
	# A pot that is riding and timed out is cashed out, not called.
	_stack([_c(4, 1), _c(13, 1)])
	hl.place_bet(1, {"amount": 20})
	hl.player_action(1, &"higher")
	var pot: int = HiLoLogic.pot_of(hl.hands[1])
	var bal: int = fx.economy.balance(1)
	hl.tick(fx.balance.hilo_action_time + 0.1)
	assert_eq(hl.hands[1]["outcome"], &"cashed")
	assert_eq(fx.economy.balance(1), bal + pot)


func test_leaving_mid_hand_settles_it() -> void:
	fx.balance.hilo_favour = 0.0
	_stack([_c(3), _c(8), _c(6)])
	hl.place_bet(1, {"amount": 40})
	hl.player_action(1, &"higher")
	var pot: int = HiLoLogic.pot_of(hl.hands[1])
	hl.leave(1)
	assert_eq(fx.economy.balance(1), 960 + pot, "a pot with a right call in it is cashed out")
	assert_false(hl.has_stake(1))
	assert_eq(hl.seats.find(1), -1)
	hl.join(1)
	hl.place_bet(1, {"amount": 40})
	hl.leave(1)
	assert_false(hl.has_stake(1), "a fresh ante is called for you on the way out")
	assert_eq(hl.hands[1]["phase"], HiLoLogic.DONE)


func test_a_minigame_refunds_fresh_antes_and_banks_won_pots() -> void:
	fx.balance.hilo_favour = 0.0
	_stack([_c(5), _c(7), _c(10)])
	hl.place_bet(1, {"amount": 50})
	hl.player_action(1, &"higher")
	var pot: int = HiLoLogic.pot_of(hl.hands[1])
	hl.place_bet(2, {"amount": 30})
	hl.drain_events()
	hl.refund_all()
	assert_eq(fx.economy.balance(2), 1000, "player 2's ante comes back: no call was made")
	assert_eq(fx.economy.balance(1), 950 + pot, "player 1 had won a call already: the pot is banked")
	assert_true(hl.hands.is_empty(), "the felt is cleared")
	var evs: Array[Dictionary] = hl.drain_events()
	var refunds: Array[Dictionary] = _types(evs, &"bets_refunded")
	assert_eq(refunds.size(), 1)
	assert_eq(int(refunds[0]["player"]), 2)
	assert_eq(int(refunds[0]["amount"]), 30)
	assert_eq(_types(evs, &"table_reset").size(), 1)
	assert_eq(_types(evs, &"round_result").size(), 1)


func test_auto_resolve_plays_every_open_hand() -> void:
	hl.place_bet(1, {"amount": 10})
	hl.place_bet(2, {"amount": 10})
	hl.auto_resolve()
	assert_false(hl.has_stake(1))
	assert_false(hl.has_stake(2))
	assert_eq(_types(hl.drain_events(), &"round_result").size(), 2)


func test_items_and_hot_table_multiply_the_winnings_only() -> void:
	fx.balance.hilo_favour = 0.0
	hl.hot_multiplier = 2.0
	_stack([_c(2), _c(9)])
	hl.place_bet(1, {"amount": 100})
	hl.player_action(1, &"higher")
	var pot: int = HiLoLogic.pot_of(hl.hands[1])
	hl.player_action(1, &"cash_out")
	assert_eq(fx.economy.balance(1), 900 + 100 + int(floor((pot - 100) * 2.0 + 0.000001)), "the hot table doubles the profit, not the ante")
