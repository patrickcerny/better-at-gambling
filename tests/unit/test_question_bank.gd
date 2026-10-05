extends GutTest
## The quiz question file and its validation (§2.9): 4 answers, a valid index, unique ids,
## non-empty text; picking never repeats within a match.

const PATH: String = "res://data/quiz/questions_en.json"


func _data() -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))


func _q(overrides: Dictionary = {}) -> Dictionary:
	var q: Dictionary = {"id": "t1", "category": "silly", "difficulty": 1, "question": "Q?", "answers": ["a", "b", "c", "d"], "correct_index": 2}
	q.merge(overrides, true)
	return q


func test_shipped_file_is_valid_and_big_enough() -> void:
	var errors: Array[String] = QuestionBank.validate(_data())
	assert_eq(errors, [] as Array[String])
	var bank: QuestionBank = QuestionBank.from_data(_data())
	assert_gte(bank.size(), 60, "MVP threshold is 60 questions")
	var cats: Dictionary = {}
	for q: Dictionary in bank.questions:
		cats[q["category"]] = true
	for c: String in QuestionBank.CATEGORIES:
		assert_true(cats.has(c), "category %s has questions" % c)
	assert_eq(Registry.quiz_bank.size(), bank.size())


func test_validation_catches_each_problem() -> void:
	assert_eq(QuestionBank.validate_question(_q()), [] as Array[String])
	assert_false(QuestionBank.validate_question(_q({"answers": ["a", "b", "c"]})).is_empty(), "3 answers")
	assert_false(QuestionBank.validate_question(_q({"answers": ["a", "b", "c", ""]})).is_empty(), "empty answer")
	assert_false(QuestionBank.validate_question(_q({"answers": ["a", "a", "c", "d"]})).is_empty(), "duplicate answer")
	assert_false(QuestionBank.validate_question(_q({"correct_index": 4})).is_empty(), "index out of range")
	assert_false(QuestionBank.validate_question(_q({"correct_index": -1})).is_empty(), "negative index")
	assert_false(QuestionBank.validate_question(_q({"question": "  "})).is_empty(), "empty question")
	assert_false(QuestionBank.validate_question(_q({"id": ""})).is_empty(), "empty id")
	assert_false(QuestionBank.validate_question(_q({"category": "sports"})).is_empty(), "unknown category")
	assert_false(QuestionBank.validate_question(_q({"difficulty": 0})).is_empty(), "difficulty 0")
	var dup: Array[String] = QuestionBank.validate({"questions": [_q(), _q()]})
	assert_eq(dup.size(), 1)
	assert_string_contains(dup[0], "duplicate id")
	assert_false(QuestionBank.validate(null).is_empty())
	var bank: QuestionBank = QuestionBank.from_data({"questions": [_q(), _q({"id": "t2", "answers": ["x"]})]})
	assert_eq(bank.size(), 1, "invalid entries are dropped")


func test_pick_never_repeats_until_the_bank_runs_dry() -> void:
	var bank: QuestionBank = QuestionBank.from_data(_data())
	var used: Dictionary = {}
	var seen: Dictionary = {}
	var rng := SeededRng.new(3)
	for i: int in bank.size() / 3:
		for q: Dictionary in bank.pick(3, rng, used):
			assert_false(seen.has(q["id"]), "repeat of %s" % q["id"])
			seen[q["id"]] = true
	assert_eq(bank.pick(3, rng, used).size(), 3, "a dry bank starts over instead of failing")


func test_shuffled_answers_keep_the_right_answer() -> void:
	var q: Dictionary = _q()
	var rng := SeededRng.new(9)
	var moved: bool = false
	for i: int in 20:
		var s: Dictionary = QuestionBank.shuffled_answers(q, rng)
		assert_eq(s["answers"][s["correct_index"]], "c")
		assert_eq((s["answers"] as Array).size(), 4)
		moved = moved or int(s["correct_index"]) != 2
	assert_true(moved, "answers actually move")
	assert_eq(q["answers"], ["a", "b", "c", "d"], "the bank's copy is untouched")
