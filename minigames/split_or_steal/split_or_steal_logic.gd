class_name SplitOrStealLogic
extends MinigameLogicBase
## "Split or Steal": a game show where the players are drawn into a schedule of pairs that play
## ONE AT A TIME on the stage while everyone else watches. Each match: ANNOUNCE (the pair walks up
## to the podiums), DECIDE (both secretly lock in SPLIT or STEAL; voice is global, so bluff, beg,
## promise), REVEAL (both choices flip up, points paid).
##
## Points per match: both SPLIT = 1 each; STEAL vs SPLIT = 3 for the stealer, 0 for the splitter;
## both STEAL = 0 each. Nobody picking in time counts as SPLIT.
## Ranking: total points, then fewer steals (the nicest player wins ties).
##
## Schedule (`build_schedule`): everyone plays the same number of SCORED matches, `matches_each`
## = 8 / players (at least 1), so the show never runs more than `MAX_PAIRS` matches:
##   2 players: the same pair plays 4 times (an iterated dilemma),
##   3 players: a round robin (3 matches, everyone plays twice),
##   4 players: two round-robin rounds (4 matches, two different opponents each),
##   5-8 players: everyone plays once.
## With an odd count (5, 7) the leftover player still gets their match: a random earlier player
## steps in "for the house" in a last bonus match. The stand-in's choice decides the payoff, but
## only the leftover scores; the stand-in's points and steals from it don't count. A bye would
## leave the leftover on 0 points (last place by default) and a normal extra match would give the
## stand-in a second chance to score, so this is the variant the points ranking keeps fair.

enum State { WAITING, INTRO, ANNOUNCE, DECIDE, REVEAL, OUTRO, DONE }

const SPLIT: String = "SPLIT"
const STEAL: String = "STEAL"
const CHOICES: Array[String] = [SPLIT, STEAL]
const POINTS_BOTH_SPLIT: int = 1
const POINTS_STEALER: int = 3
const POINTS_ROBBED: int = 0
const POINTS_BOTH_STEAL: int = 0
## Player id standing in for "nobody" (no stand-in, no current pair).
const NOBODY: int = -1
## Most players the schedule is built for (the lobby's maximum).
const MAX_PLAYERS: int = 8
## Most matches in one show (8 players = 4 pairs).
const MAX_PAIRS: int = 4
const INTRO_TIME: float = 4.0
const ANNOUNCE_TIME: float = 2.5
const DECIDE_TIME: float = 15.0
const REVEAL_TIME: float = 5.0
const OUTRO_TIME: float = 4.0
## Longest one match can take (announce + decide + reveal).
const ROUND_CAP: float = ANNOUNCE_TIME + DECIDE_TIME + REVEAL_TIME
## Longest the whole show can take: 4 + 4 × 22.5 + 4 = 98 s.
const GAME_CAP: float = INTRO_TIME + MAX_PAIRS * ROUND_CAP + OUTRO_TIME

var intro_time: float = INTRO_TIME
var announce_time: float = ANNOUNCE_TIME
var decide_time: float = DECIDE_TIME
var reveal_time: float = REVEAL_TIME
var outro_time: float = OUTRO_TIME

var state: State = State.WAITING
var timer: float = 0.0
var game_time: float = 0.0
## The show's matches in order: {a, b, house (NOBODY or whichever of a / b plays for the house),
## result ({} until revealed, then see `_score_pair`)}.
var schedule: Array[Dictionary] = []
## Index of the match on stage (-1 before the first one).
var pair_index: int = -1
## Scored matches per player (see the class comment).
var matches_each: int = 1
## player → SPLIT or STEAL, for the current match only (secret until the reveal).
var choices: Dictionary[int, String] = {}
var points: Dictionary[int, int] = {}
var steals: Dictionary[int, int] = {}
var splits: Dictionary[int, int] = {}
var _game_cap: float = GAME_CAP
var _ranking: Array[Dictionary] = []


func _on_setup(_context: Dictionary) -> void:
	intro_time = float(params.get("intro_time", intro_time))
	announce_time = float(params.get("announce_time", announce_time))
	decide_time = float(params.get("decide_time", decide_time))
	reveal_time = float(params.get("reveal_time", reveal_time))
	outro_time = float(params.get("outro_time", outro_time))
	for p: int in players:
		points[p] = 0
		steals[p] = 0
		splits[p] = 0
	matches_each = matches_per_player(players.size())
	schedule = build_schedule(players, rng)
	_game_cap = intro_time + schedule.size() * (announce_time + decide_time + reveal_time) + outro_time + 2.0
	# Nothing is announced yet: the stage on the clients is built behind the curtain, after the
	# `minigame_started` event, and must not miss the first match. The show starts on the first
	# tick (after the briefing); the snapshot carries the schedule meanwhile.


## Scored matches each player gets with `n` players.
static func matches_per_player(n: int) -> int:
	return maxi(1, (MAX_PAIRS * 2) / maxi(n, 1))


## The show's matches (see the class comment): player order shuffled with `p_rng` (when given),
## no player twice in a row where avoidable, the house match (odd counts) last.
static func build_schedule(roster: Array[int], p_rng: SeededRng) -> Array[Dictionary]:
	var seats: Array = roster.duplicate()
	if seats.size() > MAX_PLAYERS:
		seats.resize(MAX_PLAYERS)
	if p_rng != null:
		p_rng.shuffle(seats)
	var n: int = seats.size()
	if n < 2:
		return []
	var k: int = matches_per_player(n)
	var pairs: Array = []
	var house_pair: Dictionary = {}
	if n % 2 == 0:
		var rounds: Array = _circle_rounds(seats)
		for r: int in k:
			pairs.append_array(rounds[r % rounds.size()])
	elif k >= n - 1:
		for round_pairs: Array in _circle_rounds(seats):
			pairs.append_array(round_pairs)  # odd round robin: everyone plays n - 1 times
	else:
		for i: int in range(0, n - 1, 2):
			pairs.append([seats[i], seats[i + 1]])
		var leftover: int = seats[n - 1]
		var stand_in: int = seats[p_rng.range_int(0, n - 2) if p_rng != null else 0]
		house_pair = _entry(leftover, stand_in, stand_in)
	var out: Array[Dictionary] = []
	for pair: Array in _spread(pairs):
		out.append(_entry(int(pair[0]), int(pair[1]), NOBODY))
	if not house_pair.is_empty():
		out.append(house_pair)
	return out


static func _entry(a: int, b: int, house: int) -> Dictionary:
	return {"a": a, "b": b, "house": house, "result": {}}


## Round robin by the circle method (a bye seat for odd counts, its pairs dropped): every round is
## an Array of [a, b].
static func _circle_rounds(roster: Array) -> Array:
	var seats: Array = roster.duplicate()
	if seats.size() % 2 == 1:
		seats.append(NOBODY)
	var n: int = seats.size()
	var rounds: Array = []
	for r: int in n - 1:
		var pairs: Array = []
		for i: int in n >> 1:
			var a: int = seats[i]
			var b: int = seats[n - 1 - i]
			if a != NOBODY and b != NOBODY:
				pairs.append([a, b])
		rounds.append(pairs)
		var last: Variant = seats.pop_back()
		seats.insert(1, last)
	return rounds


## Reorders matches so nobody plays twice in a row when another match could go next.
static func _spread(pairs: Array) -> Array:
	var left: Array = pairs.duplicate()
	var out: Array = []
	while not left.is_empty():
		var pick: int = 0
		if not out.is_empty():
			var prev: Array = out.back()
			for i: int in left.size():
				var p: Array = left[i]
				if not (p[0] in prev or p[1] in prev):
					pick = i
					break
		out.append(left[pick])
		left.remove_at(pick)
	return out


func tick(delta: float, _now: float) -> void:
	if state == State.DONE:
		return
	if state == State.WAITING:
		_start_show()
		return
	timer -= delta
	game_time += delta
	if game_time >= _game_cap and state != State.OUTRO:
		_finish()  # safety net: the timers below always end the show well before this
		return
	match state:
		State.INTRO:
			if timer <= 0.0:
				_start_pair(0)
		State.ANNOUNCE:
			if timer <= 0.0:
				_start_decide()
		State.DECIDE:
			if timer <= 0.0 or _all_chosen():
				_reveal()
		State.REVEAL:
			if timer <= 0.0:
				_start_pair(pair_index + 1)
		State.OUTRO:
			if timer <= 0.0:
				state = State.DONE
				finished = true


func _start_show() -> void:
	state = State.INTRO
	timer = intro_time
	events.append(GameEvents.make(&"split_or_steal_started", {
		"players": players.duplicate(),
		"schedule": schedule.duplicate(true),
		"matches_each": matches_each,
		"intro_time": intro_time,
		"announce_time": announce_time,
		"decide_time": decide_time,
		"reveal_time": reveal_time,
	}))
	if schedule.is_empty():
		_finish()


## Puts match `i` on stage (or the next one that can still be played; the end when none can).
func _start_pair(i: int) -> void:
	choices.clear()
	while i < schedule.size() and not _resolve_pair(i):
		i += 1
	if i >= schedule.size():
		pair_index = schedule.size()
		_finish()
		return
	pair_index = i
	state = State.ANNOUNCE
	timer = announce_time
	var e: Dictionary = schedule[i]
	events.append(GameEvents.make(&"split_or_steal_pair", {
		"index": i,
		"total": schedule.size(),
		"a": e["a"], "b": e["b"], "house": e["house"],
		"announce_time": announce_time,
		"decide_time": decide_time,
	}))


## Makes match `i` playable after players left: a missing player (or stand-in) is replaced by a
## stand-in for the house, so whoever is still here gets their match. False = skip it (nobody
## scoring is left, or nobody can step in).
func _resolve_pair(i: int) -> bool:
	var e: Dictionary = schedule[i]
	var a: int = e["a"]
	var b: int = e["b"]
	var house: int = e["house"]
	var scorers: Array[int] = []
	for p: int in [a, b]:
		if p != house and p in players:
			scorers.append(p)
	if scorers.is_empty():
		return false
	if a in players and b in players:
		return true
	var keep: int = scorers[0]
	var candidates: Array = players.filter(func(p: int) -> bool: return p != keep)
	if candidates.is_empty():
		return false
	var stand_in: int = candidates[rng.range_int(0, candidates.size() - 1)] if rng != null else candidates[0]
	schedule[i] = _entry(keep, stand_in, stand_in)
	return true


func _start_decide() -> void:
	state = State.DECIDE
	timer = decide_time
	events.append(GameEvents.make(&"split_or_steal_decide", {"index": pair_index, "decide_time": decide_time}))


## The pair on stage ([a, b]; empty between matches).
func current_pair() -> Array[int]:
	if pair_index < 0 or pair_index >= schedule.size() or state in [State.WAITING, State.INTRO, State.OUTRO, State.DONE]:
		return []
	return [int(schedule[pair_index]["a"]), int(schedule[pair_index]["b"])]


func in_current_pair(player: int) -> bool:
	return player in current_pair()


func _all_chosen() -> bool:
	for p: int in current_pair():
		if p in players and not choices.has(p):
			return false
	return true


## The current opponent of `player` (NOBODY when not on stage).
func opponent_of(player: int) -> int:
	var pair: Array[int] = current_pair()
	if pair.size() < 2 or player not in pair:
		return NOBODY
	return pair[1] if pair[0] == player else pair[0]


## Points for one match, from A's and B's choices: [points_a, points_b].
static func payoff(choice_a: String, choice_b: String) -> Array[int]:
	if choice_a == SPLIT and choice_b == SPLIT:
		return [POINTS_BOTH_SPLIT, POINTS_BOTH_SPLIT]
	if choice_a == STEAL and choice_b == STEAL:
		return [POINTS_BOTH_STEAL, POINTS_BOTH_STEAL]
	if choice_a == STEAL:
		return [POINTS_STEALER, POINTS_ROBBED]
	return [POINTS_ROBBED, POINTS_STEALER]


func _reveal() -> void:
	var pair: Array[int] = current_pair()
	if not (pair[0] in players or pair[1] in players):
		_start_pair(pair_index + 1)  # both left mid-match: nothing to show
		return
	state = State.REVEAL
	timer = reveal_time
	var result: Dictionary = _score_pair()
	schedule[pair_index]["result"] = result
	var ev: Dictionary = result.duplicate()
	ev["index"] = pair_index
	ev["points"] = points.duplicate()
	ev["steals"] = steals.duplicate()
	events.append(GameEvents.make(&"split_or_steal_reveal", ev))


## Scores the current match. A missing pick counts as SPLIT (`auto_*` = true); the house side
## scores nothing (`points_*` 0, no steal or split counted).
func _score_pair() -> Dictionary:
	var e: Dictionary = schedule[pair_index]
	var a: int = e["a"]
	var b: int = e["b"]
	var house: int = e["house"]
	var ca: String = choices.get(a, SPLIT)
	var cb: String = choices.get(b, SPLIT)
	var pts: Array[int] = payoff(ca, cb)
	if a == house:
		pts[0] = 0
	if b == house:
		pts[1] = 0
	for side: Array in [[a, ca, pts[0]], [b, cb, pts[1]]]:
		var p: int = side[0]
		if p == house or not points.has(p):
			continue
		points[p] += int(side[2])
		if side[1] == STEAL:
			steals[p] += 1
		else:
			splits[p] += 1
	return {
		"a": a, "b": b, "house": house,
		"choice_a": ca, "choice_b": cb,
		"points_a": pts[0], "points_b": pts[1],
		"auto_a": not choices.has(a), "auto_b": not choices.has(b),
	}


func _finish() -> void:
	state = State.OUTRO
	timer = outro_time
	choices.clear()
	_ranking = _compute_ranking()
	events.append(GameEvents.make(&"split_or_steal_finished", {"ranking": _ranking.duplicate(true), "points": points.duplicate(), "steals": steals.duplicate()}))


## Accepts {choice: "SPLIT" | "STEAL"} during DECIDE from one of the two players on stage.
func submit(player: int, intent: Dictionary, _now: float) -> Dictionary:
	if player not in players:
		return StationLogicBase.fail(&"unknown_player")
	if state == State.OUTRO or state == State.DONE:
		return StationLogicBase.fail(&"game_over")
	if not in_current_pair(player):
		return StationLogicBase.fail(&"not_your_turn")  # watching this match
	if state != State.DECIDE:
		return StationLogicBase.fail(&"not_decide_phase")
	if choices.has(player):
		return StationLogicBase.fail(&"already_chose")
	var choice: String = str(intent.get("choice", "")).to_upper()
	if choice not in CHOICES:
		return StationLogicBase.fail(&"invalid_choice")
	choices[player] = choice
	# Public: only THAT they locked in, never what.
	events.append(GameEvents.make(&"split_or_steal_locked", {"index": pair_index, "player": player}))
	return StationLogicBase.OK_RESULT


## A leaver's pick is dropped (counts as SPLIT if their match is on); later matches get a stand-in.
func remove_player(player: int) -> void:
	super.remove_player(player)
	choices.erase(player)


func ranking() -> Array[Dictionary]:
	if _ranking.is_empty():
		return _compute_ranking()
	return _ranking


## Points high → low, then steals low → high (nicest wins); equal on both shares a rank. `points`
## is the game score (0-3 per scored match), like Lonely Number's round wins.
func _compute_ranking() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for p: int in players:
		rows.append({"player": p, "points": points.get(p, 0), "steals": steals.get(p, 0), "splits": splits.get(p, 0), "time": 0.0})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["points"] != b["points"]:
			return a["points"] > b["points"]
		if a["steals"] != b["steals"]:
			return a["steals"] < b["steals"]
		return a["player"] < b["player"])
	for i: int in rows.size():
		var tie: bool = i > 0 and rows[i]["points"] == rows[i - 1]["points"] and rows[i]["steals"] == rows[i - 1]["steals"]
		rows[i]["rank"] = rows[i - 1]["rank"] if tie else i + 1
	return rows


## Everything a late joiner needs to draw the show: the schedule with every revealed result, the
## match on stage, who locked in (never what), the running totals.
func get_public_state() -> Dictionary:
	var st: Dictionary = {
		"minigame": &"split_or_steal",
		"players": players.duplicate(),
		"state": state,
		"timer": snappedf(maxf(timer, 0.0), 0.01),
		"index": pair_index,
		"total": schedule.size(),
		"schedule": schedule.duplicate(true),
		"matches_each": matches_each,
		"announce_time": announce_time,
		"decide_time": decide_time,
		"reveal_time": reveal_time,
		"points": points.duplicate(),
		"steals": steals.duplicate(),
		"locked": choices.keys(),
	}
	if state == State.OUTRO or state == State.DONE:
		st["ranking"] = _ranking.duplicate(true)
	return st


## Our seat in the show. Sent every frame, so it also carries the match on stage: a stage that
## missed an event (built behind the curtain, a dropped packet) catches up from it.
func private_state(player: int) -> Dictionary:
	var pair: Array[int] = current_pair()
	var on_stage: bool = player in pair
	return {
		"index": pair_index,
		"state": state,
		"timer": snappedf(maxf(timer, 0.0), 0.01),
		"pair": pair.duplicate(),
		"house": schedule[pair_index]["house"] if not pair.is_empty() else NOBODY,
		"in_pair": on_stage,
		"can_choose": state == State.DECIDE and on_stage and not choices.has(player),
		"my_choice": choices.get(player, ""),
		"current_score": points.get(player, 0),
	}
