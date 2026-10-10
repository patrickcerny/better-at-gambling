extends GutTest
## The minigame curtain in the real match scene: it closes, holds on the minigame's name while the
## stage is built behind it, then opens (gathering into the tiebacks, then off both edges); after
## the round's rewards it closes again on "Back to the casino". Runs with the fast test timings.

var scene: MatchScene


func before_each() -> void:
	Net.stop()
	MatchScene.test_dummies = 1
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


func test_timings() -> void:
	MatchScene.test_curtain_fast = false
	assert_eq(MatchScene.curtain_times(), Vector3(0.6, 1.5, 0.8), "close 0.6 s, hold 1.5 s, open 0.8 s")
	MatchScene.test_curtain_fast = true
	var fast: Vector3 = MatchScene.curtain_times()
	assert_lt(fast.x + fast.y + fast.z, 0.5)


func test_starts_open() -> void:
	assert_eq(scene.curtain_open, 1.0)
	assert_false(scene.curtain_plaque.visible, "no name while open")
	assert_true(scene.curtain_left.get_global_rect().end.x <= 0.0)


func test_minigame_sequence_closes_holds_on_the_name_and_opens() -> void:
	scene._open_stage({"minigame": &"quiz", "players": _players()}, {})
	assert_null(scene.stage, "the stage waits behind the closed curtain")
	assert_true(await _wait_for(func() -> bool: return scene.curtain_open == 0.0), "closed")
	await wait_process_frames(1)
	assert_not_null(scene.stage, "stage built behind it")
	var def: MinigameDefinition = Registry.minigames[&"quiz"]
	assert_eq(scene.curtain_title.text, def.display_name.to_upper())
	assert_true(scene.curtain_plaque.visible)
	assert_almost_eq(scene.curtain_plaque.modulate.a, 1.0, 0.01, "name fully shown while closed")
	var w: float = scene.curtain_left.get_parent_area_size().x
	assert_almost_eq(scene.curtain_left.get_global_rect().position.x, 0.0, 0.5, "left half covered")
	assert_almost_eq(scene.curtain_right.get_global_rect().end.x, w, 0.5, "right half covered")
	assert_true(await _wait_for(func() -> bool: return scene.curtain_open > 0.0 and scene.curtain_open < 1.0), "opening")
	assert_true(await _wait_for(func() -> bool: return scene.curtain_open == 1.0), "open again")
	assert_false(scene.curtain_plaque.visible)
	assert_true(scene.curtain_left.get_global_rect().end.x <= 0.0, "left panel off screen")
	assert_true(scene.curtain_right.get_global_rect().position.x >= w, "right panel off screen")


func test_half_open_is_gathered_at_the_tiebacks() -> void:
	scene._set_curtain(0.5)
	var m: ShaderMaterial = scene.curtain_left.material as ShaderMaterial
	assert_gt(float(m.get_shader_parameter(&"gather")), 0.5, "fabric pulled into the tiebacks")
	assert_almost_eq(scene.curtain_left.get_global_rect().position.x, 0.0, 0.5, "still hanging on the rail")
	scene._set_curtain(1.0)


func test_back_to_the_casino_after_the_rewards() -> void:
	scene._curtain_back_to_casino(0.1)
	assert_eq(scene.curtain_open, 1.0, "waits for the rewards to end")
	assert_true(await _wait_for(func() -> bool: return scene.curtain_open == 0.0), "closed")
	assert_eq(scene.curtain_title.text, "BACK TO THE CASINO")
	assert_false(scene.curtain_kicker.visible)
	assert_true(await _wait_for(func() -> bool: return scene.curtain_open == 1.0), "open again")
