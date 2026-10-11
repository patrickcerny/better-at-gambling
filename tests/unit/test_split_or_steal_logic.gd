extends GutTest
## Split or Steal show: the schedule of pairs (2, 3, 4, 5, 7, 8 players; the house match for odd
## counts), one pair at a time (ANNOUNCE → DECIDE → REVEAL), nothing announced before the first
## tick (the first-round bug), watchers refused, payoffs (1/1, 3/0, 0/0), timeouts, leavers,
## ranking (points, then fewer steals), snapshot / private state for late joiners.

const S: String = SplitOrStealLogic.SPLIT
const T: String = SplitOrStealLogic.STEAL
const NOBODY: int = SplitOrStealLogic.NOBODY

var cfg: BalanceConfig = BalanceConfig.new()
var now: float = 0.0


func _game(players: Array[int], params: Dictionary = {}) -> SplitOrStealLogic:
	var g := SplitOrStealLogic.new()
	var p: Dictionary = {"intro_time": 0.5, "announce_time": 0.5, "decide_time": 1.0, "reveal_time": 0.5, "outro_time": 0.5}
	p.merge(params, true)
	g.setup(players, SeededRng.new(5), cfg, p, {})
	return g


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


func _to_next_reveal(g: SplitOrStealLogic) -> void:
	var guard: int = 0
	while g.state != SplitOrStealLogic.State.REVEAL and not g.finished and guard < 10000:
		g.tick(0.05, now)
		guard += 1


func _pick(g: SplitOrStealLogic, p: int, c: String) -> Dictionary:
	return g.submit(p, {"choice": c}, now)


func _of_type(events: Array[Dictionary], type: StringName) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## Scored matches per player in a schedule (the house side doesn't count).
func _scored(schedule: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for e: Dictionary in schedule:
		for p: int in [int(e["a"]), int(e["b"])]:
			if p != int(e["house"]):
				out[p] = int(out.get(p, 0)) + 1
	return out


# --- Schedule ---------------------------------------------------------------------------------

func test_two_players_play_four_times() -> void:
	var s: Array[Dictionary] = SplitOrStealLogic.build_schedule([1, 2], SeededRng.new(1))
	assert_eq(s.size(), 4, "an iterated dilemma")
	for e: Dictionary in s:
		assert_eq(int(e["house"]), NOBODY)
		assert_ne(int(e["a"]), int(e["b"]), "a real pair, never 'nobody'")
	assert_eq(_scored(s), {1: 4, 2: 4})


func test_three_players_round_robin() -> void:
	var s: Array[Dictionary] = SplitOrStealLogic.build_schedule([1, 2, 3], SeededRng.new(2))
	assert_eq(s.size(), 3)
	assert_eq(_scored(s), {1: 2, 2: 2, 3: 2}, "everyone plays twice")
	var keys: Dictionary = {}
	for e: Dictionary in s:
		keys["%d-%d" % [mini(e["a"], e["b"]), maxi(e["a"], e["b"])]] = true
	assert_eq(keys.size(), 3, "every pair once")


func test_four_players_two_different_opponents_each() -> void:
	var s: Array[Dictionary] = SplitOrStealLogic.build_schedule([1, 2, 3, 4], SeededRng.new(3))
	assert_eq(s.size(), 4)
	assert_eq(_scored(s), {1: 2, 2: 2, 3: 2, 4: 2})
	var keys: Dictionary = {}
	for e: Dictionary in s:
		keys["%d-%d" % [mini(e["a"], e["b"]), maxi(e["a"], e["b"])]] = true
	assert_eq(keys.size(), 4, "no rematch")


func test_five_players_leftover_gets_a_house_match() -> void:
	var s: Array[Dictionary] = SplitOrStealLogic.build_schedule([1, 2, 3, 4, 5], SeededRng.new(4))
	assert_eq(s.size(), 3, "two pairs and the bonus match")
	var last: Dictionary = s[2]
	var house: int = int(last["house"])
	assert_ne(house, NOBODY, "the bonus match has a stand-in")
	assert_true(house == int(last["a"]) or house == int(last["b"]))
	var scored: Dictionary = _scored(s)
	assert_eq(scored.size(), 5, "everyone has a scored match")
	for p: int in scored:
		assert_eq(int(scored[p]), 1, "exactly one each")
	for e: Dictionary in s.slice(0, 2):
		assert_eq(int(e["house"]), NOBODY)


func test_seven_and_eight_players_cap_at_four_pairs() -> void:
	var s7: Array[Dictionary] = SplitOrStealLogic.build_schedule([1, 2, 3, 4, 5, 6, 7], SeededRng.new(5))
	assert_eq(s7.size(), 4)
	assert_ne(int(s7[3]["house"]), NOBODY)
	assert_eq(_scored(s7).size(), 7)
	var s8: Array[Dictionary] = SplitOrStealLogic.build_schedule([1, 2, 3, 4, 5, 6, 7, 8], SeededRng.new(6))
	assert_eq(s8.size(), 4)
	assert_eq(_scored(s8), {1: 1, 2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1})


func test_no_schedule_ever_exceeds_the_cap_or_has_nobody() -> void:
	for n: int in range(2, SplitOrStealLogic.MAX_PLAYERS + 1):
		var roster: Array[int] = []
		for i: int in n:
			roster.append(i + 1)
		for seed_v: int in 5:
			var s: Array[Dictionary] = SplitOrStealLogic.build_schedule(roster, SeededRng.new(seed_v))
			assert_between(s.size(), 1, SplitOrStealLogic.MAX_PAIRS, "%d players" % n)
			var scored: Dictionary = _scored(s)
			assert_eq(scored.size(), n, "%d players: everyone plays" % n)
			var k: int = SplitOrStealLogic.matches_per_player(n)
			for p: int in scored:
				assert_eq(int(scored[p]), k, "%d players: equal scored matches" % n)
			for e: Dictionary in s:
				assert_true(int(e["a"]) in roster and int(e["b"]) in roster, "never 'nobody' on a podium")
	assert_eq(SplitOrStealLogic.build_schedule([1], null).size(), 0)
	assert_eq(SplitOrStealLogic.build_schedule([], null).size(), 0)


func test_game_cap_constants() -> void:
	assert_almost_eq(SplitOrStealLogic.ROUND_CAP, 22.5, 0.001)
	assert_almost_eq(SplitOrStealLogic.GAME_CAP, 98.0, 0.001)


# --- The first-round bug -----------------------------------------------------------------------

func test_nothing_is_announced_before_the_first_tick() -> void:
	# Setup runs when `minigame_started` goes out; the clients build their stage behind the curtain
	# after it, so a match announced here would be missed and the first round played "against
	# nobody". The show starts on the first tick (after the briefing).
	var g := _game([1, 2, 3, 4])
	assert_eq(g.drain_events().size(), 0)
	assert_eq(g.state, SplitOrStealLogic.State.WAITING)
	assert_eq(g.current_pair(), [] as Array[int])
	assert_eq(_pick(g, 1, S)["error"], &"not_your_turn")
	g.tick(0.05, now)
	var ev: Array[Dictionary] = g.drain_events()
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["type"], &"split_or_steal_started")
	assert_eq((ev[0]["schedule"] as Array).size(), 4, "the schedule goes out with the start")
	_run(g, 0.6)
	var pairs: Array = _of_type(g.drain_events(), &"split_or_steal_pair")
	assert_eq(pairs.size(), 1)
	assert_eq(int(pairs[0]["index"]), 0)
	assert_ne(int(pairs[0]["a"]), NOBODY)
	assert_ne(int(pairs[0]["b"]), NOBODY)


func test_private_state_carries_the_pair_for_a_stage_that_missed_events() -> void:
	var g := _game([1, 2, 3])
	_to_decide(g)
	var pair: Array[int] = g.current_pair()
	var priv: Dictionary = g.private_state(pair[0])
	assert_eq(priv["pair"], pair)
	assert_eq(int(priv["index"]), 0)
	assert_eq(int(priv["state"]), SplitOrStealLogic.State.DECIDE)
	assert_true(priv["in_pair"])
	assert_true(priv["can_choose"])
	var watcher: int = ([1, 2, 3] as Array[int]).filter(func(p: int) -> bool: return p not in pair)[0]
	var wpriv: Dictionary = g.private_state(watcher)
	assert_false(wpriv["in_pair"])
	assert_false(wpriv["can_choose"])
	assert_eq(wpriv["pair"], pair, "watchers see who is on stage too")


# --- Flow --------------------------------------------------------------------------------------

func test_pairs_play_one_at_a_time_in_schedule_order() -> void:
	var g := _game([1, 2, 3, 4, 5, 6])
	var order: Array = []
	var guard: int = 0
	while not g.finished and guard < 10000:
		g.tick(0.05, now)
		guard += 1
		for e: Dictionary in g.drain_events():
			if e["type"] == &"split_or_steal_pair":
				order.append([int(e["a"]), int(e["b"])])
				assert_eq(int(e["index"]), order.size() - 1, "sequential")
	assert_eq(order.size(), 3)
	for i: int in 3:
		assert_eq(order[i], [int(g.schedule[i]["a"]), int(g.schedule[i]["b"])])


func test_announce_then_decide() -> void:
	var g := _game([1, 2])
	_run(g, 0.6)
	assert_eq(g.state, SplitOrStealLogic.State.ANNOUNCE)
	var pair: Array[int] = g.current_pair()
	assert_eq(_pick(g, pair[0], S)["error"], &"not_decide_phase", "not while walking up")
	_to_decide(g)
	assert_true(_pick(g, pair[0], S)["ok"])


func test_watchers_are_refused() -> void:
	var g := _game([1, 2, 3, 4, 5])
	_to_decide(g)
	var pair: Array[int] = g.current_pair()
	for p: int in [1, 2, 3, 4, 5]:
		if p not in pair:
			assert_eq(_pick(g, p, S)["error"], &"not_your_turn")
	assert_eq(_pick(g, 99, S)["error"], &"unknown_player")


func test_rejections() -> void:
	var g := _game([1, 2])
	_to_decide(g)
	assert_eq(_pick(g, 1, "MAYBE")["error"], &"invalid_choice")
	assert_true(_pick(g, 1, "steal")["ok"], "lowercase accepted")
	assert_eq(g.choices[1], T)
	assert_eq(_pick(g, 1, S)["error"], &"already_chose")


func test_locked_event_hides_choice() -> void:
	var g := _game([1, 2])
	_to_decide(g)
	g.drain_events()
	_pick(g, 1, T)
	var locked: Array = _of_type(g.drain_events(), &"split_or_steal_locked")
	assert_eq(locked.size(), 1)
	assert_eq(int(locked[0]["player"]), 1)
	assert_false(locked[0].has("choice"), "never what")
	assert_eq(g.get_public_state()["locked"], [1])
	assert_false(str(g.get_public_state()).contains(T), "the choice stays secret in the snapshot")


func test_reveal_comes_early_when_both_decided() -> void:
	var g := _game([1, 2], {"decide_time": 10.0})
	_to_decide(g)
	_pick(g, 1, S)
	g.tick(0.05, now)
	assert_eq(g.state, SplitOrStealLogic.State.DECIDE, "one still thinking")
	_pick(g, 2, S)
	g.tick(0.05, now)
	assert_eq(g.state, SplitOrStealLogic.State.REVEAL)


func test_timeout_counts_as_split() -> void:
	var g := _game([1, 2])
	_to_decide(g)
	var pair: Array[int] = g.current_pair()
	_pick(g, pair[0], T)
	g.drain_events()
	_to_next_reveal(g)
	var rev: Array = _of_type(g.drain_events(), &"split_or_steal_reveal")
	assert_eq(rev.size(), 1)
	var r: Dictionary = rev[0]
	assert_eq(r["choice_a"], T)
	assert_eq(r["choice_b"], S)
	assert_true(r["auto_b"])
	assert_false(r["auto_a"])
	assert_eq(int(r["points_a"]), 3)
	assert_eq(g.points[pair[0]], 3)


func test_payoff_matrix() -> void:
	assert_eq(SplitOrStealLogic.payoff(S, S), [1, 1] as Array[int])
	assert_eq(SplitOrStealLogic.payoff(T, S), [3, 0] as Array[int])
	assert_eq(SplitOrStealLogic.payoff(S, T), [0, 3] as Array[int])
	assert_eq(SplitOrStealLogic.payoff(T, T), [0, 0] as Array[int])


func _play_match(g: SplitOrStealLogic, ca: String, cb: String) -> Dictionary:
	_to_decide(g)
	var pair: Array[int] = g.current_pair()
	_pick(g, pair[0], ca)
	_pick(g, pair[1], cb)
	g.tick(0.05, now)
	return g.schedule[g.pair_index]["result"]


func test_scoring_both_split_steal_and_both_steal() -> void:
	var g := _game([1, 2])
	var r: Dictionary = _play_match(g, S, S)
	assert_eq([int(r["points_a"]), int(r["points_b"])], [1, 1])
	r = _play_match(g, T, S)
	assert_eq([int(r["points_a"]), int(r["points_b"])], [3, 0])
	r = _play_match(g, T, T)
	assert_eq([int(r["points_a"]), int(r["points_b"])], [0, 0])
	var a: int = int(r["a"])
	var b: int = int(r["b"])
	# The schedule may flip sides between matches: sum per player.
	assert_eq(g.points[a] + g.points[b], 5)
	assert_eq(g.steals[a] + g.steals[b], 3)


func test_house_match_scores_only_the_leftover() -> void:
	var g := _game([1, 2, 3, 4, 5])
	for i: int in 2:
		_play_match(g, S, S)
	_to_decide(g)
	assert_eq(g.pair_index, 2)
	var e: Dictionary = g.schedule[2]
	var house: int = int(e["house"])
	var leftover: int = int(e["b"]) if int(e["a"]) == house else int(e["a"])
	var house_before: int = g.points[house]
	_pick(g, house, T)
	_pick(g, leftover, S)
	g.tick(0.05, now)
	assert_eq(g.points[house], house_before, "the stand-in scores nothing")
	assert_eq(g.steals[house], 0, "nor is the house steal counted")
	assert_eq(g.points[leftover], 0)
	var r: Dictionary = g.schedule[2]["result"]
	assert_eq(int(r["house"]), house)


func test_full_show_finishes_with_ranking() -> void:
	var g := _game([1, 2, 3, 4])
	var guard: int = 0
	while not g.finished and guard < 10000:
		if g.state == SplitOrStealLogic.State.DECIDE:
			for p: int in g.current_pair():
				if not g.choices.has(p):
					_pick(g, p, T if p == 1 else S)
		g.tick(0.05, now)
		guard += 1
	assert_true(g.finished)
	var reveals: int = 0
	var fin: Array = []
	for e: Dictionary in g.drain_events():
		if e["type"] == &"split_or_steal_reveal":
			reveals += 1
		elif e["type"] == &"split_or_steal_finished":
			fin.append(e)
	assert_eq(reveals, 4)
	assert_eq(fin.size(), 1)
	var rows: Array[Dictionary] = g.ranking()
	assert_eq(rows.size(), 4)
	assert_eq(int(rows[0]["player"]), 1, "the stealer robbed two splitters: 6 points")
	assert_eq(int(rows[0]["points"]), 6)
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
	var g := SplitOrStealLogic.new()
	g.setup([1, 2, 3, 4, 5, 6, 7, 8] as Array[int], SeededRng.new(1), cfg, {}, {})
	var t: float = 0.0
	while not g.finished and t < 200.0:
		g.tick(0.05, now)
		t += 0.05
	assert_true(g.finished)
	assert_lt(t, SplitOrStealLogic.GAME_CAP + 1.0, "nobody deciding: every match runs its full timer")


func test_player_leaving_mid_match_does_not_block() -> void:
	var g := _game([1, 2, 3, 4], {"decide_time": 30.0})
	_to_decide(g)
	var pair: Array[int] = g.current_pair()
	_pick(g, pair[0], S)
	g.remove_player(pair[1])
	g.tick(0.05, now)
	assert_eq(g.state, SplitOrStealLogic.State.REVEAL, "the one left already decided")


func test_leaver_gets_replaced_by_a_house_stand_in() -> void:
	var g := _game([1, 2, 3, 4, 5, 6])
	_play_match(g, S, S)
	var next: Dictionary = g.schedule[1]
	var gone: int = int(next["a"])
	var stays: int = int(next["b"])
	g.remove_player(gone)
	_to_decide(g)
	var e: Dictionary = g.schedule[1]
	assert_true(stays in g.current_pair(), "the one still here gets their match")
	assert_false(gone in g.current_pair())
	assert_ne(int(e["house"]), NOBODY)
	assert_ne(int(e["house"]), stays)


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
	var g := _game([1, 2, 3])
	_play_match(g, T, S)
	_to_decide(g)
	var pair: Array[int] = g.current_pair()
	_pick(g, pair[0], S)
	var st: Dictionary = g.get_public_state()
	assert_eq(st["minigame"], &"split_or_steal")
	assert_eq(int(st["state"]), SplitOrStealLogic.State.DECIDE)
	assert_eq(int(st["index"]), 1)
	assert_eq(int(st["total"]), 3)
	var sched: Array = st["schedule"]
	assert_eq(sched.size(), 3)
	assert_eq((sched[0]["result"] as Dictionary)["choice_a"], T, "revealed decisions are public")
	assert_true((sched[1]["result"] as Dictionary).is_empty(), "the current one is not")
	assert_eq(st["locked"], [pair[0]])
	var total: int = 0
	for p: Variant in st["points"]:
		total += int(st["points"][p])
	assert_eq(total, 3, "running totals")
	assert_gt(float(st["timer"]), 0.0)


func test_snapshot_ranking_in_outro() -> void:
	var g := _game([1, 2])
	var guard: int = 0
	while g.state != SplitOrStealLogic.State.OUTRO and guard < 10000:
		g.tick(0.05, now)
		guard += 1
	assert_eq((g.get_public_state()["ranking"] as Array).size(), 2)
