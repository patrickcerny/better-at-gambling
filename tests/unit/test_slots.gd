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
	assert_true(sl.player_action(1, &"stop")["ok"])
	assert_false(sl.spinning)
	var expected: int = 975 + 25 * SlotsLogic.payout_multiplier(sl.line, fx.balance)
	if SlotsLogic.is_jackpot(sl.line):
		return
	assert_eq(fx.economy.balance(1), expected)


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
