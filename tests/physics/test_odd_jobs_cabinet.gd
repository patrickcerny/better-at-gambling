extends GutTest
## The Odd Jobs cabinet in the real match scene: built next to the Gift Shop, clear of everything
## else, reachable over the navmesh; look at the 3D button and click to press it (no window), the
## bar and text live on the cabinet, and the lamps glow only while you are broke.

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
	assert_lt(Vector2(LuckyLounge.ODD_JOBS_CABINET.x - shop.global_position.x, LuckyLounge.ODD_JOBS_CABINET.z - shop.global_position.z).length(), 4.0, "near the Gift Shop (a plant apart, Patrick)")
	assert_lt(LuckyLounge.ODD_JOBS_CABINET.z, LuckyLounge.SHOP_POS.z, "on the shop's north side")
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


## Stands the local player at the cabinet, facing it, and pitches the camera at `target` (world;
## Vector3.INF: turned 90 degrees, looking along the room instead).
func _stand_and_look(target: Vector3) -> void:
	var me: int = scene.local_id
	scene.local.teleport(LuckyLounge.ODD_JOBS_POS, -PI / 2.0)
	scene.server.set_server_position(me, LuckyLounge.ODD_JOBS_POS)
	await wait_process_frames(2)
	var cam: PlayerCamera = scene.local.cam
	cam.pitch = 0.0
	await wait_process_frames(2)
	var on: bool = target.is_finite()
	if on:
		var d: Vector3 = target - cam.camera.global_position
		cam.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	else:
		cam.yaw += PI / 2.0
	# The camera settles over a few frames and the HUD prompt reads the aim a frame after the
	# controller sets it: wait for the aim, then one more frame for the prompt (slow runners).
	for i: int in 30:
		await wait_process_frames(1)
		if scene.odd_jobs.aimed == on:
			break
	await wait_process_frames(2)


## Broke without the House Comp topping you up again (it pays once per segment).
func _go_broke() -> void:
	var me: int = scene.local_id
	scene.server.economy.take_up_to(me, 1000000, &"test")
	await wait_seconds(0.3)  # a House Comp may land first
	scene.server.economy.take_up_to(me, 1000000, &"test")
	await wait_seconds(0.2)


func _click() -> void:
	scene.router.grab_pressed.emit()
	await wait_seconds(0.1)


func test_look_at_the_button_and_click_it() -> void:
	var me: int = scene.local_id
	await _go_broke()
	assert_eq(scene.server.economy.balance(me), 0)
	await _stand_and_look(scene.map.odd_jobs.button_center())
	assert_true(scene.odd_jobs.aimed, "looking at the button")
	assert_string_contains(scene.hud.prompt_label.text, "SMASH")
	assert_null(scene.find_child("OddJobsPanel", true, false) as Control, "no popup window any more")
	assert_eq(scene.router.mode, InputRouter.Mode.WALK, "you stay in the world")
	var cab: OddJobsCabinet = scene.map.odd_jobs
	var needed: int = OddJobs.presses_needed(0)
	await _click()
	assert_almost_eq(scene.server.odd_jobs.fill(), 1.0 / needed, 0.001, "one click = one press")
	assert_gt(cab.shown_fill, 0.0, "the bar on the cabinet fills")
	scene.router.grab_pressed.emit()
	await wait_process_frames(2)
	assert_lt(cab.button.position.y, OddJobsCabinet.BUTTON_POS.y, "the button dips")
	await wait_seconds(0.3)
	assert_almost_eq(cab.button.position.y, OddJobsCabinet.BUTTON_POS.y, 0.001, "and springs back")
	for i: int in needed - 3:
		await _click()
	assert_eq(scene.server.economy.balance(me), 0, "not paid before the bar is full")
	scene.router.interact.emit()  # E presses it too
	await wait_seconds(0.2)
	assert_eq(scene.server.economy.balance(me), OddJobs.PAYOUT, "the click that fills it pays $50")
	assert_string_contains(cab.note_label.text, "YOUR CLICK")
	assert_almost_eq(cab.shown_fill, 0.0, 0.01, "the bar on the cabinet starts over")
	# Rich: refused, with the note on the cabinet.
	scene.server.economy.apply(me, OddJobs.CAP, &"test")
	await wait_seconds(0.3)
	var rich: int = scene.server.economy.balance(me)
	await _click()
	assert_eq(scene.server.economy.balance(me), rich)
	assert_eq(scene.server.odd_jobs.fill(), 0.0)
	assert_string_contains(cab.note_label.text, "Go gamble")


func test_looking_away_does_not_press() -> void:
	await _go_broke()
	await _stand_and_look(Vector3.INF)
	assert_false(scene.odd_jobs.aimed, "looking along the room, not at the cabinet")
	assert_string_contains(scene.hud.prompt_label.text, "look at the big red button")
	await _click()
	scene.router.interact.emit()
	await wait_seconds(0.2)
	assert_eq(scene.server.odd_jobs.fill(), 0.0, "no press without looking at it")
	# Far away and looking its way: still nothing.
	scene.local.teleport(Vector3(14, 0, -0.95), -PI / 2.0)
	scene.server.set_server_position(scene.local_id, Vector3(14, 0, -0.95))
	await wait_process_frames(3)
	assert_false(scene.odd_jobs.aimed, "out of reach")


func test_deck_edge_counts_and_every_fast_click_lands() -> void:
	# Patrick: "the red button click thing is too small its very hard to target it" and "no rate
	# limit": aim at the deck's front edge, well off the cap, and click 30 times in one second.
	var me: int = scene.local_id
	var cab: OddJobsCabinet = scene.map.odd_jobs
	await _go_broke()
	scene.server.economy.apply(me, 499, &"test")  # 60 clicks a bar: 30 clicks = half of it
	await wait_process_frames(2)
	var edge: Vector3 = cab.global_transform * Vector3(-0.43, 1.08, 0.0)
	assert_gt(Vector2(edge.x - cab.button_center().x, edge.z - cab.button_center().z).length(), 0.3, "off the cap")
	await _stand_and_look(edge)
	assert_true(scene.odd_jobs.aimed, "the deck's edge counts as aiming")
	assert_string_contains(scene.hud.prompt_label.text, "SMASH")
	assert_not_null(cab.button.get_node("Mesh").material_overlay, "the outline shows the aim")
	var needed: int = OddJobs.presses_needed(scene.server.economy.balance(me))
	assert_eq(needed, 60)
	var t0: int = Time.get_ticks_msec()
	for i: int in 30:
		scene.router.grab_pressed.emit()
		await wait_seconds(0.03)
	assert_lt(Time.get_ticks_msec() - t0, 1500, "a one-second burst")
	assert_almost_eq(scene.server.odd_jobs.fill(), 30.0 / needed, 0.001, "all 30 clicks reached the server")
	assert_eq(scene.server.economy.balance(me), 499)


func test_glow_only_while_broke() -> void:
	var me: int = scene.local_id
	var cab: OddJobsCabinet = scene.map.odd_jobs
	assert_gt(scene.server.economy.balance(me), OddJobsController.broke_line(scene.cfg, 0))
	await wait_process_frames(2)
	assert_false(cab.glowing, "no glow with money")
	assert_false(cab.lamp_light.visible)
	assert_null(cab.button.get_node("Mesh").material_overlay, "no outline with money")
	await _go_broke()
	assert_true(cab.glowing, "broke: the cabinet glows")
	assert_true(cab.lamp_light.visible)
	assert_not_null(cab.button.get_node("Mesh").material_overlay, "and the button is outlined")
	assert_true(bool(Settings.get_value("hints", "odd_jobs", false)), "the one-time hint went out")
	scene.server.economy.apply(me, 100, &"test")
	await wait_seconds(0.3)
	assert_false(cab.glowing, "money again: glow off")
	assert_false(cab.lamp_light.visible)


## Under $50 (Patrick: "Indicator wenn man broke ist (weniger geld als 50) zum button"): a beacon
## floats over the cabinet and, while the cabinet is off screen, a gold arrow on the screen edge
## points at it; both go at the cabinet and once you have $50 again.
func test_under_50_points_the_way_to_the_button() -> void:
	var me: int = scene.local_id
	var cab: OddJobsCabinet = scene.map.odd_jobs
	await wait_process_frames(2)
	assert_false(cab.beacon.visible, "no beacon with money")
	assert_true(scene.hud.odd_jobs_pointer == null or not scene.hud.odd_jobs_pointer.visible, "no arrow with money")
	await _go_broke()
	scene.server.economy.apply(me, 30, &"test")
	await wait_seconds(0.3)
	assert_eq(scene.server.economy.balance(me), 30)
	assert_gt(30, OddJobsController.broke_line(scene.cfg, 0), "$30 is over the House Comp line")
	assert_true(scene.odd_jobs.broke, "$30 counts as broke")
	# Across the casino with the cabinet behind you: beacon up and the arrow on the screen edge.
	var away: Vector3 = Vector3(0, 0, 0)
	scene.local.teleport(away, PI / 2.0)
	scene.server.set_server_position(me, away)
	await wait_process_frames(6)
	assert_true(cab.beacon.visible, "the beacon floats over the cabinet")
	assert_not_null(scene.hud.odd_jobs_pointer)
	assert_true(scene.hud.odd_jobs_pointer.visible, "an arrow points the way")
	assert_true(scene.hud.odd_jobs_tag.visible, "with its ODD JOBS tag")
	var screen: Rect2 = scene.get_viewport().get_visible_rect()
	assert_true(screen.has_point(scene.hud.odd_jobs_pointer.position), "the arrow stays on screen")
	var c: Vector2 = scene.hud.odd_jobs_tag.position + scene.hud.odd_jobs_tag.size * 0.5
	assert_true(screen.has_point(c), "and so does its tag")
	# At the cabinet: no beacon, no arrow (the lamps and the outline take over).
	await _stand_and_look(scene.map.odd_jobs.button_center())
	assert_false(cab.beacon.visible, "no beacon at the cabinet")
	assert_false(scene.hud.odd_jobs_pointer.visible, "no arrow at the cabinet")
	assert_true(cab.glowing, "the cabinet still glows")
	# Back across the room, then $50: everything goes.
	scene.local.teleport(away, PI / 2.0)
	scene.server.set_server_position(me, away)
	await wait_process_frames(6)
	assert_true(scene.hud.odd_jobs_pointer.visible)
	scene.server.economy.apply(me, 20, &"test")
	await wait_seconds(0.3)
	assert_eq(scene.server.economy.balance(me), OddJobsController.BROKE_BELOW)
	assert_false(scene.odd_jobs.broke, "$50 is not broke")
	assert_false(cab.beacon.visible, "beacon gone at $50")
	assert_false(scene.hud.odd_jobs_pointer.visible, "arrow gone at $50")
	assert_false(cab.glowing)


func test_is_broke_under_50_or_the_comp_line() -> void:
	assert_true(OddJobsController.is_broke(49, 10))
	assert_false(OddJobsController.is_broke(50, 10))
	assert_true(OddJobsController.is_broke(70, 80), "a higher comp line wins")
	assert_false(OddJobsController.is_broke(80, 80))
