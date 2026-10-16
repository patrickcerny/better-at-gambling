extends GutTest
## Bouncer, Jackpot Magnet and Sunglasses through the real MatchServer: intents in,
## money and seats out.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(3, {"minigames": 2, "gamble_seconds": 100.0, "seed": 8})
	fx.server.start_match()
	fx.run(3.1)


func after_each() -> void:
	fx.server.free()


func test_bouncer_unseats_and_blocks_sitting_for_a_while() -> void:
	var p: int = fx.player_ids[0]
	var q: int = fx.player_ids[1]
	assert_true(fx.intent(q, &"sit", {"station": &"blackjack_1"})["ok"])
	fx.server.items.give(p, &"bouncer", fx.server.match_time)
	var r: Dictionary = fx.intent(p, &"use_item", {"slot": 0, "target": q})
	assert_true(r["ok"], str(r))
	assert_eq(fx.server.stations.station_of(q), &"", "off the seat")
	fx.run(1.5)
	assert_eq(fx.intent(q, &"sit", {"station": &"blackjack_1"})["error"], &"bounced")
	fx.run(Registry.items[&"bouncer"].duration)
	assert_true(fx.intent(q, &"sit", {"station": &"blackjack_1"})["ok"])


func test_jackpot_magnet_pays_on_another_players_win() -> void:
	var p: int = fx.player_ids[0]
	var q: int = fx.player_ids[1]
	fx.server.items.give(p, &"jackpot_magnet", fx.server.match_time)
	assert_true(fx.intent(p, &"use_item", {"slot": 0})["ok"])
	fx.run(0.1)
	var before: int = fx.server.economy.balance(p)
	# A settled win at a table, as the station reports it.
	fx.server.stations.logics[&"blackjack_1"].events.append(GameEvents.round_result(&"blackjack_1", q, 100, 300))
	fx.run(0.2)
	assert_eq(fx.server.economy.balance(p), before + 20, "10% of the $200 profit")
	assert_eq(fx.of_type(&"magnet_bonus").size(), 1)


func test_sunglasses_used_before_sitting_show_the_hole_card() -> void:
	var p: int = fx.player_ids[0]
	fx.server.items.give(p, &"sunglasses", fx.server.match_time)
	assert_true(fx.intent(p, &"use_item", {"slot": 0})["ok"], "used while walking")
	fx.run(5.0)
	assert_true(fx.intent(p, &"sit", {"station": &"blackjack_1"})["ok"])
	assert_true(fx.intent(p, &"place_bet", {"station": &"blackjack_1", "bet": {"amount": 20}})["ok"])
	fx.run(Registry.balance.bj_betting_window + 0.5)
	var pub: Dictionary = fx.server.stations.public_states()[&"blackjack_1"]
	if bool(pub["dealer_revealed"]):
		pass_test("the round already ended on a natural")
		return
	var priv: Dictionary = fx.server.get_private_snapshot(p)["station"]
	assert_true(priv.has("hole_card"), "the hole card reaches the wearer: %s" % priv)
	assert_false(fx.server.get_private_snapshot(fx.player_ids[1])["station"].has("hole_card"))
