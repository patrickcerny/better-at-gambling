extends GutTest
## Playtest fixes: every player at a table gets their own chair (the server hands out seat
## indices) and their own blackjack hand.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(4, {"minigames": 2, "gamble_seconds": 100.0, "seed": 5})
	fx.server.start_match()
	fx.run(3.1)


func after_each() -> void:
	fx.server.free()


func _sit_all(sid: StringName, ids: Array) -> void:
	var pos: Variant = fx.server.map_def.station_positions.get(sid, null)
	for p: int in ids:
		if pos != null:
			fx.server.world.set_transform(p, Vector3(pos), 0.0)
		assert_true(fx.intent(p, &"sit", {"station": sid})["ok"], "player %d sits" % p)


func test_players_at_one_table_get_different_seats() -> void:
	_sit_all(&"roulette_1", fx.player_ids)
	var seats: Array = fx.of_type(&"player_sat").map(func(e: Dictionary) -> int: return int(e["seat"]))
	assert_eq(seats, [0, 1, 2, 3])
	# Someone leaves and someone else comes back: the freed chair is reused, nobody doubles up.
	assert_true(fx.intent(fx.player_ids[1], &"leave")["ok"])
	assert_true(fx.intent(fx.player_ids[1], &"sit", {"station": &"roulette_1"})["ok"])
	assert_eq(int(fx.of_type(&"player_sat").back()["seat"]), 1)
	var snap: Dictionary = fx.server.get_snapshot()
	var used: Dictionary = {}
	for id: Variant in snap["players"]:
		var s: int = int(snap["players"][id]["seat"])
		assert_false(used.has(s), "seat %d taken twice" % s)
		used[s] = true


func test_blackjack_seat_matches_the_hand_and_hands_differ() -> void:
	var ids: Array = fx.player_ids.slice(0, 3)
	_sit_all(&"blackjack_1", ids)
	var logic: BlackjackLogic = fx.server.stations.logics[&"blackjack_1"]
	for e: Dictionary in fx.of_type(&"player_sat"):
		assert_eq(logic.seats.find(int(e["player"])), int(e["seat"]))
	for p: int in ids:
		assert_true(fx.intent(p, &"place_bet", {"station": &"blackjack_1", "bet": {"amount": 25}})["ok"])
	fx.run(Registry.balance.bj_betting_window + 0.5)
	var hands: Dictionary = logic.get_public_state()["hands"]
	assert_eq(hands.size(), 3)
	var seen: Dictionary = {}
	for p: int in ids:
		seen[str(hands[p]["cards"])] = true
	assert_eq(seen.size(), 3, "three different hands: %s" % hands)
