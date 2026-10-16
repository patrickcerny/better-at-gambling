extends GutTest
## Dodge the Dice on the authoritative server: the room opens with everyone at the bottom of the
## board, a reported step onto the landing finishes the bean, a hazard hit decided from the
## server's positions knocks the bean down and the server moves it downhill once it is up, and
## grabbing is off (shoving stays on).

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(3, {"minigames": 1, "gamble_seconds": 20.0, "seed": 9, "minigame_pool": "dodge_the_dice"})
	LuckyLounge.describe_rooms(fx.server.map_def)
	fx.server.map_def.lobby_spawns = LuckyLounge.LOBBY_SPAWNS.duplicate()


func after_each() -> void:
	fx.server.free()


func _to_game() -> DodgeTheDiceLogic:
	fx.server.start_match()
	fx.place_all(Vector3(0, 0, -4))
	var t: float = 0.0
	while fx.of_type(&"minigame_started").is_empty() and t < 200.0:
		fx.run(0.5)
		t += 0.5
	assert_eq(fx.of_type(&"minigame_started").size(), 1, "the minigame started")
	var g: DodgeTheDiceLogic = fx.server.minigame as DodgeTheDiceLogic
	assert_not_null(g, "Dodge the Dice is running")
	t = 0.0
	while fx.server.in_briefing() and t < 60.0:
		fx.run(0.5)
		t += 0.5
	# No random hazards during the checks.
	g.next_spawn = INF
	g.next_rack = INF
	g.hazards.clear()
	fx.run(0.1)
	return g


func _on_row(row: int, x: float = 0.0, frac: float = 0.5) -> Vector3:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var z: float = o.z - (float(row) + frac) * ClimbRoom.ROW_D
	return Vector3(o.x + x, ClimbRoom.surface_y(z), z)


func test_room_opens_at_the_bottom() -> void:
	var g: DodgeTheDiceLogic = _to_game()
	var started: Dictionary = fx.of_type(&"minigame_started")[0]
	assert_eq(StringName(started["minigame"]), &"dodge_the_dice")
	assert_true(started.has("room"))
	for p: int in fx.player_ids:
		var at: Vector3 = fx.server.world.get_position(p)
		assert_lt(ClimbRoom.progress(at), 0.01, "%d starts at the bottom at %s" % [p, at])
		assert_almost_eq(at.distance_to(g.spawn_for(p)), 0.0, 1.0, "on their spawn")
	assert_eq(fx.of_type(&"dodge_the_dice_begin").size(), 1, "announced once the game ticks")
	var snap: Dictionary = fx.server.get_snapshot()["minigame"]
	for k: String in ["clock", "hazards", "finish", "heights"]:
		assert_true(snap.has(k), "late joiners get the %s" % k)


func test_a_reported_step_onto_the_landing_finishes() -> void:
	var g: DodgeTheDiceLogic = _to_game()
	var a: int = fx.player_ids[0]
	var edge: Vector3 = _on_row(ClimbRoom.ROWS - 1, 0.0, 0.85)
	fx.server.world.set_transform(a, edge, 0.0)
	fx.run(0.2)
	assert_false(g.is_up(a), "the top row is not the top")
	var landing := Vector3(edge.x, ClimbRoom.top_y(), ClimbRoom.top_z() - 0.6)
	assert_true(fx.server.apply_move(a, landing, 0.0, false), "a step onto the landing is a legal move")
	fx.run(0.1)
	var tops: Array[Dictionary] = fx.of_type(&"dodge_the_dice_top")
	assert_eq(tops.size(), 1)
	assert_eq(tops[0]["players"], [a])
	assert_true(g.is_up(a))


func test_a_hit_knocks_down_and_moves_the_bean_downhill() -> void:
	var g: DodgeTheDiceLogic = _to_game()
	var a: int = fx.player_ids[1]
	var at: Vector3 = _on_row(6, 1.0)
	fx.server.world.set_transform(a, at, 0.0)
	var speed: float = 8.0
	var s: float = at.z - DodgeTheDiceLogic.start_z()
	g.hazards.append({"id": 77, "kind": "ball", "lane": 1.0, "speed": speed, "t0": g.clock + 0.05 - DodgeTheDiceLogic.DROP_TIME - s / speed, "seed": 3})
	fx.run(0.1)
	var downs: Array[Dictionary] = fx.of_type(&"player_knocked_down")
	assert_eq(downs.size(), 1, "knocked down")
	assert_eq(int(downs[0]["target"]), a)
	assert_eq(StringName(downs[0]["cause"]), &"ball")
	assert_eq(fx.of_type(&"dodge_the_dice_hit").size(), 1)
	fx.run(1.8)  # the knockdown ends, then the slide-back move
	var moved: Array[Dictionary] = fx.of_type(&"minigame_player_moved").filter(func(e: Dictionary) -> bool: return int(e["player"]) == a)
	assert_eq(moved.size(), 1, "moved once")
	var to: Vector3 = Serializer.to_vec3(moved[0]["pos"])
	assert_between(to.z - at.z, DodgeTheDiceLogic.SLIDE_MIN - 0.01, DodgeTheDiceLogic.SLIDE_MAX + 0.01, "downhill")
	assert_lt(ClimbRoom.progress(fx.server.world.get_position(a)), ClimbRoom.progress(at), "lower on the board")


func test_grab_refused_shove_allowed() -> void:
	_to_game()
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	var bp: Vector3 = _on_row(2)
	fx.server.world.set_transform(b, bp, 0.0)
	fx.server.world.set_transform(a, bp + Vector3(0, 0, 1.0), 0.0)
	assert_eq(fx.intent(a, &"grab", {"target": b})["error"], &"minigame", "no grabbing")
	assert_ne(fx.intent(a, &"shove", {"aim": [0.0, 0.0, -1.0], "target": b}).get("error", &""), &"minigame", "shoving is on")
