extends GutTest
## The match scene's 3D holder (`PixelView`, the name kept from the pixel look that was removed in
## 0.9.15): the world renders inside a sub viewport at the window's full resolution with linear
## filtering, whatever the settings say; the UI stays outside it, it sizes itself in window pixels,
## and it is never built on the dedicated server. Settings > Video has no look toggle any more.


func _view(dedicated: bool = false) -> PixelView:
	var pv := PixelView.new()
	add_child_autofree(pv)
	pv.setup(dedicated)
	return pv


func test_world_renders_at_the_windows_full_size_with_linear_filtering() -> void:
	var pv: PixelView = _view()
	assert_not_null(pv.viewport)
	assert_true(pv.world.get_parent() == pv.viewport, "the world renders inside the sub viewport")
	assert_false(pv.viewport.own_world_3d, "shares the window's World3D")
	assert_true(pv.viewport.audio_listener_enable_3d, "its camera positions 3D audio")
	assert_eq(pv.container.stretch_shrink, 1, "full resolution")
	assert_eq(pv.container.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR, "smooth filtering")
	await wait_process_frames(1)
	assert_eq(pv.viewport.size, Vector2i(get_tree().root.size), "the window's own pixels")


func test_settings_changes_leave_it_at_full_resolution() -> void:
	var pv: PixelView = _view()
	Settings.changed.emit()  # any settings change (the panel, F11)
	await wait_process_frames(1)
	assert_eq(pv.container.stretch_shrink, 1)
	assert_eq(pv.container.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR)
	assert_eq(pv.viewport.size, Vector2i(get_tree().root.size))


func test_container_is_sized_in_window_pixels() -> void:
	var pv: PixelView = _view()
	var root: Window = get_tree().root
	assert_eq(pv.container.size, Vector2(root.size))
	var canvas: Vector2 = root.get_visible_rect().size
	assert_almost_eq(pv.container.scale.x, canvas.x / float(root.size.x), 0.0001, "covers the canvas")
	assert_almost_eq(pv.container.scale.y, canvas.y / float(root.size.y), 0.0001)
	assert_eq(pv.container.mouse_filter, Control.MOUSE_FILTER_PASS, "events reach the viewport and then the router")


func test_dedicated_server_has_no_viewport() -> void:
	var pv: PixelView = _view(true)
	assert_null(pv.viewport)
	assert_null(pv.container)
	assert_eq(pv.world.get_parent(), pv)
	assert_eq(pv.world_viewport(), get_viewport())


func test_to_canvas_scales_viewport_points_onto_the_window() -> void:
	var pv: PixelView = _view()
	# A canvas that differs from the viewport's pixels (as under the window's stretch mode).
	pv.container.size = Vector2(640, 360)
	pv.container.scale = Vector2.ONE
	var cam := Camera3D.new()
	pv.world.add_child(cam)
	var ui := Control.new()
	add_child_autofree(ui)
	await wait_process_frames(1)
	var p: Vector2 = PixelView.to_canvas(cam, Vector2(100, 50), ui)
	var k: Vector2 = ui.get_viewport_rect().size / pv.viewport.get_visible_rect().size
	assert_almost_eq(p.x, 100.0 * k.x, 0.01)
	assert_almost_eq(p.y, 50.0 * k.y, 0.01)
	var inside := Control.new()
	pv.world.add_child(inside)
	assert_eq(PixelView.to_canvas(cam, Vector2(7, 7), inside), Vector2(7, 7), "identity within one viewport")


func test_video_tab_has_no_look_toggle() -> void:
	var panel := SettingsPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	assert_false("pixel_look_check" in panel)
	assert_null(panel.find_child("PixelLook", true, false))
	assert_null(panel.find_child("PixelLookHint", true, false))
	assert_false(panel.checks.has("video/pixel_look"))
