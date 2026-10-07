extends GutTest


func _sample_state() -> MatchState:
	var s := MatchState.new()
	s.match_seed = 99
	s.phase = Phase.Id.CASINO
	s.minigames = 4
	s.gamble_s = 150.0
	s.duration_s = 750.0
	s.casino_time = 123.456
	s.segment_index = 1
	for i: int in range(1, 4):
		var p := PlayerState.new()
		p.id = i
		p.uid = "uid-%d" % i
		p.display_name = "P%d" % i
		p.color_index = i
		p.skin = &"king"
		p.inventory = [&"lucky_clover", &"mirror"] as Array[StringName]
		p.quiz_points = 1500 + i
		p.position = Vector3(1.25, 0, -3.5 * i)
		s.add_player(p)
		s.balances[i] = 1000 * i
	s.jackpot = 777
	s.event_seq = 42
	s.stations = {"bj_1": {"state": 2, "seats": [1, -1, -1, -1]}}
	return s


func test_match_state_round_trip() -> void:
	var s: MatchState = _sample_state()
	var wire: Dictionary = s.to_wire()
	assert_true(Serializer.is_wire_safe(wire))
	# Through real bytes, as the network would carry it.
	var back: MatchState = MatchState.from_wire(bytes_to_var(var_to_bytes(wire)))
	assert_eq(back.to_wire(), wire)
	assert_eq(Serializer.state_hash(back.to_wire()), Serializer.state_hash(wire))
	assert_eq(back.players[2].display_name, "P2")
	assert_eq(back.players[3].skin, &"king")
	assert_eq(back.players[1].inventory, [&"lucky_clover", &"mirror"] as Array[StringName])
	assert_almost_eq(back.players[2].position.z, -7.0, 0.001)
	assert_eq(back.balances[3], 3000)


func test_state_hash_differs_on_change() -> void:
	var a: Dictionary = _sample_state().to_wire()
	var s: MatchState = _sample_state()
	s.balances[1] += 1
	assert_ne(Serializer.state_hash(a), Serializer.state_hash(s.to_wire()))


func test_wire_safety_rejects_objects() -> void:
	assert_false(Serializer.is_wire_safe({"x": Node.new()}))
	assert_false(Serializer.is_wire_safe([Vector3.ONE]))
	assert_true(Serializer.is_wire_safe({&"a": [1, 2.5, "s", true, null]}))


func test_room_codes() -> void:
	assert_true(Protocol.is_valid_room_code("KX7PQ"))
	assert_false(Protocol.is_valid_room_code("KX0PQ"))
	assert_false(Protocol.is_valid_room_code("KX7P"))


func test_events_validate() -> void:
	assert_eq(GameEvents.validate(GameEvents.round_result(&"s", 1, 10, 20)), [] as Array[String])
	assert_eq(GameEvents.validate({"type": &"money_changed", "player": 1}), ["amount", "reason", "balance"] as Array[String])
	assert_eq(GameEvents.validate({}), ["type"] as Array[String])
