extends GutTest
## WireGuard: the shape every client payload must have before a handler reads it.


func test_ordinary_intents_pass() -> void:
	for payload: Dictionary in [
		{"type": &"sit", "station": &"blackjack_1"},
		{"type": &"place_bet", "station": "roulette_1", "bet": {"type": &"straight", "value": 17, "amount": 10}},
		{"type": &"move", "pos": [1.5, 0.0, -3.25], "yaw": 3.1, "airborne": false},
		{"type": &"release", "throw": true, "aim": [0, 0, -1]},
		{"type": &"lobby_setting", "key": "minigame_pool", "value": "quiz,spy"},
		{"type": &"spy_clue", "text": "x".repeat(WireGuard.MAX_TEXT)},
		{"type": &"action", "station": &"craps_1", "action": &"roll", "params": {"numbers": [1, 2, 3], "deep": {"a": [null]}}},
		{},
	]:
		assert_eq(WireGuard.problem(payload), "", str(payload).left(80))
		assert_true(WireGuard.is_clean_dictionary(payload))


func test_non_finite_and_huge_numbers_are_refused() -> void:
	assert_ne(WireGuard.problem({"yaw": NAN}), "")
	assert_ne(WireGuard.problem({"yaw": INF}), "")
	assert_ne(WireGuard.problem({"pos": [0.0, -INF, 0.0]}), "")
	assert_ne(WireGuard.problem({"amount": 1.0e30}), "")
	assert_ne(WireGuard.problem({"amount": 9223372036854775807}), "")
	assert_ne(WireGuard.problem({"amount": -9223372036854775807 - 1}), "", "the smallest int64 has no absolute value")
	assert_eq(WireGuard.problem({"amount": 1000000000000}), "")
	assert_eq(WireGuard.problem({"amount": -1000000000000}), "")


func test_only_plain_data_types_are_allowed() -> void:
	for bad: Variant in [Vector3.ONE, Vector2.ZERO, Color.RED, PackedByteArray([1, 2]), PackedInt32Array([1]), NodePath("a/b"), Transform3D.IDENTITY, Rect2(), RID(), Basis.IDENTITY]:
		assert_ne(WireGuard.problem({"x": bad}), "", type_string(typeof(bad)))
		assert_ne(WireGuard.problem([bad]), "", type_string(typeof(bad)))
	assert_ne(WireGuard.problem({Vector2.ZERO: 1}), "", "keys are strings or ints")
	assert_ne(WireGuard.problem({[1]: 1}), "")
	assert_eq(WireGuard.problem({7: "seat"}), "")


func test_a_payload_that_is_not_a_dictionary_is_not_a_clean_dictionary() -> void:
	for bad: Variant in [null, 5, 2.5, "text", &"name", [1, 2], true, Vector3.ZERO]:
		assert_false(WireGuard.is_clean_dictionary(bad), str(bad))


func test_size_limits() -> void:
	assert_ne(WireGuard.problem({"text": "x".repeat(WireGuard.MAX_TEXT + 1)}), "")
	assert_ne(WireGuard.problem({"name": StringName("x".repeat(WireGuard.MAX_TEXT + 1))}), "")
	assert_ne(WireGuard.problem({"k".repeat(WireGuard.MAX_KEY + 1): 1}), "")
	var long_list: Array = []
	long_list.resize(WireGuard.MAX_ITEMS + 1)
	assert_ne(WireGuard.problem({"list": long_list}), "")
	long_list.resize(WireGuard.MAX_ITEMS)
	assert_eq(WireGuard.problem({"list": long_list}), "")
	var wide: Dictionary = {}
	for i: int in WireGuard.MAX_ITEMS + 1:
		wide[i] = i
	assert_ne(WireGuard.problem(wide), "")
	# Many small lists: each fits, the whole does not.
	var many: Array = []
	for i: int in 10:
		var row: Array = []
		row.resize(40)
		many.append(row)
	assert_ne(WireGuard.problem({"rows": many}), "", "410 values in one payload")


func test_nesting_depth() -> void:
	var nested: Variant = 1
	for i: int in WireGuard.MAX_DEPTH:
		nested = [nested]
	assert_eq(WireGuard.problem(nested), "", "MAX_DEPTH containers deep is fine")
	assert_ne(WireGuard.problem([nested]), "", "one deeper is not")
	var cyclic: Array = []
	cyclic.append(cyclic)
	assert_ne(WireGuard.problem(cyclic), "", "a self-referencing array ends at the depth limit")


func test_intents_check_the_kind_of_every_field() -> void:
	assert_eq(Intents.validate(Intents.make(&"sit", {"station": &"blackjack_1"})), [] as Array[String])
	assert_eq(Intents.validate(Intents.make(&"sit", {"station": 5})), ["station"] as Array[String])
	assert_eq(Intents.validate(Intents.make(&"grab", {"target": []})), ["target"] as Array[String])
	assert_eq(Intents.validate(Intents.make(&"grab", {"target": 2.0})), [] as Array[String], "a whole float is a whole number")
	assert_eq(Intents.validate(Intents.make(&"grab", {"target": 2.5})), ["target"] as Array[String])
	assert_eq(Intents.validate(Intents.make(&"move", {"pos": [1, 2, "x"], "yaw": 0.0})), ["pos"] as Array[String])
	assert_eq(Intents.validate(Intents.make(&"move", {"pos": [1, 2, 3], "yaw": NAN})), ["payload"] as Array[String])
	assert_eq(Intents.validate(Intents.make(&"shove", {"aim": [0, 0, -1], "target": "bob"})), ["target"] as Array[String], "optional fields are checked when present")
	assert_eq(Intents.validate(Intents.make(&"set_ready", {"ready": "yes"})), ["ready"] as Array[String])
	assert_eq(Intents.validate(Intents.make(&"place_bet", {"station": &"slot_1", "bet": [10]})), ["bet"] as Array[String])
	assert_eq(Intents.validate({"type": 7}), ["type"] as Array[String])
	assert_eq(Intents.validate({"type": &"fly"}), ["type"] as Array[String])
	assert_eq(Intents.type_of({"type": [1]}), &"")


func test_bet_fields() -> void:
	assert_true(StationManager.bet_fields_ok({"type": &"straight", "value": 17, "amount": 10}))
	assert_true(StationManager.bet_fields_ok({"amount": 25, "risk": "high", "unknown": [1]}))
	assert_false(StationManager.bet_fields_ok({"amount": [25]}))
	assert_false(StationManager.bet_fields_ok({"amount": 10, "type": 3}))
	assert_false(StationManager.bet_fields_ok({"amount": 10, "bonus": {}}))


func test_serializer_readers_refuse_junk() -> void:
	assert_eq(Serializer.to_vec3([1, 2, 3]), Vector3(1, 2, 3))
	assert_eq(Serializer.to_vec3([1, [], 3]), Vector3.ZERO)
	assert_eq(Serializer.to_vec3(["nan", 0, 0]), Vector3.ZERO)
	assert_eq(Serializer.to_vec3([NAN, 0, 0]), Vector3.ZERO)
	assert_eq(Serializer.to_float("3"), 0.0)
	assert_eq(Serializer.to_float(INF, 1.5), 1.5)
	assert_eq(Serializer.to_int(4.0), 4)
	assert_eq(Serializer.to_int(1.0e30, -1), -1)
	assert_eq(Serializer.to_name(5, &"x"), &"x")
	assert_true(Serializer.to_bool(1))
	assert_false(Serializer.to_bool("true"))


func test_weighted_index_never_draws_a_zero_weight() -> void:
	var r := SeededRng.new(1)
	for i: int in 20000:
		assert_ne(r.weighted_index([1.0, 2.0, 0.0]), 2)
		if is_failing():
			return
	assert_eq(r.weighted_index([0.0, 0.0]), -1)
	assert_lt(r.unit(), 1.0)
