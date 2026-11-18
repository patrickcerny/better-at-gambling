class_name RoomHost
extends Node
## Dedicated-server room lifecycle (§4.0, §4.1 handshake, §2.12): admits peers after checking
## protocol/build and verifying their join token with the orchestrator, maps peers to players
## (recognising reconnecting identities), reports heartbeats, and shuts the room down once it has
## been empty for `empty_timeout` seconds. Lives under `Net` in SERVER mode only.
##
## Joining: new players are admitted in the lobby and in a running match (late join: they spawn
## in the entrance hall and play from the next minigame on); only the results screen turns new
## faces away (`room_in_progress`). Kicks: the party leader's `kick_player` makes the MatchServer
## call `kick_player` here, which sends the kicked client `REJECT {code: kicked}` ("You were kicked
## by the host") and drops it. There is no rejoin block: a kicked player may join again on their
## own right away (Patrick 2026-11-15).
##
## Host mode (`host_mode`, a party hosted on a player's PC, see `SteamParty`): there is no
## orchestrator. Every connection comes over loopback, from the host's own game or from its
## `HostBridge`, which stamps friends' hellos with the Steam ID Steam vouched for
## ("steam:<id>"), so the hello's uid is the identity; build/protocol checks and kicks apply as
## everywhere. The room closes once the host (`host_uid`) has been gone for
## `HOST_GONE_CLOSE` seconds (their game quit or crashed), or never showed up.

const HEARTBEAT_INTERVAL: float = 5.0
## Seconds a fresh room waits for its first player before the empty timeout applies.
const FIRST_JOIN_GRACE: float = 60.0
## Once someone has played here, an empty room closes after this many seconds (Patrick: "if a room
## is empty, just kill it"); a few seconds so a crash-and-rejoin still finds the room.
const LEFT_EMPTY_CLOSE: float = 5.0
## Host mode: seconds the host may be disconnected before their room closes (a crashed game).
const HOST_GONE_CLOSE: float = 10.0

var orchestrator: String = ""
var room_id: String = ""
var room_code: String = ""
var room_secret: String = ""
## Seconds without connected players before the room closes itself (0 = never; dev servers).
var empty_timeout: float = 120.0
## Host mode: a party hosted on a player's PC (no orchestrator; see the class notes).
var host_mode: bool = false
## Host mode: the host's identity; the room closes once they are gone ("" = not watched).
var host_uid: String = ""
var _host_away: float = 0.0

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


## Reads {orchestrator, room_id, room_code, room_secret, empty_timeout, host_mode, host_uid}.
func setup(opts: Dictionary) -> void:
	orchestrator = str(opts.get("orchestrator", ""))
	room_id = str(opts.get("room_id", ""))
	room_code = str(opts.get("room_code", ""))
	room_secret = str(opts.get("room_secret", ""))
	host_mode = bool(opts.get("host_mode", false))
	host_uid = str(opts.get("host_uid", ""))
	empty_timeout = float(opts.get("empty_timeout", 120.0 if orchestrator != "" or host_mode else 0.0))


func _ready() -> void:
	http = HttpJson.new()
	http.name = "Http"
	add_child(http)
	if orchestrator != "":
		_heartbeat()
	elif host_mode:
		Log.info(&"room", "host mode: a party on a player's PC (no orchestrator, host %s)" % host_uid)


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


## Host mode: the host's own game is connected.
func host_present() -> bool:
	if server == null or host_uid == "":
		return false
	return peer_of(server.player_by_uid(host_uid)) >= 0


func on_server_attached(p_server: MatchServer) -> void:
	server = p_server
	server.kick_handler = kick_player
	# Host mode: identities and Steam inventories are vouched for, so premium and developer pieces
	# are checked against them (`MatchServer.may_wear`).
	server.verify_cosmetics = host_mode
	var queued: Array[Dictionary] = _pending.duplicate()
	_pending.clear()
	for h: Dictionary in queued:
		on_hello(h["peer"], h["hello"])


## First message of every connection.
func on_hello(peer: int, hello: Variant) -> void:
	if typeof(hello) != TYPE_DICTIONARY or _players.has(peer) or _verifying.has(peer):
		return
	var h: Dictionary = (hello as Dictionary).duplicate()
	# The Steam-granted pieces can outgrow the wire guard's list size: checked on their own.
	var owned: Variant = h.get("steam_owned", [])
	h.erase("steam_owned")
	if not WireGuard.is_clean_dictionary(h) or not valid_owned_list(owned):
		return
	if host_mode:
		h["steam_owned"] = owned  # stamped by the host's bridge (friends) or the host's own game
	if Serializer.to_int(h.get("protocol", -1), -1) != Protocol.PROTOCOL_VERSION or str(h.get("build", "")) != Protocol.BUILD_ID:
		Log.info(&"room", "peer %d rejected: version %s/%s, server %d/%s" % [peer, h.get("protocol"), h.get("build"), Protocol.PROTOCOL_VERSION, Protocol.BUILD_ID])
		_reject(peer, &"version_mismatch")
		return
	if server == null:
		_pending.append({"peer": peer, "hello": h})
		return
	if orchestrator == "":
		# Host mode: the uid is the Steam ID (stamped by the host's bridge, see the class notes).
		# Dev server (--server without an orchestrator, never used online): the client's uid.
		var display: String = _clean_name(str(h.get("name", "Player")))
		var uid: String = str(h.get("uid", ""))
		_admit(peer, uid if uid != "" else ("local:%s" if host_mode else "dev:%s") % display, display, h)
		return
	_verifying[peer] = true
	var res: Dictionary = await http.post(orchestrator.path_join("v1/internal/verify"), {"room_id": room_id, "room_secret": room_secret, "join_token": str(h.get("join_token", ""))})
	if not _verifying.has(peer):
		return  # gone while the orchestrator checked the token: admitting it now would leave a ghost
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
		server.set_steam_owned(pid, owned_of(hello))
		server.player_reconnected(pid)
		Log.info(&"room", "%s rejoined as player %d (peer %d)" % [display_name, pid, peer])
	else:
		# The dev (Patrick only, his Steam ID vouched for by the host's bridge) gets in anywhere.
		# Host mode only: there the uid is the Steam ID the bridge vouched for. A dev server's uid is
		# whatever the client claimed, and an orchestrator's is a bare Steam ID (no dev tools there).
		var god: bool = host_mode and Serializer.to_bool(hello.get("god", false)) and MatchServer.may_be_god(uid)
		if server.phases.phase == Phase.Id.RESULTS and not god:
			_reject(peer, &"room_in_progress")
			return
		if server.occupied_slots() >= Protocol.MAX_PLAYERS and not god:
			_reject(peer, &"room_full")
			return
		pid = server.add_player(uid, display_name, Serializer.to_int(hello.get("color", -1), -1), hello.get("outfit", []), god, owned_of(hello))
		_players[peer] = pid
		Log.info(&"room", "%s joined as player %d (peer %d)" % [display_name, pid, peer])
	Net.forget_private(pid)
	Net.send_to(peer, Protocol.CHANNEL_EVENTS, true, Protocol.Msg.WELCOME, {
		"player": pid, "snapshot": server.get_snapshot(), "private": server.get_private_snapshot(pid),
		"server_time": Net.server_time(), "room_code": room_code,
	})
	_empty_for = 0.0
	_ever_joined = true


## The MatchServer kicked `player`: tell their client why and drop the connection.
func kick_player(player: int) -> void:
	var peer: int = peer_of(player)
	if peer < 0:
		return
	_players.erase(peer)
	Log.info(&"room", "player %d kicked (peer %d)" % [player, peer])
	_reject(peer, &"kicked")


## SERVER: the client finished loading the match: back to the normal in-match timeout.
func on_loaded(peer: int) -> void:
	if _players.has(peer) and Net.transport != null:
		Net.transport.set_peer_timeout(peer, ENetTransport.TIMEOUT_MS)


func _reject(peer: int, code: StringName, message: String = "") -> void:
	Net.send_to(peer, Protocol.CHANNEL_EVENTS, true, Protocol.Msg.REJECT, {"code": code, "message": message if message != "" else Protocol.REJECT_TEXT.get(code, "Refused by the server.")})
	# Give ENet a moment to deliver the reason before dropping the peer.
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if Net.transport != null:
			Net.transport.kick(peer))


func on_peer_disconnected(peer: int) -> void:
	_verifying.erase(peer)
	# A hello still waiting for the match scene must not be admitted once its peer is gone.
	_pending = _pending.filter(func(h: Dictionary) -> bool: return int(h["peer"]) != peer)
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
	if host_uid != "":
		_host_away = 0.0 if host_present() else _host_away + delta
		if _host_away >= (HOST_GONE_CLOSE if _ever_joined else FIRST_JOIN_GRACE):
			_close("the host left")
			return
	if orchestrator != "":
		_heartbeat_timer += delta
		if _heartbeat_timer >= HEARTBEAT_INTERVAL:
			_heartbeat_timer = 0.0
			_heartbeat()
	if empty_timeout > 0.0:
		_empty_for = _empty_for + delta if _players.is_empty() and _verifying.is_empty() else 0.0
		# Before anyone arrived, give the creator time to load in (at least a minute).
		if _empty_for >= (minf(empty_timeout, LEFT_EMPTY_CLOSE) if _ever_joined else maxf(empty_timeout, FIRST_JOIN_GRACE)):
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
	var res: Dictionary = await http.post(orchestrator.path_join("v1/internal/heartbeat"), {
		"room_id": room_id, "room_secret": room_secret, "phase": _phase_name(), "players": _players.size(), "player_uids": uids,
		"public": is_public(), "name": party_name(), "mode": String(server.lobby.settings.get("mode", MatchMode.CASINO)) if server != null else "casino",
	})
	if res["status"] == 404 and not _closing:
		Log.warn(&"room", "orchestrator no longer knows this room; shutting down")
		_quit(0)
	elif res["status"] != 200:
		Log.warn(&"room", "heartbeat failed (%d)" % res["status"])


## The leader's PUBLIC toggle: listed in the server browser (`GET /v1/rooms?public=1`).
func is_public() -> bool:
	return server != null and bool(server.lobby.settings.get("public", false))


## Name shown in the server browser: "<leader>'s party".
func party_name() -> String:
	if server == null or not server.state.players.has(server.lobby.leader()):
		return "Lobby %s" % room_code
	return "%s's lobby" % server.state.players[server.lobby.leader()].display_name


## Sends a heartbeat now (the PUBLIC toggle shows up in the browser without waiting 5 s).
func heartbeat_soon() -> void:
	if orchestrator != "" and not _closing:
		_heartbeat_timer = HEARTBEAT_INTERVAL


func _close(reason: String) -> void:
	_closing = true
	Log.info(&"room", "closing room %s: %s" % [room_code, reason])
	if Net.voice_relay != null:
		Log.info(&"voice", Net.voice_relay.summary())
	if orchestrator != "":
		await http.post(orchestrator.path_join("v1/internal/closing"), {"room_id": room_id, "room_secret": room_secret, "reason": reason})
	_quit(0)


func _quit(code: int) -> void:
	_closing = true
	if Net.transport != null:
		Net.transport.close()
	get_tree().quit(code)


## Most Steam-granted pieces a hello may list (far above the shop's premium pieces).
const MAX_OWNED: int = 512


## True if `v` is a list of at most `MAX_OWNED` short shop ids.
static func valid_owned_list(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() > MAX_OWNED:
		return false
	for id: Variant in v:
		if not typeof(id) in [TYPE_STRING, TYPE_STRING_NAME] or str(id).length() > Intents.NAME_MAX:
			return false
	return true


## The Steam-granted pieces of an admitted hello (only host mode keeps them, see `on_hello`).
static func owned_of(hello: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for id: Variant in hello.get("steam_owned", []):
		out.append(str(id))
	return out


static func _clean_name(raw: String) -> String:
	# Control and invisible format characters out (security audit 2026-11-18): right-to-left
	# overrides and zero-width marks could make a name look like someone else's.
	var kept: String = ""
	for ch: String in raw:
		var c: int = ch.unicode_at(0)
		if c < 0x20 or (c >= 0x7F and c <= 0x9F) or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2060 and c <= 0x206F) or c == 0xFEFF or c == 0xAD:
			kept += " " if c == 0x0A or c == 0x09 else ""
			continue
		kept += ch
	var s: String = kept.strip_edges()
	while s.contains("  "):
		s = s.replace("  ", " ")
	if s.length() > 24:
		s = s.substr(0, 24)
	return s if s != "" else "Player"
