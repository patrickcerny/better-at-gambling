extends GutTest
## The six M10 items (Bouncer, Robin Hood, Jackpot Magnet, Wild Card, Butter Fingers, Bribe the
## Guard) and Sunglasses used before sitting down: what each does, its limits,
## and that money only moves between players or is paid/taken by the house with a logged reason.

var cfg: BalanceConfig = BalanceConfig.new()
var players: Dictionary[int, PlayerState] = {}
var eco: Economy
var mods: ModifierStack
var rules: InteractionRules
var world: WorldQuery
var pickups: PickupSystem
var sys: ItemSystem
var unseated: Array[int] = []
var now: float = 100.0


func before_each() -> void:
	players = {}
	unseated = []
	eco = Economy.new()
	mods = ModifierStack.new(cfg.luck_clamp)
	rules = InteractionRules.new(cfg)
	world = WorldQuery.new()
	pickups = PickupSystem.new(eco)
	for id: int in [1, 2, 3]:
		var p := PlayerState.new()
		p.id = id
		players[id] = p
		eco.add_player(id, 1000)
		world.set_transform(id, Vector3(id * 10.0, 0, 0), 0.0)
	sys = ItemSystem.new(Registry.items, cfg, players, eco, mods, rules, world, pickups, SeededRng.new(5))
	sys.interactions = InteractionResolver.new(rules, world, eco, pickups, SeededRng.new(3))
	sys.unseat = func(p: int) -> void: unseated.append(p)
	var rarities: Dictionary[StringName, int] = {}
	for id: StringName in Registry.items:
		if Registry.items[id].in_loot:
			rarities[id] = Registry.items[id].rarity
	sys.loot = LootTables.new(Registry.loot, rarities)
	now = 100.0


func _use(player: int, item: StringName, target: int = -1) -> Dictionary:
	sys.give(player, item, now)
	var r: Dictionary = sys.use(player, players[player].inventory.find(item), target, now)
	now += cfg.item_cooldown
	return r


func _events(type: StringName) -> Array[Dictionary]:
	return sys.events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _total() -> int:
	var t: int = 0
	for id: int in players:
		t += eco.balance(id)
	return t


func test_six_items_are_registered_in_the_loot_pool() -> void:
	for id: StringName in [&"bouncer", &"robin_hood", &"jackpot_magnet", &"wild_card", &"grease", &"bribe"]:
		assert_true(Registry.items.has(id), str(id))
		var def: ItemDefinition = Registry.items[id]
		assert_true(def.in_loot, str(id))
		assert_ne(def.description, "", str(id))
		assert_true(id in sys.loot.ids_of(def.rarity), "%s in its loot pool" % id)
	assert_eq(Registry.items[&"robin_hood"].rarity, ItemDefinition.Rarity.LEGENDARY)
	assert_eq(Registry.items[&"jackpot_magnet"].rarity, ItemDefinition.Rarity.LEGENDARY)


func test_bouncer_throws_a_seated_player_out_and_blocks_sitting() -> void:
	assert_eq(_use(1, &"bouncer", 2)["error"], &"not_seated", "standing players can't be bounced")
	rules.status(2).seated = true
	var r: Dictionary = _use(1, &"bouncer", 2)
	assert_true(r["ok"], str(r))
	assert_eq(unseated, [2] as Array[int], "stood up through the station")
	assert_false(rules.status(2).seated)
	assert_true(mods.has_flag(2, &"bounced"), "can't sit for a while")
	assert_true(rules.is_knocked_down(2, now - cfg.item_cooldown + 0.5))
	mods.expire(now + Registry.items[&"bouncer"].duration + 1.0)
	assert_false(mods.has_flag(2, &"bounced"), "12 s later the seats are open again")


func test_bouncer_is_blocked_by_a_bodyguard() -> void:
	rules.status(2).seated = true
	assert_true(_use(2, &"bodyguard")["ok"])
	assert_true(_use(1, &"bouncer", 2)["ok"])
	assert_eq(_events(&"item_used").back()["result"], &"blocked")
	assert_true(unseated.is_empty())


func test_robin_hood_takes_from_the_leader_and_splits_among_the_rest() -> void:
	eco.apply(3, 4000, &"test")  # 3 leads with $5000
	var before: int = _total()
	var r: Dictionary = _use(1, &"robin_hood")
	assert_true(r["ok"], str(r))
	var ev: Dictionary = _events(&"item_used").back()
	assert_eq(int(ev["target"]), 3, "always the leader")
	assert_eq(int(ev["amount"]), 400, "8% of $5000")
	assert_eq(eco.balance(3), 4600)
	assert_eq(eco.balance(1), 1200)
	assert_eq(eco.balance(2), 1200)
	assert_eq(_total(), before, "only moved between players")


func test_robin_hood_caps_at_800_and_refuses_the_leader() -> void:
	eco.apply(3, 19000, &"test")
	assert_true(_use(1, &"robin_hood")["ok"])
	assert_eq(eco.balance(3), 20000 - 800)
	assert_eq(_use(3, &"robin_hood")["error"], &"you_lead")
	assert_true(&"robin_hood" in players[3].inventory, "kept when refused")


func test_jackpot_magnet_pays_a_house_bonus_on_others_wins() -> void:
	assert_true(_use(1, &"jackpot_magnet")["ok"])
	var before2: int = eco.balance(2)
	sys.observe(GameEvents.round_result(&"blackjack_1", 2, 100, 300), now)
	assert_eq(eco.balance(1), 1020, "10% of the $200 profit")
	assert_eq(eco.balance(2), before2, "not taken from the winner")
	assert_eq(_events(&"magnet_bonus").size(), 1)
	sys.observe(GameEvents.round_result(&"blackjack_1", 1, 100, 300), now)
	sys.observe(GameEvents.round_result(&"blackjack_1", 3, 100, 0), now)
	assert_eq(eco.balance(1), 1020, "own wins and others' losses pay nothing")
	mods.expire(now + 31.0)
	sys.observe(GameEvents.round_result(&"blackjack_1", 2, 100, 300), now + 31.0)
	assert_eq(eco.balance(1), 1020, "over after 30 s")


func test_wild_card_becomes_another_item() -> void:
	for i: int in 6:
		players[1].inventory.clear()
		assert_true(_use(1, &"wild_card")["ok"])
		var got: StringName = StringName(_events(&"item_used").back()["won_item"])
		assert_ne(got, &"wild_card")
		assert_true(Registry.items.has(got), str(got))
		assert_eq(players[1].inventory, [got] as Array[StringName])


func test_grease_makes_the_target_drop_whoever_they_hold() -> void:
	world.set_transform(2, Vector3(30, 0, 0), 0.0)
	assert_eq(_use(1, &"grease", 2)["error"], &"out_of_range", "6 m reach")
	world.set_transform(2, Vector3(14, 0, 0), 0.0)
	sys.interactions.holding[2] = 3
	sys.interactions.held_by[3] = {"holder": 2, "since": now, "presses": 0}
	assert_true(_use(1, &"grease", 2)["ok"])
	sys.tick(now, true)
	assert_false(sys.interactions.is_holding(2), "slipped out of their hands")
	assert_eq(_events(&"grease_slipped").size(), 1)
	mods.expire(now + 21.0)
	sys.interactions.holding[2] = 3
	sys.interactions.held_by[3] = {"holder": 2, "since": now, "presses": 0}
	sys.tick(now + 21.0, true)
	assert_true(sys.interactions.is_holding(2), "dry again after 20 s")


func test_grease_doubles_the_next_shake_only() -> void:
	world.set_transform(2, Vector3(14, 0, 0), 0.0)
	assert_true(_use(1, &"grease", 2)["ok"])
	var before: int = _total() + _piles()
	sys.observe({"type": &"chips_shaken_out", "attacker": 3, "target": 2, "amount": 50}, now)
	assert_eq(eco.balance(2), 950, "50 more spilled")
	assert_eq(_events(&"grease_spill").size(), 1)
	sys.observe({"type": &"chips_shaken_out", "attacker": 3, "target": 2, "amount": 50}, now)
	assert_eq(eco.balance(2), 950, "only once")
	assert_eq(_total() + _piles(), before, "spilled chips lie on the floor")


func _piles() -> int:
	var t: int = 0
	for id: int in pickups.piles:
		t += int(pickups.piles[id]["amount"])
	return t


func test_bribe_hides_offences_from_the_guards() -> void:
	assert_true(_use(1, &"bribe")["ok"])
	sys.interactions.offences.append({"attacker": 1, "victim": 2, "time": now, "kind": &"shake"})
	sys.interactions.offences.append({"attacker": 3, "victim": 2, "time": now, "kind": &"shake"})
	sys.tick(now, true)
	assert_eq(sys.interactions.recent_offences(now).size(), 1, "only the unbribed one is left")
	assert_eq(int(sys.interactions.recent_offences(now)[0]["attacker"]), 3)
	mods.expire(now + 31.0)
	sys.interactions.offences.append({"attacker": 1, "victim": 2, "time": now + 31.0, "kind": &"shake"})
	sys.tick(now + 31.0, true)
	assert_eq(int(sys.interactions.recent_offences(now + 31.0)[0]["attacker"]), 1, "the bribe ran out")


func test_sunglasses_used_standing_still_peek_at_the_next_hand() -> void:
	# The effect sits on the player, not on a table: used before sitting it waits for the hand.
	assert_true(_use(1, &"sunglasses")["ok"])
	mods.expire(now + 120.0)
	assert_true(mods.has_flag(1, &"peek_dealer", &"blackjack"), "no clock on it")
	var bj := BlackjackLogic.new()
	bj.setup(&"blackjack_1", cfg, eco, mods, SeededRng.new(11))
	bj.join(1)
	assert_true(bj.place_bet(1, {"amount": 20}).get("ok", true))
	bj._deal()
	if bj.dealer_revealed:
		pass_test("dealer natural: the hole card is public anyway")
		return
	assert_eq(int(bj.get_private_state(1).get("hole_card", -1)), bj.dealer[1], "peeks the hole card")
	assert_false(bj.get_private_state(2).has("hole_card"), "nobody else does")
