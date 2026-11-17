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
## The local player's own entry on a board (`download_mine`): the row ({} = not on it) and the
## board's entry count.
signal mine_received(board: StringName, row: Dictionary, total: int)
## An upload ended: board id, the score, the new global rank (0 = unknown), whether it improved.
signal score_uploaded(board: StringName, score: int, rank: int, improved: bool)
## Someone's Steam name arrived (`name_of` asked for it).
signal name_ready(steam_id: int)

## A download job asking for the local player's own entry (not a list scope).
const SCOPE_MINE: int = -1

## Rows per download: the top of GLOBAL / FRIENDS, and how far AROUND ME looks up and down.
const TOP_ROWS: int = 50
const AROUND_ROWS: int = 10

var steam: Object = null
## Board id -> Steam handle (0 / missing = not found yet).
var handles: Dictionary[StringName, int] = {}
## Board ids waiting for a find (the first one is on its way when `_finding` is set).
var _find_queue: Array[StringName] = []
var _finding: StringName = &""
## Scores waiting for their upload: board id -> score.
var _pending_scores: Dictionary[StringName, int] = {}
## The look that goes up with the next uploads (`LeaderboardRules.skin_details`).
var _details: PackedInt32Array = PackedInt32Array()
## Downloads waiting their turn (Steam's answer carries only the handle, so one runs at a time):
## [{board, scope, upload}]. `upload`: a SCOPE_MINE job that uploads the pending score after.
var _downloads: Array[Dictionary] = []
## The download on its way ({} = none) and when it started (a lost answer stops blocking).
var _downloading: Dictionary = {}
var _download_started: int = 0
const DOWNLOAD_TIMEOUT_MS: int = 10000
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
	if steam.has_method(&"set_leaderboard_details_max"):
		steam.call("set_leaderboard_details_max", LeaderboardRules.DETAILS_MAX)
	for id: StringName in LeaderboardRules.ids():
		_find(id)


func available() -> bool:
	return steam != null


## Uploads the local player's scores (board id -> score), e.g. `LeaderboardRules.scores_for`,
## with `details` (the look, `LeaderboardRules.skin_details`). With a look, each upload first
## reads the player's own entry and writes max(old, new) with the new look ("force"), so the look
## stays current even when the score doesn't improve; without one Steam just keeps the best.
func submit(scores: Dictionary, details: PackedInt32Array = PackedInt32Array()) -> void:
	if steam == null:
		return
	if not details.is_empty():
		_details = details
	for key: Variant in scores:
		var id := StringName(str(key))
		var score: int = clampi(int(scores[key]), 0, LeaderboardRules.MAX_TOTAL)
		if LeaderboardRules.board(id).is_empty() or score <= 0:
			continue
		_pending_scores[id] = maxi(score, int(_pending_scores.get(id, 0)))
		if _details.is_empty():
			if int(handles.get(id, 0)) != 0:
				_upload(id, 0)
			else:
				_find(id)
		else:
			_queue_download({"board": id, "scope": SCOPE_MINE, "upload": true})


## Asks for a board's entries: `entries_received` (or `entries_failed`) answers.
func download(id: StringName, scope: int) -> void:
	if steam == null:
		entries_failed.emit(id, scope)
		return
	_queue_download({"board": id, "scope": scope, "upload": false})


## Asks for the local player's own entry on a board: `mine_received` answers.
func download_mine(id: StringName) -> void:
	if steam == null:
		return
	_queue_download({"board": id, "scope": SCOPE_MINE, "upload": false})


## Opens a player's Steam profile in the Steam overlay (Patrick 2026-11-16: "Steam link").
func open_profile(steam_id: int) -> void:
	if steam == null or steam_id == 0:
		return
	steam.call("activateGameOverlayToUser", "steamid", steam_id)


func _queue_download(job: Dictionary) -> void:
	for j: Dictionary in _downloads:
		if j["board"] == job["board"] and int(j["scope"]) == int(job["scope"]):
			j["upload"] = bool(j["upload"]) or bool(job["upload"])
			return
	_downloads.append(job)
	_next_download()


func _next_download() -> void:
	if not _downloading.is_empty() and Time.get_ticks_msec() - _download_started < DOWNLOAD_TIMEOUT_MS:
		return
	if not _downloading.is_empty() and bool(_downloading["upload"]):
		# Steam never answered the own-entry read: upload anyway, keeping the better score.
		var lost: StringName = StringName(_downloading["board"])
		var score: int = int(_pending_scores.get(lost, 0))
		_pending_scores.erase(lost)
		if score > 0 and int(handles.get(lost, 0)) != 0:
			steam.call("uploadLeaderboardScore", score, true, _details, int(handles[lost]))
	_downloading = {}
	for i: int in _downloads.size():
		var job: Dictionary = _downloads[i]
		var h: int = int(handles.get(StringName(job["board"]), 0))
		if h == 0:
			_find(StringName(job["board"]))
			continue
		_downloads.remove_at(i)
		_downloading = job
		_download_started = Time.get_ticks_msec()
		match int(job["scope"]):
			SCOPE_MINE:
				steam.call("downloadLeaderboardEntriesForUsers", [int(steam.call("getSteamID"))], h)
			LeaderboardRules.SCOPE_AROUND_ME:
				steam.call("downloadLeaderboardEntries", -AROUND_ROWS, AROUND_ROWS, LeaderboardRules.SCOPE_AROUND_ME, h)
			var sc:
				steam.call("downloadLeaderboardEntries", 1, TOP_ROWS, sc, h)
		return


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
		if _pending_scores.has(id) and _details.is_empty():
			_upload(id, 0)
	else:
		Log.warn(&"steam", "leaderboard %s not found or created" % id)
		var keep: Array[Dictionary] = []
		for d: Dictionary in _downloads:
			if StringName(d["board"]) != id:
				keep.append(d)
			elif int(d["scope"]) != SCOPE_MINE:
				entries_failed.emit(id, int(d["scope"]))
		_downloads = keep
	_next_find()
	_next_download()


## Uploads the pending score of board `id`: with a look, max(`current`, pending) forced (the
## look always updates), else Steam's keep-best.
func _upload(id: StringName, current: int) -> void:
	var score: int = int(_pending_scores.get(id, 0))
	_pending_scores.erase(id)
	if score <= 0 or int(handles.get(id, 0)) == 0:
		return
	if _details.is_empty():
		steam.call("uploadLeaderboardScore", score, true, PackedInt32Array(), int(handles[id]))
	else:
		steam.call("uploadLeaderboardScore", maxi(score, current), false, _details, int(handles[id]))


func _on_score_uploaded(success: bool = false, handle: int = 0, info: Variant = {}) -> void:
	var id: StringName = _board_of(handle)
	if not success or id == &"":
		Log.warn(&"steam", "leaderboard upload failed (%s)" % id)
		return
	var d: Dictionary = info if info is Dictionary else {}
	score_uploaded.emit(id, int(d.get("score", 0)), int(d.get("new_rank", 0)), bool(d.get("score_changed", false)))


func _on_scores_downloaded(_message: String = "", handle: int = 0, entries: Array = []) -> void:
	var job: Dictionary = _downloading
	_downloading = {}
	var id: StringName = _board_of(handle)
	if id == &"" or job.is_empty() or StringName(job["board"]) != id:
		_next_download()
		return
	var me: int = int(steam.call("getSteamID"))
	var total: int = int(steam.call("getLeaderboardEntryCount", handle))
	var rows: Array[Dictionary] = LeaderboardRules.entry_rows(entries, me)
	if int(job["scope"]) == SCOPE_MINE:
		var mine: Dictionary = rows[0] if not rows.is_empty() and bool(rows[0]["me"]) else {}
		if bool(job["upload"]):
			_upload(id, int(mine.get("score", 0)))
		else:
			mine_received.emit(id, mine, total)
	else:
		entries_received.emit(id, int(job["scope"]), rows, total)
	_next_download()


func _on_persona(steam_id: int = 0, _flags: int = 0) -> void:
	if steam_id in _asked_names:
		_asked_names.erase(steam_id)
		name_ready.emit(steam_id)


func _board_of(handle: int) -> StringName:
	for id: StringName in handles:
		if handles[id] == handle:
			return id
	return &""
