extends GutTest
## Roulette Royale stage: builds without crashing (one camera, the reused wheel), follows a whole
## game from server events, catches up from a snapshot, and sends schema-valid picks.

var stage: RouletteRoyaleStage
var st: ClientMatchState


func before_each() -> void:
	st = ClientMatchState.new()
	st.players = {1: {"id": 1, "name": "Me", "color": 0}, 2: {"id": 2, "name": "Other", "color": 1}, 3: {"id": 3, "name": "Third", "color": 2}}
	stage = RouletteRoyaleStage.new()
	add_child_autofree(stage)


func after_each() -> void:
	Vfx.force_enabled = false


func _begin(snapshot: Dictionary = {}) -> void:
	stage.begin(st, 1, {"minigame": &"roulette_royale", "players": [1, 2, 3]}, snapshot)


func _cameras() -> int:
	return stage.find_children("*", "Camera3D", true, false).size()


func _started() -> void:
	stage.on_event({"type": &"roulette_royale_started", "players": [1, 2, 3], "hearts": {1: 3, 2: 3, 3: 3}, "max_spins": 6, "pick_time": 5.0, "spin_time": 3.4, "seconds": 3.0})


func _open(spin: int, alive: Array, hearts: Dictionary) -> void:
	stage.on_event({"type": &"roulette_royale_pick_open", "spin": spin, "max_spins": 6, "seconds": 5.0, "alive": alive, "hearts": hearts})


func test_builds_with_exactly_one_camera() -> void:
	_begin()
	assert_eq(_cameras(), 1, "one stage camera; the wheel model's own camera is dropped")
	assert_not_null(stage.camera)
	assert_eq(stage.buttons.size(), 3)
	assert_eq(stage.board.get_child_count(), 3, "a hearts row per bean from the start event")
	assert_true(stage.buttons[0].disabled, "no picks during the intro")


func test_builds_with_wheel_fx_when_effects_are_on() -> void:
	Vfx.force_enabled = true
	_begin()
	assert_not_null(stage.wheel_fx, "reuses the roulette wheel's spin fx")
	assert_eq(_cameras(), 1)


func test_pick_flow_locks_in() -> void:
	_begin()
	_started()
	_open(0, [1, 2, 3], {1: 3, 2: 3, 3: 3})
	assert_true(stage.picking)
	assert_false(stage.buttons[2].disabled)
	stage.buttons[2].pressed.emit()
	assert_eq(stage.my_pick, 2)
	assert_true(stage.buttons[0].disabled, "one pick per spin")
	stage.buttons[0].pressed.emit()
	assert_eq(stage.my_pick, 2)


func test_keyboard_and_gamepad_pick() -> void:
	_begin()
	_started()
	_open(0, [1, 2, 3], {1: 3, 2: 3, 3: 3})
	var k := InputEventKey.new()
	k.keycode = KEY_2
	k.pressed = true
	get_tree().root.push_input(k)
	assert_eq(stage.my_pick, 1)
	_open(1, [1, 2, 3], {1: 3, 2: 3, 3: 3})
	assert_eq(stage.my_pick, -1, "new spin, new pick")
	var b := InputEventJoypadButton.new()
	b.button_index = RouletteRoyaleStage.PAD_BUTTONS[0]
	b.pressed = true
	get_tree().root.push_input(b)
	assert_eq(stage.my_pick, 0)


func test_pick_intent_matches_the_schema() -> void:
	var intent: Dictionary = Intents.make(&"submit_answer", {"question": 0, "index": 2})
	assert_true(Intents.validate(intent).is_empty(), "the server accepts the shape the stage sends")


func test_full_game_from_events_tracks_hearts_and_eliminations() -> void:
	_begin()
	_started()
	_open(0, [1, 2, 3], {1: 3, 2: 3, 3: 3})
	stage.on_event({"type": &"roulette_royale_picked", "player": 2, "spin": 0})
	assert_true(stage.picked.has(2))
	stage.on_event({"type": &"roulette_royale_spin", "spin": 0, "seconds": 3.4})
	assert_false(stage.picking)
	stage.on_event({"type": &"roulette_royale_result", "spin": 0, "number": 0, "color": &"green", "picks": {1: &"green", 2: &"red", 3: &""},
		"deltas": {1: 0, 2: -1, 3: -1}, "hearts": {1: 3, 2: 2, 3: 0}, "eliminated": [3], "alive": [1, 2]})
	assert_eq(int(stage.hearts[2]), 2)
	assert_false(3 in stage.alive)
	# String-keyed tables (as they may arrive off the wire) are fine too.
	_open(1, [1, 2], {"1": 3, "2": 2, "3": 0})
	assert_eq(int(stage.hearts[2]), 2)
	stage.on_event({"type": &"roulette_royale_result", "spin": 1, "number": 2, "color": &"black", "picks": {"1": &"black", "2": &"red"},
		"deltas": {"1": 0, "2": -1}, "hearts": {"1": 3, "2": 0, "3": 0}, "eliminated": [2], "alive": [1]})
	assert_eq(stage.alive, [1] as Array[int])
	stage.on_event({"type": &"roulette_royale_finished", "ranking": [{"player": 1, "rank": 1, "points": 300}, {"player": 2, "rank": 2, "points": 100}, {"player": 3, "rank": 3, "points": 0}]})
	assert_true(stage.finished)
	assert_true(stage.banner.visible)
	assert_string_contains(stage.banner.text, "ME WINS")
	assert_false(stage.button_row.visible)


func test_eliminated_player_cannot_pick() -> void:
	_begin()
	_started()
	_open(3, [2, 3], {1: 0, 2: 2, 3: 1})
	assert_true(stage.buttons[0].disabled)
	stage.buttons[0].pressed.emit()
	assert_eq(stage.my_pick, -1)


func test_private_state_restores_own_pick() -> void:
	_begin()
	_started()
	_open(0, [1, 2, 3], {1: 3, 2: 3, 3: 3})
	stage.on_private({"minigame": {"spin": 0, "pick": 1, "alive": true, "can_pick": false}})
	assert_eq(stage.my_pick, 1)
	stage.on_private({"minigame": {}})
	stage.on_private({})
	assert_eq(stage.my_pick, 1)


func test_catch_up_from_snapshot_mid_pick() -> void:
	var logic := RouletteRoyaleLogic.new()
	logic.setup([1, 2, 3] as Array[int], SeededRng.new(3), BalanceConfig.new(), {}, {})
	while logic.state != RouletteRoyaleLogic.State.PICK:
		logic.tick(0.05, 0.0)
	logic.submit(2, {"question": logic.spin, "index": 0}, 0.0)
	_begin(logic.get_public_state())
	assert_true(stage.picking)
	assert_true(stage.picked.has(2), "who already locked in survives the catch-up")
	assert_false(stage.buttons[0].disabled)


func test_catch_up_from_snapshot_after_results_and_finish() -> void:
	var logic := RouletteRoyaleLogic.new()
	logic.setup([1, 2, 3] as Array[int], SeededRng.new(3), BalanceConfig.new(), {}, {})
	var t: float = 0.0
	while not logic.is_finished() and t < 120.0:
		if logic.state == RouletteRoyaleLogic.State.RESULT and logic.spin == 0:
			break
		logic.tick(0.05, t)
		t += 0.05
	_begin(logic.get_public_state())
	assert_false(stage.picking)
	assert_eq(stage.board.get_child_count(), 3)
	while not logic.is_finished() and t < 120.0:
		logic.tick(0.05, t)
		t += 0.05
	var late := RouletteRoyaleStage.new()
	add_child_autofree(late)
	late.begin(st, 1, {"minigame": &"roulette_royale", "players": []}, logic.get_public_state())
	assert_true(late.finished)
	assert_eq(late.players.size(), 3, "players come from the snapshot when the start has none")


func test_ignores_other_minigames_events() -> void:
	_begin()
	stage.on_event({"type": &"quiz_question", "index": 0})
	stage.on_event({"type": &"money_changed", "player": 1})
	assert_eq(stage.spin, -1)
