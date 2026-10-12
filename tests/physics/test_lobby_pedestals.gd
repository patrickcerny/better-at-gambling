extends GutTest
## The ready pedestals (0.8.15): one marble column stump per player colour along the south wall
## of the entrance hall, a brass name plate behind it with the player's name (FREE when nobody has
## the colour), a warm glow from above while they are ready (0.9.4: the marble itself never
## changes), and low enough steps that a player simply walks up onto it (standing up there is
## what readies you).

var scene: MatchScene


func before_each() -> void:
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_seconds(3.3)


func test_one_pedestal_per_colour_with_name_plates_behind() -> void:
	var pads: Array[Node] = get_tree().get_nodes_in_group(&"ready_pads")
	assert_eq(pads.size(), LuckyLounge.PEDESTALS.size(), "eight pedestals")
	assert_eq(scene.map.pedestal_labels.size(), 8)
	assert_eq(scene.map.pedestal_lights.size(), 8, "one light per pedestal")
	for i: int in 8:
		assert_eq(scene.map.ready_pad(i), LuckyLounge.PEDESTALS[i])
		assert_gt(LuckyLounge.PEDESTALS[i].z, 14.5, "along the south wall")
		assert_gt(absf(LuckyLounge.PEDESTALS[i].x), 2.5, "clear of the revolving door gap (x −2..2)")
		var sign: Label3D = scene.map.pedestal_labels[i]
		assert_almost_eq(sign.global_position.x, LuckyLounge.PEDESTALS[i].x, 0.01, "the plate stands behind its pedestal")
		assert_gt(sign.global_position.z, LuckyLounge.PEDESTALS[i].z + 0.45, "behind the column, on the wall side")
		assert_lt(sign.global_position.z, LuckyLounge.SIZE_Z * 0.5 - 0.25, "in front of the wall")
		# Above the name tag of whoever stands on the pedestal (feet at the top + 2.15 m).
		assert_gt(sign.global_position.y - 0.2, LuckyLounge.PEDESTAL_TOP + 2.15 + 0.15, "clear of the name tag over a bean up there")
	var mine: int = int(scene.view.state.players[scene.local_id]["color"])
	for i: int in 8:
		if i != mine:
			assert_eq(scene.map.pedestal_labels[i].text, LuckyLounge.PEDESTAL_FREE, "nobody in colour %d: FREE" % i)


func test_the_plate_follows_the_owner_and_the_glow_follows_ready() -> void:
	# A map of its own: the match scene refreshes its pedestals from the shared state every frame.
	var map: LuckyLounge = (load("res://maps/lucky_lounge/lucky_lounge.tscn") as PackedScene).instantiate()
	map.bake_navmesh = false
	map.position = Vector3(0, -50, 0)
	add_child_autofree(map)
	await wait_physics_frames(2)
	var marble: Material = map.pedestal_tops[2].material_override
	map.set_pedestal(2, "Patrick", false)
	assert_eq(map.pedestal_labels[2].text, "PATRICK", "the owner's name on the plate")
	await wait_seconds(0.5)
	assert_false(map.pedestal_lights[2].visible, "owned but not ready: no glow")
	map.set_pedestal(2, "Patrick", true)
	await wait_seconds(0.1)
	assert_true(map.pedestal_lights[2].visible, "fading in")
	assert_lt(map.pedestal_lights[2].light_energy, LuckyLounge.PEDESTAL_LIGHT_ENERGY, "not at full yet")
	await wait_seconds(0.4)
	assert_almost_eq(map.pedestal_lights[2].light_energy, LuckyLounge.PEDESTAL_LIGHT_ENERGY, 0.01, "full glow once ready")
	assert_true(map.pedestal_glows[2].visible, "light cone and pool shown")
	assert_eq(map.pedestal_tops[2].material_override, marble, "the marble itself never changes")
	var spot: SpotLight3D = map.pedestal_lights[2]
	assert_gt(spot.global_position.y - map.global_position.y, LuckyLounge.WALL_H - 0.5, "from the ceiling")
	assert_almost_eq((-spot.global_basis.z).normalized().dot(Vector3.DOWN), 1.0, 0.01, "straight down")
	assert_false(spot.shadow_enabled, "no shadows")
	for i: int in 8:
		if i != 2:
			assert_false(map.pedestal_lights[i].visible, "only the ready pedestal glows (%d)" % i)
			assert_eq(map.pedestal_labels[i].text, LuckyLounge.PEDESTAL_FREE)
	map.set_pedestal(2, "Patrick", false)
	await wait_seconds(0.5)
	assert_false(map.pedestal_lights[2].visible, "faded out when not ready")
	assert_false(map.pedestal_glows[2].visible)
	map.set_pedestal(2, "", false)
	assert_eq(map.pedestal_labels[2].text, LuckyLounge.PEDESTAL_FREE, "nobody in that colour: FREE again")


func test_names_and_ready_state_follow_the_shared_state() -> void:
	var me: int = scene.local_id
	var colour: int = int(scene.view.state.players[me]["color"])
	await wait_seconds(0.4)
	assert_eq(scene.map.pedestal_labels[colour].text, str(scene.view.state.players[me]["name"]).to_upper())
	assert_false(scene.map.pedestal_lights[colour].visible, "not ready yet: no glow")
	scene.view.state.players[me]["ready"] = true
	await wait_seconds(0.6)
	assert_true(scene.map.pedestal_lights[colour].visible, "ready: the light from above is on")


func test_an_arrow_marks_my_pedestal_until_i_am_ready() -> void:
	var me: int = scene.local_id
	var colour: int = int(scene.view.state.players[me]["color"])
	await wait_seconds(0.4)
	var marker: Node3D = scene.map.pedestal_marker
	assert_not_null(marker, "marker built for the local player")
	assert_true(marker.visible, "shown while not ready")
	var pad: Vector3 = scene.map.ready_pad(colour)
	assert_almost_eq(marker.position.x, pad.x, 0.01, "over my pedestal")
	assert_almost_eq(marker.position.z, pad.z, 0.01)
	assert_gt(marker.position.y, LuckyLounge.PEDESTAL_TOP + 0.8, "floats above the column")
	var head: MeshInstance3D = marker.get_node("Head") as MeshInstance3D
	assert_eq((head.material_override as StandardMaterial3D).albedo_color, Palette.player_color(colour), "in my colour")
	scene.view.state.players[me]["ready"] = true
	await wait_seconds(0.4)
	assert_false(marker.visible, "hidden once ready")
	scene.view.state.players[me]["ready"] = false
	await wait_seconds(0.4)
	assert_true(marker.visible, "back when not ready")


func test_a_player_walks_up_onto_the_pedestal() -> void:
	var pad: Vector3 = LuckyLounge.PEDESTALS[0]
	var start: Vector3 = pad + Vector3(0, 0, -3.4)
	scene.local.teleport(start, PI)  # facing +z, towards the wall
	scene.server.set_server_position(scene.local_id, start)
	await wait_seconds(0.2)
	scene.local.auto_target = pad
	await wait_seconds(3.5)
	var at: Vector3 = scene.local.global_position
	var flat: float = Vector2(at.x - pad.x, at.z - pad.z).length()
	assert_lt(flat, LuckyLounge.PAD_RADIUS, "reached the pedestal (%.2f m off)" % flat)
	assert_gt(at.y, LuckyLounge.PEDESTAL_TOP - 0.1, "up on the abacus, y=%.2f" % at.y)
	assert_true(scene.local.is_standing())
