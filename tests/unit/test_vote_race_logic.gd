extends GutTest
## Vote Race minigame logic tests: secret ballots, zero-vote movement, timeouts, finishing order.

var cfg: BalanceConfig
var now: float = 0.0


func before_each() -> void:
	cfg = BalanceConfig.new()
	now = 0.0


func _vote_race(players: Array[int]) -> VoteRaceLogic:
	var logic: VoteRaceLogic = VoteRaceLogic.new()
	logic.setup(players, SeededRng.new(5), cfg, {}, {})
	return logic


## Casts `ballot` (voter → target); anyone missing times out. Resolves the round but stays in
## the reveal (votes still held server-side).
func _vote(logic: VoteRaceLogic, ballot: Dictionary) -> void:
	for voter: int in ballot:
		var res: Dictionary = logic.submit(voter, {"target": ballot[voter]}, now)
		assert_true(bool(res.get("ok", false)), "vote %d→%d refused: %s" % [voter, ballot[voter], res])
	if logic.phase == VoteRaceLogic.RaceState.VOTING:
		logic.tick(VoteRaceLogic.VOTE_TIME + 0.01, now)


## A full round: vote, resolve, finish the reveal (next round or game over).
func _round(logic: VoteRaceLogic, ballot: Dictionary) -> void:
	_vote(logic, ballot)
	logic.tick(VoteRaceLogic.REVEAL_TIME + 0.01, now)


func _events_of(events: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev: Dictionary in events:
		if ev["type"] == type:
			out.append(ev)
	return out


func _rank_of(logic: VoteRaceLogic, p: int) -> int:
	for row: Dictionary in logic.ranking():
		if int(row["player"]) == p:
			return int(row["rank"])
	return -1


# --- Setup --------------------------------------------------------------------------------------

func test_game_initialization_with_enough_players() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	assert_false(logic.is_finished())
	assert_eq(logic.phase, VoteRaceLogic.RaceState.VOTING)
	assert_eq(logic.racing.size(), 4)
	for p: int in [1, 2, 3, 4]:
		assert_eq(logic.positions[p], 0)


func test_game_ends_immediately_with_too_few_players() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3])
	assert_true(logic.is_finished())


# --- Secrecy ------------------------------------------------------------------------------------

func test_public_state_never_contains_current_votes() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	logic.submit(1, {"target": 2}, now)
	logic.submit(2, {"target": 3}, now)
	var state: Dictionary = logic.get_public_state()
	assert_false(state.has("votes"), "current ballot must not be public")
	assert_false(state.has("vote_counts"), "current tally must not be public")
	assert_true((state["last_reveal"] as Dictionary).is_empty(), "nothing resolved yet")
	assert_eq(state["votes_cast"], 2)
	assert_eq(state["phase"], "voting")
	assert_true(state.has("positions"))


func test_vote_events_do_not_reveal_target() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	logic.drain_events()
	logic.submit(1, {"target": 3}, now)
	var evs: Array[Dictionary] = logic.drain_events()
	assert_eq(evs.size(), 1)
	assert_eq(evs[0]["type"], &"vote_race_voted")
	assert_false(evs[0].has("target"))
	assert_false(str(evs[0]).contains("3"), "no trace of the target in the event")


func test_private_state_only_shows_own_vote() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	logic.submit(1, {"target": 3}, now)
	assert_eq(logic.private_state(1)["voted_for"], 3)
	assert_false(logic.private_state(1)["can_vote"])
	assert_eq(logic.private_state(2)["voted_for"], -1)
	assert_true(logic.private_state(2)["can_vote"])


func test_reveal_publishes_who_voted_for_whom_after_resolution() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	logic.drain_events()
	_vote(logic, {1: 4, 2: 4, 3: 4, 4: 1})
	var reveals: Array[Dictionary] = _events_of(logic.drain_events(), &"vote_race_reveal")
	assert_eq(reveals.size(), 1)
	assert_eq(reveals[0]["votes"], {1: 4, 2: 4, 3: 4, 4: 1})
	var state: Dictionary = logic.get_public_state()
	assert_eq(state["phase"], "reveal")
	assert_eq(state["last_reveal"]["votes"], {1: 4, 2: 4, 3: 4, 4: 1})
	assert_eq(state["last_reveal"]["vote_counts"][4], 3)


# --- Vote clearing ------------------------------------------------------------------------------

func test_votes_kept_through_reveal_and_cleared_on_next_round() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	_vote(logic, {1: 2, 2: 3, 3: 4, 4: 1})
	assert_eq(logic.phase, VoteRaceLogic.RaceState.REVEAL)
	assert_eq(logic.votes.size(), 4, "ballot not wiped the moment it resolves")
	assert_eq(logic.submit(1, {"target": 3}, now).get("error"), &"not_voting")
	logic.tick(VoteRaceLogic.REVEAL_TIME + 0.01, now)
	assert_eq(logic.phase, VoteRaceLogic.RaceState.VOTING)
	assert_true(logic.votes.is_empty(), "fresh ballot for the new round")
	assert_eq(logic.round_count, 1)
	assert_true(logic.submit(1, {"target": 3}, now).get("ok", false))
	assert_false(logic.get_public_state()["last_reveal"]["votes"].is_empty(), "previous reveal stays public")


# --- Movement -----------------------------------------------------------------------------------

func test_ring_vote_nobody_moves() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	_round(logic, {1: 2, 2: 3, 3: 4, 4: 1})
	for p: int in [1, 2, 3, 4]:
		assert_eq(logic.positions[p], 0)
	assert_false(logic.is_finished())


func test_players_without_votes_advance() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	_round(logic, {1: 4, 2: 4, 3: 4, 4: 1})
	assert_eq(logic.positions[1], 0)
	assert_eq(logic.positions[2], 1)
	assert_eq(logic.positions[3], 1)
	assert_eq(logic.positions[4], 0)


func test_three_racers_ring_nobody_moves_fresh_vote() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	logic.racing.erase(4)  # 4 already at the cashier
	logic.positions[4] = VoteRaceLogic.TRACK_LENGTH
	logic.finish_groups.append([4])
	_vote(logic, {1: 2, 2: 3, 3: 1})
	for p: int in [1, 2, 3]:
		assert_eq(logic.positions[p], 0, "everyone got a vote: nobody moves")
	assert_true((logic.last_reveal["moved"] as Array).is_empty())
	logic.tick(VoteRaceLogic.REVEAL_TIME + 0.01, now)
	assert_eq(logic.phase, VoteRaceLogic.RaceState.VOTING, "fresh vote next round")
	assert_true(logic.votes.is_empty())
	assert_eq(logic.racing.size(), 3)


func test_three_racers_votes_piled_on_one_lets_the_others_move() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	logic.racing.erase(4)
	logic.finish_groups.append([4])
	logic.positions[4] = VoteRaceLogic.TRACK_LENGTH
	_round(logic, {1: 3, 2: 3})  # 3 doesn't vote in time
	assert_eq(logic.positions[1], 1)
	assert_eq(logic.positions[2], 1)
	assert_eq(logic.positions[3], 0)


func test_no_vote_in_time_counts_as_no_vote() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	logic.submit(1, {"target": 2}, now)
	logic.tick(VoteRaceLogic.VOTE_TIME - 1.0, now)
	assert_eq(logic.phase, VoteRaceLogic.RaceState.VOTING, "still waiting")
	logic.tick(1.01, now)
	assert_eq(logic.phase, VoteRaceLogic.RaceState.REVEAL)
	assert_eq(logic.positions[2], 0)
	for p: int in [1, 3, 4]:
		assert_eq(logic.positions[p], 1)


func test_nobody_votes_everyone_moves() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	_round(logic, {})
	for p: int in [1, 2, 3, 4]:
		assert_eq(logic.positions[p], 1)


# --- Validation ---------------------------------------------------------------------------------

func test_cannot_vote_for_self() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	assert_eq(logic.submit(1, {"target": 1}, now).get("error"), &"cannot_vote_self")


func test_cannot_vote_twice() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	logic.submit(1, {"target": 2}, now)
	assert_eq(logic.submit(1, {"target": 3}, now).get("error"), &"already_voted")


func test_invalid_target() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	assert_eq(logic.submit(1, {"target": 999}, now).get("error"), &"invalid_target")


func test_finished_players_cannot_vote_or_be_voted_for() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4, 5])
	for i: int in VoteRaceLogic.TRACK_LENGTH:
		_round(logic, {1: 2, 2: 3, 3: 4, 4: 5, 5: 2})  # only 1 gets no votes
	assert_eq(logic.positions[1], VoteRaceLogic.TRACK_LENGTH)
	assert_false(1 in logic.racing)
	assert_false(logic.is_finished())
	assert_eq(logic.submit(1, {"target": 2}, now).get("error"), &"not_racing")
	assert_eq(logic.submit(2, {"target": 1}, now).get("error"), &"invalid_target")
	assert_false(logic.private_state(1)["can_vote"])


# --- Finishing & ranking ------------------------------------------------------------------------

func test_game_ends_when_two_racers_left_and_ranks_by_finish_then_steps() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	for i: int in VoteRaceLogic.TRACK_LENGTH:
		_round(logic, {1: 2, 2: 3, 3: 4, 4: 2})  # only 1 moves
	assert_eq(logic.racing, [2, 3, 4] as Array[int])
	_round(logic, {2: 3, 3: 2, 4: 2})  # only 4 moves
	_round(logic, {2: 3, 3: 2, 4: 2})
	for i: int in VoteRaceLogic.TRACK_LENGTH:
		assert_false(logic.is_finished())
		_round(logic, {2: 3, 3: 4, 4: 3})  # only 2 moves
	assert_true(logic.is_finished(), "only 3 and 4 left on the track")
	var ranking: Array[Dictionary] = logic.ranking()
	assert_eq(ranking.size(), 4)
	assert_eq(int(ranking[0]["player"]), 1)
	assert_eq(int(ranking[1]["player"]), 2)
	assert_eq(int(ranking[2]["player"]), 4, "more steps ranks above")
	assert_eq(int(ranking[3]["player"]), 3)
	for i: int in 4:
		assert_eq(int(ranking[i]["rank"]), i + 1)


func test_simultaneous_finishers_share_place() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4, 5])
	for i: int in VoteRaceLogic.TRACK_LENGTH:
		_round(logic, {1: 3, 2: 3, 3: 4, 4: 5, 5: 3})  # 1 and 2 move together
	assert_eq(logic.finish_groups.size(), 1)
	assert_eq(_rank_of(logic, 1), 1)
	assert_eq(_rank_of(logic, 2), 1)
	assert_eq(_rank_of(logic, 3), 3)
	assert_false(logic.is_finished(), "3 racers still on the track")


func test_game_over_event_waits_for_final_reveal() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	for i: int in VoteRaceLogic.TRACK_LENGTH - 1:
		_round(logic, {1: 3, 2: 3, 3: 4, 4: 3})  # 1 and 2 move together
	logic.drain_events()
	_vote(logic, {1: 3, 2: 3, 3: 4, 4: 3})
	assert_false(logic.is_finished(), "final reveal shows first")
	assert_eq(_events_of(logic.drain_events(), &"vote_race_reveal").size(), 1)
	logic.tick(VoteRaceLogic.REVEAL_TIME + 0.01, now)
	assert_true(logic.is_finished())
	assert_eq(_events_of(logic.drain_events(), &"vote_race_over").size(), 1)


func test_round_cap_ends_stalled_race() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	for i: int in VoteRaceLogic.MAX_ROUNDS:
		_round(logic, {1: 2, 2: 3, 3: 4, 4: 1})
	assert_true(logic.is_finished())
	assert_eq(logic.ranking().size(), 4)


# --- Disconnects --------------------------------------------------------------------------------

func test_leaving_player_votes_and_votes_for_them_are_dropped() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4, 5])
	logic.submit(1, {"target": 5}, now)
	logic.submit(5, {"target": 2}, now)
	logic.remove_player(5)
	assert_false(logic.votes.has(1), "1's target left: 1 may vote again")
	assert_false(logic.votes.has(5))
	assert_true(logic.submit(1, {"target": 2}, now).get("ok", false))


func test_leaving_down_to_two_racers_ends_game() -> void:
	var logic: VoteRaceLogic = _vote_race([1, 2, 3, 4])
	logic.remove_player(4)
	assert_false(logic.is_finished())
	logic.remove_player(3)
	assert_true(logic.is_finished())
	assert_eq(logic.ranking().size(), 2)
