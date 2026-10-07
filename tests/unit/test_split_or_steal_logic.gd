extends GutTest
## Split or Steal Tournament: round-robin schedule (simultaneous pairs, bye for odd counts, round
## cap), TALK → PICK → REVEAL flow, payoffs (1/1, 3/0, 0/0), ranking (points, then fewer steals).

const S: String = SplitOrStealLogic.SPLIT
const T: String = SplitOrStealLogic.STEAL

var cfg: BalanceConfig = BalanceConfig.new()
var now: float = 0.0


func _game(players: Array[int], params: Dictionary = {}) -> SplitOrStealLogic:
	var g := SplitOrStealLogic.new()
	var p: Dictionary = {"talk_time": 1.0, "pick_time": 1.0, "reveal_time": 0.5, "outro_time": 0.5}
	p.merge(params, true)
	g.setup(players, SeededRng.new(5), cfg, p, {})
	return g


func _run(g: SplitOrStealLogic, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		g.tick(0.05, now)
		t += 0.05


func _to_pick(g: SplitOrStealLogic) -> void:
	while g.state != SplitOrStealLogic.State.PICK and not g.finished:
		g.tick(0.05, now)


func _pair_key(a: int, b: int) -> String:
	return "%d-%d" % [mini(a, b), maxi(a, b)]


func _of_type(events: Array[Dictionary], type: StringName) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


# --- Schedule ---------------------------------------------------------------------------------

func test_even_round_robin_everyone_meets_everyone_once() -> void:
	var rounds: Array[Dictionary] = SplitOrStealLogic.build_schedule([1, 2, 3, 4, 5, 6], SeededRng.new(1))
	assert_eq(rounds.size(), 5)
	var seen: Dictionary = {}
	for r: Dictionary in rounds:
		assert_eq(r["bye"], SplitOrStealLogic.BYE, "nobody sits out with an even count")
		var in_round: Dictionary = {}
		for pair: Array in r["pairs"]:
			assert_false(in_round.has(pair[0]) or in_round.has(pair[1]), "a player plays once per round")
			in_round[pair[0]] = true
			in_round[pair[1]] = true
			var k: String = _pair_key(pair[0], pair[1])
			assert_false(seen.has(k), "pair %s repeats" % k)
			seen[k] = true
	assert_eq(seen.size(), 15, "6 choose 2")


func test_odd_round_robin_has_one_bye_per_round() -> void:
	var rounds: Array[Dictionary] = SplitOrStealLogic.build_schedule([1, 2, 3, 4, 5], SeededRng.new(2))
	assert_eq(rounds.size(), 5)
	var byes: Dictionary = {}
	var seen: Dictionary = {}
	for r: Dictionary in rounds:
		assert_ne(r["bye"], SplitOrStealLogic.BYE)
		byes[r["bye"]] = true
		assert_eq((r["pairs"] as Array).size(), 2)
		for pair: Array in r["pairs"]:
			seen[_pair_key(pair[0], pair[1])] = true
	assert_eq(byes.size(), 5, "everyone sits out exactly once")
	assert_eq(seen.size(), 10, "5 choose 2")


func test_two_and_three_players() -> void:
	assert_eq(SplitOrStealLogic.build_schedule([1, 2], null).size(), 1)
	assert_eq(SplitOrStealLogic.build_schedule([1, 2, 3], null).size(), 3)
	assert_eq(SplitOrStealLogic.build_schedule([1], null).size(), 0)


func test_eight_players_capped_at_five_rounds() -> void:
	var g: SplitOrStealLogic = _game([1, 2, 3, 4, 5, 6, 7, 8])
	assert_eq(g.get_public_state()["total_rounds"], 5)
	var uncapped: SplitOrStealLogic = _game([1, 2, 3, 4, 5, 6, 7, 8], {"max_rounds": 0})
	assert_eq(uncapped.get_public_state()["total_rounds"], 7)


# --- Payoffs ----------------------------------------------------------------------------------

func test_payoff_matrix() -> void:
	assert_eq(SplitOrStealLogic.payoff(S, S), [1, 1] as Array[int])
	assert_eq(SplitOrStealLogic.payoff(T, S), [3, 0] as Array[int])
	assert_eq(SplitOrStealLogic.payoff(S, T), [0, 3] as Array[int])
	assert_eq(SplitOrStealLogic.payoff(T, T), [0, 0] as Array[int])


func _one_match(a: String, b: String) -> SplitOrStealLogic:
	var g: SplitOrStealLogic = _game([1, 2])
	_to_pick(g)
	assert_true(g.submit(1, {"choice": a}, now)["ok"])
	assert_true(g.submit(2, {"choice": b}, now)["ok"])
	g.tick(0.05, now)
	return g


func test_both_split_one_point_each() -> void:
	var g: SplitOrStealLogic = _one_match(S, S)
	assert_eq(g.points[1], 1)
	assert_eq(g.points[2], 1)
	assert_eq(g.splits[1], 1)


func test_stealer_takes_three_splitter_zero() -> void:
	var g: SplitOrStealLogic = _one_match(T, S)
	assert_eq(g.points[1], 3)
	assert_eq(g.points[2], 0)
	assert_eq(g.steals[1], 1)
	assert_eq(g.steals[2], 0)


func test_both_steal_zero() -> void:
	var g: SplitOrStealLogic = _one_match(T, T)
	assert_eq(g.points[1], 0)
	assert_eq(g.points[2], 0)
	assert_eq(g.steals[1], 1)
	assert_eq(g.steals[2], 1)


func test_lowercase_choice_accepted() -> void:
	var g: SplitOrStealLogic = _game([1, 2])
	_to_pick(g)
	assert_true(g.submit(1, {"choice": "steal"}, now)["ok"])


func test_no_pick_counts_as_split() -> void:
	var g: SplitOrStealLogic = _game([1, 2])
	_to_pick(g)
	g.submit(1, {"choice": T}, now)
	g.drain_events()
	_run(g, 1.1)  # pick window runs out
	assert_eq(g.points[1], 3)
	assert_eq(g.points[2], 0)
	var reveal: Array = _of_type(g.drain_events(), &"split_or_steal_reveal")
	assert_eq(reveal.size(), 1)
	var res: Dictionary = reveal[0]["results"][0]
	assert_true(res["auto_b"] if res["player_b"] == 2 else res["auto_a"])


# --- Flow -------------------------------------------------------------------------------------

func test_cannot_pick_during_talk() -> void:
	var g: SplitOrStealLogic = _game([1, 2])
	assert_eq(g.state, SplitOrStealLogic.State.TALK)
	assert_eq(g.submit(1, {"choice": S}, now)["error"], &"not_pick_phase")
	assert_false(g.private_state(1)["can_choose"])


func test_reveal_comes_early_when_all_picked() -> void:
	var g: SplitOrStealLogic = _game([1, 2, 3, 4])
	_to_pick(g)
	for p: int in [1, 2, 3, 4]:
		g.submit(p, {"choice": S}, now)
	g.tick(0.05, now)
	assert_eq(g.state, SplitOrStealLogic.State.REVEAL)
	for p: int in [1, 2, 3, 4]:
		assert_eq(g.points[p], 1, "all pairs score in the same round")


func test_bye_player_cannot_pick() -> void:
	var g: SplitOrStealLogic = _game([1, 2, 3])
	_to_pick(g)
	var bye: int = g.schedule[0]["bye"]
	assert_eq(g.submit(bye, {"choice": S}, now)["error"], &"sitting_out")
	var priv: Dictionary = g.private_state(bye)
	assert_false(priv["in_current_match"])
	assert_false(priv["can_choose"])


func test_private_state_can_choose() -> void:
	var g: SplitOrStealLogic = _game([1, 2])
	_to_pick(g)
	assert_true(g.private_state(1)["can_choose"])
	assert_eq(g.private_state(1)["opponent"], 2)
	g.submit(1, {"choice": T}, now)
	assert_false(g.private_state(1)["can_choose"])
	assert_eq(g.private_state(1)["my_choice"], T)
	assert_eq(g.private_state(2)["my_choice"], "", "never sees the opponent's pick")


func test_rejections() -> void:
	var g: SplitOrStealLogic = _game([1, 2])
	_to_pick(g)
	assert_eq(g.submit(99, {"choice": S}, now)["error"], &"unknown_player")
	assert_eq(g.submit(1, {"choice": "BETRAY"}, now)["error"], &"invalid_choice")
	assert_true(g.submit(1, {"choice": S}, now)["ok"])
	assert_eq(g.submit(1, {"choice": T}, now)["error"], &"already_chose")


func test_locked_event_hides_choice() -> void:
	var g: SplitOrStealLogic = _game([1, 2])
	_to_pick(g)
	g.drain_events()
	g.submit(1, {"choice": T}, now)
	var locked: Array = _of_type(g.drain_events(), &"split_or_steal_locked")
	assert_eq(locked.size(), 1)
	assert_false(locked[0].has("choice"))


func test_full_tournament_finishes_and_tracks_points() -> void:
	var g: SplitOrStealLogic = _game([1, 2, 3, 4])
	var all: Array[Dictionary] = g.drain_events()
	var guard: int = 0
	while not g.finished and guard < 5000:
		guard += 1
		if g.state == SplitOrStealLogic.State.PICK:
			for p: int in [1, 2, 3, 4]:
				if g.opponent_of(p) != SplitOrStealLogic.BYE and not g.choices.has(p):
					g.submit(p, {"choice": T if p == 1 else S}, now)  # 1 always steals
		g.tick(0.05, now)
		all.append_array(g.drain_events())
	assert_true(g.finished)
	assert_eq(_of_type(all, &"split_or_steal_round").size(), 3)
	assert_eq(_of_type(all, &"split_or_steal_reveal").size(), 3)
	assert_eq(_of_type(all, &"split_or_steal_finished").size(), 1)
	# 1 robs everyone: 3 × 3. The others split with each other twice and get robbed once: 2.
	assert_eq(g.points[1], 9)
	for p: int in [2, 3, 4]:
		assert_eq(g.points[p], 2)
	assert_eq(g.steals[1], 3)
	var r: Array[Dictionary] = g.ranking()
	assert_eq(r[0]["player"], 1)
	assert_eq(r[0]["rank"], 1)
	assert_eq(r[1]["rank"], 2)
	assert_eq(r[3]["rank"], 2, "equal points and steals share a rank")


func test_outro_holds_before_finished() -> void:
	var g: SplitOrStealLogic = _one_match(S, S)
	_run(g, 0.55)  # reveal over → outro
	assert_eq(g.state, SplitOrStealLogic.State.OUTRO)
	assert_false(g.finished)
	assert_eq(g.submit(1, {"choice": S}, now)["error"], &"game_over")
	_run(g, 0.6)
	assert_true(g.finished)


func test_player_leaving_does_not_block_round() -> void:
	var g: SplitOrStealLogic = _game([1, 2])
	_to_pick(g)
	g.submit(1, {"choice": S}, now)
	g.remove_player(2)
	g.tick(0.05, now)
	assert_eq(g.state, SplitOrStealLogic.State.REVEAL, "nothing left to wait for")
	assert_eq(g.points[1], 0, "no match, no points")


# --- Ranking ----------------------------------------------------------------------------------

func test_ranking_by_points() -> void:
	var g: SplitOrStealLogic = _game([1, 2, 3])
	g.points = {1: 2, 2: 6, 3: 4}
	var r: Array[Dictionary] = g.ranking()
	assert_eq(r.map(func(row: Dictionary) -> int: return row["player"]), [2, 3, 1])
	assert_eq(r.map(func(row: Dictionary) -> int: return row["rank"]), [1, 2, 3])


func test_ranking_tie_goes_to_fewer_steals() -> void:
	var g: SplitOrStealLogic = _game([1, 2, 3])
	g.points = {1: 3, 2: 3, 3: 1}
	g.steals = {1: 1, 2: 0, 3: 0}
	var r: Array[Dictionary] = g.ranking()
	assert_eq(r[0]["player"], 2, "the nicer player wins the tie")
	assert_eq(r[0]["rank"], 1)
	assert_eq(r[1]["player"], 1)
	assert_eq(r[1]["rank"], 2)
	assert_eq(r[0]["steals"], 0)


func test_ranking_full_tie_shares_rank() -> void:
	var g: SplitOrStealLogic = _game([1, 2])
	g.points = {1: 1, 2: 1}
	g.steals = {1: 0, 2: 0}
	var r: Array[Dictionary] = g.ranking()
	assert_eq(r[0]["rank"], 1)
	assert_eq(r[1]["rank"], 1)


# --- Snapshot ---------------------------------------------------------------------------------

func test_public_state_for_late_join() -> void:
	var g: SplitOrStealLogic = _game([1, 2, 3])
	var st: Dictionary = g.get_public_state()
	assert_eq(st["minigame"], &"split_or_steal", "the match scene opens the right stage")
	assert_eq(st["total_rounds"], 3)
	assert_eq(st["round"], 0)
	assert_true(st.has("pairs"))
	assert_true(st.has("bye"))


func test_events_started_then_round() -> void:
	var g: SplitOrStealLogic = _game([1, 2])
	var ev: Array[Dictionary] = g.drain_events()
	assert_eq(ev[0]["type"], &"split_or_steal_started")
	assert_eq(ev[0]["total_rounds"], 1)
	assert_eq(ev[1]["type"], &"split_or_steal_round")
	assert_eq(ev[1]["pairs"].size(), 1)
