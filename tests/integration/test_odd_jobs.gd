extends GutTest
## Odd Jobs cabinet through the real MatchServer: a broke player smashes the button for $50, a rich
## one is refused, and minigames-only matches have no odd jobs.

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
