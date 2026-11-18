class_name ScoreReporter
extends Node
## Sends online match results to our leaderboard server (Patrick 2026-11-18: "mach das mit den 2").
## Every player still in a ranked online match sends the whole result (every player's rank, money
## and profit) when it ends, with a Steam Web API ticket that proves who sends it. The server counts
## a match only when two or more Steam accounts sent the same result and nobody sent another one,
## and only the server writes the Steam leaderboards (`services/orchestrator/orchestrator/scores.py`).
## So the game no longer uploads scores itself: a modified game can't put made-up numbers there.
##
## Owned by `SteamSvc` (`SteamSvc.scores`); a no-op without Steam.

## The leaderboard server (the room orchestrator on the VPS, deploy/README.md).
const API: String = "http://152.53.33.53:4300"
## The identity the server checks tickets for (orchestrator auth.STEAM_IDENTITY).
const IDENTITY: String = "better-at-gambling"
const TICKET_TIMEOUT_MS: int = 10000

var steam: Object = null
var http: HttpJson
## Web API tickets on their way: ticket handle -> hex ticket ("" = still waiting).
var _tickets: Dictionary[int, String] = {}


func _init(p_steam: Object = null) -> void:
	steam = p_steam


func _ready() -> void:
	http = HttpJson.new()
	http.name = "Http"
	add_child(http)
	if steam != null and steam.has_signal(&"get_ticket_for_web_api"):
		steam.connect(&"get_ticket_for_web_api", _on_ticket)


## The report body for the local player's copy of a `match_ended` event, or {} when the match
## doesn't go on the leaderboards (practice, not ranked by the host, a player without a Steam ID).
static func report_body(ev: Dictionary, look: PackedInt32Array) -> Dictionary:
	var progress: Dictionary = ev.get("progress", {})
	var match_id: String = str(ev.get("match_id", ""))
	if match_id == "" or progress.size() < 2:
		return {}
	var rows: Array = []
	for pid: Variant in progress:
		var row: Variant = progress[pid]
		if not row is Dictionary:
			return {}
		var r: Dictionary = row
		var sid: int = steam_id_of(str(r.get("uid", "")))
		if sid == 0 or not bool(r.get("ranked", false)):
			return {}
		rows.append({"steam_id": str(sid), "rank": int(r.get("rank", 0)), "money": int(r.get("money", 0)),
			"profit": int((r.get("stats", {}) as Dictionary).get("profit", 0)), "players": int(r.get("players", 0)), "ranked": true})
	return {"match": match_id.left(64), "rows": rows, "look": Array(look).slice(0, LeaderboardRules.DETAILS_MAX)}


## "steam:76561198..." -> 76561198..., 0 for any other uid (dev names, practice).
static func steam_id_of(uid: String) -> int:
	if not uid.begins_with("steam:"):
		return 0
	var digits: String = uid.substr(6)
	return int(digits) if digits.is_valid_int() and int(digits) > 0 else 0


## Sends the local player's report of an ended match (fire and forget; the server waits ~2 min
## for the others).
func report(ev: Dictionary, look: PackedInt32Array) -> void:
	var body: Dictionary = report_body(ev, look)
	if body.is_empty() or steam == null:
		return
	await _post("v1/matches/report", body)


## A new outfit or colour: the server re-sends the scores with it (only players already on a board).
func send_look(look: PackedInt32Array) -> void:
	if steam == null:
		return
	await _post("v1/leaderboards/look", {"look": Array(look).slice(0, LeaderboardRules.DETAILS_MAX)})


func _post(path: String, body: Dictionary) -> void:
	var ticket: String = await _web_ticket()
	if ticket == "":
		Log.warn(&"scores", "no Steam Web API ticket, %s not sent" % path)
		return
	body["ticket"] = ticket
	body["build"] = Protocol.BUILD_ID
	var res: Dictionary = await http.post(API.path_join(path), body)
	var status: int = int(res.get("status", 0))
	if status != 200:
		Log.warn(&"scores", "%s: %d %s" % [path, status, str((res.get("body", {}) as Dictionary).get("error", ""))])


## A fresh Web API ticket as hex ("" when Steam doesn't give one in time).
func _web_ticket() -> String:
	if not steam.has_method(&"getAuthTicketForWebApi"):
		return ""
	var handle: int = int(steam.call("getAuthTicketForWebApi", IDENTITY))
	if handle <= 0:
		return ""
	_tickets[handle] = ""
	var t0: int = Time.get_ticks_msec()
	while _tickets.get(handle, "") == "" and Time.get_ticks_msec() - t0 < TICKET_TIMEOUT_MS and is_inside_tree():
		await get_tree().process_frame
	var ticket: String = str(_tickets.get(handle, ""))
	_tickets.erase(handle)
	return "" if ticket == "-" else ticket


func _on_ticket(handle: int = 0, result: int = 0, _size: int = 0, buffer: Variant = PackedByteArray()) -> void:
	if not _tickets.has(handle):
		return
	if result != 1 or not buffer is PackedByteArray or (buffer as PackedByteArray).is_empty():
		_tickets[handle] = "-"  # stops the wait; "-" is no ticket
		return
	_tickets[handle] = (buffer as PackedByteArray).hex_encode()
