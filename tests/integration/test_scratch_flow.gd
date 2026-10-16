extends GutTest
## The scratch-card kiosk through the real server: sit at the counter, buy a card (one event
## carries it), reveal it and the printed prize pays through the ledger; a minigame refunds an open
## card; walking away mid-card pays it; one player at a time; the Hot Table and the stats see it
## like any other station.

const SID: StringName = &"scratch_1"

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(2, {"minigames": 2, "gamble_seconds": 100.0, "seed": 13})
	fx.server.start_match()
	fx.run(3.1)


func after_each() -> void:
	fx.server.free()


func _sit(p: int) -> Dictionary:
	var pos: Variant = fx.server.map_def.station_positions.get(SID, null)
	if pos != null:
		fx.server.world.set_transform(p, Vector3(pos), 0.0)
	return fx.intent(p, &"sit", {"station": SID})


func test_registered_on_the_map() -> void:
	assert_true(Registry.games.has(&"scratch"))
	assert_eq(Registry.games[&"scratch"].logic_script, ScratchLogic)
	assert_eq(fx.server.map_def.stations.get(SID, &""), &"scratch")
	assert_true(fx.server.stations.logics[SID] is ScratchLogic)
	assert_true(SID in fx.server.map_def.hot_table_candidates, "can be the Hot Table like the slots")
	assert_eq(LuckyLounge.STATIONS[SID][0], &"scratch")
	var pub: Dictionary = fx.server.get_snapshot()["stations"][SID]
	assert_eq(StringName(pub["game"]), &"scratch")
	assert_eq(pub["card"], [])


func test_buy_reveal_and_payout() -> void:
	var p: int = fx.player_ids[0]
	assert_true(_sit(p)["ok"])
	assert_eq(_sit(fx.player_ids[1])["error"], &"seat_taken", "one player at the counter")
	var before: int = fx.server.economy.balance(p)
	assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"tier": 1}})["ok"])
	assert_eq(fx.server.economy.balance(p), before - 25, "the card's price is taken at once")
	var bought: Array[Dictionary] = fx.of_type(&"scratch_card")
	assert_eq(bought.size(), 1, "one event carries the card")
	var card: Array[int] = []
	card.assign(bought[0]["card"])
	assert_eq(card.size(), 9)
	assert_eq(fx.server.get_snapshot()["stations"][SID]["card"], card, "the state has the same card")
	assert_eq(fx.intent(p, &"place_bet", {"station": SID, "bet": {"tier": 0}})["error"], &"card_open")
	fx.run(5.0)
	assert_eq(fx.server.economy.balance(p), before - 25, "nothing pays while it is under the foil")
	assert_true(fx.server.stations.has_stake(p))
	assert_true(fx.intent(p, &"action", {"station": SID, "action": &"reveal"})["ok"])
	var res: Array[Dictionary] = fx.of_type(&"round_result").filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID)
	assert_eq(res.size(), 1)
	var printed: int = ScratchLogic.prize(25, ScratchLogic.card_multiplier(card, 1, Registry.balance))
	var returned: int = int(res[0]["returned"])
	if printed > 25:
		var mult: float = float((res[0]["details"] as Dictionary).get("multiplier", 1.0))
		assert_eq(returned, 25 + int(floor((printed - 25) * mult + 0.000001)), "the printed prize (× any multiplier)")
	else:
		assert_eq(returned, printed, "the printed prize")
	assert_eq(fx.server.economy.balance(p), before - 25 + returned)
	if returned > 0:
		var pays: Array[Dictionary] = fx.of_type(&"money_changed").filter(func(e: Dictionary) -> bool: return int(e["player"]) == p and String(e["reason"]).ends_with("_scratch"))
		assert_gt(pays.size(), 0, "paid through the ledger")
	assert_false(fx.server.stations.has_stake(p))
	assert_eq(fx.server.get_snapshot()["stations"][SID]["card"], [])
	# A few more, each through the ledger: the money adds up to the printed prizes.
	var start: int = fx.server.economy.balance(p)
	var expected: int = start
	fx.server.stations.set_hot(&"", 1.0)
	for i: int in 6:
		var t: int = i % 3
		assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"tier": t}})["ok"])
		var c: Array[int] = []
		c.assign(fx.of_type(&"scratch_card").back()["card"])
		var price: int = Registry.balance.scratch_prices[t]
		expected += -price + ScratchLogic.prize(price, ScratchLogic.card_multiplier(c, t, Registry.balance))
		assert_true(fx.intent(p, &"action", {"station": SID, "action": &"reveal"})["ok"])
	assert_eq(fx.server.economy.balance(p), expected, "every card paid exactly its printed prize")


func test_minigame_refund_mid_card() -> void:
	var p: int = fx.player_ids[0]
	assert_true(_sit(p)["ok"])
	var start: int = fx.server.economy.balance(p)
	assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"tier": 2}})["ok"])
	assert_true(fx.server.stations.has_stake(p))
	fx.server.stations.refund_all()
	fx.run(0.1)
	assert_eq(fx.server.economy.balance(p), start, "the card is called off and the price comes back")
	assert_false(fx.server.stations.has_stake(p))
	assert_eq(fx.of_type(&"bets_refunded").filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID).size(), 1)
	assert_eq(fx.intent(p, &"action", {"station": SID, "action": &"reveal"})["error"], &"no_card")


func test_the_minigame_start_refunds_the_open_card() -> void:
	var p: int = fx.player_ids[0]
	assert_true(_sit(p)["ok"])
	var guard: int = 0
	while fx.server.phases.phase != Phase.Id.PRE_MINIGAME and guard < 400:
		fx.run(0.5)
		guard += 1
	# Bought in the warning before the minigame (an earlier card would have scratched itself).
	assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"tier": 0}})["ok"])
	while fx.server.phases.phase != Phase.Id.MINIGAME and guard < 800:
		fx.run(0.5)
		guard += 1
	assert_eq(fx.server.phases.phase, Phase.Id.MINIGAME)
	assert_eq(fx.of_type(&"round_result").filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID).size(), 0, "it never paid")
	var refunds: Array[Dictionary] = fx.of_type(&"bets_refunded").filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID)
	assert_eq(refunds.size(), 1, "the price came back when the minigame started")
	assert_eq(int(refunds[0]["amount"]), 10)
	assert_false(fx.server.stations.has_stake(p))


func test_leaving_mid_card_pays_it() -> void:
	var p: int = fx.player_ids[0]
	assert_true(_sit(p)["ok"])
	var before: int = fx.server.economy.balance(p)
	assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"tier": 0}})["ok"])
	var card: Array[int] = []
	card.assign(fx.of_type(&"scratch_card")[0]["card"])
	assert_true(fx.intent(p, &"leave")["ok"])
	var res: Array[Dictionary] = fx.of_type(&"round_result").filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID)
	assert_eq(res.size(), 1, "walking away scratches it for you")
	assert_eq(fx.server.economy.balance(p), before - 10 + int(res[0]["returned"]))
	assert_false(fx.server.stations.has_stake(p))
	assert_true(_sit(fx.player_ids[1])["ok"], "the counter is free for the next player")


func test_stats_count_the_kiosk() -> void:
	var p: int = fx.player_ids[0]
	assert_true(_sit(p)["ok"])
	for i: int in 12:
		fx.intent(p, &"place_bet", {"station": SID, "bet": {"tier": 2}})
		fx.intent(p, &"action", {"station": SID, "action": &"reveal"})
	var st: Dictionary = fx.server.stats[p]
	assert_eq(int(st["biggest_bet"]), 50, "the card price counts as a bet")
	var won: int = 0
	for e: Dictionary in fx.of_type(&"round_result"):
		if int(e["player"]) == p and int(e["net"]) > 0:
			won += int(e["net"])
	assert_eq(int((st["won_by_game"] as Dictionary).get(&"scratch", 0)), won, "winnings by game")
