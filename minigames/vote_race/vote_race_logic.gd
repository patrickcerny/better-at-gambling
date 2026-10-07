class_name VoteRaceLogic
extends MinigameLogicBase
## "Vote Race" minigame: every bean stands on a 5-step track to the cashier. Each round everyone
## still racing secretly votes for one other racer; every racer who got zero votes steps forward.
## The votes stay on the server until the round resolves, then the reveal shows who voted for whom.
## First to step 5 finishes first, the others keep going and finish in order. The race ends when
## only 2 racers are left on the track; those two rank last, by steps.
##
## Round flow: VOTING (up to VOTE_TIME, or until every racer voted) → REVEAL (REVEAL_TIME, votes
## public) → next VOTING round with a fresh, empty ballot. Not voting in time = no vote cast.

enum RaceState { VOTING, REVEAL, OVER }

const TRACK_LENGTH: int = 5
const MIN_PLAYERS_REQUIRED: int = 4
## The race stops when this many racers (or fewer) are still on the track.
const RACERS_LEFT_TO_END: int = 2
const VOTE_TIME: float = 8.0
const REVEAL_TIME: float = 3.0
## Safety cap so a table that keeps voting in a ring can't stall the match forever.
const MAX_ROUNDS: int = 15

var phase: RaceState = RaceState.VOTING
var timer: float = 0.0
var round_count: int = 0
var positions: Dictionary[int, int] = {}  # player → steps taken (0..TRACK_LENGTH)
var racing: Array[int] = []  # players still on the track (vote and can be voted for)
## Finishing places: one entry per round in which someone finished; players finishing in the
## same round share the place.
var finish_groups: Array[Array] = []
## SECRET while voting: voter → target for the current round. Never sent to clients until the
## round is resolved; cleared when the next round starts, not when it resolves.
var votes: Dictionary[int, int] = {}
## The last resolved round, public: {round, votes, vote_counts, moved, finished}.
var last_reveal: Dictionary = {}


func _on_setup(_context: Dictionary) -> void:
	if players.size() < MIN_PLAYERS_REQUIRED:
		phase = RaceState.OVER
		finished = true
		return
	for p: int in players:
		positions[p] = 0
		racing.append(p)
	events.append(GameEvents.make(&"vote_race_started", {
		"players": players.duplicate(),
		"positions": positions.duplicate(),
		"track": TRACK_LENGTH,
		"vote_time": VOTE_TIME
	}))
	_start_round()


func tick(delta: float, _now: float) -> void:
	if finished:
		return
	timer -= delta
	if timer > 0.0:
		return
	match phase:
		RaceState.VOTING:
			_resolve_round()  # time's up: whoever didn't vote cast no vote
		RaceState.REVEAL:
			if _race_over():
				_finish()
			else:
				_start_round()


func submit(player: int, intent: Dictionary, _now: float) -> Dictionary:
	if player not in players:
		return StationLogicBase.fail(&"unknown_player")
	if finished or phase == RaceState.OVER:
		return StationLogicBase.fail(&"game_over")
	if player not in racing:
		return StationLogicBase.fail(&"not_racing")
	if phase != RaceState.VOTING:
		return StationLogicBase.fail(&"not_voting")
	if votes.has(player):
		return StationLogicBase.fail(&"already_voted")
	var target: int = int(intent.get("target", -1))
	if target == player:
		return StationLogicBase.fail(&"cannot_vote_self")
	if target not in racing:
		return StationLogicBase.fail(&"invalid_target")
	votes[player] = target
	# Public: only THAT someone voted, never for whom.
	events.append(GameEvents.make(&"vote_race_voted", {"player": player, "round": round_count}))
	if _all_racers_voted():
		_resolve_round()
	return StationLogicBase.OK_RESULT


func remove_player(player: int) -> void:
	super.remove_player(player)
	positions.erase(player)
	racing.erase(player)
	for group: Array in finish_groups:
		group.erase(player)
	finish_groups.assign(finish_groups.filter(func(g: Array) -> bool: return not g.is_empty()))
	votes.erase(player)
	for voter: int in votes.keys():
		if votes[voter] == player:
			votes.erase(voter)  # their target left: they may vote again this round
	if finished or phase == RaceState.OVER:
		return
	if phase == RaceState.VOTING:
		if racing.size() <= RACERS_LEFT_TO_END:
			_finish()
		elif _all_racers_voted():
			_resolve_round()


func _start_round() -> void:
	votes.clear()  # the previous round's ballot is cleared only now, after its reveal
	phase = RaceState.VOTING
	timer = VOTE_TIME
	events.append(GameEvents.make(&"vote_race_round", {
		"round": round_count,
		"racing": racing.duplicate(),
		"positions": positions.duplicate(),
		"time_left": VOTE_TIME
	}))


func _all_racers_voted() -> bool:
	for p: int in racing:
		if not votes.has(p):
			return false
	return true


## Tallies the round: every racer with zero votes steps forward. When everyone got at least one
## vote nobody moves and the next round is a fresh vote.
func _resolve_round() -> void:
	var counts: Dictionary[int, int] = {}
	for p: int in racing:
		counts[p] = 0
	var cast: Dictionary[int, int] = {}
	for voter: int in votes:
		var target: int = votes[voter]
		if voter in racing and counts.has(target):
			counts[target] += 1
			cast[voter] = target
	var moved: Array[int] = []
	var newly_finished: Array[int] = []
	for p: int in racing:
		if counts[p] == 0:
			positions[p] = mini(positions[p] + 1, TRACK_LENGTH)
			moved.append(p)
			if positions[p] >= TRACK_LENGTH:
				newly_finished.append(p)
	for p: int in newly_finished:
		racing.erase(p)
	if not newly_finished.is_empty():
		finish_groups.append(newly_finished.duplicate())
	last_reveal = {
		"round": round_count,
		"votes": cast.duplicate(),
		"vote_counts": counts.duplicate(),
		"moved": moved.duplicate(),
		"finished": newly_finished.duplicate()
	}
	var ev: Dictionary = last_reveal.duplicate(true)
	ev["positions"] = positions.duplicate()
	ev["racing"] = racing.duplicate()
	events.append(GameEvents.make(&"vote_race_reveal", ev))
	round_count += 1
	phase = RaceState.REVEAL
	timer = REVEAL_TIME


func _race_over() -> bool:
	return racing.size() <= RACERS_LEFT_TO_END or round_count >= MAX_ROUNDS


func _finish() -> void:
	phase = RaceState.OVER
	finished = true
	events.append(GameEvents.make(&"vote_race_over", {
		"ranking": ranking(),
		"positions": positions.duplicate()
	}))


## Finishers first in the order they reached the cashier (same round = same place), then everyone
## still on the track by steps (equal steps = same place).
func ranking() -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	var rank: int = 1
	for group: Array in finish_groups:
		var sorted_group: Array = group.duplicate()
		sorted_group.sort()
		for p: int in sorted_group:
			ranked.append({"player": p, "steps": positions.get(p, 0), "finished": true, "rank": rank})
		rank += sorted_group.size()
	var rest: Array[int] = []
	for p: int in players:
		if not _has_finished(p):
			rest.append(p)
	rest.sort_custom(func(a: int, b: int) -> bool:
		var sa: int = positions.get(a, 0)
		var sb: int = positions.get(b, 0)
		return sa > sb if sa != sb else a < b
	)
	var prev_steps: int = -1
	var prev_rank: int = rank
	for i: int in rest.size():
		var p: int = rest[i]
		var steps: int = positions.get(p, 0)
		var r: int = prev_rank if steps == prev_steps else rank + i
		ranked.append({"player": p, "steps": steps, "finished": false, "rank": r})
		prev_steps = steps
		prev_rank = r
	return ranked


func _has_finished(p: int) -> bool:
	for group: Array in finish_groups:
		if p in group:
			return true
	return false


## Public snapshot: positions, who is still racing, how many have voted and the LAST RESOLVED
## round's reveal. The current round's votes are never included.
func get_public_state() -> Dictionary:
	var finish_order: Array = []
	for group: Array in finish_groups:
		finish_order.append(group.duplicate())
	return {
		"players": players.duplicate(),
		"round": round_count,
		"phase": String(RaceState.keys()[phase]).to_lower(),
		"time_left": snappedf(maxf(timer, 0.0), 0.01),
		"positions": positions.duplicate(),
		"racing": racing.duplicate(),
		"finish_order": finish_order,
		"votes_cast": votes.size() if phase == RaceState.VOTING else 0,
		"last_reveal": last_reveal.duplicate(true),
		"track": TRACK_LENGTH,
		"finished": finished
	}


func private_state(player: int) -> Dictionary:
	return {
		"can_vote": not finished and phase == RaceState.VOTING and player in racing and not votes.has(player),
		"voted_for": votes.get(player, -1) if phase == RaceState.VOTING else -1,
		"racing": player in racing
	}
