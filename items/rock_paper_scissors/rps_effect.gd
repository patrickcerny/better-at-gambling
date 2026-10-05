class_name RpsEffect
extends ItemEffect
## Rock Paper Scissors wager: challenge a player; `option` 0–2 picks the stake (5/10/15% of the
## poorer player's money). The duel itself runs in `RpsDuels`.


func can_activate(ctx: ItemContext) -> StringName:
	var duels: RpsDuels = ctx.system.duels
	if duels.busy(ctx.user) or duels.busy(ctx.target):
		return &"busy"
	if ctx.system.economy.balance(ctx.user) <= 0 or ctx.system.economy.balance(ctx.target) <= 0:
		return &"target_broke"
	return &""


func activate(ctx: ItemContext) -> Dictionary:
	var id: int = ctx.system.duels.challenge(ctx.user, ctx.target, int(ctx.options.get("option", 1)), ctx.now)
	return {"duel": id, "stake": int(ctx.system.duels.duels[id]["stake"])}
