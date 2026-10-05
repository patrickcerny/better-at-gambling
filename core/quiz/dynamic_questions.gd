class_name DynamicQuestions
extends RefCounted
## Quiz questions generated from the running match (§2.9). Pure: takes a stats dictionary
## `{players: {id: {name, balance, won_by_game: {game_id: int}}}, game_names: {game_id: String}}`
## and returns a question in the bank's schema (with `dynamic: true`), or {} if the match has
## nothing to ask about yet.

const TEMPLATES: Array[StringName] = [&"most_won_at", &"leader_money"]
## Fillers when fewer than four players are in the match.
const FILLER_NAMES: Array[String] = ["Lucky the dealer cat", "The house", "Nobody, sadly"]


## Tries the templates in random order and returns the first that works.
static func generate(stats: Dictionary, rng: SeededRng) -> Dictionary:
	var order: Array = TEMPLATES.duplicate()
	rng.shuffle(order)
	for t: StringName in order:
		var q: Dictionary = make(t, stats, rng)
		if not q.is_empty():
			return q
	return {}


## One template. {} when it has no clear answer (no wins yet, a tie).
static func make(template: StringName, stats: Dictionary, rng: SeededRng) -> Dictionary:
	match template:
		&"most_won_at":
			return _most_won_at(stats, rng)
		&"leader_money":
			return _leader_money(stats, rng)
	return {}


static func _most_won_at(stats: Dictionary, rng: SeededRng) -> Dictionary:
	var players: Dictionary = stats.get("players", {})
	var games: Array = []
	for pid: Variant in players:
		for g: Variant in players[pid].get("won_by_game", {}):
			if int(players[pid]["won_by_game"][g]) > 0 and not g in games:
				games.append(g)
	games.sort()
	rng.shuffle(games)
	for g: Variant in games:
		var best: int = -1
		var best_amount: int = 0
		var tie: bool = false
		for pid: Variant in players:
			var amount: int = int(players[pid].get("won_by_game", {}).get(g, 0))
			if amount > best_amount:
				best_amount = amount
				best = int(pid)
				tie = false
			elif amount == best_amount and amount > 0:
				tie = true
		if best < 0 or tie:
			continue
		var names: Array = []
		var correct_name: String = str(players[best]["name"])
		var others: Array = []
		for pid: Variant in players:
			if int(pid) != best:
				others.append(str(players[pid]["name"]))
		rng.shuffle(others)
		names.append(correct_name)
		for n: Variant in others:
			if names.size() < 4 and not n in names:
				names.append(n)
		for n: String in FILLER_NAMES:
			if names.size() < 4 and not n in names:
				names.append(n)
		if names.size() < 4:
			continue
		var game_name: String = str(stats.get("game_names", {}).get(g, str(g).capitalize()))
		return {"id": "dyn_most_won_%s" % g, "category": "casino_trivia", "difficulty": 2, "dynamic": true,
			"question": "Who has won the most at %s so far?" % game_name, "answers": names, "correct_index": 0,
			"explanation": "%s is up $%d at %s." % [correct_name, best_amount, game_name]}
	return {}


static func _leader_money(stats: Dictionary, rng: SeededRng) -> Dictionary:
	var players: Dictionary = stats.get("players", {})
	if players.is_empty():
		return {}
	var top: int = -1
	var top_money: int = -1
	for pid: Variant in players:
		var m: int = int(players[pid].get("balance", 0))
		if m > top_money:
			top_money = m
			top = int(pid)
	if top_money <= 0:
		return {}
	# Distractors 15-45 % away with the same last digit (so the exact amount doesn't stand out), at
	# least $40 apart from every other option, never negative.
	var options: Array[int] = [top_money]
	var guard: int = 0
	while options.size() < 4 and guard < 200:
		guard += 1
		var factor: float = rng.range_float(0.15, 0.45) * (1.0 if rng.chance(0.5) else -1.0)
		var v: int = top_money + int(roundf(top_money * factor / 10.0)) * 10
		if v <= 0:
			continue
		if options.all(func(o: int) -> bool: return absi(o - v) >= 40):
			options.append(v)
	if options.size() < 4:
		return {}
	var answers: Array = []
	for v: int in options:
		answers.append("$%d" % v)
	return {"id": "dyn_leader_money", "category": "casino_trivia", "difficulty": 2, "dynamic": true,
		"question": "How much money does the current leader have?", "answers": answers, "correct_index": 0,
		"explanation": "%s leads with $%d." % [str(players[top]["name"]), top_money]}
