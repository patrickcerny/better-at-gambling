extends GutTest
## The Wheel of Fortune through the real server: sit, put chips on symbols, the dealer spins after
## the countdown, the segment is announced as the wheel slows and every bet pays the printed odds
## through the ledger once it rests. A minigame refunds a spin in flight; a player who stands up
## mid-spin is still paid. The wheel can be the Hot Table and counts in the
## end-of-match stats like every other table.

const SID: StringName = &"wheel_1"

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(4, {"minigames": 2, "gamble_seconds": 100.0, "seed": 11})
	fx.server.start_match()
	fx.run(3.1)


func after_each() -> void:
	fx.server.free()


func _results() -> Array[Dictionary]:
	return fx.of_type(&"round_result").filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID)


func test_registered_on_the_map() -> void:
	assert_true(Registry.games.has(&"wheel"))
	assert_eq(Registry.games[&"wheel"].display_name, "Wheel of Fortune")
	assert_eq(fx.server.map_def.stations.get(SID, &""), &"wheel")
	assert_true(LuckyLounge.STATIONS.has(SID), "the lounge builds it")
	assert_eq(LuckyLounge.STATIONS[SID][0], &"wheel")
	assert_true(fx.server.stations.logics[SID] is WheelLogic)
	assert_true(SID in fx.server.map_def.hot_table_candidates, "can be the Hot Table like the other tables")
	assert_true(fx.server.dealers.has(SID), "a dealer stands at the wheel")
	var pub: Dictionary = fx.server.get_snapshot()["stations"][SID]
	assert_eq(StringName(pub["game"]), &"wheel")
	assert_eq(int(pub["segment"]), -1)


func test_bets_spin_and_payout() -> void:
	var stakes: Array = [[0, 40], [2, 20], [5, 10], [0, 30]]  # symbol, amount per player
	var before: Dictionary = {}
	for i: int in 4:
		var p: int = fx.player_ids[i]
		assert_true(fx.intent(p, &"sit", {"station": SID})["ok"], "player %d sits" % p)
		before[p] = fx.server.economy.balance(p)
		assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"symbol": stakes[i][0], "amount": stakes[i][1]}})["ok"])
		assert_eq(fx.server.economy.balance(p), int(before[p]) - int(stakes[i][1]), "the stake is taken at once")
	assert_true(fx.intent(fx.player_ids[0], &"place_bet", {"station": SID, "bet": {"symbol": 6, "amount": 10}})["ok"], "a second symbol")
	assert_eq(fx.intent(fx.player_ids[1], &"place_bet", {"station": SID, "bet": {"symbol": 9, "amount": 10}})["error"], &"invalid_symbol")
	assert_eq(fx.intent(fx.player_ids[1], &"place_bet", {"station": SID, "bet": {"symbol": 1, "amount": 500}})["error"], &"above_max")
	var logic: WheelLogic = fx.server.stations.logics[SID]
	fx.run(Registry.balance.wheel_countdown + 0.2)
	assert_eq(logic.state, WheelLogic.State.SPINNING, "the dealer spins")
	assert_eq(fx.of_type(&"wheel_spin_started").size(), 1)
	assert_eq(fx.intent(fx.player_ids[0], &"place_bet", {"station": SID, "bet": {"symbol": 0, "amount": 10}})["error"], &"betting_closed")
	assert_eq(fx.of_type(&"wheel_result").size(), 0, "no result while it spins at full speed")
	fx.run(Registry.balance.wheel_spin_time)
	var res: Array[Dictionary] = fx.of_type(&"wheel_result")
	assert_eq(res.size(), 1, "the wheel starts slowing onto the result")
	var seg: int = int(res[0]["segment"])
	var won: int = WheelLogic.symbol_at(seg)
	assert_eq(int(res[0]["symbol"]), won)
	assert_eq(_results().size(), 0, "nothing paid while it slows")
	fx.run(WheelLogic.LAND_TIME + 0.2)
	assert_eq(logic.state, WheelLogic.State.RESULT)
	var results: Array[Dictionary] = _results()
	assert_eq(results.size(), 5, "one result per bet")
	var wins: int = 0
	for r: Dictionary in results:
		var d: Dictionary = r["details"]
		var symbol: int = int(d["symbol"])
		assert_eq(int(d["segment"]), seg)
		if symbol == won:
			var mult: float = float(d.get("multiplier", 1.0))
			var stake: int = int(r["stake"])
			assert_eq(int(r["returned"]), stake + int(floor(stake * WheelLogic.PAYS[symbol] * mult + 0.000001)), "%s pays %s" % [WheelLogic.LABELS[symbol], WheelLogic.odds_text(symbol)])
			wins += 1
		else:
			assert_eq(int(r["returned"]), 0, "a losing symbol goes to the house")
	var ledger: Array[Dictionary] = fx.of_type(&"money_changed").filter(func(e: Dictionary) -> bool: return StringName(e["reason"]) == &"win_wheel")
	assert_eq(ledger.size(), wins, "every payout went through the ledger")
	# Money adds up: what each player has now is their start minus stakes plus what came back.
	for i: int in 4:
		var p: int = fx.player_ids[i]
		var back: int = 0
		var staked: int = 0
		for r: Dictionary in results.filter(func(e: Dictionary) -> bool: return int(e["player"]) == p):
			back += int(r["returned"])
			staked += int(r["stake"])
		assert_eq(fx.server.economy.balance(p), int(before[p]) - staked + back, "player %d" % p)
	var feed_snapshot: Dictionary = fx.server.get_snapshot()["stations"][SID]
	assert_eq(int(feed_snapshot["segment"]), seg, "the result is in the state")
	assert_eq(int((feed_snapshot["history"] as Array)[0]), won)


func test_minigame_refund_mid_spin() -> void:
	var p: int = fx.player_ids[0]
	assert_true(fx.intent(p, &"sit", {"station": SID})["ok"])
	var start: int = fx.server.economy.balance(p)
	assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"symbol": 3, "amount": 30}})["ok"])
	assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"symbol": 5, "amount": 20}})["ok"])
	fx.run(Registry.balance.wheel_countdown + Registry.balance.wheel_spin_time + 1.0)
	assert_true(bool(fx.server.get_snapshot()["stations"][SID]["landing"]), "the wheel is slowing down")
	assert_true(fx.server.stations.has_stake(p))
	fx.server.stations.refund_all()
	assert_eq(fx.server.economy.balance(p), start, "the spin is called off and the stakes come back")
	assert_false(fx.server.stations.has_stake(p))
	fx.run(WheelLogic.LAND_TIME + 1.0)
	var refunds: Array[Dictionary] = fx.of_type(&"bets_refunded").filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID)
	assert_eq(refunds.size(), 1, "the clients hear of it on the next tick")
	if refunds.size() == 1:
		assert_eq(int(refunds[0]["amount"]), 50)
	assert_eq(_results().size(), 0, "a refunded spin never pays")


func test_leaving_mid_spin_still_pays() -> void:
	var p: int = fx.player_ids[1]
	assert_true(fx.intent(p, &"sit", {"station": SID})["ok"])
	var start: int = fx.server.economy.balance(p)
	assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"symbol": 0, "amount": 50}})["ok"])
	fx.run(Registry.balance.wheel_countdown + 0.5)
	assert_true(fx.intent(p, &"leave", {})["ok"], "stands up while the wheel spins")
	assert_true(fx.server.stations.has_stake(p), "the chips stay on the layout")
	fx.run(Registry.balance.wheel_spin_time + WheelLogic.LAND_TIME + 0.5)
	var results: Array[Dictionary] = _results()
	assert_eq(results.size(), 1, "the bet settles without the player")
	assert_eq(fx.server.economy.balance(p), start - 50 + int(results[0]["returned"]))
	assert_false(fx.server.stations.has_stake(p))


func test_stats_count_the_wheel() -> void:
	var p: int = fx.player_ids[2]
	assert_true(fx.intent(p, &"sit", {"station": SID})["ok"])
	assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"symbol": 4, "amount": 100}})["ok"])
	fx.run(Registry.balance.wheel_countdown + Registry.balance.wheel_spin_time + WheelLogic.LAND_TIME + 0.5)
	assert_eq(int(fx.server.stats[p]["biggest_bet"]), 100, "the bet counts in the stats")
	var r: Dictionary = _results()[0]
	if int(r["net"]) > 0:
		assert_eq(int(fx.server.stats[p]["won_by_game"].get(&"wheel", 0)), int(r["net"]), "won at the wheel")
	else:
		assert_eq(int(fx.server.stats[p]["biggest_loss"]), 100)


func test_hot_wheel_multiplies_the_winnings() -> void:
	var p: int = fx.player_ids[3]
	assert_true(fx.intent(p, &"sit", {"station": SID})["ok"])
	var logic: WheelLogic = fx.server.stations.logics[SID]
	fx.server.stations.set_hot(SID, Registry.balance.hot_table_multiplier)
	for s: int in WheelLogic.SYMBOLS.size():
		fx.intent(p, &"place_bet", {"station": SID, "bet": {"symbol": s, "amount": 20}})
	fx.run(Registry.balance.wheel_countdown + 0.2)
	fx.server.stations.set_hot(SID, Registry.balance.hot_table_multiplier)  # as the Hot Table director does
	assert_almost_eq(logic.hot_multiplier, Registry.balance.hot_table_multiplier, 0.0001)
	fx.run(Registry.balance.wheel_spin_time + WheelLogic.LAND_TIME + 0.5)
	var win: Array[Dictionary] = _results().filter(func(e: Dictionary) -> bool: return int(e["net"]) > 0)
	assert_eq(win.size(), 1, "one symbol of seven comes up")
	var symbol: int = int(win[0]["details"]["symbol"])
	assert_eq(int(win[0]["returned"]), 20 + int(floor(20 * WheelLogic.PAYS[symbol] * float(win[0]["details"].get("multiplier", 1.0)) + 0.000001)))
	assert_gt(float(win[0]["details"].get("multiplier", 1.0)), 1.0, "the Hot Table's ×%.2f on the winnings" % Registry.balance.hot_table_multiplier)
