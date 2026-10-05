class_name QuestionBank
extends RefCounted
## The quiz question bank (§2.9): validates the parsed `questions_en.json` data and hands out
## questions without repeats. Pure: the caller reads and parses the file.
##
## Schema per question: {id, category, difficulty: 1-3, question, answers: [4], correct_index,
## explanation?}.

const CATEGORIES: Array[String] = ["casino_trivia", "cards_and_dice", "luck_and_superstition", "game_rules", "silly"]
const ANSWER_COUNT: int = 4

var questions: Array[Dictionary] = []
var _by_id: Dictionary[String, Dictionary] = {}


## Builds a bank from parsed JSON (`{"questions": [...]}` or a bare array). Invalid entries are
## dropped; use `validate` to see why.
static func from_data(data: Variant) -> QuestionBank:
	var bank := QuestionBank.new()
	for q: Variant in _entries(data):
		if typeof(q) == TYPE_DICTIONARY and validate_question(q).is_empty() and not bank._by_id.has(str(q["id"])):
			var clean: Dictionary = (q as Dictionary).duplicate(true)
			clean["correct_index"] = int(clean["correct_index"])
			clean["difficulty"] = int(clean["difficulty"])
			bank.questions.append(clean)
			bank._by_id[str(q["id"])] = clean
	return bank


## Every problem in the data (empty = valid): schema errors and duplicate ids.
static func validate(data: Variant) -> Array[String]:
	var errors: Array[String] = []
	var entries: Array = _entries(data)
	if entries.is_empty():
		errors.append("no questions")
	var seen: Dictionary[String, bool] = {}
	for i: int in entries.size():
		var q: Variant = entries[i]
		if typeof(q) != TYPE_DICTIONARY:
			errors.append("#%d: not an object" % i)
			continue
		for e: String in validate_question(q):
			errors.append("#%d (%s): %s" % [i, str((q as Dictionary).get("id", "?")), e])
		var id: String = str((q as Dictionary).get("id", ""))
		if seen.has(id):
			errors.append("#%d: duplicate id %s" % [i, id])
		seen[id] = true
	return errors


## Schema problems of one question.
static func validate_question(q: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if typeof(q.get("id")) != TYPE_STRING or str(q["id"]).strip_edges().is_empty():
		errors.append("id must be a non-empty string")
	if not str(q.get("category", "")) in CATEGORIES:
		errors.append("unknown category %s" % q.get("category"))
	var diff: Variant = q.get("difficulty")
	if not (typeof(diff) in [TYPE_INT, TYPE_FLOAT]) or int(diff) != diff or int(diff) < 1 or int(diff) > 3:
		errors.append("difficulty must be 1-3")
	if typeof(q.get("question")) != TYPE_STRING or str(q["question"]).strip_edges().is_empty():
		errors.append("question must be non-empty text")
	var answers: Variant = q.get("answers")
	if typeof(answers) != TYPE_ARRAY or (answers as Array).size() != ANSWER_COUNT:
		errors.append("needs exactly %d answers" % ANSWER_COUNT)
	else:
		var texts: Dictionary[String, bool] = {}
		for a: Variant in answers:
			if typeof(a) != TYPE_STRING or str(a).strip_edges().is_empty():
				errors.append("answers must be non-empty text")
			elif texts.has(str(a)):
				errors.append("duplicate answer %s" % a)
			texts[str(a)] = true
	var ci: Variant = q.get("correct_index")
	if not (typeof(ci) in [TYPE_INT, TYPE_FLOAT]) or int(ci) != ci or int(ci) < 0 or int(ci) >= ANSWER_COUNT:
		errors.append("correct_index must be 0-3")
	return errors


static func _entries(data: Variant) -> Array:
	if typeof(data) == TYPE_DICTIONARY:
		var qs: Variant = (data as Dictionary).get("questions", [])
		return qs if typeof(qs) == TYPE_ARRAY else []
	return data if typeof(data) == TYPE_ARRAY else []


## Number of usable questions.
func size() -> int:
	return questions.size()


## Question by id ({} if unknown).
func get_question(id: String) -> Dictionary:
	return _by_id.get(id, {})


## Picks `count` random questions whose ids are not in `used` and adds their ids to `used`. When
## the bank runs dry, `used` is cleared rather than failing (a very long session).
func pick(count: int, rng: SeededRng, used: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pool: Array = questions.filter(func(q: Dictionary) -> bool: return not used.has(q["id"]))
	if pool.size() < count:
		used.clear()
		pool = questions.duplicate()
	rng.shuffle(pool)
	for i: int in mini(count, pool.size()):
		out.append(pool[i])
		used[pool[i]["id"]] = true
	return out


## A copy of `q` with its answers shuffled; `correct_index` follows the right answer.
static func shuffled_answers(q: Dictionary, rng: SeededRng) -> Dictionary:
	var order: Array = range(ANSWER_COUNT)
	rng.shuffle(order)
	var out: Dictionary = q.duplicate(true)
	var answers: Array = []
	for i: int in order:
		answers.append(q["answers"][i])
	out["answers"] = answers
	out["correct_index"] = order.find(int(q["correct_index"]))
	return out
