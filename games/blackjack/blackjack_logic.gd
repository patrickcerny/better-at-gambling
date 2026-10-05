class_name BlackjackLogic
extends StationLogicBase
## Blackjack table with simultaneous play (§2.5): IDLE → BETTING (window opens on the first bet)
## → deal → ACTING (everyone at once, timeout = stand) → dealer (stands on soft 17) → PAYOUT → IDLE.
## 3:2 blackjack, double on any first two cards, no split (M7), Dealer Bust Bonus on wins.

enum State { IDLE, BETTING, ACTING, PAYOUT }

var seat_count: int = 4
var seats: Array[int] = []
var state: State = State.IDLE
var timer: float = 0.0
## player → {stake, cards: Array[int], done, doubled, blackjack, settled}
var hands: Dictionary[int, Dictionary] = {}
var dealer: Array[int] = []
var dealer_revealed: bool = false
var shoe: Shoe
var rounds_played: int = 0


func _on_setup() -> void:
	game_id = &"blackjack"
	shoe = Shoe.new(rng, balance.bj_decks, balance.bj_penetration)
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
	return OK_RESULT


func leave(p: int) -> void:
	var idx: int = seats.find(p)
	if idx >= 0:
		seats[idx] = -1
	# An open hand stays in and auto-stands.
	if hands.has(p) and state == State.ACTING:
		hands[p]["done"] = true
		_check_all_done()


## Min and max bet after the limits multiplier.
func limits() -> Vector2i:
	return Vector2i(scaled(balance.bj_min_bet), scaled(balance.bj_max_bet))


func place_bet(p: int, bet: Dictionary) -> Dictionary:
	if not p in seats:
		return fail(&"not_seated")
	if state != State.IDLE and state != State.BETTING:
		return fail(&"betting_closed")
	if hands.has(p):
		return fail(&"already_bet")
	var amount: int = int(bet.get("amount", 0))
	var lim: Vector2i = limits()
	if amount < lim.x:
		return fail(&"below_min")
	if amount > lim.y:
		return fail(&"above_max")
	if not _take_stake(p, amount):
		return fail(&"insufficient_funds")
	hands[p] = {"stake": amount, "cards": [] as Array[int], "done": false, "doubled": false, "blackjack": false, "settled": false}
	events.append(GameEvents.bet_placed(p, station_id, amount, {"game": game_id}))
	if state == State.IDLE:
		state = State.BETTING
		timer = balance.bj_betting_window
		events.append(GameEvents.make(&"round_started", {"station": station_id, "betting_window": timer}))
	return OK_RESULT


func player_action(p: int, action: StringName, _params: Dictionary = {}) -> Dictionary:
	if state != State.ACTING:
		return fail(&"wrong_state")
	if not hands.has(p) or hands[p]["done"]:
		return fail(&"no_active_hand")
	var h: Dictionary = hands[p]
	match action:
		&"hit":
			_deal_to_player(p)
			var t: int = HandEval.total(h["cards"])
			if t >= 21:
				h["done"] = true
		&"stand":
			h["done"] = true
		&"double":
			if (h["cards"] as Array).size() != 2:
				return fail(&"cannot_double")
			if not _take_stake(p, int(h["stake"])):
				return fail(&"insufficient_funds")
			h["stake"] = int(h["stake"]) * 2
			h["doubled"] = true
			_deal_to_player(p)
			h["done"] = true
		&"cut":
			# Scissors: snip off your last card (not after doubling, at least 3 cards in hand).
			if h["doubled"] or (h["cards"] as Array).size() < 3 or not modifiers.has_flag(p, &"scissors", game_id):
				return fail(&"cannot_cut")
			modifiers.consume_flag(p, &"scissors")
			var cut: int = (h["cards"] as Array).pop_back()
			shoe.return_card(cut)
		_:
			return fail(&"unknown_action")
	events.append(GameEvents.make(&"bj_action", {"station": station_id, "player": p, "action": action, "cards": (h["cards"] as Array).duplicate()}))
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
		State.ACTING:
			timer -= delta
			if timer <= 0.0:
				for p: int in hands.keys():
					hands[p]["done"] = true
				_dealer_and_settle()
		State.PAYOUT:
			timer -= delta
			if timer <= 0.0:
				_end_round()


func round_seconds() -> float:
	# Remaining betting window, then at least a few seconds of play and the dealer.
	return (timer if state == State.BETTING else balance.bj_betting_window) + 4.0


func has_stake(p: int) -> bool:
	return hands.has(p) and not bool(hands[p].get("settled", false))


func auto_resolve() -> void:
	if state == State.BETTING:
		_deal()
	if state == State.ACTING:
		for p: int in hands.keys():
			hands[p]["done"] = true
		_dealer_and_settle()
	if state == State.PAYOUT:
		_end_round()


func get_public_state() -> Dictionary:
	var hs: Dictionary = {}
	for p: int in hands.keys():
		var h: Dictionary = hands[p]
		hs[p] = {"stake": h["stake"], "cards": (h["cards"] as Array).duplicate(), "done": h["done"], "total": HandEval.total(h["cards"])}
	var shown: Array[int] = dealer.duplicate()
	if not dealer_revealed and shown.size() >= 2:
		shown = [dealer[0]]
	return {"game": game_id, "state": state, "timer": timer, "seats": seats.duplicate(), "hands": hs, "dealer": shown, "dealer_revealed": dealer_revealed}


func get_private_state(p: int) -> Dictionary:
	var out: Dictionary = {}
	if not dealer_revealed and dealer.size() >= 2 and modifiers.has_flag(p, &"peek_dealer", game_id):
		out["hole_card"] = dealer[1]
	if modifiers.has_flag(p, &"scissors", game_id):
		out["scissors"] = true
	return out


func _deal() -> void:
	if hands.is_empty():
		state = State.IDLE
		return
	dealer.clear()
	dealer_revealed = false
	for p: int in hands.keys():
		_deal_to_player(p)
	dealer.append(shoe.draw())
	for p: int in hands.keys():
		_deal_to_player(p)
	dealer.append(shoe.draw())
	events.append(GameEvents.make(&"cards_dealt", {"station": station_id, "dealer_up": dealer[0]}))
	if HandEval.is_blackjack(dealer):
		for p: int in hands.keys():
			hands[p]["done"] = true
		_dealer_and_settle()
		return
	for p: int in hands.keys():
		var h: Dictionary = hands[p]
		if HandEval.is_blackjack(h["cards"]):
			h["blackjack"] = true
			h["done"] = true
			h["settled"] = true
			var stake: int = h["stake"]
			_settle(p, stake, stake + int(floor(stake * balance.bj_blackjack_ratio)), {"outcome": &"blackjack", "cards": (h["cards"] as Array).duplicate()})
	state = State.ACTING
	timer = balance.bj_action_time
	_check_all_done()


func _deal_to_player(p: int) -> void:
	var cards: Array[int] = hands[p]["cards"]
	var lk: int = modifiers.get_luck(p, game_id)
	var d: LuckRng.Draw = luck.draw(lk, shoe.draw, func(c: int) -> float:
		var trial: Array[int] = cards.duplicate()
		trial.append(c)
		return HandEval.quality(trial))
	if d.rerolled:
		shoe.return_card(int(d.rejected))
	if d.luck_changed:
		events.append(GameEvents.luck_flourish(p, station_id, &"lucky" if lk > 0 else &"jinxed"))
	cards.append(int(d.value))


func _check_all_done() -> void:
	if state != State.ACTING:
		return
	for p: int in hands.keys():
		if not hands[p]["done"]:
			return
	_dealer_and_settle()


func _dealer_and_settle() -> void:
	dealer_revealed = true
	var need_dealer: bool = false
	for p: int in hands.keys():
		var h: Dictionary = hands[p]
		if not h["settled"] and not HandEval.is_bust(h["cards"]):
			need_dealer = true
	if need_dealer and not HandEval.is_blackjack(dealer):
		while HandEval.total(dealer) < 17:
			dealer.append(shoe.draw())
	var dt: int = HandEval.total(dealer)
	var dealer_bj: bool = HandEval.is_blackjack(dealer)
	events.append(GameEvents.make(&"bj_dealer", {"station": station_id, "cards": dealer.duplicate(), "total": dt}))
	for p: int in hands.keys():
		var h: Dictionary = hands[p]
		if h["settled"]:
			continue
		h["settled"] = true
		var stake: int = h["stake"]
		var cards: Array[int] = h["cards"]
		var pt: int = HandEval.total(cards)
		var outcome: StringName
		var ret: int = 0
		if pt > 21:
			outcome = &"bust"
		elif dealer_bj:
			outcome = &"push" if HandEval.is_blackjack(cards) else &"dealer_blackjack"
			ret = stake if outcome == &"push" else 0
		elif dt > 21:
			outcome = &"dealer_bust"
			ret = stake + int(floor(stake * balance.bj_dealer_bust_bonus + 0.000001))
		elif pt > dt:
			outcome = &"win"
			ret = stake * 2
		elif pt == dt:
			outcome = &"push"
			ret = stake
		else:
			outcome = &"lose"
		_settle(p, stake, ret, {"outcome": outcome, "cards": cards.duplicate(), "dealer": dealer.duplicate()})
	state = State.PAYOUT
	timer = balance.bj_result_time


func _end_round() -> void:
	for p: int in hands.keys():
		modifiers.consume_round(p, game_id)
	hands.clear()
	dealer.clear()
	dealer_revealed = false
	rounds_played += 1
	if shoe.needs_reshuffle():
		shoe.reshuffle()
		events.append(GameEvents.make(&"bj_reshuffle", {"station": station_id}))
	state = State.IDLE


## Basic strategy without splitting (S17, double any two): returns &"hit", &"stand" or &"double".
static func basic_strategy(cards: Array[int], dealer_up: int) -> StringName:
	var t: int = HandEval.total(cards)
	var soft: bool = HandEval.is_soft(cards)
	var two: bool = cards.size() == 2
	var up: int = Card.bj_value(dealer_up)
	if up == 1:
		up = 11
	if soft:
		if t >= 20:
			return &"stand"
		if t == 19:
			return &"double" if two and up == 6 else &"stand"
		if t == 18:
			if two and up >= 3 and up <= 6:
				return &"double"
			return &"stand" if up <= 8 else &"hit"
		if t == 17:
			return &"double" if two and up >= 3 and up <= 6 else &"hit"
		if t >= 15:
			return &"double" if two and up >= 4 and up <= 6 else &"hit"
		return &"double" if two and up >= 5 and up <= 6 else &"hit"
	if t >= 17:
		return &"stand"
	if t >= 13:
		return &"stand" if up <= 6 else &"hit"
	if t == 12:
		return &"stand" if up >= 4 and up <= 6 else &"hit"
	if t == 11:
		return &"double" if two else &"hit"
	if t == 10:
		return &"double" if two and up <= 9 else &"hit"
	if t == 9:
		return &"double" if two and up >= 3 and up <= 6 else &"hit"
	return &"hit"
