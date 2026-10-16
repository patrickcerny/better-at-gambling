extends GutTest
## All-in on the real server (Patrick: "when you try to bet more than you currently have, just bet
## the max amount (all you have)"): at every table a bet over the balance is taken at the balance,
## a bet over the table max at the max, and only a balance under the table minimum is refused.
## The `bet_placed` event carries the real amount and `all_in` for every client.

var fx: ServerFixture
var p: int


func before_each() -> void:
	fx = ServerFixture.new(2, {"minigames": 2, "gamble_seconds": 100.0, "seed": 5})
	fx.server.start_match()
	fx.run(3.1)
	p = fx.player_ids[0]


func after_each() -> void:
	fx.server.free()


## Leaves the player with exactly `money`.
func _set_money(money: int) -> void:
	var bal: int = fx.server.economy.balance(p)
	assert_true(fx.server.economy.apply(p, money - bal, &"test_setup"))
	assert_eq(fx.server.economy.balance(p), money)


func _sit(sid: StringName) -> void:
	var pos: Variant = fx.server.map_def.station_positions.get(sid, null)
	if pos != null:
		fx.server.world.set_transform(p, Vector3(pos), 0.0)
	assert_true(fx.intent(p, &"sit", {"station": sid})["ok"], "sits at %s" % sid)


func _bet(sid: StringName, bet: Dictionary) -> Dictionary:
	return fx.intent(p, &"place_bet", {"station": sid, "bet": bet})


func _last_bet_placed() -> Dictionary:
	var placed: Array[Dictionary] = fx.of_type(&"bet_placed")
	return placed.back() if not placed.is_empty() else {}


func _check_all_in(sid: StringName, bet: Dictionary, money: int) -> void:
	_set_money(money)
	fx.events.clear()
	var res: Dictionary = _bet(sid, bet)
	assert_true(res["ok"], "%s: a bet over the balance is accepted (%s)" % [sid, res])
	assert_eq(fx.server.economy.balance(p), 0, "%s: everything went in" % sid)
	var ev: Dictionary = _last_bet_placed()
	assert_eq(int(ev.get("amount", -1)), money, "%s: bet_placed carries the real amount" % sid)
	assert_true(bool((ev.get("details", {}) as Dictionary).get("all_in", false)), "%s: and says all-in" % sid)
	assert_eq(int((ev.get("details", {}) as Dictionary).get("requested", 0)), int(bet["amount"]), "%s: and what was asked" % sid)


func test_blackjack() -> void:
	var sid: StringName = &"blackjack_1"
	_sit(sid)
	var lim: Vector2i = (fx.server.stations.logics[sid] as BlackjackLogic).limits()
	_set_money(lim.x - 1)
	assert_eq(_bet(sid, {"amount": lim.y})["error"], &"insufficient_funds", "under the minimum is still refused")
	_check_all_in(sid, {"amount": lim.y}, lim.x + 7)


func test_blackjack_over_the_max_bets_the_max() -> void:
	var sid: StringName = &"blackjack_1"
	_sit(sid)
	var lim: Vector2i = (fx.server.stations.logics[sid] as BlackjackLogic).limits()
	_set_money(lim.y * 5)
	fx.events.clear()
	assert_true(_bet(sid, {"amount": lim.y * 3})["ok"])
	assert_eq(fx.server.economy.balance(p), lim.y * 4, "the table max went in")
	assert_eq(int(_last_bet_placed()["amount"]), lim.y)
	assert_false(bool((_last_bet_placed()["details"] as Dictionary).get("all_in", false)), "capped by the table, not all-in")


func test_blackjack_client_cannot_fake_all_in() -> void:
	var sid: StringName = &"blackjack_1"
	_sit(sid)
	_set_money(500)
	fx.events.clear()
	assert_true(_bet(sid, {"amount": 50, "all_in": true, "requested": 9999})["ok"])
	assert_false(bool((_last_bet_placed()["details"] as Dictionary).get("all_in", false)), "the server decides all-in")


func test_roulette() -> void:
	var sid: StringName = &"roulette_1"
	_sit(sid)
	var logic: RouletteLogic = fx.server.stations.logics[sid]
	var lim: Vector2i = logic.limits()
	_set_money(lim.x - 1)
	assert_eq(_bet(sid, {"type": &"red", "amount": lim.x * 5})["error"], &"insufficient_funds")
	_check_all_in(sid, {"type": &"red", "amount": lim.x * 5}, lim.x + 3)


func test_roulette_over_the_spin_total_bets_what_is_left() -> void:
	var sid: StringName = &"roulette_1"
	_sit(sid)
	var lim: Vector2i = (fx.server.stations.logics[sid] as RouletteLogic).limits()
	_set_money(lim.y * 2)
	assert_true(_bet(sid, {"type": &"red", "amount": lim.y - lim.x * 2})["ok"])
	fx.events.clear()
	assert_true(_bet(sid, {"type": &"black", "amount": lim.y})["ok"], "over the max total: what is left goes in")
	assert_eq(int(_last_bet_placed()["amount"]), lim.x * 2)
	assert_eq(fx.server.economy.balance(p), lim.y, "exactly the max total is on the table")
	assert_eq(_bet(sid, {"type": &"black", "amount": lim.x})["error"], &"above_max", "a full table refuses as before")


func test_horse_race() -> void:
	var sid: StringName = &"horse_race_1"
	_sit(sid)
	var logic: HorseRaceLogic = fx.server.stations.logics[sid]
	var lim: Vector2i = logic.limits()
	_set_money(lim.x - 1)
	assert_eq(_bet(sid, {"horse": 1, "amount": lim.y})["error"], &"insufficient_funds")
	_check_all_in(sid, {"horse": 1, "amount": lim.y}, lim.x + 4)


func test_horse_race_over_the_max_bets_the_max() -> void:
	var sid: StringName = &"horse_race_1"
	_sit(sid)
	var lim: Vector2i = (fx.server.stations.logics[sid] as HorseRaceLogic).limits()
	_set_money(lim.y * 3)
	fx.events.clear()
	assert_true(_bet(sid, {"horse": 2, "amount": lim.y * 2})["ok"])
	assert_eq(int(_last_bet_placed()["amount"]), lim.y)


func test_slots() -> void:
	var sid: StringName = &"slot_1"
	_sit(sid)
	var sizes: Array[int] = (fx.server.stations.logics[sid] as SlotsLogic).bet_sizes()
	_set_money(sizes[0] - 1)
	assert_eq(_bet(sid, {"amount": sizes[1]})["error"], &"insufficient_funds")
	_check_all_in(sid, {"amount": sizes[sizes.size() - 1]}, sizes[0] + 2)
	assert_eq((fx.server.stations.logics[sid] as SlotsLogic).stake, sizes[0] + 2, "the spin plays for the all-in stake")


func test_slots_unlisted_size_still_refused() -> void:
	var sid: StringName = &"slot_1"
	_sit(sid)
	assert_eq(_bet(sid, {"amount": 37, "all_in": true})["error"], &"invalid_amount")


func test_plinko() -> void:
	var sid: StringName = &"plinko_1"
	_sit(sid)
	var sizes: Array[int] = (fx.server.stations.logics[sid] as PlinkoLogic).bet_sizes()
	_set_money(sizes[0] - 1)
	assert_eq(_bet(sid, {"amount": sizes[2], "risk": &"low"})["error"], &"insufficient_funds")
	_check_all_in(sid, {"amount": sizes[2], "risk": &"low"}, sizes[1] + 1)
	fx.run(Registry.balance.plinko_flight_time + 0.5)
	var results: Array[Dictionary] = fx.of_type(&"round_result")
	assert_eq(results.size(), 1)
	assert_eq(int(results[0]["stake"]), sizes[1] + 1, "the drop settles on the all-in stake")


func test_below_min_request_is_refused() -> void:
	var sid: StringName = &"blackjack_1"
	_sit(sid)
	var lim: Vector2i = (fx.server.stations.logics[sid] as BlackjackLogic).limits()
	assert_eq(_bet(sid, {"amount": lim.x - 1})["error"], &"below_min")
