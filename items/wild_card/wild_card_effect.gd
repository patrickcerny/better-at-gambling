class_name WildCardEffect
extends ItemEffect
## Wild Card (§2.8): turns into a random item on use, its rarity rolled from `weights`
## (common / rare / legendary), never another Wild Card. The new item goes into the inventory
## like any other gift (a full inventory asks what to drop).


func activate(ctx: ItemContext) -> Dictionary:
	var sys: ItemSystem = ctx.system
	var item: StringName = roll(sys, ctx.param("weights", [0.6, 0.3, 0.1]))
	if item != &"":
		sys.give(ctx.user, item, ctx.now)
	return {"won_item": item}


static func roll(sys: ItemSystem, weights: Array) -> StringName:
	for _i: int in 8:
		var rarity: int = maxi(sys.rng.weighted_index(weights), 0)
		var item: StringName = sys.random_item(rarity)
		if item != &"" and item != &"wild_card":
			return item
	return &"lucky_clover" if sys.defs.has(&"lucky_clover") else &""
