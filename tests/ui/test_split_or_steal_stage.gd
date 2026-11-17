extends GutTest
## Split or Steal stage: a 3D show set with its own camera, two podiums and an audience seat for
## every player. Everyone plays everyone, one duel at a time: the pair on stage goes up on the
## podiums (us on the left when it is ours); buttons only for the two on stage and only while
## deciding; the audience gets "Waiting for X vs Y"; lock-ins show without the choice; the reveal
## flips both cards; THE DUELS lists results, the duel on stage and when we're up; a stage built
## after the first events (the first-round bug) catches up from the private state; a late joiner
## draws everything from the snapshot.

const S: String = SplitOrStealLogic.SPLIT
const T: String = SplitOrStealLogic.STEAL

var st: ClientMatchState
var stage: SplitOrStealStage


func before_each() -> void:
	st = ClientMatchState.new()
	st.players = {1: {"id": 1, "name": "Me", "color": 0}, 2: {"id": 2, "name": "Rival", "color": 1}, 3: {"id": 3, "name": "Third", "color": 2}}
	stage = SplitOrStealStage.new()
	add_child_autofree(stage)


func _begin(snapshot: Dictionary = {}, me: int = 1) -> void:
	stage.begin(st, me, {"minigame": &"split_or_steal", "players": [1, 2, 3]}, snapshot)
	await wait_process_frames(1)


## Duel 0: 2 vs 1, duel 1: 2 vs 3, duel 2: 3 vs 1.
func _rounds() -> Array:
	var out: Array = []
	for p: Array in [[2, 1], [2, 3], [3, 1]]:
		out.append({"duels": [{"a": p[0], "b": p[1], "result": {}}], "bye": []})
	return out


func _start() -> void:
	stage.on_event({"type": &"split_or_steal_started", "players": [1, 2, 3], "rounds": _rounds(), "duels_each": 2, "round_time": 2.0, "decide_time": 12.0})


func _duel(i: int) -> void:
	var r: Dictionary = _rounds()[i]
	stage.on_event({"type": &"split_or_steal_round", "index": i, "total": 3, "duels": r["duels"], "bye": [], "round_time": 2.0, "decide_time": 12.0})


func _decide(i: int) -> void:
	stage.on_event({"type": &"split_or_steal_decide", "index": i, "decide_time": 12.0})


func _priv(i: int, s: SplitOrStealLogic.State, opp: int, can_choose: bool, choice: String = "") -> Dictionary:
	var r: Dictionary = _rounds()[i]
	return {"minigame": {"index": i, "state": s, "timer": 10.0, "duels": r["duels"], "bye": [], "opponent": opp, "can_choose": can_choose, "my_choice": choice}}


func _card(side: int) -> String:
	return (stage.podiums[side]["card_label"] as Label3D).text


func test_builds_a_3d_set_with_camera_podiums_and_audience() -> void:
	await _begin()
	assert_not_null(stage.camera, "its own show camera")
	assert_eq(stage.podiums.size(), 2)
	assert_eq(stage.beans.size(), 3, "a bean per player")
	assert_not_null(stage.host)
	assert_not_null(stage.you_marker, "our seat is marked")
	assert_false(stage.button_row.visible, "nobody on stage yet")


func test_our_duel_goes_up_with_us_on_the_left() -> void:
	await _begin()
	_start()
	assert_eq(stage.total, 3)
	_duel(0)
	assert_eq(stage.pair, [1, 2] as Array[int], "us first even when we are side b")
	assert_eq(stage.header_label.text, "DUEL 1 / 3")
	assert_eq((stage.podiums[0]["name"] as Label3D).text, "Me")
	assert_eq((stage.podiums[1]["name"] as Label3D).text, "Rival")
	assert_eq((stage.beans[1]["bean"] as Node).get_parent(), stage.podiums[0]["root"], "our bean went up")
	assert_eq((stage.beans[3]["bean"] as Node).get_parent(), stage.beans[3]["seat"], "the third watches")
	assert_false(stage.you_marker.visible, "our seat is empty while we are on stage")


func test_buttons_only_for_the_pair_while_deciding() -> void:
	await _begin()
	_start()
	_duel(0)
	assert_true(stage.button_row.visible, "we are on stage")
	assert_true(stage.choice_buttons[S].disabled, "not while walking up")
	_decide(0)
	assert_false(stage.choice_buttons[T].disabled)
	assert_eq(_card(0), "?")
	# Offline the intent is refused: the buttons stay open instead of pretending we locked in.
	stage.choice_buttons[T].pressed.emit()
	assert_false(stage.choice_buttons[T].disabled)
	stage.on_private(_priv(0, SplitOrStealLogic.State.DECIDE, 2, false, T))
	assert_true(stage.choice_buttons[S].disabled)
	assert_eq(stage.my_choice, T)
	assert_eq(_card(0), "LOCKED IN")
	stage.on_event({"type": &"split_or_steal_locked", "index": 0, "player": 2})
	assert_eq(_card(1), "LOCKED IN")


func test_watcher_sees_waiting_no_buttons_and_when_they_are_up() -> void:
	await _begin()
	_start()
	_duel(1)
	_decide(1)
	assert_eq(stage.pair, [2, 3] as Array[int])
	assert_false(stage.button_row.visible, "the audience has no buttons")
	assert_false(stage.can_choose)
	assert_string_contains(stage.status_label.text, "Waiting for Rival vs Third")
	assert_true(stage.you_marker.visible, "our seat is marked")
	stage.on_event({"type": &"split_or_steal_locked", "index": 1, "player": 3})
	assert_string_contains(stage.status_label.text, "1 / 2 decided")
	var texts: Array[String] = []
	for c: Node in stage.round_box.get_children():
		if c is Label:
			texts.append((c as Label).text)
	assert_has(texts, "You're up next: vs Third")
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	stage._unhandled_input(key)
	assert_eq(stage.my_choice, "")


func test_reveal_flips_both_cards_and_scores() -> void:
	await _begin()
	_start()
	_duel(0)
	_decide(0)
	stage.on_event({"type": &"split_or_steal_reveal", "index": 0, "results": [
		{"a": 2, "b": 1, "choice_a": S, "choice_b": T, "points_a": 0, "points_b": 3, "auto_a": true, "auto_b": false}],
		"points": {"1": 3, "2": 0, "3": 0}, "steals": {"1": 1}})
	assert_eq(stage.phase, SplitOrStealStage.Step.REVEAL)
	assert_eq(_card(0), T, "our card, though we were side b")
	assert_eq(_card(1), S + "*", "a timed-out pick is marked")
	assert_eq((stage.podiums[0]["gain"] as Label3D).text, "+3")
	assert_eq(stage._pts(1), 3, "string keys from the wire are normalised")
	assert_string_contains(stage.result_label.text, "YOU STEAL FROM RIVAL")
	assert_false(stage.button_row.visible)
	assert_eq((stage.rounds[0]["duels"][0]["result"] as Dictionary)["choice_b"], T, "the list shows the result")
	stage.on_event({"type": &"split_or_steal_finished", "ranking": [
		{"player": 1, "points": 3, "steals": 1, "rank": 1}, {"player": 2, "points": 0, "steals": 0, "rank": 2}, {"player": 3, "points": 0, "steals": 0, "rank": 2}]})
	assert_string_contains(stage.result_label.text, "ME WINS")
	assert_eq((stage.beans[1]["bean"] as Node).get_parent(), stage.podiums[0]["root"], "the winner takes the podium")
	await wait_process_frames(2)


func test_watchers_see_who_stole() -> void:
	await _begin()
	_start()
	_duel(1)
	_decide(1)
	stage.on_event({"type": &"split_or_steal_reveal", "index": 1, "results": [
		{"a": 2, "b": 3, "choice_a": T, "choice_b": S, "points_a": 3, "points_b": 0}], "points": {"2": 3}, "steals": {"2": 1}})
	assert_string_contains(stage.result_label.text, "RIVAL STEALS FROM THIRD")


func test_stage_built_after_the_first_events_catches_up() -> void:
	await _begin()
	assert_eq(stage.pair, [] as Array[int])
	stage.on_private(_priv(0, SplitOrStealLogic.State.DECIDE, 2, true))
	assert_eq(stage.pair, [1, 2] as Array[int], "not 'nobody'")
	assert_eq(stage.phase, SplitOrStealStage.Step.DECIDE)
	assert_false(stage.choice_buttons[S].disabled, "we can choose in the first duel")
	assert_eq((stage.podiums[1]["name"] as Label3D).text, "Rival")


func test_stale_private_state_is_ignored() -> void:
	await _begin()
	_start()
	_duel(1)
	stage.on_private(_priv(0, SplitOrStealLogic.State.DECIDE, 2, true))  # last duel's data
	assert_eq(stage.pair, [2, 3] as Array[int])
	assert_false(stage.can_choose)


func test_late_join_snapshot() -> void:
	var rounds: Array = _rounds()
	rounds[0]["duels"][0]["result"] = {"a": 2, "b": 1, "choice_a": S, "choice_b": S, "points_a": 1, "points_b": 1, "auto_a": false, "auto_b": false}
	await _begin({"minigame": &"split_or_steal", "players": [1, 2, 3], "state": SplitOrStealLogic.State.DECIDE, "timer": 6.0,
		"index": 1, "total": 3, "rounds": rounds, "decide_time": 12.0, "points": {1: 1, 2: 1}, "steals": {}, "locked": [3]}, 2)
	assert_eq(stage.round_index, 1)
	assert_eq(stage.pair, [2, 3] as Array[int])
	assert_false(stage.choice_buttons[S].disabled, "on stage, deciding and not locked in")
	assert_eq(_card(1), "LOCKED IN")
	assert_between(stage.time_left, 5.0, 6.0, "counts down from the snapshot timer (one frame may pass under load)")
	assert_eq(stage._pts(1), 1)
	assert_eq(stage.round_box.get_child_count(), 3, "the three duels")
