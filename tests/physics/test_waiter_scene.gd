extends GutTest
## The waiter NPC and the Megaphone in the real match scene (M7): the waiter walks his navmesh
## route and the server knows where he is; a server-decided trip shows the fall and a puddle; the
## megaphone is picked up with E at its stand.

var scene: MatchScene


func before_each() -> void:
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	scene.server.timescale = 1.0
	await wait_seconds(3.3)
	assert_eq(scene.server.phases.phase, Phase.Id.CASINO)


func test_waiter_walks_and_reports_to_the_server() -> void:
	var guard: int = 0
	while scene.casino_floor.waiter == null and guard < 300:
		await wait_physics_frames(1)
		guard += 1
	var w: Waiter = scene.casino_floor.waiter
	assert_not_null(w, "spawned once the navmesh is ready")
	var start: Vector3 = w.global_position
	await wait_seconds(3.0)
	assert_gt(w.global_position.distance_to(start), 1.5, "walks his route")
	assert_almost_eq(scene.server.waiter.position.distance_to(w.global_position), 0.0, 0.3, "the server knows where he is")


func test_server_trip_shows_fall_and_puddle_then_he_gets_up() -> void:
	while scene.casino_floor.waiter == null:
		await wait_physics_frames(1)
	await wait_seconds(0.3)
	var w: Waiter = scene.casino_floor.waiter
	# He may already have tripped on his own (about once every 40 s), so count from here.
	var puddles_before: int = scene.view.state.puddles.size()
	scene.server.waiter.trip(scene.server.match_time, &"clumsy", -1)
	await wait_seconds(0.3)
	assert_true(w.down, "on the floor")
	assert_eq(scene.view.state.puddles.size(), puddles_before + 1)
	assert_true(scene.casino_floor.puddle_nodes.is_empty(), "no meshes on a headless run (the screenshot tool shows them)")
	var pos: Vector3 = w.global_position
	await wait_seconds(1.0)
	assert_almost_eq(w.global_position.distance_to(pos), 0.0, 0.2, "stays down")
	await wait_seconds(WaiterLogic.DOWN_SECONDS)
	assert_false(w.down, "back up with a new tray")


func test_megaphone_picked_up_with_e() -> void:
	scene.local.teleport(MegaphoneLogic.STAND_POS + Vector3(0, 0, -1.2), 0.0)
	scene.server.set_server_position(scene.local_id, MegaphoneLogic.STAND_POS + Vector3(0, 0, -1.2))
	await wait_physics_frames(2)
	assert_ne(scene.casino_floor.prompt(), "", "prompt at the stand")
	scene._on_interact()
	await wait_seconds(0.2)
	assert_eq(scene.view.state.megaphone_holder, scene.local_id)
	assert_true(scene.server.megaphone.is_holder(scene.local_id))
	assert_eq(scene.casino_floor.prompt(), "", "nothing to pick up while held")
	await wait_seconds(MegaphoneLogic.SECONDS + 0.3)
	assert_eq(scene.view.state.megaphone_holder, -1, "back on the stand")
