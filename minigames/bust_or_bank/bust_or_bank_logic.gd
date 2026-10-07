class_name BustOrBankLogic
extends MinigameLogicBase
## "Bust or Bank" minigame: last player standing at a shared blackjack shoe.
##
## Each round one shared shoe deals a card every `DEAL_INTERVAL` seconds to everyone still in play
## at once; each player adds it to their own total and may STAND (bank) at any moment. Going over
## 21 busts you on the spot. When nobody is still drawing, the round ends: busted players and the
## worst standing hand(s) are thrown out (ties for worst all go). Survivors play again with a fresh
## count until one player is left.
##
## Ranking is elimination order: later out = better. Players thrown out in the same round share a
## rank, and busted players rank below that round's worst standing hand. If everyone in a round
## busts, nobody is thrown out and the round is replayed. If every standing hand ties for worst,
## nobody is thrown out for the tie either (there would be nobody left).
##
## "Points" are the number of players you have outlasted so far; they're sent with every
## `bust_or_bank_round_end` event (absolute values, not deltas) and end up in the ranking.

enum State { INTRO, DEALING, RESULT, DONE }

## Seconds before the first cards of a round.
const INTRO_TIME: float = 2.0
## Seconds between shared cards while players are still drawing.
const DEAL_INTERVAL: float = 1.6
## Seconds the round result is shown before the next round (or the end).
const RESULT_TIME: float = 3.0
## Cards dealt at the start of a round (blackjack-style two-card start).
const OPENING_CARDS: int = 2
## Safety cap (counts replays): survivors after `max_rounds` rounds share first place. It's the
## player count + `SPARE_ROUNDS` (one knock-out per round plus a few replays), capped at
## `MAX_ROUNDS`, so a table of idle players (everyone busts, every round) still ends quickly.
const SPARE_ROUNDS: int = 3
const MAX_ROUNDS: int = 12
const SHOE_DECKS: int = 2
const BLACKJACK: int = 21

var state: State = State.INTRO
var timer: float = 0.0
## Round number, 0-based, counting replays.
var round: int = 0
var shoe: Shoe
## Players still in the game (not thrown out).
var in_round: Array[int] = []
var hands: Dictionary[int, Array] = {}  # player → Array[int] of cards this round
var standing: Dictionary[int, bool] = {}
var busted: Dictionary[int, bool] = {}
## Thrown-out groups, worst first: each entry is the players who share one rank.
var elim_groups: Array[Array] = []
var last_card: int = -1
var max_rounds: int = MAX_ROUNDS
## The round that just ended was an everyone-busted replay (the next one replays it).
var _last_was_replay: bool = false


func _on_setup(_context: Dictionary) -> void:
	shoe = Shoe.new(rng, SHOE_DECKS)
	in_round = players.duplicate()
	in_round.sort()
	max_rounds = mini(in_round.size() + SPARE_ROUNDS, MAX_ROUNDS)
	events.append(GameEvents.make(&"bust_or_bank_started", {
		"players": in_round.duplicate(),
		"deal_interval": DEAL_INTERVAL,
		"max_rounds": max_rounds,
	}))
	if in_round.size() <= 1:
		_finish()
		return
	_begin_round(false)


func tick(delta: float, _now: float) -> void:
	if finished:
		return
	timer -= delta
	if timer > 0.0:
		return
	match state:
		State.INTRO:
			state = State.DEALING
			for i: int in OPENING_CARDS:
				if state == State.DEALING:
					_deal()
			if state == State.DEALING:
				timer = DEAL_INTERVAL
		State.DEALING:
			_deal()
			if state == State.DEALING:
				timer = DEAL_INTERVAL
		State.RESULT:
			if _game_over():
				finished = true
				state = State.DONE
			else:
				_begin_round(_last_was_replay)
		State.DONE:
			finished = true


## Only action: STAND (bank your total). Cards come from the shared shoe on their own.
func submit(player: int, intent: Dictionary, _now: float) -> Dictionary:
	if player not in in_round:
		return StationLogicBase.fail(&"not_in_game")
	if finished or state == State.DONE:
		return StationLogicBase.fail(&"game_over")
	var action: String = str(intent.get("action", "")).to_lower()
	if action != "stand":
		return StationLogicBase.fail(&"invalid_action")
	if state != State.DEALING:
		return StationLogicBase.fail(&"not_dealing")
	if busted[player]:
		return StationLogicBase.fail(&"already_busted")
	if standing[player]:
		return StationLogicBase.fail(&"already_stood")
	_stand(player, false)
	if _active().is_empty():
		_end_round()
	return StationLogicBase.OK_RESULT


func remove_player(player: int) -> void:
	super.remove_player(player)
	in_round.erase(player)
	hands.erase(player)
	standing.erase(player)
	busted.erase(player)
	for group: Array in elim_groups:
		group.erase(player)
	elim_groups.assign(elim_groups.filter(func(g: Array) -> bool: return not g.is_empty()))
	if finished or state == State.DONE:
		return
	if in_round.size() <= 1:
		_finish()
	elif state == State.DEALING and _active().is_empty():
		_end_round()


# --- Round flow --------------------------------------------------------------------------------

func _begin_round(replay: bool) -> void:
	if shoe.needs_reshuffle():
		shoe.reshuffle()
	for p: int in in_round:
		hands[p] = [] as Array[int]
		standing[p] = false
		busted[p] = false
	last_card = -1
	state = State.INTRO
	timer = INTRO_TIME
	events.append(GameEvents.make(&"bust_or_bank_round_started", {
		"round": round,
		"players": in_round.duplicate(),
		"replay": replay,
		"deal_in": INTRO_TIME,
	}))


## Players still drawing this round.
func _active() -> Array[int]:
	var out: Array[int] = []
	for p: int in in_round:
		if not standing[p] and not busted[p]:
			out.append(p)
	return out


## One card from the shared shoe to everyone still drawing.
func _deal() -> void:
	var receivers: Array[int] = _active()
	if receivers.is_empty():
		_end_round()
		return
	var card: int = shoe.draw()
	last_card = card
	var totals: Dictionary[int, int] = {}
	for p: int in receivers:
		(hands[p] as Array).append(card)
		totals[p] = _total(p)
	events.append(GameEvents.make(&"bust_or_bank_card", {
		"round": round,
		"card": card,
		"receivers": receivers.duplicate(),
		"totals": totals.duplicate(),
		"next_in": DEAL_INTERVAL,
	}))
	for p: int in receivers:
		var t: int = totals[p]
		if t > BLACKJACK:
			busted[p] = true
			events.append(GameEvents.make(&"bust_or_bank_player_bust", {"player": p, "total": t, "round": round}))
		elif t == BLACKJACK:
			_stand(p, true)  # can't do better than 21
	if _active().is_empty():
		_end_round()


func _stand(player: int, auto: bool) -> void:
	standing[player] = true
	events.append(GameEvents.make(&"bust_or_bank_player_stood", {"player": player, "total": _total(player), "auto": auto, "round": round}))


func _end_round() -> void:
	# in_round is kept sorted, so these lists are too.
	var busts: Array[int] = []
	var stood: Array[int] = []
	for p: int in in_round:
		if busted[p]:
			busts.append(p)
		else:
			stood.append(p)

	var worst: Array[int] = []
	var replay: bool = stood.is_empty()  # everyone busted: replay the round for all of them
	if not replay:
		var worst_total: int = BLACKJACK + 1
		var best_total: int = -1
		for p: int in stood:
			worst_total = mini(worst_total, _total(p))
			best_total = maxi(best_total, _total(p))
		if worst_total < best_total:  # someone strictly better survives
			for p: int in stood:
				if _total(p) == worst_total:
					worst.append(p)
		# Worst first: this round's busts rank below this round's worst standing hand(s).
		if not busts.is_empty():
			elim_groups.append(busts.duplicate())
		if not worst.is_empty():
			elim_groups.append(worst.duplicate())
		for p: int in busts + worst:
			in_round.erase(p)
	var eliminated: Array[int] = []
	if not replay:
		eliminated.append_array(busts)
		eliminated.append_array(worst)

	var hands_out: Dictionary[int, Dictionary] = {}
	for p: int in busts + stood:
		hands_out[p] = {"cards": (hands[p] as Array).duplicate(), "total": _total(p), "busted": busted.get(p, false)}

	_last_was_replay = replay
	events.append(GameEvents.make(&"bust_or_bank_round_end", {
		"round": round,
		"hands": hands_out,
		"busted": busts.duplicate(),
		"worst": worst.duplicate(),
		"eliminated": eliminated,
		"replay": replay,
		"remaining": in_round.duplicate(),
		"points": points(),
	}))
	round += 1
	state = State.RESULT
	timer = RESULT_TIME
	if _game_over():
		events.append(GameEvents.make(&"bust_or_bank_finished", {"ranking": ranking().duplicate(true), "points": points()}))


func _game_over() -> bool:
	return in_round.size() <= 1 or round >= max_rounds


## Ends right away (not enough players left to play on).
func _finish() -> void:
	state = State.DONE
	finished = true
	events.append(GameEvents.make(&"bust_or_bank_finished", {"ranking": ranking().duplicate(true), "points": points()}))


func _total(player: int) -> int:
	var cards: Array[int] = []
	cards.assign(hands.get(player, []))
	return HandEval.total(cards) if not cards.is_empty() else 0


# --- Scoring -----------------------------------------------------------------------------------

## Players outlasted so far, for everyone still in the game or thrown out (absolute values).
func points() -> Dictionary[int, int]:
	var out: Dictionary[int, int] = {}
	var below: int = 0
	for group: Array in elim_groups:  # worst first
		for p: Variant in group:
			out[int(p)] = below
		below += group.size()
	for p: int in in_round:
		out[p] = below
	return out


## [{player, rank, points, out_round}] best first. Survivors share rank 1; each thrown-out group
## shares one rank (standard competition ranking: 1, 2, 2, 4 …).
func ranking() -> Array[Dictionary]:
	var pts: Dictionary[int, int] = points()
	var ranked: Array[Dictionary] = []
	var rank: int = 1
	var top: Array[int] = in_round.duplicate()
	top.sort()
	for p: int in top:
		ranked.append({"player": p, "rank": rank, "points": pts[p], "out": false})
	rank += top.size()
	for i: int in range(elim_groups.size() - 1, -1, -1):
		var group: Array = elim_groups[i].duplicate()
		group.sort()
		for p: Variant in group:
			ranked.append({"player": int(p), "rank": rank, "points": pts[int(p)], "out": true})
		rank += group.size()
	return ranked


# --- Snapshots ---------------------------------------------------------------------------------

func get_public_state() -> Dictionary:
	var hands_public: Dictionary[int, Dictionary] = {}
	for p: int in in_round:
		hands_public[p] = {
			"cards": (hands.get(p, []) as Array).duplicate(),
			"total": _total(p),
			"busted": busted.get(p, false),
			"stood": standing.get(p, false),
		}
	var out_players: Array[int] = []
	for group: Array in elim_groups:
		for p: Variant in group:
			out_players.append(int(p))
	var st: Dictionary = {
		"state": state,
		"timer": snappedf(maxf(timer, 0.0), 0.01),
		"round": round,
		"players": players.duplicate(),
		"in_round": in_round.duplicate(),
		"out": out_players,
		"hands": hands_public,
		"last_card": last_card,
		"points": points(),
		"deal_interval": DEAL_INTERVAL,
	}
	if state == State.DONE or (state == State.RESULT and _game_over()):
		st["ranking"] = ranking().duplicate(true)
	return st


func private_state(player: int) -> Dictionary:
	return {"can_stand": state == State.DEALING and player in in_round and not standing.get(player, true) and not busted.get(player, true)}
