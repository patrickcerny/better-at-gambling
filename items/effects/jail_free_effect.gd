class_name JailFreeItemEffect
extends ItemEffect
## Get Out of Jail Free item: clears the player's catch count and releases them from jail.


func activate(ctx: ItemContext) -> Dictionary:
	if ctx.system.clear_jail.is_valid():
		ctx.system.clear_jail.call(ctx.user)
	return {"player": ctx.user}
