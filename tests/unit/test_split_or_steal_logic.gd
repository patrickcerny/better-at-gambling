extends GutTest
## Split or Steal tournament: everyone plays everyone (round robin for 2-8 players; tiny tables
## repeat it), one duel at a time (ROUND → DECIDE → REVEAL), nothing announced before the first
## tick (the first-round bug), watchers are refused, payoffs (1/1, 3/0, 0/0), timeouts, leavers, ranking (points, then
## fewer steals), snapshot / private state for late joiners.

const S: String = SplitOrStealLogic.SPLIT
const T: String = SplitOrStealLogic.STEAL
const NOBODY: int = SplitOrStealLogic.NOBODY

var cfg: BalanceConfig = BalanceConfig.new()
var now: float = 0.0


func _game(players: Array[int], params: Dictionary = {}) -> SplitOrStealLogic:
	var g := SplitOrStealLogic.new()
	var p: Dictionary = {"intro_time": 0.5, "round_time": 0.5, "decide_time": 1.0, "reveal_time": 0.5, "outro_time": 0.5}
	p.merge(params, true)
	g.setup(players, SeededRng.new(5), cfg, p, {})
	return g


func _ids(n: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in n:
		out.append(i + 1)
	return out


func _run(g: SplitOrStealLogic, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		g.tick(0.05, now)
		t += 0.05


func _to_decide(g: SplitOrStealLogic) -> void:
	var guard: int = 0
	while g.state != SplitOrStealLogic.State.DECIDE and not g.finished and guard < 10000:
		g.tick(0.05, now)
		guard += 1


func _pick(g: SplitOrStealLogic, p: int, c: String) -> Dictionary:
	return g.submit(p, {"choice": c}, now)


func _of_type(events: Array[Dictionary], type: StringName) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## How often each pair meets across the whole show, keyed "lo-hi".
func _meetings(rounds: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for r: Dictionary in rounds:
		for d: Dictionary in r["duels"]:
			var a: int = int(d["a"])
			var b: int = int(d["b"])
			var key: String = "%d-%d" % [mini(a, b), maxi(a, b)]
			out[key] = int(out.get(key, 0)) + 1
	return out


# --- Schedule ----------------------------------------------------------------------------------

func test_everyone_meets_everyone_one_duel_at_a_time() -> void:
	for n: int in range(2, 9):
		var rounds: Array[Dictionary] = SplitOrStealLogic.build_rounds(_ids(n), SeededRng.new(n))
		var cycles: int = SplitOrStealLogic.cycles_for(n)
		var meet: Dictionary = _meetings(rounds)
		assert_eq(meet.size(), n * (n - 1) / 2, "%d players: every pair meets" % n)
		for k: String in meet:
			assert_eq(int(meet[k]), cycles, "%d players: pair %s meets once per cycle" % [n, k])
		assert_gte(rounds.size(), SplitOrStealLogic.MIN_ROUNDS, "%d players: long enough" % n)
		assert_lte(rounds.size(), SplitOrStealLogic.MAX_ROUNDS, "%d players: within the cap" % n)
		var prev: Array = []
		for r: Dictionary in rounds:
			assert_eq((r["duels"] as Array).size(), 1, "one duel on stage at a time")
			var d: Dictionary = r["duels"][0]
			assert_ne(int(d["a"]), int(d["b"]))
			if n >= 5:  # with 4 the three disjoint pairs can't chain into one line
				assert_false(int(d["a"]) in prev or int(d["b"]) in prev, "%d players: nobody twice in a row" % n)
			prev = [int(d["a"]), int(d["b"])]


func test_duel_counts() -> void:
	var expect: Dictionary = {2: 4, 3: 6, 4: 6, 5: 10, 6: 15, 7: 21, 8: 28}
	for n: int in expect:
		assert_eq(SplitOrStealLogic.build_rounds(_ids(n), null).size(), int(expect[n]), "%d players" % n)
	assert_eq(SplitOrStealLogic.duels_per_player(8), 7)
	assert_eq(SplitOrStealLogic.duels_per_player(2), 4)
	assert_eq(SplitOrStealLogic.duels_per_player(3), 4)


func test_game_cap_constants() -> void:
	assert_eq(SplitOrStealLogic.ROUND_CAP, SplitOrStealLogic.ROUND_TIME + SplitOrStealLogic.DECIDE_TIME + SplitOrStealLogic.REVEAL_TIME)
	assert_almost_eq(SplitOrStealLogic.GAME_CAP, 512.0, 0.01)


# --- Flow --------------------------------------------------------------------------------------

func test_nothing_is_announced_before_the_first_tick() -> void:
	var g := _game([1, 2, 3, 4])
	assert_eq(g.drain_events().size(), 0, "the stage is not built yet")
	assert_eq(g.get_public_state()["rounds"].size(), 3 * 2, "but the snapshot has the schedule")
	g.tick(0.05, now)
	var ev: Array[Dictionary] = g.drain_events()
	assert_eq(_of_type(ev, &"split_or_steal_started").size(), 1)
	assert_eq(_of_type(ev, &"split_or_steal_round").size(), 0, "the intro first")


func test_one_duel_on_stage_at_a_time() -> void:
	var g := _game(_ids(8))
	_to_decide(g)
	var rounds: Array = _of_type(g.drain_events(), &"split_or_steal_round")
	assert_eq(rounds.size(), 1)
	assert_eq((rounds[0]["duels"] as Array).size(), 1)
	var pair: Array[int] = g.active_players()
	assert_eq(pair.size(), 2)
	for p: int in _ids(8):
		if p in pair:
			assert_true(_pick(g, p, S)["ok"])
		else:
			assert_eq(_pick(g, p, S)["error"], &"not_your_turn", "the audience watches")
	g.tick(0.05, now)
	var rev: Array = _of_type(g.drain_events(), &"split_or_steal_reveal")
	assert_eq(rev.size(), 1)
	assert_eq((rev[0]["results"] as Array).size(), 1)
	assert_eq(g.points[pair[0]] + g.points[pair[1]], 2)


func test_private_state_carries_the_duel_for_a_stage_that_missed_events() -> void:
	var g := _game([1, 2, 3])
	_to_decide(g)
	var dueling: int = g.active_players()[0]
	var watching: int = ([1, 2, 3].filter(func(p: int) -> bool: return p not in g.active_players()))[0]
	var priv: Dictionary = g.private_state(dueling)
	assert_eq(int(priv["index"]), 0)
	assert_eq((priv["duels"] as Array).size(), 1)
	assert_eq(int(priv["opponent"]), g.opponent_of(dueling))
	assert_true(priv["can_choose"])
	var off: Dictionary = g.private_state(watching)
	assert_eq(int(off["opponent"]), NOBODY)
	assert_false(off["can_choose"])


func test_watchers_are_refused() -> void:
	var g := _game([1, 2, 3])
	_to_decide(g)
	var watching: int = ([1, 2, 3].filter(func(p: int) -> bool: return p not in g.active_players()))[0]
	assert_eq(_pick(g, watching, T)["error"], &"not_your_turn")


func test_rejections() -> void:
	var g := _game([1, 2])
	assert_eq(_pick(g, 1, S)["error"], &"not_decide_phase")
	_to_decide(g)
	assert_eq(_pick(g, 9, S)["error"], &"unknown_player")
	assert_eq(_pick(g, 1, "MAYBE")["error"], &"invalid_choice")
	assert_true(_pick(g, 1, "steal")["ok"], "case-insensitive")
	assert_eq(_pick(g, 1, S)["error"], &"already_chose")


func test_locked_event_hides_choice() -> void:
	var g := _game([1, 2])
	_to_decide(g)
	g.drain_events()
	_pick(g, 1, T)
	var locked: Array = _of_type(g.drain_events(), &"split_or_steal_locked")
	assert_eq(locked.size(), 1)
	assert_eq(int(locked[0]["player"]), 1)
	assert_false(locked[0].has("choice"))
	assert_false(str(locked[0]).contains(T), "the pick stays secret")


func test_reveal_comes_early_when_both_decided() -> void:
	var g := _game([1, 2, 3, 4], {"decide_time": 30.0})
	_to_decide(g)
	var pair: Array[int] = g.active_players()
	_pick(g, pair[0], S)
	g.tick(0.05, now)
	assert_eq(g.state, SplitOrStealLogic.State.DECIDE, "one still thinking")
	_pick(g, pair[1], S)
	g.tick(0.05, now)
	assert_eq(g.state, SplitOrStealLogic.State.REVEAL)


func test_timeout_counts_as_split() -> void:
	var g := _game([1, 2])
	_to_decide(g)
	_pick(g, 1, T)
	_run(g, 1.1)
	assert_eq(g.state, SplitOrStealLogic.State.REVEAL)
	var r: Dictionary = g.rounds[0]["duels"][0]["result"]
	var a_is_1: bool = int(r["a"]) == 1
	assert_eq(str(r["choice_b" if a_is_1 else "choice_a"]), S)
	assert_true(bool(r["auto_b" if a_is_1 else "auto_a"]))
	assert_eq(g.points[1], 3)


func test_payoff_matrix() -> void:
	assert_eq(SplitOrStealLogic.payoff(S, S), [1, 1] as Array[int])
	assert_eq(SplitOrStealLogic.payoff(T, S), [3, 0] as Array[int])
	assert_eq(SplitOrStealLogic.payoff(S, T), [0, 3] as Array[int])
	assert_eq(SplitOrStealLogic.payoff(T, T), [0, 0] as Array[int])


func _play_round(g: SplitOrStealLogic, pick: Callable) -> void:
	_to_decide(g)
	for p: int in g.active_players():
		_pick(g, p, pick.call(p))
	g.tick(0.05, now)


func test_scoring_both_split_steal_and_both_steal() -> void:
	var g := _game([1, 2])
	_play_round(g, func(_p: int) -> String: return S)
	assert_eq([g.points[1], g.points[2]], [1, 1])
	_play_round(g, func(p: int) -> String: return T if p == 1 else S)
	assert_eq([g.points[1], g.points[2]], [4, 1])
	_play_round(g, func(_p: int) -> String: return T)
	assert_eq([g.points[1], g.points[2]], [4, 1])
	assert_eq([g.steals[1], g.steals[2]], [2, 1])


func test_full_show_finishes_with_ranking() -> void:
	var g := _game([1, 2, 3, 4])
	var guard: int = 0
	while not g.finished and guard < 100000:
		if g.state == SplitOrStealLogic.State.DECIDE:
			for p: int in g.active_players():
				if not g.choices.has(p):
					_pick(g, p, T if p == 1 else S)
		g.tick(0.05, now)
		guard += 1
	assert_true(g.finished)
	var ev: Array[Dictionary] = g.drain_events()
	assert_eq(_of_type(ev, &"split_or_steal_reveal").size(), 6, "4 players: 6 rounds")
	assert_eq(_of_type(ev, &"split_or_steal_finished").size(), 1)
	var rows: Array[Dictionary] = g.ranking()
	assert_eq(rows.size(), 4)
	assert_eq(int(rows[0]["player"]), 1, "the stealer robbed every splitter")
	assert_eq(int(rows[0]["points"]), 3 * 3, "once against each of the other three")
	for row: Dictionary in rows:
		assert_true(row.has("rank") and row.has("time"))


func test_outro_holds_before_finished() -> void:
	var g := _game([1, 2], {"outro_time": 2.0})
	var guard: int = 0
	while g.state != SplitOrStealLogic.State.OUTRO and guard < 10000:
		g.tick(0.05, now)
		guard += 1
	assert_false(g.finished)
	assert_eq(_pick(g, 1, S)["error"], &"game_over")
	_run(g, 2.1)
	assert_true(g.finished)


func test_show_stays_within_the_game_cap() -> void:
	for n: int in [2, 3, 8]:
		var g := SplitOrStealLogic.new()
		g.setup(_ids(n), SeededRng.new(1), cfg, {}, {})
		var t: float = 0.0
		while not g.finished and t < 700.0:
			g.tick(0.05, now)
			t += 0.05
		assert_true(g.finished)
		assert_lt(t, SplitOrStealLogic.GAME_CAP + 0.2 * SplitOrStealLogic.MAX_ROUNDS, "%d players, nobody deciding: every round runs its full timer" % n)
		if n == 8:
			assert_gt(t, 120.0, "8 players: a real tournament, not a minute")


func test_leaver_counts_as_split_and_scores_nothing() -> void:
	var g := _game([1, 2, 3, 4], {"decide_time": 30.0})
	_to_decide(g)
	var gone: int = g.active_players()[0]
	var opp: int = g.opponent_of(gone)
	g.remove_player(gone)
	for p: int in g.active_players():
		_pick(g, p, T if p == opp else S)
	g.tick(0.05, now)
	assert_eq(g.state, SplitOrStealLogic.State.REVEAL, "nobody waits for the leaver")
	assert_eq(g.points[opp], 3, "the opponent still plays their duel")
	assert_false(gone in g.ranking().map(func(r: Dictionary) -> int: return int(r["player"])))
	_run(g, 0.6)
	_to_decide(g)
	assert_eq(g.round_index, 1, "the show goes on")


func test_two_players_one_leaves_ends_the_show() -> void:
	var g := _game([1, 2])
	_to_decide(g)
	g.remove_player(2)
	var guard: int = 0
	while not g.finished and guard < 10000:
		g.tick(0.05, now)
		guard += 1
	assert_true(g.finished)
	assert_eq(g.ranking().size(), 1)


# --- Ranking -----------------------------------------------------------------------------------

func test_ranking_tie_goes_to_fewer_steals() -> void:
	var g := _game([1, 2, 3])
	g.points = {1: 3, 2: 3, 3: 1}
	g.steals = {1: 1, 2: 0, 3: 0}
	var rows: Array[Dictionary] = g.ranking()
	assert_eq(int(rows[0]["player"]), 2)
	assert_eq(int(rows[1]["player"]), 1)
	assert_eq(int(rows[1]["rank"]), 2)


func test_ranking_full_tie_shares_rank() -> void:
	var g := _game([1, 2, 3])
	g.points = {1: 1, 2: 1, 3: 0}
	g.steals = {1: 0, 2: 0, 3: 0}
	var rows: Array[Dictionary] = g.ranking()
	assert_eq(int(rows[0]["rank"]), 1)
	assert_eq(int(rows[1]["rank"]), 1)
	assert_eq(int(rows[2]["rank"]), 3)


# --- Snapshot / late join ----------------------------------------------------------------------

func test_public_state_for_late_join() -> void:
	var g := _game([1, 2, 3, 4])
	_play_round(g, func(_p: int) -> String: return T)
	_to_decide(g)
	var up: int = g.active_players()[0]
	_pick(g, up, S)
	var st: Dictionary = g.get_public_state()
	assert_eq(st["minigame"], &"split_or_steal")
	assert_eq(int(st["state"]), SplitOrStealLogic.State.DECIDE)
	assert_eq(int(st["index"]), 1)
	assert_eq(int(st["total"]), 6)
	var rounds: Array = st["rounds"]
	for d: Variant in rounds[0]["duels"]:
		assert_true(((d as Dictionary)["result"] as Dictionary).has("choice_a"), "revealed decisions are public")
	for d: Variant in rounds[1]["duels"]:
		assert_true(((d as Dictionary)["result"] as Dictionary).is_empty(), "the current ones are not")
	assert_eq(st["locked"], [up])
	var stole: int = 0
	for p: Variant in st["steals"]:
		stole += int(st["steals"][p])
	assert_eq(stole, 2, "running totals: the first duel, both stole")
	assert_gt(float(st["timer"]), 0.0)


func test_snapshot_ranking_in_outro() -> void:
	var g := _game([1, 2])
	var guard: int = 0
	while g.state != SplitOrStealLogic.State.OUTRO and guard < 10000:
		g.tick(0.05, now)
		guard += 1
	assert_eq((g.get_public_state()["ranking"] as Array).size(), 2)
