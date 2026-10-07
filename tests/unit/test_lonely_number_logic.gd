extends GutTest
## Lonely Number rules (MINIGAME_IDEAS / §2.9.3): each round every player secretly picks 1-20; the
## highest number nobody else picked wins the round. 5 rounds; most round wins ranks first, ties go
## to the higher total of winning numbers.

var cfg: BalanceConfig = BalanceConfig.new()
var now: float = 0.0


func before_each() -> void:
	now = 0.0


func _game(players: Array[int]) -> LonelyNumberLogic:
	var g := LonelyNumberLogic.new()
	g.setup(players, SeededRng.new(7), cfg, {}, {})
	return g


## Everyone in `picks` (player → number) picks; returns the round_end event.
func _play_round(g: LonelyNumberLogic, picks: Dictionary) -> Dictionary:
	g.drain_events()
	for p: int in picks:
		assert_true(g.submit(p, {"number": picks[p]}, now)["ok"], "pick %d by %d accepted" % [picks[p], p])
	var ends: Array = _events_of(g.drain_events(), &"lonely_number_round_end")
	assert_eq(ends.size(), 1, "round ends once everyone picked")
	return ends[0] if not ends.is_empty() else {}


## Passes the reveal pause so the next round (or the end) begins.
func _skip_reveal(g: LonelyNumberLogic) -> void:
	g.tick(LonelyNumberLogic.REVEAL_SECONDS + 0.01, now)


func _events_of(evs: Array[Dictionary], type: StringName) -> Array:
	return evs.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _row(ranking: Array[Dictionary], player: int) -> Dictionary:
	for r: Dictionary in ranking:
		if r["player"] == player:
			return r
	return {}


# --- The lonely number --------------------------------------------------------------------------

func test_unique_highest_pick_wins_round() -> void:
	var g := _game([1, 2, 3])
	var ev: Dictionary = _play_round(g, {1: 5, 2: 12, 3: 20})
	assert_eq(ev["lonely_number"], 20)
	assert_eq(ev["winner"], 3)
	assert_eq(g.wins[3], 1)
	assert_eq(g.win_totals[3], 20)
	assert_eq(g.wins[1], 0)


func test_tied_highest_is_skipped_for_next_unique() -> void:
	var g := _game([1, 2, 3, 4])
	# 20 is picked twice, so the highest lonely number is 15.
	var ev: Dictionary = _play_round(g, {1: 20, 2: 20, 3: 15, 4: 3})
	assert_eq(ev["lonely_number"], 15)
	assert_eq(ev["winner"], 3)
	assert_eq(g.wins[1], 0, "shared 20 does not win")
	assert_eq(g.wins[2], 0)


func test_lower_unique_number_beats_shared_higher_numbers() -> void:
	var g := _game([1, 2, 3, 4, 5])
	var ev: Dictionary = _play_round(g, {1: 18, 2: 18, 3: 10, 4: 10, 5: 1})
	assert_eq(ev["lonely_number"], 1)
	assert_eq(ev["winner"], 5)


func test_all_same_number_nobody_wins() -> void:
	var g := _game([1, 2, 3])
	var ev: Dictionary = _play_round(g, {1: 7, 2: 7, 3: 7})
	assert_eq(ev["lonely_number"], -1)
	assert_eq(ev["winner"], -1)
	for p: int in [1, 2, 3]:
		assert_eq(g.wins[p], 0)
		assert_eq(g.win_totals[p], 0)


func test_all_numbers_paired_nobody_wins() -> void:
	var g := _game([1, 2, 3, 4])
	var ev: Dictionary = _play_round(g, {1: 9, 2: 9, 3: 14, 4: 14})
	assert_eq(ev["winner"], -1)


func test_lonely_number_helper() -> void:
	assert_eq(LonelyNumberLogic.lonely_number({}), -1)
	assert_eq(LonelyNumberLogic.lonely_number({1: 4}), 4)
	assert_eq(LonelyNumberLogic.lonely_number({1: 4, 2: 19, 3: 19, 4: 11}), 11)


func test_round_end_reveals_every_pick() -> void:
	var g := _game([1, 2])
	var ev: Dictionary = _play_round(g, {1: 3, 2: 8})
	assert_eq(ev["picks"], {1: 3, 2: 8})
	assert_eq(ev["wins"][2], 1)
	assert_eq(ev["totals"][2], 8)


# --- Rounds and ranking -------------------------------------------------------------------------

func test_wins_accumulate_over_rounds() -> void:
	var g := _game([1, 2])
	_play_round(g, {1: 10, 2: 4})
	_skip_reveal(g)
	_play_round(g, {1: 2, 2: 6})
	_skip_reveal(g)
	_play_round(g, {1: 17, 2: 1})
	assert_eq(g.wins[1], 2)
	assert_eq(g.win_totals[1], 27)
	assert_eq(g.wins[2], 1)
	assert_eq(g.win_totals[2], 6)
	assert_eq(g.history.size(), 3, "every round is recorded")


func test_five_rounds_then_finished() -> void:
	var g := _game([1, 2])
	for r: int in LonelyNumberLogic.ROUNDS:
		assert_false(g.is_finished(), "still playing before round %d" % (r + 1))
		assert_eq(g.round, r)
		_play_round(g, {1: r + 1, 2: 20})
		_skip_reveal(g)
	assert_true(g.is_finished())
	assert_eq(g.round, LonelyNumberLogic.ROUNDS)
	assert_eq(g.wins[2], 5)
	assert_eq(g.submit(1, {"number": 3}, now)["error"], &"game_over")


func test_not_finished_until_last_reveal_shown() -> void:
	var g := _game([1, 2])
	for r: int in LonelyNumberLogic.ROUNDS:
		_play_round(g, {1: 1, 2: 2})
		if r < LonelyNumberLogic.ROUNDS - 1:
			_skip_reveal(g)
	assert_false(g.is_finished(), "last round's reveal is still on screen")
	g.tick(LonelyNumberLogic.REVEAL_SECONDS * 0.5, now)
	assert_false(g.is_finished())
	_skip_reveal(g)
	assert_true(g.is_finished())
	var fin: Array = _events_of(g.drain_events(), &"lonely_number_finished")
	assert_eq(fin.size(), 1)
	assert_eq(fin[0]["ranking"][0]["player"], 2)


func test_spec_example_more_wins_beats_higher_total() -> void:
	# A wins with [5, 12, 20] (3 wins, total 37), B with [10, 15] (2 wins, total 25).
	var g := _game([1, 2, 3])
	var a: int = 1
	var b: int = 2
	_play_round(g, {a: 5, b: 3, 3: 3}); _skip_reveal(g)
	_play_round(g, {a: 12, b: 4, 3: 4}); _skip_reveal(g)
	_play_round(g, {a: 20, b: 1, 3: 1}); _skip_reveal(g)
	_play_round(g, {a: 2, b: 10, 3: 2}); _skip_reveal(g)
	_play_round(g, {a: 6, b: 15, 3: 6}); _skip_reveal(g)
	assert_true(g.is_finished())
	var ranking: Array[Dictionary] = g.ranking()
	assert_eq(ranking[0]["player"], a)
	assert_eq(ranking[0]["points"], 3)
	assert_eq(ranking[0]["total"], 37)
	assert_eq(ranking[1]["player"], b)
	assert_eq(ranking[1]["points"], 2)
	assert_eq(ranking[1]["total"], 25)
	assert_eq(ranking[2]["player"], 3)
	assert_eq(ranking[2]["points"], 0)
	assert_eq(ranking[2]["rank"], 3)


func test_tiebreak_on_wins_goes_to_higher_total() -> void:
	# Both win 2 rounds: player 2 with 5 + 7 = 12, player 1 with 18 + 19 = 37.
	var g := _game([1, 2, 3])
	_play_round(g, {1: 1, 2: 5, 3: 1}); _skip_reveal(g)
	_play_round(g, {1: 2, 2: 7, 3: 2}); _skip_reveal(g)
	_play_round(g, {1: 18, 2: 3, 3: 3}); _skip_reveal(g)
	_play_round(g, {1: 19, 2: 4, 3: 4}); _skip_reveal(g)
	_play_round(g, {1: 9, 2: 9, 3: 9}); _skip_reveal(g)  # nobody wins
	var ranking: Array[Dictionary] = g.ranking()
	assert_eq(ranking[0]["player"], 1, "equal wins: higher total ranks first")
	assert_eq(ranking[0]["points"], 2)
	assert_eq(ranking[0]["total"], 37)
	assert_eq(ranking[0]["rank"], 1)
	assert_eq(ranking[1]["player"], 2)
	assert_eq(ranking[1]["total"], 12)
	assert_eq(ranking[1]["rank"], 2)


func test_full_tie_shares_rank() -> void:
	var g := _game([1, 2, 3])
	for p: int in [1, 2, 3]:
		g.wins[p] = 1 if p == 3 else 2
		g.win_totals[p] = 20 if p == 3 else 30
	var ranking: Array[Dictionary] = g.ranking()
	assert_eq(_row(ranking, 1)["rank"], 1)
	assert_eq(_row(ranking, 2)["rank"], 1, "same wins and same total share first place")
	assert_eq(_row(ranking, 3)["rank"], 3)


func test_ranking_points_are_round_wins() -> void:
	var g := _game([1, 2])
	_play_round(g, {1: 14, 2: 2})
	var ranking: Array[Dictionary] = g.ranking()
	assert_eq(_row(ranking, 1)["points"], 1)
	assert_eq(_row(ranking, 2)["points"], 0)


# --- Pick validation ----------------------------------------------------------------------------

func test_out_of_range_picks_rejected() -> void:
	var g := _game([1, 2])
	assert_eq(g.submit(1, {"number": 0}, now)["error"], &"invalid_number")
	assert_eq(g.submit(1, {"number": 21}, now)["error"], &"invalid_number")
	assert_eq(g.submit(1, {}, now)["error"], &"invalid_number")
	assert_eq(g.submit(1, {"number": "twenty"}, now)["error"], &"invalid_number")
	assert_true(g.submit(1, {"number": 1}, now)["ok"], "1 is in range")
	assert_true(g.submit(2, {"number": 20}, now)["ok"], "20 is in range")


func test_double_pick_rejected() -> void:
	var g := _game([1, 2])
	assert_true(g.submit(1, {"number": 5}, now)["ok"])
	assert_eq(g.submit(1, {"number": 6}, now)["error"], &"already_picked")
	assert_eq(g.picks[1], 5, "first pick stands")


func test_unknown_player_rejected() -> void:
	var g := _game([1, 2])
	assert_eq(g.submit(99, {"number": 5}, now)["error"], &"unknown_player")


func test_pick_during_reveal_rejected() -> void:
	var g := _game([1, 2])
	_play_round(g, {1: 5, 2: 6})
	assert_eq(g.state, LonelyNumberLogic.State.REVEAL)
	assert_eq(g.submit(1, {"number": 3}, now)["error"], &"not_picking")
	_skip_reveal(g)
	assert_eq(g.state, LonelyNumberLogic.State.PICKING)
	assert_true(g.submit(1, {"number": 3}, now)["ok"])


func test_round_waits_for_everyone() -> void:
	var g := _game([1, 2, 3])
	g.drain_events()
	g.submit(1, {"number": 5}, now)
	g.submit(2, {"number": 6}, now)
	assert_eq(_events_of(g.drain_events(), &"lonely_number_round_end").size(), 0)
	assert_eq(g.round, 0)


# --- Timer and dropouts -------------------------------------------------------------------------

func test_timeout_ends_round_without_missing_pickers() -> void:
	var g := _game([1, 2, 3])
	g.drain_events()
	g.submit(1, {"number": 4}, now)
	g.submit(2, {"number": 4}, now)
	g.tick(LonelyNumberLogic.PICK_SECONDS + 0.01, now)
	var ends: Array = _events_of(g.drain_events(), &"lonely_number_round_end")
	assert_eq(ends.size(), 1, "timer ends the round")
	assert_eq(ends[0]["picks"], {1: 4, 2: 4}, "player 3 sat it out")
	assert_eq(ends[0]["winner"], -1)


func test_timeout_with_no_picks_still_advances() -> void:
	var g := _game([1, 2])
	g.tick(LonelyNumberLogic.PICK_SECONDS + 0.01, now)
	assert_eq(g.round, 1)
	_skip_reveal(g)
	assert_eq(g.state, LonelyNumberLogic.State.PICKING)


func test_idle_game_finishes_by_timer() -> void:
	var g := _game([1, 2])
	for i: int in 400:
		g.tick(0.25, now)
		if g.is_finished():
			break
	assert_true(g.is_finished(), "an AFK lobby cannot stall the minigame")


func test_dropout_ends_round_when_rest_picked() -> void:
	var g := _game([1, 2, 3])
	g.drain_events()
	g.submit(1, {"number": 8}, now)
	g.submit(2, {"number": 3}, now)
	g.remove_player(3)
	var ends: Array = _events_of(g.drain_events(), &"lonely_number_round_end")
	assert_eq(ends.size(), 1)
	assert_eq(ends[0]["winner"], 1)


func test_dropout_forfeits_pending_pick() -> void:
	var g := _game([1, 2, 3])
	g.submit(3, {"number": 20}, now)
	g.remove_player(3)
	assert_false(g.picks.has(3))
	assert_eq(g.ranking().size(), 2, "dropouts are not ranked")


# --- Events and state ---------------------------------------------------------------------------

func test_round_started_events() -> void:
	var g := _game([1, 2])
	var started: Array = _events_of(g.drain_events(), &"lonely_number_round_started")
	assert_eq(started.size(), 1)
	assert_eq(started[0]["round"], 0)
	assert_eq(started[0]["rounds"], 5)
	_play_round(g, {1: 1, 2: 2})
	_skip_reveal(g)
	started = _events_of(g.drain_events(), &"lonely_number_round_started")
	assert_eq(started.size(), 1)
	assert_eq(started[0]["round"], 1)


func test_picked_event_keeps_number_secret() -> void:
	var g := _game([1, 2])
	g.drain_events()
	g.submit(1, {"number": 13}, now)
	var picked: Array = _events_of(g.drain_events(), &"lonely_number_picked")
	assert_eq(picked.size(), 1)
	assert_eq(picked[0]["player"], 1)
	assert_false(picked[0].has("number"), "the pick stays secret until the reveal")


func test_public_state_hides_picks() -> void:
	var g := _game([1, 2])
	g.submit(1, {"number": 13}, now)
	var st: Dictionary = g.get_public_state()
	assert_eq(st["round"], 0)
	assert_eq(st["rounds"], 5)
	assert_eq(st["picked"], [1])
	assert_false(str(st).contains("13"), "no secret number in the snapshot")
	assert_false(st.has("ranking"))


func test_public_state_after_rounds_and_finish() -> void:
	var g := _game([1, 2])
	for r: int in LonelyNumberLogic.ROUNDS:
		_play_round(g, {1: 2, 2: 1})
		_skip_reveal(g)
	var st: Dictionary = g.get_public_state()
	assert_eq(st["history"].size(), 5)
	assert_eq(st["wins"][1], 5)
	assert_eq(st["totals"][1], 10)
	assert_true(st.has("ranking"))
	assert_eq(st["ranking"][0]["player"], 1)


func test_private_state() -> void:
	var g := _game([1, 2])
	assert_true(g.private_state(1)["can_pick"])
	assert_eq(g.private_state(1)["my_pick"], -1)
	g.submit(1, {"number": 11}, now)
	assert_false(g.private_state(1)["can_pick"])
	assert_eq(g.private_state(1)["my_pick"], 11)
	assert_eq(g.private_state(2)["my_pick"], -1, "others do not see it")
	assert_false(g.private_state(99)["can_pick"], "spectators cannot pick")
