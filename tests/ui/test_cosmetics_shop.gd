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
	assert_eq(panel.tiles.size(), CosmeticShop.default().items.size() + CosmeticShop.default().packs.size() + CosmeticShop.default().coin_packs.size(), "a tile per item, per pack and per coin pack")
	assert_eq(panel.selected, &"color_orange", "no preferred colour yet: the first item")
	assert_true(panel.find_child("SKINS", true, false) != null, "one SKINS tab")
	var page: Node = panel.find_child("SKINS", true, false)
	assert_true(page.find_child("color_mint", true, false) != null and page.find_child("skin_lava", true, false) != null, "plain colours and animated skins on one page")
	assert_eq(panel.tab_buttons[CosmeticDef.KIND_COLOR], panel.tab_buttons[CosmeticDef.KIND_SKIN], "one tab button for both")
	var price: Label = panel.tiles[&"color_mint"].find_child("Price", true, false) as Label
	var mint: CosmeticDef = CosmeticShop.default().find(&"color_mint")
	assert_eq(price.text, Hud._thousands(mint.price), "the number, with a coin icon next to it")
	assert_eq((panel.tiles[&"color_sky"].find_child("Price", true, false) as Label).text, "FREE")
	# Not enough Coins.
	ProfileManager.profile.coins = mint.price - 30
	panel.select(&"color_mint")
	assert_eq(panel.preview.color, Palette.player_color(mint.color_index), "the preview wears it")
	assert_eq(panel.action_button.text, "30 MORE COINS NEEDED", "the button says what is missing")
	assert_true(panel.action_button.disabled)
	assert_false(ProfileManager.profile.owns(&"color_mint"))
	assert_eq(ProfileManager.profile.coins, mint.price - 30)
	# Enough.
	ProfileManager.profile.coins = mint.price + 5
	ProfileManager.changed.emit()
	assert_eq(panel.coins_label.text, "%d" % (mint.price + 5), "the wallet follows the profile")
	panel.action_button.pressed.emit()
	assert_not_null(panel.confirm_dialog, "buying asks first")
	assert_string_contains(panel.confirm_dialog.text_label.text, "can't be refunded")
	assert_false(ProfileManager.profile.owns(&"color_mint"), "nothing bought before the answer")
	panel.confirm_dialog.cancel()
	assert_false(ProfileManager.profile.owns(&"color_mint"), "CANCEL buys nothing")
	assert_eq(ProfileManager.profile.coins, mint.price + 5)
	assert_eq(panel.selected, &"color_mint", "still picked after CANCEL")
	panel.action_button.pressed.emit()
	panel.confirm_dialog.confirm()
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
	assert_eq(entry.text, "SHOP")
	var badge: ProfileBadge = menu.get("profile_badge")
	assert_eq(badge.level_label.text, "LEVEL %d" % ProfileManager.profile.level)
	assert_gt(ProfileManager.profile.level, 1)
	assert_eq(badge.coins_label.text, "%d" % ProfileManager.profile.coins)
	assert_almost_eq(badge.xp_bar.value, ProfileManager.profile.level_progress(), 0.001)
	assert_string_contains(badge.xp_label.text, "XP")
	var shop: CosmeticsPanel = menu.get("cosmetics")
	entry.pressed.emit()
	assert_true(shop.visible, "SHOP opens the shop")
	assert_false(shop.inventory)
	assert_true(shop.tiles[&"color_mint"].visible, "the shop shows what you don't own")
	shop.close()
	(menu.find_child("CosmeticsButton", true, false) as Button).pressed.emit()
	assert_true(shop.visible and shop.inventory, "the T-shirt opens your inventory")
	assert_false(shop.tiles[&"color_mint"].visible, "the inventory only shows what you own")
	assert_true(shop.tiles[&"color_sky"].visible, "free things are yours")
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


func test_the_shop_fits_a_1080_high_screen_whatever_is_picked() -> void:
	# Patrick 2026-11-14: "now the menu is bigger than the screen". The project scales a
	# 1920x1080 canvas (aspect "expand"), so 1080 is the least height a screen gives.
	var screen := SubViewport.new()
	screen.size = Vector2i(1920, 1080)
	add_child_autofree(screen)
	var panel := CosmeticsPanel.new()
	screen.add_child(panel)
	panel.open()
	for id: StringName in [&"color_orange", &"hat_police", &"hat_crown", &"pack_royal"]:
		panel.select(id)
		await wait_process_frames(2)
		var need: float = panel.get_combined_minimum_size().y + panel.offset_top - panel.offset_bottom
		assert_lte(need, 1080.0, "%s: the shop fits (needs %d px)" % [id, need])


## Patrick 2026-11-15: picks stack across the tabs (a skin and a hat together), clicking a picked
## tile again takes it off, and BUY ALL pays for the tried-on look at once.
func test_try_ons_stack_and_come_off() -> void:
	var panel: CosmeticsPanel = _shop()
	panel.open()
	var shop: CosmeticShop = CosmeticShop.default()
	var hat: CosmeticDef = null
	var shirt: CosmeticDef = null
	for d: CosmeticDef in shop.items:
		if d.coin_buyable() and not d.is_free() and d.level == 0:
			if hat == null and d.kind == CosmeticDef.KIND_HAT:
				hat = d
			elif shirt == null and d.kind == CosmeticDef.KIND_SHIRT:
				shirt = d
	panel._on_tile_pressed(hat.id)
	panel._on_tile_pressed(shirt.id)
	assert_eq(panel.preview.outfit.get(CosmeticDef.KIND_HAT, &""), hat.id, "the hat stays on")
	assert_eq(panel.preview.outfit.get(CosmeticDef.KIND_SHIRT, &""), shirt.id)
	assert_true(panel.tiles[hat.id].button_pressed, "both tiles show as picked")
	assert_true(panel.look_label.get_parent().visible, "the look row shows")
	assert_eq(panel.look_price(), hat.price + shirt.price)
	assert_eq(panel.look_button.text, "BUY ALL · %s" % Hud._thousands(hat.price + shirt.price))
	# Clicking the picked shirt again takes it off.
	panel._on_tile_pressed(shirt.id)
	assert_eq(panel.selected, &"")
	assert_false(panel.preview.outfit.has(CosmeticDef.KIND_SHIRT), "the shirt is off")
	assert_eq(panel.preview.outfit.get(CosmeticDef.KIND_HAT, &""), hat.id, "the hat still on")
	panel._on_tile_pressed(shirt.id)
	ProfileManager.profile.coins = hat.price + shirt.price
	panel.look_button.pressed.emit()
	assert_false(ProfileManager.profile.owns(hat.id), "BUY ALL asks first")
	assert_string_contains(panel.confirm_dialog.text_label.text, hat.display_name, "lists what is bought")
	assert_string_contains(panel.confirm_dialog.text_label.text, shirt.display_name)
	assert_string_contains(panel.confirm_dialog.text_label.text, "can't be refunded")
	panel.confirm_dialog.confirm()
	assert_true(ProfileManager.profile.owns(hat.id) and ProfileManager.profile.owns(shirt.id), "bought both")
	assert_eq(ProfileManager.profile.coins, 0)
	assert_eq(panel.look_button.text, "WEAR ALL")
	panel.look_button.pressed.emit()
	assert_true(ProfileManager.profile.is_worn(hat.id) and ProfileManager.profile.is_worn(shirt.id))
	panel.reset_look()
	assert_true(panel.trying.is_empty())
	panel.close()


func test_colour_and_skin_page_has_one_pick_and_names_the_player_colour() -> void:
	# Patrick 2026-11-16: BLUE and THE HOUSE both looked picked, BLUE said WEARING under a skin.
	var p: PlayerProfile = ProfileManager.profile
	p.owned.append(&"skin_lava")
	ProfileManager.set_preferred_color(4)  # Blue
	assert_true(ProfileManager.wear(&"skin_lava"))
	var panel: CosmeticsPanel = _shop()
	panel.open(true)
	panel._on_tile_pressed(&"color_blue")
	panel._on_tile_pressed(&"skin_lava")
	panel._on_tile_pressed(&"color_blue")  # back to the colour that was tried on before
	assert_true(panel.tiles[&"color_blue"].button_pressed)
	assert_false(panel.tiles[&"skin_lava"].button_pressed, "only one tile on the page is picked")
	assert_false(panel.preview.outfit.has(CosmeticDef.KIND_SKIN), "the preview shows the plain colour")
	assert_eq(panel.action_button.text, "WEAR", "a skin covers it: wearing Blue takes the skin off")
	assert_eq((panel.tiles[&"color_blue"].find_child("Price", true, false) as Label).text, "PLAYER COLOUR", "pedestals and scoreboards still show it")
	panel._on_tile_pressed(&"skin_lava")
	assert_false(panel.tiles[&"color_blue"].button_pressed, "picking the skin drops the colour try-on")
	panel.close()


func test_the_colour_flow_is_consistent_under_a_skin() -> void:
	var p: PlayerProfile = ProfileManager.profile
	p.owned.append(&"skin_lava")
	ProfileManager.set_preferred_color(4)  # Blue
	assert_true(ProfileManager.wear(&"skin_lava"))
	var panel: CosmeticsPanel = _shop()
	panel.open(true)
	assert_eq(panel.selected, &"skin_lava", "opens on what the bean shows: the skin, not the hidden colour")
	assert_eq(panel.preview.outfit.get(CosmeticDef.KIND_SKIN, &""), &"skin_lava")
	assert_eq(panel.item_kind.text, "ANIMATED SKIN")
	panel._on_tile_pressed(&"color_blue")
	assert_eq(panel.item_kind.text, "COLOUR")
	panel._on_tile_pressed(&"color_blue")
	assert_eq(panel.selected, &"color_blue", "a second click keeps the colour picked")
	panel.action_button.pressed.emit()
	assert_eq(p.outfit.get(CosmeticDef.KIND_SKIN, &""), &"", "wearing a colour takes the skin off")
	assert_eq(p.preferred_color, 4)
	assert_eq(panel.action_button.text, "WEARING")
	assert_string_contains(panel.status_label.text, "from now on")
	panel.next_match_look = true
	panel.select(&"skin_lava")
	panel.action_button.pressed.emit()
	assert_string_contains(panel.status_label.text, "from your next match", "in a lobby it says when it shows")
	panel.close()


func test_too_few_gold_coins_opens_the_gold_tab() -> void:
	var panel: CosmeticsPanel = _shop()
	panel.open()
	var packs: Array[CoinPack] = CosmeticShop.default().coin_packs
	assert_false(packs.is_empty(), "gold packs to sell")
	var smallest: CoinPack = packs[0]
	for c: CoinPack in packs:
		if c.gold < smallest.gold:
			smallest = c
	panel.open_gold_shop(1)
	assert_eq(panel.selected, smallest.id, "the smallest pack that covers it is picked")
	assert_eq(panel.tabs.current_tab, int(panel.tab_buttons[CosmeticsPanel.KIND_COINS].get_meta(&"tab")), "on the GOLD tab")
	assert_true(panel.steam_button.visible, "ready to buy with Steam")
	panel.close()


## Achievement rewards (Patrick 2026-11-16): locked in the shop with the achievement named, then
## waiting in COLLECT (with the red dot) once the achievement is held; collecting owns it.
func test_achievement_rewards_are_collected() -> void:
	var panel: CosmeticsPanel = _shop()
	panel.open()
	panel.select(&"hat_card_house")
	assert_eq(panel.action_button.text, "ACHIEVEMENT REWARD")
	assert_true(panel.action_button.disabled, "can't be bought")
	assert_string_contains(panel.status_label.text, "Five Card Trick")
	assert_eq((panel.tiles[&"hat_card_house"].find_child("Price", true, false) as Label).text, "ACHIEVEMENT")
	assert_eq(panel.collect_tiles.size(), 0)
	assert_false(panel.collect_dot.visible)
	ProfileManager.note_achieved([&"ACH_BJ_FIVE_CARDS", &"ACH_JACKPOT"])
	assert_eq(panel.collect_tiles.size(), 2, "both wait in COLLECT")
	assert_eq(panel.collect_dot.count, 2)
	assert_eq(panel.action_button.text, "COLLECT")
	panel.select(&"shirt_tux")
	panel.collect_tiles[&"hat_card_house"].pressed.emit()
	assert_eq(panel.trying, {CosmeticDef.KIND_HAT: &"hat_card_house"} as Dictionary[StringName, StringName], "only the collected piece is tried on")
	assert_true(ProfileManager.profile.owns(&"hat_card_house"))
	assert_eq(panel.collect_tiles.size(), 1)
	assert_eq(panel.action_button.text, "WEAR", "collected: it can be worn")
	panel.collect_all_button.pressed.emit()
	assert_true(panel.trying.is_empty(), "COLLECT ALL leaves the bean as worn")
	assert_true(ProfileManager.profile.owns(&"hat_beacon"))
	assert_eq(panel.collect_tiles.size(), 0)
	assert_false(panel.collect_dot.visible)
