class_name ENetTransport
extends NetTransport
## ENet/UDP transport (§4.0: one port per room). Uses an ENetMultiplayerPeer without the
## SceneTree's multiplayer API: we frame our own packets (see `Wire`), which keeps every message
## countable and lets tests wrap the pipe with `DelayedTransport`.

const CHANNELS: int = 4
## Peer timeout in a match (§2.12: 10 s).
const TIMEOUT_MS: int = 10000
## Peer timeout while a client is still loading the match (Patrick: "Slow PCs can get kicked
## while loading"): a slow PC can block its main thread, and with it ENet, for well over 10 s while
## the casino builds. Every new peer starts with this; `set_peer_timeout` tightens it to
## `TIMEOUT_MS` once the client says it has loaded (`Protocol.Msg.LOADED`).
const LOADING_TIMEOUT_MS: int = 30000
## ENet packet throttle (see `_on_peer_connected`): ENet's default interval, faster recovery,
## and no slowing down when the round trip spikes.
const THROTTLE_INTERVAL_MS: int = 5000
const THROTTLE_ACCELERATION: int = 2
const THROTTLE_DECELERATION: int = 0

var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var _server: bool = false


## Starts listening. Returns OK or an error. `bind_ip` "127.0.0.1" keeps the port off the network
## (host mode: only the host's own game and its Steam bridge connect).
func listen(port: int, max_clients: int, bind_ip: String = "*") -> Error:
	_server = true
	peer.set_bind_ip(bind_ip)
	var err: Error = peer.create_server(port, max_clients, CHANNELS)
	if err != OK:
		return err
	# Godot 4.7's ENetMultiplayerPeer.create_server passes the channel count (4 + 2 system
	# channels) where ENet expects the incoming bandwidth, so the server tells every client it
	# can take 6 bytes/s. ENet's bandwidth throttle then cut each client's unreliable packets to
	# 1 in 32 a second after it connected, recovering over ~9 s: half of a new player's voice
	# frames (and moves) never arrived. No limit, as intended.
	peer.host.bandwidth_limit(0, 0)
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(func(id: int) -> void: peer_disconnected.emit(id))
	return OK


## Connects to a server.
func connect_to(host: String, port: int) -> Error:
	_server = false
	var err: Error = peer.create_client(host, port, CHANNELS)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(func(id: int) -> void: peer_disconnected.emit(id))
	return OK


func poll() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return out
	peer.poll()
	if not _server and peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		connection_failed.emit()
		return out
	while peer.get_available_packet_count() > 0:
		var from: int = peer.get_packet_peer()
		var channel: int = peer.get_packet_channel()
		var data: PackedByteArray = peer.get_packet()
		bytes_in += data.size()
		out.append({"peer": from, "channel": channel, "data": data})
	return out


func send(to: int, channel: int, reliable: bool, data: PackedByteArray) -> void:
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if _server and to != 0:
		# A peer that is disconnecting has no channels left; ENet would log an error.
		var pp: ENetPacketPeer = peer.get_peer(to)
		if pp == null or pp.get_state() != ENetPacketPeer.STATE_CONNECTED:
			return
	peer.set_target_peer(to)
	peer.transfer_channel = channel
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	peer.put_packet(data)
	if to == 0:
		bytes_out += data.size()
	else:
		_count_out(to, data.size())


func kick(id: int) -> void:
	if _server and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		peer.disconnect_peer(id, false)


func flush() -> void:
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED and peer.host != null:
		peer.host.flush()


func close() -> void:
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		peer.close()
	# The peer's signals hold callables on us: break the reference cycle.
	for sig: StringName in [&"peer_connected", &"peer_disconnected"]:
		for c: Dictionary in peer.get_signal_connection_list(sig):
			peer.disconnect(sig, c["callable"])


func is_active() -> bool:
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func local_id() -> int:
	return peer.get_unique_id() if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED else 0


func peer_rtt_ms(id: int) -> float:
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return 0.0
	var pp: ENetPacketPeer = peer.get_peer(id)
	return pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if pp != null else 0.0


func set_peer_timeout(id: int, timeout_ms: int) -> void:
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	var p: ENetPacketPeer = peer.get_peer(id)
	if p != null and p.get_state() == ENetPacketPeer.STATE_CONNECTED:
		p.set_timeout(32, timeout_ms / 2, timeout_ms)


func _on_peer_connected(id: int) -> void:
	var p: ENetPacketPeer = peer.get_peer(id)
	if p != null:
		p.set_timeout(32, LOADING_TIMEOUT_MS / 2, LOADING_TIMEOUT_MS)
		# ENet slows a peer's unreliable packets (drops some on purpose) whenever its round trip
		# jumps above the average, e.g. while that player's game hitches loading a minigame, and
		# takes seconds to recover: voice from the server cut out after every hitch. Keep the
		# speed up (deceleration 0); reliable packets were never affected.
		p.throttle_configure(THROTTLE_INTERVAL_MS, THROTTLE_ACCELERATION, THROTTLE_DECELERATION)
	peer_connected.emit(id)


## The peer's current ENet packet throttle (32 = everything goes out), -1 when unknown. For tests.
func packet_throttle(id: int) -> int:
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return -1
	var p: ENetPacketPeer = peer.get_peer(id)
	return int(p.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)) if p != null else -1


## The peer's ENet packet throttle limit (`ENetPacketPeer.PACKET_THROTTLE_SCALE` = 32: unreliable
## packets are never dropped on purpose; 1 drops 31 of 32), -1 when unknown. For tests.
func packet_throttle_limit(id: int) -> int:
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return -1
	var p: ENetPacketPeer = peer.get_peer(id)
	return int(p.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_LIMIT)) if p != null else -1
