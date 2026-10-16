extends GutTest
## The craps table through the real server: sit, bet, the shooter (who sat first) throws with
## SHOOT, the bets settle on the server's roll through the ledger, the point rides from roll to
## roll, the dice pass on a seven-out, a minigame gives every bet back (a line bet on the point
## too) and a player who leaves mid-point still gets their bet settled.

const SID: StringName = &"craps_1"

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(4, {"minigames": 2, "gamble_seconds": 100.0, "seed": 11})
	fx.server.start_match()
	fx.run(3.1)


func after_each() -> void:
	fx.server.free()


func _logic() -> CrapsLogic:
	return fx.server.stations.logics[SID] as CrapsLogic


func _sit(n: int) -> void:
	for i: int in n:
		assert_true(fx.intent(fx.player_ids[i], &"sit", {"station": SID})["ok"], "player %d sits" % fx.player_ids[i])


## The shooter throws as soon as the table lets them; returns the roll's `craps_result` event.
func _shoot_and_land() -> Dictionary:
	var cr: CrapsLogic = _logic()
	var guard: int = 0
	while cr.state != CrapsLogic.State.BETTING and guard < 200:
		fx.run(0.1)
		guard += 1
	fx.run(Registry.balance.craps_shoot_lock + 0.1)
	var before: int = fx.of_type(&"craps_result").size()
	if cr.shooter >= 0 and cr.state == CrapsLogic.State.BETTING:
		assert_true(fx.intent(cr.shooter, &"action", {"station": SID, "action": &"shoot"})["ok"], "the shooter throws")
	fx.run(Registry.balance.craps_throw_time + 0.2)
	var results: Array[Dictionary] = fx.of_type(&"craps_result")
	assert_eq(results.size(), before + 1, "one roll, one result")
	fx.run(Registry.balance.craps_result_time + 0.1)  # back to a betting window
	return results[-1] if results.size() > before else {}


func test_registered_on_the_map() -> void:
	assert_true(Registry.games.has(&"craps"))
	assert_eq(fx.server.map_def.stations.get(SID, &""), &"craps")
	assert_true(fx.server.stations.logics[SID] is CrapsLogic)
	assert_true(SID in fx.server.map_def.hot_table_candidates, "can be the Hot Table like the other tables")
	assert_true(LuckyLounge.STATIONS.has(SID), "built on the casino floor")
	assert_true(fx.server.dealers.has(SID), "a stickman stands at the table")
	var pub: Dictionary = fx.server.get_snapshot()["stations"][SID]
	assert_eq(StringName(pub["game"]), &"craps")
	assert_eq(int(pub["point"]), 0)


func test_bets_shoot_and_payout() -> void:
	_sit(3)
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	var c: int = fx.player_ids[2]
	var cr: CrapsLogic = _logic()
	assert_eq(cr.shooter, a, "the player who sat first shoots")
	var before: Dictionary = {a: fx.server.economy.balance(a), b: fx.server.economy.balance(b), c: fx.server.economy.balance(c)}
	assert_true(fx.intent(a, &"place_bet", {"station": SID, "bet": {"type": "field", "amount": 20}})["ok"])
	assert_true(fx.intent(b, &"place_bet", {"station": SID, "bet": {"type": "any_seven", "amount": 10}})["ok"])
	assert_true(fx.intent(c, &"place_bet", {"station": SID, "bet": {"type": "pass", "amount": 30}})["ok"])
	assert_eq(fx.server.economy.balance(c), int(before[c]) - 30, "the stake is taken at once")
	assert_eq(fx.intent(b, &"action", {"station": SID, "action": &"shoot"})["error"], &"not_shooter")
	assert_eq(fx.intent(a, &"action", {"station": SID, "action": &"shoot"})["error"], &"wait_for_bets")
	fx.run(Registry.balance.craps_shoot_lock + 0.1)
	assert_true(fx.intent(a, &"action", {"station": SID, "action": &"shoot"})["ok"])
	var rolled: Array[Dictionary] = fx.of_type(&"craps_rolled")
	assert_eq(rolled.size(), 1)
	assert_eq(int(rolled[0]["shooter"]), a)
	var dice: Array = rolled[0]["dice"]
	assert_eq(dice.size(), 2)
	assert_gt(int(rolled[0]["seed"]), 0, "the throw's seed for every client")
	assert_eq(fx.intent(b, &"place_bet", {"station": SID, "bet": {"type": "field", "amount": 10}})["error"], &"betting_closed")
	assert_eq(fx.of_type(&"round_result").filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID).size(), 0, "nothing pays while the dice are in the air")
	fx.run(Registry.balance.craps_throw_time + 0.2)
	var total: int = int(dice[0]) + int(dice[1])
	var res: Array[Dictionary] = fx.of_type(&"craps_result")
	assert_eq(res.size(), 1)
	assert_eq(int(res[0]["total"]), total)
	var results: Array[Dictionary] = fx.of_type(&"round_result").filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID)
	var decided: int = 0
	for p: int in [a, b, c]:
		var type: StringName = {a: &"field", b: &"any_seven", c: &"pass"}[p]
		var stake: int = {a: 20, b: 10, c: 30}[p]
		var r: float = CrapsLogic.decide(type, 0, total)
		var mine: Array[Dictionary] = results.filter(func(e: Dictionary) -> bool: return int(e["player"]) == p)
		if is_nan(r):
			assert_eq(mine.size(), 0, "%s rides the point" % type)
			assert_eq(fx.server.economy.balance(p), int(before[p]) - stake)
			continue
		decided += 1
		assert_eq(mine.size(), 1, "%s settles on %d" % [type, total])
		if r > 0.0:
			assert_gt(int(mine[0]["returned"]), stake, "%s wins on %d" % [type, total])
			assert_eq(fx.server.economy.balance(p), int(before[p]) - stake + int(mine[0]["returned"]))
		else:
			assert_eq(int(mine[0]["returned"]), 0)
			assert_eq(fx.server.economy.balance(p), int(before[p]) - stake, "a losing stake stays with the house")
	assert_gte(decided, 2, "both one-roll bets are decided")
	if fx.of_type(&"round_result").any(func(e: Dictionary) -> bool: return int(e["returned"]) > int(e["stake"]) and StringName(e["station"]) == SID):
		assert_gt(fx.of_type(&"money_changed").filter(func(e: Dictionary) -> bool: return StringName(e["reason"]) == &"win_craps").size(), 0, "the payout went through the ledger")


func test_point_rounds_and_the_dice_passing_on() -> void:
	_sit(3)
	var cr: CrapsLogic = _logic()
	var order: Array[int] = [fx.player_ids[0], fx.player_ids[1], fx.player_ids[2]]
	var shooters: Array[int] = [cr.shooter]
	var points: int = 0
	var refused: bool = false
	var sevens: int = 0
	var guard: int = 0
	while sevens < 2 and guard < 80:
		guard += 1
		var p: int = cr.shooter
		if cr.point == 0 and not cr.has_bet(p, &"pass"):
			assert_true(fx.intent(p, &"place_bet", {"station": SID, "bet": {"type": "pass", "amount": 10}})["ok"])
		elif cr.point != 0 and not refused:
			assert_eq(fx.intent(p, &"place_bet", {"station": SID, "bet": {"type": "pass", "amount": 10}})["error"], &"point_is_on")
			assert_true(fx.intent(p, &"clear_bets", {"station": SID})["ok"])
			assert_true(cr.has_bet(p, &"pass") or cr.bets.any(func(b: Dictionary) -> bool: return b["type"] == &"pass"), "the line bet stays up on the point")
			refused = true
		var res: Dictionary = _shoot_and_land()
		if StringName(res.get("outcome", &"")) == &"point_set":
			points += 1
			assert_eq(cr.point, int(res["total"]), "the puck goes on the point")
		if StringName(res.get("outcome", &"")) == &"seven_out":
			sevens += 1
			var next: int = order[(order.find(p) + 1) % order.size()]
			assert_eq(cr.shooter, next, "seven-out: the dice pass to the next in sitting order")
			assert_eq(cr.point, 0)
			shooters.append(cr.shooter)
		elif StringName(res.get("outcome", &"")) != &"":
			assert_eq(cr.shooter, p, "the shooter keeps the dice until a seven-out")
	gut.p("%d rolls, %d points, shooters %s" % [guard, points, str(shooters)])
	assert_eq(sevens, 2, "two seven-outs inside 80 rolls")
	assert_gt(points, 0)
	assert_eq(shooters, [order[0], order[1], order[2]] as Array[int])


func test_minigame_refunds_a_line_bet_riding_the_point() -> void:
	_sit(2)
	var cr: CrapsLogic = _logic()
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	var start_a: int = fx.server.economy.balance(a)
	var guard: int = 0
	while cr.point == 0 and guard < 30:
		guard += 1
		start_a = fx.server.economy.balance(a)
		if not cr.has_bet(a, &"pass"):
			assert_true(fx.intent(a, &"place_bet", {"station": SID, "bet": {"type": "pass", "amount": 40}})["ok"])
		_shoot_and_land()
	assert_ne(cr.point, 0, "a point is on")
	var stake_a: int = start_a - fx.server.economy.balance(a)
	assert_eq(stake_a, 40, "the pass line rides")
	var start_b: int = fx.server.economy.balance(b)
	assert_true(fx.intent(b, &"place_bet", {"station": SID, "bet": {"type": "field", "amount": 20}})["ok"])
	assert_true(fx.server.stations.has_stake(a))
	var refunds_before: int = fx.of_type(&"bets_refunded").size()
	var t: float = 0.0
	while fx.server.phases.phase != Phase.Id.MINIGAME and t < 200.0:
		fx.server._step(MatchServer.TICK)
		fx.server._flush()
		t += MatchServer.TICK
		# Keep the dice still: nobody shoots, the countdown is held back so the point stays on.
		if cr.state == CrapsLogic.State.BETTING:
			cr.timer = Registry.balance.craps_shoot_time
	assert_eq(fx.server.phases.phase, Phase.Id.MINIGAME)
	assert_eq(fx.server.economy.balance(a), start_a, "the line bet on the point came back in full")
	assert_eq(fx.server.economy.balance(b), start_b, "the field bet came back")
	assert_false(fx.server.stations.has_stake(a))
	assert_eq(cr.point, 0, "the puck is off")
	assert_true(cr.bets.is_empty())
	var refunds: Array[Dictionary] = fx.of_type(&"bets_refunded").slice(refunds_before).filter(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID)
	assert_eq(refunds.size(), 2, "one refund per player at the table")
	assert_true(fx.of_type(&"table_reset").any(func(e: Dictionary) -> bool: return StringName(e["station"]) == SID))


func test_leaving_mid_point_still_settles_and_the_stickman_throws() -> void:
	_sit(2)
	var cr: CrapsLogic = _logic()
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	var guard: int = 0
	while cr.point == 0 and guard < 30:
		guard += 1
		if not cr.has_bet(a, &"pass"):
			assert_true(fx.intent(a, &"place_bet", {"station": SID, "bet": {"type": "pass", "amount": 10}})["ok"])
		_shoot_and_land()
	assert_ne(cr.point, 0)
	var held: int = fx.server.economy.balance(a)
	assert_true(fx.intent(a, &"leave")["ok"], "the shooter stands up mid-point")
	assert_eq(cr.shooter, b, "the dice go to the next player")
	assert_true(fx.server.stations.has_stake(a), "the bet stays on the felt")
	assert_true(fx.intent(b, &"leave")["ok"])
	assert_eq(cr.shooter, -1, "nobody seated: the stickman throws")
	var before: int = fx.of_type(&"round_result").size()
	var t: float = 0.0
	while cr.has_bet(a, &"pass") and t < 400.0:
		fx.run(1.0)
		t += 1.0
	assert_false(cr.has_bet(a, &"pass"), "decided by the stickman's rolls")
	var mine: Array[Dictionary] = fx.of_type(&"round_result").slice(before).filter(func(e: Dictionary) -> bool: return int(e["player"]) == a)
	assert_eq(mine.size(), 1)
	assert_eq(fx.server.economy.balance(a), held + int(mine[0]["returned"]))
	assert_true(fx.of_type(&"craps_rolled").any(func(e: Dictionary) -> bool: return int(e["shooter"]) == -1))
	fx.run(Registry.balance.craps_throw_time + Registry.balance.craps_result_time + 0.5)
	assert_eq(cr.state, CrapsLogic.State.IDLE, "an empty table rests")
