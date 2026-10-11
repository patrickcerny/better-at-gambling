extends GutTest
## Escape works inside minigames (Patrick, 0.9.2: "can't press Escape in minigames, should be
## able to still quit and stuff"): the pause menu opens over a table stage and over a walkable
## room, on a layer above the stage's UI, and RESUME gives the stage its own input mode back.

var scene: MatchScene


func before_each() -> void:
	Net.stop()
	MatchScene.test_dummies = 3
	MatchScene.test_briefing = 0.0
	MatchScene.test_curtain_fast = true
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_process_frames(3)


func after_each() -> void:
	MatchScene.test_dummies = 0
	MatchScene.test_briefing = -1.0
	MatchScene.test_curtain_fast = false


func _players() -> Array:
	var ids: Array = []
	for pid: int in scene.avatars:
		ids.append(pid)
	return ids


func _wait_for(cond: Callable, seconds: float = 3.0) -> bool:
	var t: float = 0.0
	while not cond.call() and t < seconds:
		await wait_process_frames(1)
		t += get_process_delta_time()
	return cond.call()


func _open(minigame: StringName) -> void:
	scene._open_stage({"minigame": minigame, "players": _players()}, {})
	assert_true(await _wait_for(func() -> bool: return scene.stage != null), "stage built")
	await wait_process_frames(2)


func test_escape_opens_the_pause_menu_over_a_table_minigame() -> void:
	await _open(&"vote_race")
	assert_true(await _wait_for(func() -> bool: return scene.router.mode == InputRouter.Mode.STAGE), "the stage owns the screen")
	scene._on_pause()
	assert_not_null(scene.pause_menu, "the pause menu exists")
	assert_true(scene.pause_menu.visible, "and is open")
	assert_eq(scene.router.mode, InputRouter.Mode.MENU)
	assert_gt(scene.pause_layer.layer, scene.stage.ui.layer, "drawn above the stage's UI")
	assert_true(scene.pause_layer.visible)
	scene._on_pause()  # Escape again: resume
	assert_false(scene.pause_menu.visible)
	assert_eq(scene.router.mode, InputRouter.Mode.STAGE, "back to the stage's cursor, not walking")


func test_escape_opens_the_pause_menu_in_a_walkable_room_and_resume_walks_again() -> void:
	await _open(&"pass_the_bomb")
	assert_true(await _wait_for(func() -> bool: return scene.router.mode == InputRouter.Mode.WALK), "walking in the room")
	scene._on_pause()
	assert_true(scene.pause_menu.visible)
	assert_eq(scene.router.mode, InputRouter.Mode.MENU)
	scene.pause_menu.resumed.emit()
	assert_eq(scene.router.mode, InputRouter.Mode.WALK, "RESUME: walking again")


func test_the_rules_card_does_not_swallow_escape() -> void:
	var card := MinigameBriefing.new()
	add_child_autofree(card)
	await wait_process_frames(1)
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.physical_keycode = KEY_ESCAPE
	card._input(esc)
	assert_false(get_viewport().is_input_handled(), "Escape goes on to the input router")
	var space := InputEventKey.new()
	space.pressed = true
	space.physical_keycode = KEY_SPACE
	card._input(space)
	assert_true(get_viewport().is_input_handled(), "other keys are the card's")
