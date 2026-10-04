extends GutTest

const R := ItemDefinition.Rarity

var cfg: LootTableConfig = load("res://data/items/loot_tables.tres")
var rar: Dictionary[StringName, int] = {
	&"lucky_clover": R.COMMON, &"black_cat": R.COMMON, &"loaded_reels": R.COMMON, &"hot_hands": R.COMMON,
	&"golden_chip": R.COMMON, &"banana_peel": R.COMMON, &"bodyguard": R.COMMON, &"boxing_glove": R.COMMON,
	&"double_down": R.RARE, &"pickpocket": R.RARE, &"mirror": R.RARE,
}


func test_draft_shapes_per_placement() -> void:
	var lt := LootTables.new(cfg, rar)
	var rng := SeededRng.new(1)
	var d1: Dictionary = lt.draft(1, false, 4, rng)
	assert_eq((d1["choices"] as Array).size(), 3)
	assert_eq((d1["bonus"] as Array).size(), 1)
	for id: StringName in d1["choices"]:
		assert_eq(rar[id], R.RARE, "1st offers rare (no legendaries registered)")
	assert_eq(rar[d1["bonus"][0]], R.COMMON)
	var d3: Dictionary = lt.draft(3, false, 4, rng)
	assert_eq((d3["choices"] as Array).size(), 2)
	for id: StringName in d3["choices"]:
		assert_eq(rar[id], R.COMMON)
	var d4: Dictionary = lt.draft(4, false, 6, rng)
	assert_eq((d4["choices"] as Array).size(), 0)
	assert_eq((d4["bonus"] as Array).size(), 1)


func test_offers_have_no_duplicates() -> void:
	var lt := LootTables.new(cfg, rar)
	var rng := SeededRng.new(5)
	for i: int in 200:
		var c: Array = lt.draft(2, false, 4, rng)["choices"]
		var seen: Dictionary = {}
		for id: StringName in c:
			assert_false(seen.has(id))
			seen[id] = true


func test_underdog_only_with_three_or_more_players() -> void:
	var lt := LootTables.new(cfg, rar)
	var rng := SeededRng.new(2)
	var with3: Dictionary = lt.draft(3, true, 3, rng)
	assert_eq((with3["bonus"] as Array).size(), 1)
	assert_eq(rar[with3["bonus"][0]], R.RARE)
	var with2: Dictionary = lt.draft(2, true, 2, rng)
	assert_eq((with2["bonus"] as Array).size(), 0)


func test_second_place_weights_statistical() -> void:
	var lt := LootTables.new(cfg, rar)
	var rng := SeededRng.new(9)
	var commons: int = 0
	var total: int = 0
	for i: int in 3000:
		for id: StringName in lt.draft(2, false, 4, rng)["choices"]:
			total += 1
			if rar[id] == R.COMMON:
				commons += 1
	# Weights common:rare = 2:1, but rares run out within an offer (only 3), so ≥ 2/3 common.
	assert_between(commons / float(total), 0.62, 0.75)
