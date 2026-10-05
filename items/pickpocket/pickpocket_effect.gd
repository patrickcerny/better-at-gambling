class_name PickpocketEffect
extends ItemEffect
## Pickpocket (§2.8): steal `pct` of a nearby player's money (min/max from params, never more
## than they have). Works on seated players too.
## Greed (`option` 1 or 2, Patrick's idea): reach deeper for more money with worse odds; getting
## caught means you pay the victim what you tried to take.


func can_activate(ctx: ItemContext) -> StringName:
	return &"target_broke" if ctx.system.economy.balance(ctx.target) <= 0 else &""


func activate(ctx: ItemContext) -> Dictionary:
	var eco: Economy = ctx.system.economy
	var tier: int = clampi(int(ctx.options.get("option", 0)), 0, 2)
	var pct: float = float(ctx.param("pct", 0.12))
	var max_amount: int = int(ctx.param("max", 500))
	var odds: float = 1.0
	if tier > 0:
		pct = float((ctx.param("greedy_pct", [0.12, 0.20, 0.30]) as Array)[tier])
		odds = float((ctx.param("greedy_odds", [1.0, 0.65, 0.40]) as Array)[tier])
		max_amount = int(max_amount * (1.0 + tier))
	var amount: int = steal_amount(eco.balance(ctx.target), pct, int(ctx.param("min", 50)), max_amount)
	if odds < 1.0 and ctx.system.rng.unit() >= odds:
		var paid: int = eco.take_up_to(ctx.user, amount, &"item_pickpocket_caught", ctx.def.id)
		if paid > 0:
			eco.apply(ctx.target, paid, &"item_pickpocket_caught", ctx.def.id)
		return {"thief": ctx.user, "victim": ctx.target, "amount": 0, "caught": true, "paid": paid, "tier": tier}
	if amount > 0:
		eco.apply(ctx.target, -amount, &"item_pickpocket", ctx.def.id)
		eco.apply(ctx.user, amount, &"item_pickpocket", ctx.def.id)
	return {"thief": ctx.user, "victim": ctx.target, "amount": amount, "tier": tier}


## `pct` of `money`, at least `min_amount`, at most `max_amount`, never more than `money`.
static func steal_amount(money: int, pct: float, min_amount: int, max_amount: int) -> int:
	if money <= 0:
		return 0
	return mini(clampi(int(floor(money * pct)), min_amount, max_amount), money)
