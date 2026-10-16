extends GutTest
## The per-round casino floor draw (docs/FLOOR_PLAN.md, `FloorPlan`), on the Lucky Lounge's real
## spots and the registered games: Patrick's rules (every spot redrawn every round, nothing
## guaranteed, at least `min_filled` of each area open, soft cap per table game), seeded.

var anchors: Array
var pool: Dictionary
var cfg: FloorPlanConfig


func before_each() -> void:
	anchors = LuckyLounge.floor_anchors()
	cfg = Registry.floor_plan.duplicate() as FloorPlanConfig
	pool = FloorPlan.pool_of(Registry.game_footprints(), cfg)


func _area(vip: bool) -> Array:
	return anchors.filter(func(a: Dictionary) -> bool: return bool(a["vip"]) == vip)


func _draws(n: int, seed_value: int = 7) -> Array[Dictionary]:
	var rng := SeededRng.new(seed_value)
	var out: Array[Dictionary] = []
	for i: int in n:
		out.append(FloorPlan.draw(anchors, pool, cfg, rng))
	return out


func test_the_spots_come_from_the_map_and_the_race_hall_stays_fixed() -> void:
	assert_eq(anchors.size(), LuckyLounge.STATIONS.size() - 1, "every station but the horse race is a spot")
	var ids: Dictionary = {}
	for a: Dictionary in anchors:
		assert_false(ids.has(a["id"]), "spot ids are unique")
		ids[a["id"]] = true
		assert_ne(StringName(a["default"]), &"horse_race")
		assert_true(StringName(a["footprint"]) in [&"table", &"cabinet", &"big"])
	assert_eq(LuckyLounge.fixed_games(), [&"horse_race"])
	assert_false(pool.get(&"table", {}).has(&"horse_race"), "the horse race is never drawn")
	assert_true(pool[&"cabinet"].has(&"slots"))
	assert_true(pool[&"big"].has(&"plinko"))


func test_the_full_floor_is_the_map_as_built() -> void:
	var def := MapDefinition.new()
	LuckyLounge.describe_floor(def)
	assert_eq(def.floor_prefixes.get(&"slots", ""), "slot")
	var full: Dictionary = FloorPlan.station_ids(anchors, FloorPlan.full(anchors), def.floor_prefixes)
	assert_eq(full, LuckyLounge.full_floor_plan(), "numbering the full floor gives back the usual ids (slot_1, vip_blackjack_1, ...)")
	for sid: StringName in full:
		assert_true(LuckyLounge.STATIONS.has(sid), "%s is a STATIONS id" % sid)


func test_same_seed_same_floors_and_every_round_is_drawn_afresh() -> void:
	var a: Array[Dictionary] = _draws(6, 42)
	var b: Array[Dictionary] = _draws(6, 42)
	assert_eq(a, b, "deterministic per match seed")
	var c: Array[Dictionary] = _draws(6, 43)
	assert_ne(a, c, "another seed, other floors")
	for i: int in range(1, a.size()):
		assert_ne(a[i], a[i - 1], "round %d has a new floor" % i)


func test_every_spot_gets_a_game_of_its_size_or_is_closed_and_the_areas_stay_open_enough() -> void:
	for plan: Dictionary in _draws(400):
		assert_eq(plan.size(), anchors.size(), "every spot is drawn")
		for a: Dictionary in anchors:
			var g: StringName = plan[a["id"]]
			if g != FloorPlan.CLOSED:
				assert_true((pool[a["footprint"]] as Dictionary).has(g), "%s fits spot %s" % [g, a["id"]])
		for vip: bool in [false, true]:
			var area: Array = _area(vip)
			var need: int = ceili(area.size() * cfg.min_filled)
			assert_true(FloorPlan.filled(area, plan) >= need, "at least %d of %d spots open (vip %s)" % [need, area.size(), vip])


func test_soft_cap_holds_while_the_floor_can_be_filled_without_it() -> void:
	for plan: Dictionary in _draws(400):
		for vip: bool in [false, true]:
			var counts: Dictionary = {}
			for a: Dictionary in _area(vip):
				var g: StringName = plan[a["id"]]
				if g != FloorPlan.CLOSED and StringName(a["footprint"]) in cfg.capped_footprints:
					counts[g] = int(counts.get(g, 0)) + 1
			for g: StringName in counts:
				assert_true(int(counts[g]) <= cfg.max_per_type, "at most %d × %s (vip %s)" % [cfg.max_per_type, g, vip])


func test_the_cap_gives_way_before_the_floor_looks_empty() -> void:
	cfg.empty_chance = 1.0  # every spot closed at first: the minimum reopens them
	cfg.max_per_type = 1
	var plan: Dictionary = FloorPlan.draw(anchors, pool, cfg, SeededRng.new(3))
	for vip: bool in [false, true]:
		var area: Array = _area(vip)
		assert_eq(FloorPlan.filled(area, plan), ceili(area.size() * cfg.min_filled), "exactly the minimum (vip %s)" % vip)


func test_nothing_is_guaranteed_and_closed_spots_are_capped() -> void:
	var missing: Dictionary = {}
	var most_closed: int = 0
	for plan: Dictionary in _draws(1500, 11):
		var on_floor: Dictionary = {}
		var closed: int = 0
		for a: Dictionary in _area(false):
			if plan[a["id"]] == FloorPlan.CLOSED:
				closed += 1
			else:
				on_floor[plan[a["id"]]] = true
		most_closed = maxi(most_closed, closed)
		for g: StringName in [&"blackjack", &"roulette", &"plinko"]:
			if not on_floor.has(g):
				missing[g] = true
	assert_true(missing.has(&"plinko"), "a round can go without Plinko")
	assert_true(missing.has(&"blackjack") or missing.has(&"roulette"), "no table game is guaranteed")
	var area: int = _area(false).size()
	assert_true(most_closed <= area - ceili(area * cfg.min_filled), "closed spots never pass the minimum fill")
	assert_gt(most_closed, 0, "some rounds have closed spots")
	# Weight 0 takes a game off the floor entirely: nothing forces it back.
	cfg.weights = {&"blackjack": 0.0}
	pool = FloorPlan.pool_of(Registry.game_footprints(), cfg)
	for plan: Dictionary in _draws(50):
		assert_false(plan.values().has(&"blackjack"))


func test_every_registered_game_can_appear_and_a_new_table_game_joins_the_pool() -> void:
	var seen: Dictionary = {}
	for plan: Dictionary in _draws(300):
		for g: Variant in plan.values():
			seen[g] = true
	for id: StringName in Registry.games:
		if Registry.games[id].floor_footprint != &"fixed":
			assert_true(seen.has(id), "%s shows up on some floor" % id)
	# A game registered tomorrow (no footprint set: a table) is in the table pool with the default
	# weight and gets drawn.
	var footprints: Dictionary = Registry.game_footprints()
	footprints[&"wheel_of_fortune"] = &"table"
	var p2: Dictionary = FloorPlan.pool_of(footprints, cfg)
	assert_eq(float(p2[&"table"][&"wheel_of_fortune"]), cfg.default_weight)
	var rng := SeededRng.new(5)
	var drawn: bool = false
	for i: int in 50:
		drawn = drawn or FloorPlan.draw(anchors, p2, cfg, rng).values().has(&"wheel_of_fortune")
	assert_true(drawn)


func test_station_ids_are_numbered_per_game_and_area() -> void:
	var def := MapDefinition.new()
	LuckyLounge.describe_floor(def)
	var plan: Dictionary = _draws(1)[0]
	var ids: Dictionary = FloorPlan.station_ids(anchors, plan, def.floor_prefixes)
	var per: Dictionary = {}
	for sid: StringName in ids:
		var entry: Array = ids[sid]
		var a: Dictionary = def.floor_anchor(entry[1])
		assert_eq(plan[entry[1]], entry[0])
		assert_eq(String(sid).begins_with("vip_"), bool(a["vip"]), "%s: vip prefix" % sid)
		var stem: String = String(sid).left(String(sid).rfind("_"))
		per[stem] = int(per.get(stem, 0)) + 1
		assert_eq(String(sid), "%s_%d" % [stem, per[stem]], "numbered in map order without gaps")
	assert_eq(FloorPlan.assignment_of(ids, anchors), plan, "the wire form gives the plan back")


func test_the_geometry_keeps_big_games_off_tight_spots_and_apart() -> void:
	# Two table spots 3 m apart and one turned spot far off; a small game (2 x 2 m) fits anywhere, a
	# wide one (5 x 2 m) never stands next to another, nor where it would cross the keep-out.
	var spots: Array = [
		{"id": &"t1", "footprint": &"table", "vip": false, "default": &"small", "pos": Vector3(0, 0, 0), "yaw": 0.0},
		{"id": &"t2", "footprint": &"table", "vip": false, "default": &"small", "pos": Vector3(3, 0, 0), "yaw": 0.0},
		{"id": &"t3", "footprint": &"table", "vip": false, "default": &"small", "pos": Vector3(0, 0, 10), "yaw": PI * 0.5},
	]
	var geo := FloorGeometry.new()
	geo.rects = {&"small": Rect2(-1, -1, 2, 2), &"wide": Rect2(-2.5, -1, 5, 2)}
	geo.areas.assign([Rect2(-10, -10, 20, 25)])
	geo.keep_out.assign([Rect2(0.5, 7.0, 1.0, 1.0)])
	geo.gap = 0.6
	var by_id: Dictionary = {}
	for a: Dictionary in spots:
		by_id[a["id"]] = a
	var turned: Rect2 = geo.world_rect(spots[2], &"wide")
	assert_almost_eq(turned.size, Vector2(2, 5), Vector2(0.01, 0.01), "a turned spot turns the game's floor")
	assert_true(geo.fits(spots[0], &"wide"))
	assert_false(geo.fits(spots[2], &"wide"), "crosses the keep-out")
	assert_true(geo.fits(spots[2], &"small"))
	assert_false(geo.fits({"id": &"x", "pos": Vector3(9.5, 0, 0), "yaw": 0.0}, &"small"), "pokes out of the area")
	assert_true(geo.clear_of(spots[1], &"small", {&"t1": &"small"}, by_id), "1 m between them, more than the gap")
	assert_false(geo.clear_of(spots[1], &"wide", {&"t1": &"small"}, by_id), "too close")
	var c := FloorPlanConfig.new()
	c.min_filled = 1.0
	c.empty_chance = 0.0
	c.capped_footprints = []
	var p: Dictionary = {&"table": {&"small": 1.0, &"wide": 3.0}}
	var wide_seen: int = 0
	for s: int in 40:
		var plan: Dictionary = FloorPlan.draw(spots, p, c, SeededRng.new(s), geo)
		assert_ne(plan[&"t3"], &"wide", "never where it doesn't fit")
		assert_false(plan[&"t1"] == &"wide" and plan[&"t2"] != FloorPlan.CLOSED, "the walkway beats the minimum fill")
		assert_false(plan[&"t2"] == &"wide" and plan[&"t1"] != FloorPlan.CLOSED)
		if plan[&"t1"] == &"wide" or plan[&"t2"] == &"wide":
			wide_seen += 1
	assert_gt(wide_seen, 0, "the wide game still gets drawn where it fits")
