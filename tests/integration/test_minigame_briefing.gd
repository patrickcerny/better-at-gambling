extends GutTest
## The rules briefing before a minigame (0.8.13) and the Lonely Number intent it guards: the
## minigame stands still until everyone sent `minigame_ready` or the briefing time runs out, and
## picks sent through the real intent schema decide a round (the 0.8.12 bug: the stage's picks
## never reached the logic, so no number ever won).

var fx: ServerFixture


func after_each() -> void:
	if fx != null:
		fx.server.free()
		fx = null


func _start(briefing: float, players: int = 2) -> void:
	fx = ServerFixture.new(players, {"minigames": 1, "gamble_seconds": 5.0, "seed": 1, "minigame_pool": "lonely_number", "minigame_briefing": briefing})
	fx.server.start_match()
	fx.run(3.1 + 5.0 + 0.2)  # intro, the casino segment, into the minigame
	assert_eq(fx.server.phases.phase, Phase.Id.MINIGAME)
	assert_true(fx.server.minigame is LonelyNumberLogic)


func _logic() -> LonelyNumberLogic:
	return fx.server.minigame as LonelyNumberLogic


func test_briefing_holds_the_minigame_until_everyone_is_ready() -> void:
	_start(30.0)
	var started: Array[Dictionary] = fx.of_type(&"minigame_started")
	assert_eq(started.size(), 1)
	assert_almost_eq(float(started[0]["briefing"]), 30.0, 0.001)
	assert_true(fx.server.in_briefing())
	fx.run(5.0)
	assert_almost_eq(_logic().timer, LonelyNumberLogic.PICK_SECONDS, 0.001, "the pick timer has not started")
	assert_eq(fx.intent(fx.player_ids[0], &"lonely_number_pick", {"number": 7})["error"], &"too_early")
	assert_true(fx.intent(fx.player_ids[0], &"minigame_ready")["ok"])
	assert_true(fx.intent(fx.player_ids[0], &"minigame_ready")["ok"], "ready twice is harmless")
	var ready: Array[Dictionary] = fx.of_type(&"minigame_ready")
	assert_eq(ready.size(), 1)
	assert_eq(ready[0]["ready"], [fx.player_ids[0]])
	assert_eq(fx.of_type(&"minigame_go").size(), 0, "one player still reading")
	assert_true(fx.intent(fx.player_ids[1], &"minigame_ready")["ok"])
	assert_eq(fx.of_type(&"minigame_go").size(), 1, "everyone ready: go")
	assert_false(fx.server.in_briefing())
	assert_eq(fx.intent(fx.player_ids[1], &"minigame_ready")["error"], &"too_late")
	var snap: Dictionary = fx.server.get_snapshot()
	assert_false((snap["minigame"] as Dictionary).has("briefing"))
	fx.run(1.0)
	assert_lt(_logic().timer, LonelyNumberLogic.PICK_SECONDS, "the minigame runs now")


func test_briefing_times_out_and_shows_in_the_snapshot() -> void:
	_start(30.0)
	fx.run(10.0)
	var snap: Dictionary = fx.server.get_snapshot()
	var brief: Dictionary = (snap["minigame"] as Dictionary)["briefing"]
	assert_almost_eq(float(brief["left"]), 20.0, 0.5)
	assert_eq(brief["ready"], [])
	fx.run(20.1)
	assert_eq(fx.of_type(&"minigame_go").size(), 1, "30 s passed: it starts without everyone")
	assert_false(fx.server.in_briefing())
	assert_eq(Log.error_count, 0)


func test_briefing_does_not_wait_for_a_player_who_left() -> void:
	_start(30.0, 3)
	assert_true(fx.intent(fx.player_ids[0], &"minigame_ready")["ok"])
	assert_true(fx.intent(fx.player_ids[1], &"minigame_ready")["ok"])
	assert_eq(fx.of_type(&"minigame_go").size(), 0)
	fx.server.player_disconnected(fx.player_ids[2])
	assert_eq(fx.of_type(&"minigame_go").size(), 1)


func test_lonely_number_picks_through_the_intent_schema_decide_the_round() -> void:
	_start(0.0)
	assert_false(fx.server.in_briefing(), "no briefing when it is set to 0")
	var p1: int = fx.player_ids[0]
	var p2: int = fx.player_ids[1]
	# The exact payload the stage sends.
	var r1: Dictionary = fx.server.submit_intent(p1, Intents.make(&"lonely_number_pick", {"number": 7}))
	assert_true(r1["ok"], str(r1))
	var r2: Dictionary = fx.server.submit_intent(p2, Intents.make(&"lonely_number_pick", {"number": 12}))
	assert_true(r2["ok"], str(r2))
	assert_eq(fx.of_type(&"lonely_number_picked").size(), 2)
	fx.run(0.1)
	var ends: Array[Dictionary] = fx.of_type(&"lonely_number_round_end")
	assert_eq(ends.size(), 1, "both picked: the round ends at once")
	assert_eq(int(ends[0]["lonely_number"]), 12, "the highest number only one player picked")
	assert_eq(int(ends[0]["winner"]), p2)
	assert_eq(int((fx.server.minigame as LonelyNumberLogic).wins[p2]), 1)
	# An invalid payload never reaches the logic (the old `submit_answer` route failed like this).
	assert_eq(fx.server.submit_intent(p1, {"type": &"lonely_number_pick"})["error"], &"malformed")
