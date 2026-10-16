class_name HiLoLogic
extends StationLogicBase
## The Hi-Lo table (Patrick approved it as a new casino table): one dealer, four seats, everyone
## plays their own hand at their own pace from one shared single deck (aces high, 2 lowest).
##
## A hand: ante → the dealer turns a card face up → the player calls HIGHER or LOWER (a tie loses).
## Each call shows its true chance (counted from the cards still in the deck) and what it pays,
## locked the moment the card is shown. A right call multiplies the pot; then the player either
## cashes out or rides the pot on the next call (the streak ladder, up to `hilo_max_rungs` calls or
## `hilo_pot_cap` times the ante, where the hand cashes out on its own). A wrong call loses the
## pot. The deck is reshuffled when it runs low (checked before every ante).
##
## The house rule (Patrick, 0.9.6, "like the other tables, but dont show it"): when a call would
## lose, the server redraws the next card once with `hilo_favour` chance, then the player's luck
## rerolls it like any card. Nothing of it reaches a client; the printed pay is what the call
## returns on average with that favour counted (`pay_for`), never more than the fair odds.
##
## Everything here runs on the server; the clients only show the cards and numbers it publishes.

enum State { IDLE, PLAYING }

const SEATS: int = 4
## The two calls (also the keys of a hand's `odds` and `pays`: plain strings, so they read the
## same on every client after the snapshot round trip).
const HIGHER: String = "higher"
const LOWER: String = "lower"
## A hand's phase: calling (a card is up and the call is open) or done (the result shows a moment).
const PLAY: StringName = &"play"
const DONE: StringName = &"done"
## Hi-Lo value of an ace (aces high); 2 is the lowest card.
const ACE_HIGH: int = 14

var seats: Array[int] = []
## Player → hand: {stake, covered, cards: Array[int] (this hand's run, the last one is up), phase,
## rung (right calls so far), mult (pot ÷ ante), odds {higher, lower, tie}, pays {higher, lower},
## timer, outcome, guess (the last call)}.
var hands: Dictionary[int, Dictionary] = {}
## The single deck still to deal (the top is the back of the array).
var deck: Array[int] = []
var hands_played: int = 0
var reshuffles: int = 0


func _on_setup() -> void:
	game_id = &"hilo"
	seats.clear()
	for i: int in SEATS:
		seats.append(-1)
	_reshuffle()


func can_join(p: int) -> bool:
	return p in seats or -1 in seats


func join(p: int) -> Dictionary:
	if p in seats:
		return OK_RESULT
	var idx: int = seats.find(-1)
	if idx < 0:
		return fail(&"seat_taken")
	seats[idx] = p
	return OK_RESULT


## Standing up mid-hand settles it at once by the table's auto rule (`_auto_play`): a pot with a
## right call in it is cashed out, a fresh ante takes the likelier side.
func leave(p: int) -> void:
	var idx: int = seats.find(p)
	if idx >= 0:
		seats[idx] = -1
	if hands.has(p) and hands[p]["phase"] == PLAY:
		_auto_play(p)


## Min and max ante after the limits multiplier.
func limits() -> Vector2i:
	return Vector2i(scaled(balance.hilo_min_bet), scaled(balance.hilo_max_bet))


## All-in: an ante over the balance (or the max) bets what fits.
func bet_limits(_p: int, _bet: Dictionary) -> Vector2i:
	return limits()


## Bet shape: `{amount}` (the ante). One hand per player at a time.
func place_bet(p: int, bet: Dictionary) -> Dictionary:
	if not p in seats:
		return fail(&"not_seated")
	if hands.has(p) and hands[p]["phase"] == PLAY:
		return fail(&"already_bet")
	var amount: int = int(bet.get("amount", 0))
	var lim: Vector2i = limits()
	if amount < lim.x:
		return fail(&"below_min")
	if amount > lim.y:
		return fail(&"above_max")
	if not _take_stake(p, amount):
		return fail(&"insufficient_funds")
	hands.erase(p)  # a finished hand still showing its result makes way
	if deck.size() < balance.hilo_reshuffle_at:
		_reshuffle()
		events.append(GameEvents.make(&"hilo_reshuffle", {"station": station_id}))
	var first: int = _draw()
	var h: Dictionary = {"stake": amount, "covered": last_covered, "cards": [first] as Array[int], "phase": PLAY, "rung": 0, "mult": 1.0, "outcome": &"", "guess": "", "timer": 0.0}
	hands[p] = h
	_open_call(h)
	events.append(GameEvents.bet_placed(p, station_id, amount, with_all_in(bet, {"game": game_id})))
	events.append(GameEvents.make(&"hilo_dealt", {"station": station_id, "player": p, "card": first}))
	return OK_RESULT


## `higher` / `lower` make the call (on a pot with a right call in it, that is the ride);
## `cash_out` banks the pot once at least one call was right.
func player_action(p: int, action: StringName, _params: Dictionary = {}) -> Dictionary:
	if not hands.has(p) or hands[p]["phase"] != PLAY:
		return fail(&"no_active_hand")
	var h: Dictionary = hands[p]
	match action:
		&"higher", &"lower":
			if float((h["odds"] as Dictionary).get(String(action), 0.0)) <= 0.0:
				return fail(&"no_chance")
			_call(p, String(action))
		&"cash_out":
			if int(h["rung"]) <= 0:
				return fail(&"nothing_to_cash")
			_cash_out(p)
		_:
			return fail(&"unknown_action")
	return OK_RESULT


func tick(delta: float) -> void:
	if _fast_for(seats.filter(func(x: int) -> bool: return x >= 0)):
		delta *= 2.0  # Energy Drink, alone at the table
	for p: int in hands.keys():
		var h: Dictionary = hands[p]
		h["timer"] = float(h["timer"]) - delta
		if float(h["timer"]) > 0.0:
			continue
		if h["phase"] == PLAY:
			_auto_play(p)  # the call timed out
		else:
			hands.erase(p)


## An ante settles with the first call; a player who never calls is called for at the timeout.
func round_seconds() -> float:
	return 5.0


func has_stake(p: int) -> bool:
	return hands.has(p) and hands[p]["phase"] == PLAY


## The match is over: every open hand is played out by the auto rule.
func auto_resolve() -> void:
	for p: int in hands.keys():
		if hands[p]["phase"] == PLAY:
			_auto_play(p)


## A minigame starts: a fresh ante with no call yet comes back; a pot with right calls in it was
## won already and is cashed out (no loss and no win on the call that was still open).
func refund_all() -> void:
	if hands.is_empty():
		return
	var totals: Dictionary = {}
	for p: int in hands.keys():
		var h: Dictionary = hands[p]
		if h["phase"] != PLAY:
			continue
		if int(h["rung"]) > 0:
			_cash_out(p)
		else:
			_refund(p, int(h["stake"]), int(h.get("covered", 0)), totals)
	hands.clear()
	_emit_refunds(totals)


func get_public_state() -> Dictionary:
	var hs: Dictionary = {}
	var playing: bool = false
	for p: int in hands.keys():
		var h: Dictionary = hands[p]
		playing = playing or h["phase"] == PLAY
		hs[p] = {
			"stake": h["stake"], "cards": (h["cards"] as Array).duplicate(), "phase": h["phase"], "rung": h["rung"],
			"mult": h["mult"], "pot": pot_of(h), "odds": (h.get("odds", {}) as Dictionary).duplicate(),
			"pays": (h.get("pays", {}) as Dictionary).duplicate(), "timer": snappedf(float(h["timer"]), 0.01),
			"outcome": h["outcome"], "guess": h["guess"],
		}
	return {"game": game_id, "state": State.PLAYING if playing else State.IDLE, "seats": seats.duplicate(), "hands": hs, "deck_left": deck.size()}


## What a hand would cash out for now (the ante times its multiplier, rounded down once).
static func pot_of(h: Dictionary) -> int:
	return int(floor(int(h["stake"]) * float(h["mult"]) + 0.000001))


# --- Play ---------------------------------------------------------------------------------------


## The card that is up gets its call: the true chances from the deck as it stands and the pays,
## locked until the call is made (other players' cards never change what you were shown).
func _open_call(h: Dictionary) -> void:
	var shown: int = value_of(int((h["cards"] as Array).back()))
	var odds: Dictionary = odds_for(shown, counts_of(deck))
	h["odds"] = odds
	h["pays"] = {HIGHER: pay_for(float(odds[HIGHER]), balance), LOWER: pay_for(float(odds[LOWER]), balance)}
	h["timer"] = balance.hilo_action_time


func _call(p: int, guess: String) -> void:
	var h: Dictionary = hands[p]
	var shown: int = value_of(int((h["cards"] as Array).back()))
	var card: int = _draw_next(p, shown, guess)
	(h["cards"] as Array).append(card)
	h["guess"] = guess
	var won: bool = wins(guess, shown, value_of(card))
	var pay: float = float(h["pays"][guess])
	if won:
		h["rung"] = int(h["rung"]) + 1
		h["mult"] = minf(float(h["mult"]) * pay, balance.hilo_pot_cap)
	events.append(GameEvents.make(&"hilo_call", {"station": station_id, "player": p, "guess": guess, "card": card, "won": won, "pay": pay, "rung": h["rung"], "pot": pot_of(h) if won else 0}))
	if not won:
		_settle(p, int(h["stake"]), 0, _details(h, &"lose"))
		_finish(p, &"lose")
	elif int(h["rung"]) >= balance.hilo_max_rungs or float(h["mult"]) >= balance.hilo_pot_cap:
		_cash_out(p)  # the top of the ladder
	else:
		_open_call(h)


## The next card for a call: drawn from the deck, redrawn once with `hilo_favour` chance when it
## would lose (the quiet house rule), then rerolled by the player's luck like every table's cards.
## Cards that are passed over go back into the deck at a random place.
func _draw_next(p: int, shown: int, guess: String) -> int:
	var card: int = _draw()
	if not wins(guess, shown, value_of(card)) and rng.chance(balance.hilo_favour):
		_put_back(card)
		card = _draw()
	var lk: int = modifiers.get_luck(p, game_id)
	if lk == 0:
		return card
	var first: Array[bool] = [true]
	var d: LuckRng.Draw = luck.draw(lk, func() -> int:
		if first[0]:
			first[0] = false
			return card
		return _draw(), func(c: int) -> float: return 1.0 if wins(guess, shown, value_of(c)) else 0.0)
	if d.rerolled:
		_put_back(int(d.rejected))
	if d.luck_changed:
		events.append(GameEvents.luck_flourish(p, station_id, &"lucky" if lk > 0 else &"jinxed"))
	return int(d.value)


## Timeout, standing up or the match end: a pot with a right call in it is cashed out, a fresh ante
## takes the likelier side (higher on a coin flip) and banks a right call straight away.
func _auto_play(p: int) -> void:
	var h: Dictionary = hands[p]
	if int(h["rung"]) > 0:
		_cash_out(p)
		return
	var odds: Dictionary = h["odds"]
	_call(p, HIGHER if float(odds[HIGHER]) >= float(odds[LOWER]) else LOWER)
	if hands.has(p) and hands[p]["phase"] == PLAY:
		_cash_out(p)


func _cash_out(p: int) -> void:
	var h: Dictionary = hands[p]
	_settle(p, int(h["stake"]), pot_of(h), _details(h, &"cashed"))
	_finish(p, &"cashed")


func _finish(p: int, outcome: StringName) -> void:
	var h: Dictionary = hands[p]
	h["phase"] = DONE
	h["outcome"] = outcome
	h["timer"] = balance.hilo_result_time
	h["odds"] = {}
	h["pays"] = {}
	hands_played += 1
	modifiers.consume_round(p, game_id)


func _details(h: Dictionary, outcome: StringName) -> Dictionary:
	return {"outcome": outcome, "rung": h["rung"], "mult": h["mult"], "cards": (h["cards"] as Array).duplicate()}


# --- Deck ---------------------------------------------------------------------------------------


## A fresh single deck, shuffled, without the cards still lying in front of players mid-hand.
func _reshuffle() -> void:
	var on_felt: Dictionary[int, bool] = {}
	for p: int in hands:
		if hands[p]["phase"] == PLAY:
			for c: int in hands[p]["cards"]:
				on_felt[c] = true
	deck.clear()
	for c: int in 52:
		if not on_felt.has(c):
			deck.append(c)
	rng.shuffle(deck)
	reshuffles += 1


func _draw() -> int:
	if deck.is_empty():
		_reshuffle()
		events.append(GameEvents.make(&"hilo_reshuffle", {"station": station_id}))
	return deck.pop_back()


func _put_back(card: int) -> void:
	deck.insert(rng.range_int(0, deck.size()), card)


# --- Odds (pure) --------------------------------------------------------------------------------


## Hi-Lo value of a card: 2..13 as printed, aces high (14).
static func value_of(card: int) -> int:
	var r: int = Card.rank(card)
	return ACE_HIGH if r == 1 else r


## How many of each value (index 2..14) are in `cards`.
static func counts_of(cards: Array[int]) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(ACE_HIGH + 1)
	for c: int in cards:
		out[value_of(c)] += 1
	return out


## True chances of the next card against a shown value: {higher, lower, tie} (they sum to 1; an
## empty deck gives all zeros).
static func odds_for(shown: int, counts: PackedInt32Array) -> Dictionary:
	var hi: int = 0
	var lo: int = 0
	var tie: int = 0
	for v: int in range(2, ACE_HIGH + 1):
		if v > shown:
			hi += counts[v]
		elif v < shown:
			lo += counts[v]
		else:
			tie += counts[v]
	var n: float = float(hi + lo + tie)
	if n <= 0.0:
		return {HIGHER: 0.0, LOWER: 0.0, "tie": 0.0}
	return {HIGHER: float(hi) / n, LOWER: float(lo) / n, "tie": float(tie) / n}


## What a right call returns per $1 of pot (ante back included), for a call that comes in with
## true chance `p`: `hilo_return` on average once the quiet favour is counted (a call wins with
## p·(1 + favour·(1 − p))), never more than the fair 1/p and never more than `hilo_max_pay`,
## rounded down to the cent. 0 for a call that cannot come in.
static func pay_for(p: float, cfg: BalanceConfig) -> float:
	if p <= 0.0:
		return 0.0
	var even: float = cfg.hilo_return / (p * (1.0 + cfg.hilo_favour * (1.0 - p)))
	var pay: float = minf(minf(even, 1.0 / p), cfg.hilo_max_pay)
	return maxf(floorf(pay * 100.0 + 0.000001) / 100.0, 1.0)


## True when `next` beats the call against `shown` (a tie loses both ways).
static func wins(guess: String, shown: int, next: int) -> bool:
	return next > shown if guess == HIGHER else next < shown


## The printed table for a fresh deck (the shown card out of it): one row per shown value 2..14,
## {value, higher, lower, tie, pay_higher, pay_lower}.
static func fresh_deck_table(cfg: BalanceConfig) -> Array[Dictionary]:
	var full: Array[int] = []
	for c: int in 52:
		full.append(c)
	var out: Array[Dictionary] = []
	for v: int in range(2, ACE_HIGH + 1):
		var counts: PackedInt32Array = counts_of(full)
		counts[v] -= 1
		var o: Dictionary = odds_for(v, counts)
		out.append({"value": v, "higher": o[HIGHER], "lower": o[LOWER], "tie": o["tie"], "pay_higher": pay_for(float(o[HIGHER]), cfg), "pay_lower": pay_for(float(o[LOWER]), cfg)})
	return out
