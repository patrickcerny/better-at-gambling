extends GutTest
## `SteamLeaderboards` against a fake Steam: finds, the one-at-a-time download queue, and uploads
## that carry the player's look (Patrick 2026-11-16: "why am i not on the leaderboard", "show
## current skin in leaderboard"): own entry first, then max(old, new) forced with the new look.


class LbFakeSteam:
	extends Object
	signal leaderboard_find_result(leaderboard_handle: int, found: int)
	signal leaderboard_scores_downloaded(message: String, leaderboard_handle: int, leaderboard_entries: Array)
	signal leaderboard_score_uploaded(success: bool, this_handle: int, this_score: Dictionary)
	signal persona_state_change(steam_id: int, flags: int)

	var calls: Array[Array] = []
	var names: Dictionary[int, String] = {}

	func findOrCreateLeaderboard(board: String, _sort: int, _display: int) -> void:
		calls.append(["find", board])

	func getLeaderboardName(handle: int) -> String:
		return names.get(handle, "")

	func downloadLeaderboardEntries(a: int, b: int, scope: int, handle: int) -> void:
		calls.append(["download", scope, handle, a, b])

	func downloadLeaderboardEntriesForUsers(users: Array, handle: int) -> void:
		calls.append(["mine", handle, users])

	func uploadLeaderboardScore(score: int, keep_best: bool, details: PackedInt32Array, handle: int) -> void:
		calls.append(["upload", score, keep_best, details, handle])

	func getSteamID() -> int:
		return 42

	func getLeaderboardEntryCount(_handle: int) -> int:
		return 7

	func activateGameOverlayToUser(kind: String, steam_id: int) -> void:
		calls.append(["overlay", kind, steam_id])


var steam: LbFakeSteam
var boards: SteamLeaderboards


func before_each() -> void:
	steam = LbFakeSteam.new()
	boards = SteamLeaderboards.new(steam)
	# Answer the finds in order: handle 100 + index.
	for i: int in LeaderboardRules.BOARDS.size():
		var id: String = String(LeaderboardRules.BOARDS[i]["id"])
		steam.names[100 + i] = id
		steam.leaderboard_find_result.emit(100 + i, 1)
	steam.calls.clear()


func after_each() -> void:
	steam.free()


func _of(kind: String) -> Array[Array]:
	var out: Array[Array] = []
	for c: Array in steam.calls:
		if c[0] == kind:
			out.append(c)
	return out


func test_upload_with_a_look_keeps_the_higher_score_and_sends_the_look() -> void:
	var look: PackedInt32Array = PackedInt32Array([LeaderboardRules.SKIN_VERSION, 3, 0, 0])
	boards.submit({LeaderboardRules.BEST_MATCH_MONEY: 5000}, look)
	assert_eq(_of("mine").size(), 1, "own entry first")
	assert_eq(_of("upload").size(), 0)
	steam.leaderboard_scores_downloaded.emit("", 100, [{"steam_id": 42, "score": 8224, "global_rank": 3}])
	var up: Array[Array] = _of("upload")
	assert_eq(up.size(), 1)
	assert_eq(int(up[0][1]), 8224, "never lower than what's on the board")
	assert_false(bool(up[0][2]), "forced, so the look updates")
	assert_eq(up[0][3], look)


func test_not_on_the_board_yet_uploads_the_new_score() -> void:
	boards.submit({LeaderboardRules.ONLINE_WINNINGS: 7224}, PackedInt32Array([LeaderboardRules.SKIN_VERSION, 0]))
	steam.leaderboard_scores_downloaded.emit("", 102, [])
	assert_eq(int(_of("upload")[0][1]), 7224)


func test_downloads_run_one_at_a_time_and_answer_the_right_scope() -> void:
	var got: Array = []
	boards.entries_received.connect(func(id: StringName, scope: int, rows: Array[Dictionary], _t: int) -> void: got.append([id, scope, rows.size()]))
	var mine: Array = []
	boards.mine_received.connect(func(id: StringName, row: Dictionary, total: int) -> void: mine.append([id, row, total]))
	boards.download(LeaderboardRules.BEST_MATCH_MONEY, LeaderboardRules.SCOPE_FRIENDS)
	boards.download_mine(LeaderboardRules.BEST_MATCH_MONEY)
	assert_eq(steam.calls.size(), 1, "the second waits")
	steam.leaderboard_scores_downloaded.emit("", 100, [{"steam_id": 9, "score": 10, "global_rank": 2}])
	assert_eq(got, [[LeaderboardRules.BEST_MATCH_MONEY, LeaderboardRules.SCOPE_FRIENDS, 1]])
	assert_eq(_of("mine").size(), 1, "then the next one goes")
	steam.leaderboard_scores_downloaded.emit("", 100, [{"steam_id": 42, "score": 50, "global_rank": 12}])
	assert_eq(mine.size(), 1)
	assert_eq(int((mine[0][1] as Dictionary)["rank"]), 12)


func test_open_profile_uses_the_overlay() -> void:
	boards.open_profile(76561198325616486)
	assert_eq(_of("overlay"), [["overlay", "steamid", 76561198325616486]])
