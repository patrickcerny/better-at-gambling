class_name SteamTransport
extends NetTransport
## Steam Networking Messages transport (host mode, docs/DECISIONS.md "Host mode over Steam"):
## packets travel between Steam IDs through Valve's relay network (no port forwarding, NAT
## punched or relayed for free). Used by a friend's client to reach the host (`connect_to_user`)
## and by the host's `HostBridge` to accept friends (`listen`).
##
## Networking Messages is connectionless, so this adds a tiny handshake on its own Steam channel:
## the client repeats `HI` until the host answers `WELCOME <peer id>`; `BYE` ends a session either
## way; `KEEP` goes out once a second so silence means the peer is gone (same timeouts as
## `ENetTransport`: 30 s while loading, `set_peer_timeout` tightens it). Game channels map 1:1 to
## Steam channels (`Protocol.CHANNEL_*` = 0..3). Peer ids are small ints per Steam ID (the host
## is always `SERVER_PEER`, clients from 2 up) so `Net` and `RoomHost` never see Steam IDs.
##
## `steam` is the GodotSteam `Steam` singleton, or a fake with the same methods and signals in
## tests (tests/unit/test_steam_transport.gd).

const CONTROL_CHANNEL: int = 7
## Game channels polled each frame (`Protocol.CHANNEL_EVENTS` .. `CHANNEL_VOICE`).
const GAME_CHANNELS: Array[int] = [0, 1, 2, 3]
const MAX_MESSAGES_PER_POLL: int = 256
## k_nSteamNetworkingSend_Reliable / k_nSteamNetworkingSend_UnreliableNoNagle.
const SEND_RELIABLE: int = 8
const SEND_UNRELIABLE: int = 1
const CTRL_HI: int = 1
const CTRL_WELCOME: int = 2
const CTRL_BYE: int = 3
const CTRL_KEEP: int = 4
const HELLO_INTERVAL_MS: int = 1000
const KEEPALIVE_INTERVAL_MS: int = 1000
## A host that never answers: give up (Net's own 30 s connect timeout usually fires first).
const CONNECT_GIVE_UP_MS: int = 30000
## Seconds between a kick and closing the Steam session (the BYE and a REJECT still go out).
const CLOSE_DELAY_MS: int = 1500

var steam: Object
var max_clients: int = 12

var _server: bool = false
var _active: bool = false
var _closed: bool = false
var _local_id: int = 0
## Client: the host's Steam ID.
var _server_sid: int = 0
var _connect_started_ms: int = 0
var _last_hello_ms: int = -100000
var _last_keepalive_ms: int = 0
var _next_peer: int = 2
var _peer_by_sid: Dictionary[int, int] = {}
var _sid_by_peer: Dictionary[int, int] = {}
var _last_heard_ms: Dictionary[int, int] = {}
var _timeout_ms: Dictionary[int, int] = {}
## Steam ID → msec at which to close its session (kicked peers).
var _closing: Dictionary[int, int] = {}
## Disconnects to report on the next poll (kicks happen inside packet handling).
var _gone: Array[int] = []
var _clock: Callable = Time.get_ticks_msec


func _init(p_steam: Object = null) -> void:
	steam = p_steam
	if steam == null and Engine.has_singleton("Steam"):
		steam = Engine.get_singleton("Steam")


## Tests: replace the millisecond clock.
func set_clock(clock: Callable) -> void:
	_clock = clock


## Host: accept friends. Returns OK or ERR_UNAVAILABLE without Steam.
func listen(p_max_clients: int) -> Error:
	if steam == null:
		return ERR_UNAVAILABLE
	_server = true
	max_clients = p_max_clients
	_local_id = SERVER_PEER
	_active = true
	_hook_signals()
	return OK


## Client: start talking to the host's Steam ID. `peer_connected(SERVER_PEER)` follows its WELCOME.
func connect_to_user(host_steam_id: int) -> Error:
	if steam == null or host_steam_id == 0:
		return ERR_UNAVAILABLE
	_server = false
	_server_sid = host_steam_id
	_connect_started_ms = _now()
	_hook_signals()
	_send_hello()
	return OK


func poll() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _closed or steam == null:
		return out
	var now: int = _now()
	for peer: int in _gone:
		peer_disconnected.emit(peer)
	_gone.clear()
	for msg: Variant in steam.call("receiveMessagesOnChannel", CONTROL_CHANNEL, MAX_MESSAGES_PER_POLL):
		_on_control(msg as Dictionary, now)
		if _closed:
			return out
	for channel: int in GAME_CHANNELS:
		for msg: Variant in steam.call("receiveMessagesOnChannel", channel, MAX_MESSAGES_PER_POLL):
			var m: Dictionary = msg
			var peer: int = _peer_of_message(m)
			if peer == 0:
				continue
			_last_heard_ms[peer] = now
			var data: PackedByteArray = m.get("payload", PackedByteArray())
			bytes_in += data.size()
			out.append({"peer": peer, "channel": channel, "data": data})
	if not _server and not _active:
		if now - _connect_started_ms > CONNECT_GIVE_UP_MS:
			_closed = true
			connection_failed.emit()
			return out
		if now - _last_hello_ms >= HELLO_INTERVAL_MS:
			_send_hello()
	if _active and now - _last_keepalive_ms >= KEEPALIVE_INTERVAL_MS:
		_last_keepalive_ms = now
		for peer: int in _sid_by_peer:
			_control(_sid_by_peer[peer], CTRL_KEEP, 0, false)
	_check_timeouts(now)
	for sid: int in _closing.keys():
		if now >= _closing[sid]:
			_closing.erase(sid)
			steam.call("closeSessionWithUser", sid)
	return out


func send(to: int, channel: int, reliable: bool, data: PackedByteArray) -> void:
	if not _active or steam == null:
		return
	var flags: int = SEND_RELIABLE if reliable else SEND_UNRELIABLE
	if to == 0:
		for peer: int in _sid_by_peer:
			steam.call("sendMessageToUser", _sid_by_peer[peer], data, flags, channel)
			_count_out(peer, data.size())
		return
	if not _sid_by_peer.has(to):
		return
	steam.call("sendMessageToUser", _sid_by_peer[to], data, flags, channel)
	_count_out(to, data.size())


## Host: says BYE, forgets the peer and closes its Steam session shortly after.
func kick(peer: int) -> void:
	if not _server or not _sid_by_peer.has(peer):
		return
	var sid: int = _sid_by_peer[peer]
	_control(sid, CTRL_BYE, 0, true)
	_forget(peer)
	_closing[sid] = _now() + CLOSE_DELAY_MS
	_gone.append(peer)


func flush() -> void:
	pass  # Networking Messages sends on its own thread; nothing is held back on our side


func close() -> void:
	if _closed:
		return
	if steam != null:
		for peer: int in _sid_by_peer.keys():
			var sid: int = _sid_by_peer[peer]
			_control(sid, CTRL_BYE, 0, true)
		if not _server and _server_sid != 0:
			_control(_server_sid, CTRL_BYE, 0, true)
	# Sessions close on their own once idle; closing them now would drop the BYE.
	_sid_by_peer.clear()
	_peer_by_sid.clear()
	_active = false
	_closed = true
	_unhook_signals()


func is_active() -> bool:
	return _active


func local_id() -> int:
	return _local_id if _active else 0


func peer_rtt_ms(peer: int) -> float:
	if not _sid_by_peer.has(peer) or steam == null:
		return 0.0
	var info: Variant = steam.call("getSessionConnectionInfo", _sid_by_peer[peer], false, true)
	return float((info as Dictionary).get("ping", 0)) if info is Dictionary else 0.0


func set_peer_timeout(peer: int, timeout_ms: int) -> void:
	if _sid_by_peer.has(peer):
		_timeout_ms[peer] = timeout_ms


## Steam ID behind a peer id (0 if unknown).
func steam_id_of(peer: int) -> int:
	return _sid_by_peer.get(peer, 0)


## Peer id of a Steam ID (0 if unknown).
func peer_of_steam_id(sid: int) -> int:
	return _peer_by_sid.get(sid, 0)


# --- internals ---------------------------------------------------------------------------------

func _now() -> int:
	return int(_clock.call())


func _hook_signals() -> void:
	if steam.has_signal(&"network_messages_session_request") and not steam.is_connected(&"network_messages_session_request", _on_session_request):
		steam.connect(&"network_messages_session_request", _on_session_request)
	if steam.has_signal(&"network_messages_session_failed") and not steam.is_connected(&"network_messages_session_failed", _on_session_failed):
		steam.connect(&"network_messages_session_failed", _on_session_failed)


func _unhook_signals() -> void:
	if steam == null:
		return
	if steam.is_connected(&"network_messages_session_request", _on_session_request):
		steam.disconnect(&"network_messages_session_request", _on_session_request)
	if steam.is_connected(&"network_messages_session_failed", _on_session_failed):
		steam.disconnect(&"network_messages_session_failed", _on_session_failed)


## Someone wants to talk: the host listens to anyone (they still need the build check and a
## slot), a client only to its host.
func _on_session_request(remote_steam_id: int) -> void:
	if _closed:
		return
	if _server or remote_steam_id == _server_sid:
		steam.call("acceptSessionWithUser", remote_steam_id)


func _on_session_failed(_reason: int, remote_steam_id: int, _state: int = 0, debug_message: String = "") -> void:
	if _closed:
		return
	if _server:
		var peer: int = _peer_by_sid.get(remote_steam_id, 0)
		if peer != 0:
			Log.info(&"steam", "session with peer %d failed: %s" % [peer, debug_message])
			_forget(peer)
			_gone.append(peer)
	elif remote_steam_id == _server_sid:
		Log.info(&"steam", "session with the host failed: %s" % debug_message)
		_lose_host()


func _on_control(m: Dictionary, now: int) -> void:
	var sid: int = int(m.get("identity", 0))
	var data: PackedByteArray = m.get("payload", PackedByteArray())
	if sid == 0 or data.size() < 1:
		return
	var kind: int = data[0]
	if _server:
		var peer: int = _peer_by_sid.get(sid, 0)
		match kind:
			CTRL_HI:
				if peer == 0:
					if _sid_by_peer.size() >= max_clients:
						_control(sid, CTRL_BYE, 0, true)
						return
					peer = _next_peer
					_next_peer += 1
					_peer_by_sid[sid] = peer
					_sid_by_peer[peer] = sid
					_timeout_ms[peer] = ENetTransport.LOADING_TIMEOUT_MS
					_last_heard_ms[peer] = now
					_closing.erase(sid)
					_control(sid, CTRL_WELCOME, peer, true)
					peer_connected.emit(peer)
				else:
					_control(sid, CTRL_WELCOME, peer, true)  # our WELCOME crossed a repeated HI
			CTRL_BYE:
				if peer != 0:
					_forget(peer)
					peer_disconnected.emit(peer)
			_:
				if peer != 0:
					_last_heard_ms[peer] = now
		return
	if sid != _server_sid:
		return
	match kind:
		CTRL_WELCOME:
			if not _active:
				_local_id = data.decode_u16(1) if data.size() >= 3 else 2
				_active = true
				_peer_by_sid[sid] = SERVER_PEER
				_sid_by_peer[SERVER_PEER] = sid
				_timeout_ms[SERVER_PEER] = ENetTransport.LOADING_TIMEOUT_MS
				_last_heard_ms[SERVER_PEER] = now
				peer_connected.emit(SERVER_PEER)
		CTRL_BYE:
			_lose_host()
		_:
			if _active:
				_last_heard_ms[SERVER_PEER] = now


func _peer_of_message(m: Dictionary) -> int:
	return _peer_by_sid.get(int(m.get("identity", 0)), 0)


func _check_timeouts(now: int) -> void:
	for peer: int in _sid_by_peer.keys():
		if now - _last_heard_ms.get(peer, now) > _timeout_ms.get(peer, ENetTransport.TIMEOUT_MS):
			Log.info(&"steam", "peer %d timed out" % peer)
			if _server:
				var sid: int = _sid_by_peer[peer]
				_forget(peer)
				steam.call("closeSessionWithUser", sid)
				peer_disconnected.emit(peer)
			else:
				_lose_host()
				return


func _lose_host() -> void:
	var was_active: bool = _active
	_forget(SERVER_PEER)
	_active = false
	_closed = true
	if was_active:
		peer_disconnected.emit(SERVER_PEER)
	else:
		connection_failed.emit()


func _forget(peer: int) -> void:
	var sid: int = _sid_by_peer.get(peer, 0)
	_sid_by_peer.erase(peer)
	_peer_by_sid.erase(sid)
	_last_heard_ms.erase(peer)
	_timeout_ms.erase(peer)


func _send_hello() -> void:
	_last_hello_ms = _now()
	_control(_server_sid, CTRL_HI, 0, true)


func _control(sid: int, kind: int, arg: int, reliable: bool) -> void:
	var b := PackedByteArray()
	b.resize(3)
	b[0] = kind
	b.encode_u16(1, arg)
	steam.call("sendMessageToUser", sid, b, SEND_RELIABLE if reliable else SEND_UNRELIABLE, CONTROL_CHANNEL)
