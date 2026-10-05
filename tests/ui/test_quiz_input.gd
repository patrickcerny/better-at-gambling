extends GutTest
## Casino Quiz answers with keyboard, gamepad and mouse (M4 acceptance: "quiz playable with
## keyboard/mouse/gamepad"). Events are pushed through the viewport like real input.

var stage: QuizStage


func before_each() -> void:
	var st := ClientMatchState.new()
	st.players = {1: {"id": 1, "name": "Me", "color": 0}, 2: {"id": 2, "name": "Bot", "color": 1, "bot": true}}
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
