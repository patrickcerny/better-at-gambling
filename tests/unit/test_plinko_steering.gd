extends GutTest
## Plinko steering: the playback path must end in the server-chosen slot every time, move one
## half-slot per row, stay on the board and look random enough (M2 acceptance: 1,000 seeded drops).

const ROWS: int = 12
const SLOTS: int = 13


func test_thousand_seeded_drops_land_in_the_chosen_slot() -> void:
	var rng := SeededRng.new(2026)
	var ends: Dictionary = {}
	for i: int in 1000:
		var slot: int = rng.range_int(0, SLOTS - 1)
		var path: Array[float] = PlinkoSteering.path_to_slot(ROWS, SLOTS, slot, rng, rng.range_float(-1.0, 1.0))
		assert_eq(path.size(), ROWS + 1, "one position per row plus the landing")
		assert_eq(path[path.size() - 1], float(slot), "drop %d ends in slot %d" % [i, slot])
		for r: int in range(1, path.size() - 1):
			assert_almost_eq(absf(path[r] - path[r - 1]), 0.5, 0.0001, "row %d moves half a slot" % r)
			assert_true(path[r] >= 0.0 and path[r] <= SLOTS - 1, "stays on the board")
		assert_true(absf(path[path.size() - 1] - path[path.size() - 2]) <= 1.0, "last hop is at most one slot")
		ends[slot] = ends.get(slot, 0) + 1
	assert_eq(ends.size(), SLOTS, "every slot was hit at least once")


func test_paths_to_the_same_slot_differ() -> void:
	var rng := SeededRng.new(5)
	var seen: Dictionary = {}
	for i: int in 50:
		seen[str(PlinkoSteering.path_to_slot(ROWS, SLOTS, 6, rng))] = true
	assert_gt(seen.size(), 20, "the middle slot has many distinct paths")


func test_edge_slot_path_is_monotonic_when_it_has_to_be() -> void:
	var rng := SeededRng.new(9)
	var path: Array[float] = PlinkoSteering.path_to_slot(ROWS, SLOTS, 0, rng)
	assert_eq(path[path.size() - 1], 0.0)
	# Needs all 12 half-steps to reach column 0 from the middle (6.0): every step goes left.
	for r: int in range(1, path.size() - 1):
		assert_true(path[r] < path[r - 1], "row %d steps toward the edge" % r)

