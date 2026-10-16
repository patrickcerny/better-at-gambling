extends GutTest
## Blackjack split through the real MatchServer (Patrick: "on split, give more time for me and
## actually make it 2 hands"): the splitter's clock is extended, the first hand plays out, then the
## second gets its card and plays, and each hand pays on its own. Everything the clients draw (the
## active hand, both hands' cards, the clock) is in the snapshot.

const SID: StringName = &"blackjack_1"

var fx: ServerFixture
var p: int
var bj: BlackjackLogic


func before_each() -> void:
	fx = ServerFixture.new(2)
	fx.server.start_match()
	fx.run(3.1)  # intro
	fx.place_all()
	p = fx.player_ids[0]
	bj = fx.server.stations.logics[SID] as BlackjackLogic


func after_each() -> void:
	fx.server.free()


func _hand() -> Dictionary:
	var pub: Dictionary = fx.server.get_snapshot()["stations"][SID]
	var hands: Dictionary = pub["hands"]
	for k: Variant in hands:
		if int(k) == p:
			return hands[k]
	return {}


func _act(action: StringName) -> Dictionary:
	return fx.intent(p, &"action", {"station": SID, "action": action})


func test_split_plays_two_hands_in_turn_with_more_time() -> void:
	assert_true(fx.intent(p, &"sit", {"station": SID})["ok"])
	var start: int = fx.server.economy.balance(p)
	assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"amount": 50}})["ok"])
	# p 8,8 ; dealer 10,7 ; hand 1 gets 3 then hits 10 (21) ; hand 2 gets 9 (17)
	var c: Array[int] = [Card.make(8), Card.make(10), Card.make(8), Card.make(7), Card.make(3), Card.make(10), Card.make(9)]
	bj.shoe.stack_top(c)
	fx.run(Registry.balance.bj_betting_window + 0.1)
	assert_eq(bj.state, BlackjackLogic.State.ACTING)
	assert_true(_hand()["can_split"])
	fx.run(6.0)
	var before: float = float(_hand()["clock"])
	assert_true(_act(&"split")["ok"])
	assert_eq(fx.server.economy.balance(p), start - 100, "a second stake for the second hand")
	var h: Dictionary = _hand()
	assert_almost_eq(float(h["clock"]), before + Registry.balance.bj_action_time * Registry.balance.bj_split_time_bonus, 0.06, "the clock grew")
	assert_eq(int(h["active"]), 0, "hand 1 first")
	assert_eq((h["cards"] as Array).size(), 2)
	assert_eq((h["split"]["cards"] as Array).size(), 1, "hand 2 waits for its card")
	var split_ev: Array[Dictionary] = fx.of_type(&"bj_action").filter(func(e: Dictionary) -> bool: return e["action"] == &"split")
	assert_eq(split_ev.size(), 1, "the split reaches every client")
	# Past the original decision time: still playing.
	fx.run(Registry.balance.bj_action_time - 6.0 + 1.0)
	assert_eq(bj.state, BlackjackLogic.State.ACTING, "the extended clock is still running")
	assert_false(bool(_hand()["done"]))
	assert_true(_act(&"hit")["ok"])
	h = _hand()
	assert_eq(int(h["total"]), 21)
	assert_eq(int(h["active"]), 1, "21 on hand 1 moves play to hand 2")
	assert_eq(int(h["split"]["total"]), 17)
	assert_true(_act(&"stand")["ok"])
	assert_eq(bj.state, BlackjackLogic.State.PAYOUT)
	var res: Array[Dictionary] = fx.of_type(&"round_result").filter(func(e: Dictionary) -> bool: return int(e["player"]) == p)
	assert_eq(res.size(), 2, "one result per hand")
	assert_eq(int(res[0]["details"]["hand"]), 0)
	assert_eq(int(res[0]["returned"]), 100, "hand 1: 21 beats 17")
	assert_eq(int(res[1]["details"]["hand"]), 1)
	assert_eq(int(res[1]["returned"]), 50, "hand 2: 17 pushes")
	assert_eq(fx.server.economy.balance(p), start + 50)
	fx.run(Registry.balance.bj_result_time + 0.1)
	assert_eq(bj.state, BlackjackLogic.State.IDLE)


func test_split_hand_times_out_on_the_extended_clock() -> void:
	assert_true(fx.intent(p, &"sit", {"station": SID})["ok"])
	assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"amount": 50}})["ok"])
	var c: Array[int] = [Card.make(8), Card.make(10), Card.make(8), Card.make(7), Card.make(3), Card.make(9)]
	bj.shoe.stack_top(c)
	fx.run(Registry.balance.bj_betting_window + 0.1)
	assert_true(_act(&"split")["ok"])
	var total: float = Registry.balance.bj_action_time * (1.0 + Registry.balance.bj_split_time_bonus)
	fx.run(total - 0.5)
	assert_eq(bj.state, BlackjackLogic.State.ACTING)
	fx.run(1.0)
	assert_eq(bj.state, BlackjackLogic.State.PAYOUT, "out of time: both hands stand")
	assert_eq((bj.hands[p]["split"]["cards"] as Array).size(), 2, "hand 2 still got its second card")
