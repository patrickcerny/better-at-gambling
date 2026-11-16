extends GutTest
## The Daily Spin (Patrick 2026-11-16): the wheel's odds and Steam items, the local roll and timer,
## the profile's payouts, the wheel's geometry and the Fortune skin.

const MakeItemdefs := preload("res://tools/steam/make_itemdefs.gd")


func before_each() -> void:
	ProfileManager.set_steam_owned([] as Array[StringName])
	ProfileManager.profile = PlayerProfile.new()


func after_each() -> void:
	ProfileManager.set_steam_owned([] as Array[StringName])
	ProfileManager.reload()


func test_weights_add_up_and_every_prize_has_its_own_steam_item() -> void:
	var total: int = 0
	var items: Array[int] = []
	for i: int in DailyWheel.count():
		var s: Dictionary = DailyWheel.segment(i)
		total += int(s["weight"])
		assert_gt(int(s["weight"]), 0)
		assert_false(int(s["steam_item"]) in items, "slice %d has its own item" % i)
		items.append(int(s["steam_item"]))
		assert_eq(DailyWheel.index_of_item(int(s["steam_item"])), i)
	assert_eq(total, DailyWheel.TOTAL_WEIGHT)
	assert_eq(DailyWheel.count(), 12)
	var skin: int = DailyWheel.index_of_item(CosmeticShop.default().find(DailyWheel.SKIN_ID).steam_item)
	assert_gte(skin, 0, "the Fortune skin is on the wheel")
	assert_lt(DailyWheel.chance(skin), 0.01, "and very rare")


func test_the_wheel_items_never_clash_with_the_shop() -> void:
	var shop: CosmeticShop = CosmeticShop.default()
	var used: Array[int] = [CoinPack.GOLD_ITEM]
	for d: CosmeticDef in shop.items:
		if d.steam_item > 0 and d.id != DailyWheel.SKIN_ID:
			used.append(d.steam_item)
	for k: CosmeticPack in shop.packs:
		used.append(k.steam_item)
	for c: CoinPack in shop.coin_packs:
		used.append(c.steam_item)
	assert_false(DailyWheel.GENERATOR in used)
	for i: int in DailyWheel.count():
		var token: int = int(DailyWheel.segment(i)["steam_item"])
		if DailyWheel.segment(i)["kind"] != DailyWheel.KIND_SKIN:
			assert_false(token in used, "token %d is new" % token)
		var bundle: int = DailyWheel.gold_bundle(token)
		if DailyWheel.segment(i)["kind"] == DailyWheel.KIND_GOLD:
			assert_gt(bundle, 0)
			assert_false(bundle in used)
		else:
			assert_eq(bundle, 0)


func test_itemdefs_hold_the_generator_tokens_and_gold_bundles() -> void:
	var items: Array = MakeItemdefs.itemdefs(CosmeticShop.default())["items"]
	var by_id: Dictionary = {}
	for it: Dictionary in items:
		by_id[int(it["itemdefid"])] = it
	var gen: Dictionary = by_id[DailyWheel.GENERATOR]
	assert_eq(gen["type"], "playtimegenerator")
	assert_eq(gen["bundle"], DailyWheel.generator_bundle())
	assert_eq(int(gen["drop_window"]), DailyWheel.COOLDOWN_MIN)
	assert_eq(int(gen["drop_max_per_window"]), 1, "one spin per window")
	assert_false(gen.has("price"), "a spin is never sold")
	for i: int in DailyWheel.count():
		var s: Dictionary = DailyWheel.segment(i)
		var token: Dictionary = by_id[int(s["steam_item"])]
		assert_false(token.has("price"))
		assert_false(bool(token["tradable"]))
		if s["kind"] == DailyWheel.KIND_GOLD:
			var b: Dictionary = by_id[DailyWheel.gold_bundle(int(s["steam_item"]))]
			assert_eq(b["bundle"], "%dx%d" % [CoinPack.GOLD_ITEM, int(s["amount"])])
			assert_eq(b["exchange"], "%dx1" % int(s["steam_item"]), "only the won token turns into Gold")
			assert_false(b.has("price"))
	var skin: Dictionary = by_id[CosmeticShop.default().find(DailyWheel.SKIN_ID).steam_item]
	assert_false(skin.has("exchange"), "the Fortune skin can't be bought with Gold")


func test_local_roll_never_gives_steam_prizes() -> void:
	var seen: Dictionary = {}
	for k: int in 2000:
		var i: int = DailyWheel.roll_local(float(k) / 2000.0)
		assert_false(DailyWheel.needs_steam(i), "slice %d needs Steam" % i)
		seen[i] = true
	for i: int in DailyWheel.count():
		if not DailyWheel.needs_steam(i):
			assert_true(seen.has(i), "slice %d can come up" % i)
	assert_false(DailyWheel.needs_steam(DailyWheel.roll_local(1.0)))
	assert_false(DailyWheel.needs_steam(DailyWheel.roll_local(-1.0)))


func test_timer_and_clock_turned_back() -> void:
	var t0: int = 1_800_000_000
	assert_eq(DailyWheel.wait_s(0, t0), 0, "never spun: spin now")
	assert_eq(DailyWheel.wait_s(t0, t0 + 60), DailyWheel.COOLDOWN_S - 60)
	assert_eq(DailyWheel.wait_s(t0, t0 + DailyWheel.COOLDOWN_S), 0)
	# Spun with the clock a day ahead, then set back: the wheel stays shut until the real time
	# has passed that spin by a full cooldown.
	var ahead: int = t0 + 86400
	assert_eq(DailyWheel.wait_s(ahead, t0), 86400 + DailyWheel.COOLDOWN_S)
	assert_eq(DailyWheel.wait_text(5 * 3600 + 12 * 60 + 3), "5 H 12 M")
	assert_eq(DailyWheel.wait_text(61), "2 M")
	assert_eq(DailyWheel.wait_text(40), "40 S")


func test_spin_local_pays_once_per_cooldown() -> void:
	var t0: int = 1_800_000_000
	var p: PlayerProfile = ProfileManager.profile
	var got: Dictionary = ProfileManager.spin_local(t0, 0.0)  # the first slice: 100 Coins
	assert_eq(int(got["index"]), 0)
	assert_eq(p.coins, 100)
	assert_eq(p.daily_last, t0)
	assert_eq(ProfileManager.spin_local(t0 + 3600, 0.0), {}, "one spin a day")
	assert_eq(p.coins, 100)
	assert_false(ProfileManager.spin_local(t0 + DailyWheel.COOLDOWN_S, 0.0).is_empty(), "the next day")
	assert_eq(p.coins, 200)


func test_mystery_piece_unlocks_an_unowned_normal_piece_or_pays_coins() -> void:
	var p: PlayerProfile = ProfileManager.profile
	var id: StringName = DailyWheel.mystery_piece(p, 0.5)
	assert_ne(id, &"")
	var d: CosmeticDef = p.shop.find(id)
	assert_true(d.coin_buyable())
	assert_false(p.owns(id))
	var got: Dictionary = p.add_wheel_prize(DailyWheel.KIND_PIECE, 1, id)
	assert_eq(got["piece"], id)
	assert_true(p.owns(id))
	# Already owned (or nothing left): Coins instead.
	got = p.add_wheel_prize(DailyWheel.KIND_PIECE, 1, id)
	assert_eq(got["piece"], &"")
	assert_eq(int(got["coins"]), DailyWheel.PIECE_FALLBACK_COINS)
	# Gold and the skin never land in the profile.
	assert_eq(int(p.add_wheel_prize(DailyWheel.KIND_GOLD, 50)["coins"]), 0)


func test_daily_spin_survives_save_and_load() -> void:
	var p := PlayerProfile.new()
	p.daily_last = 1_800_000_123
	var cfg := ConfigFile.new()
	p.to_config(cfg)
	var q := PlayerProfile.new()
	q.from_config(cfg)
	assert_eq(q.daily_last, 1_800_000_123)
	cfg.set_value("daily", "last_spin", "junk")
	q.from_config(cfg)
	assert_eq(q.daily_last, 0)


func test_fortune_skin_is_wheel_only() -> void:
	var p: PlayerProfile = ProfileManager.profile
	var d: CosmeticDef = p.shop.find(DailyWheel.SKIN_ID)
	assert_not_null(d)
	assert_eq(d.kind, CosmeticDef.KIND_SKIN)
	assert_true(d.wheel_only)
	assert_false(d.is_free())
	assert_false(d.coin_buyable())
	assert_false(d.premium())
	assert_false(p.owns(d.id))
	assert_ne(p.buy(d.id), &"", "never sold")
	assert_false(p.owns(d.id))
	ProfileManager.set_steam_owned(SteamSvc.owned_from_items([{"item_id": 9, "item_definition": d.steam_item, "quantity": 1}], p.shop))
	assert_true(p.owns(d.id), "owned once Steam has it")
	assert_true(ToonMaterial.SKIN_MODES.has(d.id), "it has its own look")


func test_wheel_geometry_lands_on_the_slice() -> void:
	for i: int in DailyWheel.count():
		for off: float in [-0.4, 0.0, 0.4]:
			assert_eq(DailyWheelView.index_at(DailyWheelView.angle_for(i, off)), i, "slice %d (offset %.1f)" % [i, off])


func test_wheel_view_stops_on_the_target() -> void:
	var w := DailyWheelView.new()
	add_child_autofree(w)
	w.rev()
	for k: int in 10:
		w._process(0.05)
	assert_true(w.busy())
	w.stop_at(7, 0.2)
	var landed: Array[int] = []
	w.landed.connect(func(i: int) -> void: landed.append(i))
	for k: int in 400:
		w._process(0.05)
	assert_eq(landed, [7] as Array[int])
	assert_eq(DailyWheelView.index_at(w.angle), 7)
	assert_false(w.busy())
