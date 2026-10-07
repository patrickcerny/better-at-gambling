class_name BustOrBankLogic
extends MinigameLogicBase
## "Bust or Bank" minigame: a shared deck of cards, each round players hit or stand.
## Players who bust are out. The player with the lowest valid hand each round is out.
## After 5 rounds or only 1 player left, game ends. Players rank by points (hand value per round won).

const ROUNDS: int = 5
const MAX_CARD_VALUE: int = 21
const DECK_SIZE: int = 52

var round: int = 0
var deck: Array[int] = []
var deck_index: int = 0
var hands: Dictionary = {}  # player → cards in hand
var standing: Dictionary = {}  # player → has stood this round
var busted: Dictionary = {}  # player → has busted this round
var points_per_player: Dictionary = {}  # player → total points won


func _on_setup(_context: Dictionary) -> void:
	for p: int in players:
		hands[p] = []
		standing[p] = false
		busted[p] = false
		points_per_player[p] = 0
	_new_deck()
	_start_round()


func _new_deck() -> void:
	deck.clear()
	deck_index = 0
	for i: int in DECK_SIZE:
		deck.append(i)
	deck.shuffle()


func _start_round() -> void:
	if round >= ROUNDS or players.size() <= 1:
		finished = true
		return

	# Reset per-round state
	for p: int in players:
		hands[p].clear()
		standing[p] = false
		busted[p] = false

	# Deal one card to each player
	for p: int in players:
		_deal_card(p)

	events.append(GameEvents.make(&"bust_or_bank_started", {
		"round": round,
		"players": players.duplicate()
	}))


func _deal_card(player: int) -> void:
	if deck_index >= DECK_SIZE:
		_new_deck()

	var card: int = deck[deck_index]
	deck_index += 1
	hands[player].append(card)

	events.append(GameEvents.make(&"bust_or_bank_card_dealt", {
		"player": player,
		"card": card,
		"hand": hands[player].duplicate(),
		"total": HandEval.total(hands[player])
	}))

	# Check for bust
	if HandEval.is_bust(hands[player]):
		busted[player] = true
		events.append(GameEvents.make(&"bust_or_bank_player_bust", {
			"player": player,
			"total": HandEval.total(hands[player])
		}))


func submit(player: int, intent: Dictionary, now: float) -> Dictionary:
	if player not in players:
		return StationLogicBase.fail(&"unknown_player")
	if round >= ROUNDS:
		return StationLogicBase.fail(&"game_over")
	if standing[player]:
		return StationLogicBase.fail(&"already_stood")
	if busted[player]:
		return StationLogicBase.fail(&"already_busted")

	var action: String = str(intent.get("action", "")).to_lower()
	if action == "hit":
		_deal_card(player)
		if HandEval.is_bust(hands[player]):
			_check_round_end()
		return StationLogicBase.OK_RESULT
	elif action == "stand":
		standing[player] = true
		events.append(GameEvents.make(&"bust_or_bank_player_stood", {
			"player": player,
			"total": HandEval.total(hands[player])
		}))
		_check_round_end()
		return StationLogicBase.OK_RESULT
	else:
		return StationLogicBase.fail(&"invalid_action")


func _check_round_end() -> void:
	# Check if all non-busted players have stood, or all players are busted
	var active_players: Array[int] = []
	for p: int in players:
		if not busted[p]:
			active_players.append(p)

	if active_players.is_empty():
		# All busted, move to next round
		_end_round()
		return

	var all_stood: bool = true
	for p: int in active_players:
		if not standing[p]:
			all_stood = false
			break

	if all_stood:
		_end_round()


func _end_round() -> void:
	# Find the player with the lowest valid (non-busted) hand
	var lowest_player: int = -1
	var lowest_total: int = MAX_CARD_VALUE + 1

	for p: int in players:
		if not busted[p]:
			var total: int = HandEval.total(hands[p])
			if total < lowest_total:
				lowest_total = total
				lowest_player = p

	# The lowest player gets their hand value as points
	if lowest_player >= 0:
		var won_points: int = HandEval.total(hands[lowest_player])
		points_per_player[lowest_player] += won_points

	var round_summary: Dictionary = {
		"round": round,
		"hands": {}
	}
	for p: int in players:
		round_summary["hands"][p] = {
			"cards": hands[p].duplicate(),
			"total": HandEval.total(hands[p]),
			"busted": busted[p]
		}

	if lowest_player >= 0:
		round_summary["winner"] = lowest_player
		round_summary["points_won"] = HandEval.total(hands[lowest_player])

	events.append(GameEvents.make(&"bust_or_bank_round_end", round_summary))

	round += 1
	if round >= ROUNDS or players.size() <= 1:
		finished = true
		events.append(GameEvents.make(&"bust_or_bank_finished", {
			"ranking": ranking().duplicate(true)
		}))
	else:
		_start_round()


func ranking() -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for p: int in players:
		ranked.append({"player": p, "points": points_per_player.get(p, 0)})
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
	var hands_public: Dictionary = {}
	for p: int in players:
		hands_public[p] = {
			"cards": hands[p].duplicate(),
			"total": HandEval.total(hands[p]) if not hands[p].is_empty() else 0,
			"busted": busted[p],
			"stood": standing[p]
		}

	return {
		"round": round,
		"hands": hands_public,
		"points": points_per_player.duplicate()
	}


func private_state(player: int) -> Dictionary:
	return {
		"can_act": player in players and round < ROUNDS and not standing[player] and not busted[player]
	}
