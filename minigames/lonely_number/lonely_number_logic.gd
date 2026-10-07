class_name LonelyNumberLogic
extends MinigameLogicBase
## "Lonely Number" minigame (§2.9.3): every player secretly picks 1-20; highest number nobody else
## picked wins the round. 5 rounds, most round wins ranks first. Server decides picks, announces
## results, and handles ties.

const ROUNDS: int = 5
const NUMBER_RANGE: int = 20

var round: int = 0
var picks: Dictionary[int, int] = {}  # player → their pick
var round_winners: Array[int] = []  # winners of each round so far
var picks_per_player: Dictionary[int, int] = {}  # player → round wins


func _on_setup(_context: Dictionary) -> void:
	for p: int in players:
		picks_per_player[p] = 0


func tick(delta: float, now: float) -> void:
	if finished:
		return
	if round >= ROUNDS and picks.is_empty():
		finished = true


## Accept a player's pick (1-20).
func submit(player: int, intent: Dictionary, now: float) -> Dictionary:
	if player not in players:
		return StationLogicBase.fail(&"unknown_player")
	if round >= ROUNDS:
		return StationLogicBase.fail(&"game_over")
	if player in picks:
		return StationLogicBase.fail(&"already_picked")
	var pick: int = int(intent.get("number", -1))
	if pick < 1 or pick > NUMBER_RANGE:
		return StationLogicBase.fail(&"invalid_number")
	picks[player] = pick
	events.append(GameEvents.make(&"lonely_number_picked", {"player": player, "round": round}))
	if picks.size() == players.size():
		_end_round()
	return StationLogicBase.OK_RESULT


func _end_round() -> void:
	var counts: Dictionary[int, int] = {}
	for p: int in players:
		var num: int = picks.get(p, -1)
		if num > 0:
			counts[num] = counts.get(num, 0) + 1
	var lonely: int = -1
	for num: int in range(1, NUMBER_RANGE + 1):
		if counts.get(num, 0) == 1:
			lonely = num
	var round_winner: int = -1
	if lonely > 0:
		for p: int in players:
			if picks.get(p, -1) == lonely:
				round_winner = p
				picks_per_player[p] += 1
				break
	events.append(GameEvents.make(&"lonely_number_round_end", {
		"round": round,
		"picks": picks.duplicate(),
		"lonely_number": lonely,
		"winner": round_winner
	}))
	picks.clear()
	round += 1
	if round >= ROUNDS:
		finished = true


func ranking() -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for p: int in players:
		ranked.append({"player": p, "points": picks_per_player.get(p, 0)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["points"] != b["points"]:
			return a["points"] > b["points"]
		return a["player"] < b["player"]
	)
	var rank: int = 1
	for entry: Dictionary in ranked:
		entry["rank"] = rank
		rank += 1
	return ranked


func get_public_state() -> Dictionary:
	return {
		"round": round,
		"round_winners": picks_per_player.duplicate(),
		"picks_submitted": picks.size()
	}


func private_state(player: int) -> Dictionary:
	return {
		"can_pick": player in players and round < ROUNDS and player not in picks,
		"rounds": ROUNDS
	}
