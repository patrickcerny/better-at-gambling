extends GutTest
## Minigame start refunds (Patrick's note #9): every open stake comes back with reason
## `bet_refunded`, money is conserved, the table resets, and Fake Cash is never paid out.


func _fake_cash(fx: TableFixture, player: int) -> void:
	var m := Modifier.new()
	m.id = &"fake_cash"
	m.flags[&"fake_cash"] = true
	fx.modifiers.add(player, m)


## Sum of all balances plus what the ledger says: they must agree, and nobody gained or lost.
func _assert_whole(fx: TableFixture, players: Array[int], start: int) -> void:
	var total: int = 0
	for p: int in players:
		total += fx.economy.balance(p)
	assert_eq(fx.economy.ledger.total(), total, "ledger matches balances")
	assert_eq(total, start * players.size(), "nobody won or lost anything")


func _refunds(logic: StationLogicBase) -> Dictionary:
	var out: Dictionary = {}
	var reset: int = 0
	for e: Dictionary in logic.drain_events():
		if e["type"] == &"bets_refunded":
			out[int(e["player"])] = int(out.get(int(e["player"]), 0)) + int(e["amount"])
		elif e["type"] == &"table_reset":
			reset += 1
	out["reset"] = reset
	return out


func test_roulette_refunds_each_bet_while_betting_and_spinning() -> void:
	var players: Array[int] = [1, 2]
	var fx := TableFixture.new(3, players)
	var rl: RouletteLogic = fx.make(RouletteLogic.new())
	rl.join(1)
	rl.join(2)
	assert_true(rl.place_bet(1, {"type": &"red", "amount": 10})["ok"])
	assert_true(rl.place_bet(1, {"type": &"straight", "value": 17, "amount": 20})["ok"])
	assert_true(rl.place_bet(2, {"type": &"dozen", "value": 2, "amount": 25})["ok"])
	rl.tick(fx.balance.roulette_betting_time + 0.1)
	assert_eq(rl.state, RouletteLogic.State.SPINNING)
	rl.drain_events()
	rl.refund_all()
	var r: Dictionary = _refunds(rl)
	assert_eq(r[1], 30)
	assert_eq(r[2], 25)
	assert_eq(r["reset"], 1)
	assert_eq(rl.state, RouletteLogic.State.IDLE)
	assert_true(rl.bets.is_empty())
	assert_false(rl.has_stake(1))
	_assert_whole(fx, players, 1000)
	assert_eq(fx.economy.ledger.entries.filter(func(e: Dictionary) -> bool: return e["reason"] == &"bet_refunded").size(), 3)


func test_idle_tables_stay_quiet() -> void:
	var fx := TableFixture.new(1)
	var rl: RouletteLogic = fx.make(RouletteLogic.new())
	rl.refund_all()
	assert_eq(rl.drain_events().size(), 0)
	var sl: SlotsLogic = fx.make(SlotsLogic.new())
	sl.refund_all()
	assert_eq(sl.drain_events().size(), 0)


func test_slots_refund_the_spinning_stake() -> void:
	var players: Array[int] = [1]
	var fx := TableFixture.new(5, players)
	var sl: SlotsLogic = fx.make(SlotsLogic.new())
	sl.join(1)
	var amount: int = sl.bet_sizes()[1]
	assert_true(sl.place_bet(1, {"amount": amount})["ok"])
	sl.drain_events()
	sl.refund_all()
	assert_eq(_refunds(sl)[1], amount)
	assert_false(sl.spinning)
	assert_false(sl.has_stake(1))
	sl.tick(10.0)
	assert_eq(sl.drain_events().filter(func(e: Dictionary) -> bool: return e["type"] == &"round_result").size(), 0, "no result after a refund")
	_assert_whole(fx, players, 1000)


func test_plinko_refunds_every_chip_in_flight() -> void:
	var players: Array[int] = [1, 2]
	var fx := TableFixture.new(7, players)
	var pl: PlinkoLogic = fx.make(PlinkoLogic.new())
	pl.join(1)
	pl.join(2)
	var amount: int = pl.bet_sizes()[0]
	assert_true(pl.place_bet(1, {"amount": amount, "risk": &"high"})["ok"])
	assert_true(pl.place_bet(2, {"amount": amount, "risk": &"low"})["ok"])
	pl.cooldowns.clear()
	assert_true(pl.place_bet(1, {"amount": amount, "risk": &"medium"})["ok"])
	pl.drain_events()
	pl.refund_all()
	var r: Dictionary = _refunds(pl)
	assert_eq(r[1], amount * 2)
	assert_eq(r[2], amount)
	assert_true(pl.drops.is_empty())
	_assert_whole(fx, players, 1000)


func test_blackjack_refunds_open_hands_doubles_and_splits() -> void:
	var players: Array[int] = [1, 2]
	var fx := TableFixture.new(11, players)
	var bj: BlackjackLogic = fx.make(BlackjackLogic.new())
	bj.join(1)
	bj.join(2)
	assert_true(bj.place_bet(1, {"amount": 50})["ok"])
	assert_true(bj.place_bet(2, {"amount": 40})["ok"])
	# Betting window: refunded before any card.
	bj.refund_all()
	var r: Dictionary = _refunds(bj)
	assert_eq(r[1], 50)
	assert_eq(r[2], 40)
	assert_eq(bj.state, BlackjackLogic.State.IDLE)
	assert_true(bj.hands.is_empty())
	_assert_whole(fx, players, 1000)
	# Acting: a doubled hand and a split hand come back in full.
	bj.hands[1] = {"stake": 100, "cards": [1, 2] as Array[int], "done": false, "doubled": true, "blackjack": false, "settled": false, "covered": 0,
		"split": {"stake": 50, "cards": [3] as Array[int], "doubled": false, "covered": 0}, "active": 1}
	bj.state = BlackjackLogic.State.ACTING
	fx.economy.apply(1, -150, &"bet_blackjack")
	bj.refund_all()
	assert_eq(_refunds(bj)[1], 150)
	_assert_whole(fx, players, 1000)


func test_blackjack_paid_natural_is_not_refunded() -> void:
	var players: Array[int] = [1]
	var fx := TableFixture.new(2, players)
	var bj: BlackjackLogic = fx.make(BlackjackLogic.new())
	bj.join(1)
	bj.hands[1] = {"stake": 20, "cards": [] as Array[int], "done": true, "doubled": false, "blackjack": true, "settled": true, "covered": 0}
	bj.state = BlackjackLogic.State.ACTING
	bj.refund_all()
	var r: Dictionary = _refunds(bj)
	assert_false(r.has(1), "naturals are already paid")
	assert_eq(r["reset"], 1)
	assert_eq(fx.economy.balance(1), 1000)


func test_fake_cash_part_is_never_refunded() -> void:
	var players: Array[int] = [1]
	var fx := TableFixture.new(4, players)
	var sl: SlotsLogic = fx.make(SlotsLogic.new())
	sl.join(1)
	_fake_cash(fx, 1)
	var amount: int = sl.bet_sizes()[2]
	assert_true(sl.place_bet(1, {"amount": amount})["ok"])
	var covered: int = mini(amount, sl.scaled(StationLogicBase.FAKE_CASH_CAP))
	assert_eq(sl.stake_covered, covered)
	assert_eq(fx.economy.balance(1), 1000 - (amount - covered))
	sl.drain_events()
	sl.refund_all()
	assert_eq(_refunds(sl)[1], amount - covered)
	assert_eq(fx.economy.balance(1), 1000, "back to what they had, never more")


func test_roulette_clear_bets_keeps_fake_cash_out_too() -> void:
	var players: Array[int] = [1]
	var fx := TableFixture.new(4, players)
	var rl: RouletteLogic = fx.make(RouletteLogic.new())
	rl.join(1)
	_fake_cash(fx, 1)
	assert_true(rl.place_bet(1, {"type": &"red", "amount": 50})["ok"])
	assert_eq(fx.economy.balance(1), 1000, "Fake Cash paid all of it")
	assert_true(rl.player_action(1, &"clear_bets")["ok"])
	assert_eq(fx.economy.balance(1), 1000, "clearing doesn't turn Fake Cash into money")
