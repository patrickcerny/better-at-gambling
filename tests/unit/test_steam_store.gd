extends GutTest
## Two currencies (Patrick 2026-11-15: "Goldcoins nur für echtgeld, red coins durch spielen", red for
## normal pieces, gold for premium): red Coins buy the normal pieces, Gold Coins (Steam items bought
## in gold packs) are exchanged for premium pieces and sets. The catalog's prices and Steam item
## definitions, the profile's rules, reading a Steam inventory, and the itemdefs file for Steamworks.

const MakeItemdefs := preload("res://tools/steam/make_itemdefs.gd")


func before_each() -> void:
	ProfileManager.set_steam_owned([] as Array[StringName])
	ProfileManager.reload()


func after_each() -> void:
	ProfileManager.set_steam_owned([] as Array[StringName])
	ProfileManager.reload()


func test_normal_pieces_cost_coins_premium_ones_gold() -> void:
	var shop: CosmeticShop = CosmeticShop.default()
	var defs: Array[int] = []
	var premium: int = 0
	for d: CosmeticDef in shop.items:
		if d.kind == CosmeticDef.KIND_COLOR:
			assert_false(d.premium(), "colours stay red Coins")
		if d.premium():
			premium += 1
			assert_false(d.coin_buyable(), "%s: premium has no red price" % d.id)
			assert_between(d.gold, 50, 200, "%s: 50 to 200 Gold" % d.id)
		else:
			assert_eq(d.gold, 0)
		if d.steam_item > 0:
			assert_false(d.steam_item in defs, "%s has its own item definition" % d.id)
			defs.append(d.steam_item)
	assert_between(premium, 5, 40, "some pieces are premium")
	for k: CosmeticPack in shop.packs:
		assert_gt(k.gold, 0, "%s costs Gold" % k.id)
		assert_false(k.steam_item in defs)
		defs.append(k.steam_item)
		assert_gt(k.pieces.size(), 2)
		for id: StringName in k.pieces:
			var d: CosmeticDef = shop.find(id)
			assert_not_null(d, "%s: %s exists" % [k.id, id])
			if d != null and not d.is_free():
				assert_gt(d.steam_item, 0, "%s: the set's bundle can grant %s" % [k.id, id])
	assert_eq(shop.packs.size(), 16)
	assert_null(shop.find_pack(&"pack_holiday"), "Holiday Mode is gone from the shop")
	for c: CoinPack in shop.coin_packs:
		assert_false(c.steam_item in defs, "%s has its own item definition" % c.id)
		defs.append(c.steam_item)
		assert_gt(c.gold, 0)
		assert_between(c.cents, 50, 1000)
	assert_false(1009 in defs, "Holiday Mode's Steam item is never reused")
	assert_false(CoinPack.GOLD_ITEM in defs, "the Gold Coin is its own item")


func test_premium_pieces_need_gold_not_coins() -> void:
	var p: PlayerProfile = ProfileManager.profile
	p.coins = 99999
	assert_eq(p.buy(&"hat_crown"), &"gold")
	assert_false(p.owns(&"hat_crown"))
	assert_eq(p.buy(&"hat_police"), &"", "a normal piece sells for Coins")
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


func test_gold_coins_in_the_inventory_pay_for_exchanges() -> void:
	var shop: CosmeticShop = CosmeticShop.default()
	var stacks: Array[Dictionary] = SteamSvc.gold_stacks([
		{"item_id": 7, "item_definition": CoinPack.GOLD_ITEM, "quantity": 60},
		{"item_id": 8, "item_definition": shop.find(&"hat_crown").steam_item, "quantity": 1},
		{"item_id": 9, "item_definition": CoinPack.GOLD_ITEM, "quantity": 0},
		{"item_id": 10, "item_definition": CoinPack.GOLD_ITEM, "quantity": 100}, "junk"])
	assert_eq(stacks, [{"item_id": 7, "quantity": 60}, {"item_id": 10, "quantity": 100}] as Array[Dictionary])
	var pay: Array = SteamSvc.gold_inputs(stacks, 75)
	assert_eq(pay[0], PackedInt64Array([7, 10]), "spends the first stack, then the next")
	assert_eq(pay[1], PackedInt32Array([60, 15]))
	assert_true(SteamSvc.gold_inputs(stacks, 161).is_empty(), "not enough Gold")
	assert_true(SteamSvc.gold_inputs(stacks, 0).is_empty())
	var ids: Array[StringName] = SteamSvc.owned_from_items([{"item_id": 7, "item_definition": CoinPack.GOLD_ITEM, "quantity": 5}, {"item_id": 1, "item_definition": shop.coin_packs[0].steam_item, "quantity": 1}], shop)
	assert_true(ids.is_empty(), "Gold Coins and gold packs are no cosmetics")


func test_the_itemdefs_file_for_steamworks_matches_the_shop() -> void:
	var want: Dictionary = MakeItemdefs.itemdefs(CosmeticShop.default())
	var text: String = FileAccess.get_file_as_string("res://tools/steam/itemdefs.json")
	assert_true(JSON.parse_string(text) is Dictionary, "itemdefs.json parses")
	assert_eq(text, JSON.stringify(want, "  ", false) + "\n", "run tools/steam/make_itemdefs.gd after changing the shop")
	var items: Array = want["items"]
	# Fixed EUR/USD prices since 2026-11-15 (Valve tiers left the admin item store empty).
	assert_true(items.filter(func(i: Dictionary) -> bool: return i.has("price_category")).is_empty(), "no Valve tiers")
	var priced: Array = items.filter(func(i: Dictionary) -> bool: return i.has("price"))
	assert_eq(priced.size(), CosmeticShop.default().coin_packs.size(), "only gold packs cost real money")
	for i: Dictionary in priced:
		assert_string_contains(str(i["bundle"]), "%dx" % CoinPack.GOLD_ITEM)
	var crown: CosmeticDef = CosmeticShop.default().find(&"hat_crown")
	var row: Dictionary = items.filter(func(i: Dictionary) -> bool: return int(i["itemdefid"]) == crown.steam_item)[0]
	assert_eq(row["exchange"], "%dx%d" % [CoinPack.GOLD_ITEM, crown.gold])
	assert_eq(MakeItemdefs.price_category(99), "1;VLV100", "0,99 € is the 1 dollar tier")
	assert_eq(MakeItemdefs.price_category(199), "1;VLV200")
	assert_eq(MakeItemdefs.price_category(499), "1;VLV500")


func test_the_shop_sells_premium_and_sets_for_gold() -> void:
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var panel := CosmeticsPanel.new()
	layer.add_child(panel)
	panel.open()
	assert_not_null(panel.find_child("PACKS", true, false), "a PACKS tab")
	panel.select(&"pack_royal")
	assert_eq(panel.preview.outfit.get(&"hat"), &"hat_crown", "the preview wears the whole set")
	assert_false(panel.steam_button.visible, "sets are not sold for money directly")
	assert_eq(panel.action_button.text, "GOLD NEEDS STEAM", "no Steam in tests")
	assert_true(panel.action_button.disabled)
	var crown: CosmeticDef = CosmeticShop.default().find(&"hat_crown")
	panel.select(&"hat_crown")
	assert_eq((panel.tiles[&"hat_crown"].find_child("Price", true, false) as Label).text, Hud._thousands(crown.gold))
	assert_true((panel.tiles[&"hat_crown"].find_child("PriceRow", true, false).get_child(1) as CoinIcon).gold, "a Gold Coin next to it")
	assert_true(panel.action_button.disabled)
	ProfileManager.profile.coins = 0
	panel.select(&"hat_police")
	assert_true(panel.action_button.disabled, "too few Coins: no buying")
	assert_string_contains(panel.action_button.text, "MORE COINS NEEDED")
	assert_false((panel.tiles[&"hat_police"].find_child("PriceRow", true, false).get_child(1) as CoinIcon).gold, "a red Coin")
	assert_ne((panel.tiles[&"hat_police"].find_child("Picture", true, false) as Control).modulate, Color.WHITE, "out of reach: greyed out")
	ProfileManager.profile.coins = 99999
	panel.select(&"hat_crown")
	panel.select(&"hat_police")
	assert_false(panel.action_button.disabled)
	assert_eq(panel.action_button.text, "BUY")
	assert_false(panel.steam_button.visible)
	ProfileManager.set_steam_owned(CosmeticShop.default().find_pack(&"pack_royal").pieces)
	panel.select(&"pack_royal")
	assert_eq(panel.action_button.text, "WEAR ALL")
	var worn: Array = []
	panel.outfit_worn.connect(func(kind: StringName, id: StringName) -> void: worn.append(id))
	panel.action_button.pressed.emit()
	assert_eq(worn.size(), 5)
	assert_true(ProfileManager.profile.is_worn(&"cape_royal"))
	panel.select(CosmeticShop.default().coin_packs[0].id)
	assert_true(panel.steam_button.visible, "gold packs are bought with Steam")


func test_level_walls_unlock_skins_and_colours() -> void:
	var p: PlayerProfile = ProfileManager.profile
	var gold: CosmeticDef = CosmeticShop.default().find(&"skin_gold")
	var rainbow: CosmeticDef = CosmeticShop.default().find(&"skin_rainbow")
	assert_eq(gold.level, 25)
	assert_eq(rainbow.level, 50)
	assert_true(gold.premium(), "or bought with Gold")
	p.level = 24
	p.coins = 99999
	assert_false(p.owns(&"skin_gold"))
	assert_eq(p.buy(&"skin_gold"), &"gold")
	p.level = 25
	assert_true(p.owns(&"skin_gold"), "level 25 unlocks gold")
	assert_false(p.owns(&"skin_rainbow"))
	p.level = 50
	assert_true(p.owns(&"skin_rainbow"), "level 50 unlocks the rainbow")
	assert_false(gold.is_free())
