extends GutTest
## Bust or Bank through the real match server and intent schema: HIT / STAND go through
## `bust_or_bank_action`, the snapshot carries the table (round, survivors, who is out), idle
## players are stood by the 20 s turn timer, the elimination rounds play out and the placement
## ranking (points = players outlasted) reaches the minigame ranking.

var fx: ServerFixture


func after_each() -> void:
	if fx != null:
		fx.server.free()
		fx = null


func _start(briefing: float, players: int = 3) -> void:
	fx = ServerFixture.new(players, {"minigames": 1, "gamble_seconds": 5.0, "seed": 2, "minigame_pool": "bust_or_bank", "minigame_briefing": briefing})
	fx.server.start_match()
	fx.run(3.1 + 5.0 + 0.2)  # intro, the casino segment, into the minigame
	assert_eq(fx.server.phases.phase, Phase.Id.MINIGAME)
	assert_true(fx.server.minigame is BustOrBankLogic)


func _logic() -> BustOrBankLogic:
	return fx.server.minigame as BustOrBankLogic


func test_actions_are_held_during_the_briefing() -> void:
	_start(30.0)
	assert_eq(fx.intent(fx.player_ids[0], &"bust_or_bank_action", {"action": "hit"})["error"], &"too_early")


func test_hit_and_stand_through_the_intent_schema() -> void:
	_start(0.0)
	fx.run(BustOrBankLogic.INTRO_TIME + 0.1)
	var logic: BustOrBankLogic = _logic()
	assert_eq(logic.state, BustOrBankLogic.State.TURN)
	var first: int = logic.current
	assert_eq(first, logic.order[0], "seat order starts")
	for p: int in logic.order:
		assert_eq(logic.hands[p].size(), 1, "one card each")
	var snap: Dictionary = fx.server.get_snapshot()
	var mg: Dictionary = snap["minigame"]
	assert_eq(int(mg["current"]), first)
	assert_true((mg["hands"] as Dictionary).size() == logic.order.size(), "every hand is public")
	assert_false(mg.has("next_card"), "the next card never reaches clients")
	var other: int = logic.order[1]
	assert_eq(fx.intent(other, &"bust_or_bank_action", {"action": "hit"})["error"], &"not_your_turn")
	# The exact payload the stage sends.
	var r: Dictionary = fx.server.submit_intent(first, Intents.make(&"bust_or_bank_action", {"action": "hit"}))
	assert_true(r["ok"], str(r))
	assert_eq(logic.hands[first].size(), 2)
	assert_eq(logic.current, other, "the turn passes on")
	assert_true(fx.server.submit_intent(other, Intents.make(&"bust_or_bank_action", {"action": "stand"}))["ok"])
	assert_true(logic.standing[other])
	assert_eq(fx.server.submit_intent(first, {"type": &"bust_or_bank_action"})["error"], &"malformed")
	fx.run(0.1)
	assert_gt(fx.of_type(&"bust_or_bank_card").size(), 3)
	assert_gt(fx.of_type(&"bust_or_bank_turn").size(), 1)


func test_idle_table_plays_elimination_rounds_and_ranks_everyone() -> void:
	_start(0.0)
	var logic: BustOrBankLogic = _logic()
	var waited: float = 0.0
	while fx.of_type(&"minigame_finished").is_empty() and waited < BustOrBankLogic.GAME_CAP + 30.0:
		fx.run(1.0)
		waited += 1.0
		if logic.round_no == 2 and logic.state == BustOrBankLogic.State.TURN and not logic.out_round.is_empty():
			var mg: Dictionary = fx.server.get_snapshot()["minigame"]
			assert_eq(int(mg["round"]), 2, "the snapshot knows the round")
			assert_eq((mg["survivors"] as Array).size(), logic.alive.size())
			assert_eq((mg["out"] as Dictionary).size(), logic.out_round.size(), "and who is out")
			assert_false(mg.has("next_card"))
	var done: Array[Dictionary] = fx.of_type(&"minigame_finished")
	assert_eq(done.size(), 1)
	var ends: Array[Dictionary] = fx.of_type(&"bust_or_bank_round_end")
	assert_between(ends.size(), 1, 2, "3 players: at most 2 rounds")
	assert_true(bool(ends.back()["final"]))
	assert_eq(fx.of_type(&"bust_or_bank_finished").size(), 1)
	var ranking: Array = done[0]["ranking"]
	assert_eq(ranking.size(), 3)
	assert_eq(int(ranking[0]["rank"]), 1)
	assert_lte(int(ranking[0]["points"]), 2, "placement points: players outlasted")
	assert_eq(int(ranking[2]["points"]), 0, "last place outlasted nobody")
	assert_eq(Log.error_count, 0)
