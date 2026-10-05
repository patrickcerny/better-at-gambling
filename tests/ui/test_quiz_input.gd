extends GutTest
## Casino Quiz answers with keyboard, gamepad and mouse (M4 acceptance: "quiz playable with
## keyboard/mouse/gamepad"). Events are pushed through the viewport like real input.

var stage: QuizStage


func before_each() -> void:
	var st := ClientMatchState.new()
	st.players = {1: {"id": 1, "name": "Me", "color": 0}, 2: {"id": 2, "name": "Other", "color": 1}}
	stage = QuizStage.new()
	add_child_autofree(stage)
	stage.begin(st, 1, {"minigame": &"quiz", "players": [1, 2]}, {})
	stage.on_event({"type": &"quiz_started", "players": [1, 2], "questions": 3, "answer_time": 12.0})
	stage.on_event({"type": &"quiz_get_ready", "index": 0, "seconds": 2.0})
	stage.on_event({"type": &"quiz_question", "index": 0, "count": 3, "question": "Pick one", "answers": ["A", "B", "C", "D"], "category": "silly", "dynamic": false, "seconds": 12.0})
	await wait_process_frames(2)


func _push(ev: InputEvent) -> void:
	get_tree().root.push_input(ev)


func test_number_key_answers() -> void:
	var k := InputEventKey.new()
	k.keycode = KEY_2
	k.pressed = true
	_push(k)
	assert_eq(stage.my_answer, 1)
	assert_true(stage.answer_buttons[0].disabled, "locked in after one answer")
	var k2 := InputEventKey.new()
	k2.keycode = KEY_4
	k2.pressed = true
	_push(k2)
	assert_eq(stage.my_answer, 1, "no second answer")


func test_gamepad_face_buttons_answer() -> void:
	var b := InputEventJoypadButton.new()
	b.button_index = QuizStage.PAD_BUTTONS[2]
	b.pressed = true
	_push(b)
	assert_eq(stage.my_answer, 2)


func test_mouse_click_on_answer_button() -> void:
	stage.answer_buttons[3].pressed.emit()
	assert_eq(stage.my_answer, 3)


func test_reveal_marks_the_correct_answer() -> void:
	stage.answer_buttons[0].pressed.emit()
	stage.on_event({"type": &"quiz_reveal", "index": 0, "correct_index": 0, "answers": {1: 0, 2: 3}, "points": {1: 900}, "totals": {1: 900, 2: 0}, "explanation": "Because."})
	assert_eq(stage._total(1), 900)
	assert_false(stage.answering)


func test_reveal_waits_for_the_drum_roll_then_shows() -> void:
	stage.answer_buttons[2].pressed.emit()
	stage.on_event({"type": &"quiz_reveal", "index": 0, "correct_index": 2, "answers": {1: 2}, "points": {1: 800}, "totals": {1: 800, 2: 0}, "explanation": ""})
	assert_false(stage.pending_reveal.is_empty(), "drum roll first")
	assert_eq(stage.revealed_index, -1)
	assert_eq(stage.host.pose, QuizHost.Pose.DRUMROLL)
	await wait_seconds(QuizStage.DRUMROLL_TIME + 0.2)
	assert_true(stage.pending_reveal.is_empty())
	assert_eq(stage.revealed_index, 0)
	assert_eq(stage.status_label.text, "CORRECT!  +800")
	assert_eq(stage.host.pose, QuizHost.Pose.SURPRISED, "one of two right: Lucky is surprised")
	assert_eq((stage.podiums[1]["puppet"] as BeanPuppet).mood, BeanPuppet.Mood.CHEER)
	assert_eq((stage.podiums[2]["puppet"] as BeanPuppet).mood, BeanPuppet.Mood.SAD)


func test_next_event_flushes_a_pending_reveal() -> void:
	stage.on_event({"type": &"quiz_reveal", "index": 0, "correct_index": 1, "answers": {}, "points": {}, "totals": {}, "explanation": ""})
	stage.on_event({"type": &"quiz_get_ready", "index": 1, "seconds": 2.0})
	assert_true(stage.pending_reveal.is_empty())
	assert_eq(stage.revealed_index, 0)
	assert_eq(stage.index, 1)


func test_question_text_is_shown_once_and_host_reacts_to_a_flop() -> void:
	assert_eq(stage.question_label.text, "Pick one")
	assert_ne(stage.screen_label.text, "Pick one", "the big screen shows the countdown, not the question again")
	assert_ne(stage.bubble_label.text, "Pick one")
	stage.on_event({"type": &"quiz_reveal", "index": 0, "correct_index": 1, "answers": {1: 0, 2: 3}, "points": {}, "totals": {}, "explanation": ""})
	stage._flush_reveal()
	assert_eq(stage.host.pose, QuizHost.Pose.DISAPPOINTED, "nobody right")


func test_winner_cheers_and_last_place_sulks() -> void:
	stage.on_event({"type": &"quiz_finished", "ranking": [{"player": 2, "points": 1500, "rank": 1}, {"player": 1, "points": 0, "rank": 2}]})
	assert_eq(stage.host.pose, QuizHost.Pose.HAPPY)
	assert_eq((stage.podiums[2]["puppet"] as BeanPuppet).mood, BeanPuppet.Mood.CHEER)
	assert_eq((stage.podiums[1]["puppet"] as BeanPuppet).mood, BeanPuppet.Mood.SAD)
	assert_true(stage.banner.visible)
	assert_false(stage.card.visible, "the banner never sits on top of the question card")
