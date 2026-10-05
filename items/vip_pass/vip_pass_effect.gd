class_name VipPassEffect
extends ModifierItemEffect
## Early VIP Pass: the bouncer lets you in for a while whatever your money. When it runs out and you
## still can't afford the VIP tables, you're walked back down.


func on_expire(ctx: ItemContext, _reason: StringName) -> void:
	if ctx.system.on_vip_lost.is_valid():
		ctx.system.on_vip_lost.call(ctx.target)
