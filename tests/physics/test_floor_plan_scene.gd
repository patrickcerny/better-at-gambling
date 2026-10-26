extends GutTest
## The casino floor in the real match scene (docs/FLOOR_PLAN.md), Practice with the `floor` setting
## forced to "random" (Practice itself keeps the full floor): the full floor and a few drawn floors
## are built against the real colliders and the navmesh and must fit (no overlaps, every chair
## reachable, every guard and waiter route point walkable, the jail door, the Race Hall archway and
## the lobby and VIP doorways clear); the map builds the server's floor and draws a new one behind
## the shut doors at every regroup, dealers stand at their tables, and nothing marks a closed spot.
## How well the floors walk: tests/physics/test_floor_walkability.gd.

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


## Everything the map shows matches the server's layout.
func _check_floor() -> void:
	var srv: MatchServer = scene.server
	var map: LuckyLounge = scene.map
	assert_eq(map.floor_plan, srv.floor_plan, "the map stands on the server's floor")
	assert_eq(scene.view.state.floor_plan, srv.floor_plan, "and so does the replicated state")
	assert_eq(scene.view.state.floor_layout, srv.floor_layout)
	for sid: StringName in srv.floor_plan:
		var entry: Array = srv.floor_plan[sid]
		assert_true(map.stations.has(sid), "%s is built" % sid)
		var st: StationBase = map.stations.get(sid, null)
		if st == null:
			continue
		assert_eq(st.game_id, FloorPlan.game_of(entry))
		assert_almost_eq(st.global_position, FloorPlan.pos_of(entry), Vector3.ONE * 0.01, "%s where the layout says" % sid)
		assert_almost_eq(wrapf(st.global_rotation.y - FloorPlan.yaw_of(entry), -PI, PI), 0.0, 0.001, "%s faces where the layout says" % sid)
		assert_false(st.is_vip)
		assert_eq(Vector3(srv.map_def.station_seats[sid][0]), st.seat_position(0), "%s: the server seats people on the real chairs" % sid)
	for sid: StringName in map.stations:
		if map.stations[sid].has_meta(&"floor"):
			assert_true(srv.floor_plan.has(sid), "%s: no leftover table from an earlier layout" % sid)
	for sid: Variant in LuckyLounge.FIXED_STATIONS:
		assert_true(map.stations.has(StringName(sid)), "%s keeps its place" % sid)
	assert_true(map.stations.has(&"fun_blackjack_1"), "the waiting room keeps its tables")
	assert_null(map.find_child("ClosedSpots", true, false), "no closed spots")
	assert_null(map.find_child("TonightsFloor", true, false), "no TONIGHT'S FLOOR board")
	assert_null(map.find_child("ClosedSign", true, false), "no CLOSED TONIGHT sign")
	# Dealers: one per table that has one, at it, on both sides.
	for sid: StringName in srv.floor_plan:
		var game: StringName = FloorPlan.game_of(srv.floor_plan[sid])
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
		assert_true(is_instance_valid(scene.casino_floor.dealers[sid]) and map.stations.has(sid), "%s: no dealer left at a table that went" % sid)


## Static colliders of each floor table touch nothing but their own parts and the floor.
func _check_no_overlaps(label: String) -> void:
	var space: PhysicsDirectSpaceState3D = scene.map.get_world_3d().direct_space_state
	var checked: int = 0
	for sid: StringName in scene.map.stations:
		var root: StationBase = scene.map.stations[sid]
		if not root.has_meta(&"floor"):
			continue
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
					fail_test("%s: %s/%s overlaps %s" % [label, root.name, body.name, other.get_path()])
	assert_gt(checked, 20, "%s: colliders checked" % label)


## The navmesh reaches every chair of every table from just inside the lobby doors, the guards'
## and the waiter's route points are on it, and so are the doorways and the jail door.
func _check_navmesh(label: String) -> void:
	var nav: RID = scene.map.nav_region.get_navigation_map()
	var from: Vector3 = Vector3(0, 0, 6.5)
	for sid: StringName in scene.map.floor_plan:
		var st: StationBase = scene.map.stations[sid]
		for i: int in st.seats.size():
			# The floor by the chair (the table tops are baked too, a little island nobody walks to).
			var target: Vector3 = st.seat_position(i) * Vector3(1, 0, 1)
			var near: Vector3 = NavigationServer3D.map_get_closest_point(nav, target)
			assert_lt(near.y, 0.8, "%s: %s chair %d: the nearest walkable floor is the floor, not a table top (%s)" % [label, sid, i, near])
			assert_lt(Vector2(near.x - target.x, near.z - target.z).length(), 1.2, "%s: walkable floor by %s chair %d (%s)" % [label, sid, i, near])
			var path: PackedVector3Array = NavigationServer3D.map_get_path(nav, from, near, true)
			assert_gt(path.size(), 1, "%s: a path to %s chair %d" % [label, sid, i])
			if path.size() > 0:
				assert_lt(path[path.size() - 1].distance_to(near), 0.3, "%s: the path gets to %s chair %d (at %s, seat %s, path ends %s)" % [label, sid, i, st.global_position, near, path[path.size() - 1]])
	var points: Array[Vector3] = []
	points.append_array(CasinoFloor.WAITER_ROUTE)
	for route: Array in LuckyLounge.GUARD_ROUTES:
		for p: Vector3 in route:
			points.append(p)
	# The jail door (outside the gate), the Race Hall archway, inside the lobby doors, the VIP door
	# from the casino side, and the megaphone stand.
	for p: Vector3 in [Vector3(19.9, 0, -7.5), Vector3(21.0, 0, -13.25), Vector3(0, 0, 7.4), Vector3(0, 0, -15.0), MegaphoneLogic.STAND_POS + Vector3(-1.0, 0, 0)]:
		points.append(p)
	for p: Vector3 in points:
		var near: Vector3 = NavigationServer3D.map_get_closest_point(nav, p)
		assert_lt(Vector2(near.x - p.x, near.z - p.z).length(), 0.6, "%s: %s stays walkable (%s)" % [label, p, near])
		var path: PackedVector3Array = NavigationServer3D.map_get_path(nav, from, near, true)
		if path.size() > 0:
			assert_lt(path[path.size() - 1].distance_to(near), 0.3, "%s: and can be walked to from the doors (%s)" % [label, p])
		else:
			fail_test("%s: no path to %s" % [label, p])


func test_the_full_floor_and_drawn_floors_fit_the_real_floor() -> void:
	var def: MapDefinition = scene.server.map_def
	var geo: FloorGeometry = FloorGeometry.of_map(def, Registry.floor_plan.gap)
	assert_not_null(geo, "the map measured its games")
	for game: StringName in Registry.games:
		if not geo.rects.has(game):
			continue
		var r: Rect2 = geo.rects[game]
		assert_gt(r.size.x * r.size.y, 0.5, "%s measured (%s)" % [game, r])
	var floors: Array[FloorLayout] = [scene.server.full_floor_layout()]
	for s: int in [7, 70, 700, 7000]:
		var t0: int = Time.get_ticks_usec()
		floors.append(scene.server.draw_floor(s))
		gut.p("draw %d: %.1f ms with its checks" % [s, (Time.get_ticks_usec() - t0) / 1000.0])
	for layout: FloorLayout in floors:
		var t0: int = Time.get_ticks_usec()
		var why: Array[String] = FloorPlan.problems(layout, Registry.floor_plan, Registry.games, geo)
		gut.p("%s: fit check %.1f ms" % [layout.id, (Time.get_ticks_usec() - t0) / 1000.0])
		assert_eq(why, [] as Array[String], "%s fits the map (overlap, keep-out and walkway checks)" % layout.id)
		assert_eq(scene.server.floor_problems(layout), [] as Array[String], "%s can stand on the server" % layout.id)
		scene.map.apply_floor_plan(layout.wire_stations())
		await _wait_navmesh()
		_check_no_overlaps(String(layout.id))
		_check_navmesh(String(layout.id))


func test_the_layout_changes_behind_the_doors_at_every_regroup() -> void:
	var srv: MatchServer = scene.server
	assert_eq(srv.floor_round, 1, "Practice put a layout in (forced rotation)")
	_check_floor()
	await _wait_navmesh()
	_check_no_overlaps(String(srv.floor_layout))
	for round_i: int in [2, 3]:
		var before: StringName = srv.floor_layout
		assert_true(_skip_until(func() -> bool: return srv.phases.phase == Phase.Id.REGROUP))
		assert_eq(srv.floor_round, round_i)
		assert_ne(srv.floor_layout, before, "another floor")
		assert_false(scene.map.lobby_open, "the doors are shut while the floor changes")
		await wait_physics_frames(2)
		_check_floor()
		var feed: Array = events.filter(func(e: Dictionary) -> bool: return e["type"] == &"regroup_started")
		assert_eq(int(feed[feed.size() - 1]["floor_plan"]["round"]), round_i)
		assert_eq(StringName(feed[feed.size() - 1]["floor_plan"]["layout"]), srv.floor_layout)
		await _wait_navmesh()
		_check_no_overlaps(String(srv.floor_layout))
		assert_true(scene.local.state != PlayerAvatar.State.SEATED)
		assert_true(_skip_until(func() -> bool: return srv.phases.phase == Phase.Id.CASINO))
		assert_true(srv.economy.balance(scene.local_id) >= 0)
