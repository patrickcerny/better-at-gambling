class_name RouletteRoyaleLogic
extends MinigameLogicBase
## "Roulette Royale" minigame: players start with 3 hearts. Each round, the server picks
## a random number on a European roulette wheel (0-36). Players choose red, black, or green (0).
## Correct choice: keep hearts; wrong choice: lose one heart. Last player with ≥1 heart wins.

const INITIAL_HEARTS: int = 3
const WHEEL_MAX: int = 36
const RED_NUMBERS: Array[int] = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]
const BLACK_NUMBERS: Array[int] = [2, 4, 6, 8, 10, 11, 13, 15, 17, 20, 22, 24, 26, 28, 29, 31, 33, 35]

var round: int = 0
var hearts: Dictionary[int, int] = {}  # player → hearts remaining
var choices: Dictionary[int, StringName] = {}  # player → their choice (red/black/green)
var active_players: Array[int] = []  # players still in the game


func _on_setup(_context: Dictionary) -> void:
	for p: int in players:
		hearts[p] = INITIAL_HEARTS
	active_players = players.duplicate()
	events.append(GameEvents.make(&"roulette_royale_started", {"players": players.duplicate(), "hearts": hearts.duplicate()}))


func tick(delta: float, now: float) -> void:
	if finished:
		return
	# If all players have made their choices, run the round
	if choices.size() == active_players.size() and not active_players.is_empty():
		_end_round()
		choices.clear()


## Accept a player's choice (red, black, or green).
func submit(player: int, intent: Dictionary, now: float) -> Dictionary:
	if player not in players:
		return StationLogicBase.fail(&"unknown_player")
	if player not in active_players:
		return StationLogicBase.fail(&"not_active")
	if finished:
		return StationLogicBase.fail(&"game_over")
	if player in choices:
		return StationLogicBase.fail(&"already_chose")

	var choice: StringName = StringName(intent.get("choice", ""))
	if choice not in [&"red", &"black", &"green"]:
		return StationLogicBase.fail(&"invalid_choice")

	choices[player] = choice
	events.append(GameEvents.make(&"roulette_royale_round_start", {
		"round": round,
		"active_players": active_players.duplicate(),
		"hearts": hearts.duplicate()
	}))
	return StationLogicBase.OK_RESULT


func _end_round() -> void:
	# Server picks a random number 0-36
	var number: int = rng.range_int(0, WHEEL_MAX)
	var color: StringName = _get_color(number)

	# Process results
	var correct_players: Array[int] = []
	var wrong_players: Array[int] = []

	for p: int in active_players:
		var choice: StringName = choices.get(p, &"")
		if choice == color:
			correct_players.append(p)
		else:
			wrong_players.append(p)
			hearts[p] -= 1

	events.append(GameEvents.make(&"roulette_royale_spin_result", {
		"round": round,
		"number": number,
		"color": color,
		"correct_players": correct_players.duplicate(),
		"wrong_players": wrong_players.duplicate()
	}))

	# Update hearts display
	events.append(GameEvents.make(&"roulette_royale_hearts_update", {
		"round": round,
		"hearts": hearts.duplicate(),
		"eliminated": wrong_players.duplicate()
	}))

	# Remove players with 0 hearts
	var eliminated: Array[int] = []
	for p: int in active_players:
		if hearts[p] <= 0:
			eliminated.append(p)

	for p: int in eliminated:
		active_players.erase(p)

	round += 1

	# Check if game is finished (only 1 or 0 players left)
	if active_players.size() <= 1:
		finished = true
		events.append(GameEvents.make(&"roulette_royale_finished", {
			"winner": active_players[0] if not active_players.is_empty() else -1,
			"final_hearts": hearts.duplicate()
		}))


func _get_color(number: int) -> StringName:
	if number == 0:
		return &"green"
	elif number in RED_NUMBERS:
		return &"red"
	else:
		return &"black"


func ranking() -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for p: int in players:
		var is_winner: bool = p in active_players and active_players.size() == 1
		ranked.append({
			"player": p,
			"points": INITIAL_HEARTS - hearts.get(p, 0),
			"hearts_remaining": maxf(hearts.get(p, 0), 0)
		})

	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["hearts_remaining"] != b["hearts_remaining"]:
			return a["hearts_remaining"] > b["hearts_remaining"]
		return a["player"] < b["player"]
	)

	var rank: int = 1
	var last_hearts: int = -1
	for entry: Dictionary in ranked:
		if entry["hearts_remaining"] != last_hearts:
			rank = ranked.find(entry) + 1
			last_hearts = entry["hearts_remaining"]
		entry["rank"] = rank

	return ranked


func get_public_state() -> Dictionary:
	return {
		"round": round,
		"hearts": hearts.duplicate(),
		"active_players": active_players.duplicate(),
		"choices_submitted": choices.size()
	}


func private_state(player: int) -> Dictionary:
	return {
		"can_choose": player in active_players and player not in choices,
		"hearts": hearts.get(player, 0)
	}
