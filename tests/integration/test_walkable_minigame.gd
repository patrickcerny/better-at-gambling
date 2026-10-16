extends GutTest
## Walkable minigame rooms ("W") on the authoritative server, through Pass the Bomb: everyone is
## put on their spawn in the room when it starts, reported positions are held inside the arena
## (and the gallery once out), casino intents are refused with `minigame`, the action button is
## routed to the game, and after the rewards the regroup brings everyone back to the hall.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(3, {"minigames": 1, "gamble_seconds": 20.0, "seed": 9, "minigame_pool": "pass_the_bomb"})
	LuckyLounge.describe_rooms(fx.server.map_def)
	fx.server.map_def.lobby_spawns = LuckyLounge.LOBBY_SPAWNS.duplicate()


func after_each() -> void:
	fx.server.free()


## Starts the match and runs until the walkable game has started.
func _to_minigame() -> PassTheBombLogic:
	fx.server.start_match()
	fx.place_all(Vector3(0, 0, -4))
	var t: float = 0.0
	while fx.of_type(&"minigame_started").is_empty() and t < 200.0:
		fx.run(0.5)
		t += 0.5
	assert_eq(fx.of_type(&"minigame_started").size(), 1, "the minigame started")
	return fx.server.minigame as PassTheBombLogic


func test_everyone_is_teleported_to_their_spawn_in_the_room() -> void:
	var g: PassTheBombLogic = _to_minigame()
	assert_not_null(g, "Pass the Bomb is running")
	var ev: Dictionary = fx.of_type(&"minigame_started")[0]
	assert_true(ev.has("room"), "the start event carries the room")
	var spawns: Dictionary = ev["room"]["spawns"]
	assert_eq(spawns.size(), 3)
	for p: int in fx.player_ids:
		var spot: Vector3 = Serializer.to_vec3(spawns[p])
		assert_almost_eq(spot.distance_to(g.spawn_for(p)), 0.0, 0.002, "the event names the spawn")
		assert_true(g.arena.has_point(spot), "spawn inside the arena")
		assert_almost_eq(fx.server.world.get_position(p).distance_to(spot), 0.0, 0.01, "server body on the spawn")
		assert_gt(spot.distance_to(Vector3.ZERO), 100.0, "far from the casino")
	assert_true(fx.server.get_snapshot()["minigame"].has("room"), "late joiners get the room too")


## Online moves run through the move sanity check, whose map volume is the casino. The room is
## 200 m away: before 0.9.3 every step there was "off the map" and the client snapped back to its
## spawn (Patrick: "can't move in Pass the Bomb").
func test_walking_inside_the_room_is_a_normal_move_online() -> void:
	var g: PassTheBombLogic = _to_minigame()
	var p: int = fx.player_ids[0]
	var step: Vector3 = g.spawn_for(p) + Vector3(0.3, 0.0, 0.2)
	assert_true(g.arena.has_point(step), "a step inside the arena")
	assert_true(fx.server.sanity.in_bounds(step), "the room is on the map while it is open")
	assert_true(fx.server.apply_move(p, step, 0.0, false), "the step is accepted")
	assert_eq(fx.server.world.get_position(p), step)


func test_positions_are_clamped_to_the_arena() -> void:
	var g: PassTheBombLogic = _to_minigame()
	var p: int = fx.player_ids[0]
	# A step past the wall is held at the bound (and the client is snapped).
	var near: Vector3 = Vector3(g.arena.end.x - 0.1, 0.0, g.arena.get_center().z)
	fx.server.set_server_position(p, near)
	assert_false(fx.server.apply_move(p, near + Vector3(0.4, 0, 0), 0.0, false), "walking out is refused")
	assert_true(g.arena.has_point(fx.server.world.get_position(p)), "still in the arena")
	# Move intents too: the casino floor is a teleport back to the spawn.
	fx.intent(p, &"move", {"pos": Serializer.vec3(Vector3(0, 0, -4)), "yaw": 0.0})
	assert_eq(fx.server.world.get_position(p), g.spawn_for(p))
	# A body the server set itself (a ragdoll that got up outside) is put back every tick.
	fx.server.world.set_transform(p, Vector3(3, 0, 3), 0.0)
	fx.events.clear()
	fx.run(0.1)
	assert_eq(fx.server.world.get_position(p), g.spawn_for(p))
	var moved: Array[Dictionary] = fx.of_type(&"minigame_player_moved")
	assert_eq(moved.size(), 1, "the scene is told to move the body")
	assert_eq(int(moved[0]["player"]), p)


func test_casino_intents_are_refused_during_the_game() -> void:
	_to_minigame()
	var p: int = fx.player_ids[0]
	var blocked: Dictionary = {
		&"sit": {"station": &"blackjack_1"},
		&"use_item": {"slot": 0},
		&"shop_buy": {"index": 0},
		&"megaphone": {},
	}
	for type: StringName in blocked:
		var res: Dictionary = fx.intent(p, type, blocked[type])
		assert_false(res["ok"], "%s refused" % type)
		assert_eq(res["error"], &"minigame", "%s refused because of the minigame" % type)
	assert_true(fx.intent(p, &"emote", {"id": Emotes.ANIMATED[0] if not Emotes.ANIMATED.is_empty() else &"wave"}).has("ok"))


func test_the_action_button_reaches_the_game_and_the_server_decides() -> void:
	var g: PassTheBombLogic = _to_minigame()
	fx.run(PassTheBombLogic.FIRST_BOMB_DELAY + 0.2)
	var h: int = g.holder
	assert_true(h in fx.player_ids, "a bomb is lit")
	var other: int = fx.player_ids[0] if fx.player_ids[0] != h else fx.player_ids[1]
	var res: Dictionary = fx.intent(other, &"minigame_action", {"kind": "tag", "target": h})
	assert_eq(res["error"], &"not_holder")
	# The holder's client claims a target across the room: the server's positions say no.
	res = fx.intent(h, &"minigame_action", {"kind": "tag", "target": other})
	assert_eq(res["error"], &"no_target")
	# Face to face in reach: passed.
	var at: Vector3 = fx.server.world.get_position(other)
	fx.server.world.set_transform(h, at + Vector3(0, 0, 1.0), 0.0)  # yaw 0 faces -z: towards `other`
	res = fx.intent(h, &"minigame_action", {"kind": "tag"})
	assert_true(res["ok"], "tag: %s" % res)
	assert_eq(g.holder, other)
	assert_eq(fx.of_type(&"pass_the_bomb_passed").size(), 1)


func test_a_blown_up_player_is_knocked_down_then_moved_to_the_gallery() -> void:
	var g: PassTheBombLogic = _to_minigame()
	fx.run(PassTheBombLogic.FIRST_BOMB_DELAY + 0.2)
	var h: int = g.holder
	g._fuse_left = 0.2
	fx.run(0.3)
	assert_eq(fx.of_type(&"pass_the_bomb_exploded").size(), 1)
	var down: Array[Dictionary] = fx.of_type(&"player_knocked_down")
	assert_eq(down.size(), 1, "the blast knocks the holder down")
	assert_eq(int(down[0]["target"]), h)
	assert_eq(down[0]["cause"], &"bomb")
	fx.run(PassTheBombLogic.BLAST_KNOCKDOWN + 0.2)
	assert_true(g.gallery.has_point(fx.server.world.get_position(h)), "then out to the gallery")
	var moved: Array[Dictionary] = fx.of_type(&"minigame_player_moved").filter(func(e: Dictionary) -> bool: return int(e["player"]) == h)
	assert_eq(moved.size(), 1)
	# Out players stay in the gallery.
	fx.intent(h, &"move", {"pos": Serializer.vec3(g.spawn_for(h)), "yaw": 0.0})
	assert_true(g.gallery.has_point(fx.server.world.get_position(h)), "can't walk back into the arena")


func test_everyone_is_back_in_the_hall_after_the_game() -> void:
	var g: PassTheBombLogic = _to_minigame()
	var t: float = 0.0
	while fx.of_type(&"regroup_started").is_empty() and t < 400.0:
		if fx.server.minigame == g and g.state == PassTheBombLogic.State.LIVE:
			g._fuse_left = minf(g._fuse_left, 0.5)  # quick bangs
		fx.run(0.5)
		t += 0.5
	assert_eq(fx.of_type(&"pass_the_bomb_finished").size(), 1, "the game ran to its end")
	assert_eq(fx.of_type(&"regroup_started").size(), 1, "the regroup came")
	var positions: Dictionary = fx.of_type(&"regroup_started")[0]["positions"]
	for p: int in fx.player_ids:
		var spot: Vector3 = fx.server.map_def.lobby_spawn(p)
		assert_eq(fx.server.world.get_position(p), spot, "player %d back in the hall" % p)
		assert_eq(Serializer.to_vec3(positions[p]), spot)
	# The room is closed: no clamp, no refusals.
	var p0: int = fx.player_ids[0]
	var hall: Vector3 = fx.server.map_def.lobby_spawn(p0)
	assert_true(fx.server.apply_move(p0, hall + Vector3(0.3, 0, 0), 0.0, false), "free to walk in the hall")
	assert_false(fx.server.sanity.in_bounds(g.spawn_for(p0)), "the room is off the map again")
	assert_ne(fx.intent(p0, &"megaphone")["error"], &"minigame")
