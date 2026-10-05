class_name ScratchTicketEffect
extends ItemEffect
## Scratch Ticket: scratch it for a random common item (60%), a rare item (25%), a small cash prize
## (10%, $50–$200 × limits) or the top prize (5%, $500 × limits). Cash is paid by the house.


func activate(ctx: ItemContext) -> Dictionary:
	var sys: ItemSystem = ctx.system
	var roll: float = sys.rng.unit()
	var mult: float = float(sys.limits.call())
	var common: float = float(ctx.param("common", 0.60))
	var rare: float = float(ctx.param("rare", 0.25))
	var small: float = float(ctx.param("small_cash", 0.10))
	if roll < common + rare:
		var item: StringName = sys.random_item(ItemDefinition.Rarity.COMMON if roll < common else ItemDefinition.Rarity.RARE)
		if item == &"scratch_ticket":
			item = sys.random_item(ItemDefinition.Rarity.RARE)
		if item != &"":
			sys.give(ctx.user, item, ctx.now)
			return {"prize": &"item", "won_item": item}
	var amount: int
	if roll < common + rare + small:
		amount = int(floor(sys.rng.range_int(int(ctx.param("small_min", 50)), int(ctx.param("small_max", 200))) * mult))
	else:
		amount = int(floor(int(ctx.param("top", 500)) * mult))
	sys.economy.apply(ctx.user, amount, &"item_scratch", ctx.def.id)
	return {"prize": &"cash", "amount": amount}
