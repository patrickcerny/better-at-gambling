extends GutTest
## The Hi-Lo table through the real server: sit, ante, the card comes up with its odds, a right
## call grows the pot, riding grows it again, cashing out pays it through the ledger; a wrong call
## loses it. A minigame gives fresh antes back and banks won pots; standing up mid-hand settles
## it.

const SID: StringName = &"hilo_1"

var fx: ServerFixture
var logic: HiLoLogic


func before_each() -> void:
	fx = ServerFixture.new(4, {"minigames": 2, "gamble_seconds": 100.0, "seed": 23})
	fx.server.start_match()
	fx.run(3.1)
	logic = fx.server.stations.logics[SID] as HiLoLogic


func after_each() -> void:
	fx.server.free()


## Puts `cards` on top of the table's deck so they are dealt in this order.
func _stack(cards: Array[int]) -> void:
	for i: int in range(cards.size() - 1, -1, -1):
		logic.deck.erase(cards[i])
		logic.deck.append(cards[i])


func _results(p: int) -> Array[Dictionary]:
	return fx.of_type(&"round_result").filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID and int(e["player"]) == p)


func _hand(p: int) -> Dictionary:
	return HiLoStation.hand_of(fx.server.get_snapshot()["stations"][SID]["hands"], p)


func test_registered_on_the_map_with_a_dealer() -> void:
	assert_true(Registry.games.has(&"hilo"))
	assert_eq(Registry.games[&"hilo"].display_name, "Hi-Lo")
	assert_eq(fx.server.map_def.stations.get(SID, &""), &"hilo")
	assert_true(logic != null)
	assert_true(SID in fx.server.map_def.hot_table_candidates, "can be the Hot Table like the other tables")
	assert_true(fx.server.dealers.has(SID), "a dealer stands at the table")
	assert_true(LuckyLounge.STATIONS.has(SID), "the lounge builds the table")
	var pub: Dictionary = fx.server.get_snapshot()["stations"][SID]
	assert_eq(StringName(pub["game"]), &"hilo")
	assert_eq((pub["seats"] as Array).size(), 4)
	assert_eq(int(pub["deck_left"]), 52)


func test_ante_call_ride_and_cash_out_through_the_ledger() -> void:
	var p: int = fx.player_ids[0]
	assert_true(fx.intent(p, &"sit", {"station": SID})["ok"])
	var start: int = fx.server.economy.balance(p)
	_stack([Card.make(5), Card.make(9, 1), Card.make(3, 2)])
	assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"amount": 40}})["ok"])
	assert_eq(fx.server.economy.balance(p), start - 40, "the ante is taken at once")
	assert_true(fx.server.stations.has_stake(p))
	var h: Dictionary = _hand(p)
	assert_eq(h["cards"], [Card.make(5)])
	var odds: Dictionary = h["odds"]
	assert_almost_eq(float(odds["higher"]) + float(odds["lower"]) + float(odds["tie"]), 1.0, 0.0001)
	assert_almost_eq(float(odds["higher"]), 36.0 / 51.0, 0.0001, "the snapshot carries the true chance")
	var pay1: float = float(h["pays"]["higher"])
	assert_eq(pay1, HiLoLogic.pay_for(36.0 / 51.0, Registry.balance), "and the pay the server will use")
	assert_true(fx.intent(p, &"action", {"station": SID, "action": &"higher"})["ok"], "5 then 9")
	h = _hand(p)
	assert_eq(int(h["rung"]), 1)
	assert_eq(fx.server.economy.balance(p), start - 40, "nothing is paid while the pot can still ride")
	var pay2: float = float(h["pays"]["lower"])
	assert_true(fx.intent(p, &"action", {"station": SID, "action": &"lower"})["ok"], "9 then 3: the ride comes in")
	h = _hand(p)
	assert_eq(int(h["rung"]), 2)
	var pot: int = int(floor(40 * pay1 * pay2 + 0.000001))
	assert_eq(int(h["pot"]), pot)
	assert_true(fx.intent(p, &"action", {"station": SID, "action": &"cash_out"})["ok"])
	var r: Dictionary = _results(p)[0]
	var mult: float = float((r["details"] as Dictionary).get("multiplier", 1.0))
	var paid: int = 40 + int(floor((pot - 40) * mult + 0.000001))
	assert_eq(int(r["returned"]), paid)
	assert_eq(StringName(r["details"]["outcome"]), &"cashed")
	assert_eq(fx.server.economy.balance(p), start - 40 + paid)
	var wins: Array[Dictionary] = fx.of_type(&"money_changed").filter(func(e: Dictionary) -> bool: return StringName(e["reason"]) == &"win_hilo")
	assert_eq(wins.size(), 1, "the payout went through the ledger")
	assert_false(fx.server.stations.has_stake(p))
	assert_eq(fx.of_type(&"hilo_call").size(), 2)


func test_a_wrong_call_loses_and_the_house_keeps_the_ante() -> void:
	var p: int = fx.player_ids[1]
	fx.intent(p, &"sit", {"station": SID})
	var start: int = fx.server.economy.balance(p)
	# Ace up, call lower, the next two are aces: a tie loses even if the house redraws once.
	_stack([Card.make(1), Card.make(1, 1), Card.make(1, 2)])
	assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"amount": 25}})["ok"])
	assert_eq(fx.intent(p, &"action", {"station": SID, "action": &"higher"})["error"], &"no_chance", "nothing beats an ace")
	assert_eq(fx.intent(p, &"action", {"station": SID, "action": &"cash_out"})["error"], &"nothing_to_cash")
	assert_true(fx.intent(p, &"action", {"station": SID, "action": &"lower"})["ok"])
	assert_eq(fx.server.economy.balance(p), start - 25)
	assert_eq(int(_results(p)[0]["returned"]), 0)
	assert_eq(StringName(_hand(p)["outcome"]), &"lose")
	fx.run(Registry.balance.hilo_result_time + 0.2)
	assert_true(_hand(p).is_empty(), "the felt clears after the result")


func test_minigame_start_gives_fresh_antes_back_and_banks_won_pots() -> void:
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	fx.intent(a, &"sit", {"station": SID})
	fx.intent(b, &"sit", {"station": SID})
	while fx.server.phases.casino_time < 90.0:
		fx.run(0.5)
		for p: int in [a, b]:  # keep the call timer from playing the hands meanwhile
			if logic.hands.has(p):
				logic.hands[p]["timer"] = 99.0
	var start_a: int = fx.server.economy.balance(a)
	var start_b: int = fx.server.economy.balance(b)
	_stack([Card.make(4), Card.make(10), Card.make(6, 3)])
	assert_true(fx.intent(b, &"place_bet", {"station": SID, "bet": {"amount": 30}})["ok"])
	assert_true(fx.intent(b, &"action", {"station": SID, "action": &"higher"})["ok"], "4 then 10")
	var pot: int = int(_hand(b)["pot"])
	assert_true(fx.intent(a, &"place_bet", {"station": SID, "bet": {"amount": 20}})["ok"], "6 up, no call yet")
	var guard: int = 0
	while fx.server.phases.phase != Phase.Id.MINIGAME and guard < 400:
		fx.run(0.25)
		guard += 1
		for p: int in [a, b]:
			if logic.hands.has(p):
				logic.hands[p]["timer"] = 99.0
	assert_eq(fx.server.phases.phase, Phase.Id.MINIGAME)
	assert_eq(fx.server.economy.balance(a), start_a, "a's ante came back in full")
	var r: Dictionary = _results(b)[0]
	assert_eq(fx.server.economy.balance(b), start_b - 30 + int(r["returned"]), "b's won pot was banked")
	assert_gte(int(r["returned"]), pot, "at least the pot (a hot table or Last Call can add to it)")
	var refunds: Array[Dictionary] = fx.of_type(&"bets_refunded").filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID)
	assert_eq(refunds.size(), 1)
	assert_eq(int(refunds[0]["player"]), a)
	assert_eq(int(refunds[0]["amount"]), 20)
	for p: int in [a, b]:
		assert_false(fx.server.stations.has_stake(p))
		assert_false(fx.server.stations.is_seated(p), "stood up for the minigame")
	assert_true(logic.hands.is_empty(), "the felt is cleared")


func test_standing_up_mid_hand_settles_it() -> void:
	var p: int = fx.player_ids[2]
	fx.intent(p, &"sit", {"station": SID})
	var start: int = fx.server.economy.balance(p)
	_stack([Card.make(3), Card.make(12)])
	fx.intent(p, &"place_bet", {"station": SID, "bet": {"amount": 50}})
	fx.intent(p, &"action", {"station": SID, "action": &"higher"})
	var pot: int = int(_hand(p)["pot"])
	assert_true(fx.intent(p, &"leave")["ok"])
	var r: Dictionary = _results(p)[0]
	assert_eq(StringName(r["details"]["outcome"]), &"cashed", "the won pot is cashed out on the way out")
	assert_gte(int(r["returned"]), pot)
	assert_eq(fx.server.economy.balance(p), start - 50 + int(r["returned"]))
	assert_false(fx.server.stations.has_stake(p))
	# A fresh ante left behind is called for you (the likelier side) and settles at once.
	fx.intent(p, &"sit", {"station": SID})
	fx.intent(p, &"place_bet", {"station": SID, "bet": {"amount": 20}})
	fx.intent(p, &"leave")
	assert_eq(_results(p).size(), 2)
	assert_false(fx.server.stations.has_stake(p))
