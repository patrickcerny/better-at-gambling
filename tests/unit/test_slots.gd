extends GutTest

const S := SlotsLogic.Sym

var cfg: BalanceConfig = BalanceConfig.new()


func _pay(a: int, b: int, c: int) -> int:
	return SlotsLogic.payout_multiplier([a, b, c] as Array[int], cfg)


func test_paytable() -> void:
	assert_eq(_pay(S.DIAMOND, S.DIAMOND, S.DIAMOND), 100)
	assert_eq(_pay(S.SEVEN, S.SEVEN, S.SEVEN), 40)
	assert_eq(_pay(S.BAR, S.BAR, S.BAR), 20)
	assert_eq(_pay(S.BELL, S.BELL, S.BELL), 12)
	assert_eq(_pay(S.LEMON, S.LEMON, S.LEMON), 8)
	assert_eq(_pay(S.CHERRY, S.CHERRY, S.CHERRY), 6)
	assert_eq(_pay(S.LEMON, S.BELL, S.BAR), 0)


func test_wild_substitution() -> void:
	assert_eq(_pay(S.CLOVER, S.SEVEN, S.SEVEN), 40)
	assert_eq(_pay(S.BAR, S.CLOVER, S.CLOVER), 20)
	assert_eq(_pay(S.CLOVER, S.CLOVER, S.CLOVER), 100)
	assert_eq(_pay(S.CLOVER, S.CHERRY, S.CHERRY), 6)
	assert_eq(_pay(S.CLOVER, S.BAR, S.BELL), 0)


func test_cherry_rules() -> void:
	assert_eq(_pay(S.CHERRY, S.CHERRY, S.BELL), 2)
	assert_eq(_pay(S.BELL, S.CHERRY, S.CHERRY), 2)
	assert_eq(_pay(S.CHERRY, S.BELL, S.BAR), 1)
	assert_eq(_pay(S.BELL, S.CHERRY, S.BAR), 0, "single cherry only counts leftmost")


func test_jackpot_needs_real_diamonds() -> void:
	assert_true(SlotsLogic.is_jackpot([S.DIAMOND, S.DIAMOND, S.DIAMOND] as Array[int]))
	assert_false(SlotsLogic.is_jackpot([S.CLOVER, S.DIAMOND, S.DIAMOND] as Array[int]))


func test_exact_rtp_in_target_band() -> void:
	var r: Dictionary = SlotsLogic.exact_rtp(cfg)
	assert_between(float(r["rtp"]), 1.005, 1.02)
	assert_between(float(r["hit_rate"]), 0.30, 0.40)


func test_spin_flow_and_skip_stop() -> void:
	var fx := TableFixture.new(3, [1, 2], 1000)
	var sl: SlotsLogic = fx.make(SlotsLogic.new(), &"slot1") as SlotsLogic
	assert_true(sl.join(1)["ok"])
	assert_false(sl.join(2)["ok"])
	assert_eq(sl.place_bet(1, {"amount": 15})["error"], &"invalid_amount")
	assert_true(sl.place_bet(1, {"amount": 25})["ok"])
	assert_eq(fx.economy.balance(1), 975)
	assert_eq(sl.place_bet(1, {"amount": 25})["error"], &"busy")
	assert_eq(sl.player_action(1, &"stop")["error"], &"too_early")
	sl.tick(0.6)
	sl.drain_events()
	assert_true(sl.player_action(1, &"stop")["ok"])
	assert_false(sl.spinning)
	var expected: int = 975 + 25 * SlotsLogic.payout_multiplier(sl.line, fx.balance)
	if SlotsLogic.is_jackpot(sl.line):
		return
	# The reels land on the line first (Patrick: the payout spoiled the animation): no money, no
	# result until the last reel has stopped.
	var landing: Array[Dictionary] = sl.drain_events()
	assert_eq(landing.size(), 1)
	assert_eq(landing[0]["type"], &"slots_landing")
	assert_eq(landing[0]["line"], sl.line)
	assert_eq(fx.economy.balance(1), 975, "nothing paid while the reels land")
	assert_true(sl.has_stake(1), "the stake is still in play")
	# The reels still land on screen: no new spin (and no spamming STOP/spin) until they settle.
	assert_true(sl.get_public_state()["settling"], "settling after the stop")
	assert_eq(sl.place_bet(1, {"amount": 25})["error"], &"too_early")
	assert_eq(sl.player_action(1, &"stop")["error"], &"too_early", "nothing to stop")
	sl.tick(fx.balance.slots_settle_time - 0.1)
	assert_eq(sl.place_bet(1, {"amount": 25})["error"], &"too_early", "still landing")
	assert_eq(fx.economy.balance(1), 975, "still nothing paid")
	assert_true(sl.drain_events().is_empty(), "no result before the reels stop")
	sl.tick(0.2)
	assert_eq(fx.economy.balance(1), expected, "paid as the last reel stops")
	var paid: Array[Dictionary] = sl.drain_events()
	assert_eq(paid.filter(func(e: Dictionary) -> bool: return e["type"] == &"round_result").size(), 1)
	assert_false(sl.has_stake(1))
	assert_false(sl.get_public_state()["settling"])
	assert_true(sl.place_bet(1, {"amount": 25})["ok"], "settled: the next spin may start")


func test_full_spin_pays_only_when_the_reels_have_stopped() -> void:
	var fx := TableFixture.new(7, [1], 1000)
	var sl: SlotsLogic = fx.make(SlotsLogic.new(), &"slot1") as SlotsLogic
	sl.join(1)
	assert_true(sl.place_bet(1, {"amount": 50})["ok"])
	sl.line = [S.SEVEN, S.SEVEN, S.SEVEN] as Array[int]  # a sure win
	sl.drain_events()
	var t: float = 0.0
	var paid_at: float = -1.0
	var landing_at: float = -1.0
	while t < 6.0 and paid_at < 0.0:
		sl.tick(0.05)
		t += 0.05
		for e: Dictionary in sl.drain_events():
			if e["type"] == &"slots_landing":
				landing_at = t
			if e["type"] == &"round_result":
				paid_at = t
		if paid_at < 0.0:
			assert_eq(fx.economy.balance(1), 950, "no money before the result (t=%.2f)" % t)
	assert_almost_eq(landing_at, fx.balance.slots_spin_time, 0.06, "the reels start landing when the spin time ends")
	assert_almost_eq(paid_at - landing_at, fx.balance.slots_settle_time, 0.06, "and it pays once they have landed")
	assert_gte(fx.balance.slots_settle_time, SlotReelsFx.land_seconds(), "the reels on screen have stopped by then")
	assert_eq(fx.economy.balance(1), 950 + 50 * 40)


func test_walking_away_mid_landing_settles_at_once() -> void:
	var fx := TableFixture.new(8, [1], 1000)
	var sl: SlotsLogic = fx.make(SlotsLogic.new(), &"slot1") as SlotsLogic
	sl.join(1)
	sl.place_bet(1, {"amount": 10})
	sl.line = [S.BELL, S.BELL, S.BELL] as Array[int]
	sl.tick(fx.balance.slots_spin_time + 0.01)
	assert_eq(fx.economy.balance(1), 990)
	sl.leave(1)
	assert_eq(fx.economy.balance(1), 990 + 10 * 12, "paid as they leave")
	assert_false(sl.landing)
	sl.tick(5.0)
	assert_eq(fx.economy.balance(1), 990 + 10 * 12, "and never twice")


func test_refund_mid_landing_gives_the_stake_back() -> void:
	var fx := TableFixture.new(9, [1], 1000)
	var sl: SlotsLogic = fx.make(SlotsLogic.new(), &"slot1") as SlotsLogic
	sl.join(1)
	sl.place_bet(1, {"amount": 25})
	sl.tick(fx.balance.slots_spin_time + 0.01)
	sl.refund_all()
	assert_eq(fx.economy.balance(1), 1000)
	sl.tick(5.0)
	assert_eq(fx.economy.balance(1), 1000, "the line it was landing on never pays")


func test_bet_sizes_scale_with_limits() -> void:
	var fx := TableFixture.new(3, [1], 1000)
	var sl: SlotsLogic = fx.make(SlotsLogic.new()) as SlotsLogic
	sl.limits_multiplier = 1.5
	assert_eq(sl.bet_sizes(), [15, 37, 75, 150] as Array[int])


func test_jackpot_paid_on_three_diamonds() -> void:
	var fx := TableFixture.new(3, [1], 1000)
	var sl: SlotsLogic = fx.make(SlotsLogic.new()) as SlotsLogic
	sl.join(1)
	sl.place_bet(1, {"amount": 10})
	sl.line = [S.DIAMOND, S.DIAMOND, S.DIAMOND] as Array[int]
	var pot: int = fx.jackpot.pot
	sl.auto_resolve()
	assert_eq(fx.economy.balance(1), 990 + 1000 + pot)
	assert_eq(fx.jackpot.pot, fx.balance.jackpot_seed)
