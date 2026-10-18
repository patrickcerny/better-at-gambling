extends GutTest
## The HUD's arrow to the hot table, in the real match scene. A floor switch (or a teleport) can
## put the hot table exactly on the camera's plane for a frame; projecting that point divides by
## zero and threw engine errors ("p.d == 0") in a physics run. The arrow must point sideways then.

var scene: MatchScene


func before_each() -> void:
	Net.stop()
	MatchScene.test_dummies = 1
	MatchScene.test_curtain_fast = true
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_process_frames(3)


func after_each() -> void:
	MatchScene.test_dummies = 0
	MatchScene.test_curtain_fast = false


func test_a_hot_table_on_the_camera_plane_gets_a_sideways_arrow_and_no_error() -> void:
	var sid: StringName = scene.map.stations.keys()[0]
	var table: StationBase = scene.map.stations[sid]
	scene.view.state.hot_station = sid
	var cam: Camera3D = scene.local.cam.camera
	# Stand the camera level with the arrow's target, the table straight to its right.
	var target: Vector3 = table.global_position + Vector3(0, 2.0, 0)
	cam.global_transform = Transform3D(Basis.IDENTITY, target + Vector3(-3.0, 0.0, 0.0))  # looks down -Z
	scene._point_at_hot_table()
	assert_not_null(scene.hud.hot_pointer, "the arrow is up")
	assert_true(scene.hud.hot_pointer.visible)
	var size: Vector2 = scene.get_viewport().get_visible_rect().size
	assert_gt(scene.hud.hot_pointer.position.x, size.x * 0.5, "pointing right, where the table is: %s" % scene.hud.hot_pointer.position)
	assert_almost_eq(scene.hud.hot_pointer.rotation, 0.0, 0.05, "arrow flat, to the right")
	# And an ordinary view of it from the floor: on screen, no arrow.
	cam.global_transform = Transform3D(Basis.IDENTITY, target + Vector3(0.0, 0.0, 6.0))
	scene._point_at_hot_table()
	assert_false(scene.hud.hot_pointer.visible, "in view: no arrow")
