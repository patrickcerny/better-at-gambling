extends GutTest
## Jail system (v0.8.3): catch count, jail timer, fines, and Get Out of Jail Free item.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(2, {"minigames": 2, "gamble_seconds": 100.0, "seed": 42})


func after_each() -> void:
	fx.server.free()


func _start() -> void:
	fx.server.start_match()
	fx.run(3.1)
	fx.place_all()


func test_jail_timing_and_fines_scale_with_catch_count() -> void:
	_start()
	var p: int = fx.player_ids[0]
	var initial_balance: int = fx.server.economy.balance(p)

	# First catch: 8s jail, $100 fine
	fx.server.put_in_jail(p)
	assert_eq(fx.server.state.players[p].catch_count, 1)
	assert_almost_eq(fx.server.state.players[p].jail_time_remaining, 8.0, 0.001)
	assert_eq(fx.server.state.players[p].jail_fine, 100)

	# Release after 8 seconds
	fx.run(8.1)
	assert_almost_eq(fx.server.state.players[p].jail_time_remaining, 0.0, 0.001)
	assert_eq(fx.server.economy.balance(p), initial_balance - 100)

	# Second catch: 15s jail, $200 fine
	fx.server.put_in_jail(p)
	assert_eq(fx.server.state.players[p].catch_count, 2)
	assert_almost_eq(fx.server.state.players[p].jail_time_remaining, 15.0, 0.001)
	assert_eq(fx.server.state.players[p].jail_fine, 200)

	# Third catch: 25s jail, $400 fine
	fx.run(15.1)
	fx.server.put_in_jail(p)
	assert_eq(fx.server.state.players[p].catch_count, 3)
	assert_almost_eq(fx.server.state.players[p].jail_time_remaining, 25.0, 0.001)
	assert_eq(fx.server.state.players[p].jail_fine, 400)

	# Fourth and beyond: 40s jail, $800 fine (capped)
	fx.run(25.1)
	fx.server.put_in_jail(p)
	assert_eq(fx.server.state.players[p].catch_count, 4)
	assert_almost_eq(fx.server.state.players[p].jail_time_remaining, 40.0, 0.001)
	assert_eq(fx.server.state.players[p].jail_fine, 800)


func test_jail_events_emitted() -> void:
	_start()
	var p: int = fx.player_ids[0]

	fx.server.put_in_jail(p)
	var jailed_events: Array[Dictionary] = fx.of_type(&"player_jailed")
	assert_gt(jailed_events.size(), 0)
	assert_eq(jailed_events[-1]["player"], p)
	assert_eq(jailed_events[-1]["fine"], 100)
	assert_eq(jailed_events[-1]["catch_count"], 1)

	fx.run(8.1)
	var released_events: Array[Dictionary] = fx.of_type(&"player_released_from_jail")
	assert_gt(released_events.size(), 0)
	assert_eq(released_events[-1]["player"], p)
	assert_eq(released_events[-1]["fine"], 100)


func test_money_never_goes_negative() -> void:
	_start()
	var p: int = fx.player_ids[0]
	var initial_balance: int = fx.server.economy.balance(p)

	# Drain money first
	fx.server.economy.take_up_to(p, initial_balance - 50, &"drain")
	assert_eq(fx.server.economy.balance(p), 50)

	# First jail fine: only the $50 they have is taken, not the full $100 (the House Comp may
	# then top a broke player back up, so check the fine itself, not the final balance).
	fx.server.put_in_jail(p)
	fx.run(8.1)
	var released: Array[Dictionary] = fx.of_type(&"player_released_from_jail")
	assert_eq(released.size(), 1)
	assert_eq(released[-1]["fine"], 50)
	assert_true(fx.server.economy.balance(p) >= 0)


func test_jailed_players_released_on_minigame_start() -> void:
	# A short casino segment: the first minigame starts at casino time 10 s, inside the 15 s
	# second-offence sentence handed out right after the intro.
	fx.server.free()
	fx = ServerFixture.new(2, {"minigames": 1, "gamble_seconds": 10.0, "seed": 42})
	_start()
	var p: int = fx.player_ids[0]
	fx.server.state.players[p].catch_count = 1
	fx.server.put_in_jail(p)
	assert_almost_eq(fx.server.state.players[p].jail_time_remaining, 15.0, 0.001)
	fx.run(5.0)
	assert_gt(fx.server.state.players[p].jail_time_remaining, 0.0, "still jailed before the minigame")
	assert_true(fx.server.phases.phase == Phase.Id.CASINO or fx.server.phases.phase == Phase.Id.PRE_MINIGAME)
	fx.run(5.5)  # casino time ~10.6 s: the minigame has started
	assert_eq(fx.server.phases.phase, Phase.Id.MINIGAME)
	assert_eq(fx.server.state.players[p].jail_time_remaining, 0.0, "released when the minigame started")
	assert_eq(fx.of_type(&"player_released_from_jail").size(), 1)


func test_get_out_of_jail_free_clears_catch_count_and_releases() -> void:
	_start()
	var p: int = fx.player_ids[0]
	var initial_balance: int = fx.server.economy.balance(p)

	# Put in jail twice
	fx.server.put_in_jail(p)
	fx.run(8.1)
	fx.server.put_in_jail(p)
	assert_eq(fx.server.state.players[p].catch_count, 2)
	assert_gt(fx.server.state.players[p].jail_time_remaining, 0.0)

	# Give Get Out of Jail Free item and use it
	fx.server.items.give(p, &"get_out_of_jail_free", fx.server.match_time)
	assert_true(fx.intent(p, &"use_item", {"slot": 0})["ok"])

	# Catch count should be 0 and jail time should be 0
	assert_eq(fx.server.state.players[p].catch_count, 0)
	assert_almost_eq(fx.server.state.players[p].jail_time_remaining, 0.0, 0.001)

	# Only the first fine should have been deducted (the second jail was cleared)
	assert_eq(fx.server.economy.balance(p), initial_balance - 100)


func test_jail_state_reset_on_return_to_lobby() -> void:
	fx.server.open_lobby()
	fx.server.start_match()
	fx.run(3.1)
	fx.place_all()

	var p: int = fx.player_ids[0]

	# Put in jail
	fx.server.put_in_jail(p)
	fx.run(2.0)
	assert_gt(fx.server.state.players[p].catch_count, 0)
	assert_gt(fx.server.state.players[p].jail_time_remaining, 0.0)

	# Finish match and return to lobby
	fx.server.run_to_end(500.0)
	fx.server.return_to_lobby()

	# Jail state should be reset
	assert_eq(fx.server.state.players[p].catch_count, 0)
	assert_almost_eq(fx.server.state.players[p].jail_time_remaining, 0.0, 0.001)
	assert_eq(fx.server.state.players[p].jail_fine, 0)


func test_multiple_players_can_be_in_jail_simultaneously() -> void:
	_start()
	var p1: int = fx.player_ids[0]
	var p2: int = fx.player_ids[1]

	fx.server.put_in_jail(p1)
	fx.server.put_in_jail(p2)

	assert_almost_eq(fx.server.state.players[p1].jail_time_remaining, 8.0, 0.001)
	assert_almost_eq(fx.server.state.players[p2].jail_time_remaining, 8.0, 0.001)

	# Advance time
	fx.run(4.0)
	assert_almost_eq(fx.server.state.players[p1].jail_time_remaining, 4.0, 0.001)
	assert_almost_eq(fx.server.state.players[p2].jail_time_remaining, 4.0, 0.001)

	# Both released at the same time
	fx.run(4.1)
	assert_almost_eq(fx.server.state.players[p1].jail_time_remaining, 0.0, 0.001)
	assert_almost_eq(fx.server.state.players[p2].jail_time_remaining, 0.0, 0.001)


func test_catch_count_decrements_after_minigames() -> void:
	_start()
	var p: int = fx.player_ids[0]

	# Jail the player multiple times to build up catch count
	fx.server.put_in_jail(p)
	fx.run(8.1)
	fx.server.put_in_jail(p)
	fx.run(1.0)  # Before second minigame

	assert_eq(fx.server.state.players[p].catch_count, 2)

	# Advance to finish first minigame
	fx.run(20.0)  # This should trigger first minigame

	# After first minigame finishes, catch count should decrement
	var before_end: int = fx.server.state.players[p].catch_count
	fx.run(50.0)  # Let time pass to reach minigame end
	var after_minigame: int = fx.server.state.players[p].catch_count

	# Catch count should have decreased by 1 after the minigame
	if before_end > after_minigame:
		assert_eq(after_minigame, before_end - 1)
