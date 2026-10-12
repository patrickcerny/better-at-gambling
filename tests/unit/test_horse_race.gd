extends GutTest
## Horse race table (Patrick: "4 horses, 1:4, first to end wins, random names"): the race is a
## pure function of its seed, the first nose over the line wins, a winning bet pays 1:4, bets close
## when the gates open, and every round draws four different names.

var fx: TableFixture
var hr: HorseRaceLogic


func before_each() -> void:
	fx = TableFixture.new(3, [1, 2, 3], 1000)
	hr = fx.make(HorseRaceLogic.new(), &"hr1") as HorseRaceLogic
	hr.join(1)
	hr.join(2)


func _types(evs: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	return evs.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## Runs the table until the race result is in.
func _run_to_result() -> void:
	var guard: int = 0
	while hr.state != HorseRaceLogic.State.RESULT and guard < 2000:
		hr.tick(0.05)
		guard += 1


func test_the_race_is_the_same_for_the_same_seed() -> void:
	var a: Dictionary = HorseRaceLogic.simulate(4242)
	var b: Dictionary = HorseRaceLogic.simulate(4242)
	assert_eq(a["winner"], b["winner"])
	assert_eq(a["finish"], b["finish"])
	for h: int in HorseRaceLogic.HORSES:
		assert_eq(a["frames"][h], b["frames"][h], "lane %d runs the same" % h)
	var c: Dictionary = HorseRaceLogic.simulate(4243)
	assert_ne(a["finish"], c["finish"], "another seed, another race")


func test_winner_is_the_first_to_reach_the_line() -> void:
	for s: int in range(1, 60):
		var plan: Dictionary = HorseRaceLogic.simulate(s * 7919)
		var w: int = plan["winner"]
		var finish: Array = plan["finish"]
		for h: int in HorseRaceLogic.HORSES:
			assert_gt(float(finish[h]), 0.0, "seed %d lane %d finishes" % [s, h])
			if h != w:
				assert_true(float(finish[w]) < float(finish[h]) or (float(finish[w]) == float(finish[h]) and w < h), "seed %d: lane %d is not faster than the winner" % [s, h])
		# Just before the winner's time nobody is at the line; just after, the winner is.
		var before: Array[float] = HorseRaceLogic.sample(plan, float(finish[w]) - 0.11)
		for h: int in HorseRaceLogic.HORSES:
			assert_lt(before[h], HorseRaceLogic.FINISH, "seed %d: lane %d not over yet" % [s, h])
		var after: Array[float] = HorseRaceLogic.sample(plan, float(finish[w]) + 0.11)
		assert_gte(after[w], HorseRaceLogic.FINISH, "seed %d: the winner is over" % s)
		assert_between(float(finish[w]), 6.0, 12.0, "a race lasts about 8-10 s")


func test_races_are_fair_and_the_lead_changes() -> void:
	var wins: Array[int] = [0, 0, 0, 0]
	var changed: int = 0
	var n: int = 400
	for s: int in n:
		var plan: Dictionary = HorseRaceLogic.simulate(100003 + s * 31)
		wins[int(plan["winner"])] += 1
		var leaders: Dictionary = {}
		var t: float = 1.0
		while t < float(plan["finish"][int(plan["winner"])]):
			leaders[HorseRaceLogic.order_of(HorseRaceLogic.sample(plan, t))[0]] = true
			t += 0.25
		if leaders.size() > 1:
			changed += 1
	for h: int in HorseRaceLogic.HORSES:
		assert_between(wins[h], int(n * 0.17), int(n * 0.33), "lane %d wins about a quarter of races: %s" % [h, str(wins)])
	assert_gt(changed, n / 2, "the lead changes hands in most races (%d/%d)" % [changed, n])


func test_names_are_distinct_and_new_each_round() -> void:
	assert_gte(HorseRaceLogic.NAME_POOL.size(), 40)
	var pool: Dictionary = {}
	for name: String in HorseRaceLogic.NAME_POOL:
		assert_false(pool.has(name), "%s once in the pool" % name)
		pool[name] = true
	var rounds: Dictionary = {}
	for i: int in 30:
		var names: Array[String] = HorseRaceLogic.draw_names(fx.rng)
		assert_eq(names.size(), 4)
		var seen: Dictionary = {}
		for n: String in names:
			seen[n] = true
			assert_true(pool.has(n))
		assert_eq(seen.size(), 4, "four different names: %s" % str(names))
		rounds[",".join(names)] = true
	assert_gt(rounds.size(), 20, "the line-up changes from round to round")
	assert_eq(hr.names.size(), 4, "the table shows this round's names")
	assert_eq(hr.get_public_state()["names"], hr.names)


func test_countdown_starts_with_the_first_bet_and_bets_close_at_the_gates() -> void:
	assert_eq(hr.state, HorseRaceLogic.State.BETTING)
	hr.tick(60.0)
	assert_eq(hr.state, HorseRaceLogic.State.BETTING, "no race without a bet")
	assert_false(hr.counting)
	assert_true(hr.place_bet(1, {"horse": 2, "amount": 20})["ok"])
	assert_true(hr.counting)
	assert_almost_eq(hr.timer, fx.balance.horse_countdown, 0.001)
	hr.tick(fx.balance.horse_countdown - 0.1)
	assert_eq(hr.state, HorseRaceLogic.State.BETTING)
	assert_true(hr.place_bet(2, {"horse": 0, "amount": 10})["ok"], "still open just before the gates")
	hr.drain_events()
	hr.tick(0.2)
	assert_eq(hr.state, HorseRaceLogic.State.RACING)
	var evs: Array[Dictionary] = hr.drain_events()
	assert_eq(_types(evs, &"horse_race_started").size(), 1)
	assert_eq(int(_types(evs, &"horse_race_started")[0]["seed"]), hr.race_seed)
	assert_eq(hr.place_bet(1, {"horse": 2, "amount": 10})["error"], &"betting_closed")
	assert_eq(hr.player_action(1, &"clear_bets")["error"], &"betting_closed")
	assert_eq(fx.economy.balance(1), 980, "the stake is in")
	assert_true(hr.has_stake(1))


func test_bet_rules() -> void:
	assert_eq(hr.place_bet(1, {"horse": 4, "amount": 10})["error"], &"invalid_horse")
	assert_eq(hr.place_bet(1, {"horse": -1, "amount": 10})["error"], &"invalid_horse")
	assert_eq(hr.place_bet(1, {"horse": 0, "amount": 5})["error"], &"below_min")
	assert_eq(hr.place_bet(3, {"horse": 0, "amount": 10})["error"], &"not_seated")
	assert_true(hr.place_bet(1, {"horse": 1, "amount": 60})["ok"])
	assert_true(hr.place_bet(1, {"horse": 1, "amount": 40})["ok"], "more on the same horse")
	assert_eq(hr.place_bet(1, {"horse": 1, "amount": 10})["error"], &"above_max")
	assert_eq(hr.place_bet(1, {"horse": 3, "amount": 10})["error"], &"one_horse_only", "no backing the whole field")
	assert_true(hr.player_action(1, &"clear_bets")["ok"])
	assert_eq(fx.economy.balance(1), 1000)
	assert_false(hr.counting, "everyone took their chips back: wait for a new first bet")
	assert_true(hr.place_bet(1, {"horse": 3, "amount": 10})["ok"], "a different horse after clearing")
	hr.limits_multiplier = 2.0
	assert_eq(hr.limits(), Vector2i(20, 200), "limits rise with the segment like every table")


func test_payout_is_one_to_four_and_losers_pay_the_house() -> void:
	assert_true(hr.place_bet(1, {"horse": 0, "amount": 50})["ok"])
	assert_true(hr.place_bet(2, {"horse": 1, "amount": 30})["ok"])
	hr.tick(fx.balance.horse_countdown + 0.01)
	assert_eq(hr.state, HorseRaceLogic.State.RACING)
	# Force a known winner: replay seeds until lane 0 wins (the plan is the seed's).
	var seed_value: int = hr.race_seed
	while int(HorseRaceLogic.simulate(seed_value)["winner"]) != 0:
		seed_value += 1
	hr.race_seed = seed_value
	hr._plan = HorseRaceLogic.simulate(seed_value)
	hr.drain_events()
	_run_to_result()
	assert_eq(hr.winner, 0)
	assert_eq(fx.economy.balance(1), 1000 - 50 + 250, "stake back plus four times it")
	assert_eq(fx.economy.balance(2), 1000 - 30, "the losing stake stays with the house")
	var evs: Array[Dictionary] = hr.drain_events()
	var fin: Array[Dictionary] = _types(evs, &"horse_race_finished")
	assert_eq(fin.size(), 1)
	assert_eq(int(fin[0]["winner"]), 0)
	assert_eq(String(fin[0]["name"]), hr.names[0])
	var results: Array[Dictionary] = _types(evs, &"round_result")
	assert_eq(results.size(), 2)
	for r: Dictionary in results:
		assert_eq(int(r["net"]), 200 if int(r["player"]) == 1 else -30)
	assert_false(hr.has_stake(1))
	# The race was exactly where the plan says when it paid: the winner's nose on the line.
	assert_gte(hr.progress[0], HorseRaceLogic.FINISH)
	# The next round comes with new names.
	var old: Array[String] = hr.names.duplicate()
	hr.tick(fx.balance.horse_result_time + 0.1)
	assert_eq(hr.state, HorseRaceLogic.State.BETTING)
	assert_eq(hr.race_seed, -1)
	assert_eq(_types(hr.drain_events(), &"round_started").size(), 1)
	assert_ne(hr.names, old)


func test_server_progress_follows_the_plan() -> void:
	hr.place_bet(1, {"horse": 2, "amount": 10})
	hr.tick(fx.balance.horse_countdown + 0.01)
	var plan: Dictionary = HorseRaceLogic.simulate(hr.race_seed)
	for i: int in 40:
		hr.tick(0.1)
	var pub: Dictionary = hr.get_public_state()
	var expect: Array[float] = HorseRaceLogic.sample(plan, float(pub["race_time"]))
	for h: int in HorseRaceLogic.HORSES:
		assert_almost_eq(float(pub["progress"][h]), expect[h], 0.002, "lane %d where the plan has it" % h)
		assert_gt(float(pub["progress"][h]), 0.2, "everyone is running")


func test_refund_and_auto_resolve() -> void:
	hr.place_bet(1, {"horse": 0, "amount": 40})
	hr.tick(fx.balance.horse_countdown + 0.01)
	hr.drain_events()
	hr.refund_all()
	assert_eq(fx.economy.balance(1), 1000, "a minigame gives the stake back mid-race")
	assert_eq(hr.state, HorseRaceLogic.State.IDLE)
	var evs: Array[Dictionary] = hr.drain_events()
	assert_eq(_types(evs, &"bets_refunded").size(), 1)
	assert_eq(_types(evs, &"table_reset").size(), 1)
	hr.tick(0.1)
	assert_eq(hr.state, HorseRaceLogic.State.BETTING, "players still seated: a new round")
	hr.place_bet(2, {"horse": 3, "amount": 20})
	hr.auto_resolve()
	assert_eq(hr.state, HorseRaceLogic.State.RESULT, "the match end runs the race at once")
	assert_eq(fx.economy.balance(2), 980 + (100 if hr.winner == 3 else 0))


func test_leaving_mid_race_still_settles() -> void:
	hr.place_bet(1, {"horse": 1, "amount": 10})
	hr.tick(fx.balance.horse_countdown + 0.01)
	hr.leave(1)
	hr.leave(2)
	_run_to_result()
	assert_eq(hr.state, HorseRaceLogic.State.RESULT)
	assert_eq(fx.economy.balance(1), 990 + (50 if hr.winner == 1 else 0))
	hr.tick(fx.balance.horse_result_time + 0.1)
	assert_eq(hr.state, HorseRaceLogic.State.IDLE, "an empty table rests")
