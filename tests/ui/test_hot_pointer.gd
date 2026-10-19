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


## Patrick (0.9.14): "The hot arrow is a bit too big. Make it always the same size, wall see
## through is good." The arrow over the table covers the same share of the screen from anywhere
## (near or across the floor, any field of view), smaller than the old 1/5 of the screen, and
## still draws through walls.
func test_the_table_arrow_is_the_same_size_on_screen_from_anywhere() -> void:
	for fov: float in [70.0, 85.0, 110.0]:
		for d: float in [2.0, 5.0, 12.0, 30.0, 60.0]:
			var k: float = StationBase.hot_marker_scale(d, fov)
			var share: float = StationBase.HOT_ARROW_LENGTH * k / (2.0 * d * tan(deg_to_rad(fov) * 0.5))
			assert_almost_eq(share, StationBase.HOT_MARKER_SCREEN, 0.0001, "%.0f m at %.0f°" % [d, fov])
	assert_lt(StationBase.HOT_MARKER_SCREEN, 0.15, "smaller than before")
	var sid: StringName = scene.map.stations.keys()[0]
	var table: StationBase = scene.map.stations[sid]
	table.set_hot(true)
	var cam: Camera3D = scene.local.cam.camera
	for d: float in [4.0, 25.0]:
		cam.global_transform = Transform3D(Basis.IDENTITY, table.global_position + Vector3(0, StationBase.HOT_MARKER_Y, d))
		table._process(0.016)
		var want: float = StationBase.hot_marker_scale(cam.global_position.distance_to(table.global_position + Vector3(0, StationBase.HOT_MARKER_Y, 0)), cam.fov)
		assert_almost_eq(table.hot_marker.scale.x, want, 0.001, "scaled for %.0f m" % d)
		assert_almost_eq(table.hot_label.scale.x * table.hot_marker.scale.x, 1.0, 0.001, "the fixed-size label is not scaled twice")
	for mi: Node in table.hot_marker.find_children("*", "MeshInstance3D", true, false):
		assert_true(((mi as MeshInstance3D).material_override as BaseMaterial3D).no_depth_test, "through walls")
	assert_true(table.hot_label.no_depth_test)
	table.set_hot(false)
