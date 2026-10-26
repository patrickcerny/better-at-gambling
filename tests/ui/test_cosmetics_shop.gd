extends GutTest
## The cosmetics shop (Patrick: "There will be a shop for cosmetics ... You can set your preferred
## color in the cosmetic shop"): the main menu's COSMETICS entry and T-shirt open it, the profile
## line shows level, XP and Coins, a bought colour costs Coins (refused with a message when they
## don't reach), WEAR makes it the preferred colour, and the copy keeps Coins apart from the $
## played at the tables.

var menu: Control


func before_each() -> void:
	ProfileManager.reload()  # fresh, in memory under GUT


func after_each() -> void:
	ProfileManager.reload()


func _shop() -> CosmeticsPanel:
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var panel := CosmeticsPanel.new()
	layer.add_child(panel)
	return panel


func test_buy_refuse_and_wear() -> void:
	var panel: CosmeticsPanel = _shop()
	panel.open()
	assert_true(panel.visible)
	assert_eq(panel.tiles.size(), CosmeticShop.default().items.size(), "a tile per item")
	assert_eq(panel.selected, &"color_orange", "no preferred colour yet: the first item")
	assert_true(panel.find_child("COLOURS", true, false) != null, "a COLOURS tab")
	var price: Label = panel.tiles[&"color_mint"].find_child("Price", true, false) as Label
	var mint: CosmeticDef = CosmeticShop.default().find(&"color_mint")
	assert_eq(price.text, "%d COINS" % mint.price)
	assert_eq((panel.tiles[&"color_sky"].find_child("Price", true, false) as Label).text, "FREE")
	# Not enough Coins.
	ProfileManager.profile.coins = mint.price - 30
	panel.select(&"color_mint")
	assert_eq(panel.preview.color, Palette.player_color(mint.color_index), "the preview wears it")
	assert_string_contains(panel.action_button.text, "BUY")
	panel.action_button.pressed.emit()
	assert_string_contains(panel.status_label.text, "Not enough Coins")
	assert_string_contains(panel.status_label.text, "30 more")
	assert_false(ProfileManager.profile.owns(&"color_mint"))
	assert_eq(ProfileManager.profile.coins, mint.price - 30)
	# Enough.
	ProfileManager.profile.coins = mint.price + 5
	ProfileManager.changed.emit()
	assert_eq(panel.coins_label.text, "%d" % (mint.price + 5), "the wallet follows the profile")
	panel.action_button.pressed.emit()
	assert_true(ProfileManager.profile.owns(&"color_mint"))
	assert_eq(ProfileManager.profile.coins, 5)
	assert_eq(panel.coins_label.text, "5")
	assert_eq(price.text, "OWNED")
	assert_eq(panel.action_button.text, "WEAR")
	# Wear it.
	var worn: Array[int] = []
	panel.color_worn.connect(func(c: int) -> void: worn.append(c))
	panel.action_button.pressed.emit()
	assert_eq(ProfileManager.profile.preferred_color, mint.color_index)
	assert_eq(worn, [mint.color_index] as Array[int])
	assert_eq(price.text, "WEARING")
	assert_true(panel.action_button.disabled)
	assert_eq(SceneRouter.profile_cosmetics()["color"], mint.color_index, "the next join asks for it")
	# A free colour can be worn straight away.
	panel.select(&"color_blue")
	assert_eq(panel.action_button.text, "WEAR")
	panel.action_button.pressed.emit()
	assert_eq(ProfileManager.profile.preferred_color, 4)
	panel.close()
	assert_false(panel.visible)


func test_main_menu_opens_the_shop_and_shows_the_profile() -> void:
	ProfileManager.profile.apply_match("t", Progression.breakdown(ProfileManager.profile.config, 1, 2, 2000, 30))
	ProfileManager.changed.emit()
	menu = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
	add_child_autofree(menu)
	await wait_process_frames(2)
	var entry: Button = menu.find_child("Cosmetics", true, false) as Button
	assert_not_null(entry, "a COSMETICS entry")
	if entry == null:
		return
	assert_eq(entry.text, "COSMETICS")
	var badge: ProfileBadge = menu.get("profile_badge")
	assert_eq(badge.level_label.text, "LEVEL %d" % ProfileManager.profile.level)
	assert_gt(ProfileManager.profile.level, 1)
	assert_eq(badge.coins_label.text, "%d" % ProfileManager.profile.coins)
	assert_almost_eq(badge.xp_bar.value, ProfileManager.profile.level_progress(), 0.001)
	assert_string_contains(badge.xp_label.text, "XP")
	var shop: CosmeticsPanel = menu.get("cosmetics")
	entry.pressed.emit()
	assert_true(shop.visible, "COSMETICS opens the shop")
	shop.close()
	(menu.find_child("CosmeticsButton", true, false) as Button).pressed.emit()
	assert_true(shop.visible, "so does the T-shirt")
	shop.close()
	# Buying updates the corner line.
	ProfileManager.profile.coins = 1000
	ProfileManager.buy(&"color_gold")
	assert_eq(badge.coins_label.text, "%d" % ProfileManager.profile.coins)
	assert_lt(ProfileManager.profile.coins, 1000)


func test_the_copy_keeps_coins_and_table_money_apart() -> void:
	var panel: CosmeticsPanel = _shop()
	panel.open()
	var text: String = ""
	for l: Node in panel.find_children("*", "Label", true, false):
		text += (l as Label).text + "\n"
	assert_string_contains(text, "Coins")
	assert_string_contains(text, "$", "says the tables take $")
	assert_string_contains(text.to_lower(), "every match", "and that $ starts over")
