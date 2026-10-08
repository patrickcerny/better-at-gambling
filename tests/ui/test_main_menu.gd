extends GutTest
## Main menu (Patrick's playtest notes): the logo and entries are centred; PLAY ONLINE, PRACTICE,
## TUTORIAL, QUIT; the settings sit behind a small gear in the bottom-right corner; no "Host on
## this PC" or "Rejoin last party"; TUTORIAL opens the how-to-play pages and BACK returns.

var menu: Control


func before_each() -> void:
	menu = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
	add_child_autofree(menu)
	await wait_process_frames(3)


func _texts(root: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for b: Node in root.find_children("*", "Button", true, false):
		out.append((b as Button).text)
	return out


func test_entries_in_order_without_a_settings_entry() -> void:
	var box: VBoxContainer = menu.get_node("Center/Column/VBox")
	var names: PackedStringArray = []
	for b: Node in box.get_children():
		names.append((b as Button).text)
	assert_eq(names, PackedStringArray(["PLAY ONLINE", "PRACTICE", "TUTORIAL", "QUIT"]))


func test_logo_and_entries_are_centred() -> void:
	var w: float = menu.get_viewport_rect().size.x
	var h: float = menu.get_viewport_rect().size.y
	for path: String in ["Center/Column/Logo", "Center/Column/Rule", "Center/Column/VBox", "Center/Column/VBox/PlayOnline"]:
		var r: Rect2 = (menu.get_node(path) as Control).get_global_rect()
		assert_almost_eq(r.get_center().x, w * 0.5, 2.0, "%s centred horizontally" % path)
	var col: Rect2 = (menu.get_node("Center/Column") as Control).get_global_rect()
	assert_almost_eq(col.get_center().y, h * 0.5, 4.0, "column centred vertically")
	for b: Node in menu.get_node("Center/Column/VBox").get_children():
		assert_eq((b as Button).alignment, HORIZONTAL_ALIGNMENT_CENTER, "%s text centred" % (b as Button).text)


func test_gear_in_the_bottom_right_opens_settings() -> void:
	var gear: GearButton = menu.find_child("SettingsButton", true, false) as GearButton
	assert_not_null(gear, "settings gear")
	if gear == null:
		return
	var vp: Vector2 = menu.get_viewport_rect().size
	var r: Rect2 = gear.get_global_rect()
	assert_gt(r.position.x, vp.x * 0.85, "right edge")
	assert_gt(r.position.y, vp.y * 0.85, "bottom edge")
	assert_lt(r.end.x, vp.x + 0.5)
	assert_lt(r.end.y, vp.y + 0.5)
	assert_lt(r.size.x, 100.0, "small")
	gear.pressed.emit()
	var settings: SettingsPanel = menu.find_children("*", "SettingsPanel", true, false)[0] as SettingsPanel
	assert_true(settings.visible)
	assert_false(settings._resume.visible, "no RESUME from the main menu")
	settings.close()
	assert_true(gear.has_focus(), "focus back on the gear")


func test_no_host_on_this_pc_or_rejoin() -> void:
	menu.call(&"_show_online")
	await wait_process_frames(1)
	for t: String in _texts(menu):
		assert_false(t.to_lower().contains("host on"), "no Host on this PC: %s" % t)
		assert_false(t.to_lower().contains("rejoin"), "no Rejoin last party: %s" % t)
	assert_false(menu.has_method(&"_host_local"))
	assert_false(menu.has_method(&"_rejoin_last"))
	assert_true("Create Party" in _texts(menu), "the online form is still there")


func test_tutorial_pages_and_back() -> void:
	(menu.get_node("Center/Column/VBox/Tutorial") as Button).pressed.emit()
	await wait_process_frames(1)
	var how: HowToPlayPanel = menu.find_child("HowToPlay", true, false) as HowToPlayPanel
	assert_not_null(how)
	if how == null:
		return
	assert_true(how.visible)
	assert_false((menu.get_node("Center/Column/VBox") as Control).visible, "entries step aside")
	assert_gte(HowToPlayPanel.PAGES.size(), 5, "goal, moving, tables, items, minigames, jail")
	assert_eq(how.page, 0)
	assert_true(how.prev_button.disabled)
	for i: int in HowToPlayPanel.PAGES.size() - 1:
		how.next_button.pressed.emit()
	assert_eq(how.page, HowToPlayPanel.PAGES.size() - 1)
	assert_true(how.next_button.disabled)
	assert_string_contains(how.heading.text, "JAIL")
	assert_false(how.body.text.contains("{"), "key names filled in")
	how.back_button.pressed.emit()
	assert_false(how.visible)
	assert_true((menu.get_node("Center/Column/VBox") as Control).visible)
	assert_true((menu.get_node("Center/Column/Logo") as Control).visible)
