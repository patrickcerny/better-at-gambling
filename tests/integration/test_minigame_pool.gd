extends GutTest
## Minigame selector end to end: a match with a `minigame_pool` of two games only ever plays those,
## and the leader's `lobby_setting` changes the rotation of a party room (carried in the snapshot
## like every lobby setting).

const POOL: String = "quiz,lonely_number"


func _run_to_end(server: MatchServer, max_seconds: float = 1500.0) -> void:
	var t: float = 0.0
	while server.phases.phase != Phase.Id.RESULTS and t < max_seconds:
		server.advance(MatchServer.TICK)
		t += MatchServer.TICK


func test_a_two_game_pool_only_plays_those_games() -> void:
	var fx := ServerFixture.new(3, {"minigames": 4, "gamble_seconds": 5.0, "seed": 11, "minigame_pool": POOL})
	fx.server.start_match()
	_run_to_end(fx.server)
	var played: Array = fx.of_type(&"minigame_started").map(func(e: Dictionary) -> String: return str(e["minigame"]))
	assert_eq(played.size(), 4)
	for id: String in played:
		assert_true(POOL.split(",").has(id), "%s is in the pool" % id)
	assert_true(played.has("quiz") and played.has("lonely_number"), "the bag plays both")
	assert_eq(fx.server.lobby.settings["minigame_pool"], POOL)
	fx.server.free()


func test_the_leader_picks_the_pool_in_the_lobby() -> void:
	var server := MatchServer.new()
	var events: Array[Dictionary] = []
	server.configure({"minigames": 3, "seed": 4, "mode": "minigames", "minigame_briefing": 0.0}, Registry.balance, Registry.presets, Registry.game_logic_scripts(), Registry.maps[&"lucky_lounge"])
	server.event_emitted.connect(func(ev: Dictionary) -> void: events.append(ev))
	server.open_lobby()
	var a: int = server.add_player("dev:a", "A")
	var b: int = server.add_player("dev:b", "B")
	assert_eq(server.lobby.settings["minigame_pool"], "", "every game by default")
	assert_eq(server.submit_intent(b, Intents.make(&"lobby_setting", {"key": "minigame_pool", "value": "quiz"}))["error"], &"not_leader")
	assert_true(server.submit_intent(a, Intents.make(&"lobby_setting", {"key": "minigame_pool", "value": "lonely_number,bogus"}))["ok"])
	var last: Dictionary = events.filter(func(e: Dictionary) -> bool: return e["type"] == &"lobby_settings").back()
	assert_eq(last["settings"]["minigame_pool"], "lonely_number", "unknown ids dropped")
	assert_eq(server.get_snapshot()["lobby"]["settings"]["minigame_pool"], "lonely_number", "late joiners get it in the snapshot")
	server.start_match()
	_run_to_end(server)
	var played: Array = events.filter(func(e: Dictionary) -> bool: return e["type"] == &"minigame_started").map(func(e: Dictionary) -> String: return str(e["minigame"]))
	assert_eq(played, ["lonely_number", "lonely_number", "lonely_number"])
	server.free()
