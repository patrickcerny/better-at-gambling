extends GutTest
## Split or Steal stage: a 3D show set with its own camera, two podiums and an audience seat for
## every player. Every round all duels run at once: our duel goes up on the podiums (us on the
## left), THIS ROUND lists every duel; buttons for whoever has a duel and only while deciding;
## whoever sits out gets "You sit this round out"; lock-ins show without the choice; the reveal
## flips our cards and fills in every duel; a stage built after the first events (the first-round
## bug) catches up from the private state; a late joiner draws everything from the snapshot.

const S: String = SplitOrStealLogic.SPLIT
const T: String = SplitOrStealLogic.STEAL

var st: ClientMatchState
var stage: SplitOrStealStage


func before_each() -> void:
	st = ClientMatchState.new()
	st.players = {}
	for i: int in 5:
		st.players[i + 1] = {"id": i + 1, "name": ["Me", "Rival", "Third", "Fourth", "Fifth"][i], "color": i}
	stage = SplitOrStealStage.new()
	add_child_autofree(stage)


func _begin(snapshot: Dictionary = {}, me: int = 1) -> void:
	stage.begin(st, me, {"minigame": &"split_or_steal", "players": [1, 2, 3, 4, 5]}, snapshot)
	await wait_process_frames(1)


func _duels(pairs: Array) -> Array:
	var out: Array = []
	for p: Array in pairs:
		out.append({"a": p[0], "b": p[1], "result": {}})
	return out


## Round 0: 2 vs 1 and 3 vs 4, 5 sits out. Round 1: 1 vs 5 and 2 vs 3, 4 sits out. Round 2:
## 3 vs 5 and 4 vs 2, 1 sits out.
func _rounds() -> Array:
	return [
		{"duels": _duels([[2, 1], [3, 4]]), "bye": [5]},
		{"duels": _duels([[1, 5], [2, 3]]), "bye": [4]},
		{"duels": _duels([[3, 5], [4, 2]]), "bye": [1]},
	]


func _start() -> void:
	stage.on_event({"type": &"split_or_steal_started", "players": [1, 2, 3, 4, 5], "rounds": _rounds(), "duels_each": 4, "round_time": 2.0, "decide_time": 12.0})


func _round(i: int) -> void:
	var r: Dictionary = _rounds()[i]
	stage.on_event({"type": &"split_or_steal_round", "index": i, "total": 3, "duels": r["duels"], "bye": r["bye"], "round_time": 2.0, "decide_time": 12.0})


func _decide(i: int) -> void:
	stage.on_event({"type": &"split_or_steal_decide", "index": i, "decide_time": 12.0})


func _priv(i: int, s: SplitOrStealLogic.State, opp: int, can_choose: bool, choice: String = "") -> Dictionary:
	var r: Dictionary = _rounds()[i]
	return {"minigame": {"index": i, "state": s, "timer": 10.0, "duels": r["duels"], "bye": r["bye"], "opponent": opp, "can_choose": can_choose, "my_choice": choice}}


func _card(side: int) -> String:
	return (stage.podiums[side]["card_label"] as Label3D).text


func test_builds_a_3d_set_with_camera_podiums_and_audience() -> void:
	await _begin()
	assert_not_null(stage.camera, "its own show camera")
	assert_eq(stage.podiums.size(), 2)
	assert_eq(stage.beans.size(), 5, "a bean per player")
	assert_not_null(stage.host)
	assert_not_null(stage.you_marker, "our seat is marked")
	assert_false(stage.button_row.visible, "no duel yet")


func test_our_duel_goes_up_on_the_podiums_with_us_on_the_left() -> void:
	await _begin()
	_start()
	assert_eq(stage.total, 3)
	_round(0)
	assert_eq(stage.opponent(), 2)
	assert_eq(stage.pair, [1, 2] as Array[int], "us first even when we are side b")
	assert_eq(stage.header_label.text, "ROUND 1 / 3")
	assert_eq((stage.podiums[0]["name"] as Label3D).text, "Me")
	assert_eq((stage.podiums[1]["name"] as Label3D).text, "Rival")
	assert_eq((stage.beans[1]["bean"] as Node).get_parent(), stage.podiums[0]["root"], "our bean went up")
	assert_eq((stage.beans[3]["bean"] as Node).get_parent(), stage.beans[3]["seat"], "the other duel plays from the seats")
	assert_eq(stage.round_box.get_child_count(), 3, "two duels and who sits out")
	assert_false(stage.you_marker.visible, "our seat is empty while we are up")


func test_buttons_for_everyone_with_a_duel_while_deciding() -> void:
	await _begin()
	_start()
	_round(0)
	assert_true(stage.button_row.visible, "we have a duel")
	assert_true(stage.choice_buttons[S].disabled, "not while walking up")
	_decide(0)
	assert_false(stage.choice_buttons[T].disabled)
	assert_eq(_card(0), "?")
	# Offline the intent is refused: the buttons stay open instead of pretending we locked in.
	stage.choice_buttons[T].pressed.emit()
	assert_false(stage.choice_buttons[T].disabled)
	# The server says we picked: buttons close, our card shows LOCKED IN (never the choice).
	stage.on_private(_priv(0, SplitOrStealLogic.State.DECIDE, 2, false, T))
	assert_true(stage.choice_buttons[S].disabled)
	assert_eq(stage.my_choice, T)
	assert_eq(_card(0), "LOCKED IN")
	stage.on_event({"type": &"split_or_steal_locked", "index": 0, "player": 2})
	assert_eq(_card(1), "LOCKED IN")


func test_sitting_out_sees_the_round_and_no_buttons() -> void:
	await _begin()
	_start()
	_round(2)
	_decide(2)
	assert_eq(stage.pair, [3, 5] as Array[int], "the round's first duel is on show")
	assert_false(stage.button_row.visible, "no buttons while sitting out")
	assert_false(stage.can_choose)
	assert_true(stage.status_panel.visible)
	assert_string_contains(stage.status_label.text, "You sit this round out")
	assert_true(stage.you_marker.visible, "our seat is marked")
	stage.on_event({"type": &"split_or_steal_locked", "index": 2, "player": 4})
	assert_string_contains(stage.status_label.text, "1 / 4 decided")
	# Keys do nothing while sitting out.
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	stage._unhandled_input(key)
	assert_eq(stage.my_choice, "")


func test_reveal_flips_our_cards_and_fills_in_every_duel() -> void:
	await _begin()
	_start()
	_round(0)
	_decide(0)
	stage.on_event({"type": &"split_or_steal_reveal", "index": 0, "results": [
		{"a": 2, "b": 1, "choice_a": S, "choice_b": T, "points_a": 0, "points_b": 3, "auto_a": true, "auto_b": false},
		{"a": 3, "b": 4, "choice_a": S, "choice_b": S, "points_a": 1, "points_b": 1, "auto_a": false, "auto_b": false}],
		"points": {"1": 3, "2": 0, "3": 1, "4": 1}, "steals": {"1": 1}})
	assert_eq(stage.phase, SplitOrStealStage.Step.REVEAL)
	assert_eq(_card(0), T, "our card, though we were side b")
	assert_eq(_card(1), S + "*", "a timed-out pick is marked")
	assert_eq((stage.podiums[0]["gain"] as Label3D).text, "+3")
	assert_eq(stage._pts(1), 3, "string keys from the wire are normalised")
	assert_string_contains(stage.result_label.text, "YOU STEAL FROM RIVAL")
	assert_false(stage.button_row.visible)
	assert_eq((stage.rounds[0]["duels"][1]["result"] as Dictionary)["choice_a"], S, "the other duel is filled in too")
	stage.on_event({"type": &"split_or_steal_finished", "ranking": [
		{"player": 1, "points": 3, "steals": 1, "rank": 1}, {"player": 3, "points": 1, "steals": 0, "rank": 2},
		{"player": 4, "points": 1, "steals": 0, "rank": 2}, {"player": 2, "points": 0, "steals": 0, "rank": 4}, {"player": 5, "points": 0, "steals": 0, "rank": 4}]})
	assert_string_contains(stage.result_label.text, "ME WINS")
	assert_eq((stage.beans[1]["bean"] as Node).get_parent(), stage.podiums[0]["root"], "the winner takes the podium")
	await wait_process_frames(2)


func test_next_round_brings_a_new_opponent() -> void:
	await _begin()
	_start()
	_round(0)
	_round(1)
	assert_eq(stage.pair, [1, 5] as Array[int])
	assert_eq((stage.beans[2]["bean"] as Node).get_parent(), stage.beans[2]["seat"], "the last opponent sits down")
	assert_eq((stage.podiums[1]["name"] as Label3D).text, "Fifth")


func test_stage_built_after_the_first_events_catches_up() -> void:
	# The first-round bug: the stage is built behind the curtain after `minigame_started`, so
	# the show's first events can be gone. Our private state carries the round being played.
	await _begin()
	assert_eq(stage.pair, [] as Array[int])
	stage.on_private(_priv(0, SplitOrStealLogic.State.DECIDE, 2, true))
	assert_eq(stage.pair, [1, 2] as Array[int], "not 'nobody'")
	assert_eq(stage.phase, SplitOrStealStage.Step.DECIDE)
	assert_false(stage.choice_buttons[S].disabled, "we can choose in the first round")
	assert_eq((stage.podiums[1]["name"] as Label3D).text, "Rival")


func test_stale_private_state_is_ignored() -> void:
	await _begin()
	_start()
	_round(1)
	stage.on_private(_priv(0, SplitOrStealLogic.State.DECIDE, 2, true))  # last round's data
	assert_eq(stage.pair, [1, 5] as Array[int])
	assert_false(stage.can_choose)


func test_late_join_snapshot() -> void:
	var rounds: Array = _rounds()
	rounds[0]["duels"][0]["result"] = {"a": 2, "b": 1, "choice_a": S, "choice_b": S, "points_a": 1, "points_b": 1, "auto_a": false, "auto_b": false}
	rounds[0]["duels"][1]["result"] = {"a": 3, "b": 4, "choice_a": T, "choice_b": S, "points_a": 3, "points_b": 0, "auto_a": false, "auto_b": false}
	await _begin({"minigame": &"split_or_steal", "players": [1, 2, 3, 4, 5], "state": SplitOrStealLogic.State.DECIDE, "timer": 6.0,
		"index": 1, "total": 3, "rounds": rounds, "decide_time": 12.0, "points": {1: 1, 2: 1, 3: 3}, "steals": {3: 1}, "locked": [3]}, 2)
	assert_eq(stage.round_index, 1)
	assert_eq(stage.pair, [2, 3] as Array[int])
	assert_false(stage.choice_buttons[S].disabled, "in a duel, deciding and not locked in")
	assert_eq(_card(1), "LOCKED IN")
	assert_between(stage.time_left, 5.0, 6.0, "counts down from the snapshot timer (one frame may pass under load)")
	assert_eq(stage._pts(3), 3)
	assert_eq(stage.round_box.get_child_count(), 3)
