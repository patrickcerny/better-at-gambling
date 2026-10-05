class_name RoomHost
extends Node
## Dedicated-server room lifecycle (§4.0, §4.1 handshake, §2.12): admits peers after checking
## protocol/build and verifying their join token with the orchestrator, maps peers to players
## (recognising reconnecting identities), reports heartbeats, and shuts the room down once it has
## been empty for `empty_timeout` seconds. Lives under `Net` in SERVER mode only.

const HEARTBEAT_INTERVAL: float = 5.0
## Seconds a fresh room waits for its first player before the empty timeout applies.
const FIRST_JOIN_GRACE: float = 60.0

var orchestrator: String = ""
var room_id: String = ""
var room_code: String = ""
var room_secret: String = ""
## Seconds without connected players before the room closes itself (0 = never; dev servers).
var empty_timeout: float = 120.0

var server: MatchServer = null
var http: HttpJson

## peer → player id (welcomed peers only).
var _players: Dictionary[int, int] = {}
## Hellos that arrived before the match scene attached the server.
var _pending: Array[Dictionary] = []
## Peers whose hello is being verified.
var _verifying: Dictionary[int, bool] = {}
var _empty_for: float = 0.0
var _heartbeat_timer: float = 0.0
var _closing: bool = false
var _ever_joined: bool = false


## Reads {orchestrator, room_id, room_code, room_secret, empty_timeout}.
func setup(opts: Dictionary) -> void:
	orchestrator = str(opts.get("orchestrator", ""))
	room_id = str(opts.get("room_id", ""))
	room_code = str(opts.get("room_code", ""))
	room_secret = str(opts.get("room_secret", ""))
	empty_timeout = float(opts.get("empty_timeout", 120.0 if orchestrator != "" else 0.0))


func _ready() -> void:
	http = HttpJson.new()
	http.name = "Http"
	add_child(http)
	if orchestrator != "":
		_heartbeat()


## Welcomed peers (receive events and world packets).
func welcomed_peers() -> Array[int]:
	var out: Array[int] = []
	out.assign(_players.keys())
	return out


## Player id of a welcomed peer, or -1.
func player_of(peer: int) -> int:
	return _players.get(peer, -1)


## Peer of a player, or -1.
func peer_of(player: int) -> int:
	for peer: int in _players:
		if _players[peer] == player:
			return peer
	return -1


func on_server_attached(p_server: MatchServer) -> void:
	server = p_server
	var queued: Array[Dictionary] = _pending.duplicate()
	_pending.clear()
	for h: Dictionary in queued:
		on_hello(h["peer"], h["hello"])


## First message of every connection.
func on_hello(peer: int, hello: Variant) -> void:
	if typeof(hello) != TYPE_DICTIONARY or _players.has(peer) or _verifying.has(peer):
		return
	var h: Dictionary = hello
	if int(h.get("protocol", -1)) != Protocol.PROTOCOL_VERSION or str(h.get("build", "")) != Protocol.BUILD_ID:
		Log.info(&"room", "peer %d rejected: version %s/%s, server %d/%s" % [peer, h.get("protocol"), h.get("build"), Protocol.PROTOCOL_VERSION, Protocol.BUILD_ID])
		_reject(peer, &"version_mismatch")
		return
	if server == null:
		_pending.append({"peer": peer, "hello": h})
		return
	if orchestrator == "":
		# Dev server (--server without an orchestrator): trust the client's uid. Never used online.
		var display: String = _clean_name(str(h.get("name", "Player")))
		var uid: String = str(h.get("uid", ""))
		_admit(peer, uid if uid != "" else "dev:%s" % display, display, h)
		return
	_verifying[peer] = true
	var res: Dictionary = await http.post(orchestrator.path_join("v1/internal/verify"), {"room_id": room_id, "room_secret": room_secret, "join_token": str(h.get("join_token", ""))})
	_verifying.erase(peer)
	if res["status"] != 200:
		Log.info(&"room", "peer %d: join token refused (%d %s)" % [peer, res["status"], res["body"].get("error", "")])
		_reject(peer, &"bad_token")
		return
	var body: Dictionary = res["body"]
	_admit(peer, str(body.get("player_uid", "")), _clean_name(str(body.get("display_name", h.get("name", "Player")))), h)


func _admit(peer: int, uid: String, display_name: String, hello: Dictionary) -> void:
	var pid: int = server.player_by_uid(uid)
	if pid >= 0:
		var old_peer: int = peer_of(pid)
		if old_peer >= 0:
			_players.erase(old_peer)
			Net.transport.kick(old_peer)
		_players[peer] = pid
		server.player_reconnected(pid)
		Log.info(&"room", "%s rejoined as player %d (peer %d)" % [display_name, pid, peer])
	else:
		if server.phases.phase != Phase.Id.LOBBY:
			_reject(peer, &"room_in_progress")
			return
		if server.occupied_slots() >= Protocol.MAX_PLAYERS:
			_reject(peer, &"room_full")
			return
		pid = server.add_player(uid, display_name, false, int(hello.get("color", -1)), StringName(hello.get("hat", "none")))
		_players[peer] = pid
		Log.info(&"room", "%s joined as player %d (peer %d)" % [display_name, pid, peer])
	Net.forget_private(pid)
	Net.send_to(peer, Protocol.CHANNEL_EVENTS, true, Protocol.Msg.WELCOME, {
		"player": pid, "snapshot": server.get_snapshot(), "private": server.get_private_snapshot(pid),
		"server_time": Net.server_time(), "room_code": room_code,
	})
	_empty_for = 0.0
	_ever_joined = true


func _reject(peer: int, code: StringName) -> void:
	Net.send_to(peer, Protocol.CHANNEL_EVENTS, true, Protocol.Msg.REJECT, {"code": code, "message": Protocol.REJECT_TEXT.get(code, "Refused by the server.")})
	# Give ENet a moment to deliver the reason before dropping the peer.
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if Net.transport != null:
			Net.transport.kick(peer))


func on_peer_disconnected(peer: int) -> void:
	_verifying.erase(peer)
	if not _players.has(peer):
		return
	var pid: int = _players[peer]
	_players.erase(peer)
	Log.info(&"room", "player %d disconnected (peer %d)" % [pid, peer])
	if server != null:
		server.player_disconnected(pid)


func _process(delta: float) -> void:
	if _closing:
		return
	if orchestrator != "":
		_heartbeat_timer += delta
		if _heartbeat_timer >= HEARTBEAT_INTERVAL:
			_heartbeat_timer = 0.0
			_heartbeat()
	if empty_timeout > 0.0:
		_empty_for = _empty_for + delta if _players.is_empty() and _verifying.is_empty() else 0.0
		# Before anyone arrived, give the creator time to load in (at least a minute).
		if _empty_for >= (empty_timeout if _ever_joined else maxf(empty_timeout, FIRST_JOIN_GRACE)):
			_close("empty")


func _phase_name() -> String:
	if server == null:
		return "lobby"
	match server.phases.phase:
		Phase.Id.LOBBY:
			return "lobby"
		Phase.Id.RESULTS:
			return "results"
	return "match"


func _heartbeat() -> void:
	var uids: Array[String] = []
	if server != null:
		for peer: int in _players:
			uids.append(server.state.players[_players[peer]].uid)
	var res: Dictionary = await http.post(orchestrator.path_join("v1/internal/heartbeat"), {"room_id": room_id, "room_secret": room_secret, "phase": _phase_name(), "players": _players.size(), "player_uids": uids})
	if res["status"] == 404 and not _closing:
		Log.warn(&"room", "orchestrator no longer knows this room; shutting down")
		_quit(0)
	elif res["status"] != 200:
		Log.warn(&"room", "heartbeat failed (%d)" % res["status"])


func _close(reason: String) -> void:
	_closing = true
	Log.info(&"room", "closing room %s: %s" % [room_code, reason])
	if orchestrator != "":
		await http.post(orchestrator.path_join("v1/internal/closing"), {"room_id": room_id, "room_secret": room_secret, "reason": reason})
	_quit(0)


func _quit(code: int) -> void:
	_closing = true
	if Net.transport != null:
		Net.transport.close()
	get_tree().quit(code)


static func _clean_name(raw: String) -> String:
	var s: String = raw.strip_edges().replace("\n", " ")
	if s.length() > 24:
		s = s.substr(0, 24)
	return s if s != "" else "Player"
