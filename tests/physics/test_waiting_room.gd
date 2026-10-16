extends GutTest
## The waiting room behind the start room as bodies feel it (Patrick: "after the game starts the
## door to the hidden room closes"): its door is solid while shut (Practice, a running match) and
## open in an online lobby, the four slots and the blackjack table stand inside it, their prompt
## only shows from inside, a seat there opens the station panel on PLAY MONEY, and when the match
## starts everyone inside stands up and is back in the start room behind a shut door.

var scene: MatchScene


func before_each() -> void:
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_seconds(3.3)


## The practice match turned into an online room waiting in the lobby, waiting room open.
func _wait_in_lobby() -> void:
	scene.server.room_mode = true
	scene.server.running = false
	scene.server.phases.phase = Phase.Id.LOBBY
	scene.map.set_lobby_open(false)
	scene.server._open_fun_room()
	scene.server._flush()
	await wait_physics_frames(3)


func _put(pos: Vector3, yaw: float) -> void:
	scene.local.teleport(pos, yaw)
	scene.server.set_server_position(scene.local_id, pos)


## Throws the local player at the doorway from the start room; returns the furthest z reached.
func _throw_at_the_door() -> float:
	_put(Vector3(0, 0, 13.6), PI)
	await wait_physics_frames(2)
	var rd: RagdollBody = scene.local.start_ragdoll(Vector3(0, 2.5, 14.0))
	var furthest: float = -INF
	for i: int in 70:
		await wait_physics_frames(1)
		if is_instance_valid(rd):
			furthest = maxf(furthest, rd.body_position().z)
	if scene.local.state == PlayerAvatar.State.RAGDOLL:
		scene.local.end_ragdoll(Vector3(0, 0, 12.0))
	await wait_physics_frames(2)
	return furthest


func test_the_room_and_its_tables() -> void:
	var area: AABB = LuckyLounge.WAITING_AREA
	var slots: int = 0
	var tables: int = 0
	for sid: StringName in LuckyLounge.FUN_STATIONS:
		assert_true(scene.map.stations.has(sid), "%s is built" % sid)
		var st: StationBase = scene.map.stations[sid]
		assert_true(area.has_point(st.global_position), "%s stands in the room" % sid)
		for i: int in st.seats.size():
			assert_true(area.has_point(st.seat_position(i)), "%s seat %d is in the room" % [sid, i])
		slots += 1 if st.game_id == &"slots" else 0
		tables += 1 if st.game_id == &"blackjack" else 0
		assert_true(scene.server.map_def.station_positions.has(sid), "the server knows where %s is" % sid)
		assert_false(scene.server.stations.logics.has(sid), "%s is not a casino station" % sid)
	assert_eq(slots, 4, "four slot machines")
	assert_eq(tables, 1, "one blackjack table")
	assert_true(scene.server.map_def.has_waiting_room())
	assert_not_null(scene.map.find_child("WaitingSign", false, false), "the WAITING ROOM · PLAY MONEY board")
	assert_eq((scene.map.find_child("WaitingSign", false, false) as Label3D).text, LuckyLounge.WAITING_SIGN)
	for spot: Vector3 in LuckyLounge.LOBBY_SPAWNS + LuckyLounge.SPAWNS:
		assert_false(area.has_point(spot), "spawn %s is not in the waiting room" % spot)


func test_practice_keeps_the_door_shut_and_solid() -> void:
	assert_false(scene.map.waiting_open, "no waiting room in Practice")
	var barrier: CollisionShape3D = scene.map.waiting_door.get_node(^"Shape") as CollisionShape3D
	assert_false(barrier.disabled)
	var box: BoxShape3D = barrier.shape as BoxShape3D
	assert_gte(box.size.x, LuckyLounge.WAIT_DOOR_HALF * 2.0, "the full gap")
	assert_gte(box.size.y, LuckyLounge.WAIT_DOOR_H)
	var furthest: float = await _throw_at_the_door()
	assert_lt(furthest, LuckyLounge.WAIT_Z0 - 0.3, "bounced off the shut door (got to z=%.2f)" % furthest)
	assert_false(LuckyLounge.in_waiting_room(scene.local.global_position))


func test_the_lobby_opens_it_and_the_match_start_shuts_it() -> void:
	await _wait_in_lobby()
	assert_true(scene.view.state.waiting_room_open, "the client heard the room open")
	assert_true(scene.map.waiting_open, "the door follows")
	await wait_physics_frames(2)
	var barrier: CollisionShape3D = scene.map.waiting_door.get_node(^"Shape") as CollisionShape3D
	assert_true(barrier.disabled, "walk-through while open")
	var furthest: float = await _throw_at_the_door()
	assert_gt(furthest, LuckyLounge.WAIT_Z0 + 0.5, "through the open door into the room (got to z=%.2f)" % furthest)
	# Inside: only the room's tables offer a seat, with PLAY MONEY on the prompt. (The lobby clock
	# stands still: the throw's knockdown is cleared by hand.)
	scene.server.rules.clear_downs()
	var bj: StationBase = scene.map.stations[&"fun_blackjack_1"]
	_put(bj.seat_position(1) + Vector3(0, 0, -0.6), PI)
	await wait_frames(3)
	assert_not_null(scene.nearest_station)
	assert_true(FunRoom.is_fun(scene.nearest_station.station_id), "the play table is the one in reach")
	assert_string_contains(scene.hud.prompt_label.text, "PLAY MONEY")
	var sat: Dictionary = Net.send_intent(Intents.make(&"sit", {"station": &"fun_blackjack_1"}))
	assert_true(sat["ok"], str(sat))
	await wait_frames(4)
	assert_eq(scene.local.state, PlayerAvatar.State.SEATED, "seated at the play table")
	assert_not_null(scene.current_ui)
	assert_true(scene.current_ui.fun)
	assert_true(scene.current_ui.play_money_label.visible)
	assert_string_contains(scene.current_ui.play_money_label.text, "PLAY MONEY")
	assert_eq(scene.server.fun_room.balance(scene.local_id), FunRoom.PLAY_CHIPS)
	var real: int = scene.server.economy.balance(scene.local_id)
	# Standing on the start room side next to the wall, the play tables are out of reach.
	# The match starts: stood up, back in the start room, door shut.
	scene.server._close_fun_room()
	scene.server._flush()
	await wait_physics_frames(4)
	assert_ne(scene.local.state, PlayerAvatar.State.SEATED, "stood up")
	assert_false(LuckyLounge.in_waiting_room(scene.local.global_position), "back in the start room")
	assert_almost_eq(scene.local.global_position.z, scene.map.lobby_spawn(scene.local_id).z, 0.5)
	assert_false(scene.view.state.waiting_room_open)
	assert_false(scene.map.waiting_open)
	assert_false(barrier.disabled, "solid again")
	assert_eq(scene.server.economy.balance(scene.local_id), real, "the real money never moved")
	assert_eq(scene.view.state.balance(scene.local_id), real)


func test_the_play_tables_are_out_of_reach_from_the_start_room() -> void:
	await _wait_in_lobby()
	for x: float in [-4.6, -3.0, 0.0, 3.0, 4.6]:
		_put(Vector3(x, 0, 15.3), 0.0)
		await wait_frames(3)
		assert_true(scene.nearest_station == null or not FunRoom.is_fun(scene.nearest_station.station_id), "x=%.1f: no play-table prompt through the wall" % x)
