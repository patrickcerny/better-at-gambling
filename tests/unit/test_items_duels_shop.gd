extends GutTest
## Rock Paper Scissors wagers and the Gift Shop: duels only move money between the two players,
## the challenged player is pulled straight in, ties replay once; the shop sells each player one item per segment.

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


func test_item_pulls_the_target_straight_into_the_duel_and_winner_takes_the_stake() -> void:
	sys.give(1, &"rock_paper_scissors", now)
	var r: Dictionary = sys.use(1, 0, 2, now, {"option": 1})
	assert_true(r["ok"], str(r))
	var start: Array = _of(&"rps_start")
	assert_eq(start.size(), 1, "no invite: the duel starts at once")
	assert_eq(int(start[0]["stake"]), 100, "10% of the poorer player's $1000")
	var duel: int = int(start[0]["duel"])
	assert_eq(sys.private_state(2, now)["duel"]["state"], &"pick", "the target is in the duel without answering")
	assert_true(sys.duels.pick(1, duel, 0, now)["ok"])
	assert_false(sys.duels.pick(1, duel, 1, now)["ok"], "one pick each")
	assert_false(sys.duels.pick(3, duel, 1, now)["ok"], "outsiders can't pick")
	assert_true(sys.duels.pick(2, duel, 2, now)["ok"])
	var res: Array = _of(&"rps_result")
	assert_eq(int(res[0]["winner"]), 1)
	assert_eq(eco.balance(1), 1100)
	assert_eq(eco.balance(2), 900)
	assert_false(sys.duels.busy(1))


func test_answer_step_is_gone() -> void:
	assert_false(Intents.SCHEMA.has(&"rps_answer"), "no accept intent any more")
	assert_false(sys.duels.has_method(&"answer"))


func test_one_tie_replays_then_a_second_calls_it_off() -> void:
	var d: int = sys.duels.challenge(1, 2, 2, now)
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
	sys.duels.pick(1, d, 0, now)
	sys.duels.tick(now + RpsDuels.PICK_TIME + 0.1)
	sys.duels.tick(now + 2 * RpsDuels.PICK_TIME + 0.2)  # a tie replays once
	assert_false(sys.duels.duels.has(d))
	assert_eq(_total(), 3000)


func test_nobody_picking_still_settles() -> void:
	var d: int = sys.duels.challenge(1, 2, 0, now)
	sys.duels.tick(now + 60.0)
	sys.duels.tick(now + 120.0)
	assert_false(sys.duels.duels.has(d), "random picks for both, at most one replay")
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
