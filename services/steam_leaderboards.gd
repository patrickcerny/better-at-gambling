class_name SteamLeaderboards
extends RefCounted
## The global leaderboards on Steam (`LeaderboardRules.BOARDS`), owned by `SteamSvc` as
## `SteamSvc.boards`. The game creates the boards itself (FindOrCreateLeaderboard: descending,
## numeric), so nothing has to be set up in Steamworks first. Steam answers one find at a time, so
## finds run in a queue; uploads and downloads wait for their board's handle.
##
## Uploads are always "keep best": Steam only changes the score when the new one is higher.
## Without Steam (`steam` null) every call is a no-op and the panel says leaderboards need Steam.

## A board's entries came back: board id, scope (`LeaderboardRules.SCOPE_*`), rows
## (`LeaderboardRules.entry_rows`), and Steam's total entry count of that board.
signal entries_received(board: StringName, scope: int, rows: Array[Dictionary], total: int)
## A download failed or Steam has no such board: board id, scope.
signal entries_failed(board: StringName, scope: int)
## An upload ended: board id, the score, the new global rank (0 = unknown), whether it improved.
signal score_uploaded(board: StringName, score: int, rank: int, improved: bool)
## Someone's Steam name arrived (`name_of` asked for it).
signal name_ready(steam_id: int)

## Rows per download: the top of GLOBAL / FRIENDS, and how far AROUND ME looks up and down.
const TOP_ROWS: int = 50
const AROUND_ROWS: int = 10

var steam: Object = null
## Board id -> Steam handle (0 / missing = not found yet).
var handles: Dictionary[StringName, int] = {}
## Board ids waiting for a find (the first one is on its way when `_finding` is set).
var _find_queue: Array[StringName] = []
var _finding: StringName = &""
## Scores waiting for their board's handle: board id -> score.
var _pending_scores: Dictionary[StringName, int] = {}
## Downloads waiting for their board's handle: [{board, scope}].
var _pending_downloads: Array[Dictionary] = []
## The last download asked per handle (Steam's answer carries only the handle): handle -> scope.
var _download_scope: Dictionary[int, int] = {}
## Steam IDs whose names were asked for.
var _asked_names: Array[int] = []


func _init(p_steam: Object = null) -> void:
	steam = p_steam
	if steam == null:
		return
	steam.connect(&"leaderboard_find_result", _on_find_result)
	steam.connect(&"leaderboard_scores_downloaded", _on_scores_downloaded)
	steam.connect(&"leaderboard_score_uploaded", _on_score_uploaded)
	steam.connect(&"persona_state_change", _on_persona)
	for id: StringName in LeaderboardRules.ids():
		_find(id)


func available() -> bool:
	return steam != null


## Uploads the local player's scores (board id -> score), e.g. `LeaderboardRules.scores_for`.
func submit(scores: Dictionary) -> void:
	if steam == null:
		return
	for key: Variant in scores:
		var id := StringName(str(key))
		var score: int = clampi(int(scores[key]), 0, LeaderboardRules.MAX_TOTAL)
		if LeaderboardRules.board(id).is_empty() or score <= 0:
			continue
		_pending_scores[id] = maxi(score, int(_pending_scores.get(id, 0)))
		if int(handles.get(id, 0)) != 0:
			_upload(id)
		else:
			_find(id)


## Asks for a board's entries: `entries_received` (or `entries_failed`) answers.
func download(id: StringName, scope: int) -> void:
	if steam == null:
		entries_failed.emit(id, scope)
		return
	var h: int = int(handles.get(id, 0))
	if h == 0:
		_pending_downloads.append({"board": id, "scope": scope})
		_find(id)
		return
	_download_scope[h] = scope
	match scope:
		LeaderboardRules.SCOPE_AROUND_ME:
			steam.call("downloadLeaderboardEntries", -AROUND_ROWS, AROUND_ROWS, scope, h)
		_:
			steam.call("downloadLeaderboardEntries", 1, TOP_ROWS, scope, h)


## A player's Steam name ("" while Steam is still fetching it: `name_ready` follows).
func name_of(steam_id: int) -> String:
	if steam == null or steam_id == 0:
		return ""
	var n: String = str(steam.call("getFriendPersonaName", steam_id))
	if n == "" or n == "[unknown]":
		if not steam_id in _asked_names:
			_asked_names.append(steam_id)
			steam.call("requestUserInformation", steam_id, true)
		return ""
	return n


func _find(id: StringName) -> void:
	if int(handles.get(id, 0)) != 0 or id == _finding or id in _find_queue:
		return
	_find_queue.append(id)
	_next_find()


func _next_find() -> void:
	if _finding != &"" or _find_queue.is_empty():
		return
	_finding = _find_queue.pop_front()
	steam.call("findOrCreateLeaderboard", String(_finding), LeaderboardRules.SORT_DESCENDING, LeaderboardRules.DISPLAY_NUMERIC)


func _on_find_result(handle: int = 0, found: int = 0) -> void:
	var id: StringName = _finding
	_finding = &""
	if handle != 0 and found != 0:
		# The answer carries no name; the board we asked for is the one on its way.
		var real: String = str(steam.call("getLeaderboardName", handle))
		if real != "":
			id = StringName(real)
		handles[id] = handle
		if _pending_scores.has(id):
			_upload(id)
	else:
		Log.warn(&"steam", "leaderboard %s not found or created" % id)
	var waiting: Array[Dictionary] = _pending_downloads.duplicate()
	_pending_downloads.clear()
	for d: Dictionary in waiting:
		if StringName(d["board"]) == id and int(handles.get(id, 0)) == 0:
			entries_failed.emit(id, int(d["scope"]))
		elif int(handles.get(StringName(d["board"]), 0)) != 0:
			download(StringName(d["board"]), int(d["scope"]))
		else:
			_pending_downloads.append(d)
	_next_find()


func _upload(id: StringName) -> void:
	var score: int = int(_pending_scores.get(id, 0))
	_pending_scores.erase(id)
	if score > 0:
		steam.call("uploadLeaderboardScore", score, true, PackedInt32Array(), int(handles[id]))


func _on_score_uploaded(success: bool = false, handle: int = 0, info: Variant = {}) -> void:
	var id: StringName = _board_of(handle)
	if not success or id == &"":
		Log.warn(&"steam", "leaderboard upload failed (%s)" % id)
		return
	var d: Dictionary = info if info is Dictionary else {}
	score_uploaded.emit(id, int(d.get("score", 0)), int(d.get("new_rank", 0)), bool(d.get("score_changed", false)))


func _on_scores_downloaded(_message: String = "", handle: int = 0, entries: Array = []) -> void:
	var id: StringName = _board_of(handle)
	if id == &"":
		return
	var scope: int = int(_download_scope.get(handle, LeaderboardRules.SCOPE_GLOBAL))
	var me: int = int(steam.call("getSteamID"))
	var total: int = int(steam.call("getLeaderboardEntryCount", handle))
	entries_received.emit(id, scope, LeaderboardRules.entry_rows(entries, me), total)


func _on_persona(steam_id: int = 0, _flags: int = 0) -> void:
	if steam_id in _asked_names:
		_asked_names.erase(steam_id)
		name_ready.emit(steam_id)


func _board_of(handle: int) -> StringName:
	for id: StringName in handles:
		if handles[id] == handle:
			return id
	return &""
