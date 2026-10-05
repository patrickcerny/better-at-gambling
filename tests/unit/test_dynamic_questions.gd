extends GutTest
## Questions generated from match stats (§2.9).


func _stats(won: Dictionary, balances: Dictionary) -> Dictionary:
	var players: Dictionary = {}
	for id: int in balances:
		players[id] = {"name": "P%d" % id, "balance": balances[id], "won_by_game": won.get(id, {})}
	return {"players": players, "game_names": {&"slots": "Slots"}}


func test_most_won_at_names_the_winner() -> void:
	var st: Dictionary = _stats({1: {&"slots": 40}, 2: {&"slots": 300}}, {1: 900, 2: 1300, 3: 1000})
	var q: Dictionary = DynamicQuestions.make(&"most_won_at", st, SeededRng.new(1))
	assert_eq(q["question"], "Who has won the most at Slots so far?")
	assert_eq(q["answers"][q["correct_index"]], "P2")
	assert_eq((q["answers"] as Array).size(), 4, "fillers top up a 3-player match")
	assert_eq(QuestionBank.validate_question(q), [] as Array[String])


func test_most_won_at_skips_ties_and_empty_stats() -> void:
	assert_true(DynamicQuestions.make(&"most_won_at", _stats({}, {1: 1000, 2: 1000}), SeededRng.new(1)).is_empty())
	var tie: Dictionary = _stats({1: {&"slots": 50}, 2: {&"slots": 50}}, {1: 1000, 2: 1000})
	assert_true(DynamicQuestions.make(&"most_won_at", tie, SeededRng.new(1)).is_empty())


func test_leader_money_options() -> void:
	for seed_value: int in 30:
		var q: Dictionary = DynamicQuestions.make(&"leader_money", _stats({}, {1: 1234, 2: 800}), SeededRng.new(seed_value))
		assert_eq(q["answers"][q["correct_index"]], "$1234")
		assert_eq(QuestionBank.validate_question(q), [] as Array[String])
		for a: Variant in q["answers"]:
			assert_true(str(a).ends_with("4"), "same last digit: %s" % a)


func test_generate_falls_back_between_templates() -> void:
	var q: Dictionary = DynamicQuestions.generate(_stats({}, {1: 1500, 2: 900}), SeededRng.new(2))
	assert_eq(q["id"], "dyn_leader_money", "no wins yet: only the money question works")
	assert_true(DynamicQuestions.generate({"players": {}}, SeededRng.new(2)).is_empty())
