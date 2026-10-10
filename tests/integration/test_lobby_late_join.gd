extends GutTest
## Late join (Patrick: "Let players join running rounds (even though they didnt join at the start
## of the game)"): a new player admitted into a running room match gets the normal starting cash,
## spawns at the entrance hall by the lobby doors, shows up in a full snapshot, sits out the
## minigame already running and plays the next one.

var server: MatchServer
var events: Array[Dictionary] = []
var map: MapDefinition


func before_each() -> void:
	events.clear()
	server = MatchServer.new()
	map = Registry.maps[&"lucky_lounge"].duplicate() as MapDefinition
	map.lobby_spawns = LuckyLounge.LOBBY_SPAWNS.duplicate()
	server.configure({"minigames": 2, "gamble_seconds": 30.0, "seed": 8, "minigame_pool": "quiz", "minigame_briefing": 0.0}, Registry.balance, Registry.presets, Registry.game_logic_scripts(), map)
	server.event_emitted.connect(func(ev: Dictionary) -> void: events.append(ev))
	server.open_lobby()
	server.add_player("dev:a", "A")
	server.add_player("dev:b", "B")
	server.start_match()


func after_each() -> void:
	server.free()


func _of(type: StringName) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _run_until(phase: Phase.Id, max_seconds: float = 400.0) -> void:
	var t: float = 0.0
	while server.phases.phase != phase and t < max_seconds:
		server.advance(MatchServer.TICK)
		t += MatchServer.TICK


func test_late_joiner_in_the_casino_gets_cash_a_hall_spot_a_snapshot_and_the_next_minigame() -> void:
	_run_until(Phase.Id.CASINO)
	server.advance(5.0)
	assert_eq(server.phases.phase, Phase.Id.CASINO)
	var late: int = server.add_player("dev:late", "Late")
	assert_eq(server.economy.balance(late), Registry.balance.start_money, "normal starting cash")
	var joined: Dictionary = _of(&"player_joined").back()
	assert_true(bool(joined["late"]), "flagged as a late join")
	var spot: Vector3 = map.lobby_spawn(late)
	assert_true(server.world.get_position(late).is_equal_approx(spot), "spawns in the entrance hall")
	assert_true(server.can_move(late), "walks in on their own")
	# The snapshot a late joiner gets (WELCOME) is complete and consistent.
	var snap: Dictionary = server.get_snapshot()
	assert_eq(int(snap["phase"]), Phase.Id.CASINO)
	assert_true((snap["players"] as Dictionary).has(late), "in the snapshot's players")
	assert_eq(int((snap["balances"] as Dictionary)[late]), Registry.balance.start_money)
	assert_eq((snap["players"] as Dictionary).size(), 3)
	assert_true(Serializer.to_vec3(snap["players"][late]["pos"]).is_equal_approx(spot))
	assert_true(snap.has("stations") and snap.has("lobby") and snap.has("time_left"))
	var private: Dictionary = server.get_private_snapshot(late)
	assert_true(private.has("items"))
	# The next minigame includes them.
	_run_until(Phase.Id.MINIGAME)
	var started: Dictionary = _of(&"minigame_started").back()
	assert_true((started["players"] as Array).has(late), "plays the next minigame")
	assert_eq(Log.error_count, 0)


func test_late_joiner_during_a_minigame_sits_it_out_and_plays_the_next() -> void:
	_run_until(Phase.Id.MINIGAME)
	assert_not_null(server.minigame)
	var late: int = server.add_player("dev:late", "Late")
	assert_false(server.minigame.players.has(late), "not in the minigame already running")
	var snap: Dictionary = server.get_snapshot()
	assert_true(snap.has("minigame"), "the snapshot carries the running minigame")
	assert_false((snap["minigame"]["players"] as Array).has(late), "…without the late joiner")
	assert_eq(snap["minigame_roster"], server.minigame.players, "who it started with: the client sits out if it isn't listed")
	assert_false((snap["minigame_roster"] as Array).has(late))
	assert_eq(server.economy.balance(late), Registry.balance.start_money)
	# Answers from the late joiner don't count in this one.
	server.submit_intent(late, Intents.make(&"submit_answer", {"question": 0, "index": 0}))
	_run_until(Phase.Id.REWARDS)
	var ranking: Array = _of(&"minigame_finished").back()["ranking"]
	assert_false(ranking.any(func(r: Dictionary) -> bool: return int(r["player"]) == late), "no ranking row")
	_run_until(Phase.Id.CASINO)
	_run_until(Phase.Id.MINIGAME)
	assert_eq(_of(&"minigame_started").size(), 2)
	assert_true((_of(&"minigame_started").back()["players"] as Array).has(late), "in the next one")
	server.run_to_end()
	var standings: Array = _of(&"match_ended").back()["standings"]
	assert_true(standings.any(func(r: Dictionary) -> bool: return int(r["player"]) == late), "on the podium list")

