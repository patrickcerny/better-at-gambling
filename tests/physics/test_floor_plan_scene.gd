extends GutTest
## The per-round casino floor in the real match scene (docs/FLOOR_PLAN.md), Practice with the
## `floor` setting forced to "random" (Practice itself keeps the full floor): the map builds the
## server's plan, rebuilds it behind the shut doors at every regroup, closed spots are dressed, the
## tables never overlap anything, dealers stand at their tables, the navmesh reaches every table
## and the guards' and waiter's routes stay walkable, and the hall board lists the games.

var scene: MatchScene
var events: Array[Dictionary] = []


func before_each() -> void:
	events.clear()
	Net.stop()
	MatchScene.test_dummies = 1
	MatchScene.test_briefing = 0.0
	MatchScene.test_floor = "random"
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	Net.event_received.connect(_collect)
	await wait_seconds(3.3)


func after_each() -> void:
	MatchScene.test_dummies = 0
	MatchScene.test_briefing = -1.0
	MatchScene.test_floor = ""
	if Net.event_received.is_connected(_collect):
		Net.event_received.disconnect(_collect)


func _collect(ev: Dictionary) -> void:
	events.append(ev)


func _skip_until(cond: Callable, max_seconds: float = 900.0) -> bool:
	var t: float = 0.0
	while not cond.call() and t < max_seconds:
		scene.server.advance(MatchServer.TICK)
		t += MatchServer.TICK
	return cond.call()


func _wait_navmesh() -> void:
	var t: float = 0.0
	await wait_physics_frames(3)
	while not scene.map.navmesh_ready and t < 8.0:
		await wait_seconds(0.2)
		t += 0.2
	assert_true(scene.map.navmesh_ready, "navmesh baked again")


## Everything the map shows matches the server's plan.
func _check_floor() -> void:
	var srv: MatchServer = scene.server
	var map: LuckyLounge = scene.map
	assert_eq(map.floor_plan, srv.floor_plan, "the map stands on the server's floor")
	assert_eq(scene.view.state.floor_plan, srv.floor_plan, "and so does the replicated state")
	var anchors: Dictionary = {}
	for a: Dictionary in LuckyLounge.floor_anchors():
		anchors[a["id"]] = a
	var used: Dictionary = {}
	for sid: StringName in srv.floor_plan:
		var entry: Array = srv.floor_plan[sid]
		assert_true(map.stations.has(sid), "%s is built" % sid)
		var st: StationBase = map.stations.get(sid, null)
		if st == null:
			continue
		var a: Dictionary = anchors[entry[1]]
		used[entry[1]] = true
		assert_eq(st.game_id, StringName(entry[0]))
		assert_almost_eq(st.global_position, a["pos"] as Vector3, Vector3.ONE * 0.01, "%s on spot %s" % [sid, entry[1]])
		assert_eq(st.is_vip, bool(a["vip"]))
		assert_eq(Vector3(srv.map_def.station_seats[sid][0]), st.seat_position(0), "%s: the server seats people on the real chairs" % sid)
	for sid: StringName in map.stations:
		if map.stations[sid].has_meta(&"anchor"):
			assert_true(srv.floor_plan.has(sid), "%s: no leftover table from an earlier floor" % sid)
	assert_true(map.stations.has(&"horse_race_1"), "the Race Hall keeps its table")
	assert_true(map.stations.has(&"fun_blackjack_1"), "the waiting room keeps its tables")
	var closed: Array = []
	for c: Node in map.closed_spots.get_children():
		if not c.is_queued_for_deletion():
			closed.append(StringName(c.get_meta(&"anchor")))
	assert_eq(closed.size() + used.size(), anchors.size(), "every closed spot is dressed (rope or plant)")
	for id: StringName in closed:
		assert_false(used.has(id), "%s: no rope round an open table" % id)
	# Dealers: one per blackjack and roulette table, at it, on both sides.
	for sid: StringName in srv.floor_plan:
		var game: StringName = StringName(srv.floor_plan[sid][0])
		if not DealerLogic.OFFSETS.has(game):
			continue
		var d: Dealer = scene.casino_floor.dealers.get(sid, null)
		assert_not_null(d, "%s has a dealer" % sid)
		assert_true(srv.dealers.has(sid), "%s has a dealer on the server" % sid)
		if d != null:
			var st: StationBase = map.stations[sid]
			var spot: Vector3 = st.global_position + (DealerLogic.OFFSETS[game] as Vector3).rotated(Vector3.UP, st.global_rotation.y)
			assert_almost_eq(d.position_offset, spot, Vector3.ONE * 0.01, "%s's dealer stands at the table" % sid)
	for sid: StringName in scene.casino_floor.dealers:
		assert_true(is_instance_valid(scene.casino_floor.dealers[sid]) and map.stations.has(sid), "%s: no dealer left at a closed table" % sid)
	for line: String in FloorProps.board_text(srv.floor_plan, LuckyLounge.floor_anchors(), LuckyLounge.fixed_games()).split("\n"):
		assert_string_contains(map.floor_board.text, line)


## Static colliders of each table and closed spot touch nothing but their own parts and the floor.
func _check_no_overlaps() -> void:
	var space: PhysicsDirectSpaceState3D = scene.map.get_world_3d().direct_space_state
	var roots: Array[Node3D] = []
	for sid: StringName in scene.map.stations:
		if scene.map.stations[sid].has_meta(&"anchor"):
			roots.append(scene.map.stations[sid])
	for c: Node in scene.map.closed_spots.get_children():
		if not c.is_queued_for_deletion():
			roots.append(c as Node3D)
	var checked: int = 0
	for root: Node3D in roots:
		for body: Node in root.find_children("*", "StaticBody3D", true, false):
			for cs: Node in body.get_children():
				if not cs is CollisionShape3D:
					continue
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = (cs as CollisionShape3D).shape
				q.transform = (cs as CollisionShape3D).global_transform.translated(Vector3(0, 0.03, 0))
				q.collision_mask = 1
				checked += 1
				for hit: Dictionary in space.intersect_shape(q, 16):
					var other: Node = hit["collider"]
					if root.is_ancestor_of(other) or other.name == "Floor":
						continue
					fail_test("%s/%s overlaps %s" % [root.name, body.name, other.get_path()])
	assert_gt(checked, 20, "colliders checked")


## The navmesh reaches every table there is from the middle of the floor, and the guards' and the
## waiter's route points are on it.
func _check_navmesh() -> void:
	var nav: RID = scene.map.nav_region.get_navigation_map()
	var from: Vector3 = Vector3(0, 0, 6.5)
	for sid: StringName in scene.server.floor_plan:
		var st: StationBase = scene.map.stations[sid]
		var target: Vector3 = st.seat_position(0)
		var near: Vector3 = NavigationServer3D.map_get_closest_point(nav, target)
		assert_lt(Vector2(near.x - target.x, near.z - target.z).length(), 1.2, "%s: walkable floor by its first chair (%s)" % [sid, near])
		var path: PackedVector3Array = NavigationServer3D.map_get_path(nav, from, near, true)
		assert_gt(path.size(), 1, "%s: a path to it" % sid)
		if path.size() > 0:
			assert_lt(path[path.size() - 1].distance_to(near), 0.3, "%s: the path gets there" % sid)
	var points: Array[Vector3] = []
	points.append_array(CasinoFloor.WAITER_ROUTE)
	for route: Array in LuckyLounge.GUARD_ROUTES:
		for p: Vector3 in route:
			points.append(p)
	for p: Vector3 in points:
		var near: Vector3 = NavigationServer3D.map_get_closest_point(nav, p)
		assert_lt(Vector2(near.x - p.x, near.z - p.z).length(), 0.6, "route point %s stays walkable (%s)" % [p, near])


func test_the_floor_is_drawn_and_rebuilt_behind_the_doors_at_every_regroup() -> void:
	var srv: MatchServer = scene.server
	assert_eq(srv.floor_round, 1, "Practice drew a floor (forced random)")
	_check_floor()
	await _wait_navmesh()
	_check_no_overlaps()
	_check_navmesh()
	for round_i: int in [2, 3]:
		var before: Dictionary = srv.floor_plan.duplicate(true)
		var money: int = srv.economy.balance(scene.local_id)
		assert_true(_skip_until(func() -> bool: return srv.phases.phase == Phase.Id.REGROUP))
		assert_eq(srv.floor_round, round_i)
		assert_false(scene.map.lobby_open, "the doors are shut while the floor changes")
		await wait_physics_frames(2)
		_check_floor()
		var feed: Array = events.filter(func(e: Dictionary) -> bool: return e["type"] == &"regroup_started")
		assert_eq(int(feed[feed.size() - 1]["floor_plan"]["round"]), round_i)
		await _wait_navmesh()
		_check_no_overlaps()
		_check_navmesh()
		assert_eq(scene.local.state != PlayerAvatar.State.SEATED, true)
		if before == srv.floor_plan:
			gut.p("round %d drew the same floor by chance" % round_i)
		assert_true(_skip_until(func() -> bool: return srv.phases.phase == Phase.Id.CASINO))
		assert_true(srv.economy.balance(scene.local_id) >= 0)
		assert_true(money >= 0)


func test_every_game_fits_every_spot_the_draw_allows_it_on() -> void:
	# The draw's geometry (`FloorGeometry`, from the map's measurements) says where each game fits;
	# here each such game is built on each such spot with the real colliders, one game at a time,
	# so a spot the draw has not hit yet can't overlap a wall, the bar or the jail either. Every
	# spot's usual game fits it (the full floor is a possible draw).
	var def: MapDefinition = scene.server.map_def
	var geo: FloorGeometry = FloorGeometry.of_map(def, Registry.floor_plan.gap)
	assert_not_null(geo, "the map measured its games")
	var pool: Dictionary = FloorPlan.pool_of(Registry.game_footprints(), Registry.floor_plan)
	var anchors: Array = def.floor_anchors
	for a: Dictionary in anchors:
		assert_true(geo.fits(a, StringName(a["default"])), "%s fits spot %s %s" % [a["default"], a["id"], geo.why_not(a, StringName(a["default"]))])
	for game: StringName in Registry.games:
		if not geo.rects.has(game):
			continue
		var r: Rect2 = geo.rects[game]
		assert_gt(r.size.x * r.size.y, 0.5, "%s measured (%s)" % [game, r])
	var layouts: int = 0
	for fp: Variant in pool:
		for g: Variant in (pool[fp] as Dictionary).keys():
			var plan: Dictionary = {}
			for a: Dictionary in anchors:
				plan[a["id"]] = StringName(g) if a["footprint"] == fp and geo.fits(a, StringName(g)) else FloorPlan.CLOSED
			# Neighbours on adjacent spots may clash (the draw keeps them apart); build every
			# other fitting spot so each spot is checked on its own against the room.
			for parity: int in 2:
				var half: Dictionary = {}
				var n: int = 0
				for a: Dictionary in anchors:
					half[a["id"]] = plan[a["id"]] if plan[a["id"]] != FloorPlan.CLOSED and n % 2 == parity else FloorPlan.CLOSED
					if plan[a["id"]] != FloorPlan.CLOSED:
						n += 1
				var wire: Dictionary = FloorPlan.station_ids(anchors, half, def.floor_prefixes)
				for sid: Variant in wire.keys():
					var a: Dictionary = def.floor_anchor(StringName(wire[sid][1]))
					var others: Dictionary = half.duplicate()
					if not geo.clear_of(a, StringName(wire[sid][0]), others, _by_id(anchors)):
						wire.erase(sid)  # two of a kind side by side: the draw never does that
				scene.map.apply_floor_plan(wire)
				await wait_physics_frames(3)
				_check_no_overlaps()
				layouts += 1
	assert_gt(layouts, 4)


func test_drawn_floors_keep_the_walkways() -> void:
	var def: MapDefinition = scene.server.map_def
	var geo: FloorGeometry = FloorGeometry.of_map(def, Registry.floor_plan.gap)
	var pool: Dictionary = FloorPlan.pool_of(Registry.game_footprints(), Registry.floor_plan)
	var rng := SeededRng.new(99)
	for i: int in 6:
		var plan: Dictionary = FloorPlan.draw(def.floor_anchors, pool, Registry.floor_plan, rng, geo)
		scene.map.apply_floor_plan(FloorPlan.station_ids(def.floor_anchors, plan, def.floor_prefixes))
		await wait_physics_frames(3)
		_check_no_overlaps()


func _by_id(anchors: Array) -> Dictionary:
	var out: Dictionary = {}
	for a: Dictionary in anchors:
		out[a["id"]] = a
	return out
