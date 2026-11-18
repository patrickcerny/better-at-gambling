extends GutTest
## Security audit 2026-11-18 (OWASP Top 10: A01 broken access control, A04/A05 insecure design and
## denial of service, A07 identity). Each test pins one fix:
## - a HELLO only counts on the events channel (the host's Steam bridge stamps the Steam-vouched
##   uid there; one sent on another channel would carry a made-up identity: the dev's or the host's),
## - the dev's god mode needs a Steam-vouched uid (host mode), never a dev server's claimed uid,
## - junk in a hello's optional fields (colour, god) can't break admission,
## - SNAPSHOT_REQ / PING / MOVE floods are capped per peer, and a held-back snapshot still arrives.


const HOST_STEAM: int = 76561190000000101
const ALICE_STEAM: int = 76561190000000102

var fx: ServerFixture
var host: RoomHost
var wire: MemoryTransport


func after_each() -> void:
	Net.stop()
	Net.mode = Net.Mode.NONE
	Net.room_host = null
	Net.transport = null
	Net.local_server = null
	if fx != null:
		fx.server.free()
		fx = null


func _setup_room(host_mode: bool) -> void:
	fx = ServerFixture.new(0)
	fx.server.room_mode = true
	fx.server.open_lobby()
	host = RoomHost.new()
	host.setup({"host_mode": host_mode, "empty_timeout": 0.0})
	add_child_autofree(host)
	host.set_process(false)
	wire = MemoryTransport.new().listen()
	Net.mode = Net.Mode.SERVER
	Net.transport = wire
	Net.room_host = host
	Net.local_server = fx.server
	host.on_server_attached(fx.server)


func _hello(uid: String, extra: Dictionary = {}) -> Dictionary:
	var h: Dictionary = {"protocol": Protocol.PROTOCOL_VERSION, "build": Protocol.BUILD_ID, "name": "Friend", "uid": uid}
	h.merge(extra, true)
	return h


func _count(peer: int, type: int) -> int:
	var n: int = 0
	for m: Array in wire.messages(peer):
		if int(m[0]) == type:
			n += 1
	return n


# --- HELLO on the events channel only ----------------------------------------------------------

func test_a_hello_on_another_channel_is_ignored() -> void:
	_setup_room(true)
	var dev_uid: String = "steam:%d" % DevMode.THE_DEV
	for ch: int in [Protocol.CHANNEL_STATE, Protocol.CHANNEL_PHYSICS, Protocol.CHANNEL_VOICE]:
		Net._server_packet(5, Protocol.Msg.HELLO, _hello(dev_uid, {"god": true}), ch)
	assert_eq(_count(5, Protocol.Msg.WELCOME), 0, "no welcome for a hello that bypassed the bridge")
	assert_eq(fx.server.player_by_uid(dev_uid), -1, "nobody got in as the dev")
	assert_true(fx.server.gods.is_empty())


func test_a_hello_on_the_events_channel_still_works() -> void:
	_setup_room(true)
	Net._server_packet(2, Protocol.Msg.HELLO, _hello("steam:%d" % HOST_STEAM), Protocol.CHANNEL_EVENTS)
	assert_eq(_count(2, Protocol.Msg.WELCOME), 1)
	assert_gt(fx.server.player_by_uid("steam:%d" % HOST_STEAM), -1)


# --- God mode only for a vouched uid -----------------------------------------------------------

func test_a_dev_server_never_makes_a_claimed_dev_uid_a_god() -> void:
	_setup_room(false)  # --server without orchestrator: the uid is whatever the client says
	host.on_hello(2, _hello("steam:%d" % DevMode.THE_DEV, {"god": true}))
	var pid: int = fx.server.player_by_uid("steam:%d" % DevMode.THE_DEV)
	assert_gt(pid, -1, "admitted as an ordinary player")
	assert_false(fx.server.is_god(pid), "no dev powers from a claimed uid")
	assert_eq(StringName(fx.server.submit_intent(pid, Intents.make(&"dev_troll", {"action": &"say", "text": "hi"}))["error"]), &"not_dev")


func test_host_mode_still_lets_the_vouched_dev_in_as_god() -> void:
	_setup_room(true)
	host.on_hello(2, _hello("steam:%d" % HOST_STEAM))
	host.on_hello(3, _hello("steam:%d" % DevMode.THE_DEV, {"god": true}))
	var dev: int = fx.server.player_by_uid("steam:%d" % DevMode.THE_DEV)
	assert_true(fx.server.is_god(dev), "DEV JOIN keeps working where Steam vouches for the uid")


func test_god_needs_the_dev_steam_id() -> void:
	_setup_room(true)
	host.on_hello(2, _hello("steam:%d" % ALICE_STEAM, {"god": true}))
	assert_false(fx.server.is_god(fx.server.player_by_uid("steam:%d" % ALICE_STEAM)))


func test_junk_in_optional_hello_fields_does_not_break_admission() -> void:
	_setup_room(true)
	host.on_hello(2, _hello("steam:%d" % ALICE_STEAM, {"color": [1, 2], "god": "yes", "outfit": 7}))
	var pid: int = fx.server.player_by_uid("steam:%d" % ALICE_STEAM)
	assert_gt(pid, -1, "admitted with defaults")
	assert_eq(_count(2, Protocol.Msg.WELCOME), 1)
	assert_false(fx.server.is_god(pid))


# --- Per-peer message caps ---------------------------------------------------------------------

func test_peer_limits_cap_floods_and_refill() -> void:
	var l := PeerLimits.new()
	var ok: int = 0
	for i: int in 100:
		if l.allow(2, Protocol.Msg.SNAPSHOT_REQ, 1.0):
			ok += 1
	assert_eq(ok, int(PeerLimits.PER_SECOND[Protocol.Msg.SNAPSHOT_REQ]), "a burst, then nothing")
	assert_true(l.allow(3, Protocol.Msg.SNAPSHOT_REQ, 1.0), "every peer has its own budget")
	assert_true(l.allow(2, Protocol.Msg.SNAPSHOT_REQ, 2.0), "refills over time")
	assert_true(l.allow(2, Protocol.Msg.INTENT, 1.0), "intents have their own limiter")
	l.forget(2)
	assert_true(l.allow(2, Protocol.Msg.SNAPSHOT_REQ, 2.0), "a new peer with a reused id starts fresh")


func test_real_client_rates_are_never_limited() -> void:
	var l := PeerLimits.new()
	for i: int in 600:  # 30 s of moves at the client's 20 Hz, pings once a second
		var t: float = i * PlayerAvatar.MOVE_SEND_INTERVAL
		assert_true(l.allow(2, Protocol.Msg.MOVE, t), "move %d" % i)
		if i % 20 == 0:
			assert_true(l.allow(2, Protocol.Msg.PING, t))


func test_a_snapshot_request_flood_is_capped_but_the_last_one_is_answered() -> void:
	_setup_room(true)
	host.on_hello(2, _hello("steam:%d" % ALICE_STEAM))
	var before: int = _count(2, Protocol.Msg.SNAPSHOT)
	for i: int in 200:
		Net._server_packet(2, Protocol.Msg.SNAPSHOT_REQ, {}, Protocol.CHANNEL_STATE)
	var burst: int = int(PeerLimits.PER_SECOND[Protocol.Msg.SNAPSHOT_REQ])
	assert_eq(_count(2, Protocol.Msg.SNAPSHOT) - before, burst, "200 requests build only a burst of snapshots")
	assert_true(Net._snapshot_owed.has(2), "the held-back request is remembered")
	var t0: float = Net._now()
	while Net._now() - t0 < 0.6:  # real time: the limiter refills on the session clock
		await wait_frames(1)
	Net._pay_owed_snapshots()
	assert_eq(_count(2, Protocol.Msg.SNAPSHOT) - before, burst + 1, "one more snapshot once the limit allows")
	assert_false(Net._snapshot_owed.has(2))


func test_ping_flood_is_capped() -> void:
	_setup_room(true)
	host.on_hello(2, _hello("steam:%d" % ALICE_STEAM))
	for i: int in 100:
		Net._server_packet(2, Protocol.Msg.PING, {"t": 1.0}, Protocol.CHANNEL_STATE)
	assert_eq(_count(2, Protocol.Msg.PONG), int(PeerLimits.PER_SECOND[Protocol.Msg.PING]))


func test_steam_party_admits_the_dev_and_lobby_members_only() -> void:
	assert_true(SteamParty.may_connect(DevMode.THE_DEV), "DEV JOIN skips the Steam lobby")
	assert_false(SteamParty.may_connect(ALICE_STEAM), "not in our lobby (no Steam in tests: no lobby at all)")
	assert_false(SteamParty.may_connect(0))
