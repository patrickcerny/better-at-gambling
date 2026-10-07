extends GutTest
## Split or Steal stage: builds without a camera, follows a round (talk → pick → reveal → final)
## from events, takes button state from `can_choose`, and catches up from a late-join snapshot.

var st: ClientMatchState
var stage: SplitOrStealStage


func before_each() -> void:
	st = ClientMatchState.new()
	st.players = {1: {"id": 1, "name": "Me", "color": 0}, 2: {"id": 2, "name": "Rival", "color": 1}, 3: {"id": 3, "name": "Third", "color": 2}}
	stage = SplitOrStealStage.new()
	add_child_autofree(stage)


func _begin(snapshot: Dictionary = {}) -> void:
	stage.begin(st, 1, {"minigame": &"split_or_steal", "players": [1, 2, 3]}, snapshot)
	await wait_process_frames(1)


func _priv(round_i: int, can_choose: bool, choice: String = "") -> Dictionary:
	return {"minigame": {"round": round_i, "opponent": 2, "in_current_match": true, "can_choose": can_choose, "my_choice": choice}}


func test_builds_without_its_own_camera() -> void:
	await _begin()
	assert_null(stage.camera, "UI-only stage")
	assert_true(stage.choice_buttons[SplitOrStealLogic.SPLIT].disabled)


func test_round_flow_and_buttons() -> void:
	await _begin()
	stage.on_event({"type": &"split_or_steal_started", "players": [1, 2, 3], "total_rounds": 3, "talk_time": 8.0, "pick_time": 4.0})
	stage.on_event({"type": &"split_or_steal_round", "round": 0, "total_rounds": 3, "pairs": [[1, 2]], "bye": 3, "talk_time": 8.0})
	assert_eq(stage.opponent, 2)
	assert_eq(stage.header_label.text, "ROUND 1 / 3")
	assert_true(stage.choice_buttons[SplitOrStealLogic.STEAL].disabled, "no picking while talking")
	stage.on_private(_priv(0, false))
	assert_true(stage.choice_buttons[SplitOrStealLogic.STEAL].disabled)
	stage.on_event({"type": &"split_or_steal_pick", "round": 0, "pick_time": 4.0})
	stage.on_private(_priv(0, true))
	assert_false(stage.choice_buttons[SplitOrStealLogic.STEAL].disabled, "can_choose opens the buttons")
	# Offline the intent is refused: the buttons stay open instead of pretending we locked in.
	stage.choice_buttons[SplitOrStealLogic.STEAL].pressed.emit()
	assert_false(stage.choice_buttons[SplitOrStealLogic.STEAL].disabled)
	# The server says we picked (e.g. from another client frame): buttons close.
	stage.on_private(_priv(0, false, SplitOrStealLogic.STEAL))
	assert_true(stage.choice_buttons[SplitOrStealLogic.SPLIT].disabled)
	assert_eq(stage.my_choice, SplitOrStealLogic.STEAL)
	stage.on_event({"type": &"split_or_steal_locked", "round": 0, "player": 2})
	assert_eq(stage.opp_tag.text, "LOCKED IN")
	stage.on_event({"type": &"split_or_steal_reveal", "round": 0, "results": [
		{"player_a": 1, "player_b": 2, "choice_a": "STEAL", "choice_b": "SPLIT", "points_a": 3, "points_b": 0, "auto_a": false, "auto_b": false}],
		"points": {"1": 3, "2": 0, "3": 0}, "steals": {"1": 1}})
	assert_eq(stage.opp_tag.text, "SPLIT")
	assert_eq(stage._pts(1), 3, "string keys from the wire are normalised")
	assert_string_contains(stage.result_label.text, "You stole from Rival")
	stage.on_event({"type": &"split_or_steal_finished", "ranking": [
		{"player": 1, "points": 3, "steals": 1, "rank": 1}, {"player": 2, "points": 0, "steals": 0, "rank": 2}, {"player": 3, "points": 0, "steals": 0, "rank": 2}]})
	assert_string_contains(stage.result_label.text, "Me wins")
	await wait_process_frames(2)


func test_stale_private_state_is_ignored() -> void:
	await _begin()
	stage.on_event({"type": &"split_or_steal_round", "round": 1, "total_rounds": 3, "pairs": [[1, 2]], "bye": 3, "talk_time": 8.0})
	stage.on_event({"type": &"split_or_steal_pick", "round": 1, "pick_time": 4.0})
	stage.on_private(_priv(0, false, "SPLIT"))  # last round's private data
	assert_eq(stage.my_choice, "")


func test_sitting_out() -> void:
	await _begin()
	stage.on_event({"type": &"split_or_steal_round", "round": 0, "total_rounds": 3, "pairs": [[2, 3]], "bye": 1, "talk_time": 8.0})
	stage.on_event({"type": &"split_or_steal_pick", "round": 0, "pick_time": 4.0})
	assert_eq(stage.opponent, SplitOrStealLogic.BYE)
	assert_eq(stage.vs_label.text, "SITTING OUT")
	assert_true(stage.choice_buttons[SplitOrStealLogic.SPLIT].disabled)
	assert_eq(stage.others.get_child_count(), 1, "the other pair is listed")


func test_late_join_snapshot_initialises_buttons() -> void:
	await _begin({"minigame": &"split_or_steal", "players": [1, 2, 3], "state": SplitOrStealLogic.State.PICK, "timer": 2.0,
		"round": 1, "total_rounds": 3, "talk_time": 8.0, "pick_time": 4.0, "points": {1: 1, 2: 1}, "steals": {},
		"locked": [2], "pairs": [[1, 2]], "bye": 3})
	assert_eq(stage.round_index, 1)
	assert_false(stage.choice_buttons[SplitOrStealLogic.SPLIT].disabled, "paired, PICK and not locked in")
	assert_true(stage.locked.has(2))
	assert_almost_eq(stage.time_left, 2.0, 0.1)
