extends GutTest
## The match scene, the quiz stage and the results podium run under every pixel look (Off, Light,
## Retro, Chunky) without errors: the 3D sits in the pixel view's sub viewport with the current
## camera, the stages' 2D layers stay on the sharp window, keys still reach the stage through the
## container, and the setting flips live mid-match.

var scene: MatchScene
var _old_scale: int


func before_each() -> void:
	_old_scale = Settings.pixel_scale()


func after_each() -> void:
	Settings.change("video", "pixel_scale", _old_scale)


func _start(scale: int) -> void:
	Settings.change("video", "pixel_scale", scale)
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_process_frames(3)


func _players() -> Array:
	var ids: Array = []
	for pid: int in scene.avatars:
		ids.append(pid)
	return ids


func test_casino_quiz_and_results_under_every_look() -> void:
	for s: int in PixelView.SCALES:
		var errors: int = Log.error_count
		await _start(s)
		var pv: PixelView = scene.pixel_view
		assert_eq(pv.shrink(), s, "1/%d" % s)
		assert_true(pv.viewport.is_ancestor_of(scene.map), "map inside the pixel viewport")
		assert_true(pv.viewport.is_ancestor_of(scene.world_root), "world inside the pixel viewport")
		assert_eq(pv.viewport.get_camera_3d(), scene.local.cam.camera, "the player's camera draws the viewport")
		assert_null(get_tree().root.get_camera_3d(), "the window itself draws no 3D")
		assert_false(pv.viewport.is_ancestor_of(scene.ui_layer), "HUD stays on the window")
		# Quiz: the stage's set is pixelated, its UI is not, and a number key still answers.
		scene._open_stage({"minigame": &"quiz", "players": _players()}, {})
		await wait_process_frames(40)  # curtain animation (0.5s) + stage creation
		var stage: QuizStage = scene.stage as QuizStage
		assert_not_null(stage, "quiz stage opened")
		if stage == null:
			continue
		assert_true(pv.viewport.is_ancestor_of(stage), "stage set inside the pixel viewport")
		assert_eq(stage.ui.get_parent(), scene, "stage UI hosted on the sharp window")
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
		assert_true(pv.viewport.is_ancestor_of(scene.results_panel), "podium inside the pixel viewport")
		assert_eq(scene.results_panel.ui.get_parent(), scene, "results UI hosted on the sharp window")
		assert_eq(pv.viewport.get_camera_3d(), scene.results_panel.camera)
		scene.results_panel.finish_show()
		await wait_process_frames(2)
		# Flip the look live.
		var other: int = 1 if s != 1 else 4
		Settings.change("video", "pixel_scale", other)
		await wait_process_frames(2)
		assert_eq(pv.shrink(), other, "applied live")
		assert_eq(pv.viewport.size, Vector2i(get_tree().root.size) / other)
		assert_eq(Log.error_count, errors, "no errors at 1/%d" % s)
		scene.queue_free()
		await wait_process_frames(2)
