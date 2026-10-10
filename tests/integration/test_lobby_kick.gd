extends GutTest
## Kicking (Patrick: "Give the party lead the right to kick players"): only the party leader may
## kick, never themselves; the kicked player is gone from the lobby (or away in a running match),
## the room's kick handler drops their connection, and they can't rejoin for 60 s.

var server: MatchServer
var events: Array[Dictionary] = []
var dropped: Array[int] = []


func before_each() -> void:
	events.clear()
	dropped.clear()
	server = MatchServer.new()
	server.configure({"minigames": 1, "gamble_seconds": 30.0, "seed": 5, "minigame_pool": "quiz", "minigame_briefing": 0.0}, Registry.balance, Registry.presets, Registry.game_logic_scripts(), Registry.maps[&"lucky_lounge"])
	server.event_emitted.connect(func(ev: Dictionary) -> void: events.append(ev))
	server.kick_handler = func(pid: int) -> void: dropped.append(pid)
	server.open_lobby()


func after_each() -> void:
	server.free()


func _of(type: StringName) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _kick(by: int, target: Variant) -> Dictionary:
	return server.submit_intent(by, Intents.make(&"kick_player", {"target": target}))


func test_the_leader_kicks_a_player_out_of_the_lobby() -> void:
	var host: int = server.add_player("dev:host", "Host")
	var bob: int = server.add_player("dev:bob", "Bob")
	var cat: int = server.add_player("dev:cat", "Cat")
	assert_eq(server.lobby.leader(), host)
	var res: Dictionary = _kick(host, bob)
	assert_true(res["ok"], str(res))
	assert_eq(dropped, [bob], "the room drops the kicked player's connection")
	assert_false(server.state.players.has(bob), "gone from the lobby")
	assert_false(server.lobby.has(bob))
	assert_false(server.economy.has_player(bob))
	var kicked: Array[Dictionary] = _of(&"player_kicked")
	assert_eq(kicked.size(), 1)
	assert_eq(int(kicked[0]["player"]), bob)
	assert_eq(int(kicked[0]["by"]), host)
	assert_eq(_of(&"player_removed").size(), 1)
	assert_lt(events.find(kicked[0]), events.find(_of(&"player_removed")[0]), "the kick goes out before the removal")
	assert_true(server.state.players.has(cat), "the others stay")
	assert_eq(server.occupied_slots(), 2, "the slot is free again")


func test_non_leaders_cannot_kick_and_nobody_kicks_themselves() -> void:
	var host: int = server.add_player("dev:host", "Host")
	var bob: int = server.add_player("dev:bob", "Bob")
	assert_eq(_kick(bob, host)["error"], &"not_leader")
	assert_eq(_kick(host, host)["error"], &"bad_target")
	assert_eq(_kick(host, 99)["error"], &"bad_target")
	assert_eq(_kick(host, "bob")["error"], &"bad_target")
	assert_eq(server.submit_intent(host, {"type": &"kick_player"})["error"], &"malformed", "needs a target")
	assert_true(dropped.is_empty())
	assert_true(server.state.players.has(host) and server.state.players.has(bob))
	assert_eq(_of(&"player_kicked").size(), 0)
	assert_eq(_of(&"intent_rejected").back()["intent"], &"kick_player")


func test_a_kicked_player_cannot_rejoin_for_60_seconds() -> void:
	var host: int = server.add_player("dev:host", "Host")
	var bob: int = server.add_player("dev:bob", "Bob")
	_kick(host, bob)
	assert_almost_eq(server.kick_blocked_for("dev:bob"), Protocol.KICK_REJOIN_SECONDS, 0.1)
	assert_eq(server.kick_blocked_for("dev:host"), 0.0, "only the kicked identity")
	server.advance(30.0)
	assert_almost_eq(server.kick_blocked_for("dev:bob"), 30.0, 0.1, "still blocked")
	server.advance(30.5)
	assert_eq(server.kick_blocked_for("dev:bob"), 0.0, "welcome back after a minute")


func test_kicking_in_a_running_match_leaves_them_away() -> void:
	var host: int = server.add_player("dev:host", "Host")
	var bob: int = server.add_player("dev:bob", "Bob")
	server.start_match()
	server.advance(4.0)
	assert_eq(server.phases.phase, Phase.Id.CASINO)
	var money: int = server.economy.balance(bob)
	assert_true(_kick(host, bob)["ok"])
	assert_eq(dropped, [bob])
	assert_true(server.state.players.has(bob), "a running match keeps their standing")
	assert_false(server.state.players[bob].connected, "away, like a disconnect")
	assert_eq(server.economy.balance(bob), money)
	assert_gt(server.kick_blocked_for("dev:bob"), 59.0)


func test_practice_has_no_kicking() -> void:
	var practice := MatchServer.new()
	practice.configure({"minigames": 1, "seed": 2}, Registry.balance, Registry.presets, Registry.game_logic_scripts(), Registry.maps[&"lucky_lounge"])
	var me: int = practice.add_player("local", "Me")
	var dummy: int = practice.add_player("dummy-1", "Chip")
	assert_eq(practice.submit_intent(me, Intents.make(&"kick_player", {"target": dummy}))["error"], &"not_room")
	practice.free()
