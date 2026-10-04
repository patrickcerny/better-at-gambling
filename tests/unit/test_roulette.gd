extends GutTest

var fx: TableFixture
var rl: RouletteLogic


func before_each() -> void:
	fx = TableFixture.new(1, [1, 2], 1000)
	rl = fx.make(RouletteLogic.new(), &"rl1") as RouletteLogic
	rl.join(1)


func test_color_dozen_column_mapping_all_numbers() -> void:
	var reds: int = 0
	for n: int in range(1, 37):
		var red: bool = RouletteLogic.wins(&"red", 0, n)
		assert_ne(red, RouletteLogic.wins(&"black", 0, n), "n=%d" % n)
		if red:
			reds += 1
		assert_eq(RouletteLogic.wins(&"odd", 0, n), n % 2 == 1)
		assert_eq(RouletteLogic.wins(&"low", 0, n), n <= 18)
		var dozens: int = 0
		var columns: int = 0
		for v: int in range(1, 4):
			if RouletteLogic.wins(&"dozen", v, n):
				dozens += 1
				assert_eq(v, ceili(n / 12.0))
			if RouletteLogic.wins(&"column", v, n):
				columns += 1
				assert_eq(v, (n - 1) % 3 + 1)
		assert_eq(dozens, 1)
		assert_eq(columns, 1)
	assert_eq(reds, 18)
	assert_eq(RouletteLogic.color_of(0), &"green")
	assert_eq(RouletteLogic.color_of(32), &"red")
	assert_eq(RouletteLogic.color_of(26), &"black")


func test_zero_loses_outside_bets() -> void:
	for t: StringName in [&"red", &"black", &"odd", &"even", &"low", &"high"]:
		assert_false(RouletteLogic.wins(t, 0, 0))
	assert_false(RouletteLogic.wins(&"dozen", 1, 0))
	assert_true(RouletteLogic.wins(&"straight", 0, 0))


func test_wheel_neighbors() -> void:
	assert_true(RouletteLogic.are_neighbors(0, 32))
	assert_true(RouletteLogic.are_neighbors(26, 0))
	assert_false(RouletteLogic.are_neighbors(0, 1))
	assert_eq(RouletteLogic.WHEEL_ORDER.size(), 37)


func test_limits() -> void:
	assert_eq(rl.place_bet(1, {"type": &"red", "amount": 5})["error"], &"below_min")
	assert_true(rl.place_bet(1, {"type": &"red", "amount": 200})["ok"])
	assert_eq(rl.place_bet(1, {"type": &"black", "amount": 101})["error"], &"above_max")
	assert_true(rl.place_bet(1, {"type": &"black", "amount": 100})["ok"])
	assert_eq(rl.place_bet(1, {"type": &"straight", "value": 37, "amount": 10})["error"], &"invalid_bet_value")
	assert_eq(rl.place_bet(1, {"type": &"corner", "amount": 10})["error"], &"invalid_bet_type")
	assert_eq(rl.place_bet(2, {"type": &"red", "amount": 10})["error"], &"not_seated")


func test_cycle_and_payouts_per_type() -> void:
	# Exact payouts at generosity 0 so multipliers are plain.
	fx.balance.roulette_generosity = 0.0
	var types: Array = [[&"straight", 17, 35], [&"black", 0, 1], [&"odd", 0, 1], [&"low", 0, 1], [&"dozen", 2, 2], [&"column", 2, 2]]
	for t: Array in types:
		rl.place_bet(1, {"type": t[0], "value": t[1], "amount": 10})
	assert_eq(fx.economy.balance(1), 940)
	assert_eq(rl.state, RouletteLogic.State.BETTING)
	rl.tick(15.0)
	assert_eq(rl.state, RouletteLogic.State.SPINNING)
	assert_eq(rl.place_bet(1, {"type": &"red", "amount": 10})["error"], &"betting_closed")
	rl._pending_result = 17  # 17: black, odd, low, 2nd dozen, 2nd column
	rl.tick(4.0)
	assert_eq(rl.state, RouletteLogic.State.RESULT)
	assert_eq(rl.result, 17)
	# straight 360 + black 20 + odd 20 + low 20 + dozen 30 + column 30
	assert_eq(fx.economy.balance(1), 940 + 360 + 20 + 20 + 20 + 30 + 30)
	rl.tick(3.0)
	assert_eq(rl.state, RouletteLogic.State.BETTING)


func test_generosity_bonus_expected_value() -> void:
	# 4% of a $20 return = $0.80 -> paid as $1 with probability 0.8.
	var total: int = 0
	var n: int = 2000
	for i: int in n:
		total += rl._stochastic_round(0.8)
	assert_almost_eq(total / float(n), 0.8, 0.03)


func test_table_idles_without_players() -> void:
	rl.leave(1)
	rl.tick(15.0)
	rl.tick(4.0)
	rl.tick(3.0)
	assert_eq(rl.state, RouletteLogic.State.IDLE)


func test_auto_resolve_spins_immediately() -> void:
	rl.place_bet(1, {"type": &"red", "amount": 10})
	rl.auto_resolve()
	assert_eq(rl.state, RouletteLogic.State.RESULT)
	assert_true(rl.result >= 0)
	assert_true(rl.bets.is_empty())


func test_clear_bets_refunds() -> void:
	rl.place_bet(1, {"type": &"red", "amount": 50})
	rl.player_action(1, &"clear_bets")
	assert_eq(fx.economy.balance(1), 1000)
	assert_true(rl.bets.is_empty())


func test_lucky_neighbor_and_jinx() -> void:
	fx = TableFixture.new(1, [1], 1000)
	fx.balance.luck_reroll_per_point = 1.0  # force the luck effects
	rl = fx.make(RouletteLogic.new()) as RouletteLogic
	rl.join(1)
	fx.give_luck(1, 3)
	rl.place_bet(1, {"type": &"straight", "value": 32, "amount": 10})
	rl.tick(15.0)
	rl._pending_result = 0  # 0 sits next to 32
	rl.tick(4.0)
	assert_eq(fx.economy.balance(1), 990 + 60)
	rl.tick(3.0)
	var fx2 := TableFixture.new(2, [1], 1000)
	fx2.balance.luck_reroll_per_point = 1.0
	var r2: RouletteLogic = fx2.make(RouletteLogic.new()) as RouletteLogic
	fx2.give_luck(1, -1)
	r2.join(1)
	r2.place_bet(1, {"type": &"red", "amount": 100})
	r2.tick(15.0)
	r2._pending_result = 1
	r2.tick(4.0)
	assert_eq(fx2.economy.balance(1), 900 + 190)
