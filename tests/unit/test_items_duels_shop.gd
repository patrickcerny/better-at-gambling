extends GutTest
## Rock Paper Scissors wagers and the Gift Shop: duels only move money between the two players,
## ties replay once, silence declines; the shop sells each player one item per segment.

var cfg: BalanceConfig = BalanceConfig.new()
var players: Dictionary[int, PlayerState] = {}
var eco: Economy
var sys: ItemSystem
var now: float = 100.0


func before_each() -> void:
	players = {}
	eco = Economy.new()
	var world := WorldQuery.new()
	for id: int in [1, 2, 3]:
		var p := PlayerState.new()
		p.id = id
		players[id] = p
		eco.add_player(id, 1000)
		world.set_transform(id, Vector3(id * 10.0, 0, 0), 0.0)
	var rules := InteractionRules.new(cfg)
	sys = ItemSystem.new(Registry.items, cfg, players, eco, ModifierStack.new(cfg.luck_clamp), rules, world, PickupSystem.new(eco), SeededRng.new(4))
	var rarities: Dictionary[StringName, int] = {}
	for id: StringName in Registry.items:
		if Registry.items[id].in_loot:
			rarities[id] = Registry.items[id].rarity
	sys.loot = LootTables.new(Registry.loot, rarities)
	sys.setup_extras()
	now = 100.0


func _of(type: StringName) -> Array:
	return sys.drain_events().filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _total() -> int:
	return eco.balance(1) + eco.balance(2) + eco.balance(3)


func test_outcome_table() -> void:
	# 0 rock, 1 paper, 2 scissors
	assert_eq(RpsDuels.outcome(0, 2), 1)
	assert_eq(RpsDuels.outcome(1, 0), 1)
	assert_eq(RpsDuels.outcome(2, 1), 1)
	assert_eq(RpsDuels.outcome(2, 0), 2)
	assert_eq(RpsDuels.outcome(1, 1), 0)


func test_item_challenges_and_winner_takes_the_stake() -> void:
	sys.give(1, &"rock_paper_scissors", now)
	var r: Dictionary = sys.use(1, 0, 2, now, {"option": 1})
	assert_true(r["ok"], str(r))
	var invite: Array = _of(&"rps_invite")
	assert_eq(invite.size(), 1)
	assert_eq(int(invite[0]["stake"]), 100, "10% of the poorer player's $1000")
	var duel: int = int(invite[0]["duel"])
	assert_false(sys.duels.pick(1, duel, 0, now)["ok"], "no picks before the answer")
	assert_true(sys.duels.answer(2, duel, true, now)["ok"])
	assert_true(sys.duels.pick(1, duel, 0, now)["ok"])
	assert_false(sys.duels.pick(1, duel, 1, now)["ok"], "one pick each")
	assert_true(sys.duels.pick(2, duel, 2, now)["ok"])
	var res: Array = _of(&"rps_result")
	assert_eq(int(res[0]["winner"]), 1)
	assert_eq(eco.balance(1), 1100)
	assert_eq(eco.balance(2), 900)
	assert_false(sys.duels.busy(1))


func test_decline_and_silence_cost_nothing() -> void:
	var a: int = sys.duels.challenge(1, 2, 0, now)
	assert_false(sys.duels.answer(3, a, true, now)["ok"], "only the challenged player answers")
	assert_true(sys.duels.answer(2, a, false, now)["ok"])
	var b: int = sys.duels.challenge(1, 3, 0, now)
	sys.duels.tick(now + RpsDuels.ANSWER_TIME + 0.1, {})
	var cancelled: Array = _of(&"rps_cancelled")
	assert_eq(cancelled.map(func(e: Dictionary) -> StringName: return e["reason"]), [&"declined", &"no_answer"])
	assert_eq(int(cancelled[1]["duel"]), b)
	assert_eq(_total(), 3000)


func test_one_tie_replays_then_a_second_calls_it_off() -> void:
	var d: int = sys.duels.challenge(1, 2, 2, now)
	sys.duels.answer(2, d, true, now)
	sys.duels.pick(1, d, 1, now)
	sys.duels.pick(2, d, 1, now)
	var first: Array = _of(&"rps_result")
	assert_true(first[0]["replay"])
	assert_true(sys.duels.duels.has(d), "replayed")
	sys.duels.pick(1, d, 0, now)
	sys.duels.pick(2, d, 0, now)
	var second: Array = _of(&"rps_result")
	assert_eq(int(second[0]["winner"]), -1)
	assert_false(second[0]["replay"])
	assert_eq(_total(), 3000)
	assert_eq(eco.balance(1), 1000)


func test_missed_pick_is_random_and_money_is_conserved() -> void:
	var d: int = sys.duels.challenge(1, 2, 2, now)
	sys.duels.answer(2, d, true, now)
	sys.duels.pick(1, d, 0, now)
	sys.duels.tick(now + RpsDuels.PICK_TIME + 0.1, {})
	sys.duels.tick(now + 2 * RpsDuels.PICK_TIME + 0.2, {})  # a tie replays once
	assert_false(sys.duels.duels.has(d))
	assert_eq(_total(), 3000)


func test_bots_answer_and_pick_on_their_own() -> void:
	players[2].is_bot = true
	var resolved: int = 0
	for i: int in 20:
		var d: int = sys.duels.challenge(1, 2, 0, now)
		sys.duels.tick(now, {2: true})
		if sys.duels.duels.has(d):
			sys.duels.pick(1, d, i % 3, now)
			sys.duels.tick(now, {2: true})
			sys.duels.tick(now + RpsDuels.PICK_TIME + 1.0, {2: true})
		assert_false(sys.duels.duels.has(d))
		resolved += 1
	assert_eq(resolved, 20)
	assert_eq(_total(), 3000)


func test_busy_players_cannot_be_challenged_twice() -> void:
	sys.duels.challenge(1, 2, 0, now)
	sys.give(3, &"rock_paper_scissors", now)
	var r: Dictionary = sys.use(3, 0, 2, now)
	assert_false(r["ok"])
	assert_eq(r["error"], &"busy")


func test_end_of_segment_calls_duels_off() -> void:
	sys.duels.challenge(1, 2, 0, now)
	sys.end_segment()
	assert_true(sys.duels.duels.is_empty())


func test_shop_stocks_four_distinct_offers_priced_by_rarity() -> void:
	sys.shop.restock(2.0)
	assert_eq(sys.shop.offers.size(), GiftShop.OFFERS)
	var ids: Dictionary = {}
	for o: Dictionary in sys.shop.offers:
		ids[o["item"]] = true
		assert_true(Registry.items[StringName(o["item"])].in_loot)
		assert_eq(int(o["price"]), GiftShop.PRICES[int(o["rarity"])] * 2)
	assert_eq(ids.size(), GiftShop.OFFERS)


func test_shop_sells_one_item_per_player_per_segment() -> void:
	sys.shop.restock(1.0)
	var price: int = int(sys.shop.offers[0]["price"])
	assert_true(sys.buy(1, 0, now)["ok"])
	assert_eq(eco.balance(1), 1000 - price)
	assert_eq(players[1].inventory.size(), 1)
	assert_eq(sys.buy(1, 1, now)["error"], &"already_bought")
	assert_true(sys.buy(2, 0, now)["ok"], "the same offer sells to everyone")
	assert_true(sys.private_state(1, now).has("shop_bought"))
	assert_eq(sys.buy(3, 9, now)["error"], &"bad_value")
	eco.apply(3, -990, &"test")
	assert_eq(sys.buy(3, 0, now)["error"], &"insufficient_funds")
	sys.shop.restock(1.0)
	assert_true(sys.buy(1, 0, now)["ok"], "a new segment, a new purchase")
