class_name ENetTransport
extends NetTransport
## ENet/UDP transport (§4.0: one port per room). Uses an ENetMultiplayerPeer without the
## SceneTree's multiplayer API: we frame our own packets (see `Wire`), which keeps every message
## countable and lets tests wrap the pipe with `DelayedTransport`.

const CHANNELS: int = 4
## Peer timeout (§2.12: 10 s).
const TIMEOUT_MS: int = 10000

var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var _server: bool = false


## Starts listening. Returns OK or an error.
func listen(port: int, max_clients: int) -> Error:
	_server = true
	var err: Error = peer.create_server(port, max_clients, CHANNELS)
	if err != OK:
		return err
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


func _on_peer_connected(id: int) -> void:
	var p: ENetPacketPeer = peer.get_peer(id)
	if p != null:
		p.set_timeout(32, TIMEOUT_MS / 2, TIMEOUT_MS)
	peer_connected.emit(id)
