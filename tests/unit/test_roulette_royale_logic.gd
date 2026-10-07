extends GutTest
## Roulette Royale rules (MINIGAME_IDEAS): secret red / black / green picks each spin, 3 hearts,
## wrong (or missing) pick costs a heart, a correct green call gives one back, ranked by the order
## beans run out of hearts, wheel's 3.4 s spin, 45-75 s long.

const RED_NUMBER: int = 1
const BLACK_NUMBER: int = 2
const GREEN_NUMBER: int = 0
const RED: int = 0
const BLACK: int = 1
const GREEN: int = 2

var cfg: BalanceConfig = BalanceConfig.new()
var now: float = 0.0


func before_each() -> void:
	now = 0.0


func _royale(players: Array[int], seed: int = 5) -> RouletteRoyaleLogic:
	var r := RouletteRoyaleLogic.new()
	r.setup(players, SeededRng.new(seed), cfg, {}, {})
	return r


## Runs the server clock in 20 Hz steps until `cond` holds (or `limit` seconds pass).
func _run_until(r: RouletteRoyaleLogic, cond: Callable, limit: float = 120.0) -> void:
	var t: float = 0.0
	while not cond.call() and t < limit:
		r.tick(0.05, now)
		now += 0.05
		t += 0.05


func _to_pick(r: RouletteRoyaleLogic) -> void:
	_run_until(r, func() -> bool: return r.state == RouletteRoyaleLogic.State.PICK or r.is_finished())


func _to_result(r: RouletteRoyaleLogic) -> void:
	_run_until(r, func() -> bool: return r.state == RouletteRoyaleLogic.State.RESULT or r.is_finished())


## One spin: everyone in `picks` (player → color index) picks, the ball lands on `number`.
func _play_spin(r: RouletteRoyaleLogic, picks: Dictionary, number: int) -> void:
	_to_pick(r)
	r.forced_numbers = [number]
	for p: int in picks:
		assert_true(r.submit(p, {"question": r.spin, "index": picks[p]}, now)["ok"], "pick accepted")
	_to_result(r)


func _events_of(r: RouletteRoyaleLogic, type: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in r.drain_events():
		if e["type"] == type:
			out.append(e)
	return out


func test_players_start_with_three_hearts() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2, 3])
	var st: Dictionary = r.get_public_state()
	for p: int in [1, 2, 3]:
		assert_eq(st["hearts"][p], 3)
	assert_eq(st["alive"], [1, 2, 3])
	assert_eq(st["minigame"], &"roulette_royale", "catch-up needs the stage id")


func test_started_event_carries_players_and_hearts() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	var started: Array[Dictionary] = _events_of(r, &"roulette_royale_started")
	assert_eq(started.size(), 1)
	assert_eq(started[0]["players"], [1, 2])
	assert_eq(started[0]["hearts"][1], 3)
	assert_almost_eq(float(started[0]["spin_time"]), 3.4, 0.001, "reuses the wheel's 3.4 s spin")


func test_picks_only_during_the_pick_window() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	assert_eq(r.submit(1, {"question": 0, "index": RED}, now)["error"], &"too_late", "intro: no picks yet")
	_to_pick(r)
	assert_true(r.submit(1, {"question": 0, "index": RED}, now)["ok"])


func test_bad_picks_rejected() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	_to_pick(r)
	assert_eq(r.submit(99, {"question": 0, "index": RED}, now)["error"], &"not_in_minigame")
	assert_eq(r.submit(1, {"question": 0, "index": 3}, now)["error"], &"bad_value")
	assert_eq(r.submit(1, {"question": 0, "index": -1}, now)["error"], &"bad_value")
	assert_eq(r.submit(1, {"question": 4, "index": RED}, now)["error"], &"too_late", "stale spin index")
	assert_true(r.submit(1, {"question": 0, "index": RED}, now)["ok"])
	assert_eq(r.submit(1, {"question": 0, "index": BLACK}, now)["error"], &"already_picked")


func test_picks_stay_secret_until_the_result() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	_to_pick(r)
	r.drain_events()
	r.submit(1, {"question": 0, "index": GREEN}, now)
	var picked: Array[Dictionary] = _events_of(r, &"roulette_royale_picked")
	assert_eq(picked.size(), 1)
	assert_false(picked[0].has("index") or picked[0].has("color") or picked[0].has("pick"), "only *that* someone picked")
	assert_false(str(r.get_public_state()).contains("green"), "public snapshot holds no picks")
	assert_eq(r.private_state(1)["pick"], GREEN, "own pick comes back privately")
	assert_false(r.private_state(2).has("pick"))


func test_wrong_pick_costs_a_heart_right_pick_keeps_it() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	_play_spin(r, {1: RED, 2: BLACK}, RED_NUMBER)
	assert_eq(r.hearts[1], 3, "right colour keeps hearts")
	assert_eq(r.hearts[2], 2, "wrong colour costs one")


func test_no_pick_costs_a_heart() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	_play_spin(r, {1: RED}, RED_NUMBER)
	assert_eq(r.hearts[2], 2, "an empty pick is a wrong pick")
	assert_eq(r.last_result["picks"][2], &"")


func test_green_call_gives_a_heart_back() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	_play_spin(r, {1: BLACK, 2: RED}, RED_NUMBER)
	assert_eq(r.hearts[1], 2)
	_play_spin(r, {1: GREEN, 2: RED}, GREEN_NUMBER)
	assert_eq(r.hearts[1], 3, "correct green call: +1")
	assert_eq(r.hearts[2], 2, "red on a zero is wrong")
	assert_eq(r.last_result["deltas"][1], 1)


func test_green_never_exceeds_starting_hearts() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	_play_spin(r, {1: GREEN, 2: GREEN}, GREEN_NUMBER)
	assert_eq(r.hearts[1], 3)
	assert_eq(r.last_result["deltas"][1], 0)


func test_wrong_green_costs_a_heart() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	_play_spin(r, {1: GREEN, 2: BLACK}, BLACK_NUMBER)
	assert_eq(r.hearts[1], 2)
	assert_eq(r.hearts[2], 3)


func test_pick_window_closes_early_when_everyone_picked() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	_to_pick(r)
	r.submit(1, {"question": 0, "index": RED}, now)
	r.submit(2, {"question": 0, "index": RED}, now)
	var t0: float = now
	_run_until(r, func() -> bool: return r.state == RouletteRoyaleLogic.State.SPIN)
	assert_lt(now - t0, 1.0, "no waiting out the full window")


func test_spin_lasts_the_wheels_spin_time() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	_to_pick(r)
	_run_until(r, func() -> bool: return r.state == RouletteRoyaleLogic.State.SPIN)
	var t0: float = now
	_run_until(r, func() -> bool: return r.state == RouletteRoyaleLogic.State.RESULT)
	assert_almost_eq(now - t0, cfg.roulette_spin_time, 0.1)


func test_elimination_and_last_bean_wins() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2, 3])
	# Spin 0: 3 wrong. Spin 1: 3 wrong, 2 wrong. Spin 2: 3 out, 2 wrong. Spin 3: 2 out.
	_play_spin(r, {1: RED, 2: RED, 3: BLACK}, RED_NUMBER)
	_play_spin(r, {1: RED, 2: BLACK, 3: BLACK}, RED_NUMBER)
	_play_spin(r, {1: RED, 2: BLACK, 3: BLACK}, RED_NUMBER)
	assert_eq(r.hearts[3], 0)
	assert_false(3 in r.alive, "out at zero hearts")
	assert_eq(r.last_result["eliminated"], [3])
	assert_eq(r.submit(3, {"question": r.spin + 1, "index": RED}, now)["error"], &"knocked_out")
	_play_spin(r, {1: RED, 2: BLACK}, RED_NUMBER)
	assert_eq(r.alive, [1])
	_run_until(r, func() -> bool: return r.is_finished())
	assert_true(r.is_finished())
	var ranking: Array[Dictionary] = r.ranking()
	assert_eq(ranking[0]["player"], 1, "last bean with hearts wins")
	assert_eq(ranking[0]["rank"], 1)
	assert_eq(ranking[1]["player"], 2, "out later ranks higher")
	assert_eq(ranking[1]["rank"], 2)
	assert_eq(ranking[2]["player"], 3)
	assert_eq(ranking[2]["rank"], 3)


func test_knocked_out_on_the_same_spin_share_a_place() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2, 3])
	for i: int in 3:
		_play_spin(r, {1: RED, 2: BLACK, 3: BLACK}, RED_NUMBER)
	_run_until(r, func() -> bool: return r.is_finished())
	var ranking: Array[Dictionary] = r.ranking()
	assert_eq(ranking[0]["player"], 1)
	assert_eq(ranking[1]["rank"], 2)
	assert_eq(ranking[2]["rank"], 2, "same spin, same place")


func test_everyone_out_together_all_win() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	for i: int in 3:
		_play_spin(r, {1: BLACK, 2: BLACK}, RED_NUMBER)
	assert_true(r.alive.is_empty())
	_run_until(r, func() -> bool: return r.is_finished())
	var ranking: Array[Dictionary] = r.ranking()
	assert_eq(ranking[0]["rank"], 1)
	assert_eq(ranking[1]["rank"], 1, "last ones standing went down together")


func test_spin_cap_ranks_survivors_by_hearts() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2, 3])
	_play_spin(r, {1: RED, 2: BLACK, 3: RED}, RED_NUMBER)  # 2 loses one
	for i: int in RouletteRoyaleLogic.MAX_SPINS - 1:
		_play_spin(r, {1: RED, 2: RED, 3: RED}, RED_NUMBER)
	_run_until(r, func() -> bool: return r.is_finished())
	assert_true(r.is_finished())
	assert_eq(r.spin, RouletteRoyaleLogic.MAX_SPINS - 1, "no more than MAX_SPINS spins")
	var ranking: Array[Dictionary] = r.ranking()
	assert_eq(ranking[0]["rank"], 1)
	assert_eq(ranking[1]["rank"], 1, "1 and 3 tie on 3 hearts")
	assert_eq(ranking[2]["player"], 2)
	assert_eq(ranking[2]["rank"], 3)


func test_length_within_45_to_75_seconds_when_nobody_picks() -> void:
	# Idle players: every spin waits out the full pick window, everyone loses a heart per spin
	# (except on a green, which nobody called either), so this is a realistic slow game.
	var r: RouletteRoyaleLogic = _royale([1, 2, 3, 4])
	_run_until(r, func() -> bool: return r.is_finished(), 200.0)
	assert_true(r.is_finished())
	assert_lte(now, 75.0)


func test_worst_case_length_is_at_most_75_seconds() -> void:
	# Everyone always right, every pick at the last moment: the spin cap ends it.
	var worst: float = RouletteRoyaleLogic.INTRO_TIME + RouletteRoyaleLogic.MAX_SPINS * (RouletteRoyaleLogic.PICK_TIME + cfg.roulette_spin_time + RouletteRoyaleLogic.RESULT_TIME) + RouletteRoyaleLogic.OUTRO_TIME
	assert_lte(worst, 75.0)
	var r: RouletteRoyaleLogic = _royale([1, 2])
	while not r.is_finished() and now < 200.0:
		if r.state == RouletteRoyaleLogic.State.PICK and r.timer <= 0.1 and r.picks.is_empty():
			r.forced_numbers = [RED_NUMBER]
			r.submit(1, {"question": r.spin, "index": RED}, now)
			r.submit(2, {"question": r.spin, "index": RED}, now)
		r.tick(0.05, now)
		now += 0.05
	assert_true(r.is_finished())
	assert_eq(r.spin, RouletteRoyaleLogic.MAX_SPINS - 1)
	assert_lte(now, 75.5)


## A realistic game: beans pick ~2 s into the window, coin-flip red / black, real wheel.
func _sim_game(players: Array[int], seed: int) -> float:
	var r: RouletteRoyaleLogic = _royale(players, seed)
	var think := SeededRng.new(seed + 1000)
	now = 0.0
	while not r.is_finished() and now < 200.0:
		if r.state == RouletteRoyaleLogic.State.PICK and r.timer <= RouletteRoyaleLogic.PICK_TIME - 2.0:
			for p: int in r.alive:
				if not r.picks.has(p):
					r.submit(p, {"question": r.spin, "index": think.range_int(0, 1)}, now)
		r.tick(0.05, now)
		now += 0.05
	assert_true(r.is_finished())
	return now


func test_typical_game_lasts_45_to_75_seconds() -> void:
	for n: int in [2, 4, 6]:
		var players: Array[int] = []
		for i: int in n:
			players.append(i + 1)
		var total: float = 0.0
		for seed: int in 30:
			var t: float = _sim_game(players, seed)
			assert_lte(t, 75.0, "never over 75 s")
			total += t
		var avg: float = total / 30.0
		gut.p("%d beans: average %.1f s" % [n, avg])
		assert_between(avg, 45.0, 75.0, "%d beans: average %.1f s" % [n, avg])


func test_events_through_a_spin() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	r.drain_events()
	_play_spin(r, {1: RED, 2: BLACK}, BLACK_NUMBER)
	var types: Array = r.drain_events().map(func(e: Dictionary) -> StringName: return e["type"])
	assert_has(types, &"roulette_royale_pick_open")
	assert_has(types, &"roulette_royale_spin")
	assert_has(types, &"roulette_royale_result")
	assert_lt(types.find(&"roulette_royale_spin"), types.find(&"roulette_royale_result"))


func test_result_event_payload() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	_to_pick(r)
	r.drain_events()
	r.forced_numbers = [RED_NUMBER]
	r.submit(1, {"question": 0, "index": RED}, now)
	r.submit(2, {"question": 0, "index": GREEN}, now)
	_to_result(r)
	var res: Array[Dictionary] = _events_of(r, &"roulette_royale_result")
	assert_eq(res.size(), 1)
	var ev: Dictionary = res[0]
	assert_eq(ev["number"], RED_NUMBER)
	assert_eq(ev["color"], &"red")
	assert_eq(ev["picks"][1], &"red")
	assert_eq(ev["picks"][2], &"green")
	assert_eq(ev["deltas"][2], -1)
	assert_eq(ev["hearts"][2], 2)


func test_random_wheel_covers_all_colours() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2], 11)
	var seen: Dictionary = {}
	for i: int in 400:
		var n: int = r.rng.range_int(0, RouletteLogic.WHEEL_ORDER.size() - 1)
		assert_between(n, 0, 36)
		seen[RouletteRoyaleLogic.color_of(n)] = true
	assert_eq(seen.size(), 3)


func test_remove_player_leaves_ranking_and_ends_with_one_left() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	_to_pick(r)
	r.remove_player(2)
	_run_until(r, func() -> bool: return r.is_finished())
	assert_true(r.is_finished())
	var ranking: Array[Dictionary] = r.ranking()
	assert_eq(ranking.size(), 1)
	assert_eq(ranking[0]["player"], 1)
	assert_eq(ranking[0]["rank"], 1)


func test_heart_delta_rules() -> void:
	assert_eq(RouletteRoyaleLogic.heart_delta(&"red", &"red"), 0)
	assert_eq(RouletteRoyaleLogic.heart_delta(&"black", &"red"), -1)
	assert_eq(RouletteRoyaleLogic.heart_delta(&"green", &"green"), 1)
	assert_eq(RouletteRoyaleLogic.heart_delta(&"green", &"black"), -1)
	assert_eq(RouletteRoyaleLogic.heart_delta(&"", &"red"), -1)


func test_ranking_points_reward_survival() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	for i: int in 3:
		_play_spin(r, {1: RED, 2: BLACK}, RED_NUMBER)
	_run_until(r, func() -> bool: return r.is_finished())
	var ranking: Array[Dictionary] = r.ranking()
	assert_gt(int(ranking[0]["points"]), int(ranking[1]["points"]))
