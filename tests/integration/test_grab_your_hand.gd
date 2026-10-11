extends GutTest
## Grab Your Hand on the authoritative server: the room opens in the card hall with cards on the
## floor, walking onto a card (the server's own position) picks it up, the drop button lays it
## back down, and a shove that lands makes the target drop a card. Grabbing is refused.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(3, {"minigames": 1, "gamble_seconds": 20.0, "seed": 9, "minigame_pool": "grab_your_hand"})
	LuckyLounge.describe_rooms(fx.server.map_def)
	fx.server.map_def.lobby_spawns = LuckyLounge.LOBBY_SPAWNS.duplicate()


func after_each() -> void:
	fx.server.free()


func _to_game() -> GrabYourHandLogic:
	fx.server.start_match()
	fx.place_all(Vector3(0, 0, -4))
	var t: float = 0.0
	while fx.of_type(&"minigame_started").is_empty() and t < 200.0:
		fx.run(0.5)
		t += 0.5
	assert_eq(fx.of_type(&"minigame_started").size(), 1, "the minigame started")
	var g: GrabYourHandLogic = fx.server.minigame as GrabYourHandLogic
	assert_not_null(g, "Grab Your Hand is running")
	t = 0.0
	while fx.server.in_briefing() and t < 60.0:
		fx.run(0.5)
		t += 0.5
	fx.run(0.1)
	return g


## Puts everyone by the gallery rail, away from the cards.
func _park() -> void:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	for i: int in fx.player_ids.size():
		fx.server.world.set_transform(fx.player_ids[i], o + Vector3(-6.0 + 2.0 * float(i), 0, 6.85), 0.0)


func test_room_opens_in_the_card_hall_with_cards_on_the_floor() -> void:
	var g: GrabYourHandLogic = _to_game()
	var started: Dictionary = fx.of_type(&"minigame_started")[0]
	assert_eq(StringName(started["minigame"]), &"grab_your_hand")
	assert_true(started.has("room"))
	for p: int in fx.player_ids:
		var at: Vector3 = fx.server.world.get_position(p)
		assert_true(g.arena.has_point(at), "%d stands in the hall at %s" % [p, at])
	assert_eq(fx.of_type(&"grab_your_hand_begin").size(), 1, "announced once the game ticks")
	assert_eq(fx.of_type(&"grab_your_hand_spawned").size(), 1)
	var snap: Dictionary = fx.server.get_snapshot()["minigame"]
	assert_eq((snap["floor"] as Array).size(), g.floor_cards.size(), "late joiners see the floor")
	assert_true(g.floor_cards.size() >= 5, "players + 3 on the floor")
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	fx.server.world.set_transform(b, fx.server.world.get_position(a) + Vector3(0, 0, -0.8), 0.0)
	assert_eq(fx.intent(a, &"grab", {"target": b})["error"], &"minigame", "grab is off")


func test_walking_onto_a_card_picks_it_up_and_drop_lays_it_back() -> void:
	var g: GrabYourHandLogic = _to_game()
	_park()
	fx.run(0.1)
	var a: int = fx.player_ids[0]
	var fid: int = g.floor_cards.keys()[0]
	var card: int = int(g.floor_cards[fid]["card"])
	var spot: Vector3 = g.floor_cards[fid]["pos"]
	fx.server.world.set_transform(a, spot + Vector3(0.3, 0, 0), 0.0)  # the server's own position
	fx.run(0.1)
	assert_false(g.floor_cards.has(fid), "the card left the floor")
	assert_true(card in g.hand_of(a), "a picked it up")
	var picked: Array[Dictionary] = fx.of_type(&"grab_your_hand_picked")
	assert_eq(picked.size(), 1)
	assert_eq(int(picked[0]["player"]), a)
	assert_true(int(fx.server.get_snapshot()["minigame"]["hands"][a][0]) == card, "hands are public")
	var res: Dictionary = fx.intent(a, &"minigame_action", {"kind": "drop", "target": 0})
	assert_true(res["ok"], "drop: %s" % res)
	assert_eq(g.hand_of(a).size(), 0)
	assert_eq(fx.of_type(&"grab_your_hand_dropped").size(), 1)


func test_a_shove_makes_the_target_drop_a_card() -> void:
	var g: GrabYourHandLogic = _to_game()
	_park()
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	g.hands[b] = [Card.make(1, 0), Card.make(13, 1)]
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	# a stands behind b (yaw 0 faces -z), in the open between the dais and the gallery.
	fx.server.world.set_transform(b, o + Vector3(5.0, 0, 3.0), 0.0)
	fx.server.world.set_transform(a, o + Vector3(5.0, 0, 4.0), 0.0)
	var before: int = g.floor_cards.size()
	var shove: Dictionary = fx.intent(a, &"shove", {"aim": [0.0, 0.0, -1.0], "target": b})
	assert_true(shove["ok"], "shove: %s" % shove)
	assert_eq(g.hand_of(b).size(), 1, "b dropped one card")
	assert_eq(g.floor_cards.size(), before + 1, "it lies on the floor")
	fx.run(0.1)
	var drops: Array[Dictionary] = fx.of_type(&"grab_your_hand_dropped")
	assert_eq(drops.size(), 1)
	assert_eq(StringName(drops[0]["how"]), &"shove")
	assert_eq(int(drops[0]["attacker"]), a)
