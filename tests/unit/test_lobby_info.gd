extends GutTest
## BROWSE LOBBIES' lobby info (Patrick 2026-11-15): the host writes its settings and beans to the
## Steam lobby data, browsers read them back without trusting them.


func _state() -> ClientMatchState:
	var st := ClientMatchState.new()
	st.leader = 2
	st.phase = Phase.Id.LOBBY
	st.lobby_settings = {"minigames": 6, "gamble_minutes": 2, "items_enabled": false, "mode": &"casino"}
	st.players[1] = {"name": "Anna", "bean_color": 4, "outfit": PackedStringArray(["hat_top"]), "connected": true}
	st.players[2] = {"name": "Patrick", "bean_color": 1, "outfit": PackedStringArray(), "connected": true}
	st.players[3] = {"name": "Gone", "bean_color": 2, "connected": false}
	return st


func test_round_trip_leader_first_and_no_away_beans() -> void:
	var info: Dictionary = LobbyInfo.parse(LobbyInfo.to_text(LobbyInfo.from_state(_state())))
	assert_eq(info["minigames"], 6)
	assert_eq(info["gamble_minutes"], 2)
	assert_false(info["items"])
	assert_eq(info["mode"], MatchMode.CASINO)
	assert_false(info["playing"])
	var beans: Array = info["beans"]
	assert_eq(beans.map(func(b: Dictionary) -> String: return b["name"]), ["Patrick", "Anna"], "leader first, away players left out")
	assert_true(beans[0]["leader"])
	assert_eq(beans[1]["color"], 4)
	assert_eq(String((beans[1]["outfit"] as PackedStringArray)[0]), "hat_top")
	assert_lt(LobbyInfo.to_text(LobbyInfo.from_state(_state())).length(), 1024)


func test_parse_trusts_nothing() -> void:
	assert_eq(LobbyInfo.parse(""), {})
	assert_eq(LobbyInfo.parse("not json"), {})
	assert_eq(LobbyInfo.parse("[1,2]"), {})
	var many: Array = []
	for i: int in 20:
		many.append({"n": "x".repeat(200), "c": -3, "o": ["not_a_hat", 5], "l": true})
	var info: Dictionary = LobbyInfo.parse(JSON.stringify({"mode": "evil", "mg": 1e9, "beans": many + ["junk"]}))
	assert_eq(info["mode"], MatchMode.CASINO)
	assert_eq(info["minigames"], 99)
	assert_eq((info["beans"] as Array).size(), Protocol.MAX_PLAYERS)
	var b: Dictionary = info["beans"][0]
	assert_eq((b["name"] as String).length(), LobbyInfo.NAME_MAX)
	assert_between(int(b["color"]), 0, Palette.PLAYER_COLORS.size() - 1)
	assert_eq(String((b["outfit"] as PackedStringArray)[0]), "", "unknown items are dropped")


func test_settings_text() -> void:
	assert_eq(LobbyInfo.settings_text({}), "")
	var t: String = LobbyInfo.settings_text({"mode": MatchMode.CASINO, "minigames": 5, "gamble_minutes": 3, "items": true, "picked": 16, "all": 16})
	assert_eq(t, "Casino · 5 minigames · 3 min gambling · items on")
	var m: String = LobbyInfo.settings_text({"mode": MatchMode.MINIGAMES, "minigames": 1, "items": false, "picked": 2, "all": 16})
	assert_false(m.contains("gambling"))
	assert_string_contains(m, "1 minigame ·")
	assert_string_contains(m, "2 of 16 games")
