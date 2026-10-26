extends GutTest
## The casino floor drawn every round (docs/FLOOR_PLAN.md): the floor generator (`FloorGenerator`:
## seeded, every game placed, the table games grouped in the pit with the dealers inside and the
## players outside, tables in a row either tight or two beans apart, the canonical draw as the full
## floor and `LuckyLounge.STATIONS`), the seeds (`FloorRotation`), the wire form, the skip rule
## (`FloorPlan.problems`) and the room geometry (`FloorGeometry`: overlaps, keep-outs, the walkway
## checks for one bean and for two side by side). The real navmeshes walk the drawn floors in
## tests/physics/test_floor_walkability.gd.

## Games whose stations go by a short name instead of the game id.
const SHORT_IDS: Dictionary = {&"sword_tapper": "sword", &"slots": "slot"}
## Draws checked per test.
const DRAWS: int = 120

var cfg: FloorPlanConfig
var site: FloorSite


func before_each() -> void:
	cfg = Registry.floor_plan.duplicate() as FloorPlanConfig
	site = LuckyLounge.floor_site()


## Every registered game the generator places (game id → footprint).
func _games() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in Registry.games:
		if Registry.games[id].floor_footprint != &"fixed":
			out[id] = Registry.games[id].floor_footprint
	return out


## The room's geometry without a map: the nominal sizes, the floor area, the keep-outs.
func _geo() -> FloorGeometry:
	var def := MapDefinition.new()
	LuckyLounge.describe_floor(def)
	def.floor_rects = FloorGenerator.NOMINAL.duplicate()
	var geo: FloorGeometry = FloorGeometry.of_map(def, cfg.gap)
	assert_false(geo.can_walk(), "no walkway check without the map's colliders")
	return geo


func test_the_full_floor_is_the_canonical_draw_plus_the_fixed_stations() -> void:
	var full: FloorLayout = FloorGenerator.full(site, _games(), null, cfg)
	assert_not_null(full)
	assert_eq(full.id, &"grand_hall")
	assert_eq(LuckyLounge.full_floor_plan(), full.wire_stations(), "the map is built on the canonical draw")
	assert_eq(FloorGenerator.full(site, _games(), null, cfg).wire_stations(), full.wire_stations(), "no dice: the same every time")
	assert_eq(LuckyLounge.STATIONS.size(), full.stations.size() + LuckyLounge.FIXED_STATIONS.size())
	for sid: Variant in full.stations:
		var row: Array = full.stations[sid]
		var st: Array = LuckyLounge.STATIONS[StringName(sid)]
		assert_eq(st[0], row[0])
		assert_almost_eq(st[1] as Vector3, row[1] as Vector3, Vector3.ONE * 0.001, "%s where the canonical draw puts it" % sid)
	for sid: Variant in LuckyLounge.FIXED_STATIONS:
		assert_eq(LuckyLounge.STATIONS[StringName(sid)], LuckyLounge.FIXED_STATIONS[sid])
		assert_true(StringName(sid) in site.fixed, "%s never moves" % sid)
	var def: MapDefinition = Registry.maps[&"lucky_lounge"]
	for sid: StringName in LuckyLounge.STATIONS:
		assert_eq(def.stations.get(sid, &""), (LuckyLounge.STATIONS[sid] as Array)[0], "%s listed in the map definition" % sid)
	assert_eq(def.stations.size(), LuckyLounge.STATIONS.size())
	# Every game, the config's extra tables on top.
	var counts: Dictionary = {}
	for sid: Variant in full.stations:
		var g: StringName = (full.stations[sid] as Array)[0]
		counts[g] = int(counts.get(g, 0)) + 1
	for g: StringName in _games():
		assert_gt(int(counts.get(g, 0)), 0, "%s on the full floor" % g)
	assert_eq(int(counts.get(&"blackjack", 0)), 1 + cfg.full_extras.count(&"blackjack"))
	assert_eq(int(counts.get(&"roulette", 0)), 1 + cfg.full_extras.count(&"roulette"))
	assert_eq(int(counts.get(&"slots", 0)), cfg.cabinets.y, "every slot machine")
	assert_eq(int(counts.get(&"plinko", 0)), cfg.bigs.y)


func test_draws_are_seeded() -> void:
	var a: FloorLayout = FloorGenerator.draw(site, _games(), null, cfg, 42)
	var b: FloorLayout = FloorGenerator.draw(site, _games(), null, cfg, 42)
	var c: FloorLayout = FloorGenerator.draw(site, _games(), null, cfg, 43)
	assert_eq(a.wire_stations(), b.wire_stations(), "same seed, same floor")
	assert_ne(a.wire_stations(), c.wire_stations(), "another seed, another floor")
	assert_eq(a.id, &"floor_42", "the id spells the seed")
	assert_eq(FloorGenerator.seed_of("floor_42"), 42)
	assert_eq(FloorGenerator.seed_of("17"), 17, "a bare number works too")
	assert_eq(FloorGenerator.seed_of("grand_hall"), -1)
	assert_eq(FloorGenerator.seed_of("floor_x"), -1)
	assert_eq(FloorGenerator.seed_of("floor_-3"), -1)


func test_every_draw_puts_every_game_on_the_casino_floor() -> void:
	var floor_area: Rect2 = LuckyLounge.FLOOR_AREAS[0]
	var geo: FloorGeometry = _geo()
	var shapes: Dictionary = {}
	for s: int in DRAWS:
		var l: FloorLayout = FloorGenerator.draw(site, _games(), null, cfg, s)
		assert_not_null(l, "draw %d seats every game" % s)
		if l == null:
			continue
		var label: String = String(l.id)
		assert_eq(FloorPlan.problems(l, cfg, Registry.games, geo), [] as Array[String], "%s fits: no overlaps, no keep-outs, nothing within reach of the hall" % label)
		var seen: Dictionary = {}
		var swords: Array[Array] = []
		var tables: int = 0
		for sid: Variant in l.stations:
			var row: Array = l.stations[sid]
			var game: StringName = row[0]
			var pos: Vector3 = row[1]
			seen[game] = true
			assert_false(StringName(sid) in site.fixed or String(sid).begins_with("vip_"), "%s/%s: not a fixed station's id" % [label, sid])
			assert_true(floor_area.has_point(Vector2(pos.x, pos.z)), "%s/%s stands on the casino floor (%s)" % [label, sid, pos])
			assert_lt(pos.z, LuckyLounge.FLOOR_HALL_REACH[0].position.y, "%s/%s: out of reach of the entrance hall" % [label, sid])
			var prefix: String = String(SHORT_IDS.get(game, game)) + "_"
			assert_true(String(sid).begins_with(prefix) and String(sid).trim_prefix(prefix).is_valid_int(), "%s/%s is named after its game" % [label, sid])
			if game == &"sword_tapper":
				swords.append([Vector2(pos.x, pos.z), float(row[2])])
			if _games()[game] == &"table":
				tables += 1
				# The pit: the players outside, the dealers inside round the lane.
				var yaw: float = float(row[2])
				assert_true(is_equal_approx(yaw, 0.0) or is_equal_approx(yaw, 180.0), "%s/%s faces out of the pit (%s)" % [label, sid, yaw])
				if is_equal_approx(yaw, 180.0):
					assert_lt(pos.z, site.lane_z, "%s/%s: the north row's players face north" % [label, sid])
				else:
					assert_gt(pos.z, site.lane_z, "%s/%s: the south row's players face south" % [label, sid])
		for g: StringName in _games():
			assert_true(seen.has(g), "%s has %s" % [label, g])
		assert_between(tables, _count(&"table") + cfg.extra_tables.x - 1, _count(&"table") + cfg.extra_tables.y, "%s: every table game once and a few more" % label)
		assert_eq(swords.size(), 2, "%s: two Sword Tapper pedestals" % label)
		if swords.size() == 2:
			assert_almost_eq((swords[0][0] as Vector2).distance_to(swords[1][0]), 1.8, 0.02, "%s: side by side" % label)
			assert_almost_eq(float(swords[0][1]), float(swords[1][1]), 0.01, "%s: facing the same way" % label)
		shapes[_shape(l)] = true
	assert_gt(shapes.size(), DRAWS / 2, "the floors differ (%d different of %d)" % [shapes.size(), DRAWS])


func _count(footprint: StringName) -> int:
	var n: int = 0
	for g: StringName in _games():
		if _games()[g] == footprint:
			n += 1
	return n


## Which game stands roughly where (a 2 m grid), to tell floors apart.
static func _shape(l: FloorLayout) -> String:
	var cells: Array[String] = []
	for sid: Variant in l.stations:
		var row: Array = l.stations[sid]
		var p: Vector3 = row[1]
		cells.append("%s@%d,%d" % [row[0], roundi(p.x / 2.0), roundi(p.z / 2.0)])
	cells.sort()
	return ",".join(cells)


func test_tables_in_a_row_stand_tight_or_two_beans_apart() -> void:
	var gen := FloorGenerator.new(site, _games(), null, cfg, null)
	for s: int in DRAWS:
		var l: FloorLayout = FloorGenerator.draw(site, _games(), null, cfg, s)
		var rows: Dictionary = {}  # yaw → the row's tables [x0, x1 of their solid parts] by block
		for sid: Variant in l.stations:
			var row: Array = l.stations[sid]
			var game: StringName = row[0]
			if _games()[game] != &"table":
				continue
			var pos: Vector3 = row[1]
			var solid: Rect2 = FloorGenerator.turned(gen.solid_of(game), float(row[2]))
			var key: int = roundi(float(row[2]))
			if not rows.has(key):
				rows[key] = []
			(rows[key] as Array).append([pos.x + solid.position.x, pos.x + solid.end.x, sid])
		for key: int in rows:
			var r: Array = rows[key]
			r.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
			for i: int in range(1, r.size()):
				var gap: float = float(r[i][0]) - float(r[i - 1][1])
				assert_true(gap < site.bean_width or gap >= site.lane - 0.05, "draw %d: %s and %s stand %.2f m apart, solid to solid: a gap one bean squeezes through" % [s, r[i - 1][2], r[i][2], gap])


func test_a_new_table_game_gets_a_spot_in_the_pit() -> void:
	# A table game nobody has measured (Casino Hold'em, say): it stands in the pit like the others,
	# sized as the biggest table there is.
	var games: Dictionary = _games()
	games[&"holdem"] = &"table"
	var full: FloorLayout = FloorGenerator.full(site, games, null, cfg)
	assert_not_null(full, "the full floor has room for it")
	if full != null:
		assert_true(full.stations.has(&"holdem_1"), "the full floor has a hold'em table")
	for s: int in 40:
		var l: FloorLayout = FloorGenerator.draw(site, games, null, cfg, s)
		assert_not_null(l, "draw %d seats it" % s)
		if l == null:
			continue
		assert_true(l.stations.has(&"holdem_1"), "draw %d has a hold'em table" % s)
		var row: Array = l.stations[&"holdem_1"]
		assert_true(is_equal_approx(float(row[2]), 0.0) or is_equal_approx(float(row[2]), 180.0), "in a pit row")


func test_a_game_that_is_off_is_left_out_and_flagged() -> void:
	var games: Dictionary = _games()
	games.erase(&"craps")
	for s: int in 20:
		var l: FloorLayout = FloorGenerator.draw(site, games, null, cfg, s)
		assert_false(&"craps" in l.games(), "draw %d has no craps table" % s)
	cfg.weights = {&"craps": 0.0}
	var with: FloorLayout = FloorGenerator.full(site, _games(), null, cfg)
	var why: Array[String] = FloorPlan.problems(with, cfg, Registry.games)
	assert_false(why.is_empty(), "a floor with a game that is off can't stand")
	assert_string_contains(why[0], "craps")
	var unknown := FloorLayout.new()
	unknown.id = &"x"
	unknown.stations = {&"pachinko_1": [&"pachinko", Vector3.ZERO, 0.0]}
	assert_string_contains(FloorPlan.problems(unknown, cfg, Registry.games)[0], "no such game")
	assert_false(FloorPlan.problems(FloorLayout.new(), cfg, Registry.games).is_empty(), "an empty layout is no layout")


func test_the_seeds_are_seeded_and_never_twice_in_a_row() -> void:
	var a := FloorRotation.new(SeededRng.new(42))
	var b := FloorRotation.new(SeededRng.new(42))
	var c := FloorRotation.new(SeededRng.new(43))
	var seq_a: Array[int] = []
	var seq_b: Array[int] = []
	var seq_c: Array[int] = []
	for i: int in 60:
		seq_a.append(a.next_seed())
		seq_b.append(b.next_seed())
		seq_c.append(c.next_seed())
	assert_eq(seq_a, seq_b, "same match seed, same floors")
	assert_ne(seq_a, seq_c, "another match seed, other floors")
	assert_eq(a.current(), seq_a[59])
	for i: int in range(1, seq_a.size()):
		assert_ne(seq_a[i], seq_a[i - 1], "never the same floor twice in a row")
		assert_between(seq_a[i], 0, FloorRotation.SEED_RANGE - 1)


func test_the_wire_form_round_trips() -> void:
	var e: Array = FloorPlan.entry(&"wheel", Vector3(19.6, 0, 5.9), -90.0)
	assert_eq(FloorPlan.game_of(e), &"wheel")
	assert_almost_eq(FloorPlan.pos_of(e), Vector3(19.6, 0, 5.9), Vector3.ONE * 0.001)
	assert_almost_eq(FloorPlan.yaw_of(e), -PI * 0.5, 0.0001)
	var bytes: PackedByteArray = var_to_bytes({&"wheel_1": e})
	assert_eq(bytes_to_var(bytes), {&"wheel_1": e}, "survives the wire unchanged")
	var spots: Dictionary = FloorPlan.spots({&"wheel_1": e})
	assert_almost_eq(spots[&"wheel_1"]["pos"] as Vector3, Vector3(19.6, 0, 5.9), Vector3.ONE * 0.001)


func test_the_geometry_keeps_games_apart_and_off_keep_outs() -> void:
	# A small game (2 x 2 m) and a wide one (5 x 2 m): a turned spot turns the floor it takes, the
	# wide one crosses a keep-out and comes too close to a neighbour.
	var geo := FloorGeometry.new()
	geo.rects = {&"small": Rect2(-1, -1, 2, 2), &"wide": Rect2(-2.5, -1, 5, 2)}
	geo.areas.assign([Rect2(-10, -10, 20, 25)])
	geo.keep_out.assign([Rect2(0.5, 7.0, 1.0, 1.0)])
	geo.origin_keep_out.assign([Rect2(-10, 13, 20, 2)])
	geo.gap = 0.6
	var turned_spot: Dictionary = {"id": &"t3", "pos": Vector3(0, 0, 10), "yaw": PI * 0.5}
	var turned: Rect2 = geo.world_rect(turned_spot, &"wide")
	assert_almost_eq(turned.size, Vector2(2, 5), Vector2(0.01, 0.01), "a turned spot turns the game's floor")
	assert_false(geo.fits(turned_spot, &"wide"), "crosses the keep-out")
	assert_true(geo.fits(turned_spot, &"small"))
	assert_false(geo.fits({"id": &"x", "pos": Vector3(9.5, 0, 0), "yaw": 0.0}, &"small"), "pokes out of the area")
	assert_false(geo.fits({"id": &"x", "pos": Vector3(0, 0, 13.5), "yaw": 0.0}, &"small"), "its origin within reach of somewhere it must not be used from")
	var near: Dictionary = {&"a": FloorPlan.entry(&"small", Vector3(0, 0, 0), 0.0), &"b": FloorPlan.entry(&"small", Vector3(3, 0, 0), 0.0)}
	assert_true(FloorPlan.fit_problems(near, geo).is_empty(), "1 m between them, more than the gap")
	near[&"b"] = FloorPlan.entry(&"wide", Vector3(3, 0, 0), 0.0)
	var why: Array[String] = FloorPlan.fit_problems(near, geo)
	assert_eq(why.size(), 1, "too close: %s" % [why])
	near[&"b"] = FloorPlan.entry(&"wide", Vector3(0, 0, 10), 90.0)
	assert_string_contains(FloorPlan.fit_problems(near, geo)[0], "keep-out")


## A 10 x 10 m room entered at the bottom, a wall across the middle with an opening; one game (a
## 1 x 1 m block, its chair 1 m above it) behind the wall.
func _walled_room(opening: float) -> FloorGeometry:
	var geo := FloorGeometry.new()
	geo.rects = {&"box": Rect2(-0.5, -0.5, 1, 2)}
	geo.seats = {&"box": [Vector2(0, 1.0)]}
	geo.obstacles = {&"box": [Rect2(-0.5, -0.5, 1, 1)]}
	geo.areas.assign([Rect2(0, 0, 10, 10)])
	geo.entries.assign([Vector2(5, 9)])
	geo.pair_radius = 0.84
	geo.doorways.assign([Vector2(5, 7.5)])
	var half: float = opening * 0.5
	geo.blockers.assign([
		Rect2(-1, -1, 12, 1), Rect2(-1, 10, 12, 1), Rect2(-1, 0, 1, 10), Rect2(10, 0, 1, 10),
		Rect2(0, 5, 5 - half, 0.2), Rect2(5 + half, 5, 5 - half, 0.2),
	])
	return geo


func test_the_walkway_check_finds_a_chair_walled_off() -> void:
	# A 0.6 m opening is too narrow for the navmesh's 0.5 m radius, a 3 m one is fine.
	var plan: Dictionary = {&"box_1": FloorPlan.entry(&"box", Vector3(5, 0, 2), 0.0)}
	for opening: float in [0.6, 3.0]:
		var geo: FloorGeometry = _walled_room(opening)
		assert_true(geo.can_walk())
		var cut: Array[StringName] = geo.unreachable(FloorPlan.games_of(plan), FloorPlan.spots(plan))
		var why: Array[String] = FloorPlan.fit_problems(plan, geo)
		if opening < 1.0:
			assert_eq(cut, [&"box_1"] as Array[StringName], "a 0.6 m gap walls the chair off")
			assert_string_contains(why[0], "cut off")
		else:
			assert_true(cut.is_empty(), "a 3 m gap lets people through")
			assert_true(why.is_empty(), "and two beans side by side (%s)" % [why])


func test_the_walkway_check_finds_a_gap_only_one_bean_fits_through() -> void:
	# 1.6 m: one bean (and the guards) get through, two side by side (1.68 m) don't.
	var plan: Dictionary = {&"box_1": FloorPlan.entry(&"box", Vector3(5, 0, 2), 0.0)}
	var geo: FloorGeometry = _walled_room(1.6)
	assert_true(geo.unreachable(FloorPlan.games_of(plan), FloorPlan.spots(plan)).is_empty(), "one bean gets to the chair")
	var why: Array[String] = geo.too_narrow(FloorPlan.games_of(plan), FloorPlan.spots(plan))
	assert_eq(why.size(), 1, "the chair has no walkway two beans wide: %s" % [why])
	if why.size() > 0:
		assert_string_contains(why[0], "two beans")
	# A doorway behind a block: open for one bean, not for two.
	var door: FloorGeometry = _walled_room(3.0)
	door.blockers.append(Rect2(4.0, 7.0, 0.3, 1.0))
	door.blockers.append(Rect2(5.95, 7.0, 0.3, 1.0))
	door.doorways.assign([Vector2(5.15, 7.5)])
	var why_door: Array[String] = door.too_narrow({}, {})
	assert_eq(why_door.size(), 1, "the doorway is a squeeze: %s" % [why_door])
