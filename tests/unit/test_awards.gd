extends GutTest
## Results awards (§2.11).


func test_picks_best_per_award_and_spreads_players() -> void:
	var stats: Dictionary = {
		1: {"biggest_win": 900, "quiz_points": 2000, "biggest_bet": 500},
		2: {"biggest_win": 100, "quiz_points": 2500, "knockouts_suffered": 4},
		3: {"thrown_out": 2, "biggest_loss": 300},
	}
	var names: Dictionary = {1: "Ann", 2: "Bob", 3: "Cy"}
	var out: Array[Dictionary] = Awards.pick(stats, names, 3)
	assert_eq(out.size(), 3)
	assert_eq(out[0]["id"], &"big_winner")
	assert_eq(out[0]["player"], 1)
	assert_eq(out[0]["text"], "Biggest single win: $900")
	assert_eq(out[1]["id"], &"quiz_wiz")
	assert_eq(out[1]["name"], "Bob")
	assert_eq(out[2]["player"], 3, "third award goes to someone without one yet")


func test_zero_stats_earn_nothing_and_ties_go_to_lower_id() -> void:
	var stats: Dictionary = {2: {"biggest_win": 50}, 1: {"biggest_win": 50}, 3: {}}
	var out: Array[Dictionary] = Awards.pick(stats, {}, 4)
	assert_eq(out.size(), 1)
	assert_eq(out[0]["player"], 1)
	assert_eq(out[0]["name"], "Player 1")


func test_fills_up_with_repeats_when_few_players() -> void:
	var stats: Dictionary = {1: {"biggest_win": 10, "quiz_points": 5, "biggest_bet": 2}}
	assert_eq(Awards.pick(stats, {}, 4).size(), 3)


func test_comeback_and_thousands() -> void:
	assert_eq(Awards.value_of({"lowest_rank": 5, "final_rank": 1}, "comeback"), 4)
	assert_eq(Awards.value_of({"lowest_rank": 1, "final_rank": 2}, "comeback"), 0)
	var out: Array[Dictionary] = Awards.pick({1: {"biggest_win": 1234567}}, {}, 1)
	assert_eq(out[0]["text"], "Biggest single win: $1,234,567")


func test_jackpot_winner_comes_first() -> void:
	var stats: Dictionary = {1: {"biggest_win": 5000}, 2: {"jackpot_won": 2500, "biggest_win": 2500}}
	var out: Array[Dictionary] = Awards.pick(stats, {1: "Ann", 2: "Bob"}, 2)
	assert_eq(out[0]["id"], &"jackpot")
	assert_eq(out[0]["player"], 2)
	assert_eq(out[0]["text"], "Hit the jackpot for $2,500")
	assert_eq(out[1]["id"], &"big_winner")
	assert_eq(out[1]["player"], 1)


func test_knockouts_shoves_and_unluckiest() -> void:
	var stats: Dictionary = {
		1: {"knockouts_dealt": 3, "times_shoved": 1},
		2: {"times_shoved": 7, "knockouts_dealt": 1},
		3: {"loss_streak": 5},
	}
	var out: Array[Dictionary] = Awards.pick(stats, {}, 3)
	var by_id: Dictionary = {}
	for a: Dictionary in out:
		by_id[a["id"]] = a
	assert_eq(by_id[&"heavyweight"]["player"], 1)
	assert_eq(by_id[&"heavyweight"]["text"], "Knockouts dealt: 3")
	assert_eq(by_id[&"unluckiest"]["player"], 3)
	assert_eq(by_id[&"unluckiest"]["text"], "Lost 5 bets in a row")
	assert_eq(by_id[&"pinball"]["player"], 2)
	assert_eq(by_id[&"pinball"]["text"], "Shoved around 7 times")


func test_minimums_keep_small_numbers_out() -> void:
	var stats: Dictionary = {1: {"loss_streak": 2, "times_shoved": 1, "knockouts_suffered": 1, "thrown_out": 1}}
	assert_eq(Awards.pick(stats, {}, 4).size(), 0, "two losses in a row is not unlucky yet")
	stats[1]["loss_streak"] = 3
	assert_eq(Awards.pick(stats, {}, 4)[0]["id"], &"unluckiest")


func test_every_award_has_a_unique_id_and_valid_format() -> void:
	var ids: Dictionary = {}
	for a: Array in Awards.AWARDS:
		assert_false(ids.has(a[1]), "duplicate award id %s" % a[1])
		ids[a[1]] = true
		assert_true(str(a[3]).contains("%s"), "%s text shows the value" % a[1])
	assert_gte(Awards.AWARDS.size(), 12)
