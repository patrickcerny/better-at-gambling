extends GutTest


func test_same_seed_same_sequence() -> void:
	var a := SeededRng.new(42)
	var b := SeededRng.new(42)
	for i: int in 50:
		assert_eq(a.range_int(0, 1000), b.range_int(0, 1000))


func test_weighted_index_respects_zero_weights() -> void:
	var r := SeededRng.new(1)
	for i: int in 500:
		assert_ne(r.weighted_index([0, 5, 0, 3]), 0)
	assert_eq(r.weighted_index([0, 0]), -1)


func test_weighted_index_distribution() -> void:
	var r := SeededRng.new(7)
	var counts: Array[int] = [0, 0, 0]
	for i: int in 30000:
		counts[r.weighted_index([1, 2, 3])] += 1
	assert_almost_eq(counts[0] / 30000.0, 1.0 / 6.0, 0.01)
	assert_almost_eq(counts[2] / 30000.0, 0.5, 0.01)


func test_shuffle_is_permutation() -> void:
	var r := SeededRng.new(3)
	var arr: Array = range(52)
	r.shuffle(arr)
	var sorted: Array = arr.duplicate()
	sorted.sort()
	assert_eq(sorted, range(52))
	assert_ne(arr, range(52))


func test_chance_edges() -> void:
	var r := SeededRng.new(1)
	assert_false(r.chance(0.0))
	assert_true(r.chance(1.0))


func _gen_factory(r: SeededRng) -> Callable:
	return func() -> int: return r.range_int(0, 99)


func test_luck_zero_never_rerolls() -> void:
	var r := SeededRng.new(5)
	var l := LuckRng.new(r)
	var gen: Callable = _gen_factory(r)
	for i: int in 2000:
		var d: LuckRng.Draw = l.draw(0, gen, func(v: int) -> float: return float(v))
		assert_false(d.rerolled)


func test_positive_luck_never_worse_than_first_draw() -> void:
	# draw() calls the generator first, so an identically seeded RNG reproduces the first draw.
	for s: int in 300:
		var r := SeededRng.new(s)
		var l := LuckRng.new(r)
		var r2 := SeededRng.new(s)
		var first: int = r2.range_int(0, 99)
		var d: LuckRng.Draw = l.draw(3, _gen_factory(r), func(v: int) -> float: return float(v))
		assert_true(int(d.value) >= first, "seed %d: %d >= %d" % [s, int(d.value), first])


func test_negative_luck_never_better_than_first_draw() -> void:
	for s: int in 300:
		var r := SeededRng.new(s)
		var l := LuckRng.new(r)
		var r2 := SeededRng.new(s)
		var first: int = r2.range_int(0, 99)
		var d: LuckRng.Draw = l.draw(-3, _gen_factory(r), func(v: int) -> float: return float(v))
		assert_true(int(d.value) <= first)


func test_reroll_probability_matches_012_per_point() -> void:
	for luck: int in [1, 2, 3, -2]:
		var r := SeededRng.new(100 + luck)
		var l := LuckRng.new(r)
		var gen: Callable = _gen_factory(r)
		var rerolls: int = 0
		var n: int = 20000
		for i: int in n:
			if l.draw(luck, gen, func(v: int) -> float: return float(v)).rerolled:
				rerolls += 1
		assert_almost_eq(rerolls / float(n), 0.12 * absi(luck), 0.015, "luck %d" % luck)


func test_luck_is_clamped() -> void:
	var l := LuckRng.new(SeededRng.new(1))
	assert_eq(l.clamp_luck(9), 3)
	assert_eq(l.clamp_luck(-9), -3)
	assert_almost_eq(l.reroll_chance(7), 0.36, 0.0001)
