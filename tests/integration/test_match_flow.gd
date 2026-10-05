extends GutTest
## Whole-match flow on the authoritative server (§2.1-§2.11): quiz schedule, Last Call, Hot
## Table, House Comp, closing tables, results order, and playing again in the same room.

var fx: ServerFixture


func after_each() -> void:
	if fx != null:
		fx.server.free()
		fx = null


func _fixture(players: int, duration: int, seed_value: int = 1) -> void:
	fx = ServerFixture.new(players, {"duration": duration, "seed": seed_value})


## Steps until `cond` holds (or `max_seconds` of game time pass). Returns whether it held.
func _step_until(cond: Callable, max_seconds: float = 2000.0) -> bool:
	var t: float = 0.0
	while not cond.call() and t < max_seconds:
		fx.server._step(MatchServer.TICK)
		fx.server._flush()
		t += MatchServer.TICK
	return cond.call()


func test_quizzes_follow_the_schedule_for_5_and_30_minutes() -> void:
	_fixture(2, 5)
	fx.server.start_match()
	fx.server.run_to_end()
	assert_eq(fx.of_type(&"minigame_started").size(), 2)
	var mg: Array = fx.of_type(&"phase_changed").filter(func(e: Dictionary) -> bool: return e["phase_name"] == &"minigame").map(func(e: Dictionary) -> float: return e["casino_time"])
	assert_almost_eq(float(mg[0]), 100.0, 0.06)
	assert_almost_eq(float(mg[1]), 200.0, 0.06)
	fx.server.free()
	_fixture(2, 30)
	fx.server.start_match()
	fx.server.run_to_end()
	assert_eq(fx.of_type(&"minigame_started").size(), 7)
	assert_eq(fx.of_type(&"quiz_finished").size(), 7)
	assert_eq(fx.of_type(&"match_ended").size(), 1)
	assert_eq(Log.error_count, 0)


func test_last_call_only_in_the_final_minute() -> void:
	_fixture(2, 5)
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
	_fixture(2, 5)
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
	_fixture(2, 5)
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
	assert_eq(fx.server.economy.balance(a), 155)
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
	assert_eq(fx.of_type(&"house_comp").back()["amount"], 150)


func test_tables_close_before_the_quiz() -> void:
	_fixture(2, 5)
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
	_fixture(3, 5)
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
	_fixture(2, 5)
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
			if JSON.stringify(fx.server.get_snapshot()).contains("choices"):
				leaks.append("draft offers in public snapshot")
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
