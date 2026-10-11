extends GutTest
## Find the Lady rules: the round flow, the server-picked shuffle, picks as validated intents,
## scoring (right / wrong / speed, half-RTT corrected), the fourth card from round 4, ranking and
## ties, players dropping out, 2-player games and the late-join snapshot.


var logic: FindTheLadyLogic


func _make(ids: Array[int], seed_value: int = 11) -> FindTheLadyLogic:
	var g := FindTheLadyLogic.new()
	g.setup(ids, SeededRng.new(seed_value), BalanceConfig.new(), {}, {})
	return g


func before_each() -> void:
	logic = _make([1, 2, 3])


func _types(evs: Array[Dictionary]) -> Array[StringName]:
	var out: Array[StringName] = []
	for e: Dictionary in evs:
		out.append(e["type"])
	return out


## Intro → show → shuffle → pick (the window opens at server time `now`).
func _to_pick(g: FindTheLadyLogic, now: float = 100.0) -> void:
	if g.phase == FindTheLadyLogic.Step.INTRO:
		g.tick(FindTheLadyLogic.INTRO_TIME + 0.01, now)
	if g.phase == FindTheLadyLogic.Step.REVEAL:
		g.tick(FindTheLadyLogic.REVEAL_TIME + 0.01, now)
	assert_eq(g.phase, FindTheLadyLogic.Step.SHOW)
	g.tick(FindTheLadyLogic.SHOW_TIME + 0.01, now)
	assert_eq(g.phase, FindTheLadyLogic.Step.SHUFFLE)
	g.tick(g.timer + 0.001, now)
	assert_eq(g.phase, FindTheLadyLogic.Step.PICK)


func _wrong(g: FindTheLadyLogic) -> int:
	return (g.lady_slot + 1) % g.card_count


# --- Flow ----------------------------------------------------------------------------------------

func test_setup_starts_with_an_intro_and_no_round_yet() -> void:
	var evs: Array[Dictionary] = logic.drain_events()
	assert_eq(_types(evs), [&"find_the_lady_started"] as Array[StringName])
	assert_eq(logic.phase, FindTheLadyLogic.Step.INTRO)
	logic.tick(FindTheLadyLogic.INTRO_TIME + 0.01, 0.0)
	evs = logic.drain_events()
	assert_eq(_types(evs), [&"find_the_lady_round"] as Array[StringName])
	assert_eq(int(evs[0]["round"]), 0)
	assert_eq(int(evs[0]["cards"]), 3)
	assert_between(int(evs[0]["lady_start"]), 0, 2)


func test_shuffle_sequence_is_server_side_and_consistent() -> void:
	logic.tick(FindTheLadyLogic.INTRO_TIME + 0.01, 0.0)
	logic.tick(FindTheLadyLogic.SHOW_TIME + 0.01, 0.0)
	var ev: Dictionary = logic.drain_events().back()
	assert_eq(ev["type"], &"find_the_lady_shuffle")
	var swaps: Array = ev["swaps"]
	assert_eq(swaps.size(), FindTheLadyLogic.SWAP_COUNTS[0])
	for pair: Variant in swaps:
		assert_ne(int(pair[0]), int(pair[1]), "a swap moves two different cards")
		assert_between(int(pair[0]), 0, 2)
		assert_between(int(pair[1]), 0, 2)
	for i: int in swaps.size() - 1:
		assert_false(swaps[i] == swaps[i + 1], "no swap just undoes the one before")
	assert_eq(FindTheLadyLogic.follow(int(ev["lady_start"]), swaps), logic.lady_slot, "the clients can follow the Queen from the sequence")
	assert_almost_eq(float(ev["seconds"]), FindTheLadyLogic.shuffle_duration(0, swaps.size()), 0.001)
	# The Queen's final place never leaves the server as such before the reveal.
	assert_false(ev.has("lady"))


func test_rounds_get_faster_and_round_four_adds_a_card() -> void:
	var counts: Array[int] = []
	var swap_times: Array[float] = []
	var swap_counts: Array[int] = []
	for r: int in FindTheLadyLogic.ROUNDS:
		_to_pick(logic)
		counts.append(logic.card_count)
		swap_times.append(FindTheLadyLogic.swap_time(r))
		swap_counts.append(logic.swaps.size())
		for pair: Variant in logic.swaps:
			assert_lt(int(pair[0]), logic.card_count)
			assert_lt(int(pair[1]), logic.card_count)
		logic.tick(FindTheLadyLogic.pick_time(r) + 0.01, 200.0)
		assert_eq(logic.phase, FindTheLadyLogic.Step.REVEAL)
	assert_eq(counts, [3, 3, 3, 4, 4] as Array[int])
	for r: int in FindTheLadyLogic.ROUNDS - 1:
		assert_lt(swap_times[r + 1], swap_times[r], "each round swaps faster")
		assert_gt(swap_counts[r + 1], swap_counts[r], "and more often")
		assert_true(FindTheLadyLogic.pick_time(r + 1) <= FindTheLadyLogic.pick_time(r))
	logic.tick(FindTheLadyLogic.REVEAL_TIME + 0.01, 300.0)
	assert_eq(logic.phase, FindTheLadyLogic.Step.OUTRO)
	assert_false(logic.is_finished())
	logic.tick(FindTheLadyLogic.OUTRO_TIME + 0.01, 310.0)
	assert_true(logic.is_finished())


func test_pick_window_closes_early_once_everyone_picked() -> void:
	_to_pick(logic)
	for p: int in [1, 2, 3]:
		assert_true(logic.submit(p, {"slot": 0}, 101.0)["ok"])
	logic.tick(0.01, 101.0)
	assert_eq(logic.phase, FindTheLadyLogic.Step.REVEAL)


# --- Intents -------------------------------------------------------------------------------------

func test_pick_is_only_valid_while_the_window_is_open() -> void:
	assert_false(logic.submit(1, {"slot": 0}, 0.0)["ok"], "intro")
	logic.tick(FindTheLadyLogic.INTRO_TIME + 0.01, 0.0)
	assert_eq(logic.submit(1, {"slot": 0}, 0.0)["error"], &"too_late", "during the show")
	logic.tick(FindTheLadyLogic.SHOW_TIME + 0.01, 0.0)
	assert_eq(logic.submit(1, {"slot": 0}, 0.0)["error"], &"too_late", "during the shuffle")
	logic.tick(logic.timer + 0.01, 10.0)
	assert_eq(logic.submit(1, {"slot": 0, "round": 2}, 10.5)["error"], &"too_late", "a pick for another round")
	assert_eq(logic.submit(1, {"slot": 3}, 10.5)["error"], &"bad_value", "no fourth card in round 1")
	assert_eq(logic.submit(1, {"slot": -1}, 10.5)["error"], &"bad_value")
	assert_eq(logic.submit(9, {"slot": 0}, 10.5)["error"], &"not_in_minigame")
	assert_true(logic.submit(1, {"slot": 1, "round": 0}, 10.5)["ok"])
	assert_eq(logic.submit(1, {"slot": 2}, 10.6)["error"], &"already_picked", "no changing your mind")
	var ev: Dictionary = logic.drain_events().back()
	assert_eq(ev["type"], &"find_the_lady_picked")
	assert_false(ev.has("slot"), "others only learn THAT you picked")
	logic.tick(FindTheLadyLogic.pick_time(0) + 0.01, 20.0)
	assert_eq(logic.submit(2, {"slot": 0}, 20.0)["error"], &"too_late", "after the reveal")


func test_intent_schema_and_phase_are_declared() -> void:
	assert_true(Intents.SCHEMA.has(&"find_the_lady_pick"))
	assert_eq(IntentValidator.PHASES.get(&"find_the_lady_pick", []), [Phase.Id.MINIGAME])


# --- Scoring -------------------------------------------------------------------------------------

func test_scoring_right_wrong_and_speed() -> void:
	assert_eq(FindTheLadyLogic.pick_points(false, 0.0, 6.0), 0)
	assert_eq(FindTheLadyLogic.pick_points(true, 0.0, 6.0), 1000)
	assert_eq(FindTheLadyLogic.pick_points(true, 3.0, 6.0), 750)
	assert_eq(FindTheLadyLogic.pick_points(true, 6.0, 6.0), 500)
	assert_eq(FindTheLadyLogic.pick_points(true, 99.0, 6.0), 500, "a right pick is never worth less than 500")


func test_round_points_with_half_rtt_correction() -> void:
	logic.half_rtt = func(p: int) -> float: return 0.5 if p == 2 else 0.0
	_to_pick(logic, 100.0)
	var window: float = FindTheLadyLogic.pick_time(0)
	logic.submit(1, {"slot": logic.lady_slot}, 101.0)  # 1 s
	logic.submit(2, {"slot": logic.lady_slot}, 101.5)  # 1.5 s on arrival, 1 s after the RTT fix
	logic.submit(3, {"slot": _wrong(logic)}, 100.2)
	logic.tick(0.01, 101.5)
	var ev: Dictionary = logic.drain_events().back()
	assert_eq(ev["type"], &"find_the_lady_reveal")
	var expected: int = FindTheLadyLogic.pick_points(true, 1.0, window)
	assert_eq(int(ev["points"][1]), expected)
	assert_eq(int(ev["points"][2]), expected, "half-RTT corrected like the quiz")
	assert_eq(int(ev["points"][3]), 0, "wrong card")
	assert_eq(int(ev["lady"]), logic.lady_slot)
	assert_eq(int(ev["picks"][3]), _wrong(logic), "the reveal shows who picked which card")
	assert_eq(logic.points[1], expected)


func test_no_pick_scores_zero() -> void:
	_to_pick(logic)
	logic.submit(1, {"slot": logic.lady_slot}, 100.0)
	logic.tick(FindTheLadyLogic.pick_time(0) + 0.01, 110.0)
	var ev: Dictionary = logic.drain_events().back()
	assert_eq(int(ev["points"][2]), 0)
	assert_false((ev["picks"] as Dictionary).has(2))


# --- Ranking -------------------------------------------------------------------------------------

## Plays the whole game: `plan[p]` = "fast" (right at once), "slow" (right after 3 s), "wrong",
## or "none".
func _play(g: FindTheLadyLogic, plan: Dictionary) -> void:
	var now: float = 0.0
	while not g.is_finished() and g.phase != FindTheLadyLogic.Step.OUTRO:
		_to_pick(g, now)
		for p: int in g.players:
			match String(plan.get(p, "none")):
				"fast":
					g.submit(p, {"slot": g.lady_slot}, now)
				"slow":
					g.submit(p, {"slot": g.lady_slot}, now + 3.0)
				"wrong":
					g.submit(p, {"slot": _wrong(g)}, now)
		g.tick(FindTheLadyLogic.pick_time(g.round_index) + 0.01, now + 10.0)
		now += 30.0
		if g.round_index + 1 < FindTheLadyLogic.ROUNDS:
			continue
		g.tick(FindTheLadyLogic.REVEAL_TIME + 0.01, now)


func test_ranking_by_total_points() -> void:
	logic = _make([1, 2, 3, 4])
	_play(logic, {1: "slow", 2: "fast", 3: "wrong", 4: "none"})
	assert_eq(logic.phase, FindTheLadyLogic.Step.OUTRO)
	var r: Array[Dictionary] = logic.ranking()
	assert_eq(r.size(), 4)
	assert_eq(int(r[0]["player"]), 2)
	assert_eq(int(r[0]["points"]), 5000)
	assert_eq(int(r[1]["player"]), 1)
	assert_eq(int(r[0]["rank"]), 1)
	assert_eq(int(r[1]["rank"]), 2)
	assert_eq(int(r[2]["rank"]), 3, "both scored 0: shared rank")
	assert_eq(int(r[3]["rank"]), 3)


func test_ties_share_a_rank() -> void:
	_play(logic, {1: "fast", 2: "fast", 3: "wrong"})
	var r: Array[Dictionary] = logic.ranking()
	assert_eq(int(r[0]["rank"]), 1)
	assert_eq(int(r[1]["rank"]), 1, "same points, same time: tied")
	assert_eq(int(r[2]["rank"]), 3)
	assert_eq(int(r[2]["player"]), 3)


func test_two_player_game() -> void:
	logic = _make([5, 9])
	_play(logic, {5: "wrong", 9: "slow"})
	logic.tick(FindTheLadyLogic.OUTRO_TIME + 0.01, 999.0)
	assert_true(logic.is_finished())
	var r: Array[Dictionary] = logic.ranking()
	assert_eq(r.size(), 2)
	assert_eq(int(r[0]["player"]), 9)
	assert_eq(int(r[1]["player"]), 5)
	assert_eq(int(r[1]["points"]), 0)


func test_player_dropping_out_mid_pick() -> void:
	_to_pick(logic)
	logic.submit(1, {"slot": logic.lady_slot}, 100.0)
	logic.submit(2, {"slot": logic.lady_slot}, 100.0)
	logic.remove_player(3)
	logic.tick(0.01, 100.0)
	assert_eq(logic.phase, FindTheLadyLogic.Step.REVEAL, "the two left both picked: the window closes")
	logic.remove_player(1)
	_play(logic, {2: "fast"})
	var r: Array[Dictionary] = logic.ranking()
	assert_eq(r.size(), 1, "players who left score nothing and leave the ranking")
	assert_eq(int(r[0]["player"]), 2)
	assert_eq(logic.submit(1, {"slot": 0}, 0.0)["error"], &"not_in_minigame")


func test_everyone_leaving_ends_the_game() -> void:
	_to_pick(logic)
	for p: int in [1, 2, 3]:
		logic.remove_player(p)
	logic.tick(0.01, 100.0)
	assert_eq(logic.phase, FindTheLadyLogic.Step.OUTRO)
	logic.tick(FindTheLadyLogic.OUTRO_TIME + 0.01, 110.0)
	assert_true(logic.is_finished())
	assert_eq(logic.ranking().size(), 0)


# --- Snapshots -----------------------------------------------------------------------------------

func test_late_join_snapshot() -> void:
	logic.tick(FindTheLadyLogic.INTRO_TIME + 0.01, 0.0)
	var st: Dictionary = logic.get_public_state()
	assert_eq(st["minigame"], &"find_the_lady")
	assert_eq(st["phase"], "show")
	assert_eq(int(st["cards"]), 3)
	assert_false(st.has("swaps"), "no shuffle yet")
	logic.tick(FindTheLadyLogic.SHOW_TIME + 0.01, 0.0)
	logic.tick(0.5, 0.0)
	st = logic.get_public_state()
	assert_eq(st["phase"], "shuffle")
	assert_eq((st["swaps"] as Array).size(), logic.swaps.size(), "a late joiner can play the shuffle from where it is")
	assert_almost_eq(float(st["phase_time"]) - float(st["timer"]), 0.5, 0.02)
	assert_eq(int(st["lady_start"]), logic.lady_start)
	logic.tick(logic.timer + 0.01, 50.0)
	logic.submit(2, {"slot": 1}, 50.5)
	st = logic.get_public_state()
	assert_eq(st["phase"], "pick")
	assert_eq(st["picked"], [2])
	assert_false(st.has("reveal"), "picks stay secret until the reveal")
	assert_eq(logic.private_state(2), {"round": 0, "can_pick": false, "picked": 1})
	assert_eq(logic.private_state(1), {"round": 0, "can_pick": true})
	logic.tick(FindTheLadyLogic.pick_time(0) + 0.01, 60.0)
	st = logic.get_public_state()
	assert_eq(st["phase"], "reveal")
	assert_eq(int(st["reveal"]["lady"]), logic.lady_slot)
	assert_eq(int(st["reveal"]["picks"][2]), 1)
	assert_true(st["totals"].has(1))
