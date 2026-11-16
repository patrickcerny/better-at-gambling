class_name SplitOrStealLogic
extends MinigameLogicBase
## "Split or Steal": a game-show tournament where EVERYONE plays EVERYONE, ONE DUEL AT A TIME
## (Patrick 2026-11-16: "N to N like everyone against everyone", "die Duelle sind nacheinander, es
## ist ok wenns länger geht"). Every pair meets once; each duel is its own short show while
## everyone else watches: ROUND (the pair walks up to the podiums) → DECIDE (both secretly lock in
## SPLIT or STEAL; voice is global, so bluff, beg, promise) → REVEAL (both cards flip, points paid).
## (`rounds` holds one entry per duel; a "round" here is one duel on stage.)
##
## Points per duel: both SPLIT = 1 each; STEAL vs SPLIT = 3 for the stealer, 0 for the splitter;
## both STEAL = 0 each. Nobody picking in time counts as SPLIT.
## Ranking: total points, then fewer steals (the nicest player wins ties).
##
## Schedule (`build_rounds`): a full round robin (circle method), the duels ordered so nobody plays
## twice in a row where avoidable. Tiny tables repeat the whole cycle until the show has at least
## `MIN_ROUNDS` duels (2 players: 4 duels against each other; 3 players: every pair twice).
## 4 players = 6 duels, 8 players = 28 duels.
##
## A player who leaves keeps their seat in the schedule: their open duels count as SPLIT for them
## (like a timeout) and only the opponent scores; a duel with both players gone is skipped.

enum State { WAITING, INTRO, ROUND, DECIDE, REVEAL, OUTRO, DONE }

const SPLIT: String = "SPLIT"
const STEAL: String = "STEAL"
const CHOICES: Array[String] = [SPLIT, STEAL]
const POINTS_BOTH_SPLIT: int = 1
const POINTS_STEALER: int = 3
const POINTS_ROBBED: int = 0
const POINTS_BOTH_STEAL: int = 0
## Player id standing in for "nobody" (no opponent, sitting out).
const NOBODY: int = -1
## Most players the schedule is built for (the lobby's maximum).
const MAX_PLAYERS: int = 8
## Tiny tables repeat the round robin until the show has at least this many duels.
const MIN_ROUNDS: int = 4
## Most duels in one show (8 players: 28).
const MAX_ROUNDS: int = MAX_PLAYERS * (MAX_PLAYERS - 1) / 2
const INTRO_TIME: float = 4.0
const ROUND_TIME: float = 2.0
const DECIDE_TIME: float = 12.0
const REVEAL_TIME: float = 4.0
const OUTRO_TIME: float = 4.0
## Longest one duel can take (announce + decide + reveal).
const ROUND_CAP: float = ROUND_TIME + DECIDE_TIME + REVEAL_TIME
## Longest the whole show can take: 4 + 28 × 18 + 4 = 512 s (both locking in early ends a duel sooner).
const GAME_CAP: float = INTRO_TIME + MAX_ROUNDS * ROUND_CAP + OUTRO_TIME

var intro_time: float = INTRO_TIME
var round_time: float = ROUND_TIME
var decide_time: float = DECIDE_TIME
var reveal_time: float = REVEAL_TIME
var outro_time: float = OUTRO_TIME

var state: State = State.WAITING
var timer: float = 0.0
var game_time: float = 0.0
## The show's rounds in order: {duels: [{a, b, result ({} until revealed, see `_score_duel`)}],
## bye: [players sitting this round out]}.
var rounds: Array[Dictionary] = []
## Index of the round being played (-1 before the first one).
var round_index: int = -1
## Duels each player plays in the whole show.
var duels_each: int = 1
## player → SPLIT or STEAL, for the current round only (secret until the reveal).
var choices: Dictionary[int, String] = {}
var points: Dictionary[int, int] = {}
var steals: Dictionary[int, int] = {}
var splits: Dictionary[int, int] = {}
## Everyone who started the show (leavers stay in the schedule, see the class comment).
var roster: Array[int] = []
var _game_cap: float = GAME_CAP
var _ranking: Array[Dictionary] = []


func _on_setup(_context: Dictionary) -> void:
	intro_time = float(params.get("intro_time", intro_time))
	round_time = float(params.get("round_time", round_time))
	decide_time = float(params.get("decide_time", decide_time))
	reveal_time = float(params.get("reveal_time", reveal_time))
	outro_time = float(params.get("outro_time", outro_time))
	roster = players.duplicate()
	for p: int in players:
		points[p] = 0
		steals[p] = 0
		splits[p] = 0
	rounds = build_rounds(players, rng)
	duels_each = duels_per_player(players.size())
	_game_cap = intro_time + rounds.size() * (round_time + decide_time + reveal_time) + outro_time + 2.0 + rounds.size() * 0.5  # ticks overshoot each phase a little
	# Nothing is announced yet: the stage on the clients is built behind the curtain, after the
	# `minigame_started` event, and must not miss the first round. The show starts on the first
	# tick (after the briefing); the snapshot carries the schedule meanwhile.


## How often the round robin runs with `n` players (see the class comment).
static func cycles_for(n: int) -> int:
	if n < 2:
		return 0
	var per_cycle: int = n * (n - 1) / 2
	return ceili(float(MIN_ROUNDS) / float(per_cycle))


## Duels each player plays in a show with `n` players.
static func duels_per_player(n: int) -> int:
	return (n - 1) * cycles_for(n) if n >= 2 else 0


## One entry per duel, in show order: {duels: [{a, b, result}], bye: []}. Every pair meets once
## per cycle; the seating (who meets whom when) is shuffled with `p_rng` when given. Repeated
## cycles swap sides, so the second meeting of a pair isn't a copy of the first.
static func build_rounds(p_roster: Array[int], p_rng: SeededRng) -> Array[Dictionary]:
	var seats: Array = p_roster.duplicate()
	if seats.size() > MAX_PLAYERS:
		seats.resize(MAX_PLAYERS)
	if p_rng != null:
		p_rng.shuffle(seats)
	var n: int = seats.size()
	var out: Array[Dictionary] = []
	if n < 2:
		return out
	var pairs: Array = []
	for c: int in cycles_for(n):
		for r: Array in _circle_rounds(seats):
			for d: Array in r:
				pairs.append([d[0], d[1]] if c % 2 == 0 else [d[1], d[0]])
	for d: Array in _spread(pairs):
		out.append({"duels": [{"a": int(d[0]), "b": int(d[1]), "result": {}}], "bye": []})
	return out


## Round robin by the circle method (a bye seat for odd counts, its pairs dropped): every round is
## an Array of [a, b].
static func _circle_rounds(p_roster: Array) -> Array:
	var seats: Array = p_roster.duplicate()
	if seats.size() % 2 == 1:
		seats.append(NOBODY)
	var n: int = seats.size()
	var out: Array = []
	for r: int in n - 1:
		var pairs: Array = []
		for i: int in n >> 1:
			var a: int = seats[i]
			var b: int = seats[n - 1 - i]
			if a != NOBODY and b != NOBODY:
				pairs.append([a, b] if r % 2 == 0 or i > 0 else [b, a])  # the fixed seat alternates sides
		out.append(pairs)
		var last: Variant = seats.pop_back()
		seats.insert(1, last)
	return out


## Reorders duels so nobody plays twice in a row when that is possible (4+ players), preferring
## whoever has waited longest so nobody sits idle for ages. A depth-first search with that greedy
## order finds a clean sequence almost at once; the greedy order alone is the fallback.
static func _spread(pairs: Array) -> Array:
	var out: Array = []
	var budget: Array[int] = [20000]
	if _spread_dfs(pairs.duplicate(), out, {}, budget):
		return out
	return _spread_greedy(pairs)


static func _ranked(left: Array, prev: Array, last_played: Dictionary) -> Array:
	var idx: Array = range(left.size())
	idx.sort_custom(func(i: int, j: int) -> bool:
		return _wait_score(left[i], prev, last_played) < _wait_score(left[j], prev, last_played))
	return idx


static func _wait_score(p: Array, prev: Array, last_played: Dictionary) -> int:
	var clash: bool = p[0] in prev or p[1] in prev
	return (1 << 20 if clash else 0) + int(last_played.get(p[0], -1)) + int(last_played.get(p[1], -1))


static func _spread_dfs(left: Array, out: Array, last_played: Dictionary, budget: Array[int]) -> bool:
	if left.is_empty():
		return true
	budget[0] -= 1
	if budget[0] < 0:
		return false
	var prev: Array = out.back() if not out.is_empty() else []
	for i: int in _ranked(left, prev, last_played):
		var p: Array = left[i]
		if p[0] in prev or p[1] in prev:
			continue
		var before: Array = [last_played.get(p[0], null), last_played.get(p[1], null)]
		last_played[p[0]] = out.size()
		last_played[p[1]] = out.size()
		out.append(p)
		left.remove_at(i)
		if _spread_dfs(left, out, last_played, budget):
			return true
		left.insert(i, p)
		out.pop_back()
		for k: int in 2:
			if before[k] == null:
				last_played.erase(p[k])
			else:
				last_played[p[k]] = before[k]
	return false


static func _spread_greedy(pairs: Array) -> Array:
	var left: Array = pairs.duplicate()
	var out: Array = []
	var last_played: Dictionary = {}
	while not left.is_empty():
		var prev: Array = out.back() if not out.is_empty() else []
		var pick: int = _ranked(left, prev, last_played)[0]
		var chosen: Array = left[pick]
		last_played[chosen[0]] = out.size()
		last_played[chosen[1]] = out.size()
		out.append(chosen)
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
				_start_round(0)
		State.ROUND:
			if timer <= 0.0:
				_start_decide()
		State.DECIDE:
			if timer <= 0.0 or _all_chosen():
				_reveal()
		State.REVEAL:
			if timer <= 0.0:
				_start_round(round_index + 1)
		State.OUTRO:
			if timer <= 0.0:
				state = State.DONE
				finished = true


func _start_show() -> void:
	state = State.INTRO
	timer = intro_time
	events.append(GameEvents.make(&"split_or_steal_started", {
		"players": roster.duplicate(),
		"rounds": rounds.duplicate(true),
		"duels_each": duels_each,
		"intro_time": intro_time,
		"round_time": round_time,
		"decide_time": decide_time,
		"reveal_time": reveal_time,
	}))
	if rounds.is_empty():
		_finish()


## Starts round `i` (or the next one somebody still present plays in; the end when none is left).
func _start_round(i: int) -> void:
	choices.clear()
	while i < rounds.size() and not _round_playable(i):
		i += 1
	if i >= rounds.size():
		round_index = rounds.size()
		_finish()
		return
	round_index = i
	state = State.ROUND
	timer = round_time
	events.append(GameEvents.make(&"split_or_steal_round", {
		"index": i,
		"total": rounds.size(),
		"duels": (rounds[i]["duels"] as Array).duplicate(true),
		"bye": (rounds[i]["bye"] as Array).duplicate(),
		"round_time": round_time,
		"decide_time": decide_time,
	}))


## A round is worth playing while at least one of its duels still has a player present.
func _round_playable(i: int) -> bool:
	for d: Dictionary in rounds[i]["duels"]:
		if int(d["a"]) in players or int(d["b"]) in players:
			return true
	return false


func _start_decide() -> void:
	state = State.DECIDE
	timer = decide_time
	events.append(GameEvents.make(&"split_or_steal_decide", {"index": round_index, "decide_time": decide_time}))


## The current round's duels (empty between rounds).
func current_duels() -> Array:
	if round_index < 0 or round_index >= rounds.size() or state in [State.WAITING, State.INTRO, State.OUTRO, State.DONE]:
		return []
	return rounds[round_index]["duels"]


## Everyone with a duel this round who is still here.
func active_players() -> Array[int]:
	var out: Array[int] = []
	for d: Dictionary in current_duels():
		for k: String in ["a", "b"]:
			if int(d[k]) in players:
				out.append(int(d[k]))
	return out


func in_duel(player: int) -> bool:
	return opponent_of(player) != NOBODY


## `player`'s opponent this round (NOBODY when sitting out or between rounds).
func opponent_of(player: int) -> int:
	for d: Dictionary in current_duels():
		if int(d["a"]) == player:
			return int(d["b"])
		if int(d["b"]) == player:
			return int(d["a"])
	return NOBODY


func _all_chosen() -> bool:
	for p: int in active_players():
		if not choices.has(p):
			return false
	return true


## Points for one duel, from A's and B's choices: [points_a, points_b].
static func payoff(choice_a: String, choice_b: String) -> Array[int]:
	if choice_a == SPLIT and choice_b == SPLIT:
		return [POINTS_BOTH_SPLIT, POINTS_BOTH_SPLIT]
	if choice_a == STEAL and choice_b == STEAL:
		return [POINTS_BOTH_STEAL, POINTS_BOTH_STEAL]
	if choice_a == STEAL:
		return [POINTS_STEALER, POINTS_ROBBED]
	return [POINTS_ROBBED, POINTS_STEALER]


func _reveal() -> void:
	state = State.REVEAL
	timer = reveal_time
	var results: Array = []
	for d: Dictionary in current_duels():
		var r: Dictionary = _score_duel(d)
		d["result"] = r
		results.append(r)
	events.append(GameEvents.make(&"split_or_steal_reveal", {
		"index": round_index,
		"results": results.duplicate(true),
		"points": points.duplicate(),
		"steals": steals.duplicate(),
	}))


## Scores one duel. A missing pick counts as SPLIT (`auto_*` = true); a player who left scores
## nothing (`gone_*` = true).
func _score_duel(d: Dictionary) -> Dictionary:
	var a: int = d["a"]
	var b: int = d["b"]
	var ca: String = choices.get(a, SPLIT)
	var cb: String = choices.get(b, SPLIT)
	var pts: Array[int] = payoff(ca, cb)
	var gone: Array[bool] = [a not in players, b not in players]
	for side: Array in [[a, ca, pts[0], gone[0]], [b, cb, pts[1], gone[1]]]:
		var p: int = side[0]
		if bool(side[3]) or not points.has(p):
			continue
		points[p] += int(side[2])
		if side[1] == STEAL:
			steals[p] += 1
		else:
			splits[p] += 1
	return {
		"a": a, "b": b,
		"choice_a": ca, "choice_b": cb,
		"points_a": 0 if gone[0] else pts[0], "points_b": 0 if gone[1] else pts[1],
		"auto_a": not choices.has(a), "auto_b": not choices.has(b),
		"gone_a": gone[0], "gone_b": gone[1],
	}


func _finish() -> void:
	state = State.OUTRO
	timer = outro_time
	choices.clear()
	_ranking = _compute_ranking()
	events.append(GameEvents.make(&"split_or_steal_finished", {"ranking": _ranking.duplicate(true), "points": points.duplicate(), "steals": steals.duplicate()}))


## Accepts {choice: "SPLIT" | "STEAL"} during DECIDE from anyone with a duel this round.
func submit(player: int, intent: Dictionary, _now: float) -> Dictionary:
	if player not in players:
		return StationLogicBase.fail(&"unknown_player")
	if state == State.OUTRO or state == State.DONE:
		return StationLogicBase.fail(&"game_over")
	if state != State.DECIDE:
		return StationLogicBase.fail(&"not_decide_phase")
	if not in_duel(player):
		return StationLogicBase.fail(&"not_your_turn")  # sitting this round out
	if choices.has(player):
		return StationLogicBase.fail(&"already_chose")
	var choice: String = str(intent.get("choice", "")).to_upper()
	if choice not in CHOICES:
		return StationLogicBase.fail(&"invalid_choice")
	choices[player] = choice
	# Public: only THAT they locked in, never what.
	events.append(GameEvents.make(&"split_or_steal_locked", {"index": round_index, "player": player}))
	return StationLogicBase.OK_RESULT


## A leaver's pick is dropped: their open duels count as SPLIT and score only for the opponent.
func remove_player(player: int) -> void:
	super.remove_player(player)
	choices.erase(player)


func ranking() -> Array[Dictionary]:
	if _ranking.is_empty():
		return _compute_ranking()
	return _ranking


## Points high → low, then steals low → high (nicest wins); equal on both shares a rank. `points`
## is the game score (0-3 per duel), like Lonely Number's round wins.
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


## Everything a late joiner needs to draw the show: every round with the revealed results, the
## round being played, who locked in (never what), the running totals.
func get_public_state() -> Dictionary:
	var st: Dictionary = {
		"minigame": &"split_or_steal",
		"players": roster.duplicate(),
		"state": state,
		"timer": snappedf(maxf(timer, 0.0), 0.01),
		"index": round_index,
		"total": rounds.size(),
		"rounds": rounds.duplicate(true),
		"duels_each": duels_each,
		"round_time": round_time,
		"decide_time": decide_time,
		"reveal_time": reveal_time,
		"points": points.duplicate(),
		"steals": steals.duplicate(),
		"locked": choices.keys(),
	}
	if state == State.OUTRO or state == State.DONE:
		st["ranking"] = _ranking.duplicate(true)
	return st


## Our seat in the show. Sent every frame, so it also carries the round being played: a stage
## that missed an event (built behind the curtain, a dropped packet) catches up from it.
func private_state(player: int) -> Dictionary:
	var live: bool = not current_duels().is_empty()
	var opp: int = opponent_of(player)
	return {
		"index": round_index,
		"state": state,
		"timer": snappedf(maxf(timer, 0.0), 0.01),
		"duels": (current_duels() as Array).duplicate(true) if live else [],
		"bye": (rounds[round_index]["bye"] as Array).duplicate() if live else [],
		"opponent": opp,
		"can_choose": state == State.DECIDE and opp != NOBODY and not choices.has(player),
		"my_choice": choices.get(player, ""),
		"current_score": points.get(player, 0),
	}
