extends GutTest
## The Lucky Lounge's rooms on the authoritative server (0.8.19): nobody stays in the casino while
## the start room waits in LOBBY, a jailed player is held inside the barred cell, and on release
## they come out at the lobby doors.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(2, {"minigames": 2, "gamble_seconds": 100.0, "seed": 42})
	LuckyLounge.describe_rooms(fx.server.map_def)
	fx.server.map_def.lobby_spawns = LuckyLounge.LOBBY_SPAWNS.duplicate()


func after_each() -> void:
	fx.server.free()


func _start() -> void:
	fx.server.start_match()
	fx.run(3.1)
	fx.place_all(Vector3(0, 0, -4))


func test_the_map_describes_its_rooms() -> void:
	var def: MapDefinition = fx.server.map_def
	assert_true(def.has_jail())
	for spot: Vector3 in LuckyLounge.JAIL_SPOTS:
		assert_true(def.in_jail(spot), "cell spot %s inside the cell" % spot)
	for out: Vector3 in LuckyLounge.JAIL_EXITS:
		assert_false(def.in_jail(out), "exit %s outside the cell" % out)
		# Jail time only runs mid-match, doors open: they step out just inside the casino doors.
		assert_true(def.past_lobby_doors(out), "exit %s on the casino side" % out)
		assert_lt(def.lobby_door_z - out.z, 1.5, "exit %s right at the lobby doors" % out)
		assert_lt(absf(out.x), LuckyLounge.LOBBY_DOOR_HALF, "exit %s in front of the doorway" % out)
	for spawn: Vector3 in LuckyLounge.LOBBY_SPAWNS:
		assert_false(def.past_lobby_doors(spawn), "lobby spawn %s in the start room" % spawn)
	assert_false(def.past_lobby_doors(LuckyLounge.RESPAWN_POS), "respawn in the start room")
	assert_true(def.past_lobby_doors(Vector3(0, 0, 0)), "the casino floor is past the doors")


func test_lobby_sends_anyone_past_the_doors_back_to_their_spot() -> void:
	fx.server.open_lobby()
	var p: int = fx.player_ids[0]
	var q: int = fx.player_ids[1]
	fx.server.set_server_position(q, fx.server.map_def.lobby_spawn(q))
	fx.server.world.set_transform(p, Vector3(1.0, 0.4, 5.0), 0.0)  # thrown through the doorway
	fx.server.set_server_owned(p, true)  # a ragdoll the server simulates
	fx.events.clear()
	fx.server.advance(0.05)
	var sent: Array[Dictionary] = fx.of_type(&"player_sent_back")
	assert_eq(sent.size(), 1, "only the straggler is sent back")
	assert_eq(int(sent[0]["player"]), p)
	var spot: Vector3 = fx.server.map_def.lobby_spawn(p)
	assert_eq(Serializer.to_vec3(sent[0]["pos"]), spot)
	assert_eq(fx.server.world.get_position(p), spot, "server body back in the start room")
	assert_false(fx.server.is_server_owned(p), "the client owns the body again")
	fx.events.clear()
	fx.server.advance(0.05)
	assert_eq(fx.of_type(&"player_sent_back").size(), 0, "once back, left alone")


func test_a_jailed_player_is_put_in_the_cell_and_held_there() -> void:
	_start()
	var p: int = fx.player_ids[0]
	fx.server.put_in_jail(p)
	var ev: Dictionary = fx.of_type(&"player_jailed")[0]
	var spot: Vector3 = fx.server.map_def.jail_spot(p)
	assert_eq(Serializer.to_vec3(ev["pos"]), spot, "the event says where the cell spot is")
	assert_eq(fx.server.world.get_position(p), spot)
	# The client walks out through the bars: refused and held inside.
	assert_false(fx.server.apply_move(p, Vector3(19.5, 0, -7.5), 0.0, false), "walking out is refused")
	assert_true(fx.server.map_def.in_jail(fx.server.world.get_position(p)), "still in the cell")
	# A small step inside the cell is fine.
	var inside: Vector3 = spot + Vector3(0.3, 0, 0.2)
	assert_true(fx.server.apply_move(p, inside, 0.0, false))
	assert_eq(fx.server.world.get_position(p), inside)
	# Offline moves are clamped too, and the cell holds them every tick.
	fx.intent(p, &"move", {"pos": Serializer.vec3(Vector3(10, 0, -7.5)), "yaw": 0.0})
	assert_true(fx.server.map_def.in_jail(fx.server.world.get_position(p)), "move intent clamped")
	fx.server.world.set_transform(p, Vector3(-12, 0, 2), 0.0)
	fx.run(0.1)
	assert_true(fx.server.map_def.in_jail(fx.server.world.get_position(p)), "the tick puts them back")
	# No grabbing through the bars, either way.
	assert_false(bool(fx.intent(fx.player_ids[1], &"grab", {"target": p}).get("ok", true)), "can't grab a prisoner")
	assert_false(bool(fx.intent(p, &"grab", {"target": fx.player_ids[1]}).get("ok", true)), "can't grab from the cell")


func test_release_puts_them_at_the_lobby_doors_outside_the_cell() -> void:
	_start()
	var p: int = fx.player_ids[0]
	fx.server.put_in_jail(p)
	fx.run(8.2)
	assert_almost_eq(fx.server.state.players[p].jail_time_remaining, 0.0, 0.001)
	var rel: Array[Dictionary] = fx.of_type(&"player_released_from_jail")
	assert_eq(rel.size(), 1)
	var out: Vector3 = fx.server.map_def.jail_exit(p)
	assert_eq(Serializer.to_vec3(rel[0]["pos"]), out)
	assert_eq(fx.server.world.get_position(p), out)
	assert_false(fx.server.map_def.in_jail(out))
	# Free to walk away now.
	assert_true(fx.server.apply_move(p, out + Vector3(0.4, 0, -0.3), 0.0, false))


func test_a_map_without_a_cell_keeps_the_timer_only_jail() -> void:
	fx.server.map_def.jail_area = AABB()
	_start()
	var p: int = fx.player_ids[0]
	fx.server.put_in_jail(p)
	assert_false(fx.of_type(&"player_jailed")[0].has("pos"))
	assert_true(fx.server.apply_move(p, Vector3(0, 0, -4.3), 0.0, false), "free to move")
