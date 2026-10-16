extends GutTest
## Craps table (Patrick: "Craps but only with 2 dices"): Pass Line and Don't Pass through the
## come-out and the point, the Field and Any Seven one-roll bets, the shooter who has sat longest
## with the dice passing on a seven-out, and the server's roll quietly favouring the table.

var fx: TableFixture
var cr: CrapsLogic


func before_each() -> void:
	fx = TableFixture.new(3, [1, 2, 3], 1000)
	cr = fx.make(CrapsLogic.new(), &"cr1") as CrapsLogic
	cr.join(1)
	cr.join(2)
	fx.balance.craps_favour = 0.0  # the plain table unless a test says otherwise


func _types(evs: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	return evs.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## Settles the table on a roll of `a` + `b` (the dice the server would have drawn).
func _roll(a: int, b: int) -> void:
	assert_eq(cr.state, CrapsLogic.State.BETTING, "rolls from a betting window")
	cr._throw(-1)
	cr.dice = [a, b]
	cr.tick(fx.balance.craps_throw_time + 0.01)
	assert_eq(cr.state, CrapsLogic.State.RESULT)
	cr.tick(fx.balance.craps_result_time + 0.01)


func _open_for_shooting() -> void:
	cr.tick(fx.balance.craps_shoot_lock + 0.01)


func test_rules_table() -> void:
	# Come-out.
	for t: int in [7, 11]:
		assert_eq(CrapsLogic.decide(&"pass", 0, t), 1.0, "pass wins a natural %d" % t)
		assert_eq(CrapsLogic.decide(&"dont_pass", 0, t), -1.0)
	for t: int in [2, 3, 12]:
		assert_eq(CrapsLogic.decide(&"pass", 0, t), -1.0, "pass loses craps %d" % t)
	assert_eq(CrapsLogic.decide(&"dont_pass", 0, 2), 1.0)
	assert_eq(CrapsLogic.decide(&"dont_pass", 0, 3), 1.0)
	assert_eq(CrapsLogic.decide(&"dont_pass", 0, 12), 0.0, "bar 12: a push")
	for t: int in CrapsLogic.POINTS:
		assert_true(is_nan(CrapsLogic.decide(&"pass", 0, t)), "%d sets the point" % t)
		assert_true(is_nan(CrapsLogic.decide(&"dont_pass", 0, t)))
		assert_eq(CrapsLogic.outcome_of(0, t), &"point_set")
	# Point on 6.
	assert_eq(CrapsLogic.decide(&"pass", 6, 6), 1.0)
	assert_eq(CrapsLogic.decide(&"pass", 6, 7), -1.0)
	assert_eq(CrapsLogic.decide(&"dont_pass", 6, 7), 1.0)
	assert_eq(CrapsLogic.decide(&"dont_pass", 6, 6), -1.0)
	for t: int in [2, 3, 4, 5, 8, 9, 10, 11, 12]:
		assert_true(is_nan(CrapsLogic.decide(&"pass", 6, t)), "%d rides with the point on 6" % t)
		assert_true(is_nan(CrapsLogic.decide(&"dont_pass", 6, t)))
	assert_eq(CrapsLogic.outcome_of(6, 6), &"point_made")
	assert_eq(CrapsLogic.outcome_of(6, 7), &"seven_out")
	assert_eq(CrapsLogic.outcome_of(6, 11), &"roll")
	assert_eq(CrapsLogic.outcome_of(0, 11), &"natural")
	assert_eq(CrapsLogic.outcome_of(0, 12), &"craps")
	# One-roll bets, whatever the point.
	for p: int in [0, 4, 9]:
		for t: int in range(2, 13):
			assert_eq(CrapsLogic.decide(&"field", p, t), 1.0 if t in [2, 3, 4, 9, 10, 11, 12] else -1.0, "field on %d" % t)
			assert_eq(CrapsLogic.decide(&"any_seven", p, t), 1.0 if t == 7 else -1.0, "any seven on %d" % t)
	assert_eq(CrapsLogic.pay_ratio(&"field", 2, fx.balance), fx.balance.craps_field_double_ratio, "2 pays double")
	assert_eq(CrapsLogic.pay_ratio(&"field", 12, fx.balance), fx.balance.craps_field_double_ratio, "12 pays double")
	assert_eq(CrapsLogic.pay_ratio(&"field", 9, fx.balance), fx.balance.craps_field_ratio)
	assert_eq(CrapsLogic.pay_ratio(&"any_seven", 7, fx.balance), fx.balance.craps_any_seven_ratio)
	assert_eq(CrapsLogic.pay_ratio(&"pass", 7, fx.balance), 1.0, "line bets pay even money")
	var sum: float = 0.0
	for t: int in range(2, 13):
		sum += CrapsLogic.total_chance(t)
	assert_almost_eq(sum, 1.0, 0.000001)
	assert_almost_eq(CrapsLogic.total_chance(7), 6.0 / 36.0, 0.000001)


func test_bet_rules() -> void:
	assert_eq(cr.state, CrapsLogic.State.BETTING)
	assert_eq(cr.place_bet(1, {"type": "hardways", "amount": 10})["error"], &"invalid_bet_type")
	assert_eq(cr.place_bet(1, {"type": "pass", "amount": 5})["error"], &"below_min")
	assert_eq(cr.place_bet(3, {"type": "pass", "amount": 10})["error"], &"not_seated")
	assert_true(cr.place_bet(1, {"type": "pass", "amount": 100})["ok"])
	assert_true(cr.counting, "the first chip starts the countdown")
	assert_almost_eq(cr.timer, fx.balance.craps_shoot_time, 0.001)
	assert_true(cr.place_bet(1, {"type": "pass", "amount": 50})["ok"], "more on the same bet")
	assert_eq(cr.bets.size(), 1, "one stack per bet")
	assert_eq(int(cr.bets[0]["amount"]), 150)
	assert_eq(cr.place_bet(1, {"type": "dont_pass", "amount": 10})["error"], &"one_side_only", "no betting both sides")
	assert_true(cr.place_bet(1, {"type": "field", "amount": 40})["ok"])
	assert_eq(cr.place_bet(1, {"type": "any_seven", "amount": 20})["error"], &"above_max")
	assert_eq(fx.economy.balance(1), 810)
	assert_true(cr.player_action(1, &"clear_bets")["ok"])
	assert_eq(fx.economy.balance(1), 1000, "every chip comes back on a come-out roll")
	assert_false(cr.counting, "nothing on the felt: no countdown")
	cr.limits_multiplier = 2.0
	assert_eq(cr.limits(), Vector2i(20, 400), "limits rise with the segment like every table")


func test_pass_line_point_cycle_and_dont_pass() -> void:
	assert_true(cr.place_bet(1, {"type": "pass", "amount": 20})["ok"])
	assert_true(cr.place_bet(2, {"type": "dont_pass", "amount": 30})["ok"])
	_roll(4, 2)
	assert_eq(cr.point, 6, "6 is the point")
	assert_eq(cr.outcome, &"point_set")
	assert_eq(cr.bets.size(), 2, "both line bets ride")
	assert_eq(cr.state, CrapsLogic.State.BETTING)
	assert_true(cr.counting, "the countdown runs at once while line bets ride")
	assert_eq(cr.place_bet(1, {"type": "pass", "amount": 10})["error"], &"point_is_on", "line bets go down on the come-out")
	assert_true(cr.player_action(1, &"clear_bets")["ok"])
	assert_eq(cr.bets.size(), 2, "a line bet stays up once the point is on")
	_roll(5, 6)
	assert_eq(cr.outcome, &"roll")
	assert_eq(cr.point, 6)
	assert_eq(fx.economy.balance(1), 980)
	cr.drain_events()
	_roll(3, 3)
	assert_eq(cr.outcome, &"point_made")
	assert_eq(cr.point, 0, "back to the come-out")
	assert_eq(fx.economy.balance(1), 1020, "pass pays 1:1")
	assert_eq(fx.economy.balance(2), 970, "don't pass loses on the point")
	var results: Array[Dictionary] = _types(cr.drain_events(), &"round_result")
	assert_eq(results.size(), 2)
	assert_true(cr.bets.is_empty())
	# Seven-out the other way round.
	assert_true(cr.place_bet(1, {"type": "pass", "amount": 20})["ok"])
	assert_true(cr.place_bet(2, {"type": "dont_pass", "amount": 30})["ok"])
	_roll(6, 4)
	assert_eq(cr.point, 10)
	_roll(4, 3)
	assert_eq(cr.outcome, &"seven_out")
	assert_eq(fx.economy.balance(1), 1000)
	assert_eq(fx.economy.balance(2), 1000, "don't pass wins the seven-out")


func test_come_out_naturals_craps_and_bar_twelve() -> void:
	cr.place_bet(1, {"type": "pass", "amount": 10})
	cr.place_bet(2, {"type": "dont_pass", "amount": 10})
	_roll(5, 6)
	assert_eq(cr.outcome, &"natural")
	assert_eq(fx.economy.balance(1), 1010)
	assert_eq(fx.economy.balance(2), 990)
	cr.place_bet(1, {"type": "pass", "amount": 10})
	cr.place_bet(2, {"type": "dont_pass", "amount": 10})
	_roll(1, 2)
	assert_eq(cr.outcome, &"craps")
	assert_eq(fx.economy.balance(1), 1000)
	assert_eq(fx.economy.balance(2), 1000)
	cr.place_bet(1, {"type": "pass", "amount": 10})
	cr.place_bet(2, {"type": "dont_pass", "amount": 10})
	cr.drain_events()
	_roll(6, 6)
	assert_eq(fx.economy.balance(1), 990, "12 loses the pass line")
	assert_eq(fx.economy.balance(2), 1000, "and pushes the don't pass")
	var push: Array[Dictionary] = _types(cr.drain_events(), &"round_result").filter(func(e: Dictionary) -> bool: return int(e["player"]) == 2)
	assert_eq(int(push[0]["returned"]), 10)
	assert_eq(int(push[0]["net"]), 0)
	assert_true(cr.bets.is_empty())


func test_field_and_any_seven_are_one_roll_bets() -> void:
	fx.balance.craps_field_ratio = 1.0
	fx.balance.craps_field_double_ratio = 2.0
	fx.balance.craps_any_seven_ratio = 4.0
	cr.place_bet(1, {"type": "field", "amount": 10})
	cr.place_bet(2, {"type": "any_seven", "amount": 10})
	_roll(1, 1)
	assert_eq(fx.economy.balance(1), 1020, "2 pays the field double")
	assert_eq(fx.economy.balance(2), 990)
	assert_true(cr.bets.is_empty(), "both decided in one roll")
	cr.place_bet(1, {"type": "field", "amount": 10})
	cr.place_bet(2, {"type": "any_seven", "amount": 10})
	_roll(3, 4)
	assert_eq(fx.economy.balance(1), 1010)
	assert_eq(fx.economy.balance(2), 1030, "any seven pays 4:1")
	cr.place_bet(1, {"type": "field", "amount": 10})
	_roll(4, 5)
	assert_eq(fx.economy.balance(1), 1020)
	cr.place_bet(1, {"type": "field", "amount": 10})
	_roll(6, 6)
	assert_eq(fx.economy.balance(1), 1040, "12 pays the field double")
	# The house pays the one-roll bets a little better than the felt says.
	fx.balance.craps_any_seven_ratio = 4.8
	cr.place_bet(2, {"type": "any_seven", "amount": 10})
	_roll(1, 6)
	assert_eq(fx.economy.balance(2), 1030 + 48)
	# One-roll bets ride a point too, and come off with clear_bets.
	cr.place_bet(1, {"type": "pass", "amount": 10})
	_roll(2, 2)
	assert_eq(cr.point, 4)
	var before: int = fx.economy.balance(1)
	cr.place_bet(1, {"type": "field", "amount": 10})
	assert_true(cr.player_action(1, &"clear_bets")["ok"])
	assert_eq(fx.economy.balance(1), before)
	assert_eq(cr.bets.size(), 1, "only the pass line is left")


func test_shooter_is_the_longest_seated_and_rotates_on_seven_out() -> void:
	assert_eq(cr.shooter, 1, "sat first, shoots first")
	cr.join(3)
	cr.place_bet(2, {"type": "field", "amount": 10})
	assert_eq(cr.player_action(2, &"shoot")["error"], &"not_shooter")
	assert_eq(cr.player_action(1, &"shoot")["error"], &"wait_for_bets", "the table gets a moment to bet")
	_open_for_shooting()
	cr.drain_events()
	assert_true(cr.player_action(1, &"shoot")["ok"])
	assert_eq(cr.state, CrapsLogic.State.ROLLING)
	var rolled: Array[Dictionary] = _types(cr.drain_events(), &"craps_rolled")
	assert_eq(rolled.size(), 1)
	assert_eq(int(rolled[0]["shooter"]), 1)
	assert_eq(rolled[0]["dice"], cr.dice, "the throw carries the server's faces")
	assert_eq(int(rolled[0]["seed"]), cr.throw_seed)
	assert_eq(cr.player_action(1, &"shoot")["error"], &"betting_closed")
	assert_eq(cr.place_bet(2, {"type": "field", "amount": 10})["error"], &"betting_closed", "no bets with the dice in the air")
	cr.tick(fx.balance.craps_throw_time + 0.01)
	cr.tick(fx.balance.craps_result_time + 0.01)
	# Point, then seven-out: the dice pass to the next in sitting order.
	cr.place_bet(1, {"type": "pass", "amount": 10})
	_roll(5, 5)
	assert_eq(cr.shooter, 1, "the shooter keeps the dice while the point is on")
	_roll(5, 2)
	assert_eq(cr.shooter, 2, "seven-out: the dice pass on")
	cr.place_bet(2, {"type": "pass", "amount": 10})
	_roll(3, 3)
	_roll(1, 6)
	assert_eq(cr.shooter, 3)
	cr.place_bet(2, {"type": "pass", "amount": 10})
	_roll(4, 4)
	_roll(2, 5)
	assert_eq(cr.shooter, 1, "round the table")
	# A natural or a made point keeps the dice.
	cr.place_bet(2, {"type": "pass", "amount": 10})
	_roll(5, 6)
	assert_eq(cr.shooter, 1)
	# The shooter stands up: the next one takes the dice.
	cr.leave(1)
	assert_eq(cr.shooter, 2)
	cr.leave(3)
	assert_eq(cr.shooter, 2)
	cr.leave(2)
	assert_eq(cr.shooter, -1, "nobody left: the stickman throws")


func test_the_stickman_throws_when_the_shooter_waits() -> void:
	cr.tick(60.0)
	assert_eq(cr.state, CrapsLogic.State.BETTING, "no roll without a bet")
	cr.place_bet(2, {"type": "any_seven", "amount": 10})
	cr.tick(fx.balance.craps_shoot_time - 0.1)
	assert_eq(cr.state, CrapsLogic.State.BETTING)
	cr.drain_events()
	cr.tick(0.2)
	assert_eq(cr.state, CrapsLogic.State.ROLLING)
	assert_eq(int(_types(cr.drain_events(), &"craps_rolled")[0]["shooter"]), -1, "the stickman threw")


func test_rolls_are_fair_without_favour() -> void:
	var counts: Array[int] = []
	counts.resize(13)
	counts.fill(0)
	var n: int = 36000
	for i: int in n:
		var r: Vector2i = cr._draw_roll()
		assert_true(r.x >= 1 and r.x <= 6 and r.y >= 1 and r.y <= 6)
		counts[r.x + r.y] += 1
	for t: int in range(2, 13):
		assert_almost_eq(float(counts[t]) / n, CrapsLogic.total_chance(t), 0.006, "total %d" % t)


## Field wins out of `n` rolls with one field bet down.
func _field_wins(n: int) -> int:
	cr.bets = [{"player": 1, "type": &"field", "amount": 10}]
	var wins: int = 0
	for i: int in n:
		var r: Vector2i = cr._draw_roll()
		if CrapsLogic.decide(&"field", 0, r.x + r.y) > 0.0:
			wins += 1
	return wins


func test_the_table_is_quietly_favoured() -> void:
	fx.rng.reseed(777)
	var plain: int = _field_wins(4000)
	fx.balance.craps_favour = 1.0
	fx.rng.reseed(777)
	var favoured: int = _field_wins(4000)
	gut.p("field wins: plain %d, favour 1.0 %d of 4000" % [plain, favoured])
	assert_almost_eq(plain / 4000.0, 16.0 / 36.0, 0.03)
	# A losing roll is redrawn once: 16/36 + 20/36 × 16/36 ≈ 0.69 at certainty.
	assert_almost_eq(favoured / 4000.0, 16.0 / 36.0 * (1.0 + 20.0 / 36.0), 0.03)
	# A roll somebody wins on is never redrawn: with the field and any seven both down, a 7 (field
	# loses, any seven wins) stands.
	cr.bets = [{"player": 1, "type": &"field", "amount": 10}, {"player": 2, "type": &"any_seven", "amount": 10}]
	assert_false(cr._nobody_wins_somebody_loses(7))
	assert_true(cr._nobody_wins_somebody_loses(6))
	# A roll that decides nothing is never redrawn either.
	cr.bets = [{"player": 1, "type": &"pass", "amount": 10}]
	cr.point = 6
	assert_false(cr._nobody_wins_somebody_loses(8))
	assert_true(cr._nobody_wins_somebody_loses(7))
	cr.point = 0
	assert_false(cr._nobody_wins_somebody_loses(8), "setting a point is no loss")
	# Nothing of it is shown: the throw and the state carry the faces only.
	cr.bets = []
	cr.place_bet(1, {"type": "field", "amount": 10})
	cr.drain_events()
	cr._throw(1)
	var rolled: Dictionary = _types(cr.drain_events(), &"craps_rolled")[0]
	assert_false(rolled.has("favour"))
	assert_false(rolled.has("redrawn"))
	var pub: Dictionary = cr.get_public_state()
	assert_false(pub.has("favour"))
	assert_eq(pub.keys().filter(func(k: String) -> bool: return k.contains("favour") or k.contains("luck")), [])


func test_luck_rerolls_the_dice_like_the_other_tables() -> void:
	cr.luck.reroll_per_point = 1.0  # force the luck effects
	fx.give_luck(1, 3)
	fx.rng.reseed(99)
	var lucky: int = _field_wins(3000)
	fx.rng.reseed(99)
	cr.luck.reroll_per_point = 0.0
	var plain: int = _field_wins(3000)
	assert_gt(lucky, plain + 300, "a lucky player's field wins far more often")
	# Jinxed: the reroll keeps the worse roll for them.
	var jinx := TableFixture.new(5, [1, 2], 1000)
	var cj: CrapsLogic = jinx.make(CrapsLogic.new(), &"cj") as CrapsLogic
	cj.join(1)
	cj.luck.reroll_per_point = 1.0
	jinx.balance.craps_favour = 0.0
	jinx.give_luck(1, -3)
	cj.bets = [{"player": 1, "type": &"field", "amount": 10}]
	var jinxed: int = 0
	for i: int in 3000:
		var r: Vector2i = cj._draw_roll()
		if CrapsLogic.decide(&"field", 0, r.x + r.y) > 0.0:
			jinxed += 1
	assert_lt(jinxed, plain - 300, "a jinxed player's field loses more often")
	# A flourish shows when luck changed the roll, never an error.
	cj.place_bet(1, {"type": "any_seven", "amount": 10})
	var flourishes: int = 0
	for i: int in 50:
		cj._draw_roll()
		flourishes += _types(cj.drain_events(), &"luck_flourish").size()
	assert_gt(flourishes, 0)


func test_the_same_seed_rolls_the_same_dice() -> void:
	var a := TableFixture.new(42, [1], 1000)
	var b := TableFixture.new(42, [1], 1000)
	var la: CrapsLogic = a.make(CrapsLogic.new(), &"c") as CrapsLogic
	var lb: CrapsLogic = b.make(CrapsLogic.new(), &"c") as CrapsLogic
	var seq_a: Array = []
	var seq_b: Array = []
	for l: CrapsLogic in [la, lb]:
		l.join(1)
		for i: int in 40:
			if l.bets.is_empty():
				l.place_bet(1, {"type": "pass", "amount": 10})
			l.tick(l.balance.craps_shoot_time + 0.01)
			(seq_a if l == la else seq_b).append([l.dice.duplicate(), l.throw_seed])
			l.tick(l.balance.craps_throw_time + 0.01)
			l.tick(l.balance.craps_result_time + 0.01)
	assert_eq(seq_a, seq_b, "a match replays exactly from its seed")
	assert_eq(a.economy.balance(1), b.economy.balance(1))


func test_refund_mid_point_and_auto_resolve() -> void:
	cr.place_bet(1, {"type": "pass", "amount": 40})
	cr.place_bet(2, {"type": "field", "amount": 20})
	_roll(4, 1)
	assert_eq(cr.point, 5)
	assert_eq(fx.economy.balance(1), 960)
	cr.place_bet(2, {"type": "field", "amount": 20})
	cr._throw(2)
	assert_true(cr.has_stake(1))
	cr.drain_events()
	cr.refund_all()
	assert_eq(fx.economy.balance(1), 1000, "a minigame gives the pass line back mid-point")
	assert_eq(cr.point, 0, "the puck comes off")
	assert_eq(cr.state, CrapsLogic.State.IDLE)
	assert_false(cr.has_stake(1))
	var evs: Array[Dictionary] = cr.drain_events()
	assert_eq(_types(evs, &"bets_refunded").size(), 2)
	assert_eq(_types(evs, &"table_reset").size(), 1)
	cr.tick(0.1)
	assert_eq(cr.state, CrapsLogic.State.BETTING, "players still seated: a new come-out")
	cr.place_bet(1, {"type": "dont_pass", "amount": 30})
	cr.place_bet(2, {"type": "any_seven", "amount": 10})
	cr.drain_events()
	cr.auto_resolve()
	assert_true(cr.bets.is_empty(), "the match end throws until every bet is decided")
	assert_false(cr.has_stake(1))
	var settled: Array[Dictionary] = _types(cr.drain_events(), &"round_result")
	assert_eq(settled.size(), 2, "one result per bet")
	var back: int = int(settled.filter(func(e: Dictionary) -> bool: return int(e["player"]) == 1)[0]["returned"])
	assert_eq(fx.economy.balance(1), 970 + back)


func test_leaving_mid_point_still_settles() -> void:
	cr.place_bet(1, {"type": "pass", "amount": 10})
	_roll(3, 1)
	assert_eq(cr.point, 4)
	cr.leave(1)
	cr.leave(2)
	assert_eq(cr.state, CrapsLogic.State.BETTING)
	assert_true(cr.counting, "the stickman keeps throwing for the bet left on the felt")
	var guard: int = 0
	while not cr.bets.is_empty() and guard < 5000:
		cr.tick(0.1)
		guard += 1
	assert_true(cr.bets.is_empty())
	assert_true(fx.economy.balance(1) == 990 or fx.economy.balance(1) == 1010, "won or lost, never lost track of")
	cr.tick(fx.balance.craps_result_time + fx.balance.craps_throw_time + 0.1)
	assert_eq(cr.state, CrapsLogic.State.IDLE, "an empty table rests")


func test_public_state() -> void:
	cr.place_bet(1, {"type": "pass", "amount": 10})
	var pub: Dictionary = cr.get_public_state()
	assert_eq(StringName(pub["game"]), &"craps")
	assert_eq(int(pub["shooter"]), 1)
	assert_eq(int(pub["point"]), 0)
	assert_eq((pub["bets"] as Array).size(), 1)
	assert_gt(float(pub["shoot_in"]), 0.0, "SHOOT unlocks in a moment")
	_open_for_shooting()
	assert_eq(float(cr.get_public_state()["shoot_in"]), 0.0)
	cr.player_action(1, &"shoot")
	cr.tick(0.5)
	pub = cr.get_public_state()
	assert_eq(int(pub["state"]), CrapsLogic.State.ROLLING)
	assert_eq((pub["dice"] as Array).size(), 2, "a late joiner sees the dice in the air")
	assert_gt(int(pub["throw_seed"]), 0)
	assert_almost_eq(float(pub["roll_time"]), 0.5, 0.01)
