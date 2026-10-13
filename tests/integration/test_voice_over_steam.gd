extends GutTest
## Voice in host mode (Patrick plays over Steam with friends): the host's own game talks to the
## room server over loopback, a friend arrives over Steam Networking Messages through the host's
## `HostBridge`. A real 40 ms μ-law frame goes both ways through the real `SteamTransport` (fake
## Steam underneath), the bridge, the room server's `Net` voice relay with the real proximity
## rules and `RoomHost.player_of` for the bridged peer: same bytes, voice channel, unreliable on
## Steam, and the right speaker id on arrival.

const HOST_SID: int = 76561190000000001
const FRIEND_SID: int = 76561190000000002

var fx: ServerFixture
var steam_net: FakeSteam.Network
var host_steam: FakeSteam
var friend_steam: FakeSteam
var outside: SteamTransport  # the host's Steam end (listening)
var friend: SteamTransport  # the friend's game
var room: MemoryTransport  # the room server's loopback socket
var host_client: MemoryTransport  # the host's own game on loopback
var bridge: HostBridge
var room_host: RoomHost
var links: Array[MemoryTransport] = []
var now_ms: int = 1000
var host_player: int
var friend_player: int


func before_each() -> void:
	fx = ServerFixture.new(2, {"minigames": 2, "gamble_seconds": 100.0, "seed": 3})
	fx.server.start_match()
	fx.run(3.1)  # casino: proximity voice
	host_player = fx.player_ids[0]
	friend_player = fx.player_ids[1]
	fx.server.world.set_transform(host_player, Vector3.ZERO, 0.0)
	fx.server.world.set_transform(friend_player, Vector3(5, 0, 0), 0.0)
	steam_net = FakeSteam.Network.new()
	host_steam = steam_net.user(HOST_SID)
	friend_steam = steam_net.user(FRIEND_SID)
	outside = SteamTransport.new(host_steam)
	outside.set_clock(func() -> int: return now_ms)
	friend = SteamTransport.new(friend_steam)
	friend.set_clock(func() -> int: return now_ms)
	assert_eq(outside.listen(8), OK)
	room = MemoryTransport.new().listen()
	host_client = MemoryTransport.new().connect_to(room)
	links.clear()
	bridge = HostBridge.new(outside, func() -> NetTransport:
		var l: MemoryTransport = MemoryTransport.new().connect_to(room)
		links.append(l)
		return l)
	assert_eq(friend.connect_to_user(HOST_SID), OK)
	for i: int in 4:
		_pump()
	assert_eq(links.size(), 1, "the friend got a loopback link to the room")
	room_host = RoomHost.new()
	room_host._players[host_client.my_id] = host_player
	room_host._players[links[0].my_id] = friend_player
	Net.mode = Net.Mode.SERVER
	Net.transport = room
	Net.room_host = room_host
	Net.local_server = fx.server
	Net.voice_relay = null


func after_each() -> void:
	Net.mode = Net.Mode.NONE
	Net.transport = null
	Net.room_host = null
	Net.local_server = null
	Net.voice_relay = null
	room_host.free()
	bridge.close()
	friend.close()
	room.close()
	for u: FakeSteam in steam_net.users.values():
		u.network = null
	steam_net.users.clear()
	fx.server.free()


## One frame everywhere: the friend, the bridge, the room server (voice to `Net`), the host's game.
func _pump() -> Dictionary:
	now_ms += 16
	var got: Dictionary = {"friend": friend.poll(), "host": []}
	bridge.poll()
	for p: Dictionary in room.poll():
		if int(p["channel"]) == Protocol.CHANNEL_VOICE:
			Net._voice_packet(int(p["peer"]), p["data"])
	bridge.poll()
	got["friend"].append_array(friend.poll())
	got["host"] = host_client.poll()
	return got


func _frame(seq: int) -> PackedByteArray:
	var tone: PackedFloat32Array = VoiceWav.tone(440.0, VoiceCodec.FRAME_SECONDS, VoiceCodec.SAMPLE_RATE, 0.4)
	return VoicePacket.make_up(seq, 0, MulawCodec.new().encode(tone))


func _voice(packets: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in packets:
		if int(p["channel"]) == Protocol.CHANNEL_VOICE:
			out.append(p)
	return out


func test_a_friend_over_steam_is_heard_by_the_host() -> void:
	var up: PackedByteArray = _frame(7)
	assert_eq(up.size(), 324, "one 40 ms frame: far below Steam's unreliable message limit")
	friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_VOICE, false, up)
	var sent: Array[Dictionary] = friend_steam.game_sends(HOST_SID)
	assert_eq(int(sent[-1]["flags"]), SteamTransport.SEND_UNRELIABLE, "voice goes unreliable over Steam")
	assert_eq(int(sent[-1]["channel"]), Protocol.CHANNEL_VOICE)
	var heard: Array[Dictionary] = []
	for i: int in 3:
		heard.append_array(_voice(_pump()["host"]))
	assert_eq(heard.size(), 1, "the host's game gets the friend's frame")
	var down: Dictionary = VoicePacket.parse_down(heard[0]["data"])
	assert_eq(int(down["speaker"]), friend_player, "RoomHost.player_of knows the bridged friend")
	assert_eq(int(down["seq"]), 7)
	assert_eq(down["payload"], up.slice(VoicePacket.UP_HEADER), "same bytes")
	assert_eq(int(Net.voice_relay.received_from.get(friend_player, 0)), 1)


func test_the_host_is_heard_by_a_friend_over_steam() -> void:
	var up: PackedByteArray = _frame(3)
	host_client.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_VOICE, false, up)
	var heard: Array[Dictionary] = []
	for i: int in 3:
		heard.append_array(_voice(_pump()["friend"]))
	assert_eq(heard.size(), 1, "the friend gets the host's frame over Steam")
	assert_eq(int(heard[0]["peer"]), NetTransport.SERVER_PEER)
	var down: Dictionary = VoicePacket.parse_down(heard[0]["data"])
	assert_eq(int(down["speaker"]), host_player)
	assert_eq(down["payload"], up.slice(VoicePacket.UP_HEADER))
	var to_friend: Array[Dictionary] = host_steam.game_sends(FRIEND_SID)
	assert_eq(int(to_friend[-1]["channel"]), Protocol.CHANNEL_VOICE)
	assert_eq(int(to_friend[-1]["flags"]), SteamTransport.SEND_UNRELIABLE, "relayed voice stays unreliable on Steam")
	assert_eq(int(Net.voice_relay.delivered_to.get(friend_player, 0)), 1)


func test_a_stream_arrives_whole_and_in_order() -> void:
	# 12 frames back to back (the relay's bandwidth clock is real time; 12 fit its burst allowance).
	for seq: int in 12:
		friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_VOICE, false, _frame(seq))
		host_client.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_VOICE, false, _frame(seq))
		var got: Dictionary = _pump()
		for p: Dictionary in _voice(got["host"]):
			assert_eq(int(VoicePacket.parse_down(p["data"])["seq"]), seq)
		for p: Dictionary in _voice(got["friend"]):
			assert_eq(int(VoicePacket.parse_down(p["data"])["seq"]), seq)
	assert_eq(Net.voice_relay.delivered_to.get(host_player, 0), 12, "the friend's voice, nothing lost")
	assert_eq(Net.voice_relay.delivered_to.get(friend_player, 0), 12, "the host's voice, nothing lost")
	assert_eq(Net.voice_relay.dropped_packets, 0)
