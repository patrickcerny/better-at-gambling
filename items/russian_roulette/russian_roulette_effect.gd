class_name RussianRouletteEffect
extends ItemEffect
## Russian Roulette (multi-use): each pull pays +`gain` of your money from the house, but the odds
## of the bang start at 1 in 6 and grow by 1/6 per pull. The bang leaves you `keep` of your money;
## the rest goes into the progressive jackpot, and the revolver is gone.

## player → pulls survived with this revolver.
var pulls: Dictionary[int, int] = {}


func can_activate(ctx: ItemContext) -> StringName:
	return &"broke" if ctx.system.economy.balance(ctx.user) <= 0 else &""


func activate(ctx: ItemContext) -> Dictionary:
	var sys: ItemSystem = ctx.system
	var n: int = pulls.get(ctx.user, 0)
	var chance: float = minf(float(n + 1) / 6.0, 1.0)
	var money: int = sys.economy.balance(ctx.user)
	if sys.rng.unit() < chance:
		pulls.erase(ctx.user)
		var lost: int = money - int(floor(money * float(ctx.param("keep", 0.2))))
		sys.economy.take_up_to(ctx.user, lost, &"item_roulette_bang")
		if sys.jackpot != null:
			sys.jackpot.pot += lost
			sys.events.append(GameEvents.make(&"jackpot_changed", {"amount": sys.jackpot.pot}))
		return {"bang": true, "amount": lost, "odds": snappedf(chance, 0.001)}
	pulls[ctx.user] = n + 1
	var gain: int = int(floor(money * float(ctx.param("gain", 0.2))))
	sys.economy.apply(ctx.user, gain, &"item_roulette_click", ctx.def.id)
	return {"bang": false, "amount": gain, "odds": snappedf(chance, 0.001), "next_odds": snappedf(minf(float(n + 2) / 6.0, 1.0), 0.001), "keep": true}
