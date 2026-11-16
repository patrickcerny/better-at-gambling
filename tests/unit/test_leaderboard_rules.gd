extends GutTest
## The leaderboard rules (`LeaderboardRules`) and the lifetime statistics in the profile
## (`PlayerProfile.lifetime`): what a client uploads after a ranked match, the plausibility checks,
## the number formatting, Steam's entries as list rows, and the save/load of the stats.

const PATH: String = "user://test_leaderboard_profile.cfg"


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _row(money: int, rank: int = 1, ranked: bool = true, profit: int = 0) -> Dictionary:
	return {"money": money, "rank": rank, "players": 4, "biggest_win": 600, "ranked": ranked, "minigames_won": 1,
		"xp": 100, "coins": 10, "stats": {"profit": profit, "hands": 10, "biggest_bet": 200, "jackpot_won": 50}}


func test_scores_after_a_ranked_win() -> void:
	var p := PlayerProfile.new()
	var row: Dictionary = _row(4200, 1, true, 3200)
	row["practice"] = false
	p.apply_match("m1", row)
	var s: Dictionary = LeaderboardRules.scores_for(row, p)
	assert_eq(int(s[LeaderboardRules.BEST_MATCH_MONEY]), 4200, "Patrick's board: money at the end of the match")
	assert_false(s.has(&"BIGGEST_WIN"), "Patrick 2026-11-16: no biggest single win board")
	assert_eq(int(s[LeaderboardRules.MATCHES_WON]), 1)
	assert_eq(int(s[LeaderboardRules.ONLINE_WINNINGS]), 3200)


## Patrick 2026-11-16 "why am i not on the leaderboard": his ranked match was in the profile but
## never uploaded (developer mode on that run). The profile's bests go up again on every start.
func test_profile_bests_upload_what_the_profile_holds() -> void:
	var p := PlayerProfile.new()
	assert_true(LeaderboardRules.profile_scores(p).is_empty(), "nothing ranked yet")
	var practice: Dictionary = _row(2500, 1, false, 1500)
	practice["practice"] = true
	p.apply_match("a", practice)
	assert_true(LeaderboardRules.profile_scores(p).is_empty(), "Practice never counts")
	var row: Dictionary = _row(8224, 1, true, 7224)
	row["practice"] = false
	p.apply_match("b", row)
	var s: Dictionary = LeaderboardRules.profile_scores(p)
	assert_eq(int(s[LeaderboardRules.BEST_MATCH_MONEY]), 8224)
	assert_eq(int(s[LeaderboardRules.ONLINE_WINNINGS]), 7224)
	assert_eq(int(s[LeaderboardRules.MATCHES_WON]), 1)
	assert_eq(LeaderboardRules.BOARDS.size(), 3)


func test_unranked_or_absurd_rows_upload_nothing() -> void:
	var p := PlayerProfile.new()
	assert_true(LeaderboardRules.scores_for(_row(4200, 1, false), p).is_empty(), "the host didn't rank it")
	assert_true(LeaderboardRules.scores_for(_row(LeaderboardRules.MAX_MATCH_MONEY + 1), p).is_empty(), "too much money")
	assert_true(LeaderboardRules.scores_for(_row(-5), p).is_empty())
	var bad_rank: Dictionary = _row(3000, 9)
	assert_true(LeaderboardRules.scores_for(bad_rank, p).is_empty(), "9th of 4")
	assert_true(LeaderboardRules.scores_for({}, p).is_empty())


func test_ranked_needs_room_two_players_and_no_dev() -> void:
	var row: Dictionary = _row(3000)
	assert_true(LeaderboardRules.ranked(row, true, false))
	assert_false(LeaderboardRules.ranked(row, false, false), "Practice")
	assert_false(LeaderboardRules.ranked(row, true, true), "developer tools")
	row["players"] = 1
	row["rank"] = 1
	assert_false(LeaderboardRules.ranked(row, true, false), "alone in a lobby")


func test_formatting() -> void:
	assert_eq(LeaderboardRules.group(0), "0")
	assert_eq(LeaderboardRules.group(999), "999")
	assert_eq(LeaderboardRules.group(1000), "1,000")
	assert_eq(LeaderboardRules.group(1234567), "1,234,567")
	assert_eq(LeaderboardRules.group(-4500), "-4,500")
	assert_eq(LeaderboardRules.format_score(LeaderboardRules.BEST_MATCH_MONEY, 12345), "$12,345")
	assert_eq(LeaderboardRules.format_score(LeaderboardRules.MATCHES_WON, 12), "12")


func test_entry_rows_sorted_and_mine_marked() -> void:
	var rows: Array[Dictionary] = LeaderboardRules.entry_rows([
		{"steam_id": 7, "score": 900, "global_rank": 2},
		{"steam_id": 5, "score": 1500, "global_rank": 1},
		"junk",
	], 7)
	assert_eq(rows.size(), 2)
	assert_eq(int(rows[0]["steam_id"]), 5)
	assert_false(bool(rows[0]["me"]))
	assert_true(bool(rows[1]["me"]))


func test_lifetime_counts_practice_but_online_only_where_named() -> void:
	var p := PlayerProfile.new()
	var practice: Dictionary = _row(2500, 1, false, 1500)
	p.apply_match("a", practice)
	assert_eq(p.stat(&"winnings"), 1500)
	assert_eq(p.stat(&"hands"), 10)
	assert_eq(p.stat(&"podiums"), 1)
	assert_eq(p.stat(&"online_matches"), 0)
	assert_eq(p.stat(&"online_winnings"), 0, "Practice isn't online")
	assert_eq(p.stat(&"best_money"), 0)
	p.apply_match("b", _row(800, 4, true, -200))
	assert_eq(p.stat(&"losses"), 200)
	assert_eq(p.stat(&"online_matches"), 1)
	assert_eq(p.stat(&"best_money"), 800)
	assert_eq(p.stat(&"podiums"), 1, "4th is no podium")
	assert_eq(p.stat(&"biggest_bet"), 200, "the biggest, not a sum")


func test_lifetime_survives_save_and_clamps_a_damaged_file() -> void:
	var p := PlayerProfile.new()
	p.apply_match("a", _row(3000, 1, true, 2000))
	assert_eq(p.save(PATH), OK)
	var q := PlayerProfile.new()
	assert_eq(q.load_from(PATH), OK)
	for key: StringName in PlayerProfile.LIFETIME_KEYS:
		assert_eq(q.stat(key), p.stat(key), String(key))
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("lifetime", "hands", -40)
	cfg.set_value("lifetime", "winnings", "lots")
	cfg.save(PATH)
	q.load_from(PATH)
	assert_eq(q.stat(&"hands"), 0)
	assert_eq(q.stat(&"winnings"), 0)


func test_stat_lines_cover_the_profile() -> void:
	var p := PlayerProfile.new()
	p.apply_match("a", _row(3000, 1, true, 2000))
	var lines: Array[Array] = LeaderboardPanel.stat_lines(p)
	assert_gte(lines.size(), 15)
	var texts: Dictionary = {}
	for l: Array in lines:
		texts[l[0]] = l[1]
	assert_eq(texts["Matches played"], "1")
	assert_eq(texts["Total winnings"], "$2,000")
	assert_eq(texts["Best online match"], "$3,000")
	assert_eq(texts["Win rate"], "100%")


## Patrick 2026-11-16 "show current skin in leaderboard": the look rides in Steam's details.
func test_skin_survives_the_details_round_trip() -> void:
	var outfit := PackedStringArray()
	for kind: StringName in CosmeticDef.OUTFIT_KINDS:
		var pick: String = ""
		for d: CosmeticDef in CosmeticShop.default().items:
			if d.kind == kind:
				pick = String(d.id)
				break
		outfit.append(pick)
	var details: PackedInt32Array = LeaderboardRules.skin_details(5, outfit)
	assert_lte(details.size(), LeaderboardRules.DETAILS_MAX)
	var back: Dictionary = LeaderboardRules.skin_from_details(details)
	assert_eq(int(back["color"]), 5)
	assert_eq(back["outfit"], Cosmetics.sanitize_outfit(outfit))
	assert_true(LeaderboardRules.skin_from_details(PackedInt32Array()).is_empty(), "an old entry without a look")
	assert_true(LeaderboardRules.skin_from_details([99, 1, 2]).is_empty(), "unknown version")
	var rows: Array[Dictionary] = LeaderboardRules.entry_rows([{"steam_id": 3, "score": 10, "global_rank": 4, "details": details}], 0)
	assert_eq(int((rows[0]["skin"] as Dictionary)["color"]), 5)


## Patrick 2026-11-16: "warum ist hier 2 und 3 und keine 1": FRIENDS counts among the friends.
func test_friends_count_from_one() -> void:
	var rows: Array[Dictionary] = [{"rank": 2, "steam_id": 1, "score": 9, "me": false}, {"rank": 3, "steam_id": 2, "score": 5, "me": true}]
	var friends: Array[Dictionary] = LeaderboardRules.with_places(rows, LeaderboardRules.SCOPE_FRIENDS)
	assert_eq(int(friends[0]["place"]), 1)
	assert_eq(int(friends[1]["place"]), 2)
	assert_eq(int(friends[0]["rank"]), 2, "the global rank stays")
	var global: Array[Dictionary] = LeaderboardRules.with_places(rows, LeaderboardRules.SCOPE_GLOBAL)
	assert_eq(int(global[0]["place"]), 2)
