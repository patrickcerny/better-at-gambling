extends GutTest
## Patrick: "The throw around and the ragdoll not updating bug is still there". When the bean who
## holds someone goes flying (knocked out, knocked down, caught by a guard), the server ended the
## hold without telling anyone: the held bean kept dangling in front of the flying holder on every
## screen, never got its body back, and the holder could never grab again.

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


## The local bean grabs the bot. Returns the bot's avatar.
func _grab_bot() -> PlayerAvatar:
	_place(scene.local_id, OPEN)
	_place(bot, OPEN + Vector3(0.0, 0.0, -1.0))
	await wait_physics_frames(2)
	var res: Dictionary = scene.server.submit_intent(scene.local_id, Intents.make(&"grab", {"target": bot}))
	assert_true(res["ok"], "grabbed (%s)" % res)
	await wait_physics_frames(3)
	var b: PlayerAvatar = scene.avatars[bot]
	assert_eq(b.state, PlayerAvatar.State.HELD, "held")
	return b


func _assert_let_go(b: PlayerAvatar) -> void:
	assert_ne(b.state, PlayerAvatar.State.HELD, "no longer dangling in front of the holder")
	assert_null(b.holder, "nobody holds them on screen")
	assert_eq(scene._local_holding(), -1, "the holder's hands are free again")
	await wait_seconds(Registry.balance.knockout_time + 2.0)
	assert_true(b.is_standing(), "the held bean is on its feet")
	assert_false(scene.server.is_server_owned(bot), "the server stopped simulating them")
	assert_true(scene.server.can_move(bot), "their own moves count again")
	assert_true(scene.server.can_move(scene.local_id), "the holder's moves count again")


func test_holder_knocked_out_lets_go() -> void:
	var b: PlayerAvatar = await _grab_bot()
	assert_true(scene.server.report_knockout(scene.local_id, bot, &"wall"), "holder knocked out")
	await wait_seconds(0.5)
	await _assert_let_go(b)


func test_holder_caught_by_a_guard_lets_go() -> void:
	var b: PlayerAvatar = await _grab_bot()
	scene.server.report_thrown_out(scene.local_id, &"bouncer")
	await wait_seconds(0.5)
	await _assert_let_go(b)


func test_thrown_bean_caught_in_flight_then_holder_knocked_out() -> void:
	var b: PlayerAvatar = await _grab_bot()
	scene.server.submit_intent(scene.local_id, Intents.make(&"release", {"throw": true, "aim": Serializer.vec3(Vector3.FORWARD)}))
	await wait_physics_frames(4)
	assert_eq(b.state, PlayerAvatar.State.RAGDOLL, "thrown")
	_place(scene.local_id, b.global_position + Vector3(0.0, 0.0, 1.0))
	await wait_physics_frames(1)
	var res: Dictionary = scene.server.submit_intent(scene.local_id, Intents.make(&"grab", {"target": bot}))
	if res["ok"]:
		await wait_physics_frames(3)
		assert_true(scene.server.report_knockout(scene.local_id, bot, &"wall"), "holder knocked out")
		await wait_seconds(0.5)
	await _assert_let_go(b)
