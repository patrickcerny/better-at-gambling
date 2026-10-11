extends GutTest
## Host mode (a party on the host's PC, friends through Steam; Patrick: "like Pummel Party").
## Part 1: the room's admission without an orchestrator: the hello's uid (the Steam ID, stamped by
## the host's bridge) is the identity, version checks and the 60 s kick block still apply, and the
## room closes when the host's game is gone.
## Part 2: the whole chain in one process: a friend's `NetSession` → `SteamTransport` → (fake
## Steam) → `SteamTransport` → `HostBridge` → the room server (`Net` in SERVER/host mode with a
## MatchServer) and back: welcome with the Steam uid, intents and events, a kick and the rejoin block.


## Records the close instead of quitting the test run.
class TestHost:
	extends RoomHost
	var closed_reason: String = ""

	func _close(reason: String) -> void:
		_closing = true
		closed_reason = reason


const HOST_STEAM: int = 76561190000000101
const ALICE_STEAM: int = 76561190000000102

var fx: ServerFixture
var host: TestHost
var wire: MemoryTransport


func after_each() -> void:
	if host != null and is_instance_valid(host):
		Net.room_host = null
	Net.stop()
	Net.mode = Net.Mode.NONE
	Net.room_host = null
	Net.transport = null
	if fx != null:
		fx.server.free()
		fx = null


# --- Part 1: admission -------------------------------------------------------------------------

func _setup_room() -> void:
	fx = ServerFixture.new(0)
	fx.server.room_mode = true
	fx.server.open_lobby()
	host = TestHost.new()
	host.setup({"host_mode": true})
	add_child_autofree(host)
	host.set_process(false)
	wire = MemoryTransport.new().listen()
	Net.mode = Net.Mode.SERVER
	Net.transport = wire
	Net.room_host = host
	host.on_server_attached(fx.server)


func _hello(uid: String, name_: String = "Friend", build: String = Protocol.BUILD_ID, protocol: int = Protocol.PROTOCOL_VERSION) -> Dictionary:
	return {"protocol": protocol, "build": build, "name": name_, "uid": uid}


func _rejects(peer: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for m: Array in wire.messages(peer):
		if int(m[0]) == Protocol.Msg.REJECT:
			out.append(StringName((m[1] as Dictionary)["code"]))
	return out


func _welcomed(peer: int) -> bool:
	for m: Array in wire.messages(peer):
		if int(m[0]) == Protocol.Msg.WELCOME:
			return true
	return false


func test_host_mode_room_admits_by_steam_uid_without_an_orchestrator() -> void:
	_setup_room()
	assert_eq(host.orchestrator, "")
	assert_almost_eq(host.empty_timeout, 120.0, 0.01, "a hosted room still closes when everyone left")
	host.on_hello(2, _hello("steam:%d" % HOST_STEAM, "Patrick"))
	host.on_hello(3, _hello("steam:%d" % ALICE_STEAM, "Alice"))
	assert_true(_welcomed(2) and _welcomed(3))
	var alice: int = fx.server.player_by_uid("steam:%d" % ALICE_STEAM)
	assert_gt(alice, -1, "the Steam ID is the identity")
	assert_eq(fx.server.state.players[alice].display_name, "Alice")
	assert_eq(fx.server.lobby.leader(), fx.server.player_by_uid("steam:%d" % HOST_STEAM), "the host (first in) leads the party")


func test_host_mode_refuses_another_build_or_protocol() -> void:
	_setup_room()
	host.on_hello(2, _hello("steam:1", "Old", "0.0.1"))
	host.on_hello(3, _hello("steam:2", "Older", Protocol.BUILD_ID, Protocol.PROTOCOL_VERSION - 1))
	assert_eq(_rejects(2), [&"version_mismatch"] as Array[StringName])
	assert_eq(_rejects(3), [&"version_mismatch"] as Array[StringName])
	assert_eq(fx.server.occupied_slots(), 0)


func test_host_mode_kick_blocks_the_steam_id_for_a_minute() -> void:
	_setup_room()
	host.on_hello(2, _hello("steam:%d" % HOST_STEAM, "Patrick"))
	host.on_hello(3, _hello("steam:%d" % ALICE_STEAM, "Alice"))
	var leader: int = fx.server.player_by_uid("steam:%d" % HOST_STEAM)
	var alice: int = fx.server.player_by_uid("steam:%d" % ALICE_STEAM)
	assert_true(fx.server.submit_intent(leader, Intents.make(&"kick_player", {"target": alice}))["ok"])
	assert_eq(_rejects(3), [&"kicked"] as Array[StringName])
	host.on_peer_disconnected(3)
	host.on_hello(4, _hello("steam:%d" % ALICE_STEAM, "Alice again"))
	assert_eq(_rejects(4), [&"kick_cooldown"] as Array[StringName], "same Steam ID: blocked for 60 s")
	host.on_hello(5, _hello("steam:76561190000000999", "Bob"))
	assert_true(_welcomed(5), "someone else still gets in")
	fx.server.advance(Protocol.KICK_REJOIN_SECONDS + 1.0)
	host.on_hello(6, _hello("steam:%d" % ALICE_STEAM, "Alice"))
	assert_true(_welcomed(6), "after a minute she may come back")


func test_host_mode_room_closes_once_the_host_is_gone() -> void:
	_setup_room()
	host.host_uid = "steam:%d" % HOST_STEAM
	host.on_hello(2, _hello("steam:%d" % HOST_STEAM, "Patrick"))
	host.on_hello(3, _hello("steam:%d" % ALICE_STEAM, "Alice"))
	assert_true(host.host_present())
	for i: int in 300:
		host._process(0.1)
	assert_eq(host.closed_reason, "", "the host plays on")
	host.on_peer_disconnected(2)  # the host's game crashed or quit
	for i: int in int(RoomHost.HOST_GONE_CLOSE * 10.0) - 5:
		host._process(0.1)
	assert_eq(host.closed_reason, "", "a short drop is fine (the host can rejoin)")
	for i: int in 10:
		host._process(0.1)
	assert_eq(host.closed_reason, "the host left", "friends are not left in a room without its host")


func test_host_mode_room_closes_if_the_host_never_arrives() -> void:
	_setup_room()
	host.host_uid = "steam:%d" % HOST_STEAM
	for i: int in int(RoomHost.FIRST_JOIN_GRACE * 10.0) + 5:
		host._process(0.1)
	assert_eq(host.closed_reason, "the host left")


# --- Part 2: the whole chain -------------------------------------------------------------------

var steam_net: FakeSteam.Network
var bridge: HostBridge
var friend: Node
var room_wire: MemoryTransport
var own: MemoryTransport
var friend_events: Array[Dictionary] = []
var friend_lost: Array[String] = []


func _setup_chain() -> void:
	fx = ServerFixture.new(0)
	fx.server.room_mode = true
	fx.server.open_lobby()
	room_wire = MemoryTransport.new().listen()
	assert_eq(Net.start_server(0, {"transport": room_wire, "host_mode": true}), OK)
	assert_true(Net.room_host.host_mode)
	Net.attach_server(fx.server)
	steam_net = FakeSteam.Network.new()
	var outside := SteamTransport.new(steam_net.user(HOST_STEAM))
	assert_eq(outside.listen(Protocol.MAX_PLAYERS + 4), OK)
	bridge = HostBridge.new(outside,
		func() -> NetTransport: return MemoryTransport.new().connect_to(room_wire),
		func(peer: int) -> String: return "steam:%d" % outside.steam_id_of(peer))
	# The host's own game joins its room directly (in the real thing: ENet over loopback).
	own = MemoryTransport.new().connect_to(room_wire)
	own.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_EVENTS, true, Wire.encode(Protocol.Msg.HELLO, _hello("steam:%d" % HOST_STEAM, "Patrick")))
	friend = (load("res://net/net_session.gd") as GDScript).new()
	friend.name = "FriendNet"
	add_child(friend)
	friend.connect(&"event_received", func(ev: Dictionary) -> void: friend_events.append(ev))
	friend.connect(&"disconnected", func(reason: String) -> void: friend_lost.append(reason))


func _teardown_chain() -> void:
	friend.call(&"stop")
	friend.free()
	bridge.close()
	own.close()
	for u: FakeSteam in steam_net.users.values():
		u.network = null
	steam_net.users.clear()


func _join_friend(steam: FakeSteam, claimed_uid: String) -> Error:
	return friend.call(&"join_server", "steam:%d" % HOST_STEAM, 0, {"name": "Alice", "uid": claimed_uid}, {"transport": "steam", "steam": steam, "steam_id": HOST_STEAM})


## Real frames (Net and the friend's session process themselves); the bridge is pumped here.
func _pump(frames: int) -> void:
	for i: int in frames:
		bridge.poll()
		own.poll()
		await get_tree().process_frame


func test_a_friend_plays_through_steam_bridge_and_room() -> void:
	_setup_chain()
	var alice_steam: FakeSteam = steam_net.user(ALICE_STEAM)
	assert_eq(_join_friend(alice_steam, "steam:%d" % HOST_STEAM), OK, "she even claims to be the host")
	for i: int in 60:
		await _pump(1)
		if friend.call(&"is_welcomed"):
			break
	assert_true(friend.call(&"is_welcomed"), "welcomed through Steam and the bridge")
	var pid: int = int(friend.get(&"local_player_id"))
	assert_eq(fx.server.state.players[pid].uid, "steam:%d" % ALICE_STEAM, "the uid is her real Steam ID")
	assert_eq(fx.server.state.players.size(), 2)
	# An intent up, the event back down.
	friend.call(&"send_intent", Intents.make(&"set_ready", {"ready": true}))
	await _pump(10)
	assert_true(fx.server.lobby.is_ready(pid), "her READY reached the room")
	assert_gt(friend_events.size(), 0, "server events reach the friend")
	assert_eq(alice_steam.game_sends(HOST_STEAM).filter(func(s: Dictionary) -> bool: return int(s["channel"]) == Protocol.CHANNEL_EVENTS)[0]["flags"], SteamTransport.SEND_RELIABLE)
	# The host kicks her: the reason arrives, then the connection goes; she can't come back yet.
	var leader: int = fx.server.player_by_uid("steam:%d" % HOST_STEAM)
	assert_true(fx.server.submit_intent(leader, Intents.make(&"kick_player", {"target": pid}))["ok"])
	for i: int in 90:
		await _pump(1)
		if not friend_lost.is_empty():
			break
	assert_eq(friend_lost, ["You were kicked by the host."] as Array[String])
	assert_eq(StringName(friend.get(&"last_error_code")), &"kicked")
	assert_eq(_join_friend(alice_steam, ""), OK)
	for i: int in 90:
		await _pump(1)
		if friend_lost.size() > 1:
			break
	assert_eq(StringName(friend.get(&"last_error_code")), &"kick_cooldown", "the Steam ID is blocked for a minute")
	_teardown_chain()
