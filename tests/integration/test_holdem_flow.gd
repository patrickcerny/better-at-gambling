extends GutTest
## Casino Hold'em through the real server: sit, ante (and the AA Bonus), the deal after the
## betting window, FOLD or CALL through the ledger, the clock running out folds, "Table closing!"
## refuses a hand that could not finish, a minigame gives every open ante and call back (a bonus
## the flop settled stays settled), and standing up mid-hand folds.

const SID: StringName = &"holdem_1"

var fx: ServerFixture
var logic: HoldemLogic


func before_each() -> void:
	fx = ServerFixture.new(4, {"minigames": 2, "gamble_seconds": 100.0, "seed": 31})
	fx.server.start_match()
	fx.run(3.1)
	logic = fx.server.stations.logics[SID] as HoldemLogic


func after_each() -> void:
	fx.server.free()


func _c(name: String) -> int:
	var suit: int = "SHDC".find(name.right(1))
	var r: String = name.left(name.length() - 1)
	var rank: int = {"A": 1, "J": 11, "Q": 12, "K": 13}.get(r, 0) if not r.is_valid_int() else int(r)
	return Card.make(rank, suit)


func _rig(names: String) -> void:
	var out: Array[int] = []
	for n: String in names.split(" ", false):
		out.append(_c(n))
	logic.rigged = out


func _results(p: int) -> Array[Dictionary]:
	return fx.of_type(&"round_result").filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID and int(e["player"]) == p)


func _pub() -> Dictionary:
	return fx.server.get_snapshot()["stations"][SID]


func _hand(p: int) -> Dictionary:
	return HoldemStation.hand_of(_pub()["hands"], p)


func _deal() -> void:
	fx.run(Registry.balance.holdem_betting_window + 0.2)
	assert_eq(logic.state, HoldemLogic.State.DECIDING, "dealt")


func test_registered_on_the_map_with_a_dealer() -> void:
	assert_true(Registry.games.has(&"holdem"))
	var def: GameDefinition = Registry.games[&"holdem"]
	assert_eq(def.display_name, "Casino Hold'em")
	assert_eq(def.floor_footprint, &"table", "the floor layouts place it like any table")
	assert_eq(fx.server.map_def.stations.get(SID, &""), &"holdem")
	assert_true(SID in fx.server.map_def.hot_table_candidates, "can be the Hot Table like the other tables")
	assert_true(logic.hot_table_candidate())
	assert_true(fx.server.dealers.has(SID), "a dealer stands at the table")
	assert_true(LuckyLounge.STATIONS.has(SID), "the lounge builds the table")
	assert_gte(Protocol.PROTOCOL_VERSION, 11, "the new events and state bumped the protocol")
	var pub: Dictionary = _pub()
	assert_eq(StringName(pub["game"]), &"holdem")
	assert_eq((pub["seats"] as Array).size(), 4)
	assert_eq(ClientMatchState.station_label(SID), "Casino Hold'em 1")


func test_ante_bonus_call_and_win_through_the_ledger() -> void:
	var p: int = fx.player_ids[0]
	assert_true(fx.intent(p, &"sit", {"station": SID})["ok"])
	var start: int = fx.server.economy.balance(p)
	# Aces in the hole (the AA Bonus pays 7:1 on the flop), the dealer's fours qualify and lose.
	_rig("AS AD 9C 5H 2S KD 7C 4C 4D")
	assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"amount": 20, "bonus": 10}})["ok"])
	assert_eq(fx.server.economy.balance(p), start - 30, "ante and bonus taken at once")
	assert_true(fx.server.stations.has_stake(p))
	assert_eq(fx.intent(p, &"action", {"station": SID, "action": &"call"})["error"], &"wrong_state", "nothing to call before the deal")
	_deal()
	var h: Dictionary = _hand(p)
	assert_eq(h["hole"], [_c("AS"), _c("AD")])
	assert_eq(String(h["hand"]), "Pair of Aces", "named live")
	assert_eq((_pub()["board"] as Array).size(), 3)
	assert_eq((_pub()["dealer"] as Array).size(), 0, "nothing of the dealer's cards on the wire")
	var bonus: Dictionary = _results(p)[0]
	assert_eq(int(bonus["returned"]), 80, "the AA Bonus settled with the flop")
	assert_true(fx.intent(p, &"action", {"station": SID, "action": &"call"})["ok"])
	var main: Dictionary = _results(p)[1]
	assert_eq(StringName(main["details"]["outcome"]), &"win")
	var mult: float = float((main["details"] as Dictionary).get("multiplier", 1.0))
	var paid: int = 60 + int(floor(60 * mult + 0.000001))
	assert_eq(int(main["returned"]), paid, "ante 1:1 and call 1:1 (times any hot table / Last Call)")
	var bmult: float = float((bonus["details"] as Dictionary).get("multiplier", 1.0))
	assert_eq(fx.server.economy.balance(p), start - 30 - 40 + (10 + int(floor(70 * bmult + 0.000001))) + paid)
	var reasons: Array = fx.of_type(&"money_changed").filter(func(e: Dictionary) -> bool: return int(e["player"]) == p).map(func(e: Dictionary) -> StringName: return StringName(e["reason"]))
	assert_true(&"bet_holdem" in reasons and &"win_holdem" in reasons, "through the ledger: %s" % str(reasons))
	assert_eq(fx.of_type(&"holdem_showdown").size(), 1)
	assert_false(fx.server.stations.has_stake(p))
	fx.run(Registry.balance.holdem_result_time + 0.2)
	assert_eq(logic.state, HoldemLogic.State.IDLE, "the felt clears after the showdown")


func test_fold_and_the_clock() -> void:
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	fx.intent(a, &"sit", {"station": SID})
	fx.intent(b, &"sit", {"station": SID})
	var start_a: int = fx.server.economy.balance(a)
	var start_b: int = fx.server.economy.balance(b)
	assert_true(fx.intent(a, &"place_bet", {"station": SID, "bet": {"amount": 10}})["ok"])
	assert_true(fx.intent(b, &"place_bet", {"station": SID, "bet": {"amount": 30}})["ok"])
	_deal()
	assert_true(fx.intent(a, &"action", {"station": SID, "action": &"fold"})["ok"])
	assert_eq(fx.server.economy.balance(a), start_a - 10, "the ante is lost")
	assert_eq(StringName(_hand(a)["decision"]), &"fold")
	# b never decides: the clock runs out and the hand folds, like at the real table.
	fx.run(Registry.balance.holdem_action_time + 0.3)
	assert_eq(StringName(_results(b)[0]["details"]["outcome"]), &"fold")
	assert_eq(fx.server.economy.balance(b), start_b - 30)
	assert_eq(fx.of_type(&"holdem_showdown").size(), 1, "the dealer still turns over")


func test_table_closing_refuses_a_hand_that_could_not_finish() -> void:
	var p: int = fx.player_ids[0]
	fx.intent(p, &"sit", {"station": SID})
	fx.server.stations.closing_in = logic.round_seconds() - 0.5
	assert_eq(fx.intent(p, &"place_bet", {"station": SID, "bet": {"amount": 10}})["error"], &"table_closing")
	assert_false(fx.server.stations.has_stake(p))


func test_minigame_start_refunds_open_bets_and_keeps_a_settled_bonus() -> void:
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	fx.intent(a, &"sit", {"station": SID})
	fx.intent(b, &"sit", {"station": SID})
	# Close to the minigame, but still early enough for a hand to start.
	while fx.server.phases.casino_time < 80.0 and fx.server.phases.phase == Phase.Id.CASINO:
		fx.run(0.5)
	var start_a: int = fx.server.economy.balance(a)
	var start_b: int = fx.server.economy.balance(b)
	_rig("AS AH 9C 5H 2S 7D JC")
	assert_true(fx.intent(a, &"place_bet", {"station": SID, "bet": {"amount": 20, "bonus": 10}})["ok"])
	assert_true(fx.intent(b, &"place_bet", {"station": SID, "bet": {"amount": 10}})["ok"])
	_deal()
	assert_true(fx.intent(a, &"action", {"station": SID, "action": &"call"})["ok"])
	for p: int in [a, b]:  # keep b's clock from folding the hand meanwhile
		if logic.hands.has(p):
			logic.hands[p]["clock"] = 999.0
	var guard: int = 0
	while fx.server.phases.phase != Phase.Id.MINIGAME and guard < 400:
		fx.run(0.25)
		guard += 1
		if logic.hands.has(b):
			logic.hands[b]["clock"] = 999.0
	assert_eq(fx.server.phases.phase, Phase.Id.MINIGAME)
	var bonus: Dictionary = _results(a)[0]
	assert_eq(StringName(bonus["details"]["type"]), &"bonus")
	assert_eq(fx.server.economy.balance(a), start_a - 10 + int(bonus["returned"]), "ante and call back, the won bonus kept")
	assert_eq(fx.server.economy.balance(b), start_b, "b's ante came back in full")
	assert_eq(_results(a).size(), 1, "the hand itself was never settled")
	var refunds: Array[Dictionary] = fx.of_type(&"bets_refunded").filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID)
	assert_eq(refunds.size(), 2)
	for p: int in [a, b]:
		assert_false(fx.server.stations.has_stake(p))
		assert_false(fx.server.stations.is_seated(p), "stood up for the minigame")
	assert_true(logic.hands.is_empty(), "the felt is cleared")


func test_standing_up_mid_hand_folds() -> void:
	var p: int = fx.player_ids[2]
	var q: int = fx.player_ids[3]
	fx.intent(p, &"sit", {"station": SID})
	fx.intent(q, &"sit", {"station": SID})
	var start: int = fx.server.economy.balance(p)
	fx.intent(p, &"place_bet", {"station": SID, "bet": {"amount": 20}})
	fx.intent(q, &"place_bet", {"station": SID, "bet": {"amount": 20}})
	_deal()
	assert_true(fx.intent(p, &"leave")["ok"])
	assert_eq(StringName(_results(p)[0]["details"]["outcome"]), &"fold", "walking away folds")
	assert_eq(fx.server.economy.balance(p), start - 20)
	assert_false(fx.server.stations.has_stake(p))
	assert_true(fx.intent(p, &"sit", {"station": SID})["ok"], "the seat is free again")
	# A called hand left behind plays on to the showdown.
	assert_true(fx.intent(q, &"action", {"station": SID, "action": &"call"})["ok"])
	assert_eq(_results(q).size(), 1)
	assert_ne(StringName(_results(q)[0]["details"]["outcome"]), &"fold")
