extends GutTest
## Lonely Number stage: snapshots (apply_state) and server events (on_event) drive the number grid,
## the reveal panel and the scoreboard.

var stage: LonelyNumberStage


func before_each() -> void:
	var st := ClientMatchState.new()
	st.players = {1: {"id": 1, "name": "Me", "color": 0}, 2: {"id": 2, "name": "Other", "color": 1}}
	stage = LonelyNumberStage.new()
	add_child_autofree(stage)
	stage.begin(st, 1, {"minigame": &"lonely_number", "players": [1, 2]}, {})
	stage.on_event({"type": &"lonely_number_round_started", "round": 0, "rounds": 5, "seconds": 15.0})


func _enabled_buttons() -> int:
	return stage.buttons.filter(func(b: Button) -> bool: return not b.disabled).size()


func test_builds_twenty_buttons_enabled() -> void:
	assert_eq(stage.buttons.size(), 20)
	assert_eq(_enabled_buttons(), 20)
	assert_eq(stage.round_label.text, "Round 1 / 5")


func test_pick_locks_grid() -> void:
	stage._on_pick(7)
	assert_eq(stage.my_pick, 7)
	assert_eq(_enabled_buttons(), 0, "one pick per round")
	assert_string_contains(stage.status_label.text, "You picked 7")


func test_keyboard_pick() -> void:
	await wait_process_frames(1)
	for k: Key in [KEY_1, KEY_2, KEY_ENTER]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.pressed = true
		get_tree().root.push_input(ev)
	assert_eq(stage.my_pick, 12)


func test_round_end_then_next_round_reenables_grid() -> void:
	stage._on_pick(7)
	stage.on_event({"type": &"lonely_number_picked", "player": 2, "round": 0})
	stage.on_event({"type": &"lonely_number_round_end", "round": 0, "picks": {1: 7, 2: 7},
		"lonely_number": -1, "winner": -1, "wins": {1: 0, 2: 0}, "totals": {1: 0, 2: 0}})
	assert_false(stage.picking)
	assert_eq(_enabled_buttons(), 0, "no picking during the reveal")
	assert_true(stage.reveal_box.visible)
	assert_string_contains(stage.reveal_title.text, "nobody wins")
	stage.on_event({"type": &"lonely_number_round_started", "round": 1, "rounds": 5, "seconds": 15.0})
	assert_eq(stage.my_pick, -1)
	assert_eq(_enabled_buttons(), 20, "grid opens again for round 2")
	assert_eq(stage.round_label.text, "Round 2 / 5")


func test_round_end_shows_winner_and_score() -> void:
	stage.on_event({"type": &"lonely_number_round_end", "round": 0, "picks": {1: 15, 2: 20},
		"lonely_number": 20, "winner": 2, "wins": {1: 0, 2: 1}, "totals": {1: 0, 2: 20}})
	assert_string_contains(stage.reveal_title.text, "Other wins with 20")
	assert_eq(int(stage.wins[2]), 1)
	assert_eq(int(stage.totals[2]), 20)


func test_apply_state_catches_up_mid_game() -> void:
	stage.apply_state({"round": 2, "rounds": 5, "state": LonelyNumberLogic.State.PICKING, "timer": 9.0,
		"picked": [2], "wins": {1: 1, 2: 1}, "totals": {1: 14, 2: 9},
		"history": [{"round": 1, "picks": {1: 3, 2: 9}, "lonely_number": 9, "winner": 2}]})
	assert_eq(stage.round, 2)
	assert_eq(stage.round_label.text, "Round 3 / 5")
	assert_eq(stage.picked, [2] as Array[int])
	assert_eq(_enabled_buttons(), 20)
	assert_true(stage.reveal_box.visible, "last revealed round is shown")
	assert_string_contains(stage.reveal_title.text, "Round 2")


func test_apply_state_during_reveal_disables_grid() -> void:
	stage.apply_state({"round": 1, "state": LonelyNumberLogic.State.REVEAL, "timer": 2.0, "picked": [],
		"wins": {1: 1, 2: 0}, "totals": {1: 5, 2: 0}, "history": []})
	assert_eq(_enabled_buttons(), 0)


func test_private_snapshot_restores_own_pick() -> void:
	stage.on_private({"minigame": {"round": 0, "can_pick": false, "my_pick": 4}})
	assert_eq(stage.my_pick, 4)
	assert_eq(_enabled_buttons(), 0)


func test_finished_shows_ranking() -> void:
	stage.on_event({"type": &"lonely_number_finished", "ranking": [
		{"player": 2, "points": 3, "total": 40, "rank": 1}, {"player": 1, "points": 2, "total": 30, "rank": 2}]})
	assert_eq(stage.round_label.text, "Final results")
	assert_eq(stage.status_label.text, "You placed #2")
	assert_eq(_enabled_buttons(), 0)


func test_spectator_cannot_pick() -> void:
	var st := ClientMatchState.new()
	var s := LonelyNumberStage.new()
	add_child_autofree(s)
	s.begin(st, 9, {"minigame": &"lonely_number", "players": [1, 2]}, {})
	s._on_pick(5)
	assert_eq(s.my_pick, -1)
	assert_eq(s.status_label.text, "Spectating")
