extends GutTest
## Pixel look (Patrick: "this pixelated blur effect the game Yap Yap has"): the setting maps
## Off / Light / Retro / Chunky to a shrink of 1 / 2 / 3 / 4, applies live to the world's sub
## viewport, keeps the UI outside it, sizes itself in window pixels, and is never built on the
## dedicated server.

var _old_scale: int


func before_each() -> void:
	_old_scale = Settings.pixel_scale()


func after_each() -> void:
	Settings.change("video", "pixel_scale", _old_scale)


func _view(dedicated: bool = false) -> PixelView:
	var pv := PixelView.new()
	add_child_autofree(pv)
	pv.setup(dedicated)
	return pv


func test_labels_map_to_shrink_factors() -> void:
	assert_eq(PixelView.LABELS, ["Off", "Light (1/2)", "Retro (1/3)", "Chunky (1/4)"] as Array[String])
	assert_eq(PixelView.SCALES, [1, 2, 3, 4] as Array[int])
	assert_eq(int((Settings.DEFAULTS["video"] as Dictionary)["pixel_scale"]), 3, "Retro by default")


func test_setting_changes_the_shrink_live() -> void:
	var pv: PixelView = _view()
	assert_not_null(pv.viewport)
	assert_true(pv.world.get_parent() == pv.viewport, "the world renders inside the sub viewport")
	assert_false(pv.viewport.own_world_3d, "shares the window's World3D")
	assert_true(pv.viewport.audio_listener_enable_3d, "its camera positions 3D audio")
	assert_eq(pv.container.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "hard pixels")
	for s: int in PixelView.SCALES:
		Settings.change("video", "pixel_scale", s)
		assert_eq(pv.shrink(), s, "shrink %d" % s)
		assert_eq(pv.container.stretch_shrink, s)
		await wait_process_frames(1)
		var want: Vector2i = Vector2i(get_tree().root.size) / s
		assert_eq(pv.viewport.size, want, "viewport is the window's pixels / %d" % s)
	Settings.change("video", "pixel_scale", 9)
	assert_eq(pv.shrink(), 4, "clamped to the offered steps")


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
	assert_eq(pv.shrink(), 1)
	assert_eq(pv.world_viewport(), get_viewport())
	Settings.change("video", "pixel_scale", 4)
	assert_eq(pv.shrink(), 1, "the server ignores the setting")


func test_to_canvas_scales_viewport_points_onto_the_window() -> void:
	Settings.change("video", "pixel_scale", 3)
	var pv: PixelView = _view()
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
	assert_eq(PixelView.shrink_of(cam), 3)
	assert_eq(PixelView.shrink_of(ui), 1)


func test_settings_panel_offers_the_four_looks() -> void:
	Settings.change("video", "pixel_scale", 2)
	var panel := SettingsPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	assert_eq(panel._pixel.item_count, 4)
	assert_eq(panel._pixel.get_item_text(2), "Retro (1/3)")
	assert_eq(panel._pixel.selected, 1, "shows the saved Light")
	panel._pixel.item_selected.emit(3)
	assert_eq(Settings.pixel_scale(), 4, "picking Chunky applies at once")


func test_name_tags_stay_readable_when_shrunk() -> void:
	var far_px: float = 0.19 / (2.0 * 40.0 * tan(deg_to_rad(35.0))) * 1080.0
	for s: float in [2.0, 3.0, 4.0]:
		var k: float = NameTag.size_factor(40.0, 70.0, 0.19, s)
		assert_almost_eq(far_px * k / s, NameTag.MIN_RENDERED_PX, 0.01, "at least %d rendered pixels at 1/%d" % [int(NameTag.MIN_RENDERED_PX), int(s)])
	assert_almost_eq(NameTag.size_factor(40.0, 70.0, 0.19, 1.0), NameTag.size_factor(40.0, 70.0, 0.19), 0.0001, "off is unchanged")
