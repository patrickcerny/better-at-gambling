extends GutTest
## Whole-match flow on the authoritative server (§2.1-§2.11): quiz schedule, Last Call, Hot
## Table, House Comp, closing tables, results order, and playing again in the same room.

var fx: ServerFixture


func after_each() -> void:
	if fx != null:
		fx.server.free()
		fx = null


## `minigames` and the gambling seconds before each (Patrick's note #12).
func _fixture(players: int, minigames: int, gamble_s: float, seed_value: int = 1) -> void:
	fx = ServerFixture.new(players, {"minigames": minigames, "gamble_seconds": gamble_s, "seed": seed_value})


## Steps until `cond` holds (or `max_seconds` of game time pass). Returns whether it held.
func _step_until(cond: Callable, max_seconds: float = 2000.0) -> bool:
	var t: float = 0.0
	while not cond.call() and t < max_seconds:
		fx.server._step(MatchServer.TICK)
		fx.server._flush()
		t += MatchServer.TICK
	return cond.call()


func test_minigames_follow_the_schedule() -> void:
	_fixture(2, 2, 100.0)
	fx.server.start_match()
	fx.server.run_to_end()
	assert_eq(fx.of_type(&"minigame_started").size(), 2)
	var mg: Array = fx.of_type(&"phase_changed").filter(func(e: Dictionary) -> bool: return e["phase_name"] == &"minigame").map(func(e: Dictionary) -> float: return e["casino_time"])
	assert_almost_eq(float(mg[0]), 100.0, 0.06)
	assert_almost_eq(float(mg[1]), 200.0, 0.06)
	fx.server.free()
	_fixture(2, 7, 225.0)
	fx.server.start_match()
	fx.server.run_to_end()
	assert_eq(fx.of_type(&"minigame_started").size(), 7)
	assert_eq(fx.of_type(&"quiz_finished").size(), 7)
	assert_eq(fx.of_type(&"match_ended").size(), 1)
	assert_eq(Log.error_count, 0)


func test_last_call_only_in_the_final_minute() -> void:
	_fixture(2, 2, 100.0)
	fx.server.start_match()
	var seen_at: Array[float] = []
	fx.server.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["type"] == &"last_call":
			seen_at.append(fx.server.phases.casino_time))
	assert_true(_step_until(func() -> bool: return fx.server.phases.casino_time >= 230.0))
	assert_eq(fx.server.stations.logics[&"slot_1"].global_multiplier, 1.0, "no boost before the final minute")
	fx.server.run_to_end()
	assert_eq(seen_at.size(), 1)
	assert_almost_eq(seen_at[0], 240.0, 0.06)
	assert_eq(fx.of_type(&"last_call")[0]["multiplier"], 1.5)
	assert_eq(fx.server.stations.logics[&"slot_1"].global_multiplier, 1.0, "reset after the match")


func test_hot_table_rotates_on_casino_time() -> void:
	_fixture(2, 2, 100.0)
	fx.server.start_match()
	var starts: Array[float] = []
	fx.server.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["type"] == &"hot_table":
			starts.append(fx.server.phases.casino_time)
			assert_eq(fx.server.stations.logics[ev["station"]].hot_multiplier, 1.25))
	fx.server.run_to_end()
	assert_gt(starts.size(), 3)
	assert_between(starts[0], 45.0, 60.06)
	for i: int in range(1, starts.size()):
		assert_between(starts[i] - starts[i - 1], 44.94, 60.06)
	var hot: Array[Dictionary] = fx.of_type(&"hot_table")
	for i: int in range(1, hot.size()):
		assert_ne(hot[i]["station"], hot[i - 1]["station"], "never the same table twice in a row")
	assert_eq(fx.of_type(&"hot_table_ended").size(), hot.size(), "every hot table ends (the last at match end)")
	for sid: StringName in fx.server.stations.logics:
		assert_eq(fx.server.stations.logics[sid].hot_multiplier, 1.0)


func test_house_comp_once_per_segment_and_not_with_money_in_play() -> void:
	_fixture(2, 2, 100.0)
	fx.server.start_match()
	fx.run(3.1)
	fx.place_all()
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	# B goes broke on a slot spin: the money is in play, no comp until the spin settles.
	fx.server.economy.apply(b, -(fx.server.economy.balance(b) - 10), &"test")
	fx.server.economy.apply(a, -(fx.server.economy.balance(a) - 5), &"test")
	assert_true(fx.intent(b, &"sit", {"station": &"slot_1"})["ok"])
	assert_true(fx.intent(b, &"place_bet", {"station": &"slot_1", "bet": {"amount": 10}})["ok"])
	fx.run(0.1)
	var comps: Array[Dictionary] = fx.of_type(&"house_comp")
	assert_eq(comps.size(), 1)
	assert_eq(comps[0]["player"], a)
	assert_eq(comps[0]["amount"], 300, "Patrick: $300 before the first minigame")
	assert_eq(fx.server.economy.balance(a), 305)
	fx.server.economy.apply(a, -150, &"test")
	fx.run(1.0)
	assert_eq(fx.of_type(&"house_comp").size(), 1, "only once per segment")
	fx.run(5.0)
	if fx.server.economy.balance(b) < 10:
		assert_eq(fx.of_type(&"house_comp").filter(func(e: Dictionary) -> bool: return e["player"] == b).size(), 1, "comp after the spin lost")
	assert_true(_step_until(func() -> bool: return fx.server.phases.phase == Phase.Id.REWARDS))
	assert_true(_step_until(func() -> bool: return fx.server.phases.phase == Phase.Id.CASINO))
	fx.server.economy.apply(a, -fx.server.economy.balance(a), &"test")
	fx.run(0.1)
	assert_eq(fx.of_type(&"house_comp").filter(func(e: Dictionary) -> bool: return e["player"] == a).size(), 2, "new segment, new comp")
	assert_eq(fx.of_type(&"house_comp").back()["amount"], 450, "$450 after one minigame")
	assert_eq(int(fx.server.stats[a]["comps"]), 2, "the comps stat counts (Comeback award)")


func test_tables_close_before_the_quiz() -> void:
	_fixture(2, 2, 100.0)
	fx.server.start_match()
	fx.run(3.1)
	fx.place_all()
	var a: int = fx.player_ids[0]
	assert_true(fx.intent(a, &"sit", {"station": &"roulette_1"})["ok"])
	assert_true(_step_until(func() -> bool: return fx.server.phases.phase == Phase.Id.PRE_MINIGAME))
	assert_eq(fx.intent(a, &"place_bet", {"station": &"roulette_1", "bet": {"type": &"red", "amount": 10}})["error"], &"table_closing")
	assert_true(fx.intent(a, &"leave")["ok"])
	assert_true(fx.intent(a, &"sit", {"station": &"slot_1"})["ok"])
	assert_true(fx.intent(a, &"place_bet", {"station": &"slot_1", "bet": {"amount": 10}})["ok"], "a quick spin still fits")
	assert_true(_step_until(func() -> bool: return fx.server.phases.phase == Phase.Id.MINIGAME))
	assert_false(fx.server.stations.has_stake(a), "everything settled before the quiz")


func test_standings_tiebreakers() -> void:
	_fixture(3, 2, 100.0)
	var ids: Array[int] = fx.player_ids
	fx.server.state.players[ids[0]].quiz_points = 100
	fx.server.state.players[ids[1]].quiz_points = 900
	fx.server.state.players[ids[2]].quiz_points = 900
	var st: Array[Dictionary] = fx.server.get_standings()
	assert_eq(st[0]["player"], ids[1], "same money: quiz points decide")
	assert_eq(st[0]["rank"], 1)
	assert_eq(st[1]["rank"], 1, "full tie shares the placement")
	assert_eq(st[2]["player"], ids[0])
	assert_eq(st[2]["rank"], 3)
	fx.server.state.players[ids[2]].biggest_win = 50
	st = fx.server.get_standings()
	assert_eq(st[0]["player"], ids[2], "then biggest single win")
	assert_eq(st[1]["rank"], 2)
	fx.server.economy.apply(ids[0], 1, &"test")
	assert_eq(fx.server.get_standings()[0]["player"], ids[0], "money first")


func test_secrets_never_in_snapshots_or_events_during_a_full_match() -> void:
	_fixture(2, 2, 100.0)
	fx.server.start_match()
	var leaks: Array[String] = []
	fx.server.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["type"] in [&"quiz_question", &"quiz_get_ready", &"quiz_answered", &"rewards_started"] and JSON.stringify(ev).contains("correct"):
			leaks.append(str(ev["type"])))
	var checked: int = 0
	while fx.server.running:
		fx.server._step(MatchServer.TICK)
		fx.server._flush()
		var mg: MinigameLogicBase = fx.server.minigame
		if mg is QuizLogic and (mg as QuizLogic).state in [QuizLogic.State.READY, QuizLogic.State.ANSWER]:
			var snap: String = JSON.stringify(fx.server.get_snapshot())
			if snap.contains("correct"):
				leaks.append("snapshot")
			checked += 1
		if fx.server.phases.phase == Phase.Id.REWARDS:
			if JSON.stringify(fx.server.get_private_snapshot(fx.player_ids[0])).contains("draft"):
				leaks.append("a draft in the private snapshot")
	assert_gt(checked, 100)
	assert_eq(leaks, [] as Array[String])


func test_play_again_in_the_same_room() -> void:
	fx = ServerFixture.new(0)
	var s: MatchServer = fx.server
	s.open_lobby()
	var a: int = s.add_player("dev:a", "A")
	var b: int = s.add_player("dev:b", "B")
	var c: int = s.add_player("dev:c", "C")
	fx.player_ids.assign([a, b, c])
	s.start_match()
	s.run_to_end()
	assert_eq(s.phases.phase, Phase.Id.RESULTS)
	assert_almost_eq(s.results_return_in, Registry.balance.results_return_time, 0.01)
	var snap: Dictionary = s.get_snapshot()
	assert_eq((snap["standings"] as Array).size(), 3)
	assert_true(snap.has("awards"))
	assert_eq(fx.intent(b, &"return_to_lobby")["error"], &"not_leader")
	assert_true(fx.intent(a, &"return_to_lobby")["ok"])
	assert_eq(s.phases.phase, Phase.Id.LOBBY)
	assert_eq(fx.of_type(&"match_reset").size(), 1)
	for id: int in s.state.players:
		assert_eq(s.economy.balance(id), Registry.balance.start_money)
		assert_eq(s.state.players[id].inventory.size(), 0)
		assert_eq(s.state.players[id].quiz_points, 0)
	assert_eq(s.state.players.size(), 3, "same people")
	# Second match in the same room.
	s.start_match()
	s.run_to_end()
	assert_eq(fx.of_type(&"match_ended").size(), 2)
	assert_eq(fx.of_type(&"minigame_started").size(), 4)
	# Auto return after the results timer.
	var t: float = 0.0
	while s.phases.phase == Phase.Id.RESULTS and t < 120.0:
		s.advance(0.5)
		t += 0.5
	assert_eq(s.phases.phase, Phase.Id.LOBBY)
	assert_almost_eq(t, Registry.balance.results_return_time, 0.6)
	assert_eq(Log.error_count, 0)


func test_money_history_covers_the_match_for_the_results_graph() -> void:
	_fixture(3, 2, 100.0)
	var ids: Array = fx.server.state.players.keys()
	var start: int = fx.server.balance.start_money
	fx.server.start_match()
	assert_true(_step_until(func() -> bool: return fx.server.phases.casino_time >= 35.0))
	fx.server.economy.apply(int(ids[0]), 400, &"test", &"house")
	fx.server.run_to_end()
	var ended: Array[Dictionary] = fx.of_type(&"match_ended")
	assert_eq(ended.size(), 1)
	var interval: float = MoneyHistory.interval_for(300.0)
	assert_eq(interval, 10.0)
	for row: Dictionary in ended[0]["standings"]:
		var series: Array = row["series"]
		assert_between(series.size(), 30, 33, "a sample every 10 s of casino time plus the final balance")
		assert_eq(int(series[0]), start, "starts at the start money")
		assert_eq(int(series[-1]), int(row["money"]), "ends at the final balance")
		if int(row["player"]) == int(ids[0]):
			assert_eq(int(series[3]), start, "30 s: before the windfall")
			assert_eq(int(series[4]), start + 400, "40 s: after it")
	var snap: Dictionary = fx.server.get_snapshot()
	assert_eq((snap["standings"][0]["series"] as Array).size(), (ended[0]["standings"][0]["series"] as Array).size(), "a late results joiner gets the graph too")


func test_money_history_stays_small_in_long_matches() -> void:
	_fixture(2, 7, 225.0)
	fx.server.start_match()
	fx.server.run_to_end()
	var row: Dictionary = fx.of_type(&"match_ended")[0]["standings"][0]
	assert_lte((row["series"] as Array).size(), MoneyHistory.MAX_SAMPLES + 2)
	assert_eq(int(row["series"][-1]), int(row["money"]))


func test_minigame_start_refunds_everything_and_stands_everyone_up() -> void:
	# Patrick's notes #9 and #21: open bets come back (no loss, no win) and nobody stays seated.
	_fixture(3, 2, 100.0)
	fx.server.start_match()
	fx.run(3.1)
	fx.place_all()
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	var c: int = fx.player_ids[2]
	assert_true(_step_until(func() -> bool: return fx.server.phases.casino_time >= 86.0))
	assert_true(fx.intent(a, &"sit", {"station": &"roulette_1"})["ok"])
	assert_true(fx.intent(b, &"sit", {"station": &"blackjack_1"})["ok"])
	assert_true(fx.intent(c, &"sit", {"station": &"plinko_1"})["ok"])
	var rl: RouletteLogic = fx.server.stations.logics[&"roulette_1"]
	assert_true(_step_until(func() -> bool: return rl.state == RouletteLogic.State.BETTING))
	var before: Dictionary = {a: fx.server.economy.balance(a), b: fx.server.economy.balance(b)}
	assert_true(fx.intent(a, &"place_bet", {"station": &"roulette_1", "bet": {"type": &"red", "amount": 10}})["ok"])
	assert_true(fx.intent(a, &"place_bet", {"station": &"roulette_1", "bet": {"type": &"straight", "value": 7, "amount": 10}})["ok"])
	assert_true(fx.intent(b, &"place_bet", {"station": &"blackjack_1", "bet": {"amount": 50}})["ok"])
	assert_true(_step_until(func() -> bool: return fx.server.phases.phase == Phase.Id.MINIGAME))
	assert_eq(fx.server.economy.balance(a), int(before[a]), "roulette bets came back in full")
	var bj_paid: bool = fx.of_type(&"round_result").any(func(e: Dictionary) -> bool: return int(e["player"]) == b)
	if not bj_paid:
		assert_eq(fx.server.economy.balance(b), int(before[b]), "the open hand came back")
	for id: int in fx.player_ids:
		assert_false(fx.server.stations.is_seated(id), "stood up for the minigame")
		assert_false(fx.server.stations.has_stake(id))
		assert_eq(fx.server.state.players[id].station, &"")
	var refunds: Array[Dictionary] = fx.of_type(&"bets_refunded")
	assert_true(refunds.any(func(e: Dictionary) -> bool: return int(e["player"]) == a and int(e["amount"]) == 20))
	var stood: Array[Dictionary] = fx.of_type(&"player_stood").filter(func(e: Dictionary) -> bool: return e.get("reason", &"") == &"minigame")
	assert_eq(stood.size(), 3)
	# Refund first, then the stand-up (blackjack would otherwise auto-stand the hand).
	assert_lt(int(refunds[0]["seq"]), int(stood[0]["seq"]))
	var total: int = 0
	for id: int in fx.player_ids:
		total += fx.server.economy.balance(id)
	assert_eq(fx.server.economy.ledger.total(), total)
	assert_eq(Log.error_count, 0)


func test_after_the_rewards_everyone_regroups_in_the_hall() -> void:
	_fixture(2, 2, 100.0)
	var def: MapDefinition = fx.server.map_def.duplicate() as MapDefinition
	def.lobby_spawns = LuckyLounge.LOBBY_SPAWNS.duplicate()
	fx.server.map_def = def
	fx.server.start_match()
	fx.run(3.1)
	fx.place_all(Vector3(3, 0, -5))
	assert_true(_step_until(func() -> bool: return fx.server.phases.phase == Phase.Id.REGROUP))
	var casino_at: float = fx.server.phases.casino_time
	var ev: Dictionary = fx.of_type(&"regroup_started")[0]
	assert_almost_eq(float(ev["seconds"]), Registry.balance.regroup_time, 0.001)
	for id: int in fx.player_ids:
		assert_eq(fx.server.world.get_position(id), def.lobby_spawn(id), "everyone in the hall")
		assert_true((ev["positions"] as Dictionary).has(id))
	assert_eq(fx.intent(fx.player_ids[0], &"sit", {"station": &"slot_1"})["error"], &"wrong_phase", "no sitting while the doors are shut")
	var t0: float = fx.server.match_time
	assert_true(_step_until(func() -> bool: return fx.server.phases.phase == Phase.Id.CASINO))
	assert_almost_eq(fx.server.match_time - t0, Registry.balance.regroup_time, 0.06)
	assert_almost_eq(fx.server.phases.casino_time, casino_at, 0.001, "casino time doesn't run during the regroup")
	var names: Array = fx.of_type(&"phase_changed").map(func(e: Dictionary) -> StringName: return e["phase_name"])
	var i: int = names.find(&"rewards")
	assert_eq(names.slice(i, i + 3), [&"rewards", &"regroup", &"casino"])


func test_regroup_snapshot_for_late_joiners_and_reconnects() -> void:
	_fixture(2, 2, 100.0)
	fx.server.start_match()
	assert_true(_step_until(func() -> bool: return fx.server.phases.phase == Phase.Id.REGROUP))
	var a: int = fx.player_ids[0]
	fx.server.player_disconnected(a)
	fx.server.player_reconnected(a)
	var snap: Dictionary = fx.server.get_snapshot()
	assert_eq(int(snap["phase"]), Phase.Id.REGROUP)
	assert_between(float(snap["regroup_in"]), 0.0, Registry.balance.regroup_time)
	var st := ClientMatchState.new()
	st.apply_snapshot(snap)
	assert_eq(st.phase, Phase.Id.REGROUP)
	assert_gt(st.regroup_in, 0.0)
	assert_eq(st.minigames, 2)
	assert_almost_eq(st.duration_s, 300.0, 0.01)


func test_house_comp_on_the_reward_rows_grows_per_minigame() -> void:
	_fixture(2, 3, 60.0)
	fx.server.start_match()
	fx.run(3.1)
	var a: int = fx.player_ids[0]
	var seen: Array[int] = []
	for round_i: int in 3:
		assert_true(_step_until(func() -> bool: return fx.server.phases.phase == Phase.Id.MINIGAME))
		fx.server.economy.apply(a, -fx.server.economy.balance(a), &"test")
		assert_true(_step_until(func() -> bool: return fx.server.phases.phase == Phase.Id.REWARDS))
		var rows: Array = fx.of_type(&"rewards_started").back()["rewards"]
		for row: Dictionary in rows:
			if int(row["player"]) == a:
				seen.append(int(row.get("comp", 0)))
		assert_true(_step_until(func() -> bool: return fx.server.phases.phase == Phase.Id.CASINO))
	assert_eq(seen, [450, 600, 750] as Array[int], "$450 after the 1st minigame, $600 after the 2nd, $750 after the 3rd")
	var mine: Array[Dictionary] = fx.of_type(&"house_comp").filter(func(e: Dictionary) -> bool: return int(e["player"]) == a)
	assert_eq(mine.size(), 3, "never paid twice in a segment")
	assert_eq(int(fx.server.stats[a]["comps"]), 3)
