extends GutTest
## Split or Steal stage: a 3D show set with its own camera, two podiums and an audience seat for
## every player. Opens the announced pair on the podiums; buttons only for the two on stage and
## only while deciding; watchers get "Waiting for X vs Y"; lock-ins show without the choice; the
## reveal flips both cards; a stage built after the first events (the first-round bug) catches up
## from the private state; a late joiner draws everything from the snapshot.

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


func _schedule() -> Array:
	return [{"a": 1, "b": 2, "house": -1, "result": {}}, {"a": 2, "b": 3, "house": -1, "result": {}}, {"a": 3, "b": 1, "house": -1, "result": {}}]


func _start() -> void:
	stage.on_event({"type": &"split_or_steal_started", "players": [1, 2, 3], "schedule": _schedule(), "matches_each": 2, "announce_time": 2.5, "decide_time": 15.0})


func _pair(i: int, a: int, b: int, house: int = -1) -> void:
	stage.on_event({"type": &"split_or_steal_pair", "index": i, "total": 3, "a": a, "b": b, "house": house, "announce_time": 2.5, "decide_time": 15.0})


func _priv(i: int, s: SplitOrStealLogic.State, pair: Array, can_choose: bool, choice: String = "") -> Dictionary:
	return {"minigame": {"index": i, "state": s, "timer": 10.0, "pair": pair, "house": -1, "in_pair": 1 in pair, "can_choose": can_choose, "my_choice": choice}}


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


func test_opens_with_the_announced_pair_on_the_podiums() -> void:
	await _begin()
	_start()
	assert_eq(stage.total, 3)
	_pair(0, 1, 2)
	assert_eq(stage.pair, [1, 2] as Array[int])
	assert_eq(stage.header_label.text, "MATCH 1 / 3")
	assert_eq((stage.podiums[0]["name"] as Label3D).text, "Me")
	assert_eq((stage.podiums[1]["name"] as Label3D).text, "Rival")
	assert_eq((stage.beans[1]["bean"] as Node).get_parent(), stage.podiums[0]["root"], "our bean went up")
	assert_eq((stage.beans[3]["bean"] as Node).get_parent(), stage.beans[3]["seat"], "the third watches")
	assert_gt((stage.podiums[0]["light"] as SpotLight3D).light_energy, 0.0, "spotlight on")
	assert_false(stage.you_marker.visible, "our seat is empty while we are on stage")


func test_buttons_only_for_the_pair_while_deciding() -> void:
	await _begin()
	_start()
	_pair(0, 1, 2)
	assert_true(stage.button_row.visible, "we are on stage")
	assert_true(stage.choice_buttons[S].disabled, "not while walking up")
	stage.on_event({"type": &"split_or_steal_decide", "index": 0, "decide_time": 15.0})
	assert_false(stage.choice_buttons[T].disabled)
	assert_eq(_card(0), "?")
	# Offline the intent is refused: the buttons stay open instead of pretending we locked in.
	stage.choice_buttons[T].pressed.emit()
	assert_false(stage.choice_buttons[T].disabled)
	# The server says we picked: buttons close, our card shows LOCKED IN (never the choice).
	stage.on_private(_priv(0, SplitOrStealLogic.State.DECIDE, [1, 2], false, T))
	assert_true(stage.choice_buttons[S].disabled)
	assert_eq(stage.my_choice, T)
	assert_eq(_card(0), "LOCKED IN")
	stage.on_event({"type": &"split_or_steal_locked", "index": 0, "player": 2})
	assert_eq(_card(1), "LOCKED IN")


func test_watcher_sees_waiting_and_no_buttons() -> void:
	await _begin()
	_start()
	_pair(1, 2, 3)
	stage.on_event({"type": &"split_or_steal_decide", "index": 1, "decide_time": 15.0})
	assert_false(stage.button_row.visible, "the audience has no buttons")
	assert_false(stage.can_choose)
	assert_true(stage.status_panel.visible)
	assert_string_contains(stage.status_label.text, "Waiting for Rival vs Third")
	assert_true(stage.you_marker.visible, "our seat is marked")
	stage.on_event({"type": &"split_or_steal_locked", "index": 1, "player": 3})
	assert_string_contains(stage.status_label.text, "1 / 2 decided")
	# Keys do nothing for a watcher.
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	stage._unhandled_input(key)
	assert_eq(stage.my_choice, "")


func test_reveal_flips_both_cards_and_scores() -> void:
	await _begin()
	_start()
	_pair(0, 1, 2)
	stage.on_event({"type": &"split_or_steal_decide", "index": 0, "decide_time": 15.0})
	stage.on_event({"type": &"split_or_steal_reveal", "index": 0, "a": 1, "b": 2, "house": -1, "choice_a": T, "choice_b": S,
		"points_a": 3, "points_b": 0, "auto_a": false, "auto_b": true, "points": {"1": 3, "2": 0, "3": 0}, "steals": {"1": 1}})
	assert_eq(stage.phase, SplitOrStealStage.Step.REVEAL)
	assert_eq(_card(0), T)
	assert_eq(_card(1), S + "*", "a timed-out pick is marked")
	assert_eq((stage.podiums[0]["gain"] as Label3D).text, "+3")
	assert_eq(stage._pts(1), 3, "string keys from the wire are normalised")
	assert_string_contains(stage.result_label.text, "ME STEALS FROM RIVAL")
	assert_false(stage.button_row.visible)
	assert_eq((stage.schedule[0]["result"] as Dictionary)["choice_a"], T, "the schedule shows the result")
	stage.on_event({"type": &"split_or_steal_finished", "ranking": [
		{"player": 1, "points": 3, "steals": 1, "rank": 1}, {"player": 2, "points": 0, "steals": 0, "rank": 2}, {"player": 3, "points": 0, "steals": 0, "rank": 2}]})
	assert_string_contains(stage.result_label.text, "ME WINS")
	assert_eq((stage.beans[1]["bean"] as Node).get_parent(), stage.podiums[0]["root"], "the winner takes the podium")
	await wait_process_frames(2)


func test_house_match_is_shown() -> void:
	await _begin()
	_start()
	_pair(2, 3, 1, 3)
	assert_eq((stage.podiums[0]["score"] as Label3D).text, "FOR THE HOUSE")
	stage.on_event({"type": &"split_or_steal_decide", "index": 2, "decide_time": 15.0})
	assert_false(stage.choice_buttons[S].disabled, "we score, we choose")


func test_stage_built_after_the_first_events_catches_up() -> void:
	# The first-round bug: the stage is built behind the curtain after `minigame_started`, so
	# the show's first events can be gone. Our private state names the pair on stage.
	await _begin()
	assert_eq(stage.pair, [] as Array[int])
	stage.on_private(_priv(0, SplitOrStealLogic.State.DECIDE, [1, 2], true))
	assert_eq(stage.pair, [1, 2] as Array[int], "not 'nobody'")
	assert_eq(stage.phase, SplitOrStealStage.Step.DECIDE)
	assert_false(stage.choice_buttons[S].disabled, "we can choose in the first round")
	assert_eq((stage.podiums[1]["name"] as Label3D).text, "Rival")


func test_stale_private_state_is_ignored() -> void:
	await _begin()
	_start()
	_pair(1, 2, 3)
	stage.on_private(_priv(0, SplitOrStealLogic.State.DECIDE, [1, 2], true))  # last match's data
	assert_eq(stage.pair, [2, 3] as Array[int])
	assert_false(stage.can_choose)


func test_late_join_snapshot() -> void:
	var sched: Array = _schedule()
	sched[0]["result"] = {"a": 1, "b": 2, "house": -1, "choice_a": S, "choice_b": S, "points_a": 1, "points_b": 1, "auto_a": false, "auto_b": false}
	await _begin({"minigame": &"split_or_steal", "players": [1, 2, 3], "state": SplitOrStealLogic.State.DECIDE, "timer": 6.0,
		"index": 1, "total": 3, "schedule": sched, "decide_time": 15.0, "points": {1: 1, 2: 1}, "steals": {}, "locked": [3]}, 2)
	assert_eq(stage.pair_index, 1)
	assert_eq(stage.pair, [2, 3] as Array[int])
	assert_false(stage.choice_buttons[S].disabled, "on stage, deciding and not locked in")
	assert_eq(_card(1), "LOCKED IN")
	assert_between(stage.time_left, 5.0, 6.0, "counts down from the snapshot timer (one frame may pass under load)")
	assert_eq(stage._pts(1), 1)
	assert_eq(stage.schedule_box.get_child_count(), 3)
