class_name SpyLogic
extends MinigameLogicBase
## "Spy" minigame (a panel game of social deduction, min 4 players). The server draws a secret
## word from `data/minigames/spy_words.json` (a place or a job) and picks the spies: 1 for 4-5
## players, 2 for 6-8. Everyone else gets the word in their PRIVATE state; spies only get its
## category, plus the hint once the game clock has run for HINT_AFTER seconds. Nothing secret is
## ever in an event or the public state until the game is over.
##
## Flow: INTRO → CLUES (in seat order every player types one clue word, CLUE_TIME each; a turn
## that runs out records no clue) for CLUE_ROUNDS rounds → OPEN (the floor is open: talk on voice,
## call a vote) until the clock runs out. Any player still in the game can call a vote at any
## time in CLUES or OPEN (CALL_COOLDOWN after the last one): VOTE (VOTE_TIME, everyone still in
## picks a player, not themselves; ends early once all voted) → REVEAL. A player is voted out
## when they alone have the most votes and at least half of the players still in voted for them
## (ties or fewer: nobody). A civilian voted out → the spies win at once; every spy out → the
## group wins. A failed vote (nobody out) earns ONE extra clue round per game, so games end.
## The game clock (SECONDS_PER_PLAYER × players at the start) runs in CLUES, OPEN and VOTE; when
## it is out (a running vote still resolves first) the spies win.
##
## Clues are sanitised here: trimmed, control characters removed, at most CLUE_MAX characters; a
## civilian's clue containing the secret word is refused (`is_the_word`; a spy who happens to
## type it is let through, a refusal would tell them the word).
##
## Ranking: the winning side first, then the losing side (shared rank inside a side, except: on a
## spy win, spies never voted on rank above spies who got votes, who rank above caught spies; on
## a group win, civilians who voted for the caught spy in the decisive vote rank above the rest).
## Points are small game points by tier (3/2/1 for the winners, 0 for the losers). Dropouts: a
## spy dropping out counts as caught; anyone who drops out leaves the ranking.

enum Step { INTRO, CLUES, OPEN, VOTE, REVEAL, OUTRO, DONE }

const PHASE_NAMES: Array[String] = ["intro", "clues", "open", "vote", "reveal", "over", "over"]
const WORDS_PATH: String = "res://data/minigames/spy_words.json"
const INTRO_TIME: float = 1.5
const CLUE_TIME: float = 12.0
const VOTE_TIME: float = 15.0
const REVEAL_TIME: float = 4.5
const OUTRO_TIME: float = 6.0
const SECONDS_PER_PLAYER: float = 30.0
## Game-clock seconds after which the spies see the hint.
const HINT_AFTER: float = 60.0
const CLUE_MAX: int = 16
## Regular clue rounds (a failed vote adds one more, once).
const CLUE_ROUNDS: int = 2
## After a vote, how long before the next one can be called.
const CALL_COOLDOWN: float = 4.0
## Points by tier on the winning side (tier 0 best); the losing side scores 0.
const WIN_POINTS: Array[int] = [3, 2, 1]

const SIDE_SPIES: String = "spies"
const SIDE_GROUP: String = "group"

var phase: Step = Step.INTRO
var timer: float = 0.0
## Everyone at the table in seat order (dropouts stay here, they leave `players`).
var seats: Array[int] = []
var spies: Array[int] = []
## Spies voted out or dropped out.
var caught: Array[int] = []
## {word, category, hint}.
var secret: Dictionary = {}
var clock_total: float = 0.0
var clock_left: float = 0.0
var hint_given: bool = false
var round_index: int = 0
var rounds_planned: int = CLUE_ROUNDS
var extra_used: bool = false
## Seat index the clue rounds start from (server-picked).
var start_seat: int = 0
var speaker: int = -1
var turn_queue: Array[int] = []
## player → their clues in order: [{round, text}] ("" = the turn ran out).
var clues: Dictionary[int, Array] = {}
## The current vote: who called it and voter → target.
var caller: int = -1
var votes: Dictionary[int, int] = {}
var vote_count: int = 0
## Step and speaker to go back to after a vote.
var _resume: Step = Step.CLUES
var cooldown: float = 0.0
## Players who got at least one vote in a resolved vote.
var voted_on: Dictionary[int, bool] = {}
var last_result: Dictionary = {}
var winner: String = ""
var reason: String = ""
## The vote that caught the last spy (voter → target), and that spy.
var decisive_votes: Dictionary = {}
var decisive_out: int = -1
var _ranking: Array[Dictionary] = []


static func spy_count_for(n: int) -> int:
	return 2 if n >= 6 else 1


## Votes needed to vote someone out: at least half of the `alive_count` players still in.
static func votes_needed(alive_count: int) -> int:
	return maxi(ceili(float(alive_count) / 2.0), 1)


## The word bank: [{word, category, hint}] (read once per game, it is small).
static func word_bank() -> Array:
	var out: Array = []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(WORDS_PATH))
	if data is Array:
		for row: Variant in data:
			if row is Dictionary and str(row.get("word", "")) != "":
				out.append(row)
	return out


## Trims a typed clue to one line of at most CLUE_MAX characters.
static func sanitize_clue(raw: Variant) -> String:
	var s: String = str(raw) if raw != null else ""
	var out: String = ""
	for i: int in s.length():
		var c: int = s.unicode_at(i)
		out += " " if c < 32 or c == 127 else s[i]
	out = out.strip_edges()
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.left(CLUE_MAX).strip_edges()


## True when `clue` contains `word` (letters and digits only, any case).
static func mentions_word(clue: String, word: String) -> bool:
	var w: String = _plain(word)
	return w != "" and _plain(clue).contains(w)


static func _plain(s: String) -> String:
	var out: String = ""
	for ch: String in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch.unicode_at(0) > 127:
			out += ch
	return out


func _on_setup(context: Dictionary) -> void:
	seats = players.duplicate()
	var bank: Array = context.get("spy_words", params.get("spy_words", word_bank()))
	secret = (bank[rng.range_int(0, bank.size() - 1)] as Dictionary).duplicate() if not bank.is_empty() else {"word": "Vault", "category": "Places", "hint": "A thick steel door"}
	var pool: Array = seats.duplicate()
	rng.shuffle(pool)
	var n: int = mini(spy_count_for(seats.size()), maxi(seats.size() - 1, 1))
	for i: int in mini(n, pool.size()):
		spies.append(int(pool[i]))
	spies.sort()
	start_seat = rng.range_int(0, maxi(seats.size() - 1, 0))
	for p: int in seats:
		clues[p] = []
	clock_total = SECONDS_PER_PLAYER * float(seats.size())
	clock_left = clock_total
	phase = Step.INTRO
	timer = INTRO_TIME
	events.append(GameEvents.make(&"spy_started", {"players": players.duplicate(), "seats": seats.duplicate(), "spy_count": spies.size(),
		"clock": clock_total, "clue_time": CLUE_TIME, "vote_time": VOTE_TIME, "hint_after": HINT_AFTER, "clue_max": CLUE_MAX}))


func is_spy(p: int) -> bool:
	return p in spies


## Players still in the game (not voted out, not dropped), in seat order.
func alive() -> Array[int]:
	var out: Array[int] = []
	for p: int in seats:
		if p in players and not p in caught:
			out.append(p)
	return out


func tick(delta: float, _now: float) -> void:
	if phase == Step.DONE:
		return
	if players.is_empty() and phase != Step.OUTRO:
		_finish()
		return
	if phase in [Step.CLUES, Step.OPEN, Step.VOTE]:
		clock_left = maxf(clock_left - delta, 0.0)
		cooldown = maxf(cooldown - delta, 0.0)
		if not hint_given and clock_total - clock_left >= HINT_AFTER:
			hint_given = true
			events.append(GameEvents.make(&"spy_hint", {"clock": snappedf(clock_left, 0.01)}))
	timer -= delta
	match phase:
		Step.INTRO:
			if timer <= 0.0:
				_start_round(0)
		Step.CLUES, Step.OPEN:
			if clock_left <= 0.0:
				_decide(SIDE_SPIES, "clock")
				_finish()
			elif phase == Step.CLUES and timer <= 0.0:
				_record_clue(speaker, "", true)
		Step.VOTE:
			if timer <= 0.0 or _everyone_voted():
				_resolve_vote()
		Step.REVEAL:
			if timer <= 0.0:
				_after_reveal()
		Step.OUTRO:
			if timer <= 0.0:
				phase = Step.DONE
				finished = true


## Intents by type: `spy_clue` {text}, `spy_call_vote`, `spy_vote` {target}.
func submit(player: int, intent: Dictionary, _now: float) -> Dictionary:
	if not player in players:
		return StationLogicBase.fail(&"not_in_minigame")
	match StringName(str(intent.get("type", ""))):
		&"spy_clue":
			return submit_clue(player, intent.get("text", ""))
		&"spy_call_vote":
			return call_vote(player)
		&"spy_vote":
			var t: Variant = intent.get("target", -1)
			if not (typeof(t) in [TYPE_INT, TYPE_FLOAT]):
				return StationLogicBase.fail(&"bad_value")
			return cast_vote(player, int(t))
	return StationLogicBase.fail(&"bad_value")


func submit_clue(player: int, raw: Variant) -> Dictionary:
	if phase != Step.CLUES or player != speaker:
		return StationLogicBase.fail(&"not_your_turn")
	var text: String = sanitize_clue(raw)
	if text == "":
		return StationLogicBase.fail(&"empty_clue")
	if not is_spy(player) and mentions_word(text, str(secret.get("word", ""))):
		return StationLogicBase.fail(&"is_the_word")
	_record_clue(player, text, false)
	return StationLogicBase.OK_RESULT


func call_vote(player: int) -> Dictionary:
	if not phase in [Step.CLUES, Step.OPEN]:
		return StationLogicBase.fail(&"too_late" if phase in [Step.OUTRO, Step.DONE] else &"not_now")
	if not player in alive():
		return StationLogicBase.fail(&"out")
	if cooldown > 0.0:
		return StationLogicBase.fail(&"cooldown")
	_resume = phase
	phase = Step.VOTE
	timer = VOTE_TIME
	caller = player
	votes.clear()
	vote_count += 1
	events.append(GameEvents.make(&"spy_vote_called", {"by": player, "seconds": VOTE_TIME, "alive": alive(), "needed": votes_needed(alive().size()),
		"clock": snappedf(clock_left, 0.01), "vote": vote_count}))
	return StationLogicBase.OK_RESULT


func cast_vote(player: int, target: int) -> Dictionary:
	if phase != Step.VOTE:
		return StationLogicBase.fail(&"no_vote")
	var still_in: Array[int] = alive()
	if not player in still_in:
		return StationLogicBase.fail(&"out")
	if votes.has(player):
		return StationLogicBase.fail(&"already_voted")
	if target == player or not target in still_in:
		return StationLogicBase.fail(&"bad_target")
	votes[player] = target
	events.append(GameEvents.make(&"spy_voted", {"player": player, "count": votes.size(), "alive": still_in.size()}))
	return StationLogicBase.OK_RESULT


func remove_player(player: int) -> void:
	super.remove_player(player)
	turn_queue.erase(player)
	votes.erase(player)
	for v: int in votes.keys():
		if votes[v] == player:
			votes.erase(v)  # their vote is void: they may vote again
	if is_spy(player) and not player in caught:
		caught.append(player)  # a spy who runs counts as caught
	if winner != "":
		if not _ranking.is_empty():
			_ranking = _rank()
		return
	if phase in [Step.INTRO, Step.CLUES, Step.OPEN, Step.VOTE, Step.REVEAL]:
		if _spies_left().is_empty():
			_decide(SIDE_GROUP, "spies_left")
			_finish()
		elif _civilians_left().is_empty():
			_decide(SIDE_SPIES, "group_left")
			_finish()
		elif phase == Step.CLUES and speaker == player:
			_next_turn()


func ranking() -> Array[Dictionary]:
	return _ranking


func get_public_state() -> Dictionary:
	var clue_lists: Dictionary = {}
	for p: int in clues:
		var texts: Array = []
		for c: Variant in clues[p]:
			texts.append(str((c as Dictionary)["text"]))
		clue_lists[p] = texts
	var st: Dictionary = {"minigame": &"spy", "phase": PHASE_NAMES[phase], "players": players.duplicate(), "seats": seats.duplicate(),
		"alive": alive(), "caught": caught.duplicate(), "spy_count": spies.size(), "clock": snappedf(clock_left, 0.01),
		"clock_total": clock_total, "round": round_index, "rounds": rounds_planned, "speaker": speaker if phase == Step.CLUES else -1,
		"timer": snappedf(maxf(timer, 0.0), 0.01), "clue_time": CLUE_TIME, "vote_time": VOTE_TIME, "clues": clue_lists,
		"cooldown": snappedf(cooldown, 0.01), "hint_given": hint_given, "clue_max": CLUE_MAX}
	if phase == Step.VOTE:
		st["vote"] = {"by": caller, "voted": votes.keys(), "needed": votes_needed(alive().size()), "vote": vote_count}
	if phase in [Step.REVEAL, Step.OUTRO, Step.DONE] and not last_result.is_empty():
		st["result"] = last_result.duplicate(true)
	if phase in [Step.OUTRO, Step.DONE]:
		st.merge(_end_info())
	return st


func private_state(player: int) -> Dictionary:
	if not player in seats:
		return {"role": ""}
	var out: Dictionary = {"role": "spy" if is_spy(player) else "civilian", "category": str(secret.get("category", ""))}
	if not is_spy(player):
		out["word"] = str(secret.get("word", ""))
	elif hint_given:
		out["hint"] = str(secret.get("hint", ""))
	var still_in: bool = player in alive()
	out["in"] = still_in
	out["my_turn"] = phase == Step.CLUES and speaker == player
	out["can_call"] = still_in and phase in [Step.CLUES, Step.OPEN] and cooldown <= 0.0
	out["can_vote"] = still_in and phase == Step.VOTE and not votes.has(player)
	out["voted_for"] = votes.get(player, -1) if phase == Step.VOTE else -1
	return out


# --- Clue turns ----------------------------------------------------------------------------------

func _start_round(r: int) -> void:
	round_index = r
	turn_queue.clear()
	var n: int = seats.size()
	for i: int in n:
		var p: int = seats[(start_seat + i) % n]
		if p in alive():
			turn_queue.append(p)
	phase = Step.CLUES
	events.append(GameEvents.make(&"spy_round", {"round": r, "rounds": rounds_planned, "order": turn_queue.duplicate()}))
	_next_turn()


func _next_turn() -> void:
	var still_in: Array[int] = alive()
	while not turn_queue.is_empty() and not turn_queue[0] in still_in:
		turn_queue.pop_front()
	if turn_queue.is_empty():
		speaker = -1
		if round_index + 1 < rounds_planned:
			_start_round(round_index + 1)
		else:
			_open_floor()
		return
	speaker = turn_queue.pop_front()
	phase = Step.CLUES
	timer = CLUE_TIME
	events.append(GameEvents.make(&"spy_turn", {"player": speaker, "round": round_index, "seconds": CLUE_TIME, "clock": snappedf(clock_left, 0.01)}))


func _open_floor() -> void:
	phase = Step.OPEN
	speaker = -1
	timer = 0.0
	events.append(GameEvents.make(&"spy_open", {"clock": snappedf(clock_left, 0.01)}))


func _record_clue(player: int, text: String, timed_out: bool) -> void:
	if clues.has(player):
		clues[player].append({"round": round_index, "text": text})
	events.append(GameEvents.make(&"spy_clue", {"player": player, "text": text, "round": round_index, "timed_out": timed_out}))
	_next_turn()


# --- Votes ---------------------------------------------------------------------------------------

func _everyone_voted() -> bool:
	for p: int in alive():
		if not votes.has(p):
			return false
	return true


func _resolve_vote() -> void:
	var still_in: Array[int] = alive()
	var counts: Dictionary = {}
	for v: int in votes:
		var t: int = votes[v]
		if t in still_in:
			counts[t] = int(counts.get(t, 0)) + 1
			voted_on[t] = true
	var needed: int = votes_needed(still_in.size())
	var top: int = 0
	var leaders: Array[int] = []
	for t: Variant in counts:
		var c: int = int(counts[t])
		if c > top:
			top = c
			leaders = [int(t)]
		elif c == top:
			leaders.append(int(t))
	var out: int = leaders[0] if leaders.size() == 1 and top >= needed else -1
	var was_spy: bool = out >= 0 and is_spy(out)
	var why: String = "none" if counts.is_empty() else ("tie" if leaders.size() > 1 else ("short" if out < 0 else "out"))
	if out >= 0 and was_spy:
		caught.append(out)
		if _spies_left().is_empty():
			decisive_votes = votes.duplicate()
			decisive_out = out
			_decide(SIDE_GROUP, "caught")
	elif out >= 0:
		_decide(SIDE_SPIES, "wrong_vote")
	last_result = {"vote": vote_count, "by": caller, "votes": votes.duplicate(), "counts": counts, "needed": needed, "alive": still_in.size(),
		"out": out, "was_spy": was_spy, "why": why, "spies_left": _spies_left().size(), "decided": winner}
	phase = Step.REVEAL
	timer = REVEAL_TIME
	events.append(GameEvents.make(&"spy_vote_result", last_result.duplicate(true)))


func _after_reveal() -> void:
	if winner == "" and clock_left <= 0.0:
		_decide(SIDE_SPIES, "clock")
	if winner != "":
		_finish()
		return
	cooldown = CALL_COOLDOWN
	if int(last_result.get("out", -1)) < 0 and not extra_used:
		extra_used = true
		rounds_planned += 1
	if _resume == Step.CLUES and speaker in alive():
		phase = Step.CLUES
		timer = CLUE_TIME  # the speaker gets a fresh turn
		events.append(GameEvents.make(&"spy_turn", {"player": speaker, "round": round_index, "seconds": CLUE_TIME, "clock": snappedf(clock_left, 0.01)}))
	elif _resume == Step.CLUES:
		_next_turn()
	elif round_index + 1 < rounds_planned:
		_start_round(round_index + 1)
	else:
		_open_floor()


func _spies_left() -> Array[int]:
	var out: Array[int] = []
	for p: int in spies:
		if p in players and not p in caught:
			out.append(p)
	return out


func _civilians_left() -> Array[int]:
	var out: Array[int] = []
	for p: int in alive():
		if not is_spy(p):
			out.append(p)
	return out


# --- The end -------------------------------------------------------------------------------------

func _decide(side: String, why: String) -> void:
	if winner == "":
		winner = side
		reason = why


func _end_info() -> Dictionary:
	return {"winner": winner, "reason": reason, "spies": spies.duplicate(), "caught": caught.duplicate(), "word": str(secret.get("word", "")),
		"category": str(secret.get("category", "")), "hint": str(secret.get("hint", "")), "ranking": _ranking.duplicate(true),
		"decisive_votes": decisive_votes.duplicate(), "decisive_out": decisive_out}


func _finish() -> void:
	if winner == "":
		_decide(SIDE_SPIES, "clock")
	phase = Step.OUTRO
	timer = OUTRO_TIME
	speaker = -1
	_ranking = _rank()
	events.append(GameEvents.make(&"spy_over", _end_info()))


## Tier inside the winning side (0 best).
func _tier(p: int) -> int:
	if is_spy(p):
		if p in caught:
			return 2
		return 1 if voted_on.has(p) else 0
	if decisive_out >= 0 and int(decisive_votes.get(p, -1)) != decisive_out:
		return 1
	return 0


func _rank() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for p: int in players:
		var won: bool = is_spy(p) == (winner == SIDE_SPIES)
		var tier: int = _tier(p) if won else 0
		rows.append({"player": p, "side": SIDE_SPIES if is_spy(p) else SIDE_GROUP, "won": won, "tier": tier,
			"points": WIN_POINTS[tier] if won else 0, "spy": is_spy(p)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["won"] != b["won"]:
			return a["won"]
		if a["tier"] != b["tier"]:
			return a["tier"] < b["tier"]
		return a["player"] < b["player"])
	for i: int in rows.size():
		var same: bool = i > 0 and rows[i]["won"] == rows[i - 1]["won"] and rows[i]["tier"] == rows[i - 1]["tier"]
		rows[i]["rank"] = rows[i - 1]["rank"] if same else i + 1
	return rows
