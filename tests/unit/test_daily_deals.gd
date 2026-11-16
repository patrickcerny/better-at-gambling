extends GutTest
## DAILY DEALS (Patrick 2026-11-16: "Every day, rotate the featured skins for better prices"): new
## featured offers every UTC day, the same for everyone, only things the shop sells, and a featured
## Coin piece costs less while it is on deal: on the card, on the stage and when it is paid.

var shop: CosmeticShop = CosmeticShop.default()


func before_each() -> void:
	ProfileManager.reload()
	DailyDeals.off = false
	DailyDeals.fixed_day = -1


func after_each() -> void:
	DailyDeals.fixed_day = -1
	ProfileManager.reload()


func test_the_same_offers_all_day_new_ones_most_days() -> void:
	var a: Array[StringName] = DailyDeals.ids(shop, 20000)
	assert_eq(a, DailyDeals.ids(shop, 20000), "worked out from the day alone: everyone sees the same")
	assert_eq(a.size(), DailyDeals.COIN_DEALS + DailyDeals.GOLD_DEALS)
	var changed: int = 0
	for day: int in range(20001, 20031):
		if DailyDeals.ids(shop, day) != DailyDeals.ids(shop, day - 1):
			changed += 1
	assert_gt(changed, 25, "a new rotation (nearly) every day")


func test_only_what_the_shop_sells() -> void:
	for day: int in range(20000, 20120):
		var ids: Array[StringName] = DailyDeals.ids(shop, day)
		for i: int in ids.size():
			var d: CosmeticDef = shop.find(ids[i])
			if i < DailyDeals.COIN_DEALS:
				assert_true(d != null and DailyDeals.coin_offer(d), "%s: a Coin piece" % ids[i])
				assert_eq(d.level, 0, "never a level-pass piece")
			elif d != null:
				assert_true(d.premium() and not d.wheel_only and not d.dev_only and d.achievement == &"", "%s: a Gold piece" % ids[i])
			else:
				assert_not_null(shop.find_pack(ids[i]), "%s: a set" % ids[i])
		assert_eq(ids.size(), _unique(ids).size(), "no offer twice")


func test_a_coin_deal_costs_less_and_is_paid_that_way() -> void:
	var day: int = 20000
	DailyDeals.fixed_day = day
	var d: CosmeticDef = shop.find(DailyDeals.ids(shop, day)[0])
	var deal: int = DailyDeals.coin_price(shop, d)
	assert_eq(deal, DailyDeals.cut(d.price))
	assert_lt(deal, d.price, "%d%% off" % DailyDeals.PERCENT_OFF)
	assert_eq(DailyDeals.cut(1000), 700)
	assert_eq(DailyDeals.cut(149), 104, "Gold rounds to the Steam recipe's price")
	var p: PlayerProfile = ProfileManager.profile
	p.coins = deal
	assert_eq(ProfileManager.buy(d.id), &"", "the deal price is enough")
	assert_eq(p.coins, 0)
	# The day after it costs its normal price again (unless it's on deal again).
	var other: CosmeticDef = null
	for x: CosmeticDef in shop.items:
		if DailyDeals.coin_offer(x) and not DailyDeals.ids(shop, day).has(x.id) and not p.owns(x.id):
			other = x
			break
	assert_eq(DailyDeals.coin_price(shop, other), other.price, "not on deal: the normal price")
	p.coins = DailyDeals.cut(other.price)
	assert_eq(ProfileManager.buy(other.id), &"not_enough_coins")


func test_gold_offers_keep_their_price_until_steam_has_the_recipes() -> void:
	var day: int = 20000
	for id: StringName in DailyDeals.ids(shop, day).slice(DailyDeals.COIN_DEALS):
		var d: CosmeticDef = shop.find(id)
		var full: int = d.gold if d != null else shop.find_pack(id).gold
		var now: int = DailyDeals.gold_price(shop, d, day) if d != null else DailyDeals.pack_price(shop, shop.find_pack(id), day)
		assert_eq(now, DailyDeals.cut(full) if DailyDeals.GOLD_LIVE else full)


func test_the_shop_shows_the_deals() -> void:
	DailyDeals.fixed_day = 20000
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var panel := CosmeticsPanel.new()
	layer.add_child(panel)
	panel.open()
	await wait_process_frames(2)
	var ids: Array[StringName] = DailyDeals.ids(shop, 20000)
	assert_eq(panel.featured_row.get_child_count(), ids.size())
	var d: CosmeticDef = shop.find(ids[0])
	var card: Node = panel.featured_row.get_node("Featured_" + String(d.id))
	assert_string_contains((card.find_child("RibbonLabel", true, false) as Label).text, "DEAL -%d%%" % DailyDeals.PERCENT_OFF)
	assert_eq((card.find_child("Price", true, false) as Label).text, Hud._thousands(DailyDeals.cut(d.price)))
	assert_eq((card.find_child("WasPrice", true, false) as Label).text, Hud._thousands(d.price), "the old price, struck through")
	assert_string_contains(panel.featured_title.text, "DAILY DEALS")
	assert_string_contains(panel.featured_title.text, "NEW IN")
	panel.show_kind(d.kind)
	panel.select(d.id)
	assert_eq((panel.tiles[d.id].find_child("Price", true, false) as Label).text, Hud._thousands(DailyDeals.cut(d.price)), "the tile too")
	assert_string_contains(panel.item_kind.text, "DAILY DEAL")
	# The day turns: new cards.
	DailyDeals.fixed_day = 20001
	panel._refresh_places(ProfileManager.profile)
	await wait_process_frames(1)
	var names: Array[StringName] = []
	for c: Node in panel.featured_row.get_children():
		if not c.is_queued_for_deletion():
			names.append(StringName(String(c.name).trim_prefix("Featured_")))
	assert_eq(names, DailyDeals.ids(shop, 20001))


func test_time_left_text() -> void:
	assert_eq(DailyDeals.time_left_text(5 * 3600 + 12 * 60 + 9), "5H 12M")
	assert_eq(DailyDeals.time_left_text(30), "1M")
	assert_between(DailyDeals.seconds_left(), 0, 86400)


func _unique(a: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for x: StringName in a:
		if x not in out:
			out.append(x)
	return out
