extends GutTest
## Casino Quiz rules (§2.9): three questions, server timing with RTT compensation, ties, bots,
## and the correct answer never leaving the server before the reveal.

var cfg: BalanceConfig = BalanceConfig.new()
var bank: QuestionBank
var now: float = 0.0


func before_each() -> void:
	cfg.quiz_dynamic_chance = 0.0
	bank = QuestionBank.from_data(JSON.parse_string(FileAccess.get_file_as_string("res://data/quiz/questions_en.json")))
	now = 0.0


func _quiz(players: Array[int], bots: Dictionary[int, StringName] = {}, used: Dictionary = {}, rtt: Dictionary = {}) -> QuizLogic:
	var q := QuizLogic.new()
	q.half_rtt = func(p: int) -> float: return float(rtt.get(p, 0.0))
	q.setup(players, bots, SeededRng.new(5), cfg, {}, {"bank": bank, "used": used, "stats": {}})
	return q


func _run(q: QuizLogic, seconds: float, events: Array[Dictionary]) -> void:
	var t: float = 0.0
	while t < seconds - 0.0001 and not q.is_finished():
		q.tick(0.05, now)
		now += 0.05
		t += 0.05
		events.append_array(q.drain_events())


func _to_answer(q: QuizLogic, events: Array[Dictionary]) -> void:
	while q.state != QuizLogic.State.ANSWER and not q.is_finished():
		_run(q, 0.05, events)


func test_exactly_three_questions_then_ranking() -> void:
	var events: Array[Dictionary] = []
	var q: QuizLogic = _quiz([1, 2])
	events.append_array(q.drain_events())
	_run(q, 200.0, events)
	assert_true(q.is_finished())
	var asked: Array = events.filter(func(e: Dictionary) -> bool: return e["type"] == &"quiz_question")
	assert_eq(asked.size(), 3)
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e["type"] == &"quiz_reveal").size(), 3)
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e["type"] == &"quiz_finished").size(), 1)
	assert_eq(q.ranking().size(), 2)
	# Nobody answered: 12 s per question, nobody scores.
	for row: Dictionary in q.ranking():
		assert_eq(row["points"], 0)
		assert_eq(row["rank"], 1)


func test_no_repeats_across_quizzes_of_a_match() -> void:
	var used: Dictionary = {}
	var ids: Dictionary = {}
	for i: int in 7:  # a 30-minute match
		var q: QuizLogic = _quiz([1, 2], {}, used)
		for question: Dictionary in q.questions:
			assert_false(ids.has(question["id"]), "repeat %s" % question["id"])
			ids[question["id"]] = true
	assert_eq(ids.size(), 21)


func test_correct_index_never_sent_before_reveal() -> void:
	var events: Array[Dictionary] = []
	var q: QuizLogic = _quiz([1, 2], {3: &"hard"})
	events.append_array(q.drain_events())
	_to_answer(q, events)
	q.submit(1, {"question": 0, "index": 2}, now)
	events.append_array(q.drain_events())
	# Everything a client can get during the answer window: events, public state, private state.
	for e: Dictionary in events:
		assert_false(_mentions_correct(e), "event %s leaks the answer" % e["type"])
		assert_false(_mentions_correct(Wire.decode(Wire.encode(Protocol.Msg.EVENT, e))[1]), "serialized %s" % e["type"])
	assert_false(_mentions_correct(q.get_public_state()))
	assert_false(_mentions_correct(q.private_state(1)))
	assert_false(_mentions_correct(q.private_state(2)))
	var answered: Array = events.filter(func(e: Dictionary) -> bool: return e["type"] == &"quiz_answered")
	assert_eq(answered.size(), 1)
	assert_false(answered[0].has("answer"), "others don't learn what you picked")
	_run(q, 15.0, events)
	var reveal: Array = events.filter(func(e: Dictionary) -> bool: return e["type"] == &"quiz_reveal")
	assert_eq(reveal.size(), 1)
	assert_true(reveal[0].has("correct_index"))


func _mentions_correct(v: Variant) -> bool:
	match typeof(v):
		TYPE_DICTIONARY:
			for k: Variant in v:
				if str(k) == "correct_index" or _mentions_correct(v[k]):
					return true
		TYPE_ARRAY:
			for x: Variant in v:
				if _mentions_correct(x):
					return true
	return false


func test_scoring_compensates_latency() -> void:
	# Player 1 has 300 ms RTT (150 ms each way), player 2 none. Both press at the same moment
	# 2 s after the question appeared on their screens: same score.
	var events: Array[Dictionary] = []
	var q: QuizLogic = _quiz([1, 2], {}, {}, {1: 0.15, 2: 0.0})
	_to_answer(q, events)
	var correct: int = int(q.questions[0]["correct_index"])
	var sent: float = q.sent_at
	assert_true(q.submit(2, {"question": 0, "index": correct}, sent + 2.0)["ok"])
	assert_true(q.submit(1, {"question": 0, "index": correct}, sent + 2.0 + 0.3)["ok"])
	assert_almost_eq(q.elapsed[1], q.elapsed[2], 0.16, "the slow line only costs the one-way delay it was compensated for")
	assert_almost_eq(q.elapsed[1], 2.15, 0.001)
	_run(q, 1.0, events)
	var reveal: Dictionary = events.filter(func(e: Dictionary) -> bool: return e["type"] == &"quiz_reveal")[0]
	assert_eq(reveal["points"][2], 500 + roundi(500.0 * 10.0 / 12.0))
	assert_eq(reveal["points"][1], 500 + roundi(500.0 * (12.0 - 2.15) / 12.0))


func test_one_answer_only_and_window_checks() -> void:
	var events: Array[Dictionary] = []
	var q: QuizLogic = _quiz([1, 2])
	assert_eq(q.submit(1, {"question": 0, "index": 0}, now)["error"], &"too_late", "before the question")
	_to_answer(q, events)
	assert_eq(q.submit(1, {"question": 1, "index": 0}, now)["error"], &"too_late", "wrong question")
	assert_eq(q.submit(1, {"question": 0, "index": 4}, now)["error"], &"bad_value")
	assert_eq(q.submit(9, {"question": 0, "index": 0}, now)["error"], &"not_in_minigame")
	assert_true(q.submit(1, {"question": 0, "index": 0}, now)["ok"])
	assert_eq(q.submit(1, {"question": 0, "index": 1}, now)["error"], &"already_answered", "no changes")


func test_window_ends_early_when_everyone_answered() -> void:
	var events: Array[Dictionary] = []
	var q: QuizLogic = _quiz([1, 2])
	_to_answer(q, events)
	q.submit(1, {"question": 0, "index": 0}, now + 1.0)
	q.submit(2, {"question": 0, "index": 1}, now + 1.0)
	_run(q, 0.1, events)
	assert_eq(q.state, QuizLogic.State.REVEAL)


func test_ties_broken_by_faster_correct_time() -> void:
	var events: Array[Dictionary] = []
	var q: QuizLogic = _quiz([1, 2, 3])
	for i: int in 3:
		_to_answer(q, events)
		var c: int = int(q.questions[i]["correct_index"])
		var sent: float = q.sent_at
		# 1 and 2 are both right on every question; 1 is a bit faster once, slower once.
		q.submit(1, {"question": i, "index": c}, sent + [3.0, 6.0, 4.0][i])
		q.submit(2, {"question": i, "index": c}, sent + [3.0, 5.99, 4.0][i])
		q.submit(3, {"question": i, "index": (c + 1) % 4}, sent + 1.0)
		_run(q, 0.1, events)
	_run(q, 30.0, events)
	var ranking: Array[Dictionary] = q.ranking()
	assert_eq(ranking.map(func(r: Dictionary) -> int: return r["player"]), [2, 1, 3])
	assert_eq(ranking[0]["points"], ranking[1]["points"], "same points after rounding")
	assert_eq(ranking.map(func(r: Dictionary) -> int: return r["rank"]), [1, 2, 3])


func test_exact_ties_share_the_rank() -> void:
	var events: Array[Dictionary] = []
	var q: QuizLogic = _quiz([1, 2])
	for i: int in 3:
		_to_answer(q, events)
		var c: int = int(q.questions[i]["correct_index"])
		q.submit(1, {"question": i, "index": c}, q.sent_at + 2.0)
		q.submit(2, {"question": i, "index": c}, q.sent_at + 2.0)
		_run(q, 0.1, events)
	_run(q, 30.0, events)
	assert_eq(q.ranking().map(func(r: Dictionary) -> int: return r["rank"]), [1, 1])


func test_bots_answer_inside_the_window_with_their_accuracy() -> void:
	cfg.quiz_bot_accuracy = {&"hard": 1.0, &"easy": 0.0}
	var events: Array[Dictionary] = []
	var q: QuizLogic = _quiz([1, 2], {1: &"hard", 2: &"easy"})
	_run(q, 200.0, events)
	var reveals: Array = events.filter(func(e: Dictionary) -> bool: return e["type"] == &"quiz_reveal")
	assert_eq(reveals.size(), 3)
	for r: Dictionary in reveals:
		assert_eq(r["answers"][1], r["correct_index"])
		assert_ne(r["answers"][2], r["correct_index"])
		assert_between(int(r["points"][1]), 500 + roundi(500.0 * 3.0 / 12.0), 500 + roundi(500.0 * 10.0 / 12.0), "answered 2-9 s in")
	assert_eq(q.ranking()[0]["player"], 1)


func test_player_who_drops_scores_zero_and_leaves_the_ranking() -> void:
	var events: Array[Dictionary] = []
	var q: QuizLogic = _quiz([1, 2])
	_to_answer(q, events)
	q.remove_player(2)
	_run(q, 200.0, events)
	assert_eq(q.ranking().size(), 1)
