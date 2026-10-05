extends GutTest
## Reward phase (§2.10): placement cash, the private item draft, defaults and inventory limits.

const R := ItemDefinition.Rarity

var cfg: BalanceConfig = BalanceConfig.new()
var rar: Dictionary[StringName, int] = {
	&"lucky_clover": R.COMMON, &"black_cat": R.COMMON, &"loaded_reels": R.COMMON, &"hot_hands": R.COMMON,
	&"golden_chip": R.COMMON, &"banana_peel": R.COMMON, &"bodyguard": R.COMMON, &"boxing_glove": R.COMMON,
	&"double_down": R.RARE, &"pickpocket": R.RARE, &"mirror": R.RARE,
}
var loot: LootTables = LootTables.new(load("res://data/items/loot_tables.tres"), rar)


func _ranking(n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in n:
		out.append({"player": i + 1, "rank": i + 1})
	return out


func _setup(n: int) -> Array:
	var eco := Economy.new()
	var players: Dictionary[int, PlayerState] = {}
	for i: int in n:
		eco.add_player(i + 1, 1000)
		var ps := PlayerState.new()
		ps.id = i + 1
		players[i + 1] = ps
	return [eco, players]


func test_cash_by_placement_and_multipliers() -> void:
	assert_eq(RewardDirector.cash_for(1, true, 1.0, cfg), 150)
	assert_eq(RewardDirector.cash_for(2, true, 1.0, cfg), 100)
	assert_eq(RewardDirector.cash_for(3, true, 1.0, cfg), 50)
	assert_eq(RewardDirector.cash_for(4, true, 1.0, cfg), 0)
	assert_eq(RewardDirector.cash_for(1, true, 2.0, cfg), 300, "limits multiplier of the segment")
	assert_eq(RewardDirector.cash_for(1, false, 1.0, cfg), 300, "items off doubles cash")
	assert_eq(RewardDirector.cash_for(0, true, 1.0, cfg), 0)


func test_start_pays_cash_and_announces_without_offers() -> void:
	var s: Array = _setup(4)
	var eco: Economy = s[0]
	var rd := RewardDirector.new()
	rd.start(_ranking(4), eco, loot, true, 1.0, cfg, SeededRng.new(3))
	assert_eq(eco.balance(1), 1150)
	assert_eq(eco.balance(2), 1100)
	assert_eq(eco.balance(3), 1050)
	assert_eq(eco.balance(4), 1000)
	var ev: Array[Dictionary] = rd.drain_events()
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["type"], &"rewards_started")
	var wire: String = JSON.stringify(ev[0])
	for id: StringName in rar:
		assert_false(wire.contains(String(id)), "offers stay private")
	assert_false(rd.private_state(1).is_empty())
	assert_true((rd.private_state(1)["draft"]["choices"] as Array).size() > 0)


func test_default_pick_is_first_option_on_timeout() -> void:
	var s: Array = _setup(2)
	var players: Dictionary[int, PlayerState] = s[1]
	var rd := RewardDirector.new()
	rd.start(_ranking(2), s[0], loot, true, 1.0, cfg, SeededRng.new(7))
	var first: StringName = StringName(rd.private_state(1)["draft"]["choices"][0])
	var t: float = 0.0
	while not rd.is_done() and t < 30.0:
		rd.tick(0.05, players)
		t += 0.05
	assert_true(rd.is_done())
	assert_almost_eq(t, cfg.draft_time + cfg.reward_outro_time, 0.11)
	assert_eq(players[1].inventory[0], first)
	assert_true(rd.private_state(1).is_empty(), "no offer after the draft")


func test_pick_validation_and_early_close() -> void:
	var s: Array = _setup(2)
	var players: Dictionary[int, PlayerState] = s[1]
	var rd := RewardDirector.new()
	rd.start(_ranking(2), s[0], loot, true, 1.0, cfg, SeededRng.new(9))
	var n1: int = (rd.private_state(1)["draft"]["choices"] as Array).size()
	assert_eq(rd.pick(1, n1)["error"], &"bad_value")
	assert_eq(rd.pick(1, -1)["error"], &"bad_value")
	assert_eq(rd.pick(99, 0)["error"], &"no_reward")
	assert_true(rd.pick(1, n1 - 1)["ok"])
	assert_eq(rd.pick(1, 0)["error"], &"already_picked")
	var chosen: StringName = StringName(rd.rewards[1]["choices"][n1 - 1])
	assert_true(rd.pick(2, 0)["ok"])
	rd.tick(0.05, players)
	assert_eq(rd.state, RewardDirector.State.OUTRO, "everyone picked: the draft closes early")
	assert_eq(players[1].inventory[0], chosen)
	assert_eq(rd.pick(2, 0)["error"], &"too_late")


func test_inventory_capped_at_three() -> void:
	var s: Array = _setup(2)
	var players: Dictionary[int, PlayerState] = s[1]
	players[1].inventory.assign([&"black_cat", &"bodyguard", &"mirror"])
	var rd := RewardDirector.new()
	rd.start(_ranking(2), s[0], loot, true, 1.0, cfg, SeededRng.new(2))
	rd.pick(1, 0)
	rd.pick(2, 0)
	rd.tick(0.05, players)
	assert_eq(players[1].inventory.size(), 3)
	var res: Array[Dictionary] = rd.drain_events().filter(func(e: Dictionary) -> bool: return e["type"] == &"draft_result" and e["player"] == 1)
	assert_eq(res.size(), 1)
	assert_eq((res[0]["kept"] as Array).size(), 0)


func test_items_off_means_cash_only_and_no_draft() -> void:
	var s: Array = _setup(3)
	var eco: Economy = s[0]
	var players: Dictionary[int, PlayerState] = s[1]
	var rd := RewardDirector.new()
	rd.start(_ranking(3), eco, loot, false, 1.0, cfg, SeededRng.new(4))
	assert_eq(eco.balance(1), 1300)
	assert_true(rd.private_state(1).is_empty())
	var t: float = 0.0
	while not rd.is_done() and t < 30.0:
		rd.tick(0.05, players)
		t += 0.05
	assert_almost_eq(t, cfg.reward_outro_time, 0.11, "no draft wait")
	assert_eq(players[1].inventory.size(), 0)
