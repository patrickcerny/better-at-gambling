extends GutTest
## Odd Jobs cabinet through the real MatchServer: a broke player smashes the button for $50, two
## players fill the one shared bar and the click that completes it is paid, a rich one is refused,
## and minigames-only matches have no odd jobs.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(2, {"minigames": 2, "gamble_seconds": 100.0, "seed": 4})
	fx.server.map_def = fx.server.map_def.duplicate(true)
	fx.server.map_def.odd_jobs_position = LuckyLounge.ODD_JOBS_POS
	fx.server.start_match()
	fx.run(3.1)
	fx.place_all(LuckyLounge.ODD_JOBS_POS)


func after_each() -> void:
	fx.server.free()


func test_broke_player_smashes_for_50() -> void:
	var p: int = fx.player_ids[0]
	fx.server.economy.take_up_to(p, 1000000, &"test")
	fx.run(0.2)  # a House Comp may land first: measure from whatever they have now
	var before: int = fx.server.economy.balance(p)
	assert_lt(before, OddJobs.CAP)
	var needed: int = OddJobs.presses_needed(before)
	for i: int in needed - 1:
		assert_true(fx.intent(p, &"odd_jobs_press")["ok"])
		fx.run(0.1)
	assert_eq(fx.server.economy.balance(p), before, "not paid before the bar is full")
	assert_false(fx.of_type(&"odd_jobs_bar").is_empty())
	assert_true(fx.intent(p, &"odd_jobs_press")["ok"])
	assert_eq(fx.server.economy.balance(p), before + 50)
	var pay: Array[Dictionary] = fx.of_type(&"odd_jobs_payout")
	assert_eq(pay.size(), 1)
	assert_eq(int(pay[0]["balance"]), before + 50)
	var money: Array[Dictionary] = fx.of_type(&"money_changed").filter(func(e: Dictionary) -> bool: return e["reason"] == &"odd_jobs")
	assert_eq(money.size(), 1, "paid through the normal balance path")


func test_shared_bar_pays_the_player_whose_click_completes_it() -> void:
	var alice: int = fx.player_ids[0]
	var bob: int = fx.player_ids[1]
	for p: int in [alice, bob]:
		fx.server.economy.take_up_to(p, 1000000, &"test")
	fx.run(0.2)  # House Comps may land first: put both back on known balances below the cap
	fx.server.economy.take_up_to(alice, 1000000, &"test")
	fx.server.economy.take_up_to(bob, 1000000, &"test")
	fx.server.economy.apply(alice, 100, &"test")  # 20 clicks a bar for Alice
	fx.server.economy.apply(bob, 250, &"test")  # 35 clicks a bar for Bob
	var share_a: float = 1.0 / OddJobs.presses_needed(100)
	var share_b: float = 1.0 / OddJobs.presses_needed(250)
	# Alice fills most of it; Bob's clicks top it off.
	var alice_clicks: int = 17
	for i: int in alice_clicks:
		assert_true(fx.intent(alice, &"odd_jobs_press")["ok"])
		fx.run(0.05)
	assert_almost_eq(fx.server.odd_jobs.fill(), alice_clicks * share_a, 0.001)
	var bob_clicks: int = 0
	while fx.server.economy.balance(bob) == 250 and bob_clicks < 20:
		assert_true(fx.intent(bob, &"odd_jobs_press")["ok"])
		bob_clicks += 1
		fx.run(0.05)
	assert_eq(bob_clicks, ceili((1.0 - alice_clicks * share_a) / share_b - 0.0001), "Bob's own share per click")
	assert_eq(fx.server.economy.balance(bob), 300, "Bob's click completed the bar: Bob gets the $50")
	assert_eq(fx.server.economy.balance(alice), 100, "Alice clicked more but not last: nothing")
	var pay: Array[Dictionary] = fx.of_type(&"odd_jobs_payout")
	assert_eq(pay.size(), 1)
	assert_eq(int(pay[0]["player"]), bob)
	assert_eq(fx.server.odd_jobs.fill(), 0.0, "the bar starts over")
	var bars: Array[Dictionary] = fx.of_type(&"odd_jobs_bar")
	assert_true(bars.any(func(e: Dictionary) -> bool: return int(e["player"]) == alice), "everyone sees Alice's clicks")
	assert_eq(float(bars.back()["fill"]), 0.0)


func test_a_burst_of_clicks_all_counts() -> void:
	# No rate limit anywhere on the way (validator or cabinet): 30 presses in one tick all land.
	var p: int = fx.player_ids[0]
	fx.server.economy.apply(p, 499 - fx.server.economy.balance(p), &"test")
	var needed: int = OddJobs.presses_needed(fx.server.economy.balance(p))
	assert_eq(needed, 60)
	for i: int in 30:
		assert_true(fx.intent(p, &"odd_jobs_press")["ok"], "press %d" % i)
	assert_almost_eq(fx.server.odd_jobs.fill(), 30.0 / needed, 0.001)


func test_rich_player_is_refused() -> void:
	var p: int = fx.player_ids[1]
	if fx.server.economy.balance(p) < OddJobs.CAP:
		fx.server.economy.apply(p, OddJobs.CAP, &"test")
	var before: int = fx.server.economy.balance(p)
	var res: Dictionary = fx.intent(p, &"odd_jobs_press")
	assert_false(res["ok"])
	assert_eq(res["error"], &"enough_money")
	assert_eq(fx.server.economy.balance(p), before)


func test_too_far_from_the_cabinet() -> void:
	var p: int = fx.player_ids[0]
	fx.server.world.set_transform(p, Vector3.ZERO, 0.0)
	assert_eq(fx.intent(p, &"odd_jobs_press")["error"], &"too_far")


func test_minigames_only_has_no_odd_jobs() -> void:
	var s := MatchServer.new()
	s.configure({"minigames": 2, "seed": 6, "mode": "minigames", "minigame_briefing": 0.0, "minigame_pool": "quiz"}, Registry.balance, Registry.presets, Registry.game_logic_scripts(), Registry.maps[&"lucky_lounge"])
	var p: int = s.add_player("uid-1", "Me")
	s.start_match()
	s.advance(4.0)
	var before: int = s.economy.balance(p)
	var res: Dictionary = s.submit_intent(p, Intents.make(&"odd_jobs_press"))
	assert_false(res["ok"])
	assert_eq(res["error"], &"money_off")
	assert_eq(s.economy.balance(p), before)
	s.free()
