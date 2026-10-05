class_name QuizLogic
extends MinigameLogicBase
## The Casino Quiz (§2.9): exactly `quiz_questions` questions, each "get ready" → question with
## four answers → answer window (ends early once everyone answered) → reveal. Correct answers
## score 500-1000 by speed, measured on the server and compensated by the player's half-RTT.
##
## The correct index never leaves the server before the reveal: `quiz_question` carries the text
## and the shuffled answers only, `quiz_answered` says *that* someone answered, not what.

enum State { INTRO, READY, ANSWER, REVEAL, OUTRO, DONE }

var state: State = State.INTRO
var timer: float = 0.0
## The questions of this quiz, answers already shuffled (correct_index inside: server only).
var questions: Array[Dictionary] = []
var index: int = -1
## Server clock when the current question's answers went out.
var sent_at: float = 0.0
## Current question: player → chosen index, and → compensated elapsed seconds.
var answers: Dictionary[int, int] = {}
var elapsed: Dictionary[int, float] = {}
## Totals over the quiz.
var points: Dictionary[int, int] = {}
var correct_time: Dictionary[int, float] = {}
var _ranking: Array[Dictionary] = []
var _last_reveal: Dictionary = {}


## context: {bank: QuestionBank, used: Dictionary (ids asked this match), stats: Dictionary,
## game_names: Dictionary}.
func _on_setup(context: Dictionary) -> void:
	var bank: QuestionBank = context["bank"]
	var used: Dictionary = context.get("used", {})
	var count: int = balance.quiz_questions
	var dynamic: Dictionary = {}
	if rng.chance(balance.quiz_dynamic_chance):
		dynamic = DynamicQuestions.generate(context.get("stats", {}), rng)
	var picked: Array[Dictionary] = bank.pick(count - (1 if not dynamic.is_empty() else 0), rng, used)
	if not dynamic.is_empty():
		picked.append(dynamic)
	for q: Dictionary in picked:
		questions.append(QuestionBank.shuffled_answers(q, rng))
	for p: int in players:
		points[p] = 0
		correct_time[p] = 0.0
	state = State.INTRO
	timer = balance.quiz_intro_time
	events.append(GameEvents.make(&"quiz_started", {"players": players.duplicate(), "questions": questions.size(), "answer_time": balance.quiz_answer_time}))


func tick(delta: float, now: float) -> void:
	if state == State.DONE:
		return
	timer -= delta
	if state == State.ANSWER:
		if _everyone_answered():
			timer = minf(timer, 0.0)
	if timer > 0.0:
		return
	match state:
		State.INTRO, State.REVEAL:
			if index + 1 < questions.size():
				_get_ready()
			else:
				_outro()
		State.READY:
			_ask(now)
		State.ANSWER:
			_reveal()
		State.OUTRO:
			state = State.DONE
			finished = true


## `intent` = {question: index, index: chosen answer}.
func submit(player: int, intent: Dictionary, now: float) -> Dictionary:
	if not player in players:
		return StationLogicBase.fail(&"not_in_minigame")
	if state != State.ANSWER or int(intent.get("question", -1)) != index:
		return StationLogicBase.fail(&"too_late")
	if answers.has(player):
		return StationLogicBase.fail(&"already_answered")
	var choice: int = int(intent.get("index", -1))
	if choice < 0 or choice >= QuestionBank.ANSWER_COUNT:
		return StationLogicBase.fail(&"bad_value")
	_record(player, choice, QuizScoring.compensated_elapsed(sent_at, now, float(half_rtt.call(player))))
	return StationLogicBase.OK_RESULT


func ranking() -> Array[Dictionary]:
	return _ranking


func get_public_state() -> Dictionary:
	var st: Dictionary = {"minigame": &"quiz", "state": state, "timer": snappedf(maxf(timer, 0.0), 0.01), "index": index, "count": questions.size(),
		"players": players.duplicate(), "totals": points.duplicate(), "answered": answers.keys()}
	if index >= 0 and state in [State.ANSWER, State.REVEAL]:
		st["question"] = _public_question(index)
	if state == State.REVEAL or state == State.OUTRO:
		st["reveal"] = _last_reveal.duplicate(true)
	if state == State.OUTRO or state == State.DONE:
		st["ranking"] = _ranking.duplicate(true)
	return st


func private_state(player: int) -> Dictionary:
	if answers.has(player):
		return {"question": index, "answer": answers[player]}
	return {}


func _get_ready() -> void:
	index += 1
	answers.clear()
	elapsed.clear()
	state = State.READY
	timer = balance.quiz_ready_time
	events.append(GameEvents.make(&"quiz_get_ready", {"index": index, "seconds": balance.quiz_ready_time}))


func _ask(now: float) -> void:
	state = State.ANSWER
	timer = balance.quiz_answer_time
	sent_at = now
	var ev: Dictionary = _public_question(index)
	ev["seconds"] = balance.quiz_answer_time
	events.append(GameEvents.make(&"quiz_question", ev))


func _public_question(i: int) -> Dictionary:
	var q: Dictionary = questions[i]
	return {"index": i, "count": questions.size(), "question": q["question"], "answers": (q["answers"] as Array).duplicate(), "category": q["category"], "dynamic": bool(q.get("dynamic", false))}


func _record(player: int, choice: int, seconds: float) -> void:
	if answers.has(player) or not player in players:
		return
	answers[player] = choice
	elapsed[player] = minf(seconds, balance.quiz_answer_time)
	events.append(GameEvents.make(&"quiz_answered", {"player": player, "index": index}))


func _everyone_answered() -> bool:
	for p: int in players:
		if not answers.has(p):
			return false
	return not players.is_empty()


func _reveal() -> void:
	state = State.REVEAL
	timer = balance.quiz_reveal_time
	var correct: int = int(questions[index]["correct_index"])
	var gained: Dictionary = {}
	for p: int in players:
		var right: bool = answers.get(p, -1) == correct
		var pts: int = QuizScoring.points(right, elapsed.get(p, balance.quiz_answer_time), balance) if answers.has(p) else 0
		points[p] = int(points.get(p, 0)) + pts
		if right:
			correct_time[p] = float(correct_time.get(p, 0.0)) + float(elapsed[p])
		gained[p] = pts
	_last_reveal = {"index": index, "correct_index": correct, "answers": answers.duplicate(), "points": gained, "totals": points.duplicate(),
		"explanation": str(questions[index].get("explanation", ""))}
	events.append(GameEvents.make(&"quiz_reveal", _last_reveal.duplicate(true)))


func _outro() -> void:
	state = State.OUTRO
	timer = balance.quiz_outro_time
	var pts: Dictionary = {}
	var times: Dictionary = {}
	for p: int in players:
		pts[p] = points.get(p, 0)
		times[p] = correct_time.get(p, 0.0)
	_ranking = QuizScoring.rank(pts, times)
	events.append(GameEvents.make(&"quiz_finished", {"ranking": _ranking.duplicate(true)}))
