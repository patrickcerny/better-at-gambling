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
	assert_eq(out[0]["id"], &"jackpot")
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
