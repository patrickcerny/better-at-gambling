extends GutTest
## Steam achievement rules (`Achievements`): which moments earn which API names. Steam itself is
## off in the tests, so `SteamSvc.unlock_achievements` must quietly do nothing.


func _row(rank: int, practice: bool, players: int, extra: Dictionary = {}) -> Dictionary:
	var row: Dictionary = Progression.breakdown(ProgressionConfig.default(), rank, 0, 0, 5, practice, 0)
	row["players"] = players
	row["minigames_won"] = 0
	row["money"] = 1000
	row.merge(extra, true)
	return row


func test_every_rule_names_a_defined_achievement() -> void:
	var p := PlayerProfile.new()
	p.matches = 60
	p.wins = 20
	p.online_wins = 20
	p.xp = p.config.max_xp()
	p.sanitize()
	p.biggest_win = 99999
	p.owned.append(&"x")
	var all: Array[StringName] = Achievements.from_profile(p)
	all.append_array(Achievements.from_match(_row(1, false, 4, {"minigames_won": 3, "biggest_win": 9999, "money": 9999})))
	all.append_array(Achievements.from_match(_row(4, false, 4, {"money": 0})))
	for ev: Dictionary in [
		{"type": &"jackpot_won", "player": 1}, {"type": &"player_knocked_out", "attacker": 1, "target": 2},
		{"type": &"player_thrown_out", "target": 1}, {"type": &"banana_slip", "owner": 1, "victim": 2, "result": &"slipped"},
		{"type": &"item_used", "item": &"russian_roulette", "player": 1, "bang": false},
		{"type": &"rps_result", "replay": false, "winner": 1}, {"type": &"house_comp", "player": 1}]:
		var got: Array[StringName] = Achievements.from_event(ev, 1)
		assert_eq(got.size(), 1, str(ev))
		all.append_array(got)
	all.append(Achievements.BEAT_THE_DEV)  # earned through SteamSvc.check_beat_the_dev
	for id: StringName in all:
		assert_true(Achievements.DEFS.has(id), "%s is in DEFS" % id)
	for id: StringName in Achievements.DEFS:
		assert_true(id in all, "%s can be earned" % id)


func test_practice_and_solo_wins_do_not_count() -> void:
	assert_false(Achievements.counts_as_online_win(_row(1, true, 1)), "Practice")
	assert_false(Achievements.counts_as_online_win(_row(1, false, 1)), "alone in an online lobby")
	assert_true(Achievements.counts_as_online_win(_row(1, false, 2)))
	assert_false(Achievements.counts_as_online_win(_row(2, false, 4)))
	var practice: Array[StringName] = Achievements.from_match(_row(1, true, 1, {"money": 9999}))
	assert_eq(practice, [&"ACH_FIRST_MATCH"] as Array[StringName], "Practice only counts as a finished match")


func test_profile_counts_online_wins_only() -> void:
	var p := PlayerProfile.new()
	p.apply_match("a", _row(1, true, 1))
	p.apply_match("b", _row(1, false, 3))
	assert_eq(p.wins, 2)
	assert_eq(p.online_wins, 1)
	assert_true(&"ACH_FIRST_WIN" in Achievements.from_profile(p))
	assert_false(&"ACH_WINS_10" in Achievements.from_profile(p))


func test_events_for_someone_else_earn_nothing() -> void:
	assert_true(Achievements.from_event({"type": &"jackpot_won", "player": 2}, 1).is_empty())
	assert_true(Achievements.from_event({"type": &"banana_slip", "owner": 1, "victim": 2, "result": &"blocked"}, 1).is_empty(), "bodyguard blocked it")
	assert_true(Achievements.from_event({"type": &"item_used", "item": &"russian_roulette", "player": 1, "bang": true}, 1).is_empty(), "BANG is not surviving")
	assert_true(Achievements.from_event({"type": &"rps_result", "replay": true, "winner": 1}, 1).is_empty())
	assert_true(Achievements.from_event({"type": &"jackpot_won", "player": 1}, -1).is_empty(), "the server has no local player")


func test_without_steam_unlocking_does_nothing() -> void:
	assert_false(SteamSvc.is_available())
	assert_true(SteamSvc.unlock_achievements([&"ACH_FIRST_MATCH"] as Array[StringName]).is_empty())


func _standings(ranks: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pid: int in ranks:
		out.append({"player": pid, "rank": int(ranks[pid]), "steam_id": 7000 + pid})
	return out


func test_beat_the_dev_lists_the_players_behind() -> void:
	var st: Array[Dictionary] = _standings({1: 1, 2: 2, 3: 2, 4: 4})
	st.append({"player": 5, "rank": 5, "steam_id": 0})  # no Steam ID: skipped
	assert_eq(Achievements.steam_ids_beaten(st, 1, _row(1, false, 5)), [7002, 7003, 7004] as Array[int])
	assert_eq(Achievements.steam_ids_beaten(st, 2, _row(2, false, 5)), [7004] as Array[int], "a tie is not a win over the tied player")
	assert_eq(Achievements.steam_ids_beaten(st, 4, _row(4, false, 5)), [] as Array[int], "last beats nobody with a Steam ID")


func test_beat_the_dev_only_online() -> void:
	var st: Array[Dictionary] = _standings({1: 1, 2: 2})
	assert_eq(Achievements.steam_ids_beaten(st, 1, _row(1, true, 2)), [] as Array[int], "Practice")
	assert_eq(Achievements.steam_ids_beaten(st, 1, _row(1, false, 1)), [] as Array[int], "solo")
	assert_eq(Achievements.steam_ids_beaten(st, 9, _row(1, false, 2)), [] as Array[int], "not in the standings")


func test_standings_carry_the_steam_id_from_the_uid() -> void:
	assert_eq(MatchServer.steam_id_of_uid("steam:76561198000000001"), 76561198000000001)
	assert_eq(MatchServer.steam_id_of_uid("local:Bob"), 0)
	assert_eq(MatchServer.steam_id_of_uid("steam:abc"), 0)
	assert_eq(MatchServer.steam_id_of_uid("bridge:3"), 0)


func test_beat_the_dev_without_steam_does_nothing() -> void:
	SteamSvc.check_beat_the_dev([76561198000000001] as Array[int])
	assert_true(true, "no Steam in the tests: quietly nothing")
