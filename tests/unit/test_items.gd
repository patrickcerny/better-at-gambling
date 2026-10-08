extends GutTest
## Items (§2.8): every MVP item's effect and expiry, targets, cooldown, grace window, Bodyguard
## and Mirror, spawn/away protection, the discard flow and banana peels with money conservation.

var cfg: BalanceConfig = BalanceConfig.new()
var players: Dictionary[int, PlayerState] = {}
var eco: Economy
var mods: ModifierStack
var rules: InteractionRules
var world: WorldQuery
var pickups: PickupSystem
var sys: ItemSystem
var now: float = 100.0


func before_each() -> void:
	players = {}
	eco = Economy.new()
	mods = ModifierStack.new(cfg.luck_clamp)
	rules = InteractionRules.new(cfg)
	world = WorldQuery.new()
	pickups = PickupSystem.new(eco)
	for id: int in [1, 2, 3]:
		var p := PlayerState.new()
		p.id = id
		p.display_name = "P%d" % id
		players[id] = p
		eco.add_player(id, 1000)
		world.set_transform(id, Vector3(id * 10.0, 0, 0), 0.0)
	sys = ItemSystem.new(Registry.items, cfg, players, eco, mods, rules, world, pickups, SeededRng.new(4))
	now = 100.0


func _give(player: int, items: Array[StringName]) -> void:
	for it: StringName in items:
		sys.give(player, it, now)


func _use(player: int, slot: int = 0, target: int = -1) -> Dictionary:
	return sys.use(player, slot, target, now)


func _events(type: StringName) -> Array[Dictionary]:
	return sys.events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _near(a: int, b: int, d: float = 2.0) -> void:
	world.set_transform(b, world.get_position(a) + Vector3(d, 0, 0), 0.0)


# --- Self items --------------------------------------------------------------------------------

func test_lucky_clover_adds_luck_and_expires() -> void:
	_give(1, [&"lucky_clover"])
	assert_true(_use(1)["ok"])
	assert_eq(mods.get_luck(1), 2)
	assert_eq(players[1].inventory.size(), 0)
	mods.expire(now + 44.9)
	assert_eq(mods.get_luck(1), 2)
	mods.expire(now + 45.0)
	assert_eq(mods.get_luck(1), 0)
	assert_eq(_events(&"effect_ended")[0]["reason"], &"expired")


func test_luck_stacks_but_stays_clamped() -> void:
	_give(1, [&"lucky_clover", &"lucky_clover"])
	assert_true(_use(1)["ok"])
	now += cfg.item_cooldown
	assert_true(_use(1)["ok"])
	assert_eq(mods.get_luck(1), 3, "+4 clamped to +3")


func test_hot_hands_is_blackjack_only_three_hands_with_peek_and_segment_end() -> void:
	_give(1, [&"hot_hands", &"loaded_reels"])
	assert_true(_use(1)["ok"])
	assert_eq(mods.get_luck(1, &"blackjack"), 3)
	assert_eq(mods.get_luck(1, &"slots"), 0)
	assert_true(mods.has_flag(1, &"peek_dealer", &"blackjack"))
	for i: int in 2:
		mods.consume_round(1, &"blackjack")
	assert_eq(mods.get_luck(1, &"blackjack"), 3)
	mods.consume_round(1, &"blackjack")
	assert_eq(mods.get_luck(1, &"blackjack"), 0, "used up after 3 hands")
	now += cfg.item_cooldown
	assert_true(_use(1)["ok"])
	assert_eq(mods.get_luck(1, &"slots"), 3)
	sys.end_segment()
	assert_eq(mods.get_luck(1, &"slots"), 0, "Loaded Reels end with the segment")


func test_loaded_reels_last_eight_spins() -> void:
	_give(1, [&"loaded_reels"])
	_use(1)
	for i: int in 7:
		mods.consume_round(1, &"slots")
	assert_eq(mods.get_luck(1, &"slots"), 3)
	mods.consume_round(1, &"slots")
	assert_eq(mods.get_luck(1, &"slots"), 0)


func test_double_trouble_stacks_with_hot_table_and_last_call() -> void:
	_give(1, [&"double_down"])
	_use(1)
	var st := StationLogicBase.new()
	st.game_id = &"slots"
	st.setup(&"slot_1", cfg, eco, mods, SeededRng.new(1))
	st.hot_multiplier = 1.25
	st.global_multiplier = 1.5
	eco.apply(1, -100, &"bet_slots")
	# Stake 100 returns 300 (profit 200): 200 × 2 × 1.25 × 1.5 = 750 profit, rounded down once.
	assert_eq(st._settle(1, 100, 300), 850)
	assert_eq(eco.balance(1), 1750)
	assert_eq(mods.get_payout_multiplier(1, &"slots"), 1.0, "consumed by the first win")
	assert_eq(st._settle(1, 100, 300), 100 + int(floor(200 * 1.25 * 1.5)))


func test_double_trouble_expires_after_60s_unused() -> void:
	_give(1, [&"double_down"])
	_use(1)
	mods.expire(now + 60.0)
	assert_eq(mods.get_payout_multiplier(1, &"roulette"), 1.0)


func test_golden_chip_refunds_exactly_the_next_loss() -> void:
	_give(1, [&"golden_chip"])
	_use(1)
	var st := StationLogicBase.new()
	st.game_id = &"roulette"
	st.setup(&"roulette_1", cfg, eco, mods, SeededRng.new(1))
	eco.apply(1, -137, &"bet_roulette")
	assert_eq(st._settle(1, 137, 0), 137)
	assert_eq(eco.balance(1), 1000, "refund is exact")
	eco.apply(1, -50, &"bet_roulette")
	assert_eq(st._settle(1, 50, 0), 0, "only once")
	assert_eq(eco.balance(1), 950)


func test_spring_glove_three_uses() -> void:
	_give(1, [&"boxing_glove"])
	_use(1)
	for i: int in 3:
		assert_true(mods.has_flag(1, &"spring_glove", &"spring_glove"))
		mods.consume_round(1, &"spring_glove")
	assert_false(mods.has_flag(1, &"spring_glove", &"spring_glove"))
	var r: Dictionary = rules.shove(1, 2, now, false, true)
	assert_true(r["knockdown"], "glove shove knocks down at once")


# --- Targeted items ----------------------------------------------------------------------------

func test_black_cat_needs_a_target_when_several_and_jinxes() -> void:
	_give(1, [&"black_cat"])
	assert_eq(_use(1)["error"], &"need_target")
	assert_eq(_use(1, 0, 1)["error"], &"self_target")
	assert_eq(_use(1, 0, 9)["error"], &"bad_target")
	assert_true(_use(1, 0, 2)["ok"])
	assert_eq(mods.get_luck(2), -2)
	var used: Dictionary = _events(&"item_used")[0]
	assert_eq(used["target"], 2)
	assert_eq(used["result"], &"applied")


func test_auto_target_with_one_other_player() -> void:
	players.erase(3)
	_give(1, [&"black_cat"])
	assert_true(_use(1)["ok"])
	assert_eq(mods.get_luck(2), -2)


func test_pickpocket_range_amounts_and_never_negative() -> void:
	_give(1, [&"pickpocket", &"pickpocket", &"pickpocket"])
	assert_eq(_use(1, 0, 2)["error"], &"out_of_range")
	_near(1, 2, 3.9)
	rules.status(2).seated = true
	assert_true(_use(1, 0, 2)["ok"], "seated players can be robbed")
	assert_eq(eco.balance(1), 1120)
	assert_eq(eco.balance(2), 880)
	# Minimum: 12% of $200 is $24 → $50.
	eco.apply(2, -680, &"test")
	now += cfg.item_grace
	assert_true(_use(1, 0, 2)["ok"])
	assert_eq(eco.balance(2), 150)
	# Never more than they have.
	eco.apply(2, -120, &"test")
	now += cfg.item_grace
	assert_true(_use(1, 0, 2)["ok"])
	assert_eq(eco.balance(2), 0)
	assert_eq(PickpocketEffect.steal_amount(100000, 0.12, 50, 500), 500, "maximum")
	assert_eq(PickpocketEffect.steal_amount(0, 0.12, 50, 500), 0)


func test_pickpocket_on_a_broke_target_is_refused_and_kept() -> void:
	_near(1, 2)
	eco.apply(2, -1000, &"test")
	_give(1, [&"pickpocket"])
	assert_eq(_use(1, 0, 2)["error"], &"target_broke")
	assert_eq(players[1].inventory.size(), 1)


func test_target_away_or_protected_is_refused() -> void:
	_give(1, [&"black_cat"])
	rules.status(2).away = true
	assert_eq(_use(1, 0, 2)["error"], &"target_away")
	players[3].connected = false
	assert_eq(_use(1, 0, 3)["error"], &"target_away")
	rules.status(2).away = false
	rules.protect(2, now)
	assert_eq(_use(1, 0, 2)["error"], &"target_protected")
	now += cfg.spawn_protection
	assert_true(_use(1, 0, 2)["ok"])


func test_grace_window_and_cooldown() -> void:
	_give(1, [&"black_cat", &"black_cat", &"lucky_clover"])
	_give(3, [&"black_cat"])
	assert_true(_use(1, 0, 2)["ok"])
	assert_eq(_use(1, 1)["error"], &"cooldown")
	assert_eq(_use(3, 0, 2)["error"], &"grace", "one negative item per 5 s per target")
	now += cfg.item_grace
	assert_true(_use(3, 0, 2)["ok"])


func test_bodyguard_blocks_and_is_used_up() -> void:
	_give(2, [&"bodyguard"])
	_use(2)
	_give(1, [&"black_cat", &"black_cat"])
	assert_true(_use(1, 0, 2)["ok"])
	assert_eq(mods.get_luck(2), 0)
	assert_eq(_events(&"item_used")[1]["result"], &"blocked")
	assert_eq(players[1].inventory.size(), 1, "the blocked item is gone")
	now += cfg.item_grace
	assert_true(_use(1, 0, 2)["ok"])
	assert_eq(mods.get_luck(2), -2, "only the next one")


func test_mirror_reflects_onto_the_user() -> void:
	_give(2, [&"mirror"])
	_use(2)
	_near(1, 2)
	_give(1, [&"pickpocket"])
	assert_true(_use(1, 0, 2)["ok"])
	assert_eq(eco.balance(2), 1120, "the mirror's owner robs the thief")
	assert_eq(eco.balance(1), 880)
	assert_eq(_events(&"item_used")[1]["result"], &"reflected")
	assert_false(mods.has_flag(2, &"mirror"))


func test_mirror_before_bodyguard_and_bodyguard_absorbs_item_users_knockout() -> void:
	_give(2, [&"bodyguard", &"mirror"])
	_use(2)
	now += cfg.item_cooldown
	_use(2)
	_give(1, [&"black_cat"])
	_use(1, 0, 2)
	assert_eq(mods.get_luck(1), -2, "mirror goes first")
	assert_true(mods.has_flag(2, &"bodyguard"))
	assert_false(sys.shield_knockout(2, 3, now), "player 3 used no item")
	assert_true(sys.shield_knockout(2, 1, now + 10.0))
	assert_false(mods.has_flag(2, &"bodyguard"))


func test_effects_and_luck_in_private_state() -> void:
	_give(1, [&"lucky_clover", &"loaded_reels"])
	_use(1)
	now += cfg.item_cooldown
	_use(1)
	var priv: Dictionary = sys.private_state(1, now)
	assert_eq(priv["luck"], 2)
	assert_eq((priv["effects"] as Array).size(), 2)
	assert_almost_eq(float(priv["effects"][0]["left"]), 42.0, 0.11)
	assert_eq(priv["effects"][1]["uses"], 8)
	assert_eq(sys.public_effects()[1], [&"lucky_clover", &"loaded_reels"])


# --- Inventory & discard ------------------------------------------------------------------------

func test_full_inventory_asks_which_to_discard() -> void:
	_give(1, [&"lucky_clover", &"black_cat", &"mirror"])
	assert_false(sys.give(1, &"bodyguard", now))
	assert_eq(_events(&"discard_needed").size(), 1)
	assert_eq(sys.private_state(1, now)["discard"]["item"], &"bodyguard")
	assert_true(sys.discard(1, 1, now)["ok"])
	assert_eq(players[1].inventory, [&"lucky_clover", &"mirror", &"bodyguard"] as Array[StringName])
	assert_false(sys.private_state(1, now).has("discard"))


func test_discard_defaults_to_oldest_and_can_drop_the_newcomer() -> void:
	_give(1, [&"lucky_clover", &"black_cat", &"mirror"])
	sys.give(1, &"bodyguard", now)
	sys.give(1, &"golden_chip", now)
	sys.tick(now + cfg.discard_time - 0.1, false)
	assert_eq(players[1].inventory[0], &"lucky_clover")
	sys.tick(now + cfg.discard_time, false)
	assert_eq(players[1].inventory, [&"black_cat", &"mirror", &"bodyguard"] as Array[StringName])
	assert_eq(_events(&"discard_needed").size(), 2, "the second item asks next")
	assert_true(sys.discard(1, ItemSystem.DISCARD_INCOMING, now + 6.0)["ok"])
	assert_eq(players[1].inventory, [&"black_cat", &"mirror", &"bodyguard"] as Array[StringName])
	assert_eq(_events(&"item_discarded").back()["item"], &"golden_chip")


func test_using_an_item_lets_the_waiting_one_in() -> void:
	_give(1, [&"lucky_clover", &"black_cat", &"mirror"])
	sys.give(1, &"bodyguard", now)
	assert_true(_use(1)["ok"])
	assert_eq(players[1].inventory, [&"black_cat", &"mirror", &"bodyguard"] as Array[StringName])
	assert_true(sys.pending.is_empty())


func test_manual_discard_and_bad_slots() -> void:
	_give(1, [&"lucky_clover"])
	assert_eq(sys.discard(1, 2, now)["error"], &"bad_slot")
	assert_eq(_use(1, 1)["error"], &"bad_slot")
	assert_true(sys.discard(1, 0, now)["ok"])
	assert_eq(players[1].inventory.size(), 0)


# --- Banana peel --------------------------------------------------------------------------------

func test_banana_slip_drops_chips_stuns_and_conserves_money() -> void:
	_give(1, [&"banana_peel"])
	world.set_transform(1, Vector3(0, 0, 0), 0.0)
	assert_true(_use(1)["ok"])
	assert_eq(sys.peels.size(), 1)
	sys.tick(now + 1.0, true)
	assert_eq(sys.peels.size(), 1, "the owner doesn't slip on their own peel")
	world.set_transform(2, Vector3(0.5, 0, 0.2), 0.0)
	sys.tick(now + 2.0, true)
	assert_eq(sys.peels.size(), 0)
	var slip: Dictionary = _events(&"banana_slip")[0]
	assert_eq(slip["player"], 2)
	assert_eq(slip["amount"], 60, "6% of $1,000")
	assert_eq(eco.balance(2), 940)
	assert_eq(pickups.total_on_floor(), 60)
	assert_true(rules.is_knocked_down(2, now + 2.0 + cfg.banana_stun - 0.05))
	assert_false(rules.is_knocked_down(2, now + 2.0 + cfg.banana_stun + 0.05))
	# Conservation: collected + expired = dropped.
	var ids: Array = pickups.piles.keys()
	pickups.collect(3, int(ids[0]))
	pickups.tick(now + 100.0)
	var expired: int = 0
	var collected: int = 0
	for e: Dictionary in pickups.drain_events():
		if e["type"] == &"pickup_expired":
			expired += int(e["amount"])
		elif e["type"] == &"chips_collected":
			collected += int(e["amount"])
	assert_eq(collected + expired, 60)
	assert_eq(eco.balance(3), 1000 + collected)


func test_banana_amount_limits_and_protections() -> void:
	assert_eq(ItemSystem.slip_amount(100, 0.06, 20, 300), 20, "minimum")
	assert_eq(ItemSystem.slip_amount(100000, 0.06, 20, 300), 300, "maximum")
	assert_eq(ItemSystem.slip_amount(15, 0.06, 20, 300), 15, "never more than they have")
	_give(1, [&"banana_peel"])
	world.set_transform(1, Vector3(0, 0, 0), 0.0)
	_use(1)
	rules.status(2).seated = true
	world.set_transform(2, Vector3(0.1, 0, 0), 0.0)
	sys.tick(now + 1.0, true)
	assert_eq(sys.peels.size(), 1, "seated players don't step on peels")
	rules.status(2).seated = false
	world.airborne[2] = true
	sys.tick(now + 1.5, true)
	assert_eq(sys.peels.size(), 1, "jumping over it is fine")
	world.airborne[2] = false
	_give(2, [&"bodyguard"])
	sys.use(2, 0, -1, now + 1.6)
	sys.tick(now + 2.0, true)
	assert_eq(_events(&"banana_slip")[0]["result"], &"blocked")
	assert_eq(eco.balance(2), 1000)


func test_banana_reflected_by_mirror_and_expires() -> void:
	_give(1, [&"banana_peel", &"banana_peel"])
	world.set_transform(1, Vector3(0, 0, 0), 0.0)
	_use(1)
	_give(2, [&"mirror"])
	sys.use(2, 0, -1, now)
	world.set_transform(2, Vector3(0.2, 0, 0), 0.0)
	sys.tick(now + 0.5, true)
	var slip: Dictionary = _events(&"banana_slip")[0]
	assert_eq(slip["result"], &"reflected")
	assert_eq(slip["victim"], 1)
	assert_eq(eco.balance(1), 940)
	world.set_transform(1, Vector3(50, 0, 0), 0.0)
	sys.use(1, 0, -1, now + 10.0)
	sys.tick(now + 69.9, true)
	assert_eq(sys.peels.size(), 1)
	sys.tick(now + 70.0, true)
	assert_eq(sys.peels.size(), 0)
	assert_eq(_events(&"banana_removed").back()["reason"], &"expired")


func test_knocked_down_or_away_players_cannot_use_items() -> void:
	_give(1, [&"lucky_clover"])
	rules.status(1).knocked_down_until = now + 1.0
	assert_eq(_use(1)["error"], &"incapacitated")
	rules.status(1).knocked_down_until = -INF
	rules.status(1).away = true
	assert_eq(_use(1)["error"], &"incapacitated")
