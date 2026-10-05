class_name BeerEffect
extends ModifierItemEffect
## Beer: a little luck while you're tipsy (blurry, wobbly screen, inverted look, your money hidden
## on the HUD). When it wears off you're left holding the Empty Bottle.


func on_expire(ctx: ItemContext, reason: StringName) -> void:
	if reason == &"expired":
		ctx.system.give(ctx.target, StringName(ctx.param("leaves", "empty_bottle")), ctx.now)
