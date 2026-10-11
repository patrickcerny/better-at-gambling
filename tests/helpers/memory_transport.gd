class_name MemoryTransport
extends NetTransport
## In-memory NetTransport for tests: one listening end (`MemoryTransport.new()` then `listen()`)
## and any number of clients (`connect_to(server)`). Packets and connection changes arrive on the
## receiver's next `poll()`, like a real socket. Records sends, kicks and peer timeouts.

var server_end: MemoryTransport = null
var is_server: bool = false
var my_id: int = 0
## Server: peer id → client end.
var clients: Dictionary[int, MemoryTransport] = {}
var sent: Array[Dictionary] = []
var kicked: Array[int] = []
var timeouts: Dictionary[int, int] = {}

var _inbox: Array[Dictionary] = []
var _events: Array[Array] = []
var _next_id: int = 2
var _open: bool = false


func listen() -> MemoryTransport:
	is_server = true
	my_id = SERVER_PEER
	_open = true
	return self


func connect_to(server: MemoryTransport) -> MemoryTransport:
	server_end = server
	my_id = server._next_id
	server._next_id += 1
	server.clients[my_id] = self
	_open = true
	server._events.append([&"connected", my_id])
	_events.append([&"connected", SERVER_PEER])
	return self


func poll() -> Array[Dictionary]:
	var events: Array[Array] = _events.duplicate()
	_events.clear()
	for e: Array in events:
		if e[0] == &"connected":
			peer_connected.emit(int(e[1]))
		else:
			peer_disconnected.emit(int(e[1]))
	var out: Array[Dictionary] = _inbox.duplicate()
	_inbox.clear()
	for p: Dictionary in out:
		bytes_in += (p["data"] as PackedByteArray).size()
	return out


func send(to: int, channel: int, reliable: bool, data: PackedByteArray) -> void:
	if not _open:
		return
	sent.append({"to": to, "channel": channel, "reliable": reliable, "data": data})
	if is_server:
		var targets: Array[int] = []
		if to == 0:
			targets.assign(clients.keys())
		elif clients.has(to):
			targets.append(to)
		for t: int in targets:
			clients[t]._inbox.append({"peer": SERVER_PEER, "channel": channel, "data": data})
			_count_out(t, data.size())
	elif server_end != null and server_end._open:
		server_end._inbox.append({"peer": my_id, "channel": channel, "data": data})
		_count_out(SERVER_PEER, data.size())


func kick(peer: int) -> void:
	kicked.append(peer)
	if is_server and clients.has(peer):
		var c: MemoryTransport = clients[peer]
		clients.erase(peer)
		c._open = false
		c._events.append([&"disconnected", SERVER_PEER])
		_events.append([&"disconnected", peer])


func close() -> void:
	if not _open:
		return
	_open = false
	if is_server:
		for id: int in clients:
			clients[id]._open = false
			clients[id]._events.append([&"disconnected", SERVER_PEER])
		clients.clear()
	elif server_end != null and server_end.clients.has(my_id):
		server_end.clients.erase(my_id)
		server_end._events.append([&"disconnected", my_id])


func is_active() -> bool:
	return _open


func local_id() -> int:
	return my_id if _open else 0


func set_peer_timeout(peer: int, timeout_ms: int) -> void:
	timeouts[peer] = timeout_ms


## Decoded `[type, payload]` of everything sent to `to` (server end) or to the server (client end).
func messages(to: int = -1) -> Array[Array]:
	var out: Array[Array] = []
	for s: Dictionary in sent:
		if to >= 0 and int(s["to"]) != to:
			continue
		var m: Array = Wire.decode(s["data"])
		if not m.is_empty():
			out.append(m)
	return out
