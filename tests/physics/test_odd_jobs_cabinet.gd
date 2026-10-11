extends GutTest
## The Odd Jobs cabinet in the real match scene: built next to the Gift Shop, clear of everything
## else, reachable over the navmesh, and the walk-up → E → smash → E flow.

var scene: MatchScene


func before_each() -> void:
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_seconds(3.3)
	assert_eq(scene.server.phases.phase, Phase.Id.CASINO, "casino phase after the intro")


## World AABB of every collider under `root` (by name prefix of its body).
func _boxes(root: Node, prefix: String, include: bool) -> Array[AABB]:
	var out: Array[AABB] = []
	for n: Node in root.find_children("*", "CollisionShape3D", true, false):
		var cs: CollisionShape3D = n
		var body: Node = cs.get_parent()
		if body.name.begins_with(prefix) != include or cs.shape == null:
			continue
		out.append(cs.global_transform * cs.shape.get_debug_mesh().get_aabb())
	return out


func test_cabinet_sits_next_to_the_gift_shop_without_overlaps() -> void:
	assert_not_null(scene.map.find_child("OddJobsCabinet", true, false), "cabinet is built")
	assert_not_null(scene.map.odd_jobs_button)
	var mine: Array[AABB] = _boxes(scene.map, "OddJobs", true)
	assert_eq(mine.size(), 2, "cabinet body and its back")
	var shop: Node3D = scene.map.find_child("ShopCounter", true, false)
	assert_lt(Vector2(LuckyLounge.ODD_JOBS_CABINET.x - shop.global_position.x, LuckyLounge.ODD_JOBS_CABINET.z - shop.global_position.z).length(), 3.0, "next to the Gift Shop")
	assert_lt(LuckyLounge.ODD_JOBS_CABINET.z, LuckyLounge.SHOP_POS.z, "on the shop's free (north) side, away from the bar")
	for other: AABB in _boxes(scene.map, "OddJobs", false):
		for a: AABB in mine:
			assert_false(a.grow(-0.02).intersects(other), "cabinet overlaps a collider at %s" % other)
	# Room to stand in front of it: nothing solid where the player stands.
	var q := PhysicsShapeQueryParameters3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.4
	cyl.height = 1.4
	q.shape = cyl
	q.transform = Transform3D(Basis(), LuckyLounge.ODD_JOBS_POS + Vector3(0, 0.8, 0))
	q.collision_mask = 1
	assert_eq(scene.map.get_world_3d().direct_space_state.intersect_shape(q).size(), 0, "stand spot is clear")


func test_cabinet_is_reachable_over_the_navmesh() -> void:
	var t: float = 0.0
	while not scene.map.navmesh_ready and t < 5.0:
		await wait_seconds(0.2)
		t += 0.2
	assert_true(scene.map.navmesh_ready)
	var nav: RID = scene.map.nav_region.get_navigation_map()
	for from: Vector3 in [Vector3(0, 0, 0), Vector3(12, 0, -8), LuckyLounge.SHOP_POS]:
		var path: PackedVector3Array = NavigationServer3D.map_get_path(nav, from, LuckyLounge.ODD_JOBS_POS, true)
		assert_gt(path.size(), 0, "a path from %s" % from)
		if path.size() > 0:
			var end: Vector3 = path[path.size() - 1]
			assert_lt(Vector2(end.x - LuckyLounge.ODD_JOBS_POS.x, end.z - LuckyLounge.ODD_JOBS_POS.z).length(), 0.5, "path ends at the stand spot")
	# The Gift Shop is still reachable too.
	var shop_path: PackedVector3Array = NavigationServer3D.map_get_path(nav, Vector3(0, 0, 0), LuckyLounge.SHOP_POS, true)
	assert_lt(Vector2(shop_path[shop_path.size() - 1].x - LuckyLounge.SHOP_POS.x, shop_path[shop_path.size() - 1].z - LuckyLounge.SHOP_POS.z).length(), 0.5)


func _space() -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_SPACE
	k.keycode = KEY_SPACE
	k.pressed = true
	Input.parse_input_event(k)
	await wait_process_frames(1)
	var up: InputEventKey = k.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await wait_seconds(0.1)


func test_walk_up_press_e_and_smash() -> void:
	var me: int = scene.local_id
	scene.server.economy.take_up_to(me, 1000000, &"test")
	await wait_seconds(0.3)  # a House Comp may land first
	scene.local.teleport(LuckyLounge.ODD_JOBS_POS, -PI / 2.0)
	scene.server.set_server_position(me, LuckyLounge.ODD_JOBS_POS)
	await wait_seconds(0.3)
	assert_string_contains(scene.hud.prompt_label.text, "ODD JOBS")
	scene.router.interact.emit()
	await wait_process_frames(2)
	assert_true(scene.odd_jobs_panel.visible, "E opens the cabinet")
	assert_eq(scene.router.mode, InputRouter.Mode.MENU)
	var before: int = scene.server.economy.balance(me)
	var needed: int = OddJobs.presses_needed(before)
	for i: int in needed:
		await _space()
	assert_eq(scene.server.economy.balance(me), before + OddJobs.PAYOUT, "a full bar pays $50")
	# Rich: refused, the button greys out.
	scene.server.economy.apply(me, OddJobs.CAP, &"test")
	await wait_seconds(0.3)
	assert_true(scene.odd_jobs_panel.is_refused())
	var refused_at: int = scene.server.economy.balance(me)
	await _space()
	assert_eq(scene.server.economy.balance(me), refused_at)
	assert_string_contains((scene.odd_jobs_panel.find_child("Note", true, false) as Label).text, "Go gamble")
	scene.odd_jobs_panel.close_panel()
	await wait_process_frames(2)
	assert_false(scene.odd_jobs_panel.visible)
	assert_eq(scene.router.mode, InputRouter.Mode.WALK)
