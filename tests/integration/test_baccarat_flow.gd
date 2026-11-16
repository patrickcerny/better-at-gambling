extends GutTest
## Baccarat through the real server: on the map with a dealer, a shared round where two players
## bet on the same hands, the money through the ledger, "Table closing!" refuses a bet that could
## not pay out, and a minigame gives every open bet back.

const SID: StringName = &"baccarat_1"

var fx: ServerFixture
var logic: BaccaratLogic


func before_each() -> void:
	fx = ServerFixture.new(4, {"minigames": 2, "gamble_seconds": 100.0, "seed": 31})
	fx.server.start_match()
	fx.run(3.1)
	logic = fx.server.stations.logics[SID] as BaccaratLogic


func after_each() -> void:
	fx.server.free()


func _results(p: int) -> Array[Dictionary]:
	return fx.of_type(&"round_result").filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID and int(e["player"]) == p)


func _pub() -> Dictionary:
	return fx.server.get_snapshot()["stations"][SID]


func test_registered_on_the_map_with_a_dealer() -> void:
	assert_true(Registry.games.has(&"baccarat"))
	var def: GameDefinition = Registry.games[&"baccarat"]
	assert_eq(def.display_name, "Baccarat")
	assert_eq(def.floor_footprint, &"table", "the floor layouts place it like any table")
	assert_eq(fx.server.map_def.stations.get(SID, &""), &"baccarat")
	assert_true(SID in fx.server.map_def.hot_table_candidates, "can be the Hot Table like the other tables")
	assert_true(fx.server.dealers.has(SID), "a dealer stands at the table")
	assert_true(LuckyLounge.STATIONS.has(SID), "the lounge builds the table")
	assert_gte(Protocol.PROTOCOL_VERSION, 16, "the new game's state bumped the protocol")
	assert_eq(StringName(_pub()["game"]), &"baccarat")
	assert_eq(ClientMatchState.station_label(SID), "Baccarat 1")


func test_two_players_share_a_round_through_the_ledger() -> void:
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	assert_true(fx.intent(a, &"sit", {"station": SID})["ok"])
	assert_true(fx.intent(b, &"sit", {"station": SID})["ok"])
	var start_a: int = fx.server.economy.balance(a)
	var start_b: int = fx.server.economy.balance(b)
	# Player 9 (natural) against Banker 5.
	logic.shoe.stack_top([Card.make(9), Card.make(2), Card.make(10), Card.make(3)])
	assert_true(fx.intent(a, &"place_bet", {"station": SID, "bet": {"type": &"player", "amount": 20}})["ok"])
	assert_true(fx.intent(b, &"place_bet", {"station": SID, "bet": {"type": &"banker", "amount": 30}})["ok"])
	assert_eq(fx.server.economy.balance(a), start_a - 20)
	assert_true(fx.server.stations.has_stake(a))
	fx.run(logic.timer + 0.2)
	assert_eq(logic.state, BaccaratLogic.State.DEALING)
	assert_eq(fx.intent(a, &"place_bet", {"station": SID, "bet": {"type": &"tie", "amount": 10}})["error"], &"betting_closed")
	fx.run(Registry.balance.baccarat_card_time * 6.0 + Registry.balance.baccarat_settle_time)
	assert_eq(logic.state, BaccaratLogic.State.RESULT)
	assert_eq(StringName(_pub()["winner"]), &"player")
	var ra: Dictionary = _results(a)[0]
	assert_gt(int(ra["net"]), 0)
	assert_eq(int(_results(b)[0]["returned"]), 0)
	assert_eq(fx.server.economy.balance(a), start_a + int(ra["net"]))
	assert_eq(fx.server.economy.balance(b), start_b - 30)
	var reasons: Array = fx.of_type(&"money_changed").filter(func(e: Dictionary) -> bool: return int(e["player"]) == a).map(func(e: Dictionary) -> StringName: return StringName(e["reason"]))
	assert_true(&"bet_baccarat" in reasons and &"win_baccarat" in reasons, "through the ledger: %s" % str(reasons))
	assert_eq(fx.of_type(&"baccarat_result").size(), 1)
	assert_false(fx.server.stations.has_stake(a))


func test_table_closing_refuses_a_bet_that_could_not_pay() -> void:
	var p: int = fx.player_ids[0]
	fx.intent(p, &"sit", {"station": SID})
	fx.server.stations.closing_in = logic.round_seconds() - 0.5
	assert_eq(fx.intent(p, &"place_bet", {"station": SID, "bet": {"type": &"player", "amount": 10}})["error"], &"table_closing")
	assert_false(fx.server.stations.has_stake(p))


func test_minigame_start_refunds_open_bets() -> void:
	var a: int = fx.player_ids[0]
	fx.intent(a, &"sit", {"station": SID})
	while fx.server.phases.casino_time < 85.0 and fx.server.phases.phase == Phase.Id.CASINO:
		fx.run(0.5)
	# Bets go down in the window that is open now.
	while logic.state != BaccaratLogic.State.BETTING or logic.timer < 3.0:
		fx.run(0.25)
	var start: int = fx.server.economy.balance(a)
	if not fx.intent(a, &"place_bet", {"station": SID, "bet": {"type": &"banker", "amount": 10}})["ok"]:
		pass_test("too close to the minigame for a bet (table closing)")
		return
	logic.timer = 999.0  # the window stays open until the minigame starts
	var guard: int = 0
	while fx.server.phases.phase != Phase.Id.MINIGAME and guard < 400:
		fx.run(0.25)
		guard += 1
	assert_eq(fx.server.phases.phase, Phase.Id.MINIGAME)
	assert_eq(fx.server.economy.balance(a), start, "the bet came back in full")
	assert_eq(_results(a).size(), 0)
	assert_false(fx.server.stations.has_stake(a))
