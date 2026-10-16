extends GutTest
## Scratch-card kiosk (Patrick: "scratch cards"): the server builds a card that shows exactly the
## outcome it drew, pays by the printed prize table only, quietly redraws a blank once with the
## house rule's `scratch_favour` chance and lets luck reroll the card, never tells anyone, and the
## whole thing is a pure function of the seed.

const S := ScratchLogic.Sym

var fx: TableFixture
var sc: ScratchLogic


func before_each() -> void:
	fx = TableFixture.new(3, [1, 2], 1000)
	sc = fx.make(ScratchLogic.new(), &"scratch_1") as ScratchLogic
	sc.join(1)


func _types(evs: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	return evs.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _card(cells: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(cells)
	return out


func test_every_built_card_shows_exactly_its_outcome() -> void:
	var r := SeededRng.new(77)
	var cfg: BalanceConfig = fx.balance
	var odds_size: int = cfg.scratch_odds(0).size()
	var line_seen: Dictionary = {}
	for outcome: int in odds_size:
		for k: int in 300:
			var c: Array[int] = ScratchLogic.build_card(r, outcome)
			assert_eq(c.size(), 9)
			var lines: Array[int] = ScratchLogic.winning_lines(c)
			var cash: int = c.count(S.CASH)
			if outcome == ScratchLogic.OUTCOME_BLANK:
				assert_eq(lines.size(), 0, "a blank has no line: %s" % [c])
				assert_eq(cash, 0, "and no $")
			elif outcome == ScratchLogic.OUTCOME_CASH:
				assert_eq(lines.size(), 0, "a $ card has no line: %s" % [c])
				assert_eq(cash, 1, "and exactly one $")
			else:
				assert_eq(lines.size(), 1, "exactly one winning line: %s" % [c])
				assert_eq(cash, 0)
				if lines.size() == 1:
					assert_eq(c[int(ScratchLogic.LINES[lines[0]][0])], outcome - ScratchLogic.OUTCOME_LINE0, "of the drawn symbol")
					line_seen[lines[0]] = true
			for s: int in c:
				assert_between(s, 0, S.CASH)
			for t: int in 3:
				assert_almost_eq(ScratchLogic.card_multiplier(c, t, cfg), ScratchLogic.outcome_multiplier(cfg, t, outcome), 0.0001, "pays what it shows")
	assert_eq(line_seen.size(), 8, "rows, columns and both diagonals all come up")


func test_prize_table() -> void:
	var cfg: BalanceConfig = fx.balance
	var blank: Array[int] = _card([S.CHERRY, S.LEMON, S.BELL, S.BELL, S.SEVEN, S.CHERRY, S.LEMON, S.BELL, S.CHERRY])
	assert_eq(ScratchLogic.card_multiplier(blank, 0, cfg), 0.0)
	var row: Array[int] = _card([S.SEVEN, S.SEVEN, S.SEVEN, S.BELL, S.LEMON, S.CHERRY, S.LEMON, S.BELL, S.CHERRY])
	assert_eq(ScratchLogic.winning_lines(row), [0] as Array[int])
	assert_almost_eq(ScratchLogic.card_multiplier(row, 0, cfg), 15.0, 0.0001, "$10 card: three sevens pay 15×")
	assert_eq(ScratchLogic.prize(10, ScratchLogic.card_multiplier(row, 0, cfg)), 150)
	var diag: Array[int] = _card([S.DIAMOND, S.LEMON, S.BELL, S.LEMON, S.DIAMOND, S.CHERRY, S.BELL, S.CHERRY, S.DIAMOND])
	assert_eq(ScratchLogic.winning_lines(diag), [6] as Array[int], "the diagonal counts")
	assert_eq(ScratchLogic.prize(50, ScratchLogic.card_multiplier(diag, 2, cfg)), 10000, "$50 card: three diamonds pay $10,000")
	var col: Array[int] = _card([S.CHERRY, S.LEMON, S.BELL, S.CHERRY, S.BELL, S.LEMON, S.CHERRY, S.SEVEN, S.LEMON])
	assert_eq(ScratchLogic.winning_lines(col), [3] as Array[int], "a column counts")
	assert_eq(ScratchLogic.prize(25, ScratchLogic.card_multiplier(col, 1, cfg)), 25, "three cherries: the card's price back")
	var cash: Array[int] = _card([S.CASH, S.LEMON, S.BELL, S.BELL, S.SEVEN, S.CHERRY, S.LEMON, S.BELL, S.CHERRY])
	assert_eq(ScratchLogic.prize(10, ScratchLogic.card_multiplier(cash, 0, cfg)), 5, "a $ anywhere: the instant prize")
	assert_eq(ScratchLogic.prize(25, ScratchLogic.card_multiplier(cash, 1, cfg)), 10)
	assert_eq(ScratchLogic.prize(50, ScratchLogic.card_multiplier(cash, 2, cfg)), 25)
	var three_cash: Array[int] = _card([S.CASH, S.CASH, S.CASH, S.BELL, S.SEVEN, S.CHERRY, S.LEMON, S.BELL, S.CHERRY])
	assert_eq(ScratchLogic.winning_lines(three_cash), [] as Array[int], "$ never makes a line, each one pays")
	assert_almost_eq(ScratchLogic.card_multiplier(three_cash, 0, cfg), 1.5, 0.0001)
	# The printed table is exactly the prize rule.
	for t: int in 3:
		var rows: Array[Dictionary] = ScratchCardView.prize_rows(cfg, t, cfg.scratch_prices[t])
		assert_eq(rows.size(), 7)
		for i: int in 6:
			var sym: int = int(rows[i]["symbol"])
			var c: Array[int] = _card([sym, sym, sym, -1, -1, -1, -1, -1, -1])
			assert_eq(int(rows[i]["amount"]), ScratchLogic.prize(cfg.scratch_prices[t], ScratchLogic.card_multiplier(c, t, cfg)), "tier %d row %d" % [t, i])
			if i > 0:
				assert_gt(int(rows[i - 1]["amount"]), int(rows[i]["amount"]), "highest first")


func test_exact_rtp_per_tier_in_band() -> void:
	for t: int in 3:
		var r: Dictionary = ScratchLogic.exact_rtp(fx.balance, t)
		gut.p("scratch tier %d ($%d): exact RTP %.4f, hit rate %.3f" % [t, fx.balance.scratch_prices[t], r["rtp"], r["hit_rate"]])
		assert_between(float(r["rtp"]), 1.005, 1.02, "tier %d" % t)
		assert_between(float(r["hit_rate"]), 0.3, 0.65)
		var probs: Array[float] = ScratchLogic.outcome_probs(fx.balance, t)
		var sum: float = 0.0
		for p: float in probs:
			sum += p
		assert_almost_eq(sum, 1.0, 0.000001)


func test_favour_redraws_a_blank_once() -> void:
	var cfg := BalanceConfig.new()
	cfg.scratch_odds_low = PackedInt32Array([1, 1, 0, 0, 0, 0, 0, 0])  # half blank, half $
	var n: int = 20000
	for favour: float in [0.0, 0.5, 1.0]:
		cfg.scratch_favour = favour
		var r := SeededRng.new(5)
		var blanks: int = 0
		for i: int in n:
			if ScratchLogic.card_multiplier(ScratchLogic.draw_card(r, cfg, 0), 0, cfg) == 0.0:
				blanks += 1
		var expect: float = ScratchLogic.outcome_probs(cfg, 0)[ScratchLogic.OUTCOME_BLANK]
		assert_almost_eq(expect, 0.5 * (1.0 - favour) + 0.25 * favour, 0.0001)
		assert_almost_eq(blanks / float(n), expect, 0.015, "favour %.1f: blank rate" % favour)
	# The default tables: a little better than the plain odds, never worse.
	for t: int in 3:
		var odds: PackedInt32Array = fx.balance.scratch_odds(t)
		var plain_blank: float = odds[0] / float(Array(odds).reduce(func(a: int, b: int) -> int: return a + b, 0))
		assert_lt(ScratchLogic.outcome_probs(fx.balance, t)[0], plain_blank, "tier %d: fewer blanks than printed odds" % t)


func test_luck_rerolls_the_card() -> void:
	var means: Dictionary = {}
	for lk: int in [-3, 0, 3]:
		var f := TableFixture.new(11, [1], 100_000_000)
		f.economy.record_history = false
		if lk != 0:
			f.give_luck(1, lk, &"scratch")
		var s: ScratchLogic = f.make(ScratchLogic.new()) as ScratchLogic
		s.join(1)
		var total: float = 0.0
		var flourishes: int = 0
		for i: int in 6000:
			s.place_bet(1, {"tier": 0})
			assert_eq(_types(s.drain_events(), &"luck_flourish").size(), 0, "no clover before the card is scratched")
			total += ScratchLogic.card_multiplier(s.card, 0, f.balance)
			s.player_action(1, &"reveal")
			flourishes += _types(s.drain_events(), &"luck_flourish").size()
		means[lk] = total / 6000.0
		if lk == 0:
			assert_eq(flourishes, 0)
		else:
			assert_gt(flourishes, 0, "luck %d shows when it changed a card" % lk)
	gut.p("mean card multiplier by luck: %s" % means)
	assert_gt(float(means[3]), float(means[0]))
	assert_gt(float(means[0]), float(means[-3]))


func test_same_seed_same_cards() -> void:
	var runs: Array = []
	for k: int in 2:
		var f := TableFixture.new(4242, [1], 100000)
		var s: ScratchLogic = f.make(ScratchLogic.new()) as ScratchLogic
		s.join(1)
		var cards: Array = []
		for i: int in 40:
			s.place_bet(1, {"tier": i % 3})
			var evs: Array[Dictionary] = s.drain_events()
			var bought: Array[Dictionary] = _types(evs, &"scratch_card")
			assert_eq(bought.size(), 1, "one event carries the card")
			assert_eq(bought[0]["card"], s.card, "the card in the event is the card that pays")
			assert_eq(s.get_public_state()["card"], s.card)
			cards.append(s.card.duplicate())
			s.player_action(1, &"reveal")
		runs.append(cards)
	assert_eq(runs[0], runs[1], "the same seed sells the same cards")


func test_nothing_about_the_favour_is_sent() -> void:
	sc.place_bet(1, {"tier": 1})
	var evs: Array[Dictionary] = sc.drain_events()
	var bought: Dictionary = _types(evs, &"scratch_card")[0]
	var keys: Array = bought.keys()
	keys.sort()
	assert_eq(keys, ["card", "player", "price", "serial", "station", "tier", "type"])
	var pub_keys: Array = sc.get_public_state().keys()
	pub_keys.sort()
	assert_eq(pub_keys, ["card", "game", "last", "player", "serial", "stake", "tier"])
	assert_eq(sc.get_private_state(1), {})


func test_buy_reveal_and_payout() -> void:
	assert_eq(sc.prices(), [10, 25, 50] as Array[int])
	assert_true(sc.place_bet(1, {"tier": 1})["ok"])
	assert_eq(fx.economy.balance(1), 975, "the price is taken at once")
	assert_true(sc.has_stake(1))
	assert_eq(sc.place_bet(1, {"tier": 0})["error"], &"card_open", "one card at a time")
	var evs: Array[Dictionary] = sc.drain_events()
	assert_eq(_types(evs, &"bet_placed").size(), 1)
	assert_eq(_types(evs, &"round_result").size(), 0, "nothing pays before it is scratched")
	sc.card = _card([S.BELL, S.BELL, S.BELL, S.LEMON, S.CASH, S.CHERRY, S.SEVEN, S.CHERRY, S.LEMON])  # row of bells and a $
	sc.tick(10.0)
	assert_eq(fx.economy.balance(1), 975, "still under the foil")
	assert_true(sc.player_action(1, &"reveal")["ok"])
	var expected: int = 25 * 4 + 10
	assert_eq(fx.economy.balance(1), 975 + expected, "bells pay 4×, the $ pays $10 on the $25 card")
	var res: Array[Dictionary] = _types(sc.drain_events(), &"round_result")
	assert_eq(res.size(), 1)
	assert_eq(int(res[0]["returned"]), expected)
	assert_eq(res[0]["details"]["lines"], [0] as Array[int])
	assert_false(sc.has_stake(1))
	assert_eq(sc.get_public_state()["card"], [])
	assert_eq(int(sc.get_public_state()["last"]["returned"]), expected, "the panel can show the last card")
	assert_eq(sc.player_action(1, &"reveal")["error"], &"no_card")
	assert_eq(sc.player_action(2, &"reveal")["error"], &"not_seated")
	assert_eq(sc.player_action(1, &"stop")["error"], &"unknown_action")


func test_bets_by_amount_limits_and_funds() -> void:
	assert_eq(sc.place_bet(1, {"tier": 3})["error"], &"invalid_amount")
	assert_eq(sc.place_bet(1, {"amount": 20})["error"], &"invalid_amount")
	assert_true(sc.place_bet(1, {"amount": 50})["ok"], "a price works as the amount")
	assert_eq(sc.tier, 2)
	sc.player_action(1, &"reveal")
	sc.limits_multiplier = 1.5
	assert_eq(sc.prices(), [15, 37, 75] as Array[int], "prices scale with the table limits")
	var before: int = fx.economy.balance(1)
	assert_true(sc.place_bet(1, {"tier": 2})["ok"])
	assert_eq(fx.economy.balance(1), before - 75)
	sc.player_action(1, &"reveal")
	fx.economy.take_up_to(1, 1_000_000, &"test")
	fx.economy.apply(1, 20, &"test")
	assert_eq(sc.place_bet(1, {"tier": 1})["error"], &"insufficient_funds")
	assert_eq(fx.economy.balance(1), 20, "nothing taken")
	assert_eq(sc.place_bet(2, {"tier": 0})["error"], &"not_seated")
	assert_false(sc.can_join(2), "one player at the counter")
	assert_eq(sc.join(2)["error"], &"seat_taken")


func test_hot_table_multiplies_the_winnings() -> void:
	sc.hot_multiplier = 1.25
	sc.place_bet(1, {"tier": 0})
	sc.card = _card([S.SEVEN, S.SEVEN, S.SEVEN, S.LEMON, S.BELL, S.CHERRY, S.BELL, S.CHERRY, S.LEMON])
	sc.player_action(1, &"reveal")
	assert_eq(fx.economy.balance(1), 990 + 10 + int(floor(140 * 1.25)), "the profit ×1.25")


func test_walking_away_mid_card_pays_it() -> void:
	sc.place_bet(1, {"tier": 0})
	sc.card = _card([S.CLOVER, S.LEMON, S.BELL, S.CLOVER, S.BELL, S.CHERRY, S.CLOVER, S.CHERRY, S.LEMON])
	sc.leave(1)
	assert_eq(fx.economy.balance(1), 990 + 50, "three clovers paid as they leave")
	assert_eq(sc.player, -1)
	assert_true(sc.can_join(2), "the counter is free")
	sc.tick(100.0)
	assert_eq(fx.economy.balance(1), 1040, "and never twice")


func test_an_untouched_card_scratches_itself() -> void:
	sc.place_bet(1, {"tier": 0})
	sc.card = _card([S.CASH, S.LEMON, S.BELL, S.BELL, S.SEVEN, S.CHERRY, S.LEMON, S.BELL, S.CHERRY])
	sc.tick(fx.balance.scratch_auto_reveal - 0.5)
	assert_true(sc.has_stake(1))
	sc.tick(1.0)
	assert_false(sc.has_stake(1))
	assert_eq(fx.economy.balance(1), 995)


func test_refund_gives_the_price_back() -> void:
	sc.place_bet(1, {"tier": 2})
	assert_eq(fx.economy.balance(1), 950)
	sc.drain_events()
	sc.refund_all()
	assert_eq(fx.economy.balance(1), 1000)
	var evs: Array[Dictionary] = sc.drain_events()
	assert_eq(_types(evs, &"bets_refunded").size(), 1)
	assert_eq(int(_types(evs, &"bets_refunded")[0]["amount"]), 50)
	assert_eq(_types(evs, &"table_reset").size(), 1)
	assert_eq(_types(evs, &"round_result").size(), 0, "the card never pays")
	assert_false(sc.has_stake(1))
	assert_eq(sc.player_action(1, &"reveal")["error"], &"no_card")
	sc.refund_all()
	assert_eq(sc.drain_events().size(), 0, "nothing open, nothing to refund")


func test_fake_cash_part_is_not_refunded() -> void:
	var m := Modifier.new()
	m.id = &"fake_cash"
	m.flags = {&"fake_cash": true}
	fx.modifiers.add(1, m)
	sc.place_bet(1, {"tier": 1})
	assert_eq(sc.stake_covered, 25)
	sc.refund_all()
	assert_eq(fx.economy.balance(1), 1000 + 25 - 25, "Fake Cash paid it: nothing comes back")


func test_round_seconds_and_auto_resolve() -> void:
	assert_eq(sc.round_seconds(), ScratchLogic.ROUND_SECONDS)
	sc.place_bet(1, {"tier": 0})
	sc.card = _card([S.LEMON, S.LEMON, S.LEMON, S.CHERRY, S.BELL, S.CHERRY, S.BELL, S.CHERRY, S.BELL])
	sc.auto_resolve()
	assert_eq(fx.economy.balance(1), 990 + 20, "the match ends: the card pays")
	assert_eq(sc.cards_played, 1)
