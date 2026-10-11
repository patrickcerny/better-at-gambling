extends GutTest
## SteamTransport (host mode over Steam) against a fake `Steam` singleton: session requests are
## accepted, the HI/WELCOME handshake maps each friend's Steam ID to a small peer id, our channels
## map 1:1 to Steam channels with the reliable flag, kicks say BYE, silence times out, and only
## the host may open a session with a joining client.

const HOST_ID: int = 76561190000000001
const ALICE_ID: int = 76561190000000002
const BOB_ID: int = 76561190000000003

var net: FakeSteam.Network
var host_steam: FakeSteam
var alice_steam: FakeSteam
var bob_steam: FakeSteam
var host: SteamTransport
var alice: SteamTransport
var bob: SteamTransport
var now_ms: int = 1000
var connected: Dictionary[String, Array] = {}
var disconnected: Dictionary[String, Array] = {}


func before_each() -> void:
	now_ms = 1000
	net = FakeSteam.Network.new()
	host_steam = net.user(HOST_ID)
	alice_steam = net.user(ALICE_ID)
	bob_steam = net.user(BOB_ID)
	host = _transport("host", host_steam)
	alice = _transport("alice", alice_steam)
	bob = _transport("bob", bob_steam)
	assert_eq(host.listen(8), OK)


func after_each() -> void:
	for t: SteamTransport in [host, alice, bob]:
		t.close()  # unhooks the fake's signals (no reference cycle left behind)
	for u: FakeSteam in net.users.values():
		u.network = null
	net.users.clear()


func _transport(who: String, s: FakeSteam) -> SteamTransport:
	var t := SteamTransport.new(s)
	t.set_clock(func() -> int: return now_ms)
	connected[who] = []
	disconnected[who] = []
	t.peer_connected.connect(func(p: int) -> void: connected[who].append(p))
	t.peer_disconnected.connect(func(p: int) -> void: disconnected[who].append(p))
	return t


## One frame on every end; returns {who: packets}.
func _pump(ms: int = 16) -> Dictionary:
	now_ms += ms
	var got: Dictionary = {}
	for pair: Array in [["host", host], ["alice", alice], ["bob", bob]]:
		got[pair[0]] = (pair[1] as SteamTransport).poll()
	return got


func _join_both() -> void:
	assert_eq(alice.connect_to_user(HOST_ID), OK)
	assert_eq(bob.connect_to_user(HOST_ID), OK)
	for i: int in 3:
		_pump()


func test_handshake_accepts_the_session_and_maps_steam_ids_to_peer_ids() -> void:
	_join_both()
	assert_true(host_steam.accepted.has(ALICE_ID) and host_steam.accepted.has(BOB_ID), "the host accepted both sessions")
	assert_eq(connected["host"], [2, 3], "friends get peer ids 2 and 3")
	assert_eq(connected["alice"], [NetTransport.SERVER_PEER], "the host is peer 1 for the client")
	assert_true(alice.is_active() and bob.is_active())
	assert_eq(alice.local_id(), 2)
	assert_eq(bob.local_id(), 3)
	assert_eq(host.local_id(), NetTransport.SERVER_PEER)
	assert_eq(host.steam_id_of(2), ALICE_ID)
	assert_eq(host.peer_of_steam_id(BOB_ID), 3)


func test_channels_and_reliable_flag_map_to_steam() -> void:
	_join_both()
	var data := PackedByteArray([1, 2, 3])
	alice.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_EVENTS, true, data)
	alice.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_PHYSICS, false, data)
	alice.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_VOICE, false, data)
	var to_host: Array[Dictionary] = alice_steam.game_sends(HOST_ID)
	assert_eq(to_host.size(), 3)
	assert_eq([int(to_host[0]["channel"]), int(to_host[0]["flags"])], [Protocol.CHANNEL_EVENTS, SteamTransport.SEND_RELIABLE])
	assert_eq([int(to_host[1]["channel"]), int(to_host[1]["flags"])], [Protocol.CHANNEL_PHYSICS, SteamTransport.SEND_UNRELIABLE])
	assert_eq(int(to_host[2]["channel"]), Protocol.CHANNEL_VOICE)
	var got: Array = _pump()["host"]
	assert_eq(got.size(), 3)
	assert_eq([int(got[0]["peer"]), int(got[0]["channel"])], [2, Protocol.CHANNEL_EVENTS])
	assert_eq([int(got[1]["peer"]), int(got[1]["channel"])], [2, Protocol.CHANNEL_PHYSICS])
	assert_eq([int(got[2]["peer"]), int(got[2]["channel"])], [2, Protocol.CHANNEL_VOICE])
	assert_eq(got[0]["data"], data)


func test_host_sends_to_one_peer_or_everyone() -> void:
	_join_both()
	host.send(3, Protocol.CHANNEL_STATE, true, PackedByteArray([9]))
	host.send(0, Protocol.CHANNEL_EVENTS, true, PackedByteArray([7]))
	var got: Dictionary = _pump()
	assert_eq((got["alice"] as Array).size(), 1, "alice only gets the broadcast")
	assert_eq((got["bob"] as Array).size(), 2)
	assert_eq(int((got["bob"] as Array)[0]["peer"]), NetTransport.SERVER_PEER)
	assert_eq(host.bytes_out_by_peer[3], 2)
	assert_almost_eq(host.peer_rtt_ms(2), 42.0, 0.01, "rtt from the Steam session status")


func test_a_client_only_opens_a_session_with_its_host() -> void:
	assert_eq(alice.connect_to_user(HOST_ID), OK)
	bob_steam.sendMessageToUser(ALICE_ID, PackedByteArray([1]), SteamTransport.SEND_RELIABLE, 0)
	_pump()
	assert_false(alice_steam.accepted.has(BOB_ID), "a stranger's session is not accepted")


func test_kick_says_bye_and_the_client_loses_the_host() -> void:
	_join_both()
	host.kick(2)
	var got: Dictionary = _pump()
	assert_eq(disconnected["host"], [2], "the host reports the kicked peer")
	assert_eq(disconnected["alice"], [NetTransport.SERVER_PEER], "alice hears BYE")
	assert_false(alice.is_active())
	assert_eq((got["host"] as Array).size(), 0)
	_pump(SteamTransport.CLOSE_DELAY_MS + 10)
	assert_true(ALICE_ID in host_steam.closed, "the session closes after the BYE went out")


func test_client_leaving_frees_its_peer() -> void:
	_join_both()
	bob.close()
	_pump()
	assert_eq(disconnected["host"], [3])
	assert_eq(host.steam_id_of(3), 0)


func test_silence_times_out_and_set_peer_timeout_tightens_it() -> void:
	_join_both()
	alice_steam.drop_unreliable = true  # keep-alives are unreliable: alice falls silent
	bob_steam.drop_unreliable = true
	host.set_peer_timeout(3, ENetTransport.TIMEOUT_MS)  # bob has loaded
	_pump(ENetTransport.TIMEOUT_MS + 100)
	_pump()
	assert_eq(disconnected["host"], [3], "bob (10 s) times out first")
	_pump(ENetTransport.LOADING_TIMEOUT_MS)
	_pump()
	assert_eq(disconnected["host"], [3, 2], "alice still loading: 30 s")


func test_session_failure_drops_the_peer() -> void:
	_join_both()
	host_steam.network_messages_session_failed.emit(4, BOB_ID, 5, "relay gone")
	_pump()
	assert_eq(disconnected["host"], [3])
	alice_steam.network_messages_session_failed.emit(4, HOST_ID, 5, "relay gone")
	assert_eq(disconnected["alice"], [NetTransport.SERVER_PEER])


func test_no_host_answer_fails_the_connection() -> void:
	var failed: Array[bool] = []
	var lonely := SteamTransport.new(net.user(76561190000000009))
	lonely.set_clock(func() -> int: return now_ms)
	lonely.connection_failed.connect(func() -> void: failed.append(true))
	assert_eq(lonely.connect_to_user(76561190000000777), OK, "nobody there")
	now_ms += SteamTransport.CONNECT_GIVE_UP_MS + 1
	lonely.poll()
	assert_eq(failed, [true])
	lonely.close()


func test_full_host_refuses_more_friends() -> void:
	host.max_clients = 1
	_join_both()
	assert_eq(connected["host"], [2])
	assert_false(bob.is_active(), "bob was told BYE")


func test_without_steam_nothing_starts() -> void:
	var t := SteamTransport.new(null)
	if Engine.has_singleton("Steam"):
		t.steam = null  # the real singleton is loaded here, but no Steam client runs
	assert_eq(t.listen(4), ERR_UNAVAILABLE)
	assert_eq(t.connect_to_user(HOST_ID), ERR_UNAVAILABLE)
	assert_eq(t.poll().size(), 0)
