extends GutTest
## The ready pedestals (0.8.15): one marble column stump per player colour along the south wall
## of the entrance hall, a wall sign with the player's name, a lit top while they are ready, and
## low enough steps that a player simply walks up onto it (standing up there is what readies you).

var scene: MatchScene


func before_each() -> void:
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_seconds(3.3)


func test_one_pedestal_per_colour_with_signs_on_the_wall() -> void:
	var pads: Array[Node] = get_tree().get_nodes_in_group(&"ready_pads")
	assert_eq(pads.size(), LuckyLounge.PEDESTALS.size(), "eight pedestals")
	assert_eq(scene.map.pedestal_labels.size(), 8)
	for i: int in 8:
		assert_eq(scene.map.ready_pad(i), LuckyLounge.PEDESTALS[i])
		assert_gt(LuckyLounge.PEDESTALS[i].z, 14.5, "along the south wall")
		assert_gt(absf(LuckyLounge.PEDESTALS[i].x), 2.5, "clear of the revolving door gap (x −2..2)")
		var sign: Label3D = scene.map.pedestal_labels[i]
		assert_almost_eq(sign.global_position.x, LuckyLounge.PEDESTALS[i].x, 0.01, "the sign hangs above its pedestal")
		assert_gt(sign.global_position.z, LuckyLounge.PEDESTALS[i].z, "on the wall behind it")
	scene.map.set_pedestal(2, "Patrick", true)
	assert_eq(scene.map.pedestal_labels[2].text, "PATRICK")
	assert_true((scene.map.pedestal_tops[2].material_override as StandardMaterial3D).emission_enabled, "lit while ready")
	scene.map.set_pedestal(2, "Patrick", false)
	assert_false((scene.map.pedestal_tops[2].material_override as StandardMaterial3D).emission_enabled)
	scene.map.set_pedestal(2, "", false)
	assert_eq(scene.map.pedestal_labels[2].text, "", "nobody in that colour: blank sign")


func test_names_and_ready_state_follow_the_shared_state() -> void:
	var me: int = scene.local_id
	var colour: int = int(scene.view.state.players[me]["color"])
	await wait_seconds(0.4)
	assert_eq(scene.map.pedestal_labels[colour].text, str(scene.view.state.players[me]["name"]).to_upper())
	scene.view.state.players[me]["ready"] = true
	await wait_seconds(0.4)
	assert_true((scene.map.pedestal_tops[colour].material_override as StandardMaterial3D).emission_enabled)


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
