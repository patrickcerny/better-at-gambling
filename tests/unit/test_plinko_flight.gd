extends GutTest
## Plinko chip flight: whatever the seed, the visual chip strikes one peg per row, never sinks into
## a peg, rail or divider, stays on the board and comes to rest in exactly the server's slot.

const DROPS: int = 400
## A touch may sink this far into the peg it bounces off (the contact itself); anything else is
## a chip passing through a peg.
const TOUCH: float = 0.0045


func _flight(drop_id: int, slot: int) -> PlinkoFlight:
	var rng := SeededRng.new(drop_id * 7919 + slot)
	var path: Array[float] = PlinkoSteering.path_to_slot(PlinkoStation.ROWS, PlinkoStation.SLOTS, slot, rng)
	return PlinkoFlight.build(path, rng)


func test_every_drop_rests_in_the_servers_slot_without_tunnelling() -> void:
	var rng := SeededRng.new(4242)
	var worst_flag: float = 0.0
	var worst_peg: float = 0.0
	var min_land: float = INF
	var max_land: float = 0.0
	var d: float = PlinkoStation.CHIP_R + PlinkoStation.PEG_RADIUS
	var rail: float = PlinkoStation.BOARD_W * 0.5 - PlinkoStation.CHIP_R + 0.0001
	var pegs: Array[Vector2] = []
	for r: int in PlinkoStation.ROWS:
		for c: int in PlinkoStation.peg_count(r):
			pegs.append(PlinkoStation.peg_pos(r, c))
	for i: int in DROPS:
		var slot: int = i % PlinkoStation.SLOTS if i < PlinkoStation.SLOTS * 4 else rng.range_int(0, PlinkoStation.SLOTS - 1)
		var f: PlinkoFlight = _flight(i + 1, slot)
		worst_flag = maxf(worst_flag, f.worst_overlap)
		assert_eq(f.slot, slot)
		var rest: Vector2 = f.position_at(f.rest_time + 5.0)
		assert_almost_eq(rest.x, PlinkoStation.slot_x(slot), 0.0005, "drop %d rests on slot %d's centre" % [i, slot])
		assert_almost_eq(rest.y, PlinkoStation.FLOOR_Y + PlinkoStation.CHIP_R, 0.0005, "on the tray")
		min_land = minf(min_land, f.land_time)
		max_land = maxf(max_land, f.land_time)
		# Sampled every 4 ms of flight, independently of the planner's own checks.
		var t: float = 0.0
		while t <= f.rest_time:
			var p: Vector2 = f.position_at(t)
			if absf(p.x) > rail or p.y > PlinkoStation.entry_y() + 0.001 or p.y < PlinkoStation.FLOOR_Y + PlinkoStation.CHIP_R - 0.001:
				fail_test("drop %d leaves the board at t=%.2f: %s" % [i, t, p])
				return
			if p.y < PlinkoStation.row_y(0) + d + 0.01:
				for pp: Vector2 in pegs:
					if absf(pp.y - p.y) < d and absf(pp.x - p.x) < d:
						worst_peg = maxf(worst_peg, d - TOUCH - p.distance_to(pp))
			if p.y < PlinkoStation.DIV_TOP:  # below the divider tops it is inside its slot
				assert_lt(absf(p.x - PlinkoStation.slot_x(slot)), PlinkoStation.slot_w() * 0.5 - PlinkoStation.DIV_T * 0.5 - PlinkoStation.CHIP_R + 0.002, "drop %d between its dividers" % i)
			t += 0.004
	assert_almost_eq(worst_flag, 0.0, 0.0001, "the planner found a clean arc every time")
	assert_lt(worst_peg, 0.0005, "no chip passes through a peg")
	assert_gt(min_land, 1.8, "a fall takes a moment")
	assert_lt(max_land, 6.0, "and is not slow motion")


func test_one_peg_strike_per_row_down_the_steered_path() -> void:
	var rng := SeededRng.new(3)
	var path: Array[float] = PlinkoSteering.path_to_slot(PlinkoStation.ROWS, PlinkoStation.SLOTS, 2, rng)
	var f: PlinkoFlight = PlinkoFlight.build(path, rng)
	var rows: Array[int] = []
	for a: PlinkoFlight.Arc in f.arcs:
		if a.peg.x >= 0:
			rows.append(a.peg.x)
			assert_eq(a.peg.y, PlinkoStation.peg_col(a.peg.x, path[a.peg.x]), "row %d strikes the path's peg" % a.peg.x)
			var end: Vector2 = a.pos(a.dur)
			var peg: Vector2 = PlinkoStation.peg_pos(a.peg.x, a.peg.y)
			assert_almost_eq(end.distance_to(peg), PlinkoStation.CHIP_R + PlinkoStation.PEG_RADIUS, 0.002, "touches the peg's surface")
	var want: Array[int] = []
	for r: int in PlinkoStation.ROWS:
		want.append(r)
	assert_eq(rows, want, "every row once, top to bottom")


func test_flights_are_deterministic_and_varied() -> void:
	var a: PlinkoFlight = _flight(17, 6)
	var b: PlinkoFlight = _flight(17, 6)
	assert_eq(a.land_time, b.land_time, "every client plays the same flight")
	assert_eq(a.position_at(1.0), b.position_at(1.0))
	var seen: Dictionary = {}
	for i: int in 30:
		seen[snappedf(_flight(100 + i, 6).land_time, 0.001)] = true
	assert_gt(seen.size(), 20, "different drops to the same slot look different")


func test_chips_spin_and_bounce_up_off_pegs() -> void:
	var f: PlinkoFlight = _flight(5, 9)
	var ups: int = 0
	for a: PlinkoFlight.Arc in f.arcs:
		if a.v.y > 0.0:
			ups += 1
	assert_gt(ups, PlinkoStation.ROWS / 2, "most strikes kick the chip up a little")
	assert_ne(f.spin_at(0.0), f.spin_at(f.land_time), "the chip rolls as it falls")
