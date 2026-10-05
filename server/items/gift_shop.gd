class_name GiftShop
extends RefCounted
## The Gift Shop kiosk (Patrick's idea): four items on sale each casino segment, the same for
## everyone; each player may buy one per segment. Prices by rarity × the table limits, set above
## what an item is usually worth so money can't be farmed.

const OFFERS: int = 4
const PRICES: Array[int] = [150, 400, 900]  # common, rare, legendary

## [{item, price}] for this segment.
var offers: Array[Dictionary] = []
## Players who bought this segment.
var bought: Dictionary[int, bool] = {}
var loot: LootTables
var rng: SeededRng


func _init(p_loot: LootTables, p_rng: SeededRng) -> void:
	loot = p_loot
	rng = p_rng


## New stock (start of each casino segment): two commons, one rare, one rare-or-legendary.
func restock(limits_multiplier: float) -> void:
	offers.clear()
	bought.clear()
	if loot == null:
		return
	var picks: Array[StringName] = []
	for rarity: int in [ItemDefinition.Rarity.COMMON, ItemDefinition.Rarity.COMMON, ItemDefinition.Rarity.RARE, ItemDefinition.Rarity.LEGENDARY if rng.chance(0.4) else ItemDefinition.Rarity.RARE]:
		var pool: Array[StringName] = loot.ids_of(rarity).filter(func(x: StringName) -> bool: return not x in picks)
		if pool.is_empty():
			continue
		var id: StringName = pool[rng.range_int(0, pool.size() - 1)]
		picks.append(id)
		offers.append({"item": id, "price": int(floor(PRICES[rarity] * limits_multiplier)), "rarity": rarity})


func wire() -> Dictionary:
	return {"offers": offers.duplicate(true)}
