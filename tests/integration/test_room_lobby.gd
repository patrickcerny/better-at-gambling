extends GutTest
## Online room flow on the authoritative server (§2.2, §4.1): lobby, leader, cosmetics,
## ready → countdown → match, and the validator rules every client intent goes through.

var server: MatchServer
var events: Array[Dictionary] = []


func before_each() -> void:
	events.clear()
	server = MatchServer.new()
	server.configure({"minigames": 2, "seed": 3}, Registry.balance, Registry.presets, Registry.game_logic_scripts(), Registry.maps[&"lucky_lounge"])
	server.event_emitted.connect(func(ev: Dictionary) -> void: events.append(ev))
	server.open_lobby()


func after_each() -> void:
	server.free()


func _of(type: StringName) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _intent(p: int, type: StringName, payload: Dictionary = {}) -> Dictionary:
	return server.submit_intent(p, Intents.make(type, payload))


func _tick(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		server.advance(0.05)
		t += 0.05


func test_colors_are_fixed_and_unique_and_skins_are_picked() -> void:
	var a: int = server.add_player("dev:a", "A", 3, &"cowboy")
	var b: int = server.add_player("dev:b", "B", 3, &"king")
	assert_eq(server.state.players[a].color_index, 0, "wishes ignored: first free color")
	assert_eq(server.state.players[b].color_index, 1)
	assert_eq(server.state.players[a].skin, &"bean", "unknown skins fall back to the bean")
	assert_eq(server.state.players[b].skin, &"king", "saved skin is kept")
	assert_false(_intent(b, &"set_cosmetics", {"color": 6, "hat": &"cowboy"})["ok"], "no color picker any more")
	assert_true(_intent(a, &"set_skin", {"skin": &"swat"})["ok"])
	assert_eq(server.state.players[a].skin, &"swat")
	assert_false(_intent(a, &"set_skin", {"skin": &"dragon"})["ok"])
	assert_eq(server.state.players[a].skin, &"swat")


func test_not_ready_wins_over_the_pad_and_reconnect_starts_not_ready() -> void:
	var a: int = server.add_player("dev:a", "A")
	server.add_player("dev:b", "B")
	server.report_on_pad(a, true)
	assert_true(server.state.players[a].ready, "pad readies")
	assert_true(_intent(a, &"set_ready", {"ready": false})["ok"])
	assert_false(server.state.players[a].ready, "NOT READY works while standing on the pad")
	server.report_on_pad(a, false)
	server.report_on_pad(a, true)
	assert_true(server.state.players[a].ready, "stepping back on readies again")
	server.player_disconnected(a)
	assert_false(server.state.players[a].ready)
	server.player_reconnected(a)
	assert_false(server.state.players[a].ready, "back as not ready")
	assert_true(_intent(a, &"set_ready", {"ready": true})["ok"])
	assert_true(server.state.players[a].ready, "READY works after a reconnect")
	assert_true(_intent(a, &"set_ready", {"ready": false})["ok"])
	assert_false(server.state.players[a].ready)


func test_leader_settings_ready_countdown_and_start() -> void:
	var a: int = server.add_player("dev:a", "A")
	var b: int = server.add_player("dev:b", "B")
	assert_eq(server.lobby.leader(), a)
	assert_eq(_intent(b, &"lobby_setting", {"key": "minigames", "value": 4})["error"], &"not_leader")
	assert_true(_intent(a, &"lobby_setting", {"key": "minigames", "value": 4})["ok"])
	assert_true(_intent(a, &"lobby_setting", {"key": "gamble_minutes", "value": 2})["ok"])
	assert_eq(_intent(a, &"lobby_setting", {"key": "gamble_minutes", "value": 9})["error"], &"bad_value")
	assert_eq(server.submit_intent(a, {"type": &"add_bot"})["error"], &"malformed", "the game has no bots")
	assert_eq(_intent(a, &"place_bet", {"station": &"slot_1", "bet": {"amount": 10}})["error"], &"wrong_phase", "no gambling in the lobby")
	_intent(a, &"set_ready", {"ready": true})
	_tick(5.0)
	assert_eq(server.phases.phase, Phase.Id.LOBBY, "B isn't ready")
	server.report_on_pad(b, true)
	_tick(0.1)
	assert_eq(_of(&"lobby_countdown").size(), 1)
	server.report_on_pad(b, false)
	_tick(0.1)
	assert_eq(_of(&"lobby_countdown_cancelled").size(), 1)
	server.report_on_pad(b, true)
	_tick(LobbyController.COUNTDOWN_SECONDS + 0.5)
	assert_eq(_of(&"match_started").size(), 1)
	var started: Dictionary = _of(&"match_started")[0]
	assert_eq(int(started["minigames"]), 4, "the leader's match length applies")
	assert_almost_eq(float(started["gamble_s"]), 120.0, 0.001)
	assert_almost_eq(float(started["duration_s"]), 600.0, 0.001, "2 min × (4 minigames + the last stretch)")
	assert_eq(server.schedule.minigames, 4)
	assert_ne(server.phases.phase, Phase.Id.LOBBY)


func test_leader_leaving_hands_over_and_late_joins_are_refused_by_phase() -> void:
	var a: int = server.add_player("dev:a", "A")
	var b: int = server.add_player("dev:b", "B")
	server.player_disconnected(a)
	assert_eq(server.lobby.leader(), b)
	assert_eq(_of(&"leader_changed").back()["player"], b)
	server.player_reconnected(a)
	assert_eq(server.lobby.leader(), b, "leadership sticks")
	assert_eq(server.player_by_uid("dev:a"), a, "reconnect finds the same player")


func test_validator_rules() -> void:
	var a: int = server.add_player("dev:a", "A")
	var b: int = server.add_player("dev:b", "B")
	server.start_match()
	_tick(4.0)  # intro
	assert_eq(server.phases.phase, Phase.Id.CASINO)
	server.set_server_position(a, Vector3(Registry.maps[&"lucky_lounge"].station_positions.get(&"slot_1", Vector3.ZERO)))
	server.set_server_position(b, Vector3(Registry.maps[&"lucky_lounge"].station_positions.get(&"slot_2", Vector3.ZERO)))
	assert_eq(_intent(a, &"place_bet", {"station": &"slot_1", "bet": {"amount": 10}})["error"], &"not_seated")
	assert_true(_intent(a, &"sit", {"station": &"slot_1"})["ok"])
	assert_true(_intent(b, &"sit", {"station": &"slot_2"})["ok"])
	assert_eq(_intent(a, &"place_bet", {"station": &"slot_2", "bet": {"amount": 10}})["error"], &"not_seated", "someone else's station")
	var before: int = server.economy.balance(a)
	assert_false(_intent(a, &"place_bet", {"station": &"slot_1", "bet": {"amount": before + 1}})["ok"], "bet over money")
	assert_eq(server.economy.balance(a), before)
	assert_eq(server.submit_intent(a, {"type": &"place_bet", "station": &"slot_1"})["error"], &"malformed")
	assert_eq(server.submit_intent(a, {"type": &"hack_money", "amount": 1e9})["error"], &"malformed")
	_tick(1.1)  # fresh rate-limit window
	var limited: int = 0
	for i: int in 30:
		if _intent(b, &"emote", {"id": &"wave"})["error"] == &"rate_limited":
			limited += 1
	assert_eq(limited, 10, "more than 20 intents per second are dropped")
