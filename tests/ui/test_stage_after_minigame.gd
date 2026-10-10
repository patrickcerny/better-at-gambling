extends GutTest
## After a minigame, in the real match scene: the stage's full-screen UI (its own canvas layer,
## above the HUD's) gives way to the round's rewards and their item cards, and once everyone is
## back in the hall the stage and its layer are gone and the HUD with the item bar is back.

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


func _stage_layers() -> Array[Node]:
	return scene.find_children("StageUI", "CanvasLayer", true, false).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())


func test_rewards_show_above_the_finished_stage_and_the_hud_comes_back() -> void:
	var players: Array = _players()
	scene._open_stage({"minigame": &"vote_race", "players": players}, {})
	assert_true(await _wait_for(func() -> bool: return scene.stage != null), "stage built")
	var stage_ui: CanvasLayer = scene.stage.ui
	assert_true(stage_ui.visible)
	assert_gt(stage_ui.layer, scene.ui_layer.layer, "the stage covers the HUD layer while it plays")
	var rows: Array = []
	for i: int in players.size():
		rows.append({"player": players[i], "placement": i + 1, "cash": 100, "item": &""})
	scene._on_event({"type": &"rewards_started", "rewards": rows, "seconds": 3.0})
	assert_true(scene.reward_panel.visible, "the rewards are up")
	assert_false(stage_ui.visible, "and nothing of the stage is drawn over them")
	scene._regroup()
	await wait_process_frames(2)
	assert_null(scene.stage, "the stage is gone")
	assert_eq(_stage_layers().size(), 0, "with its UI layer")
	assert_true(scene.hud.visible, "the HUD and its item bar are back")
	assert_true(scene.hud.is_visible_in_tree())
