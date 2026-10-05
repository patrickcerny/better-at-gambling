extends GutTest
## Items inside a whole match (M5): intents, the reward draft feeding inventories, scripted
## players using items, Spring Glove and Bodyguard in physical play, and money conservation with items on.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(2, {"duration": 5, "seed": 21})


func after_each() -> void:
	fx.server.free()


func _start() -> void:
	fx.server.start_match()
	fx.run(3.1)
	fx.place_all()


func _give(player: int, items: Array[StringName]) -> void:
	for it: StringName in items:
		fx.server.items.give(player, it, fx.server.match_time)


func test_use_item_intent_rules() -> void:
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	_give(a, [&"lucky_clover", &"black_cat"])
	assert_eq(fx.intent(a, &"use_item", {"slot": 0})["error"], &"wrong_phase", "not in the intro")
	_start()
	assert_true(fx.intent(a, &"use_item", {"slot": 0})["ok"])
	assert_eq(fx.server.modifiers.get_luck(a), 2)
	assert_eq(fx.intent(a, &"use_item", {"slot": 0, "target": b})["error"], &"cooldown")
	fx.run(3.1)
	assert_true(fx.intent(a, &"use_item", {"slot": 0})["ok"], "the only other player is picked automatically")
	assert_eq(fx.server.modifiers.get_luck(b), -2)
	var used: Array[Dictionary] = fx.of_type(&"item_used")
	assert_eq(used.size(), 2)
	assert_eq(used[1]["target"], b)
	var snap: Dictionary = fx.server.get_snapshot()
	assert_eq(snap["effects"][a], [&"lucky_clover"])
	assert_eq(int(fx.server.get_private_snapshot(a)["items"]["luck"]), 2)
	assert_true(Serializer.is_wire_safe(snap))


func test_items_off_refuses_use() -> void:
	fx.server.settings["items_enabled"] = false
	_start()
	_give(fx.player_ids[0], [&"lucky_clover"])
	assert_eq(fx.intent(fx.player_ids[0], &"use_item", {"slot": 0})["error"], &"items_off")


func test_spring_glove_shoves_knock_down_three_times() -> void:
	_start()
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	fx.server.world.set_transform(a, Vector3(0, 0, 0), 0.0)
	fx.server.world.set_transform(b, Vector3(0, 0, -1.0), 0.0)
	_give(a, [&"boxing_glove"])
	assert_true(fx.intent(a, &"use_item", {"slot": 0})["ok"])
	for i: int in 3:
		assert_true(fx.intent(a, &"shove", {"aim": [0, 0, -1]})["ok"], "shove %d" % i)
		var last: Dictionary = fx.of_type(&"player_shoved").back()
		assert_true(bool(last["spring_glove"]))
		fx.run(5.0)  # past the knockdown, cooldowns and knockout immunity
	assert_eq(fx.of_type(&"player_knocked_down").size(), 3)
	assert_true(fx.intent(a, &"shove", {"aim": [0, 0, -1]})["ok"])
	assert_false(bool(fx.of_type(&"player_shoved").back()["spring_glove"]), "used up")
	assert_eq(fx.of_type(&"effect_ended").back()["reason"], &"consumed")


func test_bodyguard_absorbs_a_knockout_from_an_item_user() -> void:
	_start()
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	_give(b, [&"bodyguard"])
	_give(a, [&"lucky_clover"])
	fx.intent(b, &"use_item", {"slot": 0})
	fx.intent(a, &"use_item", {"slot": 0})
	assert_false(fx.server.report_knockout(b, a, &"thrown"), "Bodyguard takes the hit")
	assert_eq(fx.of_type(&"bodyguard_saved").size(), 1)
	assert_true(fx.server.report_knockout(b, a, &"thrown"), "only once")


func test_reward_draft_fills_inventories_and_asks_when_full() -> void:
	_start()
	var a: int = fx.player_ids[0]
	_give(a, [&"lucky_clover", &"black_cat", &"mirror"])
	fx.server.run_to_end(200.0)  # through the first quiz and its rewards
	assert_gt(fx.of_type(&"draft_result").size(), 0)
	var full: Array[Dictionary] = fx.of_type(&"discard_needed").filter(func(e: Dictionary) -> bool: return e["player"] == a)
	assert_gt(full.size(), 0, "a full inventory asks what to drop")
	assert_eq(fx.server.state.players[a].inventory.size(), 3)


func test_scripted_players_use_items_in_a_full_match_and_money_is_conserved() -> void:
	for i: int in 3:
		fx.player_ids.append(fx.server.add_player("uid-extra-%d" % i, "X%d" % i))
	_start()
	for id: int in fx.player_ids:
		_give(id, [&"banana_peel", &"black_cat", &"pickpocket"])
	# Scripted players (the game has no bots): now and then each one uses its first item on
	# someone at random, through the same intent a client sends.
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	while fx.server.running and fx.server.phases.phase != Phase.Id.RESULTS:
		fx.server.run_to_end(1.0)
		for id: int in fx.player_ids:
			if fx.server.state.players[id].inventory.is_empty() or rng.randf() > 0.1:
				continue
			var target: int = fx.player_ids[rng.randi_range(0, fx.player_ids.size() - 1)]
			fx.intent(id, &"use_item", {"slot": 0, "target": target, "option": rng.randi_range(0, 2)})
	assert_eq(fx.server.phases.phase, Phase.Id.RESULTS)
	var used: Array[Dictionary] = fx.of_type(&"item_used")
	assert_gt(used.size(), 5, "players used their items")
	var kinds: Dictionary = {}
	for e: Dictionary in used:
		kinds[e["item"]] = true
	assert_gt(kinds.size(), 2)
	# Every dollar is in a balance, on the floor, or logged as expired; the ledger matches.
	var balances: int = 0
	for id: int in fx.server.state.players:
		balances += fx.server.economy.balance(id)
	assert_eq(fx.server.economy.ledger.total(), balances)
	var dropped: int = 0
	var collected: int = 0
	var expired: int = 0
	for e: Dictionary in fx.events:
		match e["type"]:
			&"chips_dropped":
				dropped += int(e["amount"])
			&"chips_collected":
				collected += int(e["amount"])
			&"pickup_expired":
				expired += int(e["amount"])
	assert_eq(dropped, collected + expired + fx.server.pickups.total_on_floor())
	for e: Dictionary in fx.events:
		assert_eq(GameEvents.validate(e), [] as Array[String], str(e))
	assert_eq(Log.error_count, 0)
