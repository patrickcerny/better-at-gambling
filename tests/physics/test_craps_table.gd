extends GutTest
## The craps table on a client: the server's roll arrives with a throw seed, the two dice leave the
## shooter's hand, tumble inside the rails and rest showing exactly the server's faces before the
## server pays; a late joiner catches the throw mid-air; chips go on the seat's own spot; a seat's
## camera sees the felt end to end. And in the real casino: the table stands clear of everything.

var view: SubViewport
var cs: CrapsStation


func before_each() -> void:
	Vfx.force_enabled = true
	view = SubViewport.new()
	view.size = Vector2i(1920, 1080)
	add_child_autofree(view)
	cs = CrapsStation.new()
	view.add_child(cs)
	await wait_process_frames(1)


func after_each() -> void:
	Vfx.force_enabled = false


## World AABBs of the table's rail and body colliders.
func _solid_boxes(root: Node) -> Array[AABB]:
	var out: Array[AABB] = []
	for n: Node in root.find_children("*", "CollisionShape3D", true, false):
		var c: CollisionShape3D = n
		if c.shape != null and not c.get_parent() is Area3D:
			out.append(c.global_transform * c.shape.get_debug_mesh().get_aabb())
	return out


func _die_box(d: Node3D) -> AABB:
	var h: float = CrapsDice.HALF
	var corners: Array[Vector3] = []
	for x: float in [-h, h]:
		for y: float in [-h, h]:
			for z: float in [-h, h]:
				corners.append(d.global_transform * Vector3(x, y, z))
	var box := AABB(corners[0], Vector3.ZERO)
	for c: Vector3 in corners:
		box = box.expand(c)
	return box


func test_dice_rest_on_the_servers_faces_inside_the_rails() -> void:
	assert_eq(cs.dice_nodes.size(), 2, "two dice, no more")
	var walls: Array[AABB] = _solid_boxes(cs)
	var felt: Rect2 = CrapsStation.felt_rect()
	var r := RandomNumberGenerator.new()
	r.seed = 2026
	for k: int in 12:
		var faces: Array = [r.randi_range(1, 6), r.randi_range(1, 6)]
		var seed_value: int = 7919 * (k + 1)
		var seat: int = k % 7 - 1
		var wait: float = cs.throw(faces, seed_value, seat)
		assert_lte(wait, CrapsDice.REST_TIME, "seed %d: rests within the dice time" % seed_value)
		assert_lt(wait, Registry.balance.craps_throw_time, "before the server settles the bets")
		assert_true(cs.rolling())
		var t: float = 0.0
		var dt: float = 1.0 / 60.0
		while t < Registry.balance.craps_throw_time:
			cs._tick_dice(dt)
			t += dt
			for d: Node3D in cs.dice_nodes:
				var p: Vector3 = d.position
				assert_true(felt.has_point(Vector2(p.x, p.z)), "seed %d at %.2f s: on the felt (%s)" % [seed_value, t, p])
				assert_gt(p.y, CrapsStation.FELT_Y, "above the felt")
				var box: AABB = _die_box(d).grow(-0.002)
				for w: AABB in walls:
					assert_false(box.intersects(w), "seed %d at %.2f s: never inside a rail or off the table" % [seed_value, t])
			if t >= wait + dt:
				assert_false(cs.rolling(), "still once it says so")
		assert_eq(cs.shown_faces(), CrapsStation._ints(faces), "seed %d seat %d: the dice show the server's roll %s" % [seed_value, seat, str(faces)])
		for d: Node3D in cs.dice_nodes:
			assert_almost_eq(d.position.y, CrapsStation.FELT_Y + CrapsDice.HALF, 0.002, "lying on the felt")
			var up: Vector3 = d.transform.basis * CrapsDice.FACE_NORMALS[CrapsDice.face_up(d.transform.basis) - 1]
			assert_gt(up.normalized().y, 0.999, "flat, not leaning on an edge")
		assert_gt(cs.dice_nodes[0].position.distance_to(cs.dice_nodes[1].position), CrapsDice.EDGE, "the dice rest apart")


func test_the_throw_runs_on_its_own_in_real_time() -> void:
	var wait: float = cs.throw([6, 1], 31337, 2)
	await wait_seconds(wait + 0.3)
	assert_false(cs.rolling())
	assert_eq(cs.shown_faces(), [6, 1] as Array[int])


func test_late_joiner_catches_the_throw_in_the_air() -> void:
	var seat_of: Callable = func(_pid: int) -> int: return 3
	cs.show_state({"state": CrapsLogic.State.ROLLING, "point": 8, "dice": [2, 2], "throw_seed": 4242, "roll_time": 0.4, "thrown_by": 5}, seat_of)
	assert_eq(cs.throw_seed, 4242)
	var plan: Dictionary = CrapsDice.simulate(4242, CrapsStation.throw_from(3), CrapsStation.throw_target(3), CrapsStation.felt_rect(), CrapsStation.FELT_Y, [2, 2])
	assert_almost_eq(cs.dice_nodes[0].position, CrapsDice.sample(plan, 0, 0.4).origin, Vector3.ONE * 0.001, "where every other client has it")
	assert_eq(cs.puck_label.text, "ON")
	assert_lt(absf(cs.puck.position.x - CrapsStation.point_spot(8).x), CrapsStation.POINT_W * 0.5, "the puck on the 8")
	for _i: int in 200:
		cs._tick_dice(1.0 / 60.0)
	assert_eq(cs.shown_faces(), [2, 2] as Array[int])
	# A client that only sees the result puts the dice down showing it.
	cs.reset_table()
	cs.show_state({"state": CrapsLogic.State.RESULT, "point": 0, "dice": [3, 5], "throw_seed": 99, "outcome": &"point_set"})
	assert_eq(cs.shown_faces(), [3, 5] as Array[int])
	assert_eq(cs.puck_label.text, "OFF")
	cs.show_result(8, &"point_set", 8)
	assert_string_contains(cs.sign_roll.text, "8")
	assert_string_contains(cs.sign_point.text, "POINT  8")


func test_seat_camera_sees_the_felt_and_the_sign() -> void:
	var cam := Camera3D.new()
	cam.fov = 75.0
	view.add_child(cam)
	var rect := Rect2(Vector2.ZERO, Vector2(view.size))
	cam.global_transform = cs.camera_for_seat(0).global_transform
	var points: Array[Vector3] = [
		Vector3(-CrapsStation.FELT_HX, CrapsStation.FELT_Y, 0.0), Vector3(CrapsStation.FELT_HX, CrapsStation.FELT_Y, 0.0),
		Vector3(0.0, CrapsStation.FELT_Y, -CrapsStation.FELT_HZ), CrapsStation.bet_spot(&"pass", 0), CrapsStation.bet_spot(&"pass", 5),
		CrapsStation.bet_spot(&"any_seven", 3), Vector3(0.0, 2.15, -CrapsStation.TABLE_D * 0.5 - 0.95),
	]
	for p: Vector3 in points:
		var g: Vector3 = cs.to_global(p)
		assert_false(cam.is_position_behind(g), "faces %s" % p)
		assert_true(rect.has_point(cam.unproject_position(g)), "sees %s" % p)
	# The near rail hides none of the bets: nothing solid between the eye and any printed spot
	# (the players' own Pass Line included), for every seat.
	await wait_physics_frames(2)
	var space: PhysicsDirectSpaceState3D = cs.get_world_3d().direct_space_state
	for seat: int in CrapsStation.SEAT_XS.size():
		for t: StringName in CrapsLogic.BET_TYPES:
			var spot: Vector3 = cs.to_global(CrapsStation.bet_spot(t, seat) + Vector3(0, 0.01, 0.06))
			var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position, spot))
			assert_true(hit.is_empty(), "seat view sees the %s spot of seat %d over the rail" % [t, seat])
	cam.free()


func test_chips_land_on_the_seat_spot_of_each_bet() -> void:
	var w := Node3D.new()
	view.add_child(w)
	var fx := TableFx.new()
	add_child_autofree(fx)
	fx.setup({&"c": cs}, func(_p: int) -> PlayerAvatar: return null, 1, null, w,
		func(pid: int) -> Color: return Palette.player_color(pid - 1), func(_sid: StringName) -> int: return 10)
	for t: StringName in CrapsLogic.BET_TYPES:
		fx.on_event({"type": &"bet_placed", "player": 1, "station": &"c", "amount": 20, "details": {"game": "craps", "type": t, "value": 0}})
	await wait_seconds(0.8)
	var found: Dictionary = {}
	for c: Node in cs.get_children():
		if not c is ChipStack:
			continue
		var p: Vector3 = (c as ChipStack).position
		for t: StringName in CrapsLogic.BET_TYPES:
			var spot: Vector3 = CrapsStation.bet_spot(t, 0)
			if absf(p.x - spot.x) < 0.08 and absf(p.z - spot.z) < 0.1:
				found[t] = true
	assert_eq(found.size(), 4, "one stack on each printed bet: %s" % str(found.keys()))
	# The dice event goes through TableFx to the table.
	fx.on_event({"type": &"craps_rolled", "station": &"c", "shooter": -1, "dice": [4, 3], "seed": 555, "seconds": 2.6, "point": 0})
	assert_true(cs.rolling())
	fx.on_event({"type": &"craps_result", "station": &"c", "dice": [4, 3], "total": 7, "outcome": &"natural", "point": 0})
	assert_string_contains(cs.sign_roll.text, "7")


func test_the_table_stands_clear_in_the_casino() -> void:
	Vfx.force_enabled = false
	Net.stop()
	var scene: MatchScene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_seconds(3.3)
	var table: CrapsStation = scene.map.stations.get(&"craps_1", null) as CrapsStation
	assert_not_null(table, "the craps table is on the floor")
	if table == null:
		return
	var mine: Array[AABB] = _solid_boxes(table)
	assert_gt(mine.size(), 5)
	for n: Node in scene.map.find_children("*", "CollisionShape3D", true, false):
		var c: CollisionShape3D = n
		if c.shape == null or table.is_ancestor_of(c) or c.get_parent() is CharacterBody3D or c.get_parent() is RigidBody3D or c.get_parent() is Area3D:
			continue
		var other: AABB = c.global_transform * c.shape.get_debug_mesh().get_aabb()
		if other.size.y < 0.05:
			continue  # the floor
		for a: AABB in mine:
			assert_false(a.grow(-0.02).intersects(other), "craps table overlaps %s at %s" % [c.get_parent().name, other])
	# Every stool and the stickman's spot can be walked to.
	var t: float = 0.0
	while not scene.map.navmesh_ready and t < 5.0:
		await wait_seconds(0.2)
		t += 0.2
	var nav: RID = scene.map.nav_region.get_navigation_map()
	for i: int in table.seats.size():
		var spot: Vector3 = table.to_global(Vector3(CrapsStation.SEAT_XS[i], 0, CrapsStation.SEAT_Z + 0.6))
		for from: Vector3 in [Vector3(9, 0, -9), Vector3(12, 0, 2)]:
			var path: PackedVector3Array = NavigationServer3D.map_get_path(nav, from, spot, true)
			assert_gt(path.size(), 0, "a path to stool %d" % i)
			if path.size() > 0:
				assert_lt(path[path.size() - 1].distance_to(spot), 0.6, "from %s right up to stool %d" % [from, i])
	var dealer: Dealer = scene.casino_floor.dealers.get(&"craps_1", null)
	assert_not_null(dealer, "the stickman stands at the table")
	if dealer != null:
		assert_almost_eq(dealer.global_position.y, 0.0, 0.05, "on the floor")
		assert_lt(table.to_local(dealer.global_position).z, -CrapsStation.TABLE_D * 0.5 - 0.4, "outside the tub")
