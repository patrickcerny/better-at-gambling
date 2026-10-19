extends GutTest
## The casino floor's hand-made layouts and their rotation (docs/FLOOR_PLAN.md): the layout files,
## `LuckyLounge.STATIONS` as the first layout, the wire form, the bag (`FloorRotation`: seeded, no
## repeats before the bag is empty, never twice in a row, unusable layouts skipped, the full floor
## when nothing else can stand), the skip rule (`FloorPlan.problems`) and the room geometry
## (`FloorGeometry`).

## Games whose stations go by a short name instead of the game id: the Sword Tapper's pedestals
## are `sword_1` and `sword_2`.
const SHORT_IDS: Dictionary = {&"sword_tapper": "sword"}

var cfg: FloorPlanConfig


func before_each() -> void:
	cfg = Registry.floor_plan.duplicate() as FloorPlanConfig


func _ids() -> Array[StringName]:
	return cfg.enabled_ids()


func test_six_layouts_the_first_is_the_full_floor() -> void:
	assert_eq(cfg.layouts.size(), 6, "six layouts to start (FLOOR_LAYOUTS.md)")
	var seen: Dictionary = {}
	for l: FloorLayout in cfg.layouts:
		assert_not_null(l)
		assert_ne(l.id, &"", "every layout has an id")
		assert_ne(l.title, "", "and a name")
		assert_false(seen.has(l.id), "%s once" % l.id)
		seen[l.id] = true
		assert_true(l.enabled)
		assert_true(l.resource_path.begins_with("res://data/floor_layouts/"), "%s is a data file" % l.id)
	assert_eq(cfg.layouts[0].id, &"grand_hall")
	assert_eq(_ids().size(), 6, "all six rotate")


func test_stations_are_the_first_layout_plus_the_fixed_ones() -> void:
	var full: FloorLayout = cfg.layouts[0]
	assert_eq(LuckyLounge.STATIONS.size(), full.stations.size() + LuckyLounge.FIXED_STATIONS.size())
	for sid: Variant in full.stations:
		assert_eq(LuckyLounge.STATIONS[StringName(sid)], full.stations[sid], "%s comes from the layout file" % sid)
	for sid: Variant in LuckyLounge.FIXED_STATIONS:
		assert_eq(LuckyLounge.STATIONS[StringName(sid)], LuckyLounge.FIXED_STATIONS[sid])
	assert_eq(LuckyLounge.full_floor_plan(), full.wire_stations())
	var def: MapDefinition = Registry.maps[&"lucky_lounge"]
	for sid: StringName in LuckyLounge.STATIONS:
		assert_eq(def.stations.get(sid, &""), (LuckyLounge.STATIONS[sid] as Array)[0], "%s listed in the map definition" % sid)
	assert_eq(def.stations.size(), LuckyLounge.STATIONS.size())


func test_every_layout_uses_registered_games_on_the_casino_floor() -> void:
	var floor_area: Rect2 = LuckyLounge.FLOOR_AREAS[0]
	for l: FloorLayout in cfg.layouts:
		assert_true(FloorPlan.problems(l, cfg, Registry.games).is_empty(), "%s: every game is on (%s)" % [l.id, FloorPlan.problems(l, cfg, Registry.games)])
		var scratch: int = 0
		var swords: Array[Vector2] = []
		for sid: Variant in l.stations:
			var row: Array = l.stations[sid]
			var game: StringName = row[0]
			var pos: Vector3 = row[1]
			assert_ne(LuckyLounge.footprint_of(game), &"fixed", "%s/%s: fixed games keep their own place" % [l.id, sid])
			assert_false(LuckyLounge.FIXED_STATIONS.has(sid), "%s/%s: not a fixed station's id" % [l.id, sid])
			assert_false(String(sid).begins_with("vip_"), "%s/%s: the VIP lounge does not rotate" % [l.id, sid])
			assert_true(floor_area.has_point(Vector2(pos.x, pos.z)), "%s/%s stands on the casino floor (%s)" % [l.id, sid, pos])
			assert_lt(pos.z, LuckyLounge.LOBBY_DOORS_Z, "%s/%s: nothing in the entrance hall" % [l.id, sid])
			var named: bool = String(sid).begins_with(String(game) + "_") or String(sid).begins_with(String(game).trim_suffix("s") + "_")
			if SHORT_IDS.has(game):
				var short: String = String(SHORT_IDS[game]) + "_"
				named = String(sid).begins_with(short) and String(sid).trim_prefix(short).is_valid_int()
			assert_true(named, "%s/%s is named after its game" % [l.id, sid])
			if game == &"scratch":
				scratch += 1
			if game == &"sword_tapper":
				swords.append(Vector2(pos.x, pos.z))
		assert_eq(scratch, 1, "%s: one scratch counter, on the casino floor" % l.id)
		assert_eq(swords.size(), 2, "%s: two Sword Tapper pedestals (sword_1, sword_2)" % l.id)
		if swords.size() == 2:
			assert_lt(swords[0].distance_to(swords[1]), 2.5, "%s: the two pedestals stand side by side" % l.id)


func test_the_wire_form_round_trips() -> void:
	var e: Array = FloorPlan.entry(&"wheel", Vector3(19.6, 0, 5.9), -90.0)
	assert_eq(FloorPlan.game_of(e), &"wheel")
	assert_almost_eq(FloorPlan.pos_of(e), Vector3(19.6, 0, 5.9), Vector3.ONE * 0.001)
	assert_almost_eq(FloorPlan.yaw_of(e), -PI * 0.5, 0.0001)
	var bytes: PackedByteArray = var_to_bytes({&"wheel_1": e})
	assert_eq(bytes_to_var(bytes), {&"wheel_1": e}, "survives the wire unchanged")
	var spots: Dictionary = FloorPlan.spots({&"wheel_1": e})
	assert_almost_eq(spots[&"wheel_1"]["pos"] as Vector3, Vector3(19.6, 0, 5.9), Vector3.ONE * 0.001)


func test_the_bag_is_seeded_and_has_no_repeats() -> void:
	var always: Callable = func(_id: StringName) -> bool: return true
	var a := FloorRotation.new(_ids(), SeededRng.new(42))
	var b := FloorRotation.new(_ids(), SeededRng.new(42))
	var c := FloorRotation.new(_ids(), SeededRng.new(43))
	var seq_a: Array[StringName] = []
	var seq_b: Array[StringName] = []
	var seq_c: Array[StringName] = []
	for i: int in 60:
		seq_a.append(a.next(always))
		seq_b.append(b.next(always))
		seq_c.append(c.next(always))
	assert_eq(seq_a, seq_b, "same seed, same rotation")
	assert_ne(seq_a, seq_c, "another seed, another rotation")
	for bag: int in 10:
		var one: Array[StringName] = seq_a.slice(bag * 6, bag * 6 + 6)
		var distinct: Dictionary = {}
		for id: StringName in one:
			distinct[id] = true
		assert_eq(distinct.size(), 6, "bag %d: every layout once before any comes again (%s)" % [bag, one])
	for i: int in range(1, seq_a.size()):
		assert_ne(seq_a[i], seq_a[i - 1], "never the same layout twice in a row (at %d, across bag ends too)" % i)


func test_the_bag_ends_never_repeat_over_many_seeds() -> void:
	var always: Callable = func(_id: StringName) -> bool: return true
	for s: int in 200:
		var r := FloorRotation.new(_ids(), SeededRng.new(s))
		var last: StringName = &""
		for i: int in 13:
			var id: StringName = r.next(always)
			assert_ne(id, last, "seed %d step %d" % [s, i])
			last = id


func test_an_unusable_layout_is_skipped_and_the_next_one_taken() -> void:
	var off: Array[StringName] = [&"the_pit", &"the_salon"]
	var usable: Callable = func(id: StringName) -> bool: return not id in off
	var r := FloorRotation.new(_ids(), SeededRng.new(7))
	var seen: Array[StringName] = []
	for i: int in 40:
		var id: StringName = r.next(usable)
		assert_false(id in off, "%s is never put in" % id)
		seen.append(id)
	for bag: int in 10:
		var distinct: Dictionary = {}
		for id: StringName in seen.slice(bag * 4, bag * 4 + 4):
			distinct[id] = true
		assert_eq(distinct.size(), 4, "the bag goes on with the four usable layouts")
	# A layout that goes off in the middle of a bag drops out of it at once.
	var r2 := FloorRotation.new(_ids(), SeededRng.new(9))
	var first: StringName = r2.next(func(_id: StringName) -> bool: return true)
	var left: Array[StringName] = r2.remaining()
	assert_eq(left.size(), 5)
	var gone: StringName = left[0]
	var after: StringName = r2.next(func(id: StringName) -> bool: return id != gone)
	assert_eq(after, left[1], "the one after the skipped layout comes instead")
	assert_ne(after, first)
	assert_false(gone in r2.remaining(), "the skipped layout is out of this bag")


func test_nothing_usable_falls_back_to_the_full_floor() -> void:
	var r := FloorRotation.new(_ids(), SeededRng.new(3), &"grand_hall")
	for i: int in 3:
		assert_eq(r.next(func(_id: StringName) -> bool: return false), &"grand_hall", "layout 1 when none can stand")
	var only: Callable = func(id: StringName) -> bool: return id == &"the_arcade"
	for i: int in 3:
		assert_eq(r.next(only), &"the_arcade", "a single usable layout stands every round")


func test_a_game_that_is_off_skips_every_layout_with_it() -> void:
	cfg.weights = {&"craps": 0.0}
	var skipped: Array[StringName] = []
	for l: FloorLayout in cfg.layouts:
		var why: Array[String] = FloorPlan.problems(l, cfg, Registry.games)
		if &"craps" in l.games():
			assert_false(why.is_empty(), "%s needs craps: skipped" % l.id)
			assert_string_contains(why[0], "craps")
			skipped.append(l.id)
		else:
			assert_true(why.is_empty(), "%s has no craps: still in" % l.id)
	assert_gt(skipped.size(), 0)
	assert_lt(skipped.size(), cfg.layouts.size(), "some layouts are craps-free (The Arcade, The Salon)")
	var unknown := FloorLayout.new()
	unknown.id = &"x"
	unknown.stations = {&"pachinko_1": [&"pachinko", Vector3.ZERO, 0.0]}
	assert_string_contains(FloorPlan.problems(unknown, cfg, Registry.games)[0], "no such game")
	assert_false(FloorPlan.problems(FloorLayout.new(), cfg, Registry.games).is_empty(), "an empty layout is no layout")


func test_the_geometry_keeps_games_apart_and_off_keep_outs() -> void:
	# A small game (2 x 2 m) and a wide one (5 x 2 m): a turned spot turns the floor it takes, the
	# wide one crosses a keep-out and comes too close to a neighbour.
	var geo := FloorGeometry.new()
	geo.rects = {&"small": Rect2(-1, -1, 2, 2), &"wide": Rect2(-2.5, -1, 5, 2)}
	geo.areas.assign([Rect2(-10, -10, 20, 25)])
	geo.keep_out.assign([Rect2(0.5, 7.0, 1.0, 1.0)])
	geo.gap = 0.6
	var turned_spot: Dictionary = {"id": &"t3", "pos": Vector3(0, 0, 10), "yaw": PI * 0.5}
	var turned: Rect2 = geo.world_rect(turned_spot, &"wide")
	assert_almost_eq(turned.size, Vector2(2, 5), Vector2(0.01, 0.01), "a turned spot turns the game's floor")
	assert_false(geo.fits(turned_spot, &"wide"), "crosses the keep-out")
	assert_true(geo.fits(turned_spot, &"small"))
	assert_false(geo.fits({"id": &"x", "pos": Vector3(9.5, 0, 0), "yaw": 0.0}, &"small"), "pokes out of the area")
	var near: Dictionary = {&"a": FloorPlan.entry(&"small", Vector3(0, 0, 0), 0.0), &"b": FloorPlan.entry(&"small", Vector3(3, 0, 0), 0.0)}
	assert_true(FloorPlan.fit_problems(near, geo).is_empty(), "1 m between them, more than the gap")
	near[&"b"] = FloorPlan.entry(&"wide", Vector3(3, 0, 0), 0.0)
	var why: Array[String] = FloorPlan.fit_problems(near, geo)
	assert_eq(why.size(), 1, "too close: %s" % [why])
	near[&"b"] = FloorPlan.entry(&"wide", Vector3(0, 0, 10), 90.0)
	assert_string_contains(FloorPlan.fit_problems(near, geo)[0], "keep-out")


func test_the_walkway_check_finds_a_chair_walled_off() -> void:
	# A 10 x 10 m room entered at the bottom, a wall across the middle with an opening; one game
	# (a 1 x 1 m block, its chair 1 m above it) behind the wall. A 0.6 m opening is too narrow for
	# the navmesh's 0.5 m radius, a 3 m one is fine.
	var plan: Dictionary = {&"box_1": FloorPlan.entry(&"box", Vector3(5, 0, 2), 0.0)}
	for opening: float in [0.6, 3.0]:
		var geo := FloorGeometry.new()
		geo.rects = {&"box": Rect2(-0.5, -0.5, 1, 2)}
		geo.seats = {&"box": [Vector2(0, 1.0)]}
		geo.obstacles = {&"box": [Rect2(-0.5, -0.5, 1, 1)]}
		geo.areas.assign([Rect2(0, 0, 10, 10)])
		geo.entries.assign([Vector2(5, 9)])
		var half: float = opening * 0.5
		geo.blockers.assign([
			Rect2(-1, -1, 12, 1), Rect2(-1, 10, 12, 1), Rect2(-1, 0, 1, 10), Rect2(10, 0, 1, 10),
			Rect2(0, 5, 5 - half, 0.2), Rect2(5 + half, 5, 5 - half, 0.2),
		])
		assert_true(geo.can_walk())
		var cut: Array[StringName] = geo.unreachable(FloorPlan.games_of(plan), FloorPlan.spots(plan))
		var why: Array[String] = FloorPlan.fit_problems(plan, geo)
		if opening < 1.0:
			assert_eq(cut, [&"box_1"] as Array[StringName], "a 0.6 m gap walls the chair off")
			assert_string_contains(why[0], "cut off")
		else:
			assert_true(cut.is_empty(), "a 3 m gap lets people through")
			assert_true(why.is_empty())
