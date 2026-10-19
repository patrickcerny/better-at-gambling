extends GutTest
## The match scene, the quiz stage and the results podium run without errors with the 3D world in
## the `PixelView` sub viewport at the window's full resolution (linear filtering): the 3D sits
## there with the current camera, the stages' 2D layers stay on the window, and keys still reach
## the stage through the container.

var scene: MatchScene


func _start() -> void:
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_process_frames(3)


func _players() -> Array:
	var ids: Array = []
	for pid: int in scene.avatars:
		ids.append(pid)
	return ids


func test_casino_quiz_and_results_in_the_world_view() -> void:
	var errors: int = Log.error_count
	await _start()
	var pv: PixelView = scene.pixel_view
	assert_eq(pv.container.stretch_shrink, 1, "full resolution")
	assert_eq(pv.container.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR, "smooth filtering")
	assert_eq(pv.viewport.size, Vector2i(get_tree().root.size), "the window's own pixels")
	assert_true(pv.viewport.is_ancestor_of(scene.map), "map inside the world viewport")
	assert_true(pv.viewport.is_ancestor_of(scene.world_root), "world inside the world viewport")
	assert_eq(pv.viewport.get_camera_3d(), scene.local.cam.camera, "the player's camera draws the viewport")
	assert_null(get_tree().root.get_camera_3d(), "the window itself draws no 3D")
	assert_false(pv.viewport.is_ancestor_of(scene.ui_layer), "HUD stays on the window")
	# The curtain starts parked off both edges, so the casino is visible at spawn.
	var w: float = scene.curtain_left.get_parent_area_size().x
	assert_true(scene.curtain_left.get_global_rect().end.x <= 0.0, "left curtain off screen at spawn")
	assert_true(scene.curtain_right.get_global_rect().position.x >= w, "right curtain off screen at spawn")
	scene._set_curtain(0.0)
	assert_almost_eq(scene.curtain_left.get_global_rect().position.x, 0.0, 0.5, "closed curtain covers the left half")
	assert_almost_eq(scene.curtain_right.get_global_rect().end.x, w, 0.5, "closed curtain covers the right half")
	scene._set_curtain(1.0)
	# Quiz: the stage's set is in the world viewport, its UI on the window, and a number key still answers.
	scene._open_stage({"minigame": &"quiz", "players": _players()}, {})
	await wait_seconds(MatchScene.curtain_times().x + 0.3)  # curtain closes, then the stage is created behind it
	var stage: QuizStage = scene.stage as QuizStage
	assert_not_null(stage, "quiz stage opened")
	if stage == null:
		return
	await wait_seconds(MatchScene.curtain_times().y + MatchScene.curtain_times().z + 0.3)  # holds on the name, opens
	assert_true(scene.curtain_left.get_global_rect().end.x <= 0.0, "curtain opened again on the stage")
	assert_true(pv.viewport.is_ancestor_of(stage), "stage set inside the world viewport")
	assert_eq(stage.ui.get_parent(), scene, "stage UI hosted on the window")
	assert_eq(pv.viewport.get_camera_3d(), stage.camera, "stage camera took over")
	stage.on_event({"type": &"quiz_started", "players": _players(), "questions": 1, "answer_time": 12.0})
	stage.on_event({"type": &"quiz_question", "index": 0, "count": 1, "question": "Pick one", "answers": ["A", "B", "C", "D"], "category": "silly", "dynamic": false, "seconds": 12.0})
	await wait_process_frames(2)
	var k := InputEventKey.new()
	k.keycode = KEY_1
	k.pressed = true
	get_tree().root.push_input(k)
	assert_eq(stage.my_answer, 0, "key 1 reached the stage through the container")
	var ui: CanvasLayer = stage.ui
	scene._close_stage()
	await wait_process_frames(2)
	assert_false(is_instance_valid(ui), "hosted stage UI freed with the stage")
	assert_eq(pv.viewport.get_camera_3d(), scene.local.cam.camera, "back to the player's camera")
	# Results podium.
	var rows: Array = []
	var rank: int = 1
	for pid: int in _players():
		rows.append({"player": pid, "name": "P%d" % pid, "money": 1000 - rank * 10, "rank": rank, "series": [1000, 1000 - rank * 10]})
		rank += 1
	scene.view.state.standings = rows
	scene._show_results(rows)
	await wait_process_frames(2)
	assert_not_null(scene.results_panel)
	assert_true(pv.viewport.is_ancestor_of(scene.results_panel), "podium inside the world viewport")
	assert_eq(scene.results_panel.ui.get_parent(), scene, "results UI hosted on the window")
	assert_eq(pv.viewport.get_camera_3d(), scene.results_panel.camera)
	scene.results_panel.finish_show()
	await wait_process_frames(2)
	assert_eq(Log.error_count, errors, "no errors")
