extends GutTest
## The level pass track scrolls by dragging with the left mouse button too (Patrick 2026-11-15:
## "drag season pass to scroll also"), and a drag never counts as a click on a reward.


func _press(pass_panel: LevelPassPanel, at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	e.global_position = at
	pass_panel._input(e)


func _move(pass_panel: LevelPassPanel, at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	pass_panel._input(e)


func test_drag_scrolls_the_track_and_is_no_click() -> void:
	var menu: Control = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
	add_child_autofree(menu)
	await wait_process_frames(3)
	var lp: LevelPassPanel = menu.get("level_pass")
	lp.open()
	await wait_process_frames(3)
	lp.scroll.scroll_horizontal = 0
	await wait_process_frames(1)
	var r: Rect2 = lp.scroll.get_global_rect()
	var start: Vector2 = r.get_center()
	_press(lp, start, true)
	_move(lp, start + Vector2(-4, 0))
	assert_eq(lp.scroll.scroll_horizontal, 0, "a few pixels are still a click")
	assert_false(lp._dragged)
	_move(lp, start + Vector2(-300, 0))
	await wait_process_frames(1)
	assert_gt(lp.scroll.scroll_horizontal, 200, "dragging left moves the track on")
	assert_true(lp._dragged, "the release after a drag is no click on a reward")
	_press(lp, start + Vector2(-300, 0), false)
	_press(lp, start, true)
	assert_false(lp._dragged, "the next press can click again")
	_press(lp, start, false)
