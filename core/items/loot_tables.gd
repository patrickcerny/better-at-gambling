class_name LootTables
extends RefCounted
## Rolls the item each player gets after a minigame (§2.10, Patrick's note #11): one item per
## player, its rarity weighted by placement (1st 0/3/1 Common/Rare/Legendary … last 4/1/0). Last
## place with ≥ `underdog_min_players` also gets a Rare (Underdog).

var cfg: LootTableConfig
## Item id → ItemDefinition.Rarity
var rarities: Dictionary[StringName, int] = {}


func _init(p_cfg: LootTableConfig, p_rarities: Dictionary[StringName, int]) -> void:
	cfg = p_cfg
	rarities = p_rarities


## Rarity weights for a placement (1-based) among `player_count` players.
func weights_for(placement: int, player_count: int) -> PackedFloat32Array:
	var t: float = 0.0
	if player_count > 1:
		t = clampf(float(placement - 1) / float(player_count - 1), 0.0, 1.0)
	var out := PackedFloat32Array()
	for r: int in maxi(cfg.best_weights.size(), cfg.worst_weights.size()):
		var a: float = cfg.best_weights[r] if r < cfg.best_weights.size() else 0.0
		var b: float = cfg.worst_weights[r] if r < cfg.worst_weights.size() else 0.0
		out.append(lerpf(a, b, t))
	return out


## The item for one placement (&"" only when no item is registered at all).
func roll(placement: int, player_count: int, rng: SeededRng) -> StringName:
	var w: Array = Array(weights_for(placement, player_count))
	var rarity: int = rng.weighted_index(w)
	return _random_near(maxi(rarity, 0), rng)


## Underdog bonus: a Rare for last place when enough players took part (&"" otherwise).
func underdog(placement: int, worst: int, player_count: int, rng: SeededRng) -> StringName:
	if placement != worst or player_count < cfg.underdog_min_players or player_count < 2:
		return &""
	return _random_near(ItemDefinition.Rarity.RARE, rng)


## Ids of a given rarity.
func ids_of(rarity: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in rarities:
		if rarities[id] == rarity:
			out.append(id)
	out.sort()
	return out


## A random item of `rarity`; an empty pool falls back to the nearest rarity (lower first).
func _random_near(rarity: int, rng: SeededRng) -> StringName:
	for d: int in 3:
		for r: int in [rarity - d, rarity + d]:
			if r < 0 or r > ItemDefinition.Rarity.LEGENDARY:
				continue
			var pool: Array[StringName] = ids_of(r)
			if not pool.is_empty():
				return pool[rng.range_int(0, pool.size() - 1)]
	return &""
