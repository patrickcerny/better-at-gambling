class_name BustOrBankLogic
extends MinigameLogicBase
## "Bust or Bank" minigame: one hand of turn-based blackjack around a shared table.
##
## Everyone gets ONE face-up card from a shared shoe (seat order: the order the minigame was set up
## with). Then the turns go round the table in a circle: on your turn you have `TURN_TIME` seconds
## to HIT (take exactly one card, then the turn passes on) or STAND (your hand is locked and you are
## done for the round). No decision in time = STAND. Over 21 busts you on the spot; hitting to 21
## stands you automatically (you can't do better). The circle skips players who stood or busted, so
## a lone player still in keeps taking turns until they stand or bust.
##
## The upcoming card is no secret: `next_card` (the shoe's top card) is shown face up to everyone in
## every event and in the snapshot, so the decision is "do I want THAT card?".
##
## The round ends when nobody is left drawing. Highest total wins (21 best, a two-card blackjack is
## just 21); equal totals share a rank; busted players rank below every standing hand and share one
## rank. Points = hand total for standing players, 0 for busted ones.
##
## Events: `bust_or_bank_started`, `bust_or_bank_round_started` (opening deal in `deal_in` s),
## `bust_or_bank_card` (one per card dealt, the opening cards too), `bust_or_bank_turn`,
## `bust_or_bank_player_stood`, `bust_or_bank_player_left`, `bust_or_bank_round_end` (hands, ranking, points, winners).

enum State { INTRO, TURN, RESULT, DONE }

## Seconds the empty table is shown before the opening cards land and the first turn starts.
const INTRO_TIME: float = 3.0
## Seconds a player has to HIT or STAND; then they stand automatically.
const TURN_TIME: float = 20.0
## Seconds the final hands are shown before the minigame ends.
const RESULT_TIME: float = 5.0
const SHOE_DECKS: int = 2
const BLACKJACK: int = 21

var state: State = State.INTRO
## Seconds left in the current state (intro, the current turn, the result).
var timer: float = 0.0
var shoe: Shoe
## Seat order: the circle the turns go round. Players who left are removed.
var order: Array[int] = []
var hands: Dictionary[int, Array] = {}  # player → Array[int] of cards
var standing: Dictionary[int, bool] = {}
var busted: Dictionary[int, bool] = {}
## Whose turn it is (-1 outside TURN).
var current: int = -1
## Turns started so far (0 before the first).
var turn: int = 0
var last_card: int = -1
## The card the shoe deals next, shown face up to everyone (-1 once the round is over). It is
## always the shoe's top card, so `shoe.stack_top` decides the order (tests and tutorial scripting).
var next_card: int:
	get:
		if shoe == null or state == State.RESULT or state == State.DONE:
			return -1
		return shoe.peek()


func _on_setup(_context: Dictionary) -> void:
	shoe = Shoe.new(rng, SHOE_DECKS)
	order = players.duplicate()
	for p: int in order:
		hands[p] = [] as Array[int]
		standing[p] = false
		busted[p] = false
	events.append(GameEvents.make(&"bust_or_bank_started", {
		"players": order.duplicate(),
		"turn_time": TURN_TIME,
	}))
	if order.is_empty():
		_finish()
		return
	state = State.INTRO
	timer = INTRO_TIME
	events.append(GameEvents.make(&"bust_or_bank_round_started", {
		"players": order.duplicate(),
		"deal_in": INTRO_TIME,
		"turn_time": TURN_TIME,
		"next_card": next_card,
	}))


func tick(delta: float, _now: float) -> void:
	if finished:
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
		State.RESULT, State.DONE:
			state = State.DONE
			finished = true


## HIT (one card, then the next player's turn) or STAND (locked for the round), on your turn only.
func submit(player: int, intent: Dictionary, _now: float) -> Dictionary:
	if player not in order:
		return StationLogicBase.fail(&"not_in_game")
	if finished or state == State.RESULT or state == State.DONE:
		return StationLogicBase.fail(&"game_over")
	var action: String = str(intent.get("action", "")).to_lower()
	if action != "hit" and action != "stand":
		return StationLogicBase.fail(&"invalid_action")
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
## their turn, the turn passes to the next player still in.
func remove_player(player: int) -> void:
	if player not in order:
		super.remove_player(player)
		return
	var was_current: bool = state == State.TURN and player == current
	var next_p: int = _next_active_after(player, true) if was_current else -1
	super.remove_player(player)
	order.erase(player)
	hands.erase(player)
	standing.erase(player)
	busted.erase(player)
	if finished or state == State.RESULT or state == State.DONE:
		return
	events.append(GameEvents.make(&"bust_or_bank_player_left", {"player": player, "players": order.duplicate()}))
	if order.is_empty():
		_finish()
	elif order.size() == 1 and state != State.INTRO:
		_end_round()  # nobody left to play against: the last one at the table wins
	elif was_current:
		if next_p == -1:
			_end_round()
		else:
			_start_turn(next_p)


# --- Round flow --------------------------------------------------------------------------------

## One face-up card to everyone in seat order, then the first turn.
func _opening_deal() -> void:
	for p: int in order:
		_deal(p, true)
	if order.size() <= 1:
		_end_round()
		return
	_start_turn(order[0])


func _start_turn(player: int) -> void:
	state = State.TURN
	current = player
	timer = TURN_TIME
	turn += 1
	events.append(GameEvents.make(&"bust_or_bank_turn", {
		"player": player,
		"time": TURN_TIME,
		"turn": turn,
		"total": _total(player),
		"next_card": next_card,
	}))


## The turn after `player`'s: the next player in the circle still drawing (may be `player` again
## when they are the only one left), or the end of the round.
func _pass_turn(player: int) -> void:
	var nxt: int = _next_active_after(player, false)
	if nxt == -1:
		_end_round()
	else:
		_start_turn(nxt)


## The first player after `player` (going round the seat order) who has neither stood nor busted;
## `player` itself counts last unless `exclude_self`. -1 if nobody is left drawing.
func _next_active_after(player: int, exclude_self: bool) -> int:
	var n: int = order.size()
	var start: int = order.find(player)
	if start == -1 or n == 0:
		return -1
	for step: int in range(1, n + 1):
		var p: int = order[(start + step) % n]
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
		"next_card": next_card,
	}))


## `reason`: &"choice", &"timeout" (no decision in time) or &"21" (hit to 21).
func _stand(player: int, reason: StringName) -> void:
	standing[player] = true
	events.append(GameEvents.make(&"bust_or_bank_player_stood", {
		"player": player,
		"total": _total(player),
		"auto": reason != &"choice",
		"reason": reason,
	}))


func _end_round() -> void:
	state = State.RESULT
	timer = RESULT_TIME
	current = -1
	var rk: Array[Dictionary] = ranking()
	events.append(GameEvents.make(&"bust_or_bank_round_end", {
		"hands": _hands_public(),
		"ranking": rk.duplicate(true),
		"points": points(),
		"winners": winners(),
	}))


## Ends right away (nobody at the table).
func _finish() -> void:
	state = State.DONE
	finished = true
	current = -1
	events.append(GameEvents.make(&"bust_or_bank_round_end", {
		"hands": {}, "ranking": [], "points": {}, "winners": [],
	}))


func _total(player: int) -> int:
	var cards: Array[int] = []
	cards.assign(hands.get(player, []))
	return HandEval.total(cards) if not cards.is_empty() else 0


# --- Scoring -----------------------------------------------------------------------------------

## Hand total for standing (or still drawing) players, 0 for busted ones.
func points() -> Dictionary[int, int]:
	var out: Dictionary[int, int] = {}
	for p: int in order:
		out[p] = 0 if busted[p] else _total(p)
	return out


## Best-hand score: the total, or -1 for a bust (below every standing hand).
func _score(player: int) -> int:
	return -1 if busted[player] else _total(player)


## [{player, rank, points, total, busted}] best first: highest total first, equal totals share a
## rank, busted players share the last rank (standard competition ranking: 1, 2, 2, 4 …). Ties
## are listed in seat order.
func ranking() -> Array[Dictionary]:
	var sorted: Array[int] = order.duplicate()
	var seat: Dictionary[int, int] = {}
	for i: int in order.size():
		seat[order[i]] = i
	sorted.sort_custom(func(a: int, b: int) -> bool:
		var sa: int = _score(a)
		var sb: int = _score(b)
		return sa > sb if sa != sb else seat[a] < seat[b])
	var out: Array[Dictionary] = []
	var rank: int = 0
	var prev: int = -2
	for i: int in sorted.size():
		var p: int = sorted[i]
		var s: int = _score(p)
		if s != prev:
			rank = i + 1
			prev = s
		out.append({"player": p, "rank": rank, "points": 0 if busted[p] else _total(p), "total": _total(p), "busted": busted[p]})
	return out


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
		}
	return out


func get_public_state() -> Dictionary:
	var st: Dictionary = {
		"state": state,
		"timer": snappedf(maxf(timer, 0.0), 0.01),
		"turn_time": TURN_TIME,
		"players": order.duplicate(),
		"current": current,
		"turn": turn,
		"hands": _hands_public(),
		"last_card": last_card,
		"next_card": next_card,
		"points": points(),
	}
	if state == State.RESULT or state == State.DONE:
		st["ranking"] = ranking().duplicate(true)
		st["winners"] = winners()
	return st


func private_state(player: int) -> Dictionary:
	return {"my_turn": state == State.TURN and player == current}
