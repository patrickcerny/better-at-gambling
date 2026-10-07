extends GutTest
## Vote Race minigame logic tests.

var cfg: BalanceConfig
var now: float = 0.0


func before_each() -> void:
	cfg = BalanceConfig.new()
	now = 0.0


func _vote_race(players: Array[int]) -> VoteRaceLogic:
	var logic: VoteRaceLogic = VoteRaceLogic.new()
	logic.setup(players, SeededRng.new(5), cfg, {}, {})
	return logic


func test_game_initialization_with_enough_players() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	assert_false(logic.is_finished())
	assert_eq(logic.positions.size(), 4)
	for p: int in [1, 2, 3, 4]:
		assert_eq(logic.positions[p], 0)


func test_game_ends_immediately_with_too_few_players() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3])
	assert_true(logic.is_finished())


func test_single_vote_round() -> void:
	var events: Array[Dictionary] = []
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	events.append_array(logic.drain_events())

	# Each player votes for someone else
	logic.submit(1, {"target": 2}, now)
	logic.submit(2, {"target": 3}, now)
	logic.submit(3, {"target": 4}, now)
	logic.submit(4, {"target": 1}, now)
	events.append_array(logic.drain_events())

	# All players got votes, so positions don't change (no zero-vote winners)
	assert_false(logic.is_finished())

	# Verify all players are still at position 0
	for p: int in [1, 2, 3, 4]:
		assert_eq(logic.positions[p], 0)


func test_player_without_votes_advances() -> void:
	var events: Array[Dictionary] = []
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	events.append_array(logic.drain_events())

	# Players 1, 2, 3 all vote for player 4
	logic.submit(1, {"target": 4}, now)
	logic.submit(2, {"target": 4}, now)
	logic.submit(3, {"target": 4}, now)
	logic.submit(4, {"target": 1}, now)
	events.append_array(logic.drain_events())

	# Player 2 and 3 should have advanced (no votes)
	assert_eq(logic.positions[2], 1)
	assert_eq(logic.positions[3], 1)


func test_cannot_vote_for_self() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	logic.drain_events()

	var result: Dictionary = logic.submit(1, {"target": 1}, now)
	assert_false(result.get("ok", false))
	assert_eq(result.get("error", ""), &"cannot_vote_self")


func test_cannot_vote_twice() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	logic.drain_events()

	logic.submit(1, {"target": 2}, now)
	var result: Dictionary = logic.submit(1, {"target": 3}, now)

	assert_false(result.get("ok", false))
	assert_eq(result.get("error", ""), &"already_voted")


func test_invalid_target() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	logic.drain_events()

	var result: Dictionary = logic.submit(1, {"target": 999}, now)
	assert_false(result.get("ok", false))
	assert_eq(result.get("error", ""), &"invalid_target")


func test_ranking_by_position() -> void:
	var events: Array[Dictionary] = []
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	events.append_array(logic.drain_events())

	# Simulate several rounds to reach finish
	for round_num: int in 10:
		if logic.is_finished():
			break

		# Player 1 always gets votes (stays put), others advance
		logic.submit(2, {"target": 1}, now)
		logic.submit(3, {"target": 1}, now)
		logic.submit(4, {"target": 1}, now)
		logic.submit(1, {"target": 2}, now)
		events.append_array(logic.drain_events())

	var ranking: Array = logic.ranking()
	assert_eq(ranking.size(), 4)
	# Higher positions should rank first
	assert_gte(ranking[0]["position"], ranking[1]["position"])


func test_game_ends_at_winning_position() -> void:
	var events: Array[Dictionary] = []
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	events.append_array(logic.drain_events())

	# Simulate rounds until someone wins
	var max_rounds: int = 50
	for round_num: int in max_rounds:
		if logic.is_finished():
			break

		# Players 2, 3, 4 vote for player 1, player 1 votes for player 2
		# This means only 2, 3, 4 advance
		logic.submit(1, {"target": 4}, now)
		logic.submit(2, {"target": 1}, now)
		logic.submit(3, {"target": 1}, now)
		logic.submit(4, {"target": 1}, now)
		events.append_array(logic.drain_events())

	assert_true(logic.is_finished())
	assert_ne(logic.winner, -1)


func test_public_state_hides_nothing_wrong() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	logic.drain_events()

	logic.submit(1, {"target": 2}, now)
	logic.submit(2, {"target": 3}, now)
	logic.submit(3, {"target": 4}, now)
	logic.submit(4, {"target": 1}, now)

	var state: Dictionary = logic.get_public_state()
	assert_true(state.has("positions"))
	assert_true(state.has("votes"))
	assert_true(state.has("vote_counts"))
	assert_eq(state["votes"].size(), 4)
