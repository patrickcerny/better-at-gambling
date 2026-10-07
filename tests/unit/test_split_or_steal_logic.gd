extends GutTest
## Split or Steal Tournament rules: round-robin tournament, SPLIT/STEAL choices,
## payoff matrix: both SPLIT=500 each, both STEAL=0 each, one steals=1000/0.

var cfg: BalanceConfig = BalanceConfig.new()
var now: float = 0.0


func before_each() -> void:
	now = 0.0


func _tournament(players: Array[int]) -> SplitOrStealLogic:
	var s := SplitOrStealLogic.new()
	s.setup(players, SeededRng.new(5), cfg, {}, {})
	return s


func test_two_players_one_match() -> void:
	var s: SplitOrStealLogic = _tournament([1, 2])
	var state: Dictionary = s.get_public_state()
	assert_eq(state["total_matches"], 1)


func test_three_players_three_matches() -> void:
	var s: SplitOrStealLogic = _tournament([1, 2, 3])
	var state: Dictionary = s.get_public_state()
	# 3 choose 2 = 3 matches
	assert_eq(state["total_matches"], 3)


func test_four_players_six_matches() -> void:
	var s: SplitOrStealLogic = _tournament([1, 2, 3, 4])
	var state: Dictionary = s.get_public_state()
	# 4 choose 2 = 6 matches
	assert_eq(state["total_matches"], 6)


func test_both_split_earns_500_each() -> void:
	var s: SplitOrStealLogic = _tournament([1, 2])

	s.tick(0.05, now)  # Start first match
	s.submit(1, {"choice": "SPLIT"}, now)
	s.submit(2, {"choice": "SPLIT"}, now)
	s.tick(0.05, now)

	var state: Dictionary = s.get_public_state()
	assert_eq(state["scores"][1], 500)
	assert_eq(state["scores"][2], 500)


func test_both_steal_earns_zero() -> void:
	var s: SplitOrStealLogic = _tournament([1, 2])

	s.tick(0.05, now)  # Start first match
	s.submit(1, {"choice": "STEAL"}, now)
	s.submit(2, {"choice": "STEAL"}, now)
	s.tick(0.05, now)

	var state: Dictionary = s.get_public_state()
	assert_eq(state["scores"][1], 0)
	assert_eq(state["scores"][2], 0)


func test_one_steal_one_split_stealer_wins() -> void:
	var s: SplitOrStealLogic = _tournament([1, 2])

	s.tick(0.05, now)  # Start first match
	s.submit(1, {"choice": "STEAL"}, now)
	s.submit(2, {"choice": "SPLIT"}, now)
	s.tick(0.05, now)

	var state: Dictionary = s.get_public_state()
	assert_eq(state["scores"][1], 1000, "Stealer gets 1000")
	assert_eq(state["scores"][2], 0, "Splitter gets 0")


func test_game_ends_after_all_matches() -> void:
	var s: SplitOrStealLogic = _tournament([1, 2])

	s.tick(0.05, now)  # Start first match
	s.submit(1, {"choice": "SPLIT"}, now)
	s.submit(2, {"choice": "SPLIT"}, now)
	s.tick(0.05, now)
	now += 0.05

	assert_true(s.is_finished())


func test_invalid_choice_rejected() -> void:
	var s: SplitOrStealLogic = _tournament([1, 2])

	s.tick(0.05, now)  # Start first match
	var result: Dictionary = s.submit(1, {"choice": "BETRAY"}, now)
	assert_eq(result["error"], &"invalid_choice")


func test_double_choice_rejected() -> void:
	var s: SplitOrStealLogic = _tournament([1, 2])

	s.tick(0.05, now)  # Start first match
	assert_true(s.submit(1, {"choice": "SPLIT"}, now)["ok"])
	var result: Dictionary = s.submit(1, {"choice": "STEAL"}, now)
	assert_eq(result["error"], &"already_chose")


func test_unknown_player_rejected() -> void:
	var s: SplitOrStealLogic = _tournament([1, 2])

	s.tick(0.05, now)  # Start first match
	var result: Dictionary = s.submit(99, {"choice": "SPLIT"}, now)
	assert_eq(result["error"], &"unknown_player")


func test_player_not_in_match_rejected() -> void:
	var s: SplitOrStealLogic = _tournament([1, 2, 3])

	s.tick(0.05, now)  # Start first match
	# First match is only between two players
	var result: Dictionary = s.submit(3, {"choice": "SPLIT"}, now)
	assert_eq(result["error"], &"not_in_current_match")


func test_ranking_by_total_score() -> void:
	var s: SplitOrStealLogic = _tournament([1, 2, 3])

	# Manually set scores
	s.player_scores[1] = 1500
	s.player_scores[2] = 1000
	s.player_scores[3] = 500
	s.finished = true

	var ranking: Array[Dictionary] = s.ranking()
	assert_eq(ranking[0]["player"], 1)
	assert_eq(ranking[1]["player"], 2)
	assert_eq(ranking[2]["player"], 3)


func test_events_emitted() -> void:
	var s: SplitOrStealLogic = _tournament([1, 2])
	var events: Array[Dictionary] = s.drain_events()

	var started: Array = events.filter(func(e: Dictionary) -> bool:
		return e["type"] == &"split_or_steal_started"
	)
	assert_eq(started.size(), 1)


func test_pairing_event() -> void:
	var s: SplitOrStealLogic = _tournament([1, 2])
	s.drain_events()

	s.tick(0.05, now)  # Trigger first match start
	var events: Array[Dictionary] = s.drain_events()

	var pairing: Array = events.filter(func(e: Dictionary) -> bool:
		return e["type"] == &"split_or_steal_pairing"
	)
	assert_eq(pairing.size(), 1)


func test_payoff_event() -> void:
	var s: SplitOrStealLogic = _tournament([1, 2])
	s.drain_events()

	s.tick(0.05, now)  # Start first match
	s.submit(1, {"choice": "SPLIT"}, now)
	s.submit(2, {"choice": "STEAL"}, now)
	s.tick(0.05, now)

	var events: Array[Dictionary] = s.drain_events()
	var payoff: Array = events.filter(func(e: Dictionary) -> bool:
		return e["type"] == &"split_or_steal_payoff"
	)
	assert_eq(payoff.size(), 1)
	assert_eq(payoff[0]["payoff_a"], 0)
	assert_eq(payoff[0]["payoff_b"], 1000)
