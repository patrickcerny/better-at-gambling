extends GutTest
## Sword Tapper through the real server: step up to the pedestal, pull (one `sword_pull` event
## carries the whole pull), the sword stays stuck or comes free, and the lit gems pay through the
## ledger when the reveal ends; walking away or a minigame pays an open pull at once (never a
## refund); a pull that could not finish before the casino closes is refused ("Table closing!");
## all-in pulls with what fits; luck shifts what the pedestal pays; it never turns into the Hot Table.

const SID: StringName = &"sword_1"
const SWORDS: Array[StringName] = [&"sword_1", &"sword_2"]

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(2, {"minigames": 2, "gamble_seconds": 100.0, "seed": 21})
	fx.server.start_match()
	fx.run(3.1)


func after_each() -> void:
	fx.server.free()


func _logic() -> SwordTapperLogic:
	return fx.server.stations.logics[SID] as SwordTapperLogic


func _sit(p: int, sid: StringName = SID) -> Dictionary:
	var pos: Variant = fx.server.map_def.station_positions.get(sid, null)
	if pos != null:
		fx.server.world.set_transform(p, Vector3(pos), 0.0)
	return fx.intent(p, &"sit", {"station": sid})


func _pull(p: int, amount: int) -> Dictionary:
	return fx.intent(p, &"place_bet", {"station": SID, "bet": {"amount": amount}})


## Pays the open pull now (as walking away would) and hands its events out.
func _resolve() -> void:
	_logic().auto_resolve()
	fx.server._flush()


func _set_money(p: int, money: int) -> void:
	assert_true(fx.server.economy.apply(p, money - fx.server.economy.balance(p), &"test_setup"))


func _here(type: StringName) -> Array[Dictionary]:
	return fx.of_type(type).filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID)


func _event_pull(ev: Dictionary) -> Dictionary:
	return {"free": ev["free"], "gems": ev["gems"], "mult": ev["mult"]}


func test_registered_on_the_map() -> void:
	assert_true(Registry.games.has(&"sword_tapper"))
	assert_eq(Registry.games[&"sword_tapper"].logic_script, SwordTapperLogic)
	assert_gte(Protocol.PROTOCOL_VERSION, 10, "the new event and state bumped the protocol (to 10; later tables bump it again)")
	for sid: StringName in SWORDS:
		assert_eq(fx.server.map_def.stations.get(sid, &""), &"sword_tapper")
		assert_true(fx.server.stations.logics[sid] is SwordTapperLogic)
		assert_false(sid in fx.server.map_def.hot_table_candidates, "never a Hot Table candidate")
		assert_false(fx.server.stations.logics[sid].hot_table_candidate())
		assert_eq(LuckyLounge.STATIONS[sid][0], &"sword_tapper")
	var pub: Dictionary = fx.server.get_snapshot()["stations"][SID]
	assert_eq(StringName(pub["game"]), &"sword_tapper")
	assert_false(pub["pulling"])
	assert_eq(int(pub["serial"]), 0)


func test_the_hot_table_never_lands_on_a_pedestal() -> void:
	var seen: Dictionary = {}
	for i: int in 60:
		fx.server.hot_tables.tick(1000.0)
		var cur: StringName = fx.server.hot_tables.current
		seen[cur] = true
		assert_false(cur in SWORDS, "the pedestal is never drawn")
		for sid: StringName in SWORDS:
			assert_eq(fx.server.stations.logics[sid].hot_multiplier, 1.0, "and never pays hot")
	assert_gt(seen.size(), 5, "the draw still moves around the other tables")


func test_a_pull_pays_when_the_reveal_ends() -> void:
	var p: int = fx.player_ids[0]
	assert_true(_sit(p)["ok"])
	assert_eq(_sit(fx.player_ids[1])["error"], &"seat_taken", "one player per pedestal")
	assert_true(_sit(fx.player_ids[1], &"sword_2")["ok"], "the other pedestal is free")
	var before: int = fx.server.economy.balance(p)
	assert_eq(_pull(p, 5)["error"], &"below_min")
	assert_true(_pull(p, 40)["ok"])
	assert_eq(fx.server.economy.balance(p), before - 40, "the stake is taken at the tap")
	var evs: Array[Dictionary] = _here(&"sword_pull")
	assert_eq(evs.size(), 1, "one event carries the pull")
	var ev: Dictionary = evs[0]
	assert_eq(int(ev["player"]), p)
	assert_eq(int(ev["stake"]), 40)
	assert_eq(int(ev["serial"]), 1)
	var n: int = (ev["gems"] as Array).size()
	if bool(ev["free"]):
		assert_between(n, SwordTapperLogic.MIN_GEMS, SwordTapperLogic.RING_SIZE, "a freed sword lights 3 to 17 gems")
	else:
		assert_eq(n, 0, "a stuck sword lights none")
	var placed: Array[Dictionary] = _here(&"bet_placed")
	assert_eq(placed.size(), 1)
	assert_eq(int(placed[0]["amount"]), 40)
	var pub: Dictionary = fx.server.get_snapshot()["stations"][SID]
	assert_true(pub["pulling"])
	assert_eq(pub["pull"], _event_pull(ev), "the state has the same pull")
	assert_eq(_pull(p, 40)["error"], &"pulling", "one pull at a time")
	assert_true(fx.server.stations.has_stake(p))
	fx.run(Registry.balance.sword_reveal_time - 0.4)
	assert_eq(_here(&"round_result").size(), 0, "nothing pays during the reveal")
	assert_eq(fx.server.economy.balance(p), before - 40)
	fx.run(0.6)
	var res: Array[Dictionary] = _here(&"round_result")
	assert_eq(res.size(), 1, "it pays when the reveal ends")
	var printed: int = SwordTapperLogic.prize(40, _event_pull(ev), Registry.balance)
	assert_eq(int(ev["win"]), printed, "the event says what it pays")
	assert_eq(int(res[0]["returned"]), printed, "the printed prize, nothing else")
	assert_eq(fx.server.economy.balance(p), before - 40 + printed)
	assert_false(fx.server.stations.has_stake(p))
	pub = fx.server.get_snapshot()["stations"][SID]
	assert_false(pub["pulling"])
	assert_eq(int(pub["last"]["serial"]), 1)
	assert_eq(int(pub["last"]["returned"]), printed)
	assert_eq((pub["history"] as Array).size(), 1)


func test_stuck_and_free() -> void:
	var p: int = fx.player_ids[0]
	assert_true(_sit(p)["ok"])
	_set_money(p, 100000)
	var stuck: int = 0
	var free: int = 0
	var i: int = 0
	while (stuck < 3 or free < 3) and i < 300:
		i += 1
		var before: int = fx.server.economy.balance(p)
		assert_true(_pull(p, 25)["ok"])
		var ev: Dictionary = _here(&"sword_pull").back()
		_resolve()
		var res: Dictionary = _here(&"round_result").back()
		if bool(ev["free"]):
			free += 1
			var printed: int = SwordTapperLogic.prize(25, _event_pull(ev), Registry.balance)
			assert_eq(int(res["returned"]), printed, "freed: the lit gems' sum × the multiplier")
			assert_eq(fx.server.economy.balance(p), before - 25 + printed)
			if int(ev["mult"]) > 1:
				assert_lte((ev["gems"] as Array).size(), Registry.balance.sword_mult_max_gems, "only a small win is multiplied")
		else:
			stuck += 1
			assert_eq(int(res["returned"]), 0, "stuck: the stake is lost")
			assert_eq(fx.server.economy.balance(p), before - 25)
			assert_eq(int(ev["win"]), 0)
	assert_gte(stuck, 3, "the sword stays in the stone sometimes")
	assert_gte(free, 3, "and comes free sometimes")
	assert_eq(int(fx.server.stats[p]["biggest_bet"]), 25, "a pull counts as a bet")
	assert_eq((fx.server.get_snapshot()["stations"][SID]["history"] as Array).size(), mini(i, SwordTapperLogic.HISTORY))


func test_walking_away_mid_pull_pays_it() -> void:
	var p: int = fx.player_ids[0]
	assert_true(_sit(p)["ok"])
	var before: int = fx.server.economy.balance(p)
	assert_true(_pull(p, 10)["ok"])
	var ev: Dictionary = _here(&"sword_pull")[0]
	assert_true(fx.intent(p, &"leave")["ok"])
	var res: Array[Dictionary] = _here(&"round_result")
	assert_eq(res.size(), 1, "walking away pays the pull at once")
	assert_eq(int(res[0]["returned"]), SwordTapperLogic.prize(10, _event_pull(ev), Registry.balance))
	assert_eq(fx.server.economy.balance(p), before - 10 + int(res[0]["returned"]))
	assert_false(fx.server.stations.has_stake(p))
	assert_eq(_here(&"bets_refunded").size(), 0, "never a refund")
	assert_true(_sit(fx.player_ids[1])["ok"], "the pedestal is free for the next player")


func test_table_closing_refuses_a_late_pull() -> void:
	var p: int = fx.player_ids[0]
	assert_true(_sit(p)["ok"])
	var before: int = fx.server.economy.balance(p)
	fx.server.stations.closing_in = SwordTapperLogic.ROUND_SECONDS - 0.5
	assert_eq(_pull(p, 10)["error"], &"table_closing", "a pull that could not finish is refused")
	assert_eq(fx.server.economy.balance(p), before, "and takes nothing")
	assert_eq(_here(&"sword_pull").size(), 0)
	fx.server.stations.closing_in = SwordTapperLogic.ROUND_SECONDS + 0.5
	assert_true(_pull(p, 10)["ok"], "one that fits is fine")


func test_a_minigame_pays_the_open_pull() -> void:
	var p: int = fx.player_ids[0]
	assert_true(_sit(p)["ok"])
	var before: int = fx.server.economy.balance(p)
	assert_true(_pull(p, 30)["ok"])
	var ev: Dictionary = _here(&"sword_pull")[0]
	fx.server.stations.refund_all()
	fx.server._flush()
	var res: Array[Dictionary] = _here(&"round_result")
	assert_eq(res.size(), 1, "the pull was decided at the tap: it pays")
	assert_eq(int(res[0]["returned"]), SwordTapperLogic.prize(30, _event_pull(ev), Registry.balance))
	assert_eq(fx.server.economy.balance(p), before - 30 + int(res[0]["returned"]))
	assert_eq(_here(&"bets_refunded").size(), 0, "never a refund")
	assert_false(fx.server.stations.has_stake(p))


func test_the_minigame_start_leaves_nothing_open() -> void:
	var p: int = fx.player_ids[0]
	assert_true(_sit(p)["ok"])
	var guard: int = 0
	while fx.server.phases.phase != Phase.Id.PRE_MINIGAME and guard < 400:
		fx.run(0.5)
		guard += 1
	assert_true(_pull(p, 10)["ok"], "a pull still fits early in the warning")
	var placed: int = 1
	var refused: int = 0
	while fx.server.phases.phase != Phase.Id.MINIGAME and guard < 800:
		var r: Dictionary = _pull(p, 10)
		if r["ok"]:
			placed += 1
		else:
			assert_true(r["error"] == &"pulling" or r["error"] == &"table_closing", "refused: %s" % r)
			if r["error"] == &"table_closing":
				refused += 1
		fx.run(0.5)
		guard += 1
	assert_eq(fx.server.phases.phase, Phase.Id.MINIGAME)
	assert_gt(refused, 0, "the last seconds refuse a pull")
	assert_false(fx.server.stations.has_stake(p), "everything paid before the minigame")
	assert_eq(_here(&"round_result").size(), placed, "every pull paid")
	assert_eq(_here(&"bets_refunded").size(), 0)


func test_all_in() -> void:
	var p: int = fx.player_ids[0]
	assert_true(_sit(p)["ok"])
	var lim: Vector2i = _logic().limits()
	_set_money(p, lim.x - 1)
	assert_eq(_pull(p, lim.y)["error"], &"insufficient_funds", "under the minimum is refused")
	_set_money(p, lim.x + 7)
	fx.events.clear()
	assert_true(_pull(p, lim.y)["ok"], "a stake over the balance pulls with what fits")
	assert_eq(fx.server.economy.balance(p), 0)
	var ev: Dictionary = _here(&"bet_placed").back()
	assert_eq(int(ev["amount"]), lim.x + 7)
	assert_true(bool((ev["details"] as Dictionary).get("all_in", false)), "and says all-in")
	assert_eq(int(_here(&"sword_pull")[0]["stake"]), lim.x + 7)
	_resolve()
	_set_money(p, lim.y * 5)
	assert_true(_pull(p, lim.y * 3)["ok"])
	assert_eq(fx.server.economy.balance(p), lim.y * 4, "over the max pulls at the max")
	assert_eq(_logic().stake, lim.y)


## Luck rerolls the whole pull: returns what `pulls` pulls of $100 paid back per dollar.
func _rtp_with_luck(p: int, luck: int, pulls: int) -> float:
	var m := Modifier.new()
	m.id = &"test_luck"
	m.luck = luck
	fx.server.modifiers.add(p, m)
	_set_money(p, 10000000)
	fx.events.clear()
	var paid: int = 0
	for i: int in pulls:
		# Straight to the pedestal's logic: the intent rate limit would refuse 1500 taps at once.
		assert_true(_logic().place_bet(p, {"amount": 100})["ok"])
		_resolve()
		paid += int(_here(&"round_result").back()["returned"])
	var flourishes: Array[Dictionary] = _here(&"luck_flourish")
	assert_gt(flourishes.size(), 0, "luck shows on the result")
	for e: Dictionary in flourishes:
		assert_eq(StringName(e["kind"]), &"lucky" if luck > 0 else &"jinxed")
	fx.server.modifiers.remove_by_id(p, &"test_luck")
	return paid / (100.0 * pulls)


func test_luck_better_and_worse() -> void:
	var p: int = fx.player_ids[0]
	assert_true(_sit(p)["ok"])
	var lucky: float = _rtp_with_luck(p, 3, 1500)
	var jinxed: float = _rtp_with_luck(p, -3, 1500)
	gut.p("sword tapper on the server: luck +3 %.3f  luck -3 %.3f" % [lucky, jinxed])
	assert_gt(lucky, 1.05, "a lucky player beats the house")
	assert_lt(jinxed, 0.95, "a jinxed one does worse")
	assert_gt(lucky - jinxed, 0.3)
