extends GutTest
## Practice has no minigames (Patrick 2026-11-16: "No minigames in the practise mode"): the casino
## never closes; where a minigame would start the round turns over (new limits, fresh Gift Shop
## stock, Out of Order signs down) and the match ends after the same casino time as usual.

var server: MatchServer
var events: Array[Dictionary] = []


func _configure(extra: Dictionary) -> void:
	events.clear()
	server = MatchServer.new()
	var s: Dictionary = {"minigames": 3, "gamble_seconds": 20.0, "seed": 7, "minigame_pool": "quiz", "minigame_briefing": 1.0}
	s.merge(extra, true)
	server.configure(s, Registry.balance, Registry.presets, Registry.game_logic_scripts(), Registry.maps[&"lucky_lounge"])
	server.event_emitted.connect(func(ev: Dictionary) -> void: events.append(ev))
	server.add_player("dev:solo", "Solo")
	server.start_match()


func after_each() -> void:
	if server != null:
		server.free()
		server = null


func _of(type: StringName) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _phases() -> Array:
	return _of(&"phase_changed").map(func(e: Dictionary) -> StringName: return e["phase_name"])


func _advance(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds and server.phases.phase != Phase.Id.RESULTS:
		server.advance(MatchServer.TICK)
		t += MatchServer.TICK


func test_practice_runs_casino_to_results_without_any_minigame() -> void:
	_configure({"no_minigames": true})
	assert_true(bool(server.lobby.settings["no_minigames"]), "clients see it in the lobby settings")
	_advance(200.0)
	assert_eq(_phases(), [&"intro", &"casino", &"results"], "no warning, minigame, rewards or regroup")
	assert_eq(_of(&"minigame_warning").size(), 0)
	assert_eq(_of(&"minigame_started").size(), 0)
	assert_eq(_of(&"rewards_started").size(), 0)
	assert_eq(_of(&"round_turned").size(), 3, "a new round where each minigame would have started")
	assert_eq(_of(&"match_ended").size(), 1)
	assert_almost_eq(server.phases.casino_time, 80.0, 0.01, "same casino time as a match with minigames")


func test_round_turn_restocks_the_shop_raises_limits_and_takes_signs_down() -> void:
	_configure({"no_minigames": true})
	_advance(3.5)  # past the intro
	assert_eq(server.phases.phase, Phase.Id.CASINO)
	assert_eq(server.phases.next_minigame_in(), INF, "the HUD shows no minigame countdown")
	assert_lt(float(server.get_snapshot()["next_minigame_in"]), 0.0)
	var sid: StringName = server.stations.logics.keys()[0]
	server.stations.close_station(sid, INF)  # Out of Order: "until the next minigame"
	var restocks: int = _of(&"shop_restocked").size()
	_advance(18.0)  # casino 18.5 s: the round turns at 20 s
	assert_eq(_of(&"round_turned").size(), 0)
	_advance(2.0)
	assert_eq(_of(&"round_turned").size(), 1)
	assert_eq(server.phases.phase, Phase.Id.CASINO, "the casino stays open")
	assert_false(server.stations.is_out_of_order(sid), "the sign comes down when the round turns")
	assert_eq(_of(&"shop_restocked").size(), restocks + 1, "fresh Gift Shop stock")
	assert_eq(server.state.segment_index, 1)
	assert_false(server.minigame_now(), "no START NEXT MINIGAME")
	assert_false(server.dev_minigame_now(), "nor the developer's minigame jump")


func test_without_the_flag_the_minigame_still_comes() -> void:
	_configure({})
	_advance(30.0)
	assert_eq(_of(&"minigame_started").size(), 1)
	assert_eq(_of(&"round_turned").size(), 0)
