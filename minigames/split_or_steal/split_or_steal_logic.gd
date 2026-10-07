class_name SplitOrStealLogic
extends MinigameLogicBase
## "Split or Steal Tournament": a round robin where everyone meets everyone once (capped at
## `max_rounds`). Every round all pairs play at the same time; with an odd count one player sits
## the round out. A round is TALK (voice is global during minigames: bluff, beg, promise), then
## PICK (secretly SPLIT or STEAL), then REVEAL.
##
## Points per match: both SPLIT = 1 each; STEAL vs SPLIT = 3 for the stealer, 0 for the splitter;
## both STEAL = 0 each. Nobody picking in time counts as SPLIT.
## Ranking: total points, then fewer steals (the nicest player wins ties).

enum State { TALK, PICK, REVEAL, OUTRO, DONE }

const SPLIT: String = "SPLIT"
const STEAL: String = "STEAL"
const CHOICES: Array[String] = [SPLIT, STEAL]
const POINTS_BOTH_SPLIT: int = 1
const POINTS_STEALER: int = 3
const POINTS_ROBBED: int = 0
const POINTS_BOTH_STEAL: int = 0
## Player id standing in for "nobody" (the bye slot of an odd round robin).
const BYE: int = -1

var talk_time: float = 8.0
var pick_time: float = 4.0
var reveal_time: float = 2.5
var outro_time: float = 4.0
var max_rounds: int = 5

var state: State = State.TALK
var timer: float = 0.0
## Every round of the tournament: {pairs: Array of [a, b], bye: player or BYE}.
var schedule: Array[Dictionary] = []
var round_index: int = -1
## player → SPLIT or STEAL, for the current round.
var choices: Dictionary[int, String] = {}
var points: Dictionary[int, int] = {}
var steals: Dictionary[int, int] = {}
var splits: Dictionary[int, int] = {}
## Results of the round last revealed (see `_score_round`).
var last_results: Array[Dictionary] = []
var _ranking: Array[Dictionary] = []


func _on_setup(_context: Dictionary) -> void:
	talk_time = float(params.get("talk_time", talk_time))
	pick_time = float(params.get("pick_time", pick_time))
	reveal_time = float(params.get("reveal_time", reveal_time))
	outro_time = float(params.get("outro_time", outro_time))
	max_rounds = int(params.get("max_rounds", max_rounds))
	for p: int in players:
		points[p] = 0
		steals[p] = 0
		splits[p] = 0
	schedule = build_schedule(players, rng, max_rounds)
	events.append(GameEvents.make(&"split_or_steal_started", {
		"players": players.duplicate(),
		"total_rounds": schedule.size(),
		"talk_time": talk_time,
		"pick_time": pick_time,
		"reveal_time": reveal_time,
	}))
	if schedule.is_empty():
		_finish()
	else:
		_start_round(0)


## Round robin by the circle method: player order shuffled with `p_rng` (when given), a BYE added
## for an odd count, the first seat fixed and the others rotating. Every pair meets at most once;
## `cap` > 0 keeps only the first `cap` rounds (7–8 players would otherwise play 7 rounds).
static func build_schedule(roster: Array[int], p_rng: SeededRng, cap: int = 0) -> Array[Dictionary]:
	var seats: Array = roster.duplicate()
	if p_rng != null:
		p_rng.shuffle(seats)
	if seats.size() < 2:
		return []
	if seats.size() % 2 == 1:
		seats.append(BYE)
	var n: int = seats.size()
	var rounds: Array[Dictionary] = []
	for r: int in n - 1:
		var pairs: Array = []
		var bye: int = BYE
		for i: int in n >> 1:
			var a: int = seats[i]
			var b: int = seats[n - 1 - i]
			if a == BYE:
				bye = b
			elif b == BYE:
				bye = a
			else:
				pairs.append([a, b])
		rounds.append({"pairs": pairs, "bye": bye})
		# Rotate everyone but seat 0 one step clockwise.
		var last: Variant = seats.pop_back()
		seats.insert(1, last)
	if cap > 0 and rounds.size() > cap:
		rounds.resize(cap)
	return rounds


func tick(delta: float, _now: float) -> void:
	if state == State.DONE:
		return
	timer -= delta
	match state:
		State.TALK:
			if timer <= 0.0:
				_start_pick()
		State.PICK:
			if timer <= 0.0 or _all_chosen():
				_reveal()
		State.REVEAL:
			if timer <= 0.0:
				if round_index + 1 < schedule.size():
					_start_round(round_index + 1)
				else:
					_finish()
		State.OUTRO:
			if timer <= 0.0:
				state = State.DONE
				finished = true


func _start_round(i: int) -> void:
	round_index = i
	state = State.TALK
	timer = talk_time
	choices.clear()
	var r: Dictionary = schedule[i]
	events.append(GameEvents.make(&"split_or_steal_round", {
		"round": i,
		"total_rounds": schedule.size(),
		"pairs": (r["pairs"] as Array).duplicate(true),
		"bye": r["bye"],
		"talk_time": talk_time,
	}))


func _start_pick() -> void:
	state = State.PICK
	timer = pick_time
	events.append(GameEvents.make(&"split_or_steal_pick", {"round": round_index, "pick_time": pick_time}))


## The pairs of the current round in which both players are still here.
func _live_pairs() -> Array:
	if round_index < 0 or round_index >= schedule.size():
		return []
	return (schedule[round_index]["pairs"] as Array).filter(func(pair: Array) -> bool:
		return int(pair[0]) in players and int(pair[1]) in players)


func _all_chosen() -> bool:
	for pair: Array in _live_pairs():
		if not choices.has(int(pair[0])) or not choices.has(int(pair[1])):
			return false
	return true


## The current opponent of `player` (BYE when sitting out or the opponent left).
func opponent_of(player: int) -> int:
	for pair: Array in _live_pairs():
		if int(pair[0]) == player:
			return int(pair[1])
		if int(pair[1]) == player:
			return int(pair[0])
	return BYE


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
	state = State.REVEAL
	timer = reveal_time
	last_results = _score_round()
	events.append(GameEvents.make(&"split_or_steal_reveal", {
		"round": round_index,
		"results": last_results.duplicate(true),
		"points": points.duplicate(),
		"steals": steals.duplicate(),
	}))


## Scores every live pair of the current round. A missing pick counts as SPLIT (`auto_*` = true).
func _score_round() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pair: Array in _live_pairs():
		var a: int = int(pair[0])
		var b: int = int(pair[1])
		var ca: String = choices.get(a, SPLIT)
		var cb: String = choices.get(b, SPLIT)
		var pts: Array[int] = payoff(ca, cb)
		for side: Array in [[a, ca, pts[0]], [b, cb, pts[1]]]:
			var p: int = side[0]
			points[p] += int(side[2])
			if side[1] == STEAL:
				steals[p] += 1
			else:
				splits[p] += 1
		out.append({
			"player_a": a, "player_b": b,
			"choice_a": ca, "choice_b": cb,
			"points_a": pts[0], "points_b": pts[1],
			"auto_a": not choices.has(a), "auto_b": not choices.has(b),
		})
	return out


func _finish() -> void:
	state = State.OUTRO
	timer = outro_time
	_ranking = _compute_ranking()
	events.append(GameEvents.make(&"split_or_steal_finished", {"ranking": _ranking.duplicate(true)}))


## Accepts {choice: "SPLIT" | "STEAL"} during PICK from a player who is in a pair this round.
func submit(player: int, intent: Dictionary, _now: float) -> Dictionary:
	if player not in players:
		return StationLogicBase.fail(&"unknown_player")
	if state == State.OUTRO or state == State.DONE:
		return StationLogicBase.fail(&"game_over")
	if state != State.PICK:
		return StationLogicBase.fail(&"not_pick_phase")
	if opponent_of(player) == BYE:
		return StationLogicBase.fail(&"sitting_out")
	if choices.has(player):
		return StationLogicBase.fail(&"already_chose")
	var choice: String = str(intent.get("choice", "")).to_upper()
	if choice not in CHOICES:
		return StationLogicBase.fail(&"invalid_choice")
	choices[player] = choice
	# Public: only THAT they locked in, never what.
	events.append(GameEvents.make(&"split_or_steal_locked", {"round": round_index, "player": player}))
	return StationLogicBase.OK_RESULT


func remove_player(player: int) -> void:
	super.remove_player(player)
	choices.erase(player)  # their opponent this round simply has no match left


func ranking() -> Array[Dictionary]:
	if _ranking.is_empty():
		return _compute_ranking()
	return _ranking


## Points high → low, then steals low → high (nicest wins); equal on both shares a rank.
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


func get_public_state() -> Dictionary:
	var st: Dictionary = {
		"minigame": &"split_or_steal",
		"players": players.duplicate(),
		"state": state,
		"timer": snappedf(maxf(timer, 0.0), 0.01),
		"round": round_index,
		"total_rounds": schedule.size(),
		"talk_time": talk_time,
		"pick_time": pick_time,
		"points": points.duplicate(),
		"steals": steals.duplicate(),
		"locked": choices.keys(),
	}
	if round_index >= 0 and round_index < schedule.size():
		st["pairs"] = (schedule[round_index]["pairs"] as Array).duplicate(true)
		st["bye"] = schedule[round_index]["bye"]
	if state == State.REVEAL:
		st["results"] = last_results.duplicate(true)
	if state == State.OUTRO or state == State.DONE:
		st["ranking"] = _ranking.duplicate(true)
	return st


func private_state(player: int) -> Dictionary:
	var opp: int = opponent_of(player)
	return {
		"round": round_index,
		"opponent": opp,
		"in_current_match": opp != BYE,
		"can_choose": state == State.PICK and opp != BYE and not choices.has(player),
		"my_choice": choices.get(player, ""),
		"current_score": points.get(player, 0),
	}
