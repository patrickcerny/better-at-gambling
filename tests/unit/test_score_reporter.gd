extends GutTest
## Server-checked leaderboards (2026-11-18): what each player's game sends to the leaderboard server
## when an online match ends (`ScoreReporter.report_body`), and that the game never uploads scores
## to Steam itself any more.

const A: int = 76561190000000001
const B: int = 76561190000000002


func _row(uid: String, rank: int, money: int, ranked: bool = true) -> Dictionary:
	return {"uid": uid, "rank": rank, "money": money, "players": 2, "ranked": ranked, "stats": {"profit": money - 1000}}


func _ended(rows: Dictionary) -> Dictionary:
	return {"type": &"match_ended", "match_id": "123-4", "progress": rows, "standings": []}


func test_a_ranked_match_becomes_one_report_with_every_player() -> void:
	var look := PackedInt32Array([1, 3, 55])
	var body: Dictionary = ScoreReporter.report_body(_ended({0: _row("steam:%d" % A, 1, 3200), 1: _row("steam:%d" % B, 2, 400)}), look)
	assert_eq(body["match"], "123-4")
	assert_eq(body["look"], [1, 3, 55])
	var rows: Array = body["rows"]
	assert_eq(rows.size(), 2)
	assert_eq(rows[0], {"steam_id": str(A), "rank": 1, "money": 3200, "profit": 2200, "players": 2, "ranked": true})
	assert_eq(rows[1]["steam_id"], str(B))


func test_nothing_is_sent_for_unranked_or_practice_matches() -> void:
	var look := PackedInt32Array()
	assert_eq(ScoreReporter.report_body(_ended({0: _row("steam:%d" % A, 1, 3200, false), 1: _row("steam:%d" % B, 2, 400, false)}), look), {})
	assert_eq(ScoreReporter.report_body(_ended({0: _row("steam:%d" % A, 1, 3200)}), look), {}, "alone")
	assert_eq(ScoreReporter.report_body(_ended({0: _row("dev:bob", 1, 3200), 1: _row("steam:%d" % B, 2, 400)}), look), {}, "no Steam ID")
	assert_eq(ScoreReporter.report_body({"progress": {}}, look), {})


func test_steam_ids_from_uids() -> void:
	assert_eq(ScoreReporter.steam_id_of("steam:%d" % A), A)
	assert_eq(ScoreReporter.steam_id_of("%d" % A), 0)
	assert_eq(ScoreReporter.steam_id_of("steam:abc"), 0)
	assert_eq(ScoreReporter.steam_id_of("steam:-5"), 0)


func test_the_match_server_names_each_row_s_player() -> void:
	var fx := ServerFixture.new(2)
	fx.server.room_mode = true
	var standings: Array[Dictionary] = []
	var rank: int = 1
	for id: int in fx.server.state.players:
		fx.server.state.players[id].uid = "steam:%d" % (A + id)
		standings.append({"player": id, "rank": rank})
		rank += 1
	var rows: Dictionary = fx.server.progress_rows(standings)
	for id: int in rows:
		assert_eq(rows[id]["uid"], "steam:%d" % (A + id))
	fx.server.free()


func test_the_game_no_longer_uploads_scores_itself() -> void:
	var src: String = FileAccess.get_file_as_string("res://services/steam_service.gd")
	assert_false(src.contains("boards.submit("), "only the leaderboard server writes scores")
