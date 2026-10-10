class_name BustOrBankLogic
extends MinigameLogicBase
## "Bust or Bank" minigame: turn-based blackjack round a shared table, played in elimination
## rounds until one player is left (Patrick 2026-10-10: "multiple rounds, only one per round (bust
## are directly out) are thrown out till one remains").
##
## Every round: everyone still in gets ONE face-up card from a shared shoe, then the turns go round
## the table in a circle: on your turn you have `TURN_TIME` seconds to HIT (take exactly one card,
## then the turn passes on) or STAND (your hand is locked for the round). No decision in time =
## STAND. Over 21 busts you on the spot; hitting to 21 stands you automatically. The circle skips
## players who stood or busted, so a lone player still drawing keeps taking turns. The round ends
## when nobody is left drawing (or after `ROUND_CAP` seconds of turns: everyone undecided stands).
##
## After the round: everyone who busted is out. If nobody busted, the lowest standing total is out
## (all of them when several share it). If that would put everyone still in out (all tied, or all
## busted), nobody goes and the survivors play again. Rounds repeat with fresh hands, the turn
## circle starting one seat further each round, until one player remains: the winner. Eliminated
## players stay at the table as spectators. At most `players - 1` rounds and `GAME_CAP` seconds:
## when either runs out, the survivors are ranked by their current hand.
##
## The upcoming card is a secret (Patrick 2026-10-10: "it should be a gamble"): nothing about the
## shoe's top card goes into events or the public snapshot. `next_card` stays server-side for
## tests and tutorial scripting.
##
## Ranking: the winner(s) first, then the eliminated players by the round they went out (later is
## better); within one round a standing hand beats a busted one and a higher total a lower one;
## equal = shared rank. Points = number of players ranked below you (winner players - 1, last 0).
##
## Events: `bust_or_bank_started`, `bust_or_bank_round_started` (`round`, opening deal in `deal_in`
## s), `bust_or_bank_card` (one per card dealt, the opening cards too), `bust_or_bank_turn`,
## `bust_or_bank_player_stood`, `bust_or_bank_player_left`, `bust_or_bank_round_end` (hands, `out`,
## `survivors`, `why`, `final`) and, once, `bust_or_bank_finished` (ranking, points, winners).

enum State { INTRO, TURN, RESULT, DONE }

## Seconds the table is shown before a round's opening cards land and its first turn starts.
const INTRO_TIME: float = 3.0
## Seconds a player has to HIT or STAND; then they stand automatically.
const TURN_TIME: float = 20.0
## Seconds a round's result (who is out, or the final ranking) is shown.
const RESULT_TIME: float = 5.0
## Most seconds the turns of ONE round may take: an idle table of 8 would otherwise run
## 8 × `TURN_TIME`. When it runs out, everyone still undecided stands.
const ROUND_CAP: float = 90.0
## Most seconds the whole minigame may take (intros, turns and results): an idle table of 8 would
## otherwise play 7 capped rounds (over 11 minutes). When it runs out mid-round, everyone
## undecided stands and that round is the last; only the final `RESULT_TIME` comes on top.
const GAME_CAP: float = 420.0
const SHOE_DECKS: int = 2
const BLACKJACK: int = 21

var state: State = State.INTRO
## Seconds left in the current state (intro, the current turn, the result).
var timer: float = 0.0
## Seconds the turns of the current round have taken so far (see `ROUND_CAP`).
var round_time: float = 0.0
## Seconds the whole minigame has taken so far (see `GAME_CAP`).
var game_time: float = 0.0
var shoe: Shoe
## Seat order: everyone at the table, still in or out. Players who left are removed.
var order: Array[int] = []
## The players still in, in seat order: the circle the turns go round.
var alive: Array[int] = []
## player → the round they went out in (eliminated players only).
var out_round: Dictionary[int, int] = {}
## player → their hand when they went out: the total, or -1 for a bust.
var out_score: Dictionary[int, int] = {}
var hands: Dictionary[int, Array] = {}  # player → Array[int] of cards (eliminated: their last hand)
var standing: Dictionary[int, bool] = {}
var busted: Dictionary[int, bool] = {}
## Current round (1 = the first, 0 before it).
var round_no: int = 0
## Rounds at most: players - 1 (at least 1).
var max_rounds: int = 1
## Who starts the current round's turn circle (the next round starts one seat further).
var starter: int = -1
## Whose turn it is (-1 outside TURN).
var current: int = -1
## Turns started so far, over all rounds (0 before the first).
var turn: int = 0
var last_card: int = -1
## The last round's verdict: who went out and why (&"busted", &"lowest", &"replay", &"none").
var last_out: Array[int] = []
var last_why: StringName = &""
## True once the game is decided (the final result is showing, or the game is over).
var final: bool = false
## Seat order at the start, never shrinks: where the next round's circle starts.
var _seats: Array[int] = []
var _ranking: Array[Dictionary] = []
## The card the shoe deals next, server-side only (-1 between rounds). It is always the shoe's top
## card, so `shoe.stack_top` decides the order (tests and tutorial scripting).
var next_card: int:
	get:
		if shoe == null or state == State.RESULT or state == State.DONE:
			return -1
		return shoe.peek()


func _on_setup(_context: Dictionary) -> void:
	shoe = Shoe.new(rng, SHOE_DECKS)
	order = players.duplicate()
	_seats = order.duplicate()
	alive = order.duplicate()
	max_rounds = maxi(order.size() - 1, 1)
	for p: int in order:
		hands[p] = [] as Array[int]
		standing[p] = false
		busted[p] = false
	events.append(GameEvents.make(&"bust_or_bank_started", {
		"players": order.duplicate(),
		"turn_time": TURN_TIME,
		"max_rounds": max_rounds,
	}))
	if order.is_empty():
		_finish()
		return
	_start_round()


func tick(delta: float, _now: float) -> void:
	if finished:
		return
	game_time += delta
	if state == State.TURN:
		round_time += delta
		if round_time >= ROUND_CAP or game_time >= GAME_CAP:
			var reason: StringName = &"game_cap" if game_time >= GAME_CAP else &"round_cap"
			for p: int in alive:
				if not standing[p] and not busted[p]:
					_stand(p, reason)
			_end_round()
			return
	timer -= delta
	if timer > 0.0:
		return
	match state:
		State.INTRO:
			_opening_deal()
		State.TURN:
			var p: int = current
			_stand(p, &"timeout")
			_pass_turn(p)
		State.RESULT:
			if final:
				state = State.DONE
				finished = true
			else:
				_start_round()
		State.DONE:
			finished = true


## HIT (one card, then the next player's turn) or STAND (locked for the round), on your turn only.
func submit(player: int, intent: Dictionary, _now: float) -> Dictionary:
	if player not in order:
		return StationLogicBase.fail(&"not_in_game")
	if finished or final or state == State.DONE:
		return StationLogicBase.fail(&"game_over")
	var action: String = str(intent.get("action", "")).to_lower()
	if action != "hit" and action != "stand":
		return StationLogicBase.fail(&"invalid_action")
	if player not in alive:
		return StationLogicBase.fail(&"eliminated")
	if state == State.RESULT:
		return StationLogicBase.fail(&"not_your_turn")
	if busted[player]:
		return StationLogicBase.fail(&"already_busted")
	if standing[player]:
		return StationLogicBase.fail(&"already_stood")
	if state != State.TURN or player != current:
		return StationLogicBase.fail(&"not_your_turn")
	if action == "stand":
		_stand(player, &"choice")
	else:
		_deal(player)
		if not busted[player] and _total(player) == BLACKJACK:
			_stand(player, &"21")  # can't do better than 21
	_pass_turn(player)
	return StationLogicBase.OK_RESULT


## A player who leaves is dropped from the table and the ranking (like the other minigames); on
## their turn, the turn passes to the next player still in. When one player is left in, they win.
func remove_player(player: int) -> void:
	if player not in order:
		super.remove_player(player)
		return
	var was_current: bool = state == State.TURN and player == current
	var next_p: int = _next_active_after(player, true) if was_current else -1
	var was_alive: bool = player in alive
	super.remove_player(player)
	order.erase(player)
	alive.erase(player)
	hands.erase(player)
	standing.erase(player)
	busted.erase(player)
	out_round.erase(player)
	out_score.erase(player)
	last_out.erase(player)
	if not _ranking.is_empty():
		_ranking = _compute_ranking()
	if finished or final or state == State.DONE:
		return
	events.append(GameEvents.make(&"bust_or_bank_player_left", {
		"player": player,
		"players": order.duplicate(),
		"survivors": alive.duplicate(),
	}))
	if order.is_empty():
		_finish()
		return
	if not was_alive:
		return  # a spectator: the game goes on
	if alive.size() <= 1:
		if state == State.RESULT:
			_end_game()  # between rounds: nobody left to play against
		elif state == State.TURN:
			_end_round()  # the last one in wins
		# INTRO: the opening deal ends the round
	elif was_current:
		if next_p == -1:
			_end_round()
		else:
			_start_turn(next_p)


# --- Round flow --------------------------------------------------------------------------------

## Fresh hands for everyone still in, then the intro before the opening deal.
func _start_round() -> void:
	round_no += 1
	round_time = 0.0
	current = -1
	last_out.clear()
	last_why = &""
	for p: int in alive:
		hands[p] = [] as Array[int]
		standing[p] = false
		busted[p] = false
	starter = _next_starter()
	state = State.INTRO
	timer = INTRO_TIME
	events.append(GameEvents.make(&"bust_or_bank_round_started", {
		"round": round_no,
		"max_rounds": max_rounds,
		"players": order.duplicate(),
		"survivors": alive.duplicate(),
		"starter": starter,
		"deal_in": INTRO_TIME,
		"turn_time": TURN_TIME,
	}))


## Round 1: the first seat. Later: the first player still in after the previous round's starter.
func _next_starter() -> int:
	if alive.is_empty():
		return -1
	if starter == -1:
		return alive[0]
	var n: int = _seats.size()
	var from: int = _seats.find(starter)
	for step: int in range(1, n + 1):
		var p: int = _seats[(from + step) % n]
		if p in alive:
			return p
	return alive[0]


## One face-up card to everyone still in, round the circle from the starter, then the first turn.
func _opening_deal() -> void:
	if alive.is_empty():
		_end_round()
		return
	var from: int = maxi(alive.find(starter), 0)
	for i: int in alive.size():
		_deal(alive[(from + i) % alive.size()], true)
	if alive.size() <= 1:
		_end_round()
		return
	_start_turn(alive[from])


func _start_turn(player: int) -> void:
	state = State.TURN
	current = player
	timer = TURN_TIME
	turn += 1
	events.append(GameEvents.make(&"bust_or_bank_turn", {
		"player": player,
		"time": TURN_TIME,
		"turn": turn,
		"round": round_no,
		"total": _total(player),
	}))


## The turn after `player`'s: the next player in the circle still drawing (may be `player` again
## when they are the only one left), or the end of the round.
func _pass_turn(player: int) -> void:
	var nxt: int = _next_active_after(player, false)
	if nxt == -1:
		_end_round()
	else:
		_start_turn(nxt)


## The first player after `player` (going round the circle of players still in) who has neither
## stood nor busted; `player` itself counts last unless `exclude_self`. -1 if nobody is drawing.
func _next_active_after(player: int, exclude_self: bool) -> int:
	var n: int = alive.size()
	var start: int = alive.find(player)
	if start == -1 or n == 0:
		return -1
	for step: int in range(1, n + 1):
		var p: int = alive[(start + step) % n]
		if exclude_self and p == player:
			continue
		if not standing[p] and not busted[p]:
			return p
	return -1


## One card from the shared shoe to `player`.
func _deal(player: int, opening: bool = false) -> void:
	var card: int = shoe.draw()
	last_card = card
	(hands[player] as Array).append(card)
	var t: int = _total(player)
	if t > BLACKJACK:
		busted[player] = true
	events.append(GameEvents.make(&"bust_or_bank_card", {
		"player": player,
		"card": card,
		"total": t,
		"busted": busted[player],
		"opening": opening,
	}))


## `reason`: &"choice", &"timeout" (no decision in time), &"21" (hit to 21), &"round_cap" or
## &"game_cap" (time ran out).
func _stand(player: int, reason: StringName) -> void:
	standing[player] = true
	events.append(GameEvents.make(&"bust_or_bank_player_stood", {
		"player": player,
		"total": _total(player),
		"auto": reason != &"choice",
		"reason": reason,
	}))


## Who goes out after this round: everyone who busted, else the lowest standing total (all who
## share it); nobody when that would be everyone still in. Returns [out: Array[int], why].
func _eliminations() -> Array:
	var out: Array[int] = []
	if alive.size() <= 1:
		return [out, &"none"]
	for p: int in alive:
		if busted[p]:
			out.append(p)
	var why: StringName = &"busted"
	if out.is_empty():
		why = &"lowest"
		var lowest: int = BLACKJACK + 1
		for p: int in alive:
			lowest = mini(lowest, _total(p))
		for p: int in alive:
			if _total(p) == lowest:
				out.append(p)
	if out.size() >= alive.size():
		out.clear()
		why = &"replay"
	return [out, why]


func _end_round() -> void:
	state = State.RESULT
	timer = RESULT_TIME
	current = -1
	var verdict: Array = _eliminations()
	last_out.assign(verdict[0])
	last_why = verdict[1]
	for p: int in last_out:
		out_round[p] = round_no
		out_score[p] = _score(p)
		alive.erase(p)
	var lowest: int = -1
	if last_why == &"lowest" and not last_out.is_empty():
		lowest = _total(last_out[0])
	final = alive.size() <= 1 or round_no >= max_rounds or game_time >= GAME_CAP
	events.append(GameEvents.make(&"bust_or_bank_round_end", {
		"round": round_no,
		"hands": _hands_public(),
		"out": last_out.duplicate(),
		"why": last_why,
		"lowest": lowest,
		"survivors": alive.duplicate(),
		"final": final,
	}))
	if final:
		_end_game()


## The game is decided: the final ranking goes out and shows for `RESULT_TIME`.
func _end_game() -> void:
	final = true
	state = State.RESULT
	timer = RESULT_TIME
	current = -1
	_ranking = _compute_ranking()
	events.append(GameEvents.make(&"bust_or_bank_finished", {
		"round": round_no,
		"hands": _hands_public(),
		"ranking": _ranking.duplicate(true),
		"points": points(),
		"winners": winners(),
	}))


## Ends right away (nobody at the table).
func _finish() -> void:
	state = State.DONE
	final = true
	finished = true
	current = -1
	_ranking.clear()
	events.append(GameEvents.make(&"bust_or_bank_finished", {
		"round": round_no, "hands": {}, "ranking": [], "points": {}, "winners": [],
	}))


func _total(player: int) -> int:
	var cards: Array[int] = []
	cards.assign(hands.get(player, []))
	return HandEval.total(cards) if not cards.is_empty() else 0


# --- Scoring -----------------------------------------------------------------------------------

## A hand's worth: the total, or -1 for a bust (below every standing hand).
func _score(player: int) -> int:
	return -1 if busted.get(player, false) else _total(player)


## Sort key, compared left to right (bigger is better): still in above out, a later round out
## above an earlier one, then the hand. The last player in wins whatever their hand.
func _key(player: int) -> Array[int]:
	if out_round.has(player):
		return [0, out_round[player], out_score[player]]
	if alive.size() == 1:
		return [1, 0, 0]
	return [1, 0, _score(player)]


static func _better(a: Array[int], b: Array[int]) -> bool:
	for i: int in a.size():
		if a[i] != b[i]:
			return a[i] > b[i]
	return false


## [{player, rank, points, total, busted, out_round}] best first (standard competition ranking:
## 1, 2, 2, 4 …; ties in seat order). `out_round` is 0 for players still in. Points = the number
## of players ranked below you, so a shared rank shares the points.
func ranking() -> Array[Dictionary]:
	if not _ranking.is_empty():
		return _ranking
	return _compute_ranking()


func _compute_ranking() -> Array[Dictionary]:
	var sorted: Array[int] = order.duplicate()
	var seat: Dictionary[int, int] = {}
	for i: int in order.size():
		seat[order[i]] = i
	sorted.sort_custom(func(a: int, b: int) -> bool:
		var ka: Array[int] = _key(a)
		var kb: Array[int] = _key(b)
		return _better(ka, kb) if ka != kb else seat[a] < seat[b])
	var out: Array[Dictionary] = []
	for i: int in sorted.size():
		var p: int = sorted[i]
		var rank: int = i + 1
		if i > 0 and _key(p) == _key(sorted[i - 1]):
			rank = int(out[i - 1]["rank"])
		out.append({"player": p, "rank": rank, "points": 0, "total": _total(p),
			"busted": bool(busted.get(p, false)), "out_round": int(out_round.get(p, 0))})
	for row: Dictionary in out:
		var below: int = 0
		for other: Dictionary in out:
			if int(other["rank"]) > int(row["rank"]):
				below += 1
		row["points"] = below
	return out


## player → points (see `ranking`).
func points() -> Dictionary[int, int]:
	var pts: Dictionary[int, int] = {}
	for row: Dictionary in ranking():
		pts[int(row["player"])] = int(row["points"])
	return pts


## Everyone sharing rank 1 (empty while nobody is at the table).
func winners() -> Array[int]:
	var out: Array[int] = []
	for row: Dictionary in ranking():
		if int(row["rank"]) == 1:
			out.append(int(row["player"]))
	return out


# --- Snapshots ---------------------------------------------------------------------------------

func _hands_public() -> Dictionary[int, Dictionary]:
	var out: Dictionary[int, Dictionary] = {}
	for p: int in order:
		out[p] = {
			"cards": (hands.get(p, []) as Array).duplicate(),
			"total": _total(p),
			"busted": busted.get(p, false),
			"stood": standing.get(p, false),
			"out": out_round.get(p, 0),
		}
	return out


func get_public_state() -> Dictionary:
	var st: Dictionary = {
		"state": state,
		"timer": snappedf(maxf(timer, 0.0), 0.01),
		"turn_time": TURN_TIME,
		"round": round_no,
		"max_rounds": max_rounds,
		"players": order.duplicate(),
		"survivors": alive.duplicate(),
		"out": out_round.duplicate(),
		"current": current,
		"turn": turn,
		"hands": _hands_public(),
		"last_card": last_card,
		"final": final,
	}
	if state == State.RESULT or state == State.DONE:
		st["last_out"] = last_out.duplicate()
		st["why"] = last_why
	if final:
		st["ranking"] = ranking().duplicate(true)
		st["points"] = points()
		st["winners"] = winners()
	return st


func private_state(player: int) -> Dictionary:
	return {"my_turn": state == State.TURN and player == current, "out": out_round.has(player)}
