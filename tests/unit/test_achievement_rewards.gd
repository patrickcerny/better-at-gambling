extends GutTest
## Achievement rewards (Patrick 2026-11-16: "Each achievement should also unlock something"): every
## achievement has its own piece with a model, none of them can be bought, levelled or won on the
## wheel, they are owned only once collected in the shop's COLLECT tab, which also lists reached
## level-pass pieces and Daily Spin wins, and all of that survives a save and load.

const PATH: String = "user://test_achievement_rewards.cfg"
## Achievements that live on other branches until they reach main.
const LATER: Array[StringName] = [&"ACH_LOGO_SPINNER"]


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _rewards() -> Array[CosmeticDef]:
	var out: Array[CosmeticDef] = []
	for d: CosmeticDef in CosmeticShop.default().items:
		if d.achievement != &"":
			out.append(d)
	return out


func _reward_for(ach: StringName) -> CosmeticDef:
	for d: CosmeticDef in _rewards():
		if d.achievement == ach:
			return d
	return null


func test_every_achievement_has_exactly_one_reward() -> void:
	for ach: StringName in Achievements.DEFS:
		var n: int = 0
		for d: CosmeticDef in _rewards():
			if d.achievement == ach:
				n += 1
		assert_eq(n, 1, "%s has one reward" % ach)
	for d: CosmeticDef in _rewards():
		assert_true(Achievements.DEFS.has(d.achievement) or d.achievement in LATER, "%s: %s is a real achievement" % [d.id, d.achievement])


func test_rewards_cannot_be_bought_levelled_or_spun() -> void:
	var p := PlayerProfile.new()
	p.coins = PlayerProfile.MAX_COINS
	p.xp = p.config.max_xp()
	p.sanitize()
	for d: CosmeticDef in _rewards():
		assert_false(d.coin_buyable(), d.id)
		assert_false(d.premium(), d.id)
		assert_false(d.is_free(), d.id)
		assert_eq(d.level, 0, d.id)
		assert_false(d.wheel_only, d.id)
		assert_false(p.owns(d.id), "%s is not owned at max level with max Coins" % d.id)
		assert_ne(p.buy(d.id), &"", "%s can't be bought" % d.id)
	for i: int in 50:
		var piece: StringName = DailyWheel.mystery_piece(p, float(i) / 50.0)
		var d: CosmeticDef = p.shop.find(piece)
		assert_true(d == null or d.achievement == &"", "the wheel never gives %s" % piece)


func test_every_outfit_reward_has_a_model() -> void:
	for d: CosmeticDef in _rewards():
		if d.kind in [CosmeticDef.KIND_COLOR, CosmeticDef.KIND_SKIN]:
			continue
		if d.kind == CosmeticDef.KIND_BOOTS:
			assert_false(OutfitMeshes.boot_meshes(d.id).is_empty(), d.id)
		elif d.kind == CosmeticDef.KIND_EYES:
			assert_true(OutfitMeshes.mesh(d.id) != null or OutfitMeshes.pupil_mesh(d.id) != null, d.id)
		elif d.kind == CosmeticDef.KIND_MOUTH:
			assert_true(OutfitMeshes.mesh(d.id) != null or OutfitMeshes.mouth_style(d.id) > 0, d.id)
		else:
			assert_not_null(OutfitMeshes.mesh(d.id), d.id)


func test_an_achieved_reward_waits_until_collected() -> void:
	var p := PlayerProfile.new()
	var d: CosmeticDef = _reward_for(&"ACH_HOLDEM_ROYAL_FLUSH")
	assert_not_null(d)
	assert_false(p.can_collect(d.id), "not achieved yet")
	assert_false(p.collect(d.id))
	assert_true(p.note_achieved([&"ACH_HOLDEM_ROYAL_FLUSH"]))
	assert_false(p.note_achieved([&"ACH_HOLDEM_ROYAL_FLUSH"]), "known already")
	assert_true(d.id in p.collectable())
	assert_false(p.owns(d.id), "owned only once collected")
	assert_true(p.collect(d.id))
	assert_true(p.owns(d.id))
	assert_false(d.id in p.collectable())
	assert_false(p.collect(d.id), "once")
	assert_true(p.wear(d.id))


func test_level_pieces_and_wheel_wins_show_up_to_collect() -> void:
	var p := PlayerProfile.new()
	var lv: CosmeticDef = null
	for d: CosmeticDef in p.shop.items:
		if d.level > 1 and d.achievement == &"" and (lv == null or d.level < lv.level):
			lv = d
	assert_not_null(lv)
	assert_false(p.can_collect(lv.id), "level not reached")
	p.xp = p.config.max_xp()
	p.sanitize()
	assert_true(p.can_collect(lv.id))
	assert_true(p.owns(lv.id), "level pieces stay owned from their level on")
	assert_true(p.collect(lv.id))
	assert_false(p.can_collect(lv.id))
	var piece: StringName = DailyWheel.mystery_piece(p, 0.5)
	var got: Dictionary = p.add_wheel_prize(DailyWheel.KIND_PIECE, 0, piece)
	assert_eq(got["piece"], piece)
	assert_true(p.can_collect(piece), "a Daily Spin piece waits in COLLECT")
	assert_true(p.owns(piece))
	assert_true(p.collect(piece))
	assert_false(p.can_collect(piece))


func test_rewards_survive_save_and_load() -> void:
	var p := PlayerProfile.new()
	var a: CosmeticDef = _reward_for(&"ACH_FIRST_MATCH")
	var b: CosmeticDef = _reward_for(&"ACH_JACKPOT")
	p.note_achieved([&"ACH_FIRST_MATCH", &"ACH_JACKPOT"])
	p.collect(a.id)
	if a.kind in CosmeticDef.OUTFIT_KINDS:
		p.wear(a.id)
	else:
		p.set_preferred_color(a.color_index)
	assert_eq(p.save(PATH), OK)
	var q := PlayerProfile.new()
	assert_eq(q.load_from(PATH), OK)
	assert_true(q.owns(a.id))
	assert_false(q.owns(b.id))
	assert_true(q.can_collect(b.id))
	assert_eq(q.collectable(), [b.id] as Array[StringName])


func test_an_old_profile_keeps_its_level_pieces_out_of_collect() -> void:
	var cfg := ConfigFile.new()
	var p := PlayerProfile.new()
	p.xp = p.config.max_xp()
	p.sanitize()
	p.to_config(cfg)
	cfg.erase_section("rewards")  # saved before the COLLECT tab existed
	var q := PlayerProfile.new()
	q.from_config(cfg)
	assert_eq(q.collectable(), [] as Array[StringName], "nothing old to collect")
	q.note_achieved([&"ACH_FIRST_MATCH"])
	assert_eq(q.collectable().size(), 1, "but earned achievements' rewards are there")
