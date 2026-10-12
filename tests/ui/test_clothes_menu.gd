extends GutTest
## Clothes menu (Patrick: "Remove in-game skin picker, put in clothes menu (T-shirt icon next to
## settings gear)"): the T-shirt button beside the main menu's gear opens a grid of every skin;
## picking one saves it in user://settings.cfg, so `SceneRouter.profile_cosmetics()` sends it with
## the next join. The lobby panel no longer has a skin picker.

var menu: Control
var _old_skin: String


func before_each() -> void:
	_old_skin = str(Settings.get_value("profile", "skin", "bean"))
	menu = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
	add_child_autofree(menu)
	await wait_process_frames(3)


func after_each() -> void:
	Settings.set_value("profile", "skin", _old_skin)
	Settings.save()


func test_tshirt_sits_left_of_the_gear() -> void:
	var tshirt: Button = menu.find_child("ClothesButton", true, false) as Button
	var gear: Button = menu.find_child("SettingsButton", true, false) as Button
	assert_not_null(tshirt, "T-shirt button in the main menu")
	assert_eq(tshirt.tooltip_text, "Clothes")
	assert_almost_eq(tshirt.size, gear.size, Vector2.ONE, "same size as the gear")
	assert_almost_eq(tshirt.global_position.y, gear.global_position.y, 1.0, "same row as the gear")
	assert_lt(tshirt.global_position.x + tshirt.size.x, gear.global_position.x, "left of the gear")


func test_tshirt_opens_the_clothes_grid_and_picking_saves_the_skin() -> void:
	Settings.set_value("profile", "skin", "bean")
	var tshirt: Button = menu.find_child("ClothesButton", true, false) as Button
	var panel: ClothesPanel = menu.get("clothes")
	assert_false(panel.visible, "closed at first")
	tshirt.pressed.emit()
	await wait_process_frames(1)
	assert_true(panel.visible, "the T-shirt opens the clothes menu")
	assert_eq(panel.tiles.size(), Cosmetics.SKINS.size(), "a tile per skin")
	assert_true((panel.tiles[&"bean"] as Button).button_pressed, "the worn skin is lit")
	(panel.tiles[&"wizard"] as Button).pressed.emit()
	assert_true((panel.tiles[&"wizard"] as Button).button_pressed)
	assert_false((panel.tiles[&"bean"] as Button).button_pressed, "one lit tile")
	assert_eq(str(Settings.get_value("profile", "skin")), "wizard", "saved in the profile")
	assert_eq(SceneRouter.profile_cosmetics()["skin"], &"wizard", "the next join sends it")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(Settings.PATH), OK)
	assert_eq(str(cfg.get_value("profile", "skin", "")), "wizard", "written to user://settings.cfg")
	panel.back_button.pressed.emit()
	assert_false(panel.visible, "BACK closes it")
	assert_true(tshirt.has_focus(), "focus back on the T-shirt")


func test_the_lobby_panel_has_no_skin_picker() -> void:
	var panel := LobbyPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	for l: Node in panel.find_children("*", "Label", true, false):
		assert_false((l as Label).text.contains("SKIN"), "no YOUR SKIN row: %s" % (l as Label).text)
	assert_false(panel.has_method("_cycle_skin"))
