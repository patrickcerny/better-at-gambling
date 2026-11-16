extends GutTest
## Out of Order through the real MatchServer (Patrick 0.9.71: "out of order stops any game and
## refunds the money", "until the next minigame"): the round at that table stops at once, every
## stake in play (split and doubled hands included, a spinning wheel too) goes back to its owner,
## nobody stays seated, the refund is no loss for the streak luck or the match stats, and the sign
## comes down when the next minigame starts.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(3, {"minigames": 2, "gamble_seconds": 100.0, "seed": 8})
	fx.server.start_match()
	fx.run(3.1)
	fx.place_all()
	fx.server.map_def = fx.server.map_def.duplicate(true)


func after_each() -> void:
	fx.server.free()


func _step_until(cond: Callable, max_seconds: float = 2000.0) -> bool:
	var t: float = 0.0
	while not cond.call() and t < max_seconds:
		fx.server._step(MatchServer.TICK)
		fx.server._flush()
		t += MatchServer.TICK
	return cond.call()


## `user` hangs the sign on `sid` (moved far away from every other station so it is the nearest).
func _hang_sign(user: int, sid: StringName) -> void:
	var pos: Vector3 = Vector3(500, 0, 500)
	fx.server.map_def.station_positions[sid] = pos
	fx.server.world.set_transform(user, pos, 0.0)
	fx.server.items.give(user, &"out_of_order", fx.server.match_time)
	var r: Dictionary = fx.intent(user, &"use_item", {"slot": 0})
	assert_true(r["ok"], str(r))


func _total_money() -> int:
	var total: int = 0
	for id: int in fx.player_ids:
		total += fx.server.economy.balance(id)
	return total


func test_split_and_doubled_blackjack_hand_comes_back_in_full() -> void:
	var sid: StringName = &"blackjack_1"
	var p: int = fx.player_ids[0]
	var q: int = fx.player_ids[1]
	var bj: BlackjackLogic = fx.server.stations.logics[sid] as BlackjackLogic
	assert_true(fx.intent(p, &"sit", {"station": sid})["ok"])
	var start: int = fx.server.economy.balance(p)
	var stats_before: Dictionary = fx.server.stats[p].duplicate(true)
	var streak_before: float = fx.server.modifiers.streak_luck(p)
	assert_true(fx.intent(p, &"place_bet", {"station": sid, "bet": {"amount": 50}})["ok"])
	# p 8,8 ; dealer 10,7 ; hand 1 gets 3 (11, doubled: draws 2) ; hand 2 gets 9
	var c: Array[int] = [Card.make(8), Card.make(10), Card.make(8), Card.make(7), Card.make(3), Card.make(2), Card.make(9)]
	bj.shoe.stack_top(c)
	fx.run(Registry.balance.bj_betting_window + 0.1)
	assert_eq(bj.state, BlackjackLogic.State.ACTING)
	assert_true(fx.intent(p, &"action", {"station": sid, "action": &"split"})["ok"])
	assert_true(fx.intent(p, &"action", {"station": sid, "action": &"double"})["ok"])
	assert_eq(fx.server.economy.balance(p), start - 150, "stake + split + double in play")
	assert_eq(bj.state, BlackjackLogic.State.ACTING, "hand 2 still to play")
	_hang_sign(q, sid)
	assert_eq(fx.server.economy.balance(p), start, "every stake came back")
	assert_eq(bj.state, BlackjackLogic.State.IDLE, "the round stopped")
	assert_true(bj.hands.is_empty())
	assert_false(fx.server.stations.is_seated(p), "stood up")
	assert_false(fx.server.stations.has_stake(p))
	assert_eq(fx.server.state.players[p].station, &"")
	var refunds: Array[Dictionary] = fx.of_type(&"bets_refunded").filter(func(e: Dictionary) -> bool: return int(e["player"]) == p)
	assert_eq(refunds.size(), 1)
	assert_eq(int(refunds[0]["amount"]), 150)
	assert_false(fx.of_type(&"table_reset").filter(func(e: Dictionary) -> bool: return e["station"] == sid).is_empty(), "clients clear the felt")
	var stood: Array[Dictionary] = fx.of_type(&"player_stood").filter(func(e: Dictionary) -> bool: return e.get("reason", &"") == &"out_of_order")
	assert_eq(stood.size(), 1)
	assert_lt(int(refunds[0]["seq"]), int(stood[0]["seq"]), "refund before the stand-up")
	assert_false(fx.of_type(&"round_result").any(func(e: Dictionary) -> bool: return int(e["player"]) == p), "no result: no win, no loss")
	assert_eq(fx.server.modifiers.streak_luck(p), streak_before, "a refund is no loss for the streak luck")
	assert_eq(int(fx.server.stats[p]["losing_now"]), int(stats_before["losing_now"]))
	assert_eq(int(fx.server.stats[p]["hands"]), int(stats_before["hands"]))
	# Closed: nobody sits, a minute later still nobody.
	assert_eq(fx.server.stations.sit(p, sid)["error"], &"out_of_order")
	fx.run(60.0)
	assert_eq(fx.server.stations.sit(p, sid)["error"], &"out_of_order")
	assert_eq(fx.server.economy.ledger.total(), _total_money())
	assert_eq(Log.error_count, 0)


func test_spinning_roulette_refunds_everyone_and_reopens_at_the_minigame() -> void:
	var sid: StringName = &"roulette_1"
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	var user: int = fx.player_ids[2]
	var rl: RouletteLogic = fx.server.stations.logics[sid] as RouletteLogic
	assert_true(fx.intent(a, &"sit", {"station": sid})["ok"])
	assert_true(fx.intent(b, &"sit", {"station": sid})["ok"])
	assert_true(_step_until(func() -> bool: return rl.state == RouletteLogic.State.BETTING, 60.0))
	var before: Dictionary = {a: fx.server.economy.balance(a), b: fx.server.economy.balance(b)}
	assert_true(fx.intent(a, &"place_bet", {"station": sid, "bet": {"type": &"red", "amount": 30}})["ok"])
	assert_true(fx.intent(a, &"place_bet", {"station": sid, "bet": {"type": &"straight", "value": 7, "amount": 10}})["ok"])
	assert_true(fx.intent(b, &"place_bet", {"station": sid, "bet": {"type": &"black", "amount": 25}})["ok"])
	assert_true(_step_until(func() -> bool: return rl.state == RouletteLogic.State.SPINNING, 60.0))
	_hang_sign(user, sid)
	assert_eq(rl.state, RouletteLogic.State.IDLE, "the wheel stopped")
	assert_true(rl.bets.is_empty())
	assert_eq(fx.server.economy.balance(a), int(before[a]))
	assert_eq(fx.server.economy.balance(b), int(before[b]))
	for id: int in [a, b]:
		assert_false(fx.server.stations.is_seated(id))
	assert_false(fx.of_type(&"round_result").any(func(e: Dictionary) -> bool: return e["station"] == sid))
	# A second sign can't go on a table that is already closed.
	assert_eq(fx.server._nearest_station(user, 4.0), &"")
	# The next minigame takes the sign down.
	assert_true(_step_until(func() -> bool: return fx.server.phases.phase == Phase.Id.MINIGAME))
	assert_false(fx.server.stations.out_of_order.has(sid))
	assert_false(fx.server.stations.public_states()[sid].has("out_of_order"))
	assert_eq(fx.server.economy.ledger.total(), _total_money())
	assert_eq(Log.error_count, 0)
