class_name LootTables
extends RefCounted
## Builds reward-draft offers (§2.10) from the registered items' rarities.
##
## 1st: pick 1 of 3 (weighted Rare/Legendary) + 1 random Common. 2nd: pick 1 of 3 (Common/Rare).
## 3rd: pick 1 of 2 Commons. 4th+: 1 random Common. Last place with ≥ 3 players: + 1 Rare (Underdog).

var cfg: LootTableConfig
## Item id → ItemDefinition.Rarity
var rarities: Dictionary[StringName, int] = {}


func _init(p_cfg: LootTableConfig, p_rarities: Dictionary[StringName, int]) -> void:
	cfg = p_cfg
	rarities = p_rarities


## Draft for one placement (1-based). Returns {choices: Array[StringName], bonus: Array[StringName]}:
## the player picks one of `choices` (empty = none) and also receives every `bonus` item.
func draft(placement: int, is_last: bool, player_count: int, rng: SeededRng) -> Dictionary:
	var choices: Array[StringName] = []
	var bonus: Array[StringName] = []
	match placement:
		1:
			choices = _offer(cfg.first_weights, cfg.first_offer_count, rng)
			bonus.append(_random_of(ItemDefinition.Rarity.COMMON, rng, []))
		2:
			choices = _offer(cfg.second_weights, cfg.second_offer_count, rng)
		3:
			choices = _distinct(ItemDefinition.Rarity.COMMON, cfg.third_offer_count, rng)
		_:
			bonus.append(_random_of(ItemDefinition.Rarity.COMMON, rng, []))
	if is_last and player_count >= cfg.underdog_min_players:
		bonus.append(_random_of(ItemDefinition.Rarity.RARE, rng, []))
	bonus = bonus.filter(func(x: StringName) -> bool: return x != &"")
	return {"choices": choices, "bonus": bonus}


## Ids of a given rarity.
func ids_of(rarity: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in rarities:
		if rarities[id] == rarity:
			out.append(id)
	out.sort()
	return out


func _offer(weights: PackedFloat32Array, count: int, rng: SeededRng) -> Array[StringName]:
	var out: Array[StringName] = []
	var guard: int = 0
	while out.size() < count and guard < 100:
		guard += 1
		var w: Array = []
		for r: int in weights.size():
			w.append(weights[r] if not ids_of(r).filter(func(x: StringName) -> bool: return not x in out).is_empty() else 0.0)
		var rarity: int = rng.weighted_index(w)
		if rarity < 0:
			break
		var id: StringName = _random_of(rarity, rng, out)
		if id != &"":
			out.append(id)
	return out


func _distinct(rarity: int, count: int, rng: SeededRng) -> Array[StringName]:
	var pool: Array[StringName] = ids_of(rarity)
	rng.shuffle(pool)
	return pool.slice(0, mini(count, pool.size()))


func _random_of(rarity: int, rng: SeededRng, exclude: Array[StringName]) -> StringName:
	var pool: Array[StringName] = ids_of(rarity).filter(func(x: StringName) -> bool: return not x in exclude)
	if pool.is_empty():
		return &""
	return pool[rng.range_int(0, pool.size() - 1)]
