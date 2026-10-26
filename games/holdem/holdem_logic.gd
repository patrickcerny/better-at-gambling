class_name HoldemLogic
extends StationLogicBase
## Casino Hold'em (Patrick: "2 card texas holdem against dealer (the one with ante and bonus
## play). Orient yourself on the bwin game"): Texas Hold'em against the house, as bwin runs it
## with Evolution's table. Up to four seats play their own hands against one dealer hand and one
## board, everyone at once.
##
## IDLE → BETTING (the window opens on the first ante; others can still ante) → deal: two hole
## cards to every hand, two face down to the dealer, the flop → DECIDING (everyone at once, each on
## their own clock; out of time = FOLD, the real rule) → showdown: turn, river, the dealer turns
## over → PAYOUT → IDLE. One fresh 52-card deck, shuffled from the server's rng, per hand.
##
## FOLD loses the ante. CALL puts up twice the ante. At the showdown the dealer qualifies with a
## pair of fours or better: if not, the ante pays by the ante paytable and the call pushes; if so,
## the better five of seven cards wins (ante by the paytable, call 1:1), a tie pushes both and a
## dealer win takes both. The optional AA Bonus pays on the player's first five cards (hole cards
## and flop) whatever the player does next; it settles as soon as the flop is out. The money is
## decided here only: the clients show what the public state says.
##
## The house rule (0.9.6, Patrick: "always favoured to win for you, by a bit, like the other
## games, but dont show it"): a showdown no called hand would win (and one would lose) has its
## unseen cards drawn again once with `holdem_favour` chance, a flop that pays no bonus bet with
## `holdem_bonus_favour` chance; then every player's luck rerolls like every other table's cards.
## Nothing of it reaches a client. The dealer's two cards lie face down from the deal, so which two
## they are is only drawn at the showdown (nobody can tell the difference).

enum State { IDLE, BETTING, DECIDING, PAYOUT }

const SEATS: int = 4
## A hand's decision.
const CALL: StringName = &"call"
const FOLD: StringName = &"fold"
## Felt spot names (the bet types in `bet_placed` / `round_result` details).
const ANTE: StringName = &"ante"
const BONUS: StringName = &"bonus"
const CALL_BET: StringName = &"call"

var seat_count: int = SEATS
var seats: Array[int] = []
var state: State = State.IDLE
var timer: float = 0.0
## player → {ante, bonus, call, covered (Fake Cash part of each, per spot), hole: Array[int],
## decision (&"" / call / fold), clock, settled (the ante and call), bonus_settled, gone (stood up
## before the deal), outcome, returned, bonus_returned}.
var hands: Dictionary[int, Dictionary] = {}
## The community cards: the flop, then all five after the showdown.
var board: Array[int] = []
## The dealer's two cards (empty until the showdown draws them).
var dealer: Array[int] = []
var dealer_score: int = -1
## The deck still to deal (the top is the back of the array).
var deck: Array[int] = []
var hands_played: int = 0
## Tests and dev shots: cards the next deal deals first, in deal order (hole cards seat by seat,
## the flop, then turn, river and the dealer's two at the showdown).
var rigged: Array[int] = []


func _on_setup() -> void:
	game_id = &"holdem"
	seats.clear()
	for i: int in seat_count:
		seats.append(-1)


func can_join(p: int) -> bool:
	return p in seats or -1 in seats


func join(p: int) -> Dictionary:
	if p in seats:
		return OK_RESULT
	var idx: int = seats.find(-1)
	if idx < 0:
		return fail(&"seat_taken")
	seats[idx] = p
	if hands.has(p):
		hands[p]["gone"] = false  # back before the deal: the hand is yours to play again
	return OK_RESULT


## Standing up: an ante still waiting for the deal is dealt and then folds (its bonus still plays);
## a hand that has not decided folds at once (the table's auto rule, like the clock running out). A
## called hand plays on to the showdown.
func leave(p: int) -> void:
	var idx: int = seats.find(p)
	if idx >= 0:
		seats[idx] = -1
	if not hands.has(p):
		return
	if state == State.BETTING:
		hands[p]["gone"] = true
	elif state == State.DECIDING and hands[p]["decision"] == &"":
		_fold(p)
		_check_all_done()


## Ante limits after the limits multiplier.
func limits() -> Vector2i:
	return Vector2i(scaled(balance.holdem_min_bet), scaled(balance.holdem_max_bet))


## AA Bonus limits after the limits multiplier.
func bonus_limits() -> Vector2i:
	return Vector2i(scaled(balance.holdem_min_bet), scaled(balance.holdem_bonus_max_bet))


## All-in: an ante over the max bets the max; one over the balance bets what still leaves the call
## (twice the ante) covered after the bonus.
func clamp_bet(p: int, bet: Dictionary) -> Dictionary:
	var out: Dictionary = bet.duplicate()
	out.erase("all_in")
	out.erase("requested")
	if not out.has("amount"):
		return out
	var lim: Vector2i = limits()
	var requested: int = int(out["amount"])
	var bonus: int = maxi(int(out.get("bonus", 0)), 0)
	var res: Dictionary = BetClamp.resolve(requested, maxi(stake_available(p) - bonus, 0) / 3, lim.x, lim.y)
	if res["error"] != &"":
		return out
	out["amount"] = int(res["amount"])
	if bool(res["all_in"]):
		out["all_in"] = true
		out["requested"] = requested
	return out


func bet_limits(_p: int, _bet: Dictionary) -> Vector2i:
	return limits()


## Bet shape: `{amount}` (the ante) and optionally `bonus` (the AA Bonus, 0 = none). One hand per
## player per deal. The balance has to cover the call as well (three times the ante, plus the
## bonus), as at the real table.
func place_bet(p: int, bet: Dictionary) -> Dictionary:
	if not p in seats:
		return fail(&"not_seated")
	if state != State.IDLE and state != State.BETTING:
		return fail(&"betting_closed")
	if hands.has(p):
		return fail(&"already_bet")
	var amount: int = int(bet.get("amount", 0))
	var bonus: int = int(bet.get("bonus", 0))
	var lim: Vector2i = limits()
	if amount < lim.x:
		return fail(&"below_min")
	if amount > lim.y:
		return fail(&"above_max")
	var blim: Vector2i = bonus_limits()
	if bonus < 0 or (bonus > 0 and bonus < blim.x):
		return fail(&"below_min")
	if bonus > blim.y:
		return fail(&"above_max")
	if stake_available(p) < amount * 3 + bonus:
		return fail(&"insufficient_funds")
	if not _take_stake(p, amount):
		return fail(&"insufficient_funds")
	var covered: int = last_covered
	var bonus_covered: int = 0
	if bonus > 0:
		if not _take_stake(p, bonus):
			_refund(p, amount, covered, {})  # can't happen after the check above; never keep half a bet
			return fail(&"insufficient_funds")
		bonus_covered = last_covered
	hands[p] = {
		"ante": amount, "bonus": bonus, "call": 0, "covered": covered, "bonus_covered": bonus_covered, "call_covered": 0,
		"hole": [] as Array[int], "decision": &"", "clock": 0.0, "settled": false, "bonus_settled": bonus == 0,
		"gone": false, "outcome": &"", "returned": 0, "bonus_returned": -1,
	}
	events.append(GameEvents.bet_placed(p, station_id, amount, with_all_in(bet, {"game": game_id, "type": ANTE})))
	if bonus > 0:
		events.append(GameEvents.bet_placed(p, station_id, bonus, {"game": game_id, "type": BONUS}))
	if state == State.IDLE:
		state = State.BETTING
		timer = balance.holdem_betting_window
		events.append(GameEvents.make(&"round_started", {"station": station_id, "betting_window": timer}))
	return OK_RESULT


## `call` (twice the ante) or `fold`, once per hand while the flop is out.
func player_action(p: int, action: StringName, _params: Dictionary = {}) -> Dictionary:
	if state != State.DECIDING:
		return fail(&"wrong_state")
	if not hands.has(p) or hands[p]["decision"] != &"":
		return fail(&"no_active_hand")
	var h: Dictionary = hands[p]
	match action:
		CALL:
			var amount: int = int(h["ante"]) * 2
			if not _take_stake(p, amount):
				return fail(&"insufficient_funds")
			h["call"] = amount
			h["call_covered"] = last_covered
			h["decision"] = CALL
			events.append(GameEvents.bet_placed(p, station_id, amount, {"game": game_id, "type": CALL_BET}))
			events.append(GameEvents.make(&"holdem_action", {"station": station_id, "player": p, "action": CALL}))
		FOLD:
			_fold(p)
		_:
			return fail(&"unknown_action")
	_check_all_done()
	return OK_RESULT


func tick(delta: float) -> void:
	if _fast_for(seats.filter(func(x: int) -> bool: return x >= 0)):
		delta *= 2.0  # Energy Drink, alone at the table
	match state:
		State.BETTING:
			timer -= delta
			if timer <= 0.0:
				_deal()
		State.DECIDING:
			# Every player on their own clock; out of time = fold.
			for p: int in hands.keys():
				var h: Dictionary = hands[p]
				if h["decision"] != &"":
					continue
				h["clock"] = float(h["clock"]) - delta
				if float(h["clock"]) <= 0.0:
					_fold(p)
			timer = _longest_clock()
			_check_all_done()
		State.PAYOUT:
			timer -= delta
			if timer <= 0.0:
				_end_round()


func _longest_clock() -> float:
	var out: float = 0.0
	for p: int in hands.keys():
		if hands[p]["decision"] == &"":
			out = maxf(out, float(hands[p]["clock"]))
	return out


func round_seconds() -> float:
	# The rest of the betting window, then at least a few seconds of play and the showdown.
	return (timer if state == State.BETTING else balance.holdem_betting_window) + 4.0


func has_stake(p: int) -> bool:
	return hands.has(p) and not (bool(hands[p]["settled"]) and bool(hands[p]["bonus_settled"]))


## The match is over: the cards are dealt, every open decision folds (the auto rule) and the hand
## is played out.
func auto_resolve() -> void:
	if state == State.BETTING:
		_deal()
	if state == State.DECIDING:
		for p: int in hands.keys():
			if hands[p]["decision"] == &"":
				_fold(p)
		_check_all_done()
	if state == State.PAYOUT:
		_end_round()


## A minigame starts: every ante and call still open comes back in full (no loss, no win), and so
## does a bonus before the flop. A bonus the flop already settled stays settled, and so does a
## folded ante: they were played (like blackjack's paid naturals).
func refund_all() -> void:
	if state == State.IDLE and hands.is_empty():
		return
	var totals: Dictionary = {}
	for p: int in hands.keys():
		var h: Dictionary = hands[p]
		if not bool(h["bonus_settled"]):
			_refund(p, int(h["bonus"]), int(h["bonus_covered"]), totals)
		if not bool(h["settled"]):
			_refund(p, int(h["ante"]), int(h["covered"]), totals)
			if int(h["call"]) > 0:
				_refund(p, int(h["call"]), int(h["call_covered"]), totals)
		if bool(h["settled"]) or (int(h["bonus"]) > 0 and int(h["bonus_returned"]) >= 0):
			modifiers.consume_round(p, game_id)  # something of this hand was played
	hands.clear()
	board.clear()
	dealer.clear()
	dealer_score = -1
	deck.clear()
	state = State.IDLE
	timer = 0.0
	_emit_refunds(totals)


func get_public_state() -> Dictionary:
	var hs: Dictionary = {}
	var revealed: bool = dealer.size() == 2
	for p: int in hands.keys():
		var h: Dictionary = hands[p]
		var hole: Array[int] = h["hole"]
		var row: Dictionary = {
			"ante": h["ante"], "bonus": h["bonus"], "call": h["call"], "hole": hole.duplicate(),
			"decision": h["decision"], "outcome": h["outcome"], "returned": h["returned"], "bonus_returned": h["bonus_returned"],
		}
		if not hole.is_empty():
			var mine: Array[int] = hole.duplicate()
			mine.append_array(board)
			var score: int = HoldemHand.evaluate(mine)
			row["rank"] = HoldemHand.category(score)
			row["hand"] = HoldemHand.describe(score)
			if revealed and h["decision"] == CALL:
				row["best"] = HoldemHand.best_five(mine)
		if state == State.DECIDING and h["decision"] == &"":
			row["clock"] = maxf(float(h["clock"]), 0.0)
		hs[p] = row
	var out: Dictionary = {
		"game": game_id, "state": state, "timer": timer, "seats": seats.duplicate(), "hands": hs,
		"board": board.duplicate(), "dealer": dealer.duplicate(), "dealer_down": 2 if state == State.DECIDING else 0,
	}
	if revealed:
		out["dealer_hand"] = HoldemHand.describe(dealer_score)
		out["dealer_rank"] = HoldemHand.category(dealer_score)
		out["qualifies"] = HoldemHand.dealer_qualifies(dealer_score)
		var all: Array[int] = dealer.duplicate()
		all.append_array(board)
		out["dealer_best"] = HoldemHand.best_five(all)
	return out


# --- Play ---------------------------------------------------------------------------------------


## A fresh deck; two hole cards to every hand, the flop; the bonuses settle; the clocks start.
func _deal() -> void:
	if hands.is_empty():
		state = State.IDLE
		return
	deck.clear()
	for c: int in 52:
		deck.append(c)
	rng.shuffle(deck)
	for i: int in range(rigged.size() - 1, -1, -1):
		deck.erase(rigged[i])
		deck.append(rigged[i])
	rigged.clear()
	board.clear()
	dealer.clear()
	dealer_score = -1
	var order: Array[int] = _seat_order()
	for p: int in order:
		hands[p]["hole"] = _draw_hole(p)
	board = _draw_flop(order)
	events.append(GameEvents.make(&"cards_dealt", {"station": station_id, "board": board.duplicate()}))
	for p: int in order:
		var h: Dictionary = hands[p]
		if int(h["bonus"]) > 0:
			_settle_bonus(p)
	state = State.DECIDING
	for p: int in order:
		hands[p]["clock"] = balance.holdem_action_time
		if bool(hands[p]["gone"]):
			_fold(p)  # stood up before the deal
	timer = _longest_clock()
	_check_all_done()


## Players with a hand, in seat order (then anyone who stood up before the deal).
func _seat_order() -> Array[int]:
	var out: Array[int] = []
	for s: int in seats:
		if s >= 0 and hands.has(s):
			out.append(s)
	for p: int in hands.keys():
		if not p in out:
			out.append(p)
	return out


## Two hole cards; the player's luck may reroll the pair (judged by `preflop_strength`).
func _draw_hole(p: int) -> Array[int]:
	var lk: int = modifiers.get_luck(p, game_id)
	var d: LuckRng.Draw = luck.draw(lk, func() -> Array[int]: return _take(2), func(cards: Array[int]) -> float: return preflop_strength(cards))
	if d.rerolled:
		_put_back(d.rejected as Array[int])
	if d.luck_changed:
		events.append(GameEvents.luck_flourish(p, station_id, &"lucky" if lk > 0 else &"jinxed"))
	return d.value as Array[int]


## The flop: drawn again once with `holdem_bonus_favour` chance when no bonus bet would pay, then
## every player's luck rerolls it (judged by their best five cards so far).
func _draw_flop(order: Array[int]) -> Array[int]:
	var current: Array = [_take(3)]
	if _bonus_out() and not _any_bonus_pays(current[0]) and rng.chance(balance.holdem_bonus_favour):
		_put_back(current[0])
		current[0] = _take(3)
	for p: int in order:
		var lk: int = modifiers.get_luck(p, game_id)
		if lk == 0:
			continue
		var hole: Array[int] = hands[p]["hole"]
		var d: LuckRng.Draw = luck.draw(lk, func() -> Array[int]:
			var out: Array[int] = current[0]
			current[0] = _take(3)
			return out, func(flop: Array[int]) -> float:
			var five: Array[int] = hole.duplicate()
			five.append_array(flop)
			return float(HoldemHand.evaluate(five)))
		if d.rerolled:
			_put_back(d.rejected as Array[int])
		current[0] = d.value
		if d.luck_changed:
			events.append(GameEvents.luck_flourish(p, station_id, &"lucky" if lk > 0 else &"jinxed"))
	return current[0] as Array[int]


func _bonus_out() -> bool:
	for p: int in hands:
		if int(hands[p]["bonus"]) > 0:
			return true
	return false


func _any_bonus_pays(flop: Array[int]) -> bool:
	for p: int in hands:
		var h: Dictionary = hands[p]
		if int(h["bonus"]) <= 0:
			continue
		var five: Array[int] = (h["hole"] as Array[int]).duplicate()
		five.append_array(flop)
		if bonus_pay(HoldemHand.evaluate(five), balance) > 0:
			return true
	return false


func _settle_bonus(p: int) -> void:
	var h: Dictionary = hands[p]
	var five: Array[int] = (h["hole"] as Array[int]).duplicate()
	five.append_array(board)
	var score: int = HoldemHand.evaluate(five)
	var stake: int = int(h["bonus"])
	var ret: int = bonus_return(stake, score, balance)
	h["bonus_settled"] = true
	h["bonus_returned"] = _settle(p, stake, ret, {"type": BONUS, "outcome": &"bonus_win" if ret > 0 else &"bonus_lose", "rank": HoldemHand.category(score), "hand": HoldemHand.describe(score), "cards": five})


func _fold(p: int) -> void:
	var h: Dictionary = hands[p]
	h["decision"] = FOLD
	h["settled"] = true
	h["outcome"] = FOLD
	h["returned"] = _settle(p, int(h["ante"]), 0, {"type": ANTE, "outcome": FOLD, "cards": (h["hole"] as Array[int]).duplicate()})
	events.append(GameEvents.make(&"holdem_action", {"station": station_id, "player": p, "action": FOLD}))


func _check_all_done() -> void:
	if state != State.DECIDING:
		return
	for p: int in hands.keys():
		if hands[p]["decision"] == &"":
			return
	_showdown()


## Turn, river and the dealer's two cards (one draw of the four unseen cards, with the house rule
## and the players' luck), then every called hand is paid.
func _showdown() -> void:
	var callers: Array[int] = []
	for p: int in _seat_order():
		if hands[p]["decision"] == CALL:
			callers.append(p)
	var current: Array = [_take(4)]
	if not callers.is_empty() and _nobody_wins_somebody_loses(callers, current[0]) and rng.chance(balance.holdem_favour):
		_put_back(current[0])
		current[0] = _take(4)
	for p: int in callers:
		var lk: int = modifiers.get_luck(p, game_id)
		if lk == 0:
			continue
		var d: LuckRng.Draw = luck.draw(lk, func() -> Array[int]:
			var out: Array[int] = current[0]
			current[0] = _take(4)
			return out, func(rest: Array[int]) -> float: return float(_net_for(p, rest)))
		if d.rerolled:
			_put_back(d.rejected as Array[int])
		current[0] = d.value
		if d.luck_changed:
			events.append(GameEvents.luck_flourish(p, station_id, &"lucky" if lk > 0 else &"jinxed"))
	var rest: Array[int] = current[0]
	board.append_array(rest.slice(0, 2))
	dealer = rest.slice(2, 4)
	var all: Array[int] = dealer.duplicate()
	all.append_array(board)
	dealer_score = HoldemHand.evaluate(all)
	var qualifies: bool = HoldemHand.dealer_qualifies(dealer_score)
	events.append(GameEvents.make(&"holdem_showdown", {"station": station_id, "board": board.duplicate(), "dealer": dealer.duplicate(), "dealer_hand": HoldemHand.describe(dealer_score), "qualifies": qualifies}))
	for p: int in callers:
		var h: Dictionary = hands[p]
		var cards: Array[int] = (h["hole"] as Array[int]).duplicate()
		cards.append_array(board)
		var score: int = HoldemHand.evaluate(cards)
		var ante: int = int(h["ante"])
		var call: int = int(h["call"])
		var outcome: StringName = main_outcome(score, dealer_score)
		var ret: int = main_return(ante, call, score, dealer_score, balance)
		h["settled"] = true
		h["outcome"] = outcome
		h["returned"] = _settle(p, ante + call, ret, {
			"type": ANTE, "outcome": outcome, "rank": HoldemHand.category(score), "hand": HoldemHand.describe(score),
			"dealer_hand": HoldemHand.describe(dealer_score), "cards": cards, "dealer": dealer.duplicate(),
		})
	state = State.PAYOUT
	timer = balance.holdem_result_time


## What player `p`'s called hand nets (ante + call) with these four unseen cards
## ([turn, river, dealer, dealer]).
func _net_for(p: int, rest: Array[int]) -> int:
	var h: Dictionary = hands[p]
	var b: Array[int] = board.duplicate()
	b.append_array(rest.slice(0, 2))
	var mine: Array[int] = (h["hole"] as Array[int]).duplicate()
	mine.append_array(b)
	var theirs: Array[int] = rest.slice(2, 4)
	theirs.append_array(b)
	var ante: int = int(h["ante"])
	var call: int = int(h["call"])
	return main_return(ante, call, HoldemHand.evaluate(mine), HoldemHand.evaluate(theirs), balance) - ante - call


## True when the four unseen cards make no called hand win and at least one lose.
func _nobody_wins_somebody_loses(callers: Array[int], rest: Array[int]) -> bool:
	var loses: bool = false
	for p: int in callers:
		var net: int = _net_for(p, rest)
		if net > 0:
			return false
		if net < 0:
			loses = true
	return loses


func _end_round() -> void:
	for p: int in hands.keys():
		modifiers.consume_round(p, game_id)
	hands_played += 1
	hands.clear()
	board.clear()
	dealer.clear()
	dealer_score = -1
	deck.clear()
	state = State.IDLE


# --- Deck ---------------------------------------------------------------------------------------


func _take(n: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in n:
		out.append(deck.pop_back())
	return out


## Cards passed over go back into the deck at random places.
func _put_back(cards: Array[int]) -> void:
	for c: int in cards:
		deck.insert(rng.range_int(0, deck.size()), c)


# --- Rules (pure) -------------------------------------------------------------------------------


## &"win", &"push", &"lose" or &"no_qualify" (the dealer has less than a pair of fours) for a called
## hand's score against the dealer's.
static func main_outcome(player_score: int, dealer_score_in: int) -> StringName:
	if not HoldemHand.dealer_qualifies(dealer_score_in):
		return &"no_qualify"
	if player_score > dealer_score_in:
		return &"win"
	if player_score == dealer_score_in:
		return &"push"
	return &"lose"


## What a called hand returns (ante and call together, stakes included): the dealer does not
## qualify → ante paid by the paytable, call back; the player wins → ante by the paytable and the
## call 1:1; a tie → both back; the dealer wins → nothing.
static func main_return(ante: int, call: int, player_score: int, dealer_score_in: int, cfg: BalanceConfig) -> int:
	var pay: int = ante_pay(HoldemHand.category(player_score), cfg)
	match main_outcome(player_score, dealer_score_in):
		&"no_qualify":
			return ante * (1 + pay) + call
		&"win":
			return ante * (1 + pay) + call * 2
		&"push":
			return ante + call
	return 0


## The ante paytable (profit per $1) for a hand category.
static func ante_pay(cat: int, cfg: BalanceConfig) -> int:
	return cfg.holdem_ante_pays[clampi(cat, 0, cfg.holdem_ante_pays.size() - 1)]


## The AA Bonus pay (profit per $1) for a five-card score: a pair only counts when it is aces.
static func bonus_pay(score: int, cfg: BalanceConfig) -> int:
	var cat: int = HoldemHand.category(score)
	if cat == HoldemHand.Rank.HIGH_CARD:
		return 0
	if cat == HoldemHand.Rank.PAIR and HoldemHand.kicker(score, 0) != HoldemHand.ACE:
		return 0
	return cfg.holdem_bonus_pays[clampi(cat, 0, cfg.holdem_bonus_pays.size() - 1)]


## What an AA Bonus of `stake` returns on a five-card score (stake included; 0 = lost).
static func bonus_return(stake: int, score: int, cfg: BalanceConfig) -> int:
	var pay: int = bonus_pay(score, cfg)
	return stake * (1 + pay) if pay > 0 else 0


## Luck's measure of two hole cards: a pair beats any two different cards, then high cards, a suit
## in common and neighbours count.
static func preflop_strength(hole: Array[int]) -> float:
	if hole.size() < 2:
		return 0.0
	var a: int = HoldemHand.value(hole[0])
	var b: int = HoldemHand.value(hole[1])
	if a == b:
		return 100.0 + a * 2.0
	var hi: int = maxi(a, b)
	var lo: int = mini(a, b)
	var out: float = hi * 2.0 + lo
	if Card.suit(hole[0]) == Card.suit(hole[1]):
		out += 3.0
	if hi - lo == 1 or (hi == HoldemHand.ACE and lo == 2):
		out += 2.0
	return out


## The simple strategy the RTP sim and the autoplay use: call with a pair or better, a flush or
## straight draw, or an ace or a king in the hole; fold with nothing else (about one hand in four).
static func simple_call(hole: Array[int], flop: Array[int]) -> bool:
	var five: Array[int] = hole.duplicate()
	five.append_array(flop)
	if HoldemHand.category(HoldemHand.evaluate(five)) >= HoldemHand.Rank.PAIR:
		return true
	for c: int in hole:
		if HoldemHand.value(c) >= 13:
			return true
	return HoldemHand.has_flush_draw(five) or HoldemHand.has_straight_draw(five)
