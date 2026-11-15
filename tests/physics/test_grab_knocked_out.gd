extends GutTest
## Patrick: "Sometimes after I knock out a player too often, the skin gets stuck. The player (in his
## view) is walking around, but the lobby is not registering any movements". Grabbing a knocked-out
## bean switched it from RAGDOLL to HELD without removing the ragdoll, so the host's knockout timer
## (which only gets RAGDOLL bodies up) never handed the body back: the server ignored that
## player's moves from then on.

var scene: MatchScene
var bot: int = -1

const OPEN: Vector3 = Vector3(5.0, 0.0, 4.5)


func before_all() -> void:
	MatchScene.test_dummies = 1


func after_all() -> void:
	MatchScene.test_dummies = 0


func before_each() -> void:
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	for pid: int in scene.avatars:
		if pid != scene.local_id:
			bot = pid
	scene.server.timescale = 1.0
	await wait_seconds(3.3)
	for g: Guard in scene.guards:
		g.process_mode = Node.PROCESS_MODE_DISABLED
		g.global_position = Vector3(-18.0, 0.0, -12.0)
	if scene.casino_floor != null and scene.casino_floor.waiter != null:
		scene.casino_floor.waiter.process_mode = Node.PROCESS_MODE_DISABLED
		scene.casino_floor.waiter.global_position = Vector3(-18.0, 0.0, 12.0)


func _place(pid: int, pos: Vector3) -> void:
	scene.avatars[pid].teleport(pos, 0.0)
	scene.server.set_server_position(pid, pos)


func test_grabbed_knocked_out_player_gets_their_body_back() -> void:
	_place(scene.local_id, OPEN)
	_place(bot, OPEN + Vector3(0.0, 0.0, -1.2))
	await wait_physics_frames(2)
	var b: PlayerAvatar = scene.avatars[bot]
	assert_true(scene.server.report_knockout(bot, scene.local_id, &"wall"), "knocked out")
	await wait_seconds(0.6)
	assert_eq(b.state, PlayerAvatar.State.RAGDOLL, "lying as a ragdoll")
	assert_true(scene.server.is_server_owned(bot), "the host simulates the ragdoll")
	_place(scene.local_id, b.global_position + Vector3(0.0, 0.0, 1.0))
	await wait_physics_frames(1)
	var res: Dictionary = scene.server.submit_intent(scene.local_id, Intents.make(&"grab", {"target": bot}))
	assert_true(res["ok"], "grabbed the knocked-out bean (%s)" % res)
	await wait_physics_frames(3)
	assert_eq(b.state, PlayerAvatar.State.HELD, "held")
	assert_null(b.ragdoll, "no ragdoll left lying on the floor")
	scene.server.submit_intent(scene.local_id, Intents.make(&"release", {"throw": false, "aim": Serializer.vec3(Vector3.FORWARD)}))
	await wait_seconds(Registry.balance.knockout_time + 1.0)
	assert_true(b.is_standing(), "on their feet")
	assert_false(scene.server.is_server_owned(bot), "the server stopped simulating the body")
	assert_true(scene.server.can_move(bot), "their own moves count again")
