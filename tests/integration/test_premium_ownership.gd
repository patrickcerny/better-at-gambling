extends GutTest
## Security audit 2026-11-18: premium outfit pieces (Gold Coins, the Daily Spin skin) and the
## developer pieces can only be worn online when the player really owns them. The joining game
## sends its Steam-signed inventory (`SteamSvc.inventory_proof`), the host's `HostBridge` has Steam
## check it (`InventoryProof`) and stamps what it grants as `steam_owned`; the room server
## (`MatchServer.may_wear`) takes off and refuses everything else.

const FRIEND_STEAM: int = 76561190000000102


## Stands in for GodotSteam's inventory calls: proofs are "signed" byte strings
## [owner steam id as text] + ":" + [item definitions], answered after `delay_polls` polls.
class FakeInventorySteam:
	extends RefCounted
	var results: Dictionary = {}
	var destroyed: Array[int] = []
	var delay_polls: int = 0
	var _next: int = 100

	func deserializeResult(buffer: PackedByteArray) -> int:
		_next += 1
		results[_next] = {"text": buffer.get_string_from_utf8(), "polls": 0}
		return _next

	func getResultStatus(handle: int) -> int:
		var r: Dictionary = results.get(handle, {})
		if r.is_empty():
			return 2
		r["polls"] = int(r["polls"]) + 1
		if int(r["polls"]) <= delay_polls:
			return InventoryProof.RESULT_PENDING
		return InventoryProof.RESULT_OK if str(r["text"]).contains(":") else 2

	func checkResultSteamID(steam_id: int, handle: int) -> bool:
		return str(results[handle]["text"]).split(":")[0] == str(steam_id)

	func getResultItems(handle: int) -> Array:
		var out: Array = []
		for def: String in str(results[handle]["text"]).split(":")[1].split(",", false):
			out.append({"item_id": 1, "item_definition": int(def), "quantity": 1})
		return out

	func destroyResult(handle: int) -> void:
		destroyed.append(handle)


static func proof(owner: int, defs: Array) -> PackedByteArray:
	var parts: PackedStringArray = []
	for d: Variant in defs:
		parts.append(str(d))
	return ("%d:%s" % [owner, ",".join(parts)]).to_utf8_buffer()


static func premium() -> CosmeticDef:
	for d: CosmeticDef in CosmeticShop.default().items:
		if d.gold > 0 and d.steam_item > 0 and d.kind in CosmeticDef.OUTFIT_KINDS:
			return d
	return null


static func coin_piece() -> CosmeticDef:
	for d: CosmeticDef in CosmeticShop.default().items:
		if d.coin_buyable() and d.kind in CosmeticDef.OUTFIT_KINDS:
			return d
	return null


static func dev_piece() -> CosmeticDef:
	for d: CosmeticDef in CosmeticShop.default().items:
		if d.dev_only and d.kind in CosmeticDef.OUTFIT_KINDS:
			return d
	return null


static func outfit_with(d: CosmeticDef) -> Array:
	var out: Array = []
	for kind: StringName in CosmeticDef.OUTFIT_KINDS:
		out.append(String(d.id) if kind == d.kind else "")
	return out


# --- InventoryProof ----------------------------------------------------------------------------

func test_a_proof_grants_its_pieces_to_its_owner_only() -> void:
	var steam := FakeInventorySteam.new()
	var check := InventoryProof.new(steam)
	var d: CosmeticDef = premium()
	var h: int = check.start(proof(FRIEND_STEAM, [d.steam_item]))
	assert_gt(h, 0)
	assert_true(d.id in (check.poll(FRIEND_STEAM, h) as Array), "Steam vouched for it")
	assert_true(h in steam.destroyed, "the handle is freed")
	var h2: int = check.start(proof(FRIEND_STEAM, [d.steam_item]))
	assert_eq(check.poll(76561190000000999, h2), [] as Array[StringName], "someone else's proof grants nothing")
	var h3: int = check.start("forged".to_utf8_buffer())
	assert_eq(check.poll(FRIEND_STEAM, h3), [] as Array[StringName], "a broken signature grants nothing")
	assert_eq(check.start(PackedByteArray()), 0, "no proof, nothing to check")
	assert_eq(check.start("junk"), 0)


func test_poll_waits_while_steam_checks() -> void:
	var steam := FakeInventorySteam.new()
	steam.delay_polls = 2
	var check := InventoryProof.new(steam)
	var h: int = check.start(proof(FRIEND_STEAM, [premium().steam_item]))
	assert_null(check.poll(FRIEND_STEAM, h))
	assert_null(check.poll(FRIEND_STEAM, h))
	assert_eq((check.poll(FRIEND_STEAM, h) as Array).size(), 1)


# --- HostBridge ---------------------------------------------------------------------------------

var outside: MemoryTransport
var room: MemoryTransport
var bridge: HostBridge
var friend: MemoryTransport
var fake: FakeInventorySteam
var now_ms: int = 0


func _bridge(delay: int = 0) -> void:
	outside = MemoryTransport.new().listen()
	room = MemoryTransport.new().listen()
	bridge = HostBridge.new(outside, func() -> NetTransport: return MemoryTransport.new().connect_to(room), func(_p: int) -> String: return "steam:%d" % FRIEND_STEAM)
	fake = FakeInventorySteam.new()
	fake.delay_polls = delay
	bridge.inventory_check = InventoryProof.new(fake)
	bridge.clock = func() -> int: return now_ms
	friend = MemoryTransport.new().connect_to(outside)


func after_each() -> void:
	if bridge != null:
		bridge.close()
		friend.close()
		room.close()
		bridge = null
	Net.stop()
	Net.mode = Net.Mode.NONE
	Net.room_host = null
	Net.transport = null
	if fx != null:
		fx.server.free()
		fx = null


func _step(n: int = 2) -> Array[Dictionary]:
	var at_room: Array[Dictionary] = []
	for i: int in n:
		friend.poll()
		bridge.poll()
		at_room.append_array(room.poll())
	return at_room


func _hello_bytes(extra: Dictionary) -> PackedByteArray:
	var h: Dictionary = {"protocol": Protocol.PROTOCOL_VERSION, "build": Protocol.BUILD_ID, "name": "Alice"}
	h.merge(extra, true)
	return Wire.encode(Protocol.Msg.HELLO, h)


func _hellos(got: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in got:
		var msg: Array = Wire.decode(p["data"])
		if not msg.is_empty() and int(msg[0]) == Protocol.Msg.HELLO:
			out.append(msg[1])
	return out


func test_the_bridge_stamps_what_steam_vouched_for() -> void:
	_bridge(2)
	var d: CosmeticDef = premium()
	friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_EVENTS, true, _hello_bytes({"inventory": proof(FRIEND_STEAM, [d.steam_item]), "steam_owned": ["claimed_everything"]}))
	friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_STATE, true, Wire.encode(Protocol.Msg.LOADED, {}))
	var got: Array[Dictionary] = _step(2)
	assert_eq(_hellos(got).size(), 0, "held while Steam checks the proof")
	got.append_array(_step(3))
	var hellos: Array[Dictionary] = _hellos(got)
	assert_eq(hellos.size(), 1)
	assert_eq(hellos[0]["steam_owned"], [String(d.id)], "only what Steam vouched for, not the claim")
	assert_false(hellos[0].has("inventory"), "the proof bytes stay with the bridge")
	assert_eq(int(Wire.decode(got[-1]["data"])[0]), Protocol.Msg.LOADED, "held packets follow in order")


func test_no_proof_means_no_premium_pieces() -> void:
	_bridge()
	friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_EVENTS, true, _hello_bytes({"steam_owned": ["anything"]}))
	var hellos: Array[Dictionary] = _hellos(_step(3))
	assert_eq(hellos.size(), 1)
	assert_eq(hellos[0]["steam_owned"], [])


func test_a_proof_steam_never_answers_times_out_empty() -> void:
	_bridge(1000000)
	friend.send(NetTransport.SERVER_PEER, Protocol.CHANNEL_EVENTS, true, _hello_bytes({"inventory": proof(FRIEND_STEAM, [premium().steam_item])}))
	assert_eq(_hellos(_step(3)).size(), 0)
	now_ms += bridge.proof_timeout_ms + 1
	var hellos: Array[Dictionary] = _hellos(_step(2))
	assert_eq(hellos.size(), 1, "the friend still gets in")
	assert_eq(hellos[0]["steam_owned"], [])


# --- The room server ----------------------------------------------------------------------------

var fx: ServerFixture
var host: RoomHost
var wire: MemoryTransport


func _room() -> void:
	fx = ServerFixture.new(0)
	fx.server.room_mode = true
	fx.server.open_lobby()
	host = RoomHost.new()
	host.setup({"host_mode": true, "empty_timeout": 0.0})
	add_child_autofree(host)
	host.set_process(false)
	wire = MemoryTransport.new().listen()
	Net.mode = Net.Mode.SERVER
	Net.transport = wire
	Net.room_host = host
	host.on_server_attached(fx.server)


func _join(peer: int, steam_id: int, outfit: Array, owned: Array) -> int:
	host.on_hello(peer, {"protocol": Protocol.PROTOCOL_VERSION, "build": Protocol.BUILD_ID, "name": "P%d" % peer, "uid": "steam:%d" % steam_id, "outfit": outfit, "steam_owned": owned})
	return fx.server.player_by_uid("steam:%d" % steam_id)


func test_an_unowned_premium_piece_is_taken_off_and_refused() -> void:
	_room()
	var d: CosmeticDef = premium()
	var pid: int = _join(2, FRIEND_STEAM, outfit_with(d), [])
	assert_gt(pid, -1)
	assert_false(String(d.id) in fx.server.state.players[pid].outfit, "taken off on join")
	var res: Dictionary = fx.server.submit_intent(pid, Intents.make(&"set_outfit", {"kind": d.kind, "item": d.id}))
	assert_eq(StringName(res["error"]), &"not_owned")


func test_an_owned_premium_piece_and_coin_pieces_are_worn() -> void:
	_room()
	var d: CosmeticDef = premium()
	var pid: int = _join(2, FRIEND_STEAM, outfit_with(d), [String(d.id)])
	assert_true(String(d.id) in fx.server.state.players[pid].outfit, "Steam vouched for it")
	var c: CosmeticDef = coin_piece()
	assert_true(fx.server.submit_intent(pid, Intents.make(&"set_outfit", {"kind": c.kind, "item": c.id}))["ok"], "Coin pieces live in the profile")


func test_developer_pieces_only_for_developer_accounts() -> void:
	var d: CosmeticDef = dev_piece()
	if d == null:
		pass_test("no developer piece in the shop")
		return
	_room()
	var pid: int = _join(2, FRIEND_STEAM, outfit_with(d), [String(d.id)])
	assert_false(String(d.id) in fx.server.state.players[pid].outfit)
	var dev: int = _join(3, DevMode.THE_DEV, outfit_with(d), [])
	assert_true(String(d.id) in fx.server.state.players[dev].outfit)


func test_a_long_owned_list_fits_the_hello() -> void:
	_room()
	var many: Array = []
	for d: CosmeticDef in CosmeticShop.default().items:
		many.append(String(d.id))
	assert_gt(many.size(), WireGuard.MAX_ITEMS, "more than a wire list may hold")
	var pid: int = _join(2, FRIEND_STEAM, outfit_with(premium()), many)
	assert_gt(pid, -1, "a whale still gets in")
	assert_true(String(premium().id) in fx.server.state.players[pid].outfit)


func test_practice_does_not_check() -> void:
	var server := ServerFixture.new(0)
	var d: CosmeticDef = premium()
	assert_false(server.server.verify_cosmetics)
	assert_true(server.server.may_wear(0, d.id))
	server.server.free()
