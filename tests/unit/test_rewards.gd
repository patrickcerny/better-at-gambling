extends GutTest
## Reward phase (§2.10, Patrick's note #11): no draft. Placement cash for every place, one item per
## player rolled by placement, the Underdog Rare, the House Comp on the rows and the reveal timer.

const R := ItemDefinition.Rarity

var cfg: BalanceConfig = BalanceConfig.new()
var rar: Dictionary[StringName, int] = {
	&"lucky_clover": R.COMMON, &"black_cat": R.COMMON, &"loaded_reels": R.COMMON, &"hot_hands": R.COMMON,
	&"golden_chip": R.COMMON, &"banana_peel": R.COMMON, &"bodyguard": R.COMMON, &"boxing_glove": R.COMMON,
	&"double_down": R.RARE, &"pickpocket": R.RARE, &"mirror": R.RARE,
	&"crown": R.LEGENDARY,
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


func test_cash_by_placement_for_every_place() -> void:
	assert_eq(RewardDirector.cash_for(1, true, 1.0, cfg), 150)
	assert_eq(RewardDirector.cash_for(2, true, 1.0, cfg), 100)
	assert_eq(RewardDirector.cash_for(3, true, 1.0, cfg), 75)
	assert_eq(RewardDirector.cash_for(4, true, 1.0, cfg), 50)
	assert_eq(RewardDirector.cash_for(5, true, 1.0, cfg), 25)
	assert_eq(RewardDirector.cash_for(8, true, 1.0, cfg), 25, "places past the list get the last prize")
	assert_eq(RewardDirector.cash_for(1, true, 2.0, cfg), 300, "limits multiplier of the segment")
	assert_eq(RewardDirector.cash_for(1, false, 1.0, cfg), 300, "items off doubles cash")
	assert_eq(RewardDirector.cash_for(0, true, 1.0, cfg), 0)


func test_start_pays_cash_gives_one_item_each_and_announces_everything() -> void:
	var s: Array = _setup(4)
	var eco: Economy = s[0]
	var players: Dictionary[int, PlayerState] = s[1]
	var rd := RewardDirector.new()
	rd.start(_ranking(4), eco, loot, true, 1.0, cfg, SeededRng.new(3), players)
	assert_eq(eco.balance(1), 1150)
	assert_eq(eco.balance(2), 1100)
	assert_eq(eco.balance(3), 1075)
	assert_eq(eco.balance(4), 1050)
	var ev: Array[Dictionary] = rd.drain_events()
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["type"], &"rewards_started")
	var rows: Array = ev[0]["rewards"]
	assert_eq(rows.size(), 4)
	for i: int in rows.size():
		assert_eq(int(rows[i]["placement"]), i + 1, "rows in placement order")
		assert_true(rar.has(StringName(rows[i]["item"])), "everyone gets an item")
		assert_eq(players[i + 1].inventory[0], StringName(rows[i]["item"]), "granted right away")
	assert_true(rows[3].has("bonus"), "last of 4: Underdog Rare")
	assert_eq(rar[StringName(rows[3]["bonus"])], R.RARE)
	assert_false(rows[0].has("bonus"))
	assert_almost_eq(float(ev[0]["seconds"]), cfg.reward_reveal_time + cfg.reward_row_time * 4, 0.01)


func test_reveal_runs_its_timer_then_is_done() -> void:
	var s: Array = _setup(2)
	var rd := RewardDirector.new()
	rd.start(_ranking(2), s[0], loot, true, 1.0, cfg, SeededRng.new(7), s[1])
	var t: float = 0.0
	while not rd.is_done() and t < 30.0:
		rd.tick(0.05)
		t += 0.05
	assert_true(rd.is_done())
	assert_almost_eq(t, cfg.reward_reveal_time + cfg.reward_row_time * 2, 0.11)
	assert_eq((rd.get_public_state()["rewards"] as Array).size(), 2, "snapshot keeps the rows")


func test_full_inventory_goes_through_grant() -> void:
	var s: Array = _setup(2)
	var players: Dictionary[int, PlayerState] = s[1]
	players[1].inventory.assign([&"black_cat", &"bodyguard", &"mirror", &"golden_chip", &"rock_paper_scissors", &"lucky_clover"])
	var granted: Array = []
	var rd := RewardDirector.new()
	rd.grant = func(p: int, item: StringName) -> void: granted.append([p, item])
	rd.start(_ranking(2), s[0], loot, true, 1.0, cfg, SeededRng.new(2), players)
	assert_eq(granted.size(), 2, "the ItemSystem decides (discard choice when full)")
	assert_eq(players[1].inventory.size(), 6)


func test_items_off_means_cash_only() -> void:
	var s: Array = _setup(3)
	var eco: Economy = s[0]
	var players: Dictionary[int, PlayerState] = s[1]
	var rd := RewardDirector.new()
	rd.start(_ranking(3), eco, loot, false, 1.0, cfg, SeededRng.new(4), players)
	assert_eq(eco.balance(1), 1300)
	assert_eq(eco.balance(3), 1150)
	var rows: Array = rd.drain_events()[0]["rewards"]
	assert_eq(StringName(rows[0]["item"]), &"")
	assert_eq(players[1].inventory.size(), 0)


func test_comp_runs_before_the_prize_and_lands_on_the_row() -> void:
	var s: Array = _setup(2)
	var eco: Economy = s[0]
	eco.apply(2, -1000, &"test")
	var asked: Array = []
	var rd := RewardDirector.new()
	rd.start(_ranking(2), eco, loot, true, 1.0, cfg, SeededRng.new(5), s[1], func(p: int) -> int:
		asked.append([p, eco.balance(p)])
		if eco.balance(p) < 10:
			eco.apply(p, 450, &"house_comp")
			return 450
		return 0)
	assert_eq(asked, [[1, 1000], [2, 0]], "broke means broke at the end of the round, before the prize")
	var rows: Array = rd.drain_events()[0]["rewards"]
	assert_false(rows[0].has("comp"))
	assert_eq(int(rows[1]["comp"]), 450)
	assert_eq(eco.balance(2), 450 + 100)
