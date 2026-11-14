extends GutTest
## Real-money cosmetics through Steam (Patrick 2026-11-14: pieces 0,50 to 1 euro, some only for
## money, full packs 50 cents cheaper than everything single): the catalog's prices and Steam item
## definitions, the profile's rules, reading a Steam inventory, and the itemdefs file for Steamworks.

const MakeItemdefs := preload("res://tools/steam/make_itemdefs.gd")


func before_each() -> void:
	ProfileManager.set_steam_owned([] as Array[StringName])
	ProfileManager.reload()


func after_each() -> void:
	ProfileManager.set_steam_owned([] as Array[StringName])
	ProfileManager.reload()


func test_every_paid_piece_costs_50_cents_to_a_euro_and_has_its_own_steam_item() -> void:
	var shop: CosmeticShop = CosmeticShop.default()
	var defs: Array[int] = []
	var money_only: int = 0
	for d: CosmeticDef in shop.items:
		if d.kind == CosmeticDef.KIND_COLOR:
			assert_false(d.steam_buyable(), "colours stay Coins only")
			continue
		if d.is_free():
			assert_false(d.steam_buyable(), "%s is free" % d.id)
			continue
		assert_true(d.steam_buyable(), "%s is for sale on Steam" % d.id)
		if d.kind == CosmeticDef.KIND_SKIN:
			assert_between(d.cents, 100, 200, "%s: animated skins are the pricier tier" % d.id)
			assert_true(d.money_only, "%s: skins are for money (or a level)" % d.id)
		else:
			assert_between(d.cents, 50, 100, "%s costs 0,50 to 1 euro" % d.id)
		assert_false(d.steam_item in defs, "%s has its own item definition" % d.id)
		defs.append(d.steam_item)
		if d.money_only:
			money_only += 1
			assert_false(d.coin_buyable())
	assert_between(money_only, 5, 40, "some pieces are only sold for money")
	for k: CosmeticPack in shop.packs:
		assert_eq(k.cents, shop.pieces_cents(k) - CosmeticPack.DISCOUNT_CENTS, "%s is 50 cents under its pieces" % k.id)
		assert_false(k.steam_item in defs)
		defs.append(k.steam_item)
		assert_gt(k.pieces.size(), 2)
		for id: StringName in k.pieces:
			assert_not_null(shop.find(id), "%s: %s exists" % [k.id, id])
	assert_eq(shop.packs.size(), 16)
	var holiday: CosmeticPack = shop.find_pack(&"pack_holiday")
	assert_null(holiday, "Holiday Mode is gone from the shop")
	for c: CoinPack in shop.coin_packs:
		assert_false(c.steam_item in defs, "%s has its own item definition" % c.id)
		defs.append(c.steam_item)
		assert_gt(c.coins, 0)
		assert_between(c.cents, 50, 1000)
	assert_false(1009 in defs, "Holiday Mode's Steam item is never reused")


func test_money_only_pieces_come_from_steam_not_coins() -> void:
	var p: PlayerProfile = ProfileManager.profile
	p.coins = 99999
	assert_eq(p.buy(&"hat_crown"), &"steam_only")
	assert_false(p.owns(&"hat_crown"))
	assert_eq(p.buy(&"hat_police"), &"", "a Coins piece still sells for Coins")
	ProfileManager.set_steam_owned([&"hat_crown", &"cape_royal"] as Array[StringName])
	p = ProfileManager.profile
	assert_true(p.owns(&"hat_crown"))
	assert_true(ProfileManager.wear(&"hat_crown"))
	assert_eq(p.outfit_wire()[0], "hat_crown")
	ProfileManager.reload()
	assert_true(ProfileManager.profile.owns(&"cape_royal"), "the Steam inventory outlives a reload")
	# The inventory not (yet) holding it: the piece stays in the saved outfit but is not shown.
	ProfileManager.set_steam_owned([] as Array[StringName])
	p = ProfileManager.profile
	p.outfit[&"hat"] = &"hat_crown"
	p.sanitize()
	assert_eq(p.outfit.get(&"hat"), &"hat_crown", "kept while the inventory loads")
	assert_eq(p.outfit_wire()[0], "", "but nobody sees it")
	assert_false(p.is_worn(&"hat_crown"))
	var pack: CosmeticPack = CosmeticShop.default().find_pack(&"pack_police")
	assert_false(p.owns_pack(pack))


func test_a_steam_inventory_listing_becomes_owned_pieces() -> void:
	var shop: CosmeticShop = CosmeticShop.default()
	var crown: CosmeticDef = shop.find(&"hat_crown")
	var pack: CosmeticPack = shop.find_pack(&"pack_chef")
	var ids: Array[StringName] = SteamSvc.owned_from_items([
		{"item_id": 1, "item_definition": crown.steam_item, "quantity": 1},
		{"item_id": 2, "item_definition": pack.steam_item, "quantity": 1},
		{"item_id": 3, "item_definition": 999999, "quantity": 1}, "junk"], shop)
	assert_true(&"hat_crown" in ids)
	for id: StringName in pack.pieces:
		assert_true(id in ids, "the pack brings %s" % id)
	assert_eq(ids.size(), 1 + pack.pieces.size())
	assert_eq(SteamSvc.format_price(75, "EUR"), "0,75 €")
	assert_eq(SteamSvc.format_price(150, "USD"), "$1.50")
	assert_eq(SteamSvc.format_price(99, "GBP"), "£0.99")


func test_the_itemdefs_file_for_steamworks_matches_the_shop() -> void:
	var want: Dictionary = MakeItemdefs.itemdefs(CosmeticShop.default())
	var text: String = FileAccess.get_file_as_string("res://tools/steam/itemdefs.json")
	assert_true(JSON.parse_string(text) is Dictionary, "itemdefs.json parses")
	assert_eq(text, JSON.stringify(want, "  ", false) + "\n", "run tools/steam/make_itemdefs.gd after changing the shop")
	var bundle: Dictionary = (want["items"] as Array).filter(func(i: Dictionary) -> bool: return i["type"] == "bundle")[0]
	assert_string_contains(str(bundle["bundle"]), "x1")
	assert_eq(MakeItemdefs.price(75), "1;EUR75,USD75")


func test_the_shop_sells_packs_and_money_only_pieces_through_steam() -> void:
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var panel := CosmeticsPanel.new()
	layer.add_child(panel)
	panel.open()
	assert_not_null(panel.find_child("PACKS", true, false), "a PACKS tab")
	panel.select(&"pack_royal")
	assert_eq(panel.preview.outfit.get(&"hat"), &"hat_crown", "the preview wears the whole pack")
	assert_true(panel.steam_button.visible)
	assert_true(panel.steam_button.disabled, "no Steam in tests: greyed out")
	assert_string_contains(panel.steam_button.text, SteamSvc.format_price(CosmeticShop.default().find_pack(&"pack_royal").cents, "EUR"))
	assert_false(panel.action_button.visible, "nothing to wear yet")
	panel.select(&"hat_crown")
	assert_false(panel.action_button.visible, "no Coins price for the crown")
	assert_eq((panel.tiles[&"hat_crown"].find_child("Price", true, false) as Label).text, "1,00 €")
	panel.select(&"hat_police")
	assert_true(panel.action_button.visible)
	assert_eq(panel.action_button.text, "BUY FOR COINS")
	assert_true(panel.steam_button.visible, "or with Steam")
	ProfileManager.set_steam_owned(CosmeticShop.default().find_pack(&"pack_royal").pieces)
	panel.select(&"pack_royal")
	assert_eq(panel.action_button.text, "WEAR ALL")
	assert_false(panel.steam_button.visible)
	var worn: Array = []
	panel.outfit_worn.connect(func(kind: StringName, id: StringName) -> void: worn.append(id))
	panel.action_button.pressed.emit()
	assert_eq(worn.size(), 5)
	assert_true(ProfileManager.profile.is_worn(&"cape_royal"))


func test_coin_packs_bought_on_steam_become_coins() -> void:
	var shop: CosmeticShop = CosmeticShop.default()
	assert_eq(shop.coin_packs.size(), 3)
	var small: CoinPack = shop.coin_packs[0]
	var stacks: Array[Dictionary] = SteamSvc.coin_stacks([
		{"item_id": 7, "item_definition": small.steam_item, "quantity": 2},
		{"item_id": 8, "item_definition": shop.find(&"hat_crown").steam_item, "quantity": 1},
		{"item_id": 9, "item_definition": small.steam_item, "quantity": 0}, "junk"], shop)
	assert_eq(stacks.size(), 1, "only coin packs are used up, and only real stacks")
	assert_eq(stacks[0], {"item_id": 7, "quantity": 2, "coins": small.coins * 2})
	assert_eq(shop.by_steam_item(small.steam_item), small)
	var ids: Array[StringName] = SteamSvc.owned_from_items([{"item_id": 7, "item_definition": small.steam_item, "quantity": 1}], shop)
	assert_true(ids.is_empty(), "a coin pack is no cosmetic")
	var p: PlayerProfile = ProfileManager.profile
	p.coins = 100
	assert_eq(ProfileManager.add_coins(small.coins), small.coins)
	assert_eq(ProfileManager.profile.coins, 100 + small.coins)
	assert_eq(ProfileManager.add_coins(-50), 0, "nothing is taken away")


func test_level_walls_unlock_skins_and_colours() -> void:
	var p: PlayerProfile = ProfileManager.profile
	var gold: CosmeticDef = CosmeticShop.default().find(&"skin_gold")
	var rainbow: CosmeticDef = CosmeticShop.default().find(&"skin_rainbow")
	assert_eq(gold.level, 25)
	assert_eq(rainbow.level, 50)
	assert_true(gold.steam_buyable(), "or bought with money")
	p.level = 24
	p.coins = 99999
	assert_false(p.owns(&"skin_gold"))
	assert_eq(p.buy(&"skin_gold"), &"steam_only")
	p.level = 25
	assert_true(p.owns(&"skin_gold"), "level 25 unlocks gold")
	assert_false(p.owns(&"skin_rainbow"))
	p.level = 50
	assert_true(p.owns(&"skin_rainbow"), "level 50 unlocks the rainbow")
	assert_false(gold.is_free())
