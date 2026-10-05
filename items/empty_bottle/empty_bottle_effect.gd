class_name EmptyBottleEffect
extends ItemEffect
## Empty Bottle (left over from a Beer): bonk a nearby player, who drops to the floor for a few
## seconds and spills a few chips.


func can_activate(ctx: ItemContext) -> StringName:
	if ctx.system.rules.status(ctx.user).seated:
		return &"seated"
	if ctx.system.rules.status(ctx.target).seated:
		return &"target_seated"
	return &""


func activate(ctx: ItemContext) -> Dictionary:
	var sys: ItemSystem = ctx.system
	var spilled: Dictionary = sys.spill(ctx.target, float(ctx.param("pct", 0.05)), int(ctx.param("min", 20)), int(ctx.param("max", 200)), &"item_bottle", ctx.now)
	sys.knock_down(ctx.target, float(ctx.param("stun", 4.0)), ctx.user, &"bottle", ctx.now)
	return {"victim": ctx.target, "amount": spilled["amount"], "piles": spilled["piles"]}
