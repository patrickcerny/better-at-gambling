extends GutTest
## The start room and the jail cell as bodies feel them (0.8.19): the shut lobby doors are solid
## across the whole doorway (a thrown ragdoll bounces off), anyone who still ends up in the casino
## while the room waits in LOBBY is sent back to the start room, and the barred cell's gate and bars
## keep a prisoner in.

var scene: MatchScene


func before_each() -> void:
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_seconds(3.3)


## The practice match turned into an online room waiting in the lobby, doors shut.
func _wait_in_lobby() -> void:
	scene.server.room_mode = true
	scene.server.running = false
	scene.server.phases.phase = Phase.Id.LOBBY
	scene.map.set_lobby_open(false)
	await wait_physics_frames(2)


func _put(pos: Vector3, yaw: float) -> void:
	scene.local.teleport(pos, yaw)
	scene.server.set_server_position(scene.local_id, pos)


func test_the_shut_doors_fill_the_doorway() -> void:
	await _wait_in_lobby()
	var barrier: CollisionShape3D = scene.map.lobby_doors.get_child(0) as CollisionShape3D
	assert_false(barrier.disabled, "solid while shut")
	var box: BoxShape3D = barrier.shape as BoxShape3D
	assert_gte(box.size.x, LuckyLounge.LOBBY_DOOR_HALF * 2.0, "the full doorway width")
	assert_gte(box.size.y, LuckyLounge.LOBBY_DOOR_H, "the full doorway height")
	assert_eq(scene.map.lobby_doors.collision_layer & 1, 1, "on the world layer: players and ragdolls hit it")
	scene.map.set_lobby_open(true)
	await wait_physics_frames(2)
	assert_true(barrier.disabled, "open for the match")


func test_a_ragdoll_thrown_at_the_shut_doors_stays_in_the_start_room() -> void:
	await _wait_in_lobby()
	var door_z: float = scene.server.map_def.lobby_door_z
	for x: float in [-2.2, 0.0, 1.6]:
		_put(Vector3(x, 0, 11.0), 0.0)
		await wait_physics_frames(2)
		var rd: RagdollBody = scene.local.start_ragdoll(Vector3(0, 3.0, -16.0))
		var furthest: float = INF
		for i: int in 60:
			await wait_physics_frames(1)
			if is_instance_valid(rd):
				furthest = minf(furthest, rd.body_position().z)
		assert_gt(furthest, door_z - 0.3, "x=%.1f: bounced off the doors (got to z=%.2f)" % [x, furthest])
		assert_false(scene.server.map_def.past_lobby_doors(scene.local.global_position), "still in the start room")
		if scene.local.state == PlayerAvatar.State.RAGDOLL:
			scene.local.end_ragdoll(Vector3(x, 0, 11.0))
		await wait_physics_frames(2)


func test_a_ragdoll_past_the_door_line_is_sent_back() -> void:
	await _wait_in_lobby()
	var door_z: float = scene.server.map_def.lobby_door_z
	# A glitch got them through: tumbling on the casino floor while the doors are shut.
	_put(Vector3(0.5, 0, 5.0), 0.0)
	scene.local.start_ragdoll(Vector3(0, 2.0, -3.0))
	assert_eq(scene.local.state, PlayerAvatar.State.RAGDOLL, "tumbling in the casino")
	await wait_seconds(0.6)
	assert_ne(scene.local.state, PlayerAvatar.State.RAGDOLL, "the ragdoll is over")
	var at: Vector3 = scene.local.global_position
	assert_gt(at.z, door_z, "back in the start room (z=%.2f)" % at.z)
	assert_almost_eq(Vector2(at.x, at.z).distance_to(Vector2(scene.map.lobby_spawn(scene.local_id).x, scene.map.lobby_spawn(scene.local_id).z)), 0.0, 0.6, "on their spot")
	assert_false(scene.server.map_def.past_lobby_doors(scene.server.world.get_position(scene.local_id)), "the server agrees")
	# Standing, they stay put: walking at the doors gets nowhere.
	scene.local.auto_target = Vector3(0, 0, 2.0)
	await wait_seconds(2.5)
	scene.local.auto_target = Vector3.INF
	assert_gt(scene.local.global_position.z, door_z, "the doors hold a walker too")


func test_the_jail_gate_and_bars_keep_a_prisoner_in() -> void:
	var cell: AABB = LuckyLounge.JAIL_AREA
	for target: Vector3 in [Vector3(-14.0, 0, LuckyLounge.JAIL_GATE_Z), Vector3(-20.0, 0, 1.0), Vector3(-14.0, 0, 9.5)]:
		_put(LuckyLounge.JAIL_SPOTS[2], -PI * 0.5)
		await wait_physics_frames(3)
		assert_true(_inside(cell, scene.local.global_position), "starts in the cell")
		scene.local.auto_target = target
		await wait_seconds(2.5)
		scene.local.auto_target = Vector3.INF
		var at: Vector3 = scene.local.global_position
		assert_true(_inside(cell, at), "walking towards %s: still in the cell at %s" % [target, at])


func _inside(cell: AABB, p: Vector3) -> bool:
	return p.x > cell.position.x and p.x < cell.end.x and p.z > cell.position.z and p.z < cell.end.z
