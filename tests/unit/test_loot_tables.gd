extends GutTest
## The item roll after each minigame (Patrick's note #11): rarity weighted by placement.

const R := ItemDefinition.Rarity

var cfg: LootTableConfig = load("res://data/items/loot_tables.tres")
var rar: Dictionary[StringName, int] = {
	&"lucky_clover": R.COMMON, &"black_cat": R.COMMON, &"loaded_reels": R.COMMON, &"hot_hands": R.COMMON,
	&"golden_chip": R.COMMON, &"banana_peel": R.COMMON, &"bodyguard": R.COMMON, &"boxing_glove": R.COMMON,
	&"double_down": R.RARE, &"pickpocket": R.RARE, &"mirror": R.RARE,
	&"crown": R.LEGENDARY, &"golden_ticket": R.LEGENDARY,
}


func _counts(lt: LootTables, placement: int, players: int, n: int, seed_value: int) -> Array[float]:
	var rng := SeededRng.new(seed_value)
	var c: Array[float] = [0.0, 0.0, 0.0]
	for i: int in n:
		c[rar[lt.roll(placement, players, rng)]] += 1.0
	for r: int in 3:
		c[r] /= n
	return c


func test_weights_blend_from_first_to_last() -> void:
	var lt := LootTables.new(cfg, rar)
	assert_eq(lt.weights_for(1, 4), PackedFloat32Array([0.0, 3.0, 1.0]), "1st: 0/3/1")
	assert_eq(lt.weights_for(4, 4), PackedFloat32Array([4.0, 1.0, 0.0]), "last: 4/1/0")
	var mid: PackedFloat32Array = lt.weights_for(2, 3)
	assert_almost_eq(mid[0], 2.0, 0.001)
	assert_almost_eq(mid[1], 2.0, 0.001)
	assert_almost_eq(mid[2], 0.5, 0.001)
	assert_eq(lt.weights_for(1, 1), PackedFloat32Array([0.0, 3.0, 1.0]), "alone: first-place odds")


func test_first_place_odds_statistical() -> void:
	var c: Array[float] = _counts(LootTables.new(cfg, rar), 1, 4, 4000, 9)
	assert_eq(c[R.COMMON], 0.0, "1st never gets a Common")
	assert_between(c[R.RARE], 0.72, 0.78)
	assert_between(c[R.LEGENDARY], 0.22, 0.28)


func test_last_place_odds_statistical() -> void:
	var c: Array[float] = _counts(LootTables.new(cfg, rar), 4, 4, 4000, 11)
	assert_between(c[R.COMMON], 0.77, 0.83)
	assert_between(c[R.RARE], 0.17, 0.23)
	assert_eq(c[R.LEGENDARY], 0.0, "last never gets a Legendary")


func test_empty_pool_falls_back_to_the_nearest_rarity() -> void:
	var no_legend: Dictionary[StringName, int] = {&"lucky_clover": R.COMMON, &"mirror": R.RARE}
	var lt := LootTables.new(cfg, no_legend)
	var rng := SeededRng.new(3)
	for i: int in 200:
		assert_true(no_legend.has(lt.roll(1, 4, rng)))
	var only_common: Dictionary[StringName, int] = {&"lucky_clover": R.COMMON}
	assert_eq(LootTables.new(cfg, only_common).roll(1, 4, rng), &"lucky_clover")
	var empty: Dictionary[StringName, int] = {}
	assert_eq(LootTables.new(cfg, empty).roll(1, 4, rng), &"")


func test_underdog_only_for_last_with_three_or_more_players() -> void:
	var lt := LootTables.new(cfg, rar)
	var rng := SeededRng.new(2)
	var id: StringName = lt.underdog(3, 3, 3, rng)
	assert_eq(rar[id], R.RARE)
	assert_eq(lt.underdog(2, 2, 2, rng), &"", "two players: no underdog")
	assert_eq(lt.underdog(2, 3, 3, rng), &"", "not last")
