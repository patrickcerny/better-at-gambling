extends GutTest
## Roulette Sumo on the authoritative server: the room opens on the wheel, a reported position
## past the rim takes the bean out and moves it to the gallery, a push decided from the server's
## positions nudges the target (no knockdown, no knockout, no money moves, they keep moving), and
## the casino's shove and grab are off.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(3, {"minigames": 1, "gamble_seconds": 20.0, "seed": 9, "minigame_pool": "roulette_sumo"})
	LuckyLounge.describe_rooms(fx.server.map_def)
	fx.server.map_def.lobby_spawns = LuckyLounge.LOBBY_SPAWNS.duplicate()


func after_each() -> void:
	fx.server.free()


func _to_game() -> RouletteSumoLogic:
	fx.server.start_match()
	fx.place_all(Vector3(0, 0, -4))
	var t: float = 0.0
	while fx.of_type(&"minigame_started").is_empty() and t < 200.0:
		fx.run(0.5)
		t += 0.5
	assert_eq(fx.of_type(&"minigame_started").size(), 1, "the minigame started")
	var g: RouletteSumoLogic = fx.server.minigame as RouletteSumoLogic
	assert_not_null(g, "Roulette Sumo is running")
	t = 0.0
	while fx.server.in_briefing() and t < 60.0:
		fx.run(0.5)
		t += 0.5
	# Park the ball by the turret so it bowls nobody over during the checks.
	g.ball_pos = Vector2(0, -RouletteSumoLogic.BALL_MIN_R)
	g.ball_vel = Vector2.ZERO
	g.ball_turn = 0.0
	g.seg_left = 1000.0
	fx.run(0.1)
	return g


func _deck(r: float, a: float) -> Vector3:
	return WheelRoom.center() + Vector3(sin(a) * r, WheelRoom.WHEEL_TOP, cos(a) * r)


func test_room_opens_on_the_wheel() -> void:
	var g: RouletteSumoLogic = _to_game()
	var started: Dictionary = fx.of_type(&"minigame_started")[0]
	assert_eq(StringName(started["minigame"]), &"roulette_sumo")
	assert_true(started.has("room"))
	for p: int in fx.player_ids:
		var at: Vector3 = fx.server.world.get_position(p)
		assert_true(RouletteSumoLogic.on_deck(at), "%d stands on the wheel at %s" % [p, at])
		assert_almost_eq(at.distance_to(g.spawn_for(p)), 0.0, 3.0, "near their spawn")
	assert_eq(fx.of_type(&"roulette_sumo_begin").size(), 1, "announced once the game ticks")
	assert_false(fx.of_type(&"roulette_sumo_wheel").is_empty(), "the wheel is synced")
	var snap: Dictionary = fx.server.get_snapshot()["minigame"]
	for k: String in ["angle", "omega", "ball", "clock"]:
		assert_true(snap.has(k), "late joiners get the %s" % k)


func test_past_the_rim_is_out_and_goes_to_the_gallery() -> void:
	var g: RouletteSumoLogic = _to_game()
	var a: int = fx.player_ids[0]
	var from: Vector3 = fx.server.world.get_position(a)
	var c: Vector3 = WheelRoom.center()
	var outward: Vector3 = Vector3(from.x - c.x, 0, from.z - c.z).normalized()
	var over: Vector3 = c + outward * (RouletteSumoLogic.FALL_RADIUS + 0.4) + Vector3(0, WheelRoom.WHEEL_TOP, 0)
	assert_true(fx.server.apply_move(a, over, 0.0, false), "a step over the rim is a legal move")
	fx.run(0.1)
	var elim: Array[Dictionary] = fx.of_type(&"minigame_eliminated")
	assert_eq(elim.size(), 1)
	assert_eq(elim[0]["players"], [a])
	assert_eq(StringName(elim[0]["cause"]), &"fell")
	assert_false(g.is_alive(a))
	fx.run(1.5)  # the tumble, then the gallery
	assert_true(g.gallery.has_point(fx.server.world.get_position(a)), "%d watches from the gallery" % a)
	var moved: bool = false
	for ev: Dictionary in fx.of_type(&"minigame_player_moved"):
		if int(ev["player"]) == a and g.gallery.has_point(Serializer.to_vec3(ev["pos"])):
			moved = true
	assert_true(moved, "the scene is told to move them")


func test_a_push_nudges_without_knocking_down() -> void:
	var g: RouletteSumoLogic = _to_game()
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	var bp: Vector3 = _deck(1.5, 0.0)
	fx.server.world.set_transform(b, bp, 0.0)
	fx.server.world.set_transform(a, bp + Vector3(1.2, 0, 0), PI * 0.5)  # yaw pi/2 faces -x: at b
	var money_before: Dictionary[int, int] = {}
	for p: int in fx.player_ids:
		money_before[p] = fx.server.economy.balance(p)
	var res: Dictionary = fx.intent(a, &"minigame_action", {"kind": "push", "target": b})
	assert_true(res["ok"], "push: %s" % res)
	var pushes: Array[Dictionary] = fx.of_type(&"roulette_sumo_push")
	assert_eq(pushes.size(), 1)
	assert_eq(int(pushes[0]["target"]), b)
	assert_eq(fx.intent(a, &"minigame_action", {"kind": "push", "target": b})["error"], &"cooldown")
	fx.run(0.3)
	assert_true(fx.of_type(&"player_knocked_down").is_empty(), "a push is no knockdown")
	assert_true(fx.of_type(&"player_knocked_out").is_empty(), "nor a knockout")
	assert_true(g.is_alive(b), "still on the wheel")
	assert_true(fx.server.can_move(b), "and still walking")
	assert_true(fx.server.apply_move(b, fx.server.world.get_position(b) + Vector3(-0.8, 0, 0), 0.0, false), "the slide the client reports is accepted")
	for p: int in fx.player_ids:
		assert_eq(fx.server.economy.balance(p), money_before[p], "no money moves on a push")
	assert_eq(fx.intent(a, &"minigame_action", {"kind": "swing", "target": b})["error"], &"bad_value", "no bats")


func test_shove_and_grab_are_refused() -> void:
	_to_game()
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	var bp: Vector3 = _deck(3.0, 0.0)
	fx.server.world.set_transform(b, bp, 0.0)
	fx.server.world.set_transform(a, bp + Vector3(0, 0, 1.0), 0.0)
	assert_eq(fx.intent(a, &"shove", {"aim": [0.0, 0.0, -1.0], "target": b})["error"], &"minigame", "no shoving")
	assert_eq(fx.intent(a, &"grab", {"target": b})["error"], &"minigame", "no grabbing")
