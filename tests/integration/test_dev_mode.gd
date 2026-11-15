extends GutTest
## Developer mode (Patrick: "add a developer mode for me so i can check out everything fast. IDK
## how to do that smartly so not everyone can do it"): only Patrick's SteamID64 (`DevMode`), the
## profile tools, the dev practice settings, and the Practice-server tools (money, items, the next
## minigame now).

var _old_profile: PlayerProfile


func before_each() -> void:
	DevMode.forced = -1
	DevMode.used = false
	_old_profile = ProfileManager.profile
	ProfileManager.profile = PlayerProfile.new()


func after_each() -> void:
	DevMode.forced = -1
	DevMode.used = false
	ProfileManager.set_dev_unlock_all(false)
	ProfileManager.profile = _old_profile


func test_only_listed_steam_accounts() -> void:
	assert_false(DevMode.is_dev_id(0), "no Steam: never")
	assert_false(DevMode.is_dev_id(76561190000000002), "a friend's account: no")
	for id: int in DevMode.STEAM_IDS:
		assert_true(DevMode.is_dev_id(id))
	assert_false(DevMode.allowed(), "tests run without Steam: off")
	DevMode.forced = 1
	assert_true(DevMode.allowed())


func test_coins_levels_and_every_cosmetic() -> void:
	var p: PlayerProfile = ProfileManager.profile
	DevMode.add_coins(10000)
	assert_eq(p.coins, 10000)
	assert_true(DevMode.used, "achievements off from now on")
	DevMode.set_level(12)
	assert_eq(p.level, 12)
	DevMode.set_level(500)
	assert_eq(p.level, p.config.max_level, "clamped to the max level")
	var paid: CosmeticDef = null
	for d: CosmeticDef in p.shop.items:
		if not d.is_free():
			paid = d
			break
	assert_not_null(paid)
	if paid == null:
		return
	assert_false(p.owns(paid.id))
	DevMode.set_unlock_all(true)
	assert_true(ProfileManager.profile.owns(paid.id), "every piece owned")
	assert_false(paid.id in ProfileManager.profile.owned, "nothing is bought")
	ProfileManager.reload()
	assert_true(ProfileManager.profile.owns(paid.id), "until the game closes, not until the next reload")
	DevMode.set_unlock_all(false)
	assert_false(ProfileManager.profile.owns(paid.id), "off again: back to what is really owned")


func test_achievements_stay_off_after_dev_use() -> void:
	DevMode.mark_used()
	assert_eq(SteamSvc.unlock_achievements([&"ACH_FIRST_MATCH"]), [] as Array[StringName])


func test_practice_settings() -> void:
	var casino: Dictionary = DevMode.casino_settings(3)
	assert_eq(casino["mode"], MatchMode.CASINO)
	assert_eq(casino["dummies"], 3)
	assert_true(casino["dev"])
	var vr: Dictionary = DevMode.minigame_settings(&"vote_race", 0)
	assert_eq(vr["mode"], MatchMode.MINIGAMES)
	assert_eq(vr["minigame_pool"], "vote_race")
	assert_eq(vr["minigames"], 1)
	assert_gte(int(vr["dummies"]) + 1, (Registry.minigames[&"vote_race"] as MinigameDefinition).min_players, "enough dummies for it to run")


func test_a_dev_minigame_settings_match_plays_that_game() -> void:
	var fx := ServerFixture.new(4, {"minigames": 1, "gamble_seconds": 5.0, "seed": 2, "mode": "minigames", "minigame_pool": "spy", "minigame_briefing": 0.0})
	fx.server.start_match()
	fx.run(10.0)
	var started: Array[Dictionary] = fx.of_type(&"minigame_started")
	assert_eq(started.size(), 1)
	if not started.is_empty():
		assert_eq(str(started[0]["minigame"]), "spy")
	fx.server.free()


func test_server_money_items_and_minigame_now() -> void:
	var fx := ServerFixture.new(4, {"minigames": 3, "gamble_seconds": 200.0, "seed": 5, "minigame_briefing": 0.0, "minigame_pool": ""})
	var srv: MatchServer = fx.server
	var me: int = fx.player_ids[0]
	srv.start_match()
	fx.run(4.0)
	assert_eq(srv.phases.phase, Phase.Id.CASINO)
	var before: int = srv.economy.balance(me)
	assert_true(srv.dev_give_money(me, 10000))
	assert_eq(srv.economy.balance(me), before + 10000)
	srv.dev_give_money(me, -1000000)
	assert_eq(srv.economy.balance(me), 0, "taking never goes below zero")
	assert_true(srv.dev_give_item(me, &"scissors"))
	assert_has(srv.state.players[me].inventory, &"scissors")
	assert_true(srv.dev_minigame_now(&"lonely_number"))
	fx.run(3.0)
	var started: Array[Dictionary] = fx.of_type(&"minigame_started")
	assert_eq(started.size(), 1, "the minigame came straight away")
	if not started.is_empty():
		assert_eq(str(started[0]["minigame"]), "lonely_number", "the one picked")
	assert_false(srv.dev_minigame_now(), "not while a minigame runs")
	fx.server.free()


func test_forced_minigame_needs_enough_players() -> void:
	var dir := MinigameDirector.new(MinigameDirector.pool_defs(Registry.minigames, ""), Registry.quiz_bank)
	dir.forced_next = &"vote_race"
	var d: MinigameDefinition = dir.pick(SeededRng.new(1), 1)
	assert_true(d == null or d.id != &"vote_race", "too few players: the normal pick")
	assert_eq(dir.forced_next, &"", "used up either way")
	dir.forced_next = &"vote_race"
	assert_eq(dir.pick(SeededRng.new(1), 6).id, &"vote_race")
