class_name BaseballBatEffect
extends ItemEffect
## Baseball Bat: one swing at a nearby player knocks them out on the spot (like three shoves) and
## spills some of their chips around them for anyone to grab. Works on someone sitting at a table:
## the swing knocks them off their seat (their bet settles as if they had stood up).


func can_activate(ctx: ItemContext) -> StringName:
	var sys: ItemSystem = ctx.system
	if sys.rules.status(ctx.user).seated:
		return &"seated"
	if sys.rules.is_knocked_out(ctx.target, ctx.now) or ctx.now < sys.rules.status(ctx.target).ko_immune_until:
		return &"target_protected"
	return &""


func activate(ctx: ItemContext) -> Dictionary:
	var sys: ItemSystem = ctx.system
	sys.pull_off_seat(ctx.target)
	var spilled: Dictionary = sys.spill(ctx.target, float(ctx.param("pct", 0.08)), int(ctx.param("min", 30)), int(ctx.param("max", 400)), &"item_bat", ctx.now)
	var out: bool = sys.interactions != null and sys.interactions.report_knockout(ctx.target, ctx.user, ctx.now, &"bat")
	return {"victim": ctx.target, "knocked_out": out, "amount": spilled["amount"], "piles": spilled["piles"]}
