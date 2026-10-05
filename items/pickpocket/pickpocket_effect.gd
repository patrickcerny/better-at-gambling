class_name PickpocketEffect
extends ItemEffect
## Pickpocket (§2.8): steal `pct` of a nearby player's money (min/max from params, never more
## than they have). Works on seated players too.


func can_activate(ctx: ItemContext) -> StringName:
	return &"target_broke" if ctx.system.economy.balance(ctx.target) <= 0 else &""


func activate(ctx: ItemContext) -> Dictionary:
	var eco: Economy = ctx.system.economy
	var amount: int = steal_amount(eco.balance(ctx.target), float(ctx.param("pct", 0.12)), int(ctx.param("min", 50)), int(ctx.param("max", 500)))
	if amount > 0:
		eco.apply(ctx.target, -amount, &"item_pickpocket", ctx.def.id)
		eco.apply(ctx.user, amount, &"item_pickpocket", ctx.def.id)
	return {"thief": ctx.user, "victim": ctx.target, "amount": amount}


## `pct` of `money`, at least `min_amount`, at most `max_amount`, never more than `money`.
static func steal_amount(money: int, pct: float, min_amount: int, max_amount: int) -> int:
	if money <= 0:
		return 0
	return mini(clampi(int(floor(money * pct)), min_amount, max_amount), money)
