extends GutTest
## The horse race table through the real server: walk up, sit, back a horse, the gates open after
## the countdown, the first horse over the line pays 1:4 through the ledger and everyone else's
## stake stays with the house. Events go out on the normal station path.

const SID: StringName = &"horse_race_1"

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(4, {"minigames": 2, "gamble_seconds": 100.0, "seed": 11})
	fx.server.start_match()
	fx.run(3.1)


func after_each() -> void:
	fx.server.free()


func test_registered_on_the_map() -> void:
	assert_true(Registry.games.has(&"horse_race"))
	assert_eq(fx.server.map_def.stations.get(SID, &""), &"horse_race")
	assert_true(fx.server.stations.logics[SID] is HorseRaceLogic)
	assert_true(SID in fx.server.map_def.hot_table_candidates, "can be the Hot Table like the other tables")
	var pub: Dictionary = fx.server.get_snapshot()["stations"][SID]
	assert_eq(StringName(pub["game"]), &"horse_race")
	assert_eq((pub["names"] as Array).size(), 4, "the board has a line-up before anyone sits")


func test_bet_race_and_payout() -> void:
	var stake: int = 40
	var before: Dictionary = {}
	for i: int in 4:
		var p: int = fx.player_ids[i]
		assert_true(fx.intent(p, &"sit", {"station": SID})["ok"], "player %d sits" % p)
		before[p] = fx.server.economy.balance(p)
		assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"horse": i, "amount": stake}})["ok"])
		assert_eq(fx.server.economy.balance(p), int(before[p]) - stake, "the stake is taken at once")
	assert_eq(fx.of_type(&"horse_race_countdown").size(), 1, "the first bet starts the countdown")
	var logic: HorseRaceLogic = fx.server.stations.logics[SID]
	fx.run(Registry.balance.horse_countdown + 0.2)
	assert_eq(logic.state, HorseRaceLogic.State.RACING, "the gates are open")
	assert_eq(fx.intent(fx.player_ids[0], &"place_bet", {"station": SID, "bet": {"horse": 0, "amount": stake}})["error"], &"betting_closed")
	var started: Array[Dictionary] = fx.of_type(&"horse_race_started")
	assert_eq(started.size(), 1)
	var plan: Dictionary = HorseRaceLogic.simulate(int(started[0]["seed"]))
	var expected_winner: int = int(plan["winner"])
	fx.run(HorseRaceLogic.MAX_SECONDS)
	var finished: Array[Dictionary] = fx.of_type(&"horse_race_finished")
	assert_eq(finished.size(), 1)
	assert_eq(int(finished[0]["winner"]), expected_winner, "every client's replay of the seed has the same winner")
	var results: Array[Dictionary] = fx.of_type(&"round_result").filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID)
	assert_eq(results.size(), 4, "one result per bet")
	for i: int in 4:
		var p: int = fx.player_ids[i]
		var r: Dictionary = results.filter(func(e: Dictionary) -> bool: return int(e["player"]) == p)[0]
		if i == expected_winner:
			var mult: float = float((r["details"] as Dictionary).get("multiplier", 1.0))
			var profit: int = int(floor(stake * Registry.balance.horse_payout_ratio * mult + 0.000001))
			assert_eq(int(r["returned"]), stake + profit, "1:4: the stake back plus four times it")
			assert_eq(fx.server.economy.balance(p), int(before[p]) + profit)
		else:
			assert_eq(int(r["returned"]), 0)
			assert_eq(fx.server.economy.balance(p), int(before[p]) - stake, "a losing stake stays with the house")
	var wins: Array[Dictionary] = fx.of_type(&"money_changed").filter(func(e: Dictionary) -> bool: return StringName(e["reason"]) == &"win_horse_race")
	assert_eq(wins.size(), 1, "the payout went through the ledger")
	assert_eq(int(wins[0]["player"]), fx.player_ids[expected_winner])


func test_minigame_refund_mid_race() -> void:
	var p: int = fx.player_ids[0]
	assert_true(fx.intent(p, &"sit", {"station": SID})["ok"])
	var start: int = fx.server.economy.balance(p)
	assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"horse": 2, "amount": 30}})["ok"])
	fx.run(Registry.balance.horse_countdown + 1.0)
	assert_true(fx.server.stations.has_stake(p))
	fx.server.stations.refund_all()
	assert_eq(fx.server.economy.balance(p), start, "the race is called off and the stake comes back")
	assert_false(fx.server.stations.has_stake(p))
