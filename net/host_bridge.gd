class_name HostBridge
extends RefCounted
## Host mode (docs/DECISIONS.md "Host mode over Steam"): runs in the host's game and connects
## friends arriving over Steam (`outside`, a listening `SteamTransport`) to the party's room server
## on this PC (the headless `--server --host-mode` child, loopback only). Each friend gets its
## own loopback connection (`local_factory`), so the room server sees ordinary peers and
## everything (admission, kicks, late join, voice relay) works exactly as on a dedicated server.
##
## The bridge only looks inside two kinds of packets: a friend's HELLO, whose `uid` it overwrites
## with the Steam ID Steam vouched for ("steam:<id>": identities can't be faked, the 60 s kick block
## holds), and LOADED, which tightens the Steam-side timeout like `RoomHost.on_loaded` does for
## the loopback side. Everything else is forwarded byte for byte on the same channel.

## Most packets held per friend while its loopback connection opens.
const MAX_QUEUED: int = 512

var outside: NetTransport
## () -> NetTransport: a new client connection to the room server.
var local_factory: Callable
## outside peer → "steam:<id>" (the uid the room server sees).
var uid_of: Callable

var _links: Dictionary[int, NetTransport] = {}
var _link_up: Dictionary[int, bool] = {}
var _queued: Dictionary[int, Array] = {}
## Friends whose room connection dropped this poll (dropped on Steam after forwarding).
var _lost: Array[int] = []


func _init(p_outside: NetTransport, p_local_factory: Callable, p_uid_of: Callable = Callable()) -> void:
	outside = p_outside
	local_factory = p_local_factory
	uid_of = p_uid_of
	outside.peer_connected.connect(_on_outside_connected)
	outside.peer_disconnected.connect(_on_outside_disconnected)


## Friends currently bridged.
func peers() -> Array[int]:
	var out: Array[int] = []
	out.assign(_links.keys())
	return out


## Pumps both sides once (call every frame).
func poll() -> void:
	if outside == null:
		return
	for p: Dictionary in outside.poll():
		_from_outside(int(p["peer"]), int(p["channel"]), p["data"])
	for peer: int in _links.keys():
		var link: NetTransport = _links.get(peer)
		if link == null:
			continue
		# Packets that came with a disconnect (a REJECT before the kick) are still forwarded.
		for p: Dictionary in link.poll():
			var ch: int = int(p["channel"])
			outside.send(peer, ch, Protocol.is_reliable_channel(ch), p["data"])
		link.flush()
	for peer: int in _lost:
		if _links.has(peer):
			_drop_link(peer, false)
			outside.kick(peer)
	_lost.clear()
	outside.flush()


## Closes every link and the outside transport.
func close() -> void:
	for peer: int in _links.keys():
		_drop_link(peer, true)
	if outside != null:
		outside.close()
		outside = null


func _on_outside_connected(peer: int) -> void:
	var link: NetTransport = local_factory.call()
	if link == null:
		Log.warn(&"host", "could not open a loopback connection for peer %d" % peer)
		outside.kick(peer)
		return
	_links[peer] = link
	_link_up[peer] = false
	_queued[peer] = []
	link.peer_connected.connect(func(_id: int) -> void: _on_link_up(peer))
	link.peer_disconnected.connect(func(_id: int) -> void: _on_link_lost(peer))
	link.connection_failed.connect(func() -> void: _on_link_lost(peer))
	Log.info(&"host", "friend connected over Steam (peer %d)" % peer)


func _on_outside_disconnected(peer: int) -> void:
	if _links.has(peer):
		Log.info(&"host", "friend left (peer %d)" % peer)
		_drop_link(peer, true)


func _on_link_up(peer: int) -> void:
	if not _links.has(peer):
		return
	_link_up[peer] = true
	var link: NetTransport = _links[peer]
	for q: Array in _queued.get(peer, []):
		link.send(NetTransport.SERVER_PEER, int(q[0]), Protocol.is_reliable_channel(int(q[0])), q[1])
	_queued[peer] = []
	link.flush()


## The room server dropped the friend (kick, refusal, shutdown): drop them on Steam too, after
## the REJECT that may have come with it.
func _on_link_lost(peer: int) -> void:
	if _links.has(peer) and not peer in _lost:
		_lost.append(peer)


func _drop_link(peer: int, say_bye: bool) -> void:
	var link: NetTransport = _links.get(peer)
	_links.erase(peer)
	_link_up.erase(peer)
	_queued.erase(peer)
	if link == null:
		return
	if say_bye and link.is_active():
		# Leaving on purpose or timed out on Steam: free the slot now, not after ENet notices.
		link.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_EVENTS, true, Wire.encode(Protocol.Msg.BYE, {}))
		link.poll()
		link.flush()
	link.close()


func _from_outside(peer: int, channel: int, data: PackedByteArray) -> void:
	if not _links.has(peer):
		return
	if channel == Protocol.CHANNEL_EVENTS:
		data = _stamp_hello(peer, data)
	elif channel == Protocol.CHANNEL_STATE:
		var msg: Array = Wire.decode(data)
		if not msg.is_empty() and int(msg[0]) == Protocol.Msg.LOADED:
			outside.set_peer_timeout(peer, ENetTransport.TIMEOUT_MS)
	if not _link_up.get(peer, false):
		var q: Array = _queued[peer]
		if q.size() < MAX_QUEUED or Protocol.is_reliable_channel(channel):
			q.append([channel, data])
		return
	_links[peer].send(NetTransport.SERVER_PEER, channel, Protocol.is_reliable_channel(channel), data)


func _stamp_hello(peer: int, data: PackedByteArray) -> PackedByteArray:
	var msg: Array = Wire.decode(data)
	if msg.is_empty() or int(msg[0]) != Protocol.Msg.HELLO or typeof(msg[1]) != TYPE_DICTIONARY:
		return data
	var hello: Dictionary = (msg[1] as Dictionary).duplicate()
	if uid_of.is_valid():
		hello["uid"] = str(uid_of.call(peer))
	else:
		hello.erase("uid")
	return Wire.encode(Protocol.Msg.HELLO, hello)
