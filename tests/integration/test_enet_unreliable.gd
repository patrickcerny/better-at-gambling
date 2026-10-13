extends GutTest
## Real ENet sockets on loopback: a freshly connected client's unreliable packets (voice frames,
## moves) all arrive. Godot 4.7's `ENetMultiplayerPeer.create_server` puts the channel count where
## ENet expects the incoming bandwidth, so an unpatched server announces 6 bytes/s and ENet's
## bandwidth throttle on the client dropped 31 of every 32 unreliable packets a second after
## connecting (~47 % of the first 9 s of a player's voice; found by `tests/net -k voice`).
## And ENet's packet throttle must not slow the server's unreliable packets to a client whose
## round trip spiked (a hitch while loading): voice to that player cut out for seconds after.

var server: ENetTransport
var client: ENetTransport
var got: int = 0
var got_down: int = 0
var client_id: int = -1


func before_each() -> void:
	var port: int = 25000 + randi() % 2000
	server = ENetTransport.new()
	assert_eq(server.listen(port, 4, "127.0.0.1"), OK)
	server.peer_connected.connect(func(id: int) -> void: client_id = id)
	client = ENetTransport.new()
	assert_eq(client.connect_to("127.0.0.1", port), OK)
	got = 0
	got_down = 0
	client_id = -1


func after_each() -> void:
	client.close()
	server.close()


func _pump(client_too: bool = true) -> void:
	for p: Dictionary in server.poll():
		if int(p["channel"]) == Protocol.CHANNEL_VOICE:
			got += 1
	if client_too:
		for p: Dictionary in client.poll():
			if int(p["channel"]) == Protocol.CHANNEL_VOICE:
				got_down += 1
		client.flush()
	server.flush()


func _connect() -> void:
	var waited: int = 0
	while (not client.is_active() or client_id < 0) and waited < 3000:
		_pump()
		await get_tree().create_timer(0.01).timeout
		waited += 10
	assert_true(client.is_active(), "connected on loopback")


func test_a_new_clients_voice_frames_all_arrive() -> void:
	await _connect()
	var frame := PackedByteArray()
	frame.resize(324)
	var sent: int = 0
	# 2.5 s of voice, one 40 ms frame at a time, starting right after the connection.
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 2500:
		if (Time.get_ticks_msec() - start) / 40 >= sent:
			client.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_VOICE, false, frame)
			sent += 1
		_pump()
		await get_tree().create_timer(0.005).timeout
	for i: int in 20:
		_pump()
		await get_tree().create_timer(0.01).timeout
	assert_gt(sent, 55)
	assert_eq(client.packet_throttle_limit(NetTransport.SERVER_PEER), ENetPacketPeer.PACKET_THROTTLE_SCALE, "ENet never throttles us")
	assert_gt(got, sent - 2, "every frame arrived (%d of %d)" % [got, sent])


## The server streams voice to a client whose game freezes for 1.5 s (no polling, no acks): its
## round trip spikes, and ENet must not throttle what the server sends it afterwards.
func test_a_hitch_does_not_throttle_voice_to_that_player() -> void:
	await _connect()
	var frame := PackedByteArray()
	frame.resize(324)
	var sent: int = 0
	var start: int = Time.get_ticks_msec()
	var after_hitch: int = -1
	while Time.get_ticks_msec() - start < 5000:
		var t: int = Time.get_ticks_msec() - start
		if t / 40 >= sent:
			server.send(client_id, Protocol.CHANNEL_VOICE, false, frame)
			sent += 1
		var hitching: bool = t > 1000 and t < 2500
		_pump(not hitching)
		if t >= 3000 and after_hitch < 0:
			after_hitch = sent
			got_down = 0
		await get_tree().create_timer(0.005).timeout
	for i: int in 20:
		_pump()
		await get_tree().create_timer(0.01).timeout
	assert_eq(server.packet_throttle(client_id), ENetPacketPeer.PACKET_THROTTLE_SCALE, "ENet does not slow the server's packets to them")
	var expected: int = sent - after_hitch
	assert_gt(got_down, expected - 2, "every frame after the hitch arrived (%d of %d)" % [got_down, expected])
