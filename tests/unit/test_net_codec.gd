extends GutTest
## M3 wire pieces: packet framing, the binary world packet, interpolation, the network clock and
## the server's movement sanity checks.


func test_wire_round_trip_and_garbage() -> void:
	var payload: Dictionary = {"type": &"place_bet", "station": &"slot_3", "bet": {"amount": 25}, "pos": [1.5, 0.0, -2.0]}
	var msg: Array = Wire.decode(Wire.encode(Protocol.Msg.INTENT, payload))
	assert_eq(msg[0], Protocol.Msg.INTENT)
	assert_eq(msg[1], payload)
	assert_eq(Wire.decode(PackedByteArray([1, 2, 3, 4, 5])), [], "garbage decodes to nothing")
	assert_eq(Wire.decode(PackedByteArray()), [])
	assert_eq(Wire.decode(var_to_bytes([999])), [], "wrong shape")


func _world() -> Dictionary:
	return {
		"t": 12.345, "tick": 247,
		"players": {
			1: {"state": 0, "airborne": false, "pos": Vector3(1.25, 0.0, -3.5), "yaw": 1.2},
			2: {"state": 3, "airborne": true, "pos": Vector3(-7.0, 2.0, 9.0), "yaw": -2.9,
				"rag": {"pos": Vector3(-7.0, 2.4, 9.1), "rot": Quaternion(Vector3.UP, 0.7).normalized(),
					"parts": [Vector3(-7.0, 2.9, 9.1), Vector3(-7.3, 2.4, 9.0), Vector3(-6.7, 2.4, 9.0), Vector3(-7.0, 2.0, 9.1)]}},
		},
		"guards": [{"pos": Vector3(12, 0, 2), "yaw": 0.5, "state": 1}],
		"props": {4: {"pos": Vector3(3, 0.4, 3), "rot": Quaternion(Vector3.RIGHT, 1.0)}},
	}


func test_world_codec_round_trip_precision() -> void:
	var bytes: PackedByteArray = WorldCodec.encode(_world())
	var w: Dictionary = WorldCodec.decode(bytes)
	assert_almost_eq(float(w["t"]), 12.345, 0.001)
	assert_eq(int(w["tick"]), 247)
	var p1: Dictionary = w["players"][1]
	assert_eq(p1["pos"], Vector3(1.25, 0.0, -3.5))
	assert_almost_eq(float(p1["yaw"]), 1.2, 0.001)
	assert_false(p1["airborne"])
	assert_false(p1.has("rag"))
	var p2: Dictionary = w["players"][2]
	assert_true(p2["airborne"])
	assert_almost_eq(wrapf(float(p2["yaw"]) - (-2.9), -PI, PI), 0.0, 0.001, "yaw wraps but keeps its angle")
	var rag: Dictionary = p2["rag"]
	assert_almost_eq((rag["pos"] as Vector3).distance_to(Vector3(-7.0, 2.4, 9.1)), 0.0, 0.0001)
	assert_almost_eq((rag["rot"] as Quaternion).angle_to(Quaternion(Vector3.UP, 0.7)), 0.0, 0.001)
	for i: int in 4:
		assert_almost_eq((rag["parts"][i] as Vector3).distance_to(_world()["players"][2]["rag"]["parts"][i]), 0.0, 0.002, "parts to the millimetre")
	assert_eq(int(w["guards"][0]["state"]), 1)
	assert_almost_eq((w["props"][4]["rot"] as Quaternion).angle_to(Quaternion(Vector3.RIGHT, 1.0)), 0.0, 0.001)
	# A full 8-player world (2 ragdolls, guards, 6 moving props) stays well under one MTU.
	var big: Dictionary = _world()
	for i: int in range(3, 9):
		big["players"][i] = {"state": 0, "airborne": false, "pos": Vector3(i, 0, i), "yaw": 0.1}
	for i: int in 6:
		big["props"][i + 10] = {"pos": Vector3(i, 1, 0), "rot": Quaternion.IDENTITY}
	assert_lt(WorldCodec.encode(big).size(), 600)


func test_world_codec_rejects_truncated_and_foreign_packets() -> void:
	var bytes: PackedByteArray = WorldCodec.encode(_world())
	assert_eq(WorldCodec.decode(bytes.slice(0, bytes.size() - 5)), {})
	assert_eq(WorldCodec.decode(PackedByteArray([99, 0, 0])), {})
	assert_eq(WorldCodec.decode(PackedByteArray()), {})


func test_interp_buffer() -> void:
	var b := InterpBuffer.new(PackedInt32Array([1]))
	b.push(1.0, PackedFloat32Array([0.0, PI - 0.1]))
	b.push(1.1, PackedFloat32Array([1.0, -PI + 0.1]))
	b.push(1.05, PackedFloat32Array([99.0, 0.0]))  # out of order: dropped
	assert_eq(b.size(), 2)
	var mid: PackedFloat32Array = b.sample(1.05)
	assert_almost_eq(mid[0], 0.5, 0.0001)
	assert_almost_eq(absf(wrapf(mid[1], -PI, PI)), PI, 0.0001, "angles take the short way round")
	assert_almost_eq(b.sample(0.5)[0], 0.0, 0.0001, "before the oldest sample: hold")
	assert_almost_eq(b.sample(1.15)[0], 1.5, 0.0001, "short extrapolation")
	assert_almost_eq(b.sample(5.0)[0], 2.0, 0.0001, "extrapolation is capped at 0.1 s")
	b.clear()
	assert_true(b.is_empty())
	assert_eq(b.sample(1.0).size(), 0)


func test_net_clock_estimates_offset_and_rtt() -> void:
	var c := NetClock.new()
	# Server clock runs 100 s ahead; RTT 0.2 s.
	for i: int in 10:
		var sent: float = 1.0 + i
		c.add_sample(sent, sent + 100.0 + 0.1, sent + 0.2)
	assert_almost_eq(c.rtt, 0.2, 0.01)
	assert_almost_eq(c.server_now(50.0), 150.0, 0.02)
	assert_eq(c.ping_ms(), 200)


func test_move_sanity() -> void:
	var s := MoveSanity.new()
	assert_true(s.check(1, Vector3(0, 0, 0), 0.0), "first report sets the baseline")
	assert_true(s.check(1, Vector3(0.4, 0, 0), 0.05), "walking")
	assert_false(s.check(1, Vector3(10, 0, 0), 0.10), "10 m in 50 ms")
	assert_eq(s.last_good(1), Vector3(0.4, 0, 0))
	assert_true(s.check(1, Vector3(8, 0, 0), 0.6), "sprint + push within the limit")
	assert_false(s.check(1, Vector3(8, 0, 500), 30.0), "outside the map")
	s.allow_teleport(1, Vector3(0, 0, 13), 31.0)
	assert_true(s.check(1, Vector3(20, 0, -10), 31.2), "teleport grace")
	assert_true(s.check(1, Vector3(20.2, 0, -10), 33.0))
	assert_false(s.check(1, Vector3(-20, 0, 10), 33.05))
	assert_false(s.check(2, Vector3(NAN, 0, 0), 1.0))
