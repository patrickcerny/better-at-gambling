extends GutTest
## Patrick's extra items (docs/ITEM_IDEAS.md): what each does, its limits, and that money is only
## moved (or paid/taken by the house with a logged reason), never lost.

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
		players[id] = p
		eco.add_player(id, 1000)
		world.set_transform(id, Vector3(id * 10.0, 0, 0), 0.0)
	sys = ItemSystem.new(Registry.items, cfg, players, eco, mods, rules, world, pickups, SeededRng.new(9))
	sys.interactions = InteractionResolver.new(rules, world, eco, pickups, SeededRng.new(3))
	var rarities: Dictionary[StringName, int] = {}
	for id: StringName in Registry.items:
		if Registry.items[id].in_loot:
			rarities[id] = Registry.items[id].rarity
	sys.loot = LootTables.new(Registry.loot, rarities)
	sys.jackpot = ProgressiveJackpot.new(0.01, 500)
	now = 100.0


func _give(player: int, items: Array[StringName]) -> void:
	for it: StringName in items:
		sys.give(player, it, now)


func _use(player: int, target: int = -1, options: Dictionary = {}) -> Dictionary:
	var r: Dictionary = sys.use(player, 0, target, now, options)
	now += cfg.item_cooldown
	return r


func _events(type: StringName) -> Array[Dictionary]:
	return sys.events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _near(a: int, b: int, d: float = 1.5) -> void:
	world.set_transform(b, world.get_position(a) + Vector3(d, 0, 0), 0.0)


func _total() -> int:
	var t: int = 0
	for id: int in players:
		t += eco.balance(id)
	return t


func test_every_new_item_is_registered_with_an_effect() -> void:
	for id: StringName in [&"sunglasses", &"bad_luck_monkey", &"vip_pass", &"scratch_ticket", &"energy_drink", &"baseball_bat", &"empty_bottle", &"credit_card", &"dog_collar", &"fake_cash", &"scissors", &"beer", &"russian_roulette"]:
		assert_true(Registry.items.has(id), str(id))
		assert_not_null(Registry.items[id].effect_script, str(id))
	assert_false(Registry.items[&"empty_bottle"].in_loot, "bottles only come from beer")
	assert_false(&"empty_bottle" in sys.loot.ids_of(ItemDefinition.Rarity.COMMON))


func test_sunglasses_peek_for_one_blackjack_hand() -> void:
	_give(1, [&"sunglasses"])
	assert_true(_use(1)["ok"])
	assert_true(mods.has_flag(1, &"peek_dealer", &"blackjack"))
	mods.consume_round(1, &"blackjack")
	assert_false(mods.has_flag(1, &"peek_dealer", &"blackjack"))


func test_monkey_jinxes_and_passes_on_with_a_shove() -> void:
	_give(1, [&"bad_luck_monkey"])
	assert_true(_use(1, 2)["ok"])
	assert_eq(mods.get_luck(2), -3)
	sys.pass_monkey(2, 3, now)
	assert_eq(mods.get_luck(2), 0)
	assert_eq(mods.get_luck(3), -3, "hot potato")
	assert_eq(_events(&"monkey_passed").size(), 1)
	mods.expire(now + 30.0)
	assert_eq(mods.get_luck(3), 0, "keeps its original expiry")


func test_vip_pass_flag_and_callback_on_expiry() -> void:
	var lost: Array[int] = []
	sys.on_vip_lost = func(p: int) -> void: lost.append(p)
	_give(1, [&"vip_pass"])
	assert_true(_use(1)["ok"])
	assert_true(mods.has_flag(1, &"vip_pass"))
	mods.expire(now + 200.0)
	assert_eq(lost, [1] as Array[int])


func test_scratch_ticket_gives_an_item_or_house_cash() -> void:
	var cash: int = 0
	var items: int = 0
	for i: int in 200:
		players[1].inventory.clear()
		_give(1, [&"scratch_ticket"])
		var before: int = eco.balance(1)
		assert_true(_use(1)["ok"])
		var ev: Dictionary = _events(&"item_used").back()
		if ev["prize"] == &"cash":
			cash += 1
			assert_eq(eco.balance(1) - before, int(ev["amount"]))
			assert_between(int(ev["amount"]), 50, 500)
		else:
			items += 1
			assert_true(players[1].inventory.has(StringName(ev["won_item"])))
			assert_ne(StringName(ev["won_item"]), &"empty_bottle")
	assert_between(cash, 15, 50, "about 15% cash")
	assert_eq(cash + items, 200)
	assert_eq(eco.ledger.total(), _total())


func test_bat_knocks_out_and_spills_chips() -> void:
	_near(1, 2)
	_give(1, [&"baseball_bat"])
	var r: Dictionary = _use(1, 2)
	assert_true(r["ok"], str(r))
	var ev: Dictionary = _events(&"item_used").back()
	assert_true(bool(ev["knocked_out"]))
	assert_eq(sys.interactions.drain_events().filter(func(e: Dictionary) -> bool: return e["type"] == &"player_knocked_out").size(), 1)
	assert_eq(int(ev["amount"]), 80, "8% of 1000")
	assert_eq(pickups.total_on_floor(), 80)
	assert_eq(eco.balance(2), 920)


func test_bat_needs_range_and_knocks_a_seated_target_off_their_seat() -> void:
	_give(1, [&"baseball_bat"])
	assert_eq(sys.use(1, 0, 2, now)["error"], &"out_of_range")
	_near(1, 2)
	rules.status(2).seated = true
	var unseated: Array[int] = []
	sys.unseat = func(p: int) -> Dictionary:
		unseated.append(p)
		return {"ok": true}
	assert_true(sys.use(1, 0, 2, now)["ok"], "items can hit people at tables")
	assert_eq(unseated, [2] as Array[int], "stood up through the station first")
	assert_false(rules.status(2).seated)
	assert_true(rules.is_knocked_out(2, now))
	rules.status(1).seated = true
	_give(1, [&"baseball_bat"])
	now += cfg.item_cooldown + 0.1
	world.set_transform(3, world.get_position(1) + Vector3(0, 0, 1.5), 0.0)
	assert_eq(sys.use(1, 0, 3, now)["error"], &"seated", "but not from a seat")


func test_beer_luck_then_empty_bottle_which_stuns() -> void:
	_give(1, [&"beer"])
	assert_true(_use(1)["ok"])
	assert_eq(mods.get_luck(1), 1)
	assert_true(mods.has_flag(1, &"drunk"))
	mods.expire(now + 41.0)
	assert_eq(players[1].inventory, [&"empty_bottle"] as Array[StringName])
	now += 41.0
	_near(1, 2)
	assert_true(_use(1, 2)["ok"])
	assert_true(rules.is_knocked_down(2, now - cfg.item_cooldown + 3.9))
	assert_eq(eco.balance(2), 950, "5% spilled")


func test_credit_card_loan_and_repayment_never_negative() -> void:
	_give(1, [&"credit_card", &"credit_card"])
	assert_true(_use(1)["ok"])
	assert_eq(eco.balance(1), 1300)
	mods.expire(now + 91.0)
	assert_eq(eco.balance(1), 940, "paid back 360")
	# Second card, but spend everything first: the bank takes what's there.
	assert_true(_use(1)["ok"])
	eco.apply(1, -1200, &"test")
	mods.expire(now + 200.0)
	assert_eq(eco.balance(1), 0)
	assert_eq(_events(&"credit_repaid").back()["amount"], 40)


func test_russian_roulette_pays_until_the_bang_then_jackpot() -> void:
	_give(1, [&"russian_roulette"])
	var pot: int = sys.jackpot.pot
	var pulls: int = 0
	while true:
		var money: int = eco.balance(1)
		assert_true(_use(1)["ok"])
		var ev: Dictionary = _events(&"item_used").back()
		pulls += 1
		if bool(ev["bang"]):
			assert_eq(eco.balance(1), int(floor(money * 0.2)) + (money - int(floor(money * 0.2))) - int(ev["amount"]))
			assert_eq(sys.jackpot.pot, pot + int(ev["amount"]), "lost money feeds the jackpot")
			assert_eq(players[1].inventory.size(), 0, "revolver gone")
			break
		assert_eq(eco.balance(1), money + int(floor(money * 0.2)))
		assert_eq(players[1].inventory, [&"russian_roulette"] as Array[StringName], "stays for another pull")
		assert_almost_eq(float(ev["odds"]), pulls / 6.0, 0.001)
		assert_lt(pulls, 7)


func test_greedy_pickpocket_tiers() -> void:
	var caught: int = 0
	var stolen: int = 0
	for i: int in 100:
		players[1].inventory.clear()
		_near(1, 2)
		_give(1, [&"pickpocket"])
		var before: int = _total()
		now += cfg.item_grace
		assert_true(_use(1, 2, {"option": 2})["ok"])
		var ev: Dictionary = _events(&"item_used").back()
		assert_eq(_total(), before, "money only moves between the two")
		if bool(ev.get("caught", false)):
			caught += 1
		else:
			stolen += 1
		eco.apply(1, 1000 - eco.balance(1), &"test")
		eco.apply(2, 1000 - eco.balance(2), &"test")
	assert_between(caught, 45, 75, "very greedy works 40% of the time")
	# Safe tier is the classic sure 12%.
	players[1].inventory.clear()
	_give(1, [&"pickpocket"])
	now += cfg.item_grace
	assert_true(_use(1, 2)["ok"])
	assert_eq(int(_events(&"item_used").back()["amount"]), 120)


func test_fake_cash_pays_the_stake_and_may_be_caught() -> void:
	var fx := TableFixture.new(2, [1], 1000)
	var bj: BlackjackLogic = fx.make(BlackjackLogic.new(), &"bj") as BlackjackLogic
	bj.join(1)
	var m := Modifier.new()
	m.id = &"fake_cash"
	m.flags[&"fake_cash"] = true
	fx.modifiers.add(1, m)
	assert_true(bj.place_bet(1, {"amount": 150})["ok"])
	assert_eq(fx.economy.balance(1), 1000, "the house paid the stake")
	var used: Array = bj.drain_events().filter(func(e: Dictionary) -> bool: return e["type"] == &"fake_cash_used")
	assert_eq(used.size(), 1)
	assert_eq(int(used[0]["amount"]), 150)
	assert_false(fx.modifiers.has_flag(1, &"fake_cash"), "used up")


func test_dog_collar_takes_a_share_of_wins() -> void:
	var fx := TableFixture.new(2, [1, 2], 1000)
	var bj: BlackjackLogic = fx.make(BlackjackLogic.new(), &"bj") as BlackjackLogic
	bj.join(1)
	var m := Modifier.new()
	m.id = &"dog_collar"
	m.source_player = 2
	m.flags[&"collar"] = true
	fx.modifiers.add(1, m)
	bj._settle(1, 100, 200)
	assert_eq(fx.economy.balance(1), 1000 + 200 - 15, "15% of the $100 profit")
	assert_eq(fx.economy.balance(2), 1015)


func test_scissors_cut_the_last_card() -> void:
	var fx := TableFixture.new(2, [1], 1000)
	var bj: BlackjackLogic = fx.make(BlackjackLogic.new(), &"bj") as BlackjackLogic
	bj.join(1)
	bj.shoe.stack_top([Card.make(10), Card.make(9), Card.make(2), Card.make(10), Card.make(5)] as Array[int])
	bj.place_bet(1, {"amount": 50})
	bj.tick(30.0)
	assert_eq(bj.state, BlackjackLogic.State.ACTING)
	assert_eq(bj.player_action(1, &"cut")["error"], &"cannot_cut", "no scissors")
	var m := Modifier.new()
	m.id = &"scissors"
	m.game_id = &"blackjack"
	m.flags[&"scissors"] = true
	fx.modifiers.add(1, m)
	assert_true(bj.get_private_state(1).get("scissors", false))
	assert_eq(bj.player_action(1, &"cut")["error"], &"cannot_cut", "needs three cards")
	assert_true(bj.player_action(1, &"hit")["ok"])  # 10 + 2 + 5 = 17
	assert_true(bj.player_action(1, &"cut")["ok"])
	assert_eq(HandEval.total(bj.hands[1]["cards"]), 12, "the 5 is gone")
	assert_false(fx.modifiers.has_flag(1, &"scissors"), "used up")


func test_energy_drink_speeds_up_a_table_you_have_alone() -> void:
	var fx := TableFixture.new(2, [1, 2], 1000)
	var r: RouletteLogic = fx.make(RouletteLogic.new(), &"r") as RouletteLogic
	r.join(1)
	r.tick(0.01)
	var start: float = r.timer
	var m := Modifier.new()
	m.id = &"energy_drink"
	m.flags[&"fast_tables"] = true
	fx.modifiers.add(1, m)
	r.tick(1.0)
	assert_almost_eq(r.timer, start - 2.0, 0.001, "double speed alone")
	r.join(2)
	r.tick(1.0)
	assert_almost_eq(r.timer, start - 3.0, 0.001, "normal speed with company")
