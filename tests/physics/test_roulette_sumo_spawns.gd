extends GutTest
## Roulette Sumo starts in the real match scene (Patrick 2026-11-16: "on roulette sumo you still
## spawn at the edge sometimes"): from the moment the room opens, through the rules card and the
## start grace, every bean stands well inside the wheel, for 2 to 8 players.

var scene: MatchScene


func after_each() -> void:
	MatchScene.test_dummies = 0
	MatchScene.test_briefing = -1.0
	MatchScene.test_curtain_fast = false


func _open(dummies: int, briefing: float) -> void:
	Net.stop()
	MatchScene.test_dummies = dummies
	MatchScene.test_briefing = briefing
	MatchScene.test_curtain_fast = true
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_seconds(3.3)


func _skip_until(cond: Callable, max_seconds: float = 900.0) -> bool:
	var t: float = 0.0
	while not cond.call() and t < max_seconds:
		scene.server.advance(MatchServer.TICK)
		t += MatchServer.TICK
	return cond.call()


func _run_start(dummies: int, briefing: float, shove_out: bool = false) -> void:
	await _open(dummies, briefing)
	assert_true(scene.server.dev_minigame_now(&"roulette_sumo"))
	assert_true(_skip_until(func() -> bool: return scene.server.phases.phase == Phase.Id.MINIGAME))
	var g: RouletteSumoLogic = scene.server.minigame as RouletteSumoLogic
	assert_not_null(g)
	var me: int = scene.local_id
	var worst: float = 0.0
	var t: float = 0.0
	var shoved: bool = false
	# Through the rules card and the start grace (the wheel stands still until the spin).
	while (scene.server.in_briefing() or g.grace_left > 0.1) and t < briefing + 10.0:
		await wait_physics_frames(3)
		t += get_physics_process_delta_time() * 3.0
		if shove_out and not shoved and not scene.server.in_briefing():
			# Knocked to the rim just as the game starts (a casino shove landing late, a glitch).
			shoved = true
			var c: Vector3 = WheelRoom.center()
			var edge: Vector3 = c + Vector3(6.4, WheelRoom.WHEEL_TOP, 0.0)
			scene.local.teleport(edge, 0.0)
			scene.server.set_server_position(me, edge)
			await wait_physics_frames(12)
			t += get_physics_process_delta_time() * 12.0
		for pid: int in scene.avatars:
			var a: PlayerAvatar = scene.avatars[pid]
			worst = maxf(worst, RouletteSumoLogic.flat_radius(a.global_position))
	gut.p("%d players: worst radius %.2f" % [dummies + 1, worst])
	if not shove_out:
		assert_lt(worst, WheelRoom.SPAWN_RADIUS + 0.5, "nobody starts near the edge (%d players)" % (dummies + 1))
	for p: int in g.players:
		assert_true(g.is_alive(p), "%d is still in at the spin" % p)
		var at: Vector3 = (scene.avatars[p] as PlayerAvatar).global_position
		var home: Vector3 = g.spawn_for(p)
		assert_lt(Vector2(at.x - home.x, at.z - home.z).length(), RouletteSumoLogic.START_LEASH + 0.3, "%d is on their spot when the wheel starts" % p)
	assert_lt(RouletteSumoLogic.flat_radius(scene.local.global_position), WheelRoom.SPAWN_RADIUS + 1.0, "our bean is back inside")


func test_two_players() -> void:
	await _run_start(1, 1.0)


func test_five_players() -> void:
	await _run_start(4, 1.0)


func test_eight_players() -> void:
	await _run_start(7, 1.0)


func test_knocked_to_the_rim_at_the_start_goes_back_to_the_spot() -> void:
	await _run_start(3, 1.0, true)
