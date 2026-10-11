extends GutTest
## Split or Steal through the real match server and intent schema: nothing of the show goes out
## with `minigame_started` (the stage is built behind the curtain after it: the first-round bug),
## the show begins after the briefing, picks go through `split_or_steal_pick`, watchers are
## refused, the snapshot carries the schedule and the ranking reaches the minigame ranking.

var fx: ServerFixture


func after_each() -> void:
	if fx != null:
		fx.server.free()
		fx = null


func _start(briefing: float, players: int = 3) -> void:
	fx = ServerFixture.new(players, {"minigames": 1, "gamble_seconds": 5.0, "seed": 2, "minigame_pool": "split_or_steal", "minigame_briefing": briefing})
	fx.server.start_match()
	fx.run(3.1 + 5.0 + 0.2)  # intro, the casino segment, into the minigame
	assert_eq(fx.server.phases.phase, Phase.Id.MINIGAME)
	assert_true(fx.server.minigame is SplitOrStealLogic)


func _logic() -> SplitOrStealLogic:
	return fx.server.minigame as SplitOrStealLogic


func test_nothing_goes_out_with_minigame_started_and_picks_wait_for_the_briefing() -> void:
	_start(30.0)
	assert_eq(fx.of_type(&"split_or_steal_pair").size(), 0, "no match before the stage exists")
	assert_eq(fx.of_type(&"split_or_steal_started").size(), 0)
	assert_eq(fx.intent(fx.player_ids[0], &"split_or_steal_pick", {"choice": "SPLIT"})["error"], &"too_early")
	var snap: Dictionary = fx.server.get_snapshot()
	assert_eq((snap["minigame"]["schedule"] as Array).size(), 3, "the schedule is in the snapshot already")


func test_pair_by_pair_through_the_intent_schema() -> void:
	_start(0.0)
	fx.run(SplitOrStealLogic.INTRO_TIME + SplitOrStealLogic.ANNOUNCE_TIME + 0.2)
	var logic: SplitOrStealLogic = _logic()
	assert_eq(logic.state, SplitOrStealLogic.State.DECIDE)
	assert_eq(fx.of_type(&"split_or_steal_started").size(), 1)
	var pairs: Array[Dictionary] = fx.of_type(&"split_or_steal_pair")
	assert_eq(pairs.size(), 1, "one pair at a time")
	var pair: Array[int] = logic.current_pair()
	assert_eq([int(pairs[0]["a"]), int(pairs[0]["b"])], [pair[0], pair[1]])
	var watcher: int = -1
	for p: int in fx.player_ids:
		if p not in pair:
			watcher = p
	assert_eq(fx.intent(watcher, &"split_or_steal_pick", {"choice": "STEAL"})["error"], &"not_your_turn")
	var mg: Dictionary = fx.server.get_snapshot()["minigame"]
	assert_eq(int(mg["index"]), 0)
	var priv: Dictionary = fx.server.get_private_snapshot(pair[0])["minigame"]
	assert_true(priv["can_choose"])
	assert_eq(priv["pair"], pair)
	# The exact payload the stage sends.
	assert_true(fx.server.submit_intent(pair[0], Intents.make(&"split_or_steal_pick", {"choice": "STEAL"}))["ok"])
	assert_true(fx.server.submit_intent(pair[1], Intents.make(&"split_or_steal_pick", {"choice": "SPLIT"}))["ok"])
	fx.run(0.1)
	var rev: Array[Dictionary] = fx.of_type(&"split_or_steal_reveal")
	assert_eq(rev.size(), 1)
	assert_eq(int(rev[0]["points_a"]), 3)
	assert_eq(logic.points[pair[0]], 3)


func test_show_finishes_and_ranks() -> void:
	_start(0.0, 4)
	fx.run(SplitOrStealLogic.GAME_CAP + 2.0)
	assert_ne(fx.server.phases.phase, Phase.Id.MINIGAME, "the show is over")
	var fin: Array[Dictionary] = fx.of_type(&"minigame_finished")
	assert_eq(fin.size(), 1)
	assert_eq((fin[0]["ranking"] as Array).size(), 4)
	assert_eq(fx.of_type(&"split_or_steal_reveal").size(), 4, "4 players: 4 matches")
