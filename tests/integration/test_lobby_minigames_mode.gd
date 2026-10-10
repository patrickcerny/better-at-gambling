extends GutTest
## MINIGAMES ONLY party mode (Patrick: "Play minigames button so you can only play minigames with
## friends"): the leader picks it in the lobby; the match plays the chosen number of minigames back
## to back (briefing → minigame → results/rewards → next minigame) with no casino phase at all,
## then the podium. Practice runs the same mode from its own settings.

var server: MatchServer
var events: Array[Dictionary] = []


func before_each() -> void:
	events.clear()
	server = MatchServer.new()
	server.configure({"minigames": 5, "seed": 4, "minigame_pool": "quiz", "minigame_briefing": 2.0}, Registry.balance, Registry.presets, Registry.game_logic_scripts(), Registry.maps[&"lucky_lounge"])
	server.event_emitted.connect(func(ev: Dictionary) -> void: events.append(ev))
	server.open_lobby()


func after_each() -> void:
	server.free()


func _of(type: StringName) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _phases() -> Array:
	return _of(&"phase_changed").map(func(e: Dictionary) -> StringName: return e["phase_name"])


func _run_to_end(max_seconds: float = 900.0) -> void:
	var t: float = 0.0
	while server.phases.phase != Phase.Id.RESULTS and t < max_seconds:
		server.advance(MatchServer.TICK)
		t += MatchServer.TICK


func test_leader_picks_minigames_only_and_it_runs_minigame_results_minigame_without_casino() -> void:
	var a: int = server.add_player("dev:a", "A")
	var b: int = server.add_player("dev:b", "B")
	assert_eq(server.submit_intent(b, Intents.make(&"lobby_setting", {"key": "mode", "value": "minigames"}))["error"], &"not_leader")
	assert_eq(server.submit_intent(a, Intents.make(&"lobby_setting", {"key": "mode", "value": "poker"}))["error"], &"bad_value")
	assert_true(server.submit_intent(a, Intents.make(&"lobby_setting", {"key": "mode", "value": "minigames"}))["ok"])
	assert_true(server.submit_intent(a, Intents.make(&"lobby_setting", {"key": "minigames", "value": 2}))["ok"])
	assert_eq(_of(&"lobby_settings").back()["settings"]["mode"], MatchMode.MINIGAMES)
	server.start_match()
	var started: Dictionary = _of(&"match_started").back()
	assert_eq(started["mode"], MatchMode.MINIGAMES)
	assert_eq(int(started["minigames"]), 2)
	assert_false(bool(server.settings["items_enabled"]), "no items without a casino")
	_run_to_end()
	assert_eq(_phases(), [&"intro", &"minigame", &"rewards", &"regroup", &"minigame", &"rewards", &"regroup", &"results"])
	assert_false(_phases().has(&"casino"), "no casino phase")
	assert_false(_phases().has(&"pre_minigame"))
	assert_eq(_of(&"minigame_started").size(), 2)
	assert_gt(float(_of(&"minigame_started")[0]["briefing"]), 0.0, "each minigame has its briefing")
	assert_eq(_of(&"minigame_go").size(), 2)
	assert_eq(_of(&"rewards_started").size(), 2, "results between the minigames")
	assert_eq(_of(&"match_ended").size(), 1, "podium at the end")
	assert_eq(server.phases.casino_time, 0.0, "casino time never ran")
	assert_eq(_of(&"bet_placed").size(), 0)
	for row: Dictionary in _of(&"rewards_started")[0]["rewards"]:
		assert_eq(StringName(row.get("item", &"")), &"", "no item draft")
	assert_eq(Log.error_count, 0)


func test_the_casino_mode_is_unchanged() -> void:
	var a: int = server.add_player("dev:a", "A")
	server.add_player("dev:b", "B")
	server.submit_intent(a, Intents.make(&"lobby_setting", {"key": "minigames", "value": 1}))
	server.settings["gamble_seconds"] = 20.0
	server.start_match()
	_run_to_end()
	assert_eq(_phases(), [&"intro", &"casino", &"pre_minigame", &"minigame", &"rewards", &"regroup", &"casino", &"results"])
	assert_eq(_of(&"match_started").back()["mode"], MatchMode.CASINO)


func test_practice_minigames_only_solo_plays_what_one_player_can() -> void:
	var practice := MatchServer.new()
	var got: Array[Dictionary] = []
	practice.configure({"minigames": 3, "seed": 6, "mode": "minigames", "minigame_briefing": 0.0}, Registry.balance, Registry.presets, Registry.game_logic_scripts(), Registry.maps[&"lucky_lounge"])
	practice.event_emitted.connect(func(ev: Dictionary) -> void: got.append(ev))
	practice.add_player("local", "Me")
	practice.start_match()
	practice.run_to_end()
	var names: Array = got.filter(func(e: Dictionary) -> bool: return e["type"] == &"phase_changed").map(func(e: Dictionary) -> StringName: return e["phase_name"])
	assert_false(names.has(&"casino"))
	assert_eq(names.back(), &"results")
	var played: Array = got.filter(func(e: Dictionary) -> bool: return e["type"] == &"minigame_started").map(func(e: Dictionary) -> StringName: return StringName(e["minigame"]))
	assert_eq(played.size(), 3, "three minigames back to back")
	for id: StringName in played:
		assert_lte((Registry.minigames[id] as MinigameDefinition).min_players, 1, "%s works solo" % id)
	var too_few: Array[MinigameDefinition] = MatchMode.needs_more_players(Registry.minigames.values(), 1)
	assert_false(too_few.is_empty(), "the practice menu notes the 2+ player minigames")
	for d: MinigameDefinition in too_few:
		assert_gt(d.min_players, 1)
	practice.free()
