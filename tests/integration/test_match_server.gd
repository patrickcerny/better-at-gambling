extends GutTest
## In-process MatchServer: scripted intents sit at every station type, bet, play, and the phase
## machine runs a whole 5-minute match with money conservation.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(2)
	fx.server.start_match()
	fx.run(3.1)  # intro
	fx.place_all()


func after_each() -> void:
	fx.server.free()


func test_phase_sequence_for_5_minute_match() -> void:
	assert_eq(fx.server.phases.phase, Phase.Id.CASINO)
	fx.server.run_to_end()
	var names: Array = fx.of_type(&"phase_changed").map(func(e: Dictionary) -> StringName: return e["phase_name"])
	assert_eq(names, [&"intro", &"casino", &"pre_minigame", &"minigame", &"rewards", &"regroup", &"casino", &"pre_minigame", &"minigame", &"rewards", &"regroup", &"casino", &"results"])
	assert_eq(fx.of_type(&"regroup_started").size(), 2)
	assert_eq(fx.of_type(&"minigame_started").size(), 2)
	assert_eq(fx.of_type(&"quiz_finished").size(), 2)
	assert_eq(fx.of_type(&"rewards_started").size(), 2)
	assert_eq(fx.of_type(&"last_call").size(), 1)
	var ended: Array[Dictionary] = fx.of_type(&"match_ended")
	assert_eq(ended.size(), 1)
	assert_eq((ended[0]["standings"] as Array).size(), 2)
	assert_almost_eq(fx.server.phases.casino_time, 300.0, 0.06)
	assert_false(fx.server.running)
	assert_eq(Log.error_count, 0)


func test_segments_end_exactly_on_schedule() -> void:
	fx.server.run_to_end()
	var segs: Array = fx.of_type(&"segment_ended")
	assert_eq(segs.size(), 3)
	var times: Array = fx.of_type(&"phase_changed").filter(func(e: Dictionary) -> bool: return e["phase_name"] == &"minigame").map(func(e: Dictionary) -> float: return e["casino_time"])
	assert_almost_eq(float(times[0]), 100.0, 0.06)
	assert_almost_eq(float(times[1]), 200.0, 0.06)


func test_sit_bet_play_blackjack_via_intents() -> void:
	var p: int = fx.player_ids[0]
	assert_eq(fx.intent(p, &"place_bet", {"station": &"blackjack_1", "bet": {"amount": 50}})["error"], &"not_seated")
	assert_true(fx.intent(p, &"sit", {"station": &"blackjack_1"})["ok"])
	assert_eq(fx.intent(p, &"sit", {"station": &"blackjack_2"})["error"], &"already_seated")
	assert_eq(fx.intent(p, &"move", {"pos": [1, 0, 0], "yaw": 0.0})["error"], &"not_standing")
	assert_true(fx.intent(p, &"place_bet", {"station": &"blackjack_1", "bet": {"amount": 50}})["ok"])
	assert_eq(fx.server.economy.balance(p), 950)
	fx.run(8.1)
	var bj: BlackjackLogic = fx.server.stations.logics[&"blackjack_1"] as BlackjackLogic
	assert_eq(bj.state, BlackjackLogic.State.ACTING if not bj.hands.is_empty() and not bj.hands[p]["done"] else bj.state)
	if bj.state == BlackjackLogic.State.ACTING:
		assert_true(fx.intent(p, &"action", {"station": &"blackjack_1", "action": &"stand"})["ok"])
	fx.run(2.1)
	assert_eq(bj.state, BlackjackLogic.State.IDLE)
	var results: Array[Dictionary] = fx.of_type(&"round_result")
	assert_eq(results.size(), 1)
	assert_eq(fx.server.economy.balance(p), 950 + int(results[0]["returned"]))
	assert_true(fx.intent(p, &"leave")["ok"])
	assert_true(fx.intent(p, &"move", {"pos": [1, 0, 0], "yaw": 0.0})["ok"])


func test_every_station_type_accepts_a_bet() -> void:
	var p: int = fx.player_ids[0]
	var bets: Dictionary = {&"roulette_1": {"type": &"red", "amount": 10}, &"slot_1": {"amount": 25}, &"plinko_1": {"amount": 10, "risk": &"low"}}
	for sid: StringName in bets:
		assert_true(fx.intent(p, &"sit", {"station": sid})["ok"], str(sid))
		assert_true(fx.intent(p, &"place_bet", {"station": sid, "bet": bets[sid]})["ok"], str(sid))
		fx.run(20.0)
		assert_true(fx.intent(p, &"leave")["ok"])
	assert_eq(fx.of_type(&"round_result").size(), 3)
	# Money conservation: every change is in the ledger with a reason.
	var ledger_total: int = fx.server.economy.ledger.total()
	var balances: int = 0
	for id: int in fx.player_ids:
		balances += fx.server.economy.balance(id)
	assert_eq(ledger_total, balances)
	for e: Dictionary in fx.server.economy.ledger.entries:
		assert_ne(e["reason"], &"")


func test_leave_mid_round_auto_resolves_and_money_matches_snapshot() -> void:
	var p: int = fx.player_ids[0]
	fx.intent(p, &"sit", {"station": &"roulette_1"})
	fx.intent(p, &"place_bet", {"station": &"roulette_1", "bet": {"type": &"black", "amount": 100}})
	fx.intent(p, &"leave")
	fx.run(25.0)
	assert_eq(fx.of_type(&"round_result").size(), 1)
	var snap: Dictionary = fx.server.get_snapshot()
	assert_eq(int(snap["balances"][p]), fx.server.economy.balance(p))
	assert_true(Serializer.is_wire_safe(snap))


func test_vip_requires_money_and_wrong_phase_rejected() -> void:
	var p: int = fx.player_ids[0]
	assert_eq(fx.intent(p, &"sit", {"station": &"vip_blackjack_1"})["error"], &"vip_denied")
	fx.server.economy.apply(p, 2000, &"test")
	assert_true(fx.intent(p, &"sit", {"station": &"vip_blackjack_1"})["ok"])
	assert_eq(fx.server.stations.logics[&"vip_blackjack_1"].limits_multiplier, 3.0)
	fx.intent(p, &"leave")
	fx.server.run_to_end()
	assert_eq(fx.intent(p, &"sit", {"station": &"blackjack_1"})["ok"], true, "sitting allowed at results")
	assert_eq(fx.intent(p, &"place_bet", {"station": &"blackjack_1", "bet": {"amount": 10}})["error"], &"wrong_phase")


func test_malformed_unknown_and_rate_limited() -> void:
	var p: int = fx.player_ids[0]
	assert_eq(fx.server.submit_intent(p, {"type": &"sit"})["error"], &"malformed")
	assert_eq(fx.server.submit_intent(99, Intents.make(&"leave"))["error"], &"unknown_player")
	var rejected: int = 0
	for i: int in 40:
		if fx.intent(p, &"emote", {"id": &"wave"})["error"] == &"rate_limited":
			rejected += 1
	assert_eq(rejected, 20)
	fx.run(1.0)
	assert_true(fx.intent(p, &"emote", {"id": &"wave"})["ok"])
	assert_eq(fx.intent(p, &"emote", {"id": &"moon"})["error"], &"unknown_emote")
	assert_eq(fx.intent(p, &"emote", {"id": 7})["error"], &"unknown_emote")


func test_snapshot_round_trips_into_client_state() -> void:
	var p: int = fx.player_ids[0]
	fx.intent(p, &"sit", {"station": &"slot_3"})
	var cs := ClientMatchState.new()
	cs.apply_snapshot(bytes_to_var(var_to_bytes(fx.server.get_snapshot())))
	assert_eq(cs.phase, Phase.Id.CASINO)
	assert_eq(cs.balance(p), 1000)
	assert_eq(cs.seat_of[p], &"slot_3")
	assert_eq(cs.players.size(), 2)
	assert_true(cs.stations.has("slot_3"))
	assert_eq(cs.rank_of(p), 1)
	for ev: Dictionary in fx.events:
		assert_true(Serializer.is_wire_safe(ev), str(ev["type"]))
