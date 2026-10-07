class_name LonelyNumberLogic
extends MinigameLogicBase
## "Lonely Number" minigame (§2.9.3): each round every player secretly picks a number from 1 to 20.
## The highest number nobody else picked (the "lonely number") wins the round. After 5 rounds the
## player with the most round wins ranks first; ties go to the higher total of winning numbers.
##
## Flow per round: PICKING (until everyone picked or the timer runs out; players who did not pick
## sit the round out) → REVEAL (everyone's pick is shown for a moment) → next round. The minigame
## finishes after the last reveal so the final result is visible before the ranking screen.

enum State { PICKING, REVEAL, DONE }

const ROUNDS: int = 5
const MIN_NUMBER: int = 1
const MAX_NUMBER: int = 20
## Seconds each player has to pick per round.
const PICK_SECONDS: float = 15.0
## Seconds the round result stays on screen before the next round.
const REVEAL_SECONDS: float = 3.0

var state: State = State.PICKING
## Index of the current round (0-based); equals ROUNDS once the game is over.
var round: int = 0
## Seconds left in the current phase (picking or reveal).
var timer: float = PICK_SECONDS
## player → their secret pick this round.
var picks: Dictionary[int, int] = {}
## player → rounds won.
var wins: Dictionary[int, int] = {}
## player → sum of the numbers they won rounds with (tiebreaker).
var win_totals: Dictionary[int, int] = {}
## Revealed rounds: [{round, picks, lonely_number, winner}].
var history: Array[Dictionary] = []


func _on_setup(_context: Dictionary) -> void:
	for p: int in players:
		wins[p] = 0
		win_totals[p] = 0
	_start_round()


func tick(delta: float, _now: float) -> void:
	if finished:
		return
	timer = maxf(timer - delta, 0.0)
	if timer > 0.0:
		return
	match state:
		State.PICKING:
			_end_round()
		State.REVEAL:
			if round >= ROUNDS:
				_finish()
			else:
				_start_round()


## Accept a player's pick: intent {"number": 1..20}.
func submit(player: int, intent: Dictionary, _now: float) -> Dictionary:
	if player not in players:
		return StationLogicBase.fail(&"unknown_player")
	if finished or round >= ROUNDS:
		return StationLogicBase.fail(&"game_over")
	if state != State.PICKING:
		return StationLogicBase.fail(&"not_picking")
	if player in picks:
		return StationLogicBase.fail(&"already_picked")
	var raw: Variant = intent.get("number", -1)
	if not (raw is int or raw is float):
		return StationLogicBase.fail(&"invalid_number")
	var pick: int = int(raw)
	if pick < MIN_NUMBER or pick > MAX_NUMBER:
		return StationLogicBase.fail(&"invalid_number")
	picks[player] = pick
	events.append(GameEvents.make(&"lonely_number_picked", {"player": player, "round": round}))
	if _everyone_picked():
		_end_round()
	return StationLogicBase.OK_RESULT


## A dropout forfeits their pending pick; the round ends early if everyone left has picked.
func remove_player(player: int) -> void:
	super.remove_player(player)
	picks.erase(player)
	if not finished and state == State.PICKING and not picks.is_empty() and _everyone_picked():
		_end_round()


## The highest number exactly one player picked, or -1 if every number was shared.
static func lonely_number(round_picks: Dictionary) -> int:
	var counts: Dictionary[int, int] = {}
	for p: Variant in round_picks:
		var n: int = int(round_picks[p])
		counts[n] = counts.get(n, 0) + 1
	var best: int = -1
	for n: int in counts:
		if counts[n] == 1 and n > best:
			best = n
	return best


func _everyone_picked() -> bool:
	for p: int in players:
		if p not in picks:
			return false
	return true


func _start_round() -> void:
	state = State.PICKING
	timer = PICK_SECONDS
	picks.clear()
	events.append(GameEvents.make(&"lonely_number_round_started", {"round": round, "rounds": ROUNDS, "seconds": PICK_SECONDS}))


func _end_round() -> void:
	var lonely: int = lonely_number(picks)
	var winner: int = -1
	if lonely > 0:
		for p: int in picks:
			if picks[p] == lonely:
				winner = p
				break
	if winner >= 0:
		wins[winner] = wins.get(winner, 0) + 1
		win_totals[winner] = win_totals.get(winner, 0) + lonely
	var result: Dictionary = {
		"round": round,
		"picks": picks.duplicate(),
		"lonely_number": lonely,
		"winner": winner,
	}
	history.append(result)
	var ev: Dictionary = result.duplicate()
	ev["wins"] = wins.duplicate()
	ev["totals"] = win_totals.duplicate()
	events.append(GameEvents.make(&"lonely_number_round_end", ev))
	picks.clear()
	round += 1
	state = State.REVEAL
	timer = REVEAL_SECONDS


func _finish() -> void:
	state = State.DONE
	timer = 0.0
	finished = true
	events.append(GameEvents.make(&"lonely_number_finished", {"ranking": ranking()}))


## Most round wins first, then higher total of winning numbers. Players equal on both share a rank.
## `points` is the number of round wins; `total` is the tiebreaker.
func ranking() -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for p: int in players:
		ranked.append({"player": p, "points": wins.get(p, 0), "total": win_totals.get(p, 0)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["points"] != b["points"]:
			return a["points"] > b["points"]
		if a["total"] != b["total"]:
			return a["total"] > b["total"]
		return a["player"] < b["player"]
	)
	for i: int in ranked.size():
		var e: Dictionary = ranked[i]
		if i > 0 and e["points"] == ranked[i - 1]["points"] and e["total"] == ranked[i - 1]["total"]:
			e["rank"] = ranked[i - 1]["rank"]
		else:
			e["rank"] = i + 1
	return ranked


func get_public_state() -> Dictionary:
	var st: Dictionary = {
		"round": round,
		"rounds": ROUNDS,
		"state": state,
		"timer": snappedf(timer, 0.01),
		"picked": picks.keys(),
		"wins": wins.duplicate(),
		"totals": win_totals.duplicate(),
		"history": history.duplicate(true),
	}
	if finished:
		st["ranking"] = ranking()
	return st


func private_state(player: int) -> Dictionary:
	return {
		"round": round,
		"can_pick": player in players and not finished and state == State.PICKING and player not in picks,
		"my_pick": picks.get(player, -1),
	}
