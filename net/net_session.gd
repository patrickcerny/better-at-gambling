extends Node
## `Net` autoload: the single door between the game and a server (§4.1). Presentation code only
## calls `send_intent`/`request_snapshot` and listens to `event_received`; it never knows whether
## the server is in-process (Practice), across ENet (online client) or this process itself
## (dedicated server).
##
## Modes:
## - LOCAL: in-process MatchServer (Practice/Tutorial, offline).
## - CLIENT: connected to a dedicated server over a NetTransport.
## - SERVER: this process is the dedicated room server; `RoomHost` admits players.

## Emitted for every server event, in sequence order.
signal event_received(event: Dictionary)
## Emitted once the server accepted us (CLIENT) or the session started (LOCAL).
signal connected
## Emitted when the connection drops, fails or is refused. `reason` is player-facing text.
signal disconnected(reason: String)
## CLIENT: a decoded 20 Hz world packet (see `WorldCodec`).
signal world_received(world: Dictionary)
## CLIENT: a fresh full snapshot arrived (after a gap or on request).
signal snapshot_received(snapshot: Dictionary)
## CLIENT: the server refused our movement and put us back.
signal position_forced(pos: Vector3, yaw: float)
## SERVER: an accepted movement report from a client's own avatar.
signal move_received(player: int, pos: Vector3, yaw: float, airborne: bool)
## CLIENT: a relayed voice frame (`VoicePacket` down packet) on the voice channel.
signal voice_received(data: PackedByteArray)

enum Mode { NONE, LOCAL, CLIENT, SERVER }

const PING_INTERVAL: float = 1.0
const STATUS_INTERVAL: float = 0.25
const WORLD_INTERVAL: float = 1.0 / Protocol.SERVER_TICK_HZ
const CONNECT_TIMEOUT: float = 10.0
## Most latency credited to a quiz answer (half a 500 ms round trip).
const MAX_HALF_RTT: float = 0.25
## Silence after which the UI shows "Connection lost — reconnecting…" (§2.12).
const SILENCE_WARNING: float = 3.0
## Events kept for late-joining views (a long match without snapshots just falls back to a resync).
const BACKLOG_MAX: int = 4000
## Validator-level refusals that produce no `intent_rejected` event on the server.
const SILENT_REJECTIONS: Array[StringName] = [&"wrong_phase", &"malformed", &"unknown_player"]

var mode: Mode = Mode.NONE
## This client's player id on the server (-1 when not connected).
var local_player_id: int = -1
## The in-process server in LOCAL and SERVER mode.
var local_server: MatchServer = null
var transport: NetTransport = null
var clock: NetClock = NetClock.new()
## SERVER: room lifecycle (handshake, orchestrator, empty shutdown).
var room_host: RoomHost = null
## SERVER: proximity voice relay (created on the first voice packet).
var voice_relay: VoiceRelay = null
## SERVER: returns the world dictionary to stream (set by the match scene).
var world_provider: Callable
## Last refusal/disconnect (code + player-facing text), for the menu's error panel.
var last_error_code: StringName = &""
var last_error: String = ""
## CLIENT: the room we're in ({room_id, room_code, host, port}); kept for "Rejoin".
var room: Dictionary = {}

var _snapshot: Dictionary = {}
var _private: Dictionary = {}
## CLIENT: events received since `_snapshot` was taken, so a view created later (the match scene
## loads after WELCOME) can catch up without a gap.
var _backlog: Array[Dictionary] = []
var _hello: Dictionary = {}
var _welcomed: bool = false
var _welcomed_at: float = 0.0
var _connect_deadline: float = 0.0
var _last_packet_at: float = 0.0
var _ping_timer: float = 0.0
var _status_timer: float = 0.0
var _world_timer: float = 0.0
var _world_tick: int = 0
var _station_hashes: Dictionary = {}
var _private_hashes: Dictionary[int, int] = {}
var _start_ticks: int = Time.get_ticks_usec()


## Orchestrator client (create/join parties by code).
var online: OnlineService


func _exit_tree() -> void:
	stop()


func _ready() -> void:
	online = OnlineService.new()
	online.name = "Online"
	add_child(online)


# --- Common API --------------------------------------------------------------------------------

## Starts an in-process session with `server` and joins it as `display_name`.
func start_local(server: MatchServer, display_name: String) -> int:
	stop()
	mode = Mode.LOCAL
	local_server = server
	server.event_emitted.connect(_on_local_event)
	local_player_id = server.add_player("local", display_name, false, -1, StringName(Settings.get_value("profile", "skin", "bean")))
	connected.emit()
	return local_player_id


## Leaves the current session (says goodbye to a server first).
func stop() -> void:
	if mode == Mode.CLIENT and transport != null and _welcomed:
		_send(NetTransport.SERVER_PEER, Protocol.CHANNEL_EVENTS, true, Protocol.Msg.BYE, {})
		transport.poll()
		transport.flush()
	if local_server != null and local_server.event_emitted.is_connected(_on_local_event):
		local_server.event_emitted.disconnect(_on_local_event)
	if local_server != null and local_server.event_emitted.is_connected(_on_server_event):
		local_server.event_emitted.disconnect(_on_server_event)
	if transport != null:
		transport.close()
	transport = null
	if room_host != null:
		room_host.queue_free()
		room_host = null
	local_server = null
	voice_relay = null
	local_player_id = -1
	_welcomed = false
	_snapshot = {}
	_private = {}
	_backlog.clear()
	clock = NetClock.new()
	mode = Mode.NONE


## Sends an intent. LOCAL returns the server's {ok, error}; CLIENT returns {ok: true, pending: true}
## (refusals come back as `intent_rejected` events).
func send_intent(intent: Dictionary) -> Dictionary:
	match mode:
		Mode.LOCAL:
			return local_server.submit_intent(local_player_id, intent)
		Mode.CLIENT:
			if not _welcomed:
				return StationLogicBase.fail(&"not_connected")
			if intent.get("type") == &"move":
				_send(NetTransport.SERVER_PEER, Protocol.CHANNEL_PHYSICS, false, Protocol.Msg.MOVE, intent)
			else:
				_send(NetTransport.SERVER_PEER, Protocol.CHANNEL_EVENTS, true, Protocol.Msg.INTENT, intent)
			return {"ok": true, "error": &"", "pending": true}
	return StationLogicBase.fail(&"not_connected")


## CLIENT: sends one captured voice frame (`VoicePacket` up packet) to the server for relaying.
## No-op otherwise (Practice has nobody to talk to).
func send_voice(packet: PackedByteArray) -> void:
	if mode == Mode.CLIENT and _welcomed and transport != null:
		transport.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_VOICE, false, packet)


## Latest full snapshot (immediate in LOCAL mode; the cached, status-refreshed copy in CLIENT mode).
func request_snapshot() -> Dictionary:
	match mode:
		Mode.LOCAL, Mode.SERVER:
			return local_server.get_snapshot() if local_server != null else {}
		Mode.CLIENT:
			return _snapshot
	return {}


## CLIENT: events that arrived after the cached snapshot (replay them on top of it).
func events_since_snapshot() -> Array[Dictionary]:
	return _backlog if mode == Mode.CLIENT else [] as Array[Dictionary]


## CLIENT: asks the server for a fresh snapshot (sequence gap); `snapshot_received` follows.
func request_fresh_snapshot() -> void:
	if mode == Mode.CLIENT and _welcomed:
		_send(NetTransport.SERVER_PEER, Protocol.CHANNEL_STATE, true, Protocol.Msg.SNAPSHOT_REQ, {})


## Private data for this player (own station secrets).
func request_private_snapshot() -> Dictionary:
	match mode:
		Mode.LOCAL:
			return local_server.get_private_snapshot(local_player_id)
		Mode.CLIENT:
			return _private
	return {}


## True while this process runs as the dedicated server.
func is_server() -> bool:
	return mode == Mode.SERVER


## True while connected to a remote server.
func is_client() -> bool:
	return mode == Mode.CLIENT


## True once a CLIENT session was accepted.
func is_welcomed() -> bool:
	return _welcomed


## Seconds since the last packet from the server (CLIENT).
func silence() -> float:
	return _now() - _last_packet_at if mode == Mode.CLIENT and _welcomed else 0.0


## Server clock in seconds: authoritative on the server, estimated on clients.
func server_time() -> float:
	if mode == Mode.CLIENT:
		return clock.server_now(_now())
	return _now()


## CLIENT: average download since WELCOME in bytes/s (payload bytes, before ENet compression).
func download_rate() -> float:
	if mode != Mode.CLIENT or transport == null or not _welcomed:
		return 0.0
	return transport.bytes_in / maxf(_now() - _welcomed_at, 0.001)


## Round-trip time in ms (CLIENT).
func ping_ms() -> int:
	return clock.ping_ms()


# --- Client ------------------------------------------------------------------------------------

## Connects to a dedicated server. `hello` carries {join_token, name, uid, color, skin};
## `opts` may add {latency_ms, loss} (tests). Returns OK if the attempt started.
func join_server(host: String, port: int, hello: Dictionary, opts: Dictionary = {}) -> Error:
	stop()
	transport = TransportFactory.client(host, port, opts)
	if transport == null:
		_fail(&"timeout", "Could not open a connection to %s:%d." % [host, port])
		return ERR_CANT_CONNECT
	mode = Mode.CLIENT
	room["host"] = host
	room["port"] = port
	_hello = hello.duplicate()
	_hello["protocol"] = Protocol.PROTOCOL_VERSION
	if not _hello.has("build"):
		_hello["build"] = Protocol.BUILD_ID
	_connect_deadline = _now() + CONNECT_TIMEOUT
	transport.peer_connected.connect(_on_client_peer_connected)
	transport.peer_disconnected.connect(func(_id: int) -> void: _on_client_lost("Connection to the server was lost."))
	transport.connection_failed.connect(func() -> void: _on_client_lost("Could not reach the server."))
	Log.info(&"net", "connecting to %s:%d" % [host, port])
	return OK


func _on_client_peer_connected(_id: int) -> void:
	_last_packet_at = _now()
	_send(NetTransport.SERVER_PEER, Protocol.CHANNEL_EVENTS, true, Protocol.Msg.HELLO, _hello)


func _on_client_lost(reason: String) -> void:
	if mode != Mode.CLIENT:
		return
	var code: StringName = &"connection_lost" if _welcomed else &"timeout"
	_fail(code, reason)


func _fail(code: StringName, reason: String) -> void:
	last_error_code = code
	last_error = reason
	Log.warn(&"net", "disconnected (%s): %s" % [code, reason])
	stop()
	disconnected.emit(reason)


func _client_packet(type: int, payload: Variant) -> void:
	match type:
		Protocol.Msg.WELCOME:
			var w: Dictionary = payload
			local_player_id = int(w["player"])
			_snapshot = w.get("snapshot", {})
			_backlog.clear()
			_private = w.get("private", {})
			room["room_code"] = str(w.get("room_code", ""))
			_welcomed = true
			_welcomed_at = _now()
			_ping_timer = PING_INTERVAL  # ping right away
			Log.info(&"net", "welcomed as player %d" % local_player_id)
			connected.emit()
		Protocol.Msg.REJECT:
			var r: Dictionary = payload
			var code: StringName = StringName(r.get("code", "server_error"))
			_fail(code, str(r.get("message", Protocol.REJECT_TEXT.get(code, "Refused by the server."))))
		Protocol.Msg.EVENT:
			if _backlog.size() < BACKLOG_MAX:
				_backlog.append(payload)
			# Keep the cached snapshot's Gift Shop current (STATUS doesn't carry it).
			if (payload as Dictionary).get("type", &"") == &"shop_restocked":
				_snapshot["shop"] = {"offers": (payload as Dictionary)["offers"]}
			event_received.emit(payload)
		Protocol.Msg.WORLD:
			var w: Dictionary = WorldCodec.decode(payload)
			if not w.is_empty():
				world_received.emit(w)
		Protocol.Msg.STATUS:
			var st: Dictionary = payload
			for k: String in ["time_left", "next_minigame_in", "casino_time", "jackpot"]:
				if st.has(k):
					_snapshot[k] = st[k]
			if st.has("stations"):
				var stations: Dictionary = _snapshot.get("stations", {})
				stations.merge(st["stations"], true)
				_snapshot["stations"] = stations
		Protocol.Msg.SNAPSHOT:
			_snapshot = payload
			_backlog.clear()
			snapshot_received.emit(_snapshot)
		Protocol.Msg.PRIVATE:
			_private = payload
		Protocol.Msg.PONG:
			var p: Dictionary = payload
			clock.add_sample(float(p["t"]), float(p["server_time"]), _now())
		Protocol.Msg.FORCE_POSITION:
			var f: Dictionary = payload
			position_forced.emit(Serializer.to_vec3(f["pos"]), float(f.get("yaw", 0.0)))
		Protocol.Msg.INTENT_RESULT:
			var r: Dictionary = payload
			event_received.emit({"type": &"intent_rejected", "player": local_player_id, "intent": r.get("type"), "error": StringName(r.get("error", ""))})


# --- Server ------------------------------------------------------------------------------------

## Starts listening as the dedicated room server. `opts`: {orchestrator, room_id, room_code,
## room_secret, empty_timeout, latency_ms, loss}. Returns OK or an error.
func start_server(port: int, opts: Dictionary = {}) -> Error:
	stop()
	transport = TransportFactory.server(port, Protocol.MAX_PLAYERS + 4, opts)
	if transport == null:
		Log.error(&"net", "could not listen on UDP port %d" % port)
		return ERR_CANT_CREATE
	mode = Mode.SERVER
	room_host = RoomHost.new()
	room_host.name = "RoomHost"
	room_host.setup(opts)
	add_child(room_host)
	transport.peer_connected.connect(func(id: int) -> void: Log.info(&"net", "peer %d connected" % id))
	transport.peer_disconnected.connect(room_host.on_peer_disconnected)
	Log.info(&"net", "server listening on UDP %d (room %s)" % [port, opts.get("room_code", "-")])
	return OK


## SERVER: the match scene created the authoritative MatchServer.
func attach_server(server: MatchServer) -> void:
	local_server = server
	server.event_emitted.connect(_on_server_event)
	server.half_rtt_provider = half_rtt_of
	room_host.on_server_attached(server)


## SERVER: half the round trip to a player's client in seconds (quiz answer timing, §2.9).
## Capped so a laggy connection can't buy extra answer time.
func half_rtt_of(player: int) -> float:
	if transport == null or room_host == null:
		return 0.0
	var peer: int = room_host.peer_of(player)
	return clampf(transport.peer_rtt_ms(peer) / 2000.0, 0.0, MAX_HALF_RTT) if peer > 0 else 0.0


## SERVER: sends one message to a peer.
func send_to(peer: int, channel: int, reliable: bool, type: int, payload: Variant) -> void:
	_send(peer, channel, reliable, type, payload)


func _on_server_event(ev: Dictionary) -> void:
	event_received.emit(ev)  # the server's own match scene reacts too (ragdolls, guards, piles)
	var bytes: PackedByteArray = Wire.encode(Protocol.Msg.EVENT, ev)
	for peer: int in room_host.welcomed_peers():
		transport.send(peer, Protocol.CHANNEL_EVENTS, true, bytes)


func _server_packet(peer: int, type: int, payload: Variant) -> void:
	if type == Protocol.Msg.HELLO:
		room_host.on_hello(peer, payload)
		return
	var pid: int = room_host.player_of(peer)
	if pid < 0 or local_server == null:
		return
	match type:
		Protocol.Msg.INTENT:
			var intent: Dictionary = payload
			if intent.get("type") == &"move":
				return
			var res: Dictionary = local_server.submit_intent(pid, intent)
			if not res["ok"] and StringName(res["error"]) in SILENT_REJECTIONS:
				_send(peer, Protocol.CHANNEL_EVENTS, true, Protocol.Msg.INTENT_RESULT, {"type": intent.get("type", &""), "error": res["error"]})
		Protocol.Msg.MOVE:
			var m: Dictionary = payload
			if Intents.validate(m).size() > 0 or not local_server.can_move(pid):
				return
			var pos: Vector3 = Serializer.to_vec3(m["pos"])
			var yaw: float = float(m["yaw"])
			if local_server.apply_move(pid, pos, yaw, bool(m.get("airborne", false))):
				move_received.emit(pid, pos, yaw, bool(m.get("airborne", false)))
			else:
				var good: Vector3 = local_server.sanity.last_good(pid)
				Log.warn(&"net", "player %d moved implausibly to %s, snapping back to %s (phase %s, t=%.2f)" % [pid, pos, good, Phase.name_of(local_server.phases.phase), local_server.uptime()])
				_send(peer, Protocol.CHANNEL_STATE, true, Protocol.Msg.FORCE_POSITION, {"pos": Serializer.vec3(good), "yaw": yaw})
		Protocol.Msg.SNAPSHOT_REQ:
			_send(peer, Protocol.CHANNEL_EVENTS, true, Protocol.Msg.SNAPSHOT, local_server.get_snapshot())
		Protocol.Msg.PING:
			_send(peer, Protocol.CHANNEL_STATE, true, Protocol.Msg.PONG, {"t": payload.get("t", 0.0), "server_time": server_time()})
		Protocol.Msg.BYE:
			# Leaving on purpose: free the slot (and hand over leadership) now, not after ENet notices.
			if room_host != null:
				room_host.on_peer_disconnected(peer)
			transport.kick(peer)


func _server_tick(delta: float) -> void:
	if local_server == null:
		return
	var peers: Array[int] = room_host.welcomed_peers()
	_world_timer += delta
	if _world_timer >= WORLD_INTERVAL:
		_world_timer = fmod(_world_timer, WORLD_INTERVAL)
		if world_provider.is_valid() and not peers.is_empty():
			_world_tick += 1
			var w: Dictionary = world_provider.call()
			w["t"] = server_time()
			w["tick"] = _world_tick
			var bytes: PackedByteArray = Wire.encode(Protocol.Msg.WORLD, WorldCodec.encode(w))
			for peer: int in peers:
				transport.send(peer, Protocol.CHANNEL_PHYSICS, false, bytes)
	_status_timer += delta
	if _status_timer >= STATUS_INTERVAL:
		_status_timer = 0.0
		_send_status(peers)


func _send_status(peers: Array[int]) -> void:
	var snap: Dictionary = local_server.get_snapshot()
	var changed: Dictionary = {}
	var stations: Dictionary = snap.get("stations", {})
	for sid: Variant in stations:
		var h: int = Serializer.state_hash(stations[sid])
		if _station_hashes.get(sid, 0) != h:
			_station_hashes[sid] = h
			changed[sid] = stations[sid]
	var status: Dictionary = {"time_left": snap["time_left"], "next_minigame_in": snap["next_minigame_in"], "casino_time": snap["casino_time"], "jackpot": snap["jackpot"]}
	if not changed.is_empty():
		status["stations"] = changed
	var bytes: PackedByteArray = Wire.encode(Protocol.Msg.STATUS, status)
	for peer: int in peers:
		transport.send(peer, Protocol.CHANNEL_STATE, true, bytes)
		var pid: int = room_host.player_of(peer)
		var priv: Dictionary = local_server.get_private_snapshot(pid)
		var ph: int = Serializer.state_hash(priv)
		if _private_hashes.get(pid, 0) != ph:
			_private_hashes[pid] = ph
			_send(peer, Protocol.CHANNEL_STATE, true, Protocol.Msg.PRIVATE, priv)


## SERVER: a newly welcomed peer has the full snapshot already; make sure it also gets its private data.
func forget_private(player: int) -> void:
	_private_hashes.erase(player)


# --- Loop --------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if transport == null:
		return
	for p: Dictionary in transport.poll():
		if int(p["channel"]) == Protocol.CHANNEL_VOICE:
			_voice_packet(int(p["peer"]), p["data"])
			continue
		var msg: Array = Wire.decode(p["data"])
		if msg.is_empty():
			continue
		if mode == Mode.CLIENT:
			_last_packet_at = _now()
			_client_packet(int(msg[0]), msg[1])
		elif mode == Mode.SERVER:
			_server_packet(int(p["peer"]), int(msg[0]), msg[1])
		if transport == null:
			return  # a packet ended the session
	match mode:
		Mode.CLIENT:
			if not _welcomed and _now() > _connect_deadline:
				_fail(&"timeout", "The server did not answer.")
				return
			if _welcomed:
				_ping_timer += delta
				if _ping_timer >= PING_INTERVAL:
					_ping_timer = 0.0
					_send(NetTransport.SERVER_PEER, Protocol.CHANNEL_STATE, true, Protocol.Msg.PING, {"t": _now()})
		Mode.SERVER:
			_server_tick(delta)


## Voice frames bypass `Wire`: clients play them, the server relays them to listeners in reach.
func _voice_packet(peer: int, data: PackedByteArray) -> void:
	if mode == Mode.CLIENT:
		if _welcomed:
			voice_received.emit(data)
	elif mode == Mode.SERVER and local_server != null and room_host != null:
		var speaker: int = room_host.player_of(peer)
		if speaker < 0:
			return
		if voice_relay == null:
			voice_relay = VoiceRelay.new()
		var peers: Dictionary[int, int] = {}
		for pr: int in room_host.welcomed_peers():
			peers[room_host.player_of(pr)] = pr
		var listeners: Array[int] = []
		listeners.assign(peers.keys())
		var out: Dictionary[int, PackedByteArray] = voice_relay.route(local_server, speaker, data, _now(), listeners)
		for pid: int in out:
			transport.send(peers[pid], Protocol.CHANNEL_VOICE, false, out[pid])


func _send(peer: int, channel: int, reliable: bool, type: int, payload: Variant) -> void:
	if transport != null:
		transport.send(peer, channel, reliable, Wire.encode(type, payload))


func _now() -> float:
	return (Time.get_ticks_usec() - _start_ticks) / 1000000.0


func _on_local_event(ev: Dictionary) -> void:
	event_received.emit(ev)
