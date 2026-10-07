class_name VoteRaceLogic
extends MinigameLogicBase
## "Vote Race" minigame: each round, players vote for another player.
## Players with zero votes take one step forward. First to position 5 wins.
## Requires min 4 players. Each player votes for exactly one other (no self-votes).

const WINNING_POSITION: int = 5
const MIN_PLAYERS_REQUIRED: int = 4

var positions: Dictionary[int, int] = {}  # player → current position (0-5)
var votes: Dictionary[int, int] = {}  # player → target they voted for
var vote_counts: Dictionary[int, int] = {}  # player → votes received this round
var round_count: int = 0
var finished_game: bool = false
var winner: int = -1


func _on_setup(_context: Dictionary) -> void:
	if players.size() < MIN_PLAYERS_REQUIRED:
		# Not enough players, end immediately
		finished = true
		return

	for p: int in players:
		positions[p] = 0

	events.append(GameEvents.make(&"vote_race_started", {
		"players": players.duplicate(),
		"positions": positions.duplicate()
	}))


func tick(delta: float, now: float) -> void:
	if finished:
		return


func submit(player: int, intent: Dictionary, now: float) -> Dictionary:
	if player not in players:
		return StationLogicBase.fail(&"unknown_player")
	if finished:
		return StationLogicBase.fail(&"game_over")
	if player in votes:
		return StationLogicBase.fail(&"already_voted")

	var target: int = int(intent.get("target", -1))
	if target == player:
		return StationLogicBase.fail(&"cannot_vote_self")
	if target not in players:
		return StationLogicBase.fail(&"invalid_target")

	votes[player] = target
	vote_counts[target] = vote_counts.get(target, 0) + 1

	events.append(GameEvents.make(&"vote_race_votes_ready", {
		"voted": player
	}))

	if votes.size() == players.size():
		_end_round()

	return StationLogicBase.OK_RESULT


func _end_round() -> void:
	events.append(GameEvents.make(&"vote_race_voting_phase", {
		"round": round_count,
		"vote_counts": vote_counts.duplicate()
	}))

	# Players with zero votes advance
	for p: int in players:
		if vote_counts.get(p, 0) == 0:
			positions[p] += 1
			events.append(GameEvents.make(&"vote_race_progress", {
				"player": p,
				"new_position": positions[p]
			}))

			# Check for winner
			if positions[p] >= WINNING_POSITION:
				winner = p
				finished = true
				events.append(GameEvents.make(&"vote_race_winner", {
					"winner": p,
					"ranking": ranking().duplicate(true)
				}))
				return

	# Reset for next round
	votes.clear()
	vote_counts.clear()
	round_count += 1


func ranking() -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for p: int in players:
		ranked.append({"player": p, "position": positions.get(p, 0)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["position"] != b["position"]:
			return a["position"] > b["position"]
		return a["player"] < b["player"]
	)
	var rank: int = 1
	for entry: Dictionary in ranked:
		entry["rank"] = rank
		rank += 1
	return ranked


func get_public_state() -> Dictionary:
	return {
		"round": round_count,
		"positions": positions.duplicate(),
		"votes": votes.duplicate(),
		"vote_counts": vote_counts.duplicate(),
		"finished": finished,
		"winner": winner
	}


func private_state(player: int) -> Dictionary:
	return {
		"can_vote": player in players and not finished and player not in votes,
		"voted_for": votes.get(player, -1)
	}
