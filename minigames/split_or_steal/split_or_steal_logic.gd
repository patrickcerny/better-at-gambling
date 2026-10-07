class_name SplitOrStealLogic
extends MinigameLogicBase
## "Split or Steal Tournament" minigame: round-robin tournament where each pair plays once.
## Players choose SPLIT or STEAL. Both SPLIT: each gets 500. Both STEAL: each gets 0.
## One SPLIT, one STEAL: stealer gets 1000, splitter gets 0.

const SPLIT_PAYOFF: int = 500
const STEAL_PAYOFF: int = 1000
const ZERO_PAYOFF: int = 0

var tournament_matches: Array = []  # Array of [player_a, player_b] pairs
var match_index: int = 0
var current_match: Array = []  # [player_a, player_b] or empty
var current_choices: Dictionary[int, StringName] = {}  # player → SPLIT or STEAL
var player_scores: Dictionary[int, int] = {}  # player → total points
var match_results: Array[Dictionary] = []  # Results of completed matches
var ready_players: Array = []  # Players who have submitted choices for current match


func _on_setup(_context: Dictionary) -> void:
	# Initialize player scores
	for p: int in players:
		player_scores[p] = 0

	# Generate round-robin pairings
	_generate_tournament()

	events.append(GameEvents.make(&"split_or_steal_started", {
		"players": players.duplicate(),
		"total_matches": tournament_matches.size()
	}))


func _generate_tournament() -> void:
	# All unique pairs of players
	for i: int in range(players.size()):
		for j: int in range(i + 1, players.size()):
			tournament_matches.append([players[i], players[j]])


func tick(delta: float, now: float) -> void:
	if finished:
		return

	# Start next match if current one is empty
	if current_match.is_empty() and match_index < tournament_matches.size():
		_start_next_match()

	# End current match if both players have chosen
	if not current_match.is_empty() and current_choices.size() == 2:
		_end_current_match()
		current_choices.clear()
		ready_players.clear()
		current_match.clear()
		match_index += 1

		# Check if tournament is finished
		if match_index >= tournament_matches.size():
			finished = true
			events.append(GameEvents.make(&"split_or_steal_finished", {
				"final_scores": player_scores.duplicate()
			}))


func _start_next_match() -> void:
	if match_index < tournament_matches.size():
		current_match = tournament_matches[match_index].duplicate()
		current_choices.clear()
		ready_players.clear()

		events.append(GameEvents.make(&"split_or_steal_pairing", {
			"match_index": match_index,
			"player_a": current_match[0],
			"player_b": current_match[1]
		}))


## Accept a player's choice (SPLIT or STEAL).
func submit(player: int, intent: Dictionary, now: float) -> Dictionary:
	if player not in players:
		return StationLogicBase.fail(&"unknown_player")
	if finished:
		return StationLogicBase.fail(&"game_over")
	if current_match.is_empty():
		return StationLogicBase.fail(&"no_active_match")
	if player not in current_match:
		return StationLogicBase.fail(&"not_in_current_match")
	if player in current_choices:
		return StationLogicBase.fail(&"already_chose")

	var choice: StringName = StringName(intent.get("choice", ""))
	if choice not in [&"SPLIT", &"STEAL"]:
		return StationLogicBase.fail(&"invalid_choice")

	current_choices[player] = choice
	if player not in ready_players:
		ready_players.append(player)

	events.append(GameEvents.make(&"split_or_steal_choice_ready", {
		"match_index": match_index,
		"player": player
	}))

	return StationLogicBase.OK_RESULT


func _end_current_match() -> void:
	if current_match.size() != 2:
		return

	var player_a: int = current_match[0]
	var player_b: int = current_match[1]
	var choice_a: StringName = current_choices.get(player_a, &"SPLIT")
	var choice_b: StringName = current_choices.get(player_b, &"SPLIT")

	var payoff_a: int = 0
	var payoff_b: int = 0

	# Calculate payoffs
	if choice_a == &"SPLIT" and choice_b == &"SPLIT":
		payoff_a = SPLIT_PAYOFF
		payoff_b = SPLIT_PAYOFF
	elif choice_a == &"STEAL" and choice_b == &"STEAL":
		payoff_a = ZERO_PAYOFF
		payoff_b = ZERO_PAYOFF
	elif choice_a == &"STEAL":
		payoff_a = STEAL_PAYOFF
		payoff_b = ZERO_PAYOFF
	else:  # choice_b == "STEAL"
		payoff_a = ZERO_PAYOFF
		payoff_b = STEAL_PAYOFF

	player_scores[player_a] += payoff_a
	player_scores[player_b] += payoff_b

	var result: Dictionary = {
		"match_index": match_index,
		"player_a": player_a,
		"player_b": player_b,
		"choice_a": choice_a,
		"choice_b": choice_b,
		"payoff_a": payoff_a,
		"payoff_b": payoff_b
	}
	match_results.append(result)

	events.append(GameEvents.make(&"split_or_steal_payoff", result))


func ranking() -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for p: int in players:
		ranked.append({"player": p, "points": player_scores.get(p, 0)})

	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["points"] != b["points"]:
			return a["points"] > b["points"]
		return a["player"] < b["player"]
	)

	var rank: int = 1
	var last_points: int = -1
	for entry: Dictionary in ranked:
		if entry["points"] != last_points:
			rank = ranked.find(entry) + 1
			last_points = entry["points"]
		entry["rank"] = rank

	return ranked


func get_public_state() -> Dictionary:
	return {
		"match_index": match_index,
		"total_matches": tournament_matches.size(),
		"current_match": current_match.duplicate(),
		"scores": player_scores.duplicate(),
		"match_results": match_results.duplicate()
	}


func private_state(player: int) -> Dictionary:
	var in_current: bool = player in current_match
	return {
		"in_current_match": in_current,
		"can_choose": in_current and player not in current_choices,
		"current_score": player_scores.get(player, 0)
	}
