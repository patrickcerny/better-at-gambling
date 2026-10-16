extends GutTest
## The scratch-card kiosk in the real match scene: the counter stands in the start room west of the
## settings tablet, clear of every other collider, its attendant on the floor behind it; the spot
## in front of the stool is free and reachable over the navmesh from the start room and the casino;
## sitting down opens the card panel, a bought card slides onto the counter and is gone once it has
## paid.

const SID: StringName = &"scratch_1"

var scene: MatchScene


func before_each() -> void:
	Vfx.force_enabled = true
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_seconds(3.3)
	assert_eq(scene.server.phases.phase, Phase.Id.CASINO, "casino phase after the intro")


func after_each() -> void:
	Vfx.force_enabled = false


func _kiosk() -> ScratchStation:
	return scene.map.stations[SID] as ScratchStation


## Where a player walks up to: in front of the stool, on the room side.
func _approach() -> Vector3:
	var st: ScratchStation = _kiosk()
	var p: Vector3 = st.to_global(Vector3(0, 0, 1.55))
	p.y = 0.0
	return p


## World AABBs of the solid colliders under `root` (bodies only, not trigger areas).
func _solids(root: Node, mine: Node, include_mine: bool) -> Array[AABB]:
	var out: Array[AABB] = []
	for n: Node in root.find_children("*", "CollisionShape3D", true, false):
		var cs: CollisionShape3D = n
		if cs.shape == null or not cs.get_parent() is PhysicsBody3D or cs.disabled:
			continue
		if mine.is_ancestor_of(cs) != include_mine:
			continue
		out.append(cs.global_transform * cs.shape.get_debug_mesh().get_aabb())
	return out


func test_kiosk_stands_where_the_map_says_without_overlaps() -> void:
	var st: ScratchStation = _kiosk()
	assert_not_null(st, "the kiosk is built from the STATIONS table")
	assert_eq(st.game_id, &"scratch")
	assert_almost_eq(st.global_position, Vector3(-19, 0, 10), Vector3.ONE * 0.001)
	assert_almost_eq(st.rotation.y, PI * 0.5, 0.001, "the counter faces east into the room")
	assert_lt(st.global_position.z, LuckyLounge.SIZE_Z * 0.5, "inside the start room")
	assert_gt(st.global_position.z, LuckyLounge.LOBBY_DOORS_Z, "south of the lobby doors")
	var mine: Array[AABB] = _solids(scene.map, st, true)
	assert_gte(mine.size(), 4, "counter, attendant, board posts and stool are solid")
	for other: AABB in _solids(scene.map, st, false):
		for a: AABB in mine:
			assert_false(a.grow(-0.02).intersects(other), "kiosk part %s overlaps a collider at %s" % [a, other])
	var tablet: Vector3 = LuckyLounge.SETTINGS_TABLET_POS
	assert_gt(Vector2(tablet.x - st.global_position.x, tablet.z - st.global_position.z).length(), LuckyLounge.SETTINGS_TABLET_RANGE + st.interact_radius, "the tablet's E and the kiosk's E never compete")
	for sid: StringName in scene.map.stations:
		if sid != SID:
			var o: StationBase = scene.map.stations[sid]
			assert_gt(o.global_position.distance_to(st.global_position), o.interact_radius + st.interact_radius, "%s is far enough" % sid)
	assert_not_null(st.attendant, "the attendant stands behind the counter")
	assert_almost_eq(st.attendant.global_position.y, 0.0, 0.001, "feet on the floor")
	var behind: Vector3 = st.to_local(st.attendant.global_position)
	assert_lt(behind.z, -ScratchStation.COUNTER_SIZE.z * 0.5, "behind the counter, not in it")


func test_the_stand_spot_is_free_and_reachable() -> void:
	var spot: Vector3 = _approach()
	var q := PhysicsShapeQueryParameters3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.35
	cyl.height = 1.4
	q.shape = cyl
	q.transform = Transform3D(Basis(), spot + Vector3(0, 0.8, 0))
	q.collision_mask = 1
	assert_eq(scene.map.get_world_3d().direct_space_state.intersect_shape(q).size(), 0, "nothing solid where you walk up")
	assert_lt(Vector2(spot.x - _kiosk().seat_position(0).x, spot.z - _kiosk().seat_position(0).z).length(), _kiosk().interact_radius, "close enough to sit from there")
	var t: float = 0.0
	while not scene.map.navmesh_ready and t < 5.0:
		await wait_seconds(0.2)
		t += 0.2
	assert_true(scene.map.navmesh_ready)
	var nav: RID = scene.map.nav_region.get_navigation_map()
	for from: Vector3 in [Vector3(0, 0, 12.3), Vector3(-7, 0, 10.0), Vector3(0, 0, 0)]:
		var path: PackedVector3Array = NavigationServer3D.map_get_path(nav, from, spot, true)
		assert_gt(path.size(), 0, "a path from %s" % from)
		if path.size() > 0:
			var end: Vector3 = path[path.size() - 1]
			assert_lt(Vector2(end.x - spot.x, end.z - spot.z).length(), 0.5, "from %s the path ends at the counter" % from)


func test_sit_buy_reveal_through_the_scene() -> void:
	var st: ScratchStation = _kiosk()
	var spot: Vector3 = _approach()
	scene.local.teleport(spot, 0.0)
	scene.server.set_server_position(scene.local_id, spot)
	await wait_physics_frames(2)
	var res: Dictionary = Net.send_intent(Intents.make(&"sit", {"station": SID}))
	assert_true(res["ok"], "sit: %s" % res)
	await wait_physics_frames(3)
	assert_true(scene.current_ui is ScratchUi, "the card panel opens")
	var ui: ScratchUi = scene.current_ui as ScratchUi
	assert_true(ui.visible)
	assert_true(scene.router.look_locked, "the head stays put while scratching")
	assert_string_contains(st.prompt_text(10), "scratch card")
	assert_true(ui.buy(0), "buy a $10 card")
	await wait_seconds(0.8)
	assert_true(ui.card_open(), "the server's card is under the foil")
	assert_true(st.card_mesh.visible, "and lies on the counter")
	assert_almost_eq(st.card_mesh.position, ScratchStation.CARD_SPOT, Vector3.ONE * 0.01, "slid out of the dispenser onto the mat")
	var before: int = scene.server.economy.balance(scene.local_id)
	ui.reveal_all()
	await wait_seconds(ScratchCardView.REVEAL_STEP * 9 + 0.6)
	assert_true(ui.card_view.is_fully_revealed())
	assert_false(scene.server.stations.has_stake(scene.local_id), "paid once it was bare")
	var won: int = ScratchUi.prize_of(ui.shown_card, 0, 10)
	if not scene.server.stations.hot.has(SID):
		assert_eq(scene.server.economy.balance(scene.local_id), before + won, "the printed prize")
	# The empty kiosk reaches the client with the next snapshot (later on a busy runner).
	await wait_until(func() -> bool: return not st.card_mesh.visible, 2.0)
	assert_false(st.card_mesh.visible, "the paid card is off the counter")
