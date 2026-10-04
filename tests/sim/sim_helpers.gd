class_name SimHelpers
extends RefCounted
## Monte-Carlo drivers that play rounds through the real station logic.

const BANKROLL: int = 1_000_000_000


static func fixture(seed_value: int, luck: int, game_id: StringName) -> TableFixture:
	var fx := TableFixture.new(seed_value, [1], BANKROLL)
	fx.economy.record_history = false
	if luck != 0:
		fx.give_luck(1, luck, game_id)
	return fx


## Returns {wagered, returned, rtp, hits, rounds} for `spins` slot spins at `bet`.
static func slots(spins: int, luck: int, seed_value: int, bet: int = 100) -> Dictionary:
	var fx := fixture(seed_value, luck, &"slots")
	var sl: SlotsLogic = fx.make(SlotsLogic.new()) as SlotsLogic
	sl.jackpot = null
	sl.join(1)
	var hits: int = 0
	for i: int in spins:
		sl.place_bet(1, {"amount": bet})
		if SlotsLogic.payout_multiplier(sl.line, fx.balance) > 0:
			hits += 1
		sl.auto_resolve()
		sl.events.clear()
	var wagered: int = spins * bet
	var returned: int = fx.economy.balance(1) - BANKROLL + wagered
	return {"wagered": wagered, "returned": returned, "rtp": returned / float(wagered), "hits": hits / float(spins)}


## Plinko drops at one risk row.
static func plinko(drops: int, risk: StringName, luck: int, seed_value: int, bet: int = 100) -> Dictionary:
	var fx := fixture(seed_value, luck, &"plinko")
	var pl: PlinkoLogic = fx.make(PlinkoLogic.new()) as PlinkoLogic
	pl.jackpot = null
	pl.join(1)
	for i: int in drops:
		pl.cooldowns[1] = 0.0
		pl.place_bet(1, {"amount": bet, "risk": risk})
		pl.auto_resolve()
		pl.events.clear()
	var wagered: int = drops * bet
	var returned: int = fx.economy.balance(1) - BANKROLL + wagered
	return {"wagered": wagered, "returned": returned, "rtp": returned / float(wagered)}


## Blackjack hands with basic strategy (no split).
static func blackjack(hands: int, luck: int, seed_value: int, bet: int = 100) -> Dictionary:
	var fx := fixture(seed_value, luck, &"blackjack")
	var bj: BlackjackLogic = fx.make(BlackjackLogic.new()) as BlackjackLogic
	bj.join(1)
	var wagered: int = 0
	for i: int in hands:
		var before: int = fx.economy.balance(1)
		bj.place_bet(1, {"amount": bet})
		bj.tick(100.0)  # close the betting window -> deal
		while bj.state == BlackjackLogic.State.ACTING and not bj.hands[1]["done"]:
			var action: StringName = BlackjackLogic.basic_strategy(bj.hands[1]["cards"], bj.dealer[0])
			bj.player_action(1, action)
		wagered += int(bj.hands[1]["stake"]) if bj.hands.has(1) else bet
		bj.auto_resolve()
		bj.events.clear()
		if before < 0:
			break
	var returned: int = fx.economy.balance(1) - BANKROLL + wagered
	return {"wagered": wagered, "returned": returned, "rtp": returned / float(wagered)}


## Roulette spins with one bet per spin.
static func roulette(spins: int, type: StringName, value: int, luck: int, seed_value: int, bet: int = 100) -> Dictionary:
	var fx := fixture(seed_value, luck, &"roulette")
	var rl: RouletteLogic = fx.make(RouletteLogic.new()) as RouletteLogic
	rl.join(1)
	for i: int in spins:
		rl.place_bet(1, {"type": type, "value": value, "amount": bet})
		rl.auto_resolve()
		rl.tick(100.0)
		rl.events.clear()
	var wagered: int = spins * bet
	var returned: int = fx.economy.balance(1) - BANKROLL + wagered
	return {"wagered": wagered, "returned": returned, "rtp": returned / float(wagered)}
