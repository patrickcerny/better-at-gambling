extends GutTest
## Jackpot Climb on the authoritative server: the room opens with everyone on the apron, a
## reported step onto the pad finishes the bean, a bat swing decided from the server's positions
## knocks a neighbour off (a real knockdown with the attacker), a fall after a checkpoint flag
## comes back on that flag (the server moves the body), and grabbing is off (shoving stays on).

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(3, {"minigames": 1, "gamble_seconds": 20.0, "seed": 9, "minigame_pool": "jackpot_climb"})
	LuckyLounge.describe_rooms(fx.server.map_def)
	fx.server.map_def.lobby_spawns = LuckyLounge.LOBBY_SPAWNS.duplicate()


func after_each() -> void:
	fx.server.free()


func _to_game() -> JackpotClimbLogic:
	fx.server.start_match()
	fx.place_all(Vector3(0, 0, -4))
	var t: float = 0.0
	while fx.of_type(&"minigame_started").is_empty() and t < 200.0:
		fx.run(0.5)
		t += 0.5
	assert_eq(fx.of_type(&"minigame_started").size(), 1, "the minigame started")
	var g: JackpotClimbLogic = fx.server.minigame as JackpotClimbLogic
	assert_not_null(g, "Jackpot Climb is running")
	t = 0.0
	while fx.server.in_briefing() and t < 60.0:
		fx.run(0.5)
		t += 0.5
	fx.run(0.1)
	return g


func _on_stack(i: int) -> Vector3:
	return WalkableLogicBase.ROOM_ORIGIN + (ChipTowers.stacks()[i]["pos"] as Vector3)


func test_room_opens_on_the_apron() -> void:
	var g: JackpotClimbLogic = _to_game()
	var started: Dictionary = fx.of_type(&"minigame_started")[0]
	assert_eq(StringName(started["minigame"]), &"jackpot_climb")
	assert_true(started.has("room"))
	for p: int in fx.player_ids:
		var at: Vector3 = fx.server.world.get_position(p)
		assert_lt(ClimbRoom.progress(at, "towers"), 0.01, "%d starts at the bottom at %s" % [p, at])
		assert_gt(at.z, WalkableLogicBase.ROOM_ORIGIN.z, "on the apron")
		assert_almost_eq(at.distance_to(g.spawn_for(p)), 0.0, 1.0, "on their spawn")
	assert_eq(fx.of_type(&"jackpot_climb_begin").size(), 1, "announced once the game ticks")
	var snap: Dictionary = fx.server.get_snapshot()["minigame"]
	for k: String in ["clock", "finish", "heights", "down"]:
		assert_true(snap.has(k), "late joiners get the %s" % k)


func test_a_reported_step_onto_the_pad_finishes() -> void:
	var g: JackpotClimbLogic = _to_game()
	var a: int = fx.player_ids[0]
	var last: Vector3 = _on_stack(ChipTowers.stacks().size() - 1)
	fx.server.world.set_transform(a, last, 0.0)
	fx.run(0.2)
	assert_false(g.is_up(a), "the last stack is not the top")
	var pad: Vector3 = WalkableLogicBase.ROOM_ORIGIN + ChipTowers.pad_center() + ChipTowers.entry_dir() * 1.2
	assert_true(fx.server.apply_move(a, pad, 0.0, false), "a jump onto the pad is a legal move")
	fx.run(0.1)
	var tops: Array[Dictionary] = fx.of_type(&"jackpot_climb_top")
	assert_eq(tops.size(), 1)
	assert_eq(tops[0]["players"], [a])
	assert_true(g.is_up(a))
	assert_eq(fx.server.get_snapshot()["minigame"]["finish"], [[a]])


func test_a_swing_knocks_a_neighbour_down() -> void:
	var g: JackpotClimbLogic = _to_game()
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	var at: Vector3 = _on_stack(6)
	fx.server.world.set_transform(b, at, 0.0)
	# The client claims a hit from the floor: the server's positions say miss.
	var res: Dictionary = fx.intent(a, &"minigame_action", {"kind": "swing", "target": b})
	assert_true(res["ok"])
	assert_eq(res["result"], &"miss")
	fx.run(JackpotClimbLogic.SWING_COOLDOWN + 0.1)
	fx.server.world.set_transform(a, at + Vector3(0, 0, 1.0), 0.0)  # yaw 0 faces -z: towards b
	res = fx.intent(a, &"minigame_action", {"kind": "swing"})
	assert_eq(res["result"], &"hit", "swing: %s" % res)
	fx.run(0.1)
	var down: Array[Dictionary] = fx.of_type(&"player_knocked_down")
	assert_eq(down.size(), 1)
	assert_eq(int(down[0]["target"]), b)
	assert_eq(int(down[0]["attacker"]), a)
	assert_eq(down[0]["cause"], &"bat")
	assert_true(fx.server.rules.is_knocked_down(b, fx.server.match_time), "down on the server")
	assert_true(g.is_down(b))
	fx.run(JackpotClimbLogic.KNOCK_SECONDS)
	fx.server.report_got_up(b, fx.server.world.get_position(b))
	assert_false(g.is_down(b))
	assert_true(g.is_immune(b), "the short grace after getting up")


func test_a_fall_after_flag_two_comes_back_on_flag_two() -> void:
	var g: JackpotClimbLogic = _to_game()
	var a: int = fx.player_ids[0]
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	fx.server.world.set_transform(a, o + (ChipTowers.checkpoints()[0]["spots"] as Array)[0], 0.0)
	fx.run(0.2)
	fx.server.world.set_transform(a, o + (ChipTowers.checkpoints()[1]["spots"] as Array)[0], 0.0)
	fx.run(0.2)
	assert_eq(g.checkpoint.get(a, 0), 2, "flag 2 reached")
	assert_eq(fx.of_type(&"jackpot_climb_checkpoint").size(), 2)
	# Off the edge, all the way down to the net.
	fx.server.world.set_transform(a, o + Vector3(-10.5, 0.0, ChipTowers.CENTER_Z), 0.0)
	fx.run(0.2)
	assert_eq(fx.of_type(&"jackpot_climb_respawn").size(), 1)
	var moved: Array[Dictionary] = fx.of_type(&"minigame_player_moved").filter(func(e: Dictionary) -> bool: return int(e["player"]) == a)
	assert_eq(moved.size(), 1, "the scene is told to put the body back")
	var at: Vector3 = fx.server.world.get_position(a)
	assert_eq(ChipTowers.checkpoint_at(at - o), 2, "on tier 2, not the floor: %s" % at)
	assert_almost_eq(at.distance_to(g.respawn_spot(a, 2)), 0.0, 0.01)
	assert_gte(float(fx.server.get_snapshot()["minigame"]["checkpoints"][a]), 2.0)


func test_grab_refused_shove_allowed() -> void:
	_to_game()
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	var bp: Vector3 = _on_stack(2)
	fx.server.world.set_transform(b, bp, 0.0)
	fx.server.world.set_transform(a, bp + Vector3(0, 0, 1.0), 0.0)
	assert_eq(fx.intent(a, &"grab", {"target": b})["error"], &"minigame", "no grabbing")
	assert_ne(fx.intent(a, &"shove", {"aim": [0.0, 0.0, -1.0], "target": b}).get("error", &""), &"minigame", "shoving is on")
