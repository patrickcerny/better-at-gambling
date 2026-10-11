extends GutTest
## HostBridge (host mode): every friend arriving over Steam gets its own connection to the room
## server on the host's PC; packets pass both ways on the same channel, the friend's HELLO carries
## the Steam-vouched uid (whatever the friend claimed), LOADED tightens the Steam-side timeout,
## and leaving / kicks propagate in both directions. In-memory transports stand in for Steam and
## for loopback ENet.

var outside: MemoryTransport  # the Steam side (listening)
var room: MemoryTransport  # the room server (listening on loopback)
var bridge: HostBridge
var friend: MemoryTransport
var links: Array[MemoryTransport] = []


func before_each() -> void:
	outside = MemoryTransport.new().listen()
	room = MemoryTransport.new().listen()
	links.clear()
	bridge = HostBridge.new(outside, _open_link, func(peer: int) -> String: return "steam:7656119%d" % peer)
	friend = MemoryTransport.new().connect_to(outside)


func after_each() -> void:
	bridge.close()
	friend.close()
	room.close()


func _open_link() -> NetTransport:
	var l: MemoryTransport = MemoryTransport.new().connect_to(room)
	links.append(l)
	return l


func _step(n: int = 2) -> Array[Dictionary]:
	var at_room: Array[Dictionary] = []
	for i: int in n:
		friend.poll()
		bridge.poll()
		at_room.append_array(room.poll())
	return at_room


func _hello(uid: String) -> PackedByteArray:
	return Wire.encode(Protocol.Msg.HELLO, {"protocol": Protocol.PROTOCOL_VERSION, "build": Protocol.BUILD_ID, "name": "Alice", "uid": uid})


func test_a_friend_gets_a_room_connection_and_hello_carries_the_steam_uid() -> void:
	friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_EVENTS, true, _hello("steam:1"))  # a lie
	var got: Array[Dictionary] = _step(3)
	assert_eq(links.size(), 1, "one loopback connection per friend")
	assert_eq(bridge.peers(), [2] as Array[int])
	assert_eq(got.size(), 1)
	var msg: Array = Wire.decode(got[0]["data"])
	assert_eq(int(msg[0]), Protocol.Msg.HELLO)
	assert_eq(str((msg[1] as Dictionary)["uid"]), "steam:76561192", "uid from the Steam identity, not the hello")
	assert_eq(str((msg[1] as Dictionary)["name"]), "Alice")
	assert_eq(int(got[0]["channel"]), Protocol.CHANNEL_EVENTS)


func test_packets_pass_both_ways_on_their_channels() -> void:
	friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_EVENTS, true, _hello(""))
	_step(3)
	var move: PackedByteArray = Wire.encode(Protocol.Msg.MOVE, {"seq": 1})
	friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_PHYSICS, false, move)
	friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_VOICE, false, PackedByteArray([1, 2, 3]))
	var got: Array[Dictionary] = _step(2)
	assert_eq(got.size(), 2)
	assert_eq([int(got[0]["channel"]), got[0]["data"]], [Protocol.CHANNEL_PHYSICS, move])
	assert_eq([int(got[1]["channel"]), got[1]["data"]], [Protocol.CHANNEL_VOICE, PackedByteArray([1, 2, 3])])
	var link_peer: int = links[0].my_id
	room.send(link_peer, Protocol.CHANNEL_STATE, true, Wire.encode(Protocol.Msg.STATUS, {"jackpot": 5}))
	room.send(link_peer, Protocol.CHANNEL_PHYSICS, false, PackedByteArray([9]))
	bridge.poll()
	var down: Array[Dictionary] = friend.poll()
	assert_eq(down.size(), 2)
	assert_eq(int(down[0]["channel"]), Protocol.CHANNEL_STATE)
	assert_eq(int(down[1]["channel"]), Protocol.CHANNEL_PHYSICS)
	var to_friend: Array[Dictionary] = outside.sent
	assert_true(bool(to_friend[0]["reliable"]), "state goes reliable")
	assert_false(bool(to_friend[1]["reliable"]), "physics goes unreliable")


func test_loaded_tightens_the_steam_timeout() -> void:
	friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_EVENTS, true, _hello(""))
	_step(3)
	friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_STATE, true, Wire.encode(Protocol.Msg.LOADED, {}))
	var got: Array[Dictionary] = _step(1)
	assert_eq(outside.timeouts.get(2, 0), ENetTransport.TIMEOUT_MS)
	assert_eq(got.size(), 1, "LOADED still reaches the room")


func test_a_friend_leaving_says_bye_to_the_room() -> void:
	friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_EVENTS, true, _hello(""))
	_step(3)
	friend.close()
	var got: Array[Dictionary] = _step(1)
	assert_eq(bridge.peers().size(), 0)
	assert_eq(int(Wire.decode(got[-1]["data"])[0]), Protocol.Msg.BYE, "the slot is freed right away")
	assert_false(links[0].is_active())


func test_a_room_kick_drops_the_friend_on_steam() -> void:
	friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_EVENTS, true, _hello(""))
	_step(3)
	room.send(links[0].my_id, Protocol.CHANNEL_EVENTS, true, Wire.encode(Protocol.Msg.REJECT, {"code": &"kicked"}))
	room.kick(links[0].my_id)
	bridge.poll()
	var down: Array[Dictionary] = friend.poll()
	assert_eq(int(Wire.decode(down[0]["data"])[0]), Protocol.Msg.REJECT, "the reason arrives first")
	assert_eq(outside.kicked, [2] as Array[int])
	assert_eq(bridge.peers().size(), 0)


func test_packets_before_the_room_answers_are_queued() -> void:
	bridge.local_factory = func() -> NetTransport:
		var l: MemoryTransport = _open_link()
		l._events.clear()  # the room has not answered yet
		return l
	friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_EVENTS, true, _hello(""))
	friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_PHYSICS, false, PackedByteArray([5]))
	friend.poll()
	bridge.poll()  # link opened, not up yet: both packets wait
	bridge.poll()
	assert_eq(room.poll().size(), 0)
	links[0]._events.append([&"connected", NetTransport.SERVER_PEER])
	bridge.poll()
	var got: Array[Dictionary] = room.poll()
	assert_eq(got.size(), 2, "flushed in order once the room connection is up")
	assert_eq(int(got[1]["channel"]), Protocol.CHANNEL_PHYSICS)


func test_close_drops_everyone() -> void:
	friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_EVENTS, true, _hello(""))
	_step(3)
	bridge.close()
	assert_false(outside.is_active())
	assert_false(links[0].is_active())
