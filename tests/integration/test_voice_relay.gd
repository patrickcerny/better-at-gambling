extends GutTest
## Proximity voice relay on the server (§2.22, §4.1 channel 3): who gets a speaker's frames
## (distance, same table, global phases), the per-speaker bandwidth cap, and the `Net` glue that
## receives voice from a client peer and sends it on to the listeners' peers.


class RecordingTransport:
	extends NetTransport
	var sent: Array[Dictionary] = []

	func send(to: int, channel: int, reliable: bool, data: PackedByteArray) -> void:
		sent.append({"peer": to, "channel": channel, "reliable": reliable, "data": data})


var fx: ServerFixture
var relay: VoiceRelay
var speaker: int
var near: int
var far: int


func before_each() -> void:
	fx = ServerFixture.new(3, {"minigames": 2, "gamble_seconds": 100.0, "seed": 3})
	fx.server.start_match()
	fx.run(3.1)  # past the intro: casino
	relay = VoiceRelay.new()
	speaker = fx.player_ids[0]
	near = fx.player_ids[1]
	far = fx.player_ids[2]
	fx.server.world.set_transform(speaker, Vector3(0, 0, 0), 0.0)
	fx.server.world.set_transform(near, Vector3(3, 0, 0), 0.0)
	fx.server.world.set_transform(far, Vector3(0, 0, 25), 0.0)


func after_each() -> void:
	fx.server.free()


func _frame(seq: int = 0, flags: int = 0) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(VoiceCodec.FRAME_SAMPLES)
	payload.fill(0x7F)
	return VoicePacket.make_up(seq, flags, payload)


func _route(t: float = 0.0, data: PackedByteArray = PackedByteArray()) -> Dictionary[int, PackedByteArray]:
	return relay.route(fx.server, speaker, data if not data.is_empty() else _frame(), t, fx.player_ids)


func test_speaker_at_3m_is_relayed_and_at_25m_is_not() -> void:
	assert_eq(fx.server.phases.phase, Phase.Id.CASINO)
	var out: Dictionary[int, PackedByteArray] = _route()
	assert_true(out.has(near), "3 m away: heard")
	assert_false(out.has(far), "25 m away: not relayed")
	assert_false(out.has(speaker), "never echoed back to the speaker")
	var d: Dictionary = VoicePacket.parse_down(out[near])
	assert_eq(d["speaker"], speaker)
	assert_eq(d["flags"], 0, "positional voice")
	assert_eq((d["payload"] as PackedByteArray).size(), VoiceCodec.FRAME_SAMPLES)


func test_hearing_radius_edge() -> void:
	fx.server.world.set_transform(far, Vector3(0, 0, VoiceProximity.HEARING_RADIUS - 0.5), 0.0)
	assert_true(_route().has(far))
	fx.server.world.set_transform(far, Vector3(0, 0, VoiceProximity.HEARING_RADIUS + 0.5), 0.0)
	assert_false(_route(1.0).has(far))


func test_everyone_hears_everyone_in_quiz_rewards_and_results() -> void:
	for phase: Phase.Id in [Phase.Id.MINIGAME, Phase.Id.REWARDS, Phase.Id.RESULTS]:
		fx.server.phases.phase = phase
		var out: Dictionary[int, PackedByteArray] = _route(float(phase))
		assert_true(out.has(near) and out.has(far), "%s: global voice" % Phase.name_of(phase))
		assert_eq(VoicePacket.parse_down(out[far])["flags"], VoicePacket.FLAG_GLOBAL)
	for phase: Phase.Id in [Phase.Id.LOBBY, Phase.Id.INTRO, Phase.Id.CASINO, Phase.Id.PRE_MINIGAME]:
		fx.server.phases.phase = phase
		assert_false(_route(10.0 + float(phase)).has(far), "%s: proximity only" % Phase.name_of(phase))


func test_quiz_phase_reached_by_playing_is_global() -> void:
	# The real schedule, not a poked phase: run until the first minigame starts.
	var guard: int = 0
	while fx.server.phases.phase != Phase.Id.MINIGAME and guard < 20000:
		fx.server.advance(MatchServer.TICK)
		guard += 1
	assert_eq(fx.server.phases.phase, Phase.Id.MINIGAME)
	fx.server.world.set_transform(far, Vector3(0, 0, 60), 0.0)
	assert_true(_route(500.0).has(far), "during the quiz everyone hears everyone")


func test_same_table_hears_at_full_volume_regardless_of_distance() -> void:
	var sid: StringName = &"roulette_1"
	var pos: Vector3 = Vector3(fx.server.map_def.station_positions.get(sid, Vector3.ZERO))
	for p: int in [speaker, far]:
		fx.server.world.set_transform(p, pos, 0.0)
		assert_true(fx.intent(p, &"sit", {"station": sid})["ok"], "player %d sits" % p)
	fx.server.world.set_transform(speaker, Vector3(0, 0, 0), 0.0)
	fx.server.world.set_transform(far, Vector3(0, 0, 40), 0.0)
	var out: Dictionary[int, PackedByteArray] = _route()
	assert_true(out.has(far), "same table: heard 40 m away")
	assert_eq(VoicePacket.parse_down(out[far])["flags"], VoicePacket.FLAG_TABLE)
	assert_eq(VoicePacket.parse_down(out[near])["flags"], 0, "the bystander still hears positional voice")


func test_megaphone_holder_is_heard_by_everyone_for_ten_seconds() -> void:
	fx.server.world.set_transform(speaker, MegaphoneLogic.STAND_POS, 0.0)
	fx.server.world.set_transform(near, MegaphoneLogic.STAND_POS + Vector3(3, 0, 0), 0.0)
	fx.server.world.set_transform(far, MegaphoneLogic.STAND_POS + Vector3(0, 0, -40), 0.0)
	assert_false(_route().has(far), "without the megaphone: 40 m is out of reach")
	assert_true(fx.intent(speaker, &"megaphone")["ok"], "picked up at the stand")
	var out: Dictionary[int, PackedByteArray] = _route(1.0)
	assert_true(out.has(far) and out.has(near), "megaphone: everyone hears the holder")
	assert_eq(VoicePacket.parse_down(out[far])["flags"], VoicePacket.FLAG_GLOBAL, "full volume, not positional")
	assert_eq(VoicePacket.parse_down(out[near])["flags"], VoicePacket.FLAG_GLOBAL)
	assert_false(relay.route(fx.server, far, _frame(), 1.5, fx.player_ids).has(speaker), "only the holder is global")
	fx.run(MegaphoneLogic.SECONDS + 0.1)
	assert_false(_route(20.0).has(far), "after 10 s the megaphone is back on its stand")
	assert_eq(VoicePacket.parse_down(_route(21.0)[near])["flags"], 0, "positional again")


func test_end_flag_survives_and_client_flags_are_not_trusted() -> void:
	var out: Dictionary[int, PackedByteArray] = _route(0.0, _frame(5, VoicePacket.FLAG_END | VoicePacket.FLAG_GLOBAL))
	var d: Dictionary = VoicePacket.parse_down(out[near])
	assert_eq(d["flags"], VoicePacket.FLAG_END, "clients can't claim global voice")
	assert_eq(d["seq"], 5)
	assert_false(out.has(far))


func test_malformed_and_unknown_speakers_are_dropped() -> void:
	assert_true(_route(0.0, PackedByteArray([1, 2, 3, 4, 5])).is_empty())
	assert_true(relay.route(fx.server, 999, _frame(), 0.0, fx.player_ids).is_empty())


func test_bandwidth_cap_per_speaker() -> void:
	# A steady μ-law speaker (25 frames/s) for 10 s: never throttled.
	for i: int in 250:
		assert_false(_route(i * VoiceCodec.FRAME_SECONDS, _frame(i)).is_empty())
	assert_eq(relay.dropped_packets, 0)
	# A flood (200 frames in one second) is cut to the cap.
	var through: int = 0
	for i: int in 200:
		if not _route(20.0 + i * 0.005, _frame(i)).is_empty():
			through += 1
	var bytes_per_s: float = through * _frame().size()
	assert_lt(bytes_per_s, VoiceRelay.MAX_BYTES_PER_SECOND * (1.0 + VoiceRelay.BURST_SECONDS) + 1.0, "flood capped (%d of 200 through)" % through)
	assert_gt(relay.dropped_packets, 100)
	# Another speaker has their own budget.
	assert_false(relay.route(fx.server, near, _frame(), 21.0, fx.player_ids).is_empty())


func test_net_server_relays_from_peer_to_listener_peers() -> void:
	var t := RecordingTransport.new()
	var host := RoomHost.new()
	host._players[10] = speaker
	host._players[11] = near
	host._players[12] = far
	Net.mode = Net.Mode.SERVER
	Net.transport = t
	Net.room_host = host
	Net.local_server = fx.server
	Net._voice_packet(10, _frame(3))
	Net._voice_packet(99, _frame(4))  # not a welcomed peer: ignored
	var sent: Array[Dictionary] = t.sent.duplicate()
	Net.mode = Net.Mode.NONE
	Net.transport = null
	Net.room_host = null
	Net.local_server = null
	Net.voice_relay = null
	host.free()
	assert_eq(sent.size(), 1, "only the listener in range gets it")
	assert_eq(sent[0]["peer"], 11)
	assert_eq(sent[0]["channel"], Protocol.CHANNEL_VOICE)
	assert_false(sent[0]["reliable"], "voice is unreliable")
	assert_eq(VoicePacket.parse_down(sent[0]["data"])["speaker"], speaker)


func test_net_client_sends_up_and_emits_relayed_frames() -> void:
	var t := RecordingTransport.new()
	Net.mode = Net.Mode.CLIENT
	Net.transport = t
	Net._welcomed = true
	var got: Array[PackedByteArray] = []
	var cb: Callable = func(d: PackedByteArray) -> void: got.append(d)
	Net.voice_received.connect(cb)
	Net.send_voice(_frame(1))
	var down: PackedByteArray = VoicePacket.make_down(2, 1, 0, PackedByteArray([1, 2]))
	Net._voice_packet(NetTransport.SERVER_PEER, down)
	Net.voice_received.disconnect(cb)
	Net.mode = Net.Mode.NONE
	Net.transport = null
	Net._welcomed = false
	assert_eq(t.sent.size(), 1)
	assert_eq(t.sent[0]["peer"], NetTransport.SERVER_PEER)
	assert_eq(t.sent[0]["channel"], Protocol.CHANNEL_VOICE)
	assert_eq(got, [down])


func test_client_channel_plays_relayed_voice_and_respects_mutes() -> void:
	var head_a := Node3D.new()
	var head_b := Node3D.new()
	add_child_autofree(head_a)
	add_child_autofree(head_b)
	var heads: Dictionary[int, Node3D] = {2: head_a, 3: head_b}
	var ch := VoiceChannel.new()
	ch.audio_enabled = false
	ch.setup(null, 1, func(pid: int) -> Node3D: return heads.get(pid, null), null, true)
	add_child_autofree(ch)
	var codec := MulawCodec.new()
	var tone: PackedFloat32Array = VoiceWav.tone(220.0, 0.04, VoiceCodec.SAMPLE_RATE, 0.4)
	ch.set_muted(3, true)
	for seq: int in 5:
		for pid: int in [1, 2, 3, 7]:
			ch._on_voice(VoicePacket.make_down(pid, seq, 0, codec.encode(tone)))
	assert_eq(ch.received_packets, 5, "own echo, muted and avatar-less speakers are skipped")
	assert_true(ch.playbacks.has(2))
	assert_false(ch.playbacks.has(3), "muted")
	assert_eq(ch.playbacks[2].get_parent(), head_a, "voice comes from the speaker's head")
	for i: int in 10:
		ch.playbacks[2].advance(VoiceCodec.FRAME_SECONDS)
	assert_true(ch.is_talking(2))
	assert_false(ch.is_talking(3))
