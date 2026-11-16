extends GutTest
## Global leaderboards (Patrick 2026-11-16): the match server decides per player whether a match
## may go on a leaderboard (`ranked`: online room, 2+ players, no developer tools, plausible
## numbers, `LeaderboardRules`) and sends the lifetime statistics with each row; the profile adds
## them up (`PlayerProfile.lifetime`).

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(3)
	fx.server.start_match()
	fx.run(3.1)
	fx.place_all()
	ProfileManager.reload()


func after_each() -> void:
	fx.server.free()
	ProfileManager.reload()


func _rows() -> Dictionary:
	var ended: Array[Dictionary] = fx.of_type(&"match_ended")
	assert_eq(ended.size(), 1)
	return ended[0].get("progress", {}) if not ended.is_empty() else {}


func test_practice_is_never_ranked() -> void:
	fx.server.run_to_end()
	for pid: int in fx.player_ids:
		assert_false(bool(_rows()[pid]["ranked"]), "no online room: no leaderboard")


func test_an_online_room_is_ranked_and_carries_stats() -> void:
	fx.server.room_mode = true
	var p1: int = fx.player_ids[0]
	fx.server.stats[p1]["hands"] = 7
	fx.server.stats[p1]["knockouts_dealt"] = 2
	fx.server.run_to_end()
	var rows: Dictionary = _rows()
	for pid: int in fx.player_ids:
		var row: Dictionary = rows[pid]
		assert_true(bool(row["ranked"]), "online, 3 players, nothing odd")
		assert_eq(int(row["stats"]["profit"]), int(row["money"]) - fx.server.balance.start_money)
	assert_eq(int(rows[p1]["stats"]["hands"]), 7)
	assert_eq(int(rows[p1]["stats"]["knockouts_dealt"]), 2)


func test_a_dev_tool_unranks_the_server() -> void:
	fx.server.room_mode = true
	fx.server.dev_give_money(fx.player_ids[0], 500)
	fx.server.run_to_end()
	for pid: int in fx.player_ids:
		assert_false(bool(_rows()[pid]["ranked"]), "dev money touched this server")


func test_implausible_money_is_not_ranked() -> void:
	fx.server.room_mode = true
	fx.server.economy.apply(fx.player_ids[0], LeaderboardRules.MAX_MATCH_MONEY * 2, &"test")
	fx.server.run_to_end()
	assert_false(bool(_rows()[fx.player_ids[0]]["ranked"]), "two million $ in one match is not believed")
	assert_true(bool(_rows()[fx.player_ids[1]]["ranked"]), "the others still count")


func test_the_profile_adds_up_lifetime_stats() -> void:
	fx.server.room_mode = true
	var me: int = fx.player_ids[1]
	fx.server.stats[me]["hands"] = 4
	fx.server.run_to_end()
	var ev: Dictionary = bytes_to_var(var_to_bytes(fx.of_type(&"match_ended")[0]))
	ProfileManager.apply_results(ev, me)
	var p: PlayerProfile = ProfileManager.profile
	var row: Dictionary = ev["progress"][me]
	assert_eq(p.stat(&"hands"), 4)
	assert_eq(p.stat(&"online_matches"), 1)
	assert_eq(p.stat(&"best_money"), int(row["money"]))
	var profit: int = int(row["stats"]["profit"])
	assert_eq(p.stat(&"winnings"), maxi(profit, 0))
	assert_eq(p.stat(&"losses"), maxi(-profit, 0))
	ProfileManager.apply_results(ev, me)
	assert_eq(p.stat(&"hands"), 4, "the same match id adds nothing twice")
