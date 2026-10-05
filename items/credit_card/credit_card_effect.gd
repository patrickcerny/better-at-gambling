class_name CreditCardEffect
extends ItemEffect
## Credit Card: the bank lends you `amount` × limits now; when the card's time is up it takes back
## `repay` × the same multiplier, or everything you have if that's less (money never goes negative).


func activate(ctx: ItemContext) -> Dictionary:
	var sys: ItemSystem = ctx.system
	var mult: float = float(sys.limits.call())
	var loan: int = int(floor(int(ctx.param("amount", 300)) * mult))
	var debt: int = int(floor(int(ctx.param("repay", 360)) * mult))
	sys.economy.apply(ctx.user, loan, &"item_credit_loan", ctx.def.id)
	var m := Modifier.new()
	m.id = ctx.def.id
	m.source_player = ctx.user
	m.expires_at = ctx.now + ctx.def.duration
	m.flags[&"debt"] = debt
	sys.modifiers.add(ctx.user, m)
	return {"affected": ctx.user, "seconds": ctx.def.duration, "loan": loan, "debt": debt}


func on_expire(ctx: ItemContext, _reason: StringName) -> void:
	var sys: ItemSystem = ctx.system
	var m: Modifier = ctx.options.get("modifier", null)
	var debt: int = int(m.flags.get(&"debt", 0)) if m != null else 0
	if debt <= 0:
		return
	var paid: int = sys.economy.take_up_to(ctx.target, debt, &"item_credit_repay")
	sys.events.append(GameEvents.make(&"credit_repaid", {"player": ctx.target, "amount": paid, "debt": debt}))
