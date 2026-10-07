extends GutTest
## Out of Order sign and Gift Shop through the real MatchServer.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(3, {"minigames": 2, "gamble_seconds": 100.0, "seed": 8})
	fx.server.start_match()
	fx.run(3.1)


func after_each() -> void:
	fx.server.free()


func test_out_of_order_blocks_the_nearest_table_then_expires() -> void:
	var p: int = fx.player_ids[0]
	var q: int = fx.player_ids[1]
	var sid: StringName = &"roulette_1"
	var pos: Vector3 = Vector3(4, 0, 4)
	# Filled in by the map scene in the real game; a copy so the shared map resource stays clean.
	fx.server.map_def = fx.server.map_def.duplicate(true)
	fx.server.map_def.station_positions[sid] = pos
	fx.server.world.set_transform(p, pos, 0.0)
	fx.server.world.set_transform(q, pos, 0.0)
	fx.server.items.give(p, &"out_of_order", fx.server.match_time)
	var r: Dictionary = fx.intent(p, &"use_item", {"slot": 0})
	assert_true(r["ok"], str(r))
	assert_true(fx.server.stations.public_states()[sid].has("out_of_order"))
	assert_eq(fx.intent(q, &"sit", {"station": sid})["error"], &"out_of_order")
	fx.run(Registry.items[&"out_of_order"].duration + 0.5)
	assert_false(fx.server.stations.out_of_order.has(sid))
	assert_true(fx.intent(q, &"sit", {"station": sid})["ok"])


func test_out_of_order_needs_a_table_nearby() -> void:
	var p: int = fx.player_ids[0]
	fx.server.world.set_transform(p, Vector3(0, 0, 200), 0.0)
	fx.server.items.give(p, &"out_of_order", fx.server.match_time)
	assert_eq(fx.intent(p, &"use_item", {"slot": 0})["error"], &"no_station")


func test_shop_is_stocked_and_sells() -> void:
	var shop: Dictionary = fx.server.get_snapshot()["shop"]
	assert_eq((shop["offers"] as Array).size(), GiftShop.OFFERS)
	assert_false(fx.of_type(&"shop_restocked").is_empty())
	var p: int = fx.player_ids[2]
	var before: int = fx.server.economy.balance(p)
	assert_true(fx.intent(p, &"shop_buy", {"index": 0})["ok"])
	assert_eq(fx.server.economy.balance(p), before - int(shop["offers"][0]["price"]))
	assert_eq(fx.intent(p, &"shop_buy", {"index": 1})["error"], &"already_bought")
