class_name BaccaratLogic
extends StationLogicBase
## Punto Banco baccarat with a shared round, like roulette: BETTING (`baccarat_betting_time`) →
## DEALING (the cards turn over one by one, `baccarat_card_time` apart, then `baccarat_settle_time`)
## → RESULT → BETTING. Everyone at the table bets on the same two hands: PLAYER (1:1), BANKER (1:1
## less the commission), TIE (9:1) and the two PAIR side bets (11:1, the hand's first two cards are a
## pair). Player and Banker bets push on a tie. The dealer plays both hands by the fixed tableau
## (`player_draws`, `banker_draws`); nobody decides anything after the bets. The whole hand is drawn
## when the betting closes, but the public state only shows the cards turned so far, and the bets
## pay once the last card is up. The table only cycles while someone sits at it.

enum State { IDLE, BETTING, DEALING, RESULT }

const PLAYER: StringName = &"player"
const BANKER: StringName = &"banker"
const TIE: StringName = &"tie"
const PLAYER_PAIR: StringName = &"player_pair"
const BANKER_PAIR: StringName = &"banker_pair"
const BET_TYPES: Array[StringName] = [PLAYER, BANKER, TIE, PLAYER_PAIR, BANKER_PAIR]
## Luck at the table (the cards are shared, so luck moves the pay, not the cards, like roulette):
## a lucky player's Player/Banker bet that loses by a single point may come back; a jinxed
## player's winning Player/Banker bet may pay only this share of its winnings.
const LUCKY_ONE_POINT: StringName = &"one_point"
const JINX_SHARE: float = 0.8

var spots: int = 5
var players: Array[int] = []
var state: State = State.IDLE
var timer: float = 0.0
## Bets this round: {player, type, amount, covered}.
var bets: Array[Dictionary] = []
var shoe: Shoe
## This round's hands as drawn (deal order P1 B1 P2 B2, then each side's third card if any) and
## how many of `order` are face up.
var player_cards: Array[int] = []
var banker_cards: Array[int] = []
## Which hand gets each card, in the order they turn over (&"player" / &"banker").
var order: Array[StringName] = []
var shown: int = 0
## The last round's winner (&"player", &"banker", &"tie"; &"" while dealing or before the first).
var winner: StringName = &""
var rounds_played: int = 0
## Road: the winners of the last rounds, oldest first (the scoreboard over the table).
var history: Array[StringName] = []
const HISTORY_SIZE: int = 12
## The last round's net per player (player → winnings minus stakes), shown while RESULT.
var results: Dictionary[int, int] = {}

var _settled: bool = false


func _on_setup() -> void:
	game_id = &"baccarat"
	shoe = Shoe.new(rng, balance.baccarat_decks, balance.baccarat_penetration)


func can_join(p: int) -> bool:
	return p in players or players.size() < spots


func join(p: int) -> Dictionary:
	if p in players:
		return OK_RESULT
	if players.size() >= spots:
		return fail(&"seat_taken")
	players.append(p)
	if state == State.IDLE:
		_start_betting()
	return OK_RESULT


func leave(p: int) -> void:
	players.erase(p)


## Minimum per bet and maximum total per round for one player, after the limits multiplier.
func limits() -> Vector2i:
	return Vector2i(scaled(balance.baccarat_min_bet), scaled(balance.baccarat_max_total))


## Total staked by a player this round.
func player_total(p: int) -> int:
	var sum: int = 0
	for b: Dictionary in bets:
		if b["player"] == p:
			sum += int(b["amount"])
	return sum


func bet_limits(p: int, _bet: Dictionary) -> Vector2i:
	var lim: Vector2i = limits()
	return Vector2i(lim.x, lim.y - player_total(p))


func place_bet(p: int, bet: Dictionary) -> Dictionary:
	if not p in players:
		return fail(&"not_seated")
	if state != State.BETTING:
		return fail(&"betting_closed")
	var type: StringName = StringName(bet.get("type", ""))
	var amount: int = int(bet.get("amount", 0))
	if not type in BET_TYPES:
		return fail(&"invalid_bet_type")
	var lim: Vector2i = limits()
	if amount < lim.x:
		return fail(&"below_min")
	if player_total(p) + amount > lim.y:
		return fail(&"above_max")
	if not _take_stake(p, amount):
		return fail(&"insufficient_funds")
	bets.append({"player": p, "type": type, "amount": amount, "covered": last_covered})
	events.append(GameEvents.bet_placed(p, station_id, amount, with_all_in(bet, {"game": game_id, "type": type, "value": 0})))
	return OK_RESULT


func player_action(p: int, action: StringName, _params: Dictionary = {}) -> Dictionary:
	if action == &"clear_bets":
		if state != State.BETTING:
			return fail(&"betting_closed")
		for b: Dictionary in bets.duplicate():
			if b["player"] == p:
				bets.erase(b)
				var back: int = int(b["amount"]) - int(b.get("covered", 0))
				if back > 0:
					economy.apply(p, back, &"bet_cleared", station_id)
		return OK_RESULT
	return fail(&"unknown_action")


func tick(delta: float) -> void:
	if _fast_for(players):
		delta *= 2.0  # Energy Drink, alone at the table
	match state:
		State.IDLE:
			if not players.is_empty():
				_start_betting()
		State.BETTING:
			timer -= delta
			if timer <= 0.0:
				if bets.is_empty():
					_start_betting()  # nobody bet: a fresh window, no cards wasted
				else:
					_start_deal()
		State.DEALING:
			timer -= delta
			while timer <= 0.0 and state == State.DEALING:
				if shown < order.size():
					shown += 1
					timer += balance.baccarat_card_time if shown < order.size() else balance.baccarat_settle_time
				else:
					_resolve()
		State.RESULT:
			timer -= delta
			if timer <= 0.0:
				if players.is_empty():
					state = State.IDLE
				else:
					_start_betting()


## Seconds a bet placed now needs until it pays: the rest of the window plus the longest deal.
func round_seconds() -> float:
	return (timer if state == State.BETTING else balance.baccarat_betting_time) + balance.baccarat_card_time * 6.0 + balance.baccarat_settle_time


func has_stake(p: int) -> bool:
	return state != State.RESULT and player_total(p) > 0


func auto_resolve() -> void:
	if state == State.BETTING and not bets.is_empty():
		_start_deal()
	if state == State.DEALING:
		shown = order.size()
		_resolve()
	if state == State.BETTING and bets.is_empty():
		state = State.IDLE


func refund_all() -> void:
	if state == State.IDLE:
		return
	var totals: Dictionary = {}
	if state == State.BETTING or state == State.DEALING:
		for b: Dictionary in bets:
			_refund(int(b["player"]), int(b["amount"]), int(b.get("covered", 0)), totals)
	bets.clear()
	_clear_hands()
	winner = &""
	state = State.IDLE
	timer = 0.0
	_emit_refunds(totals)


func get_public_state() -> Dictionary:
	var p: Array[int] = shown_cards(PLAYER)
	var b: Array[int] = shown_cards(BANKER)
	var out: Dictionary = {
		"game": game_id, "state": state, "timer": timer, "players": players.duplicate(), "bets": bets.duplicate(true),
		"player_cards": p, "banker_cards": b, "winner": winner if state == State.RESULT else &"",
		"history": history.duplicate(),
	}
	if state == State.RESULT:
		out["results"] = results.duplicate()
	if not p.is_empty():
		out["player_total"] = hand_total(p)
	if not b.is_empty():
		out["banker_total"] = hand_total(b)
	return out


## The cards of one hand that are face up so far.
func shown_cards(side: StringName) -> Array[int]:
	var out: Array[int] = []
	var pi: int = 0
	var bi: int = 0
	for i: int in mini(shown, order.size()):
		if order[i] == PLAYER:
			if side == PLAYER:
				out.append(player_cards[pi])
			pi += 1
		else:
			if side == BANKER:
				out.append(banker_cards[bi])
			bi += 1
	return out


func _start_betting() -> void:
	state = State.BETTING
	timer = balance.baccarat_betting_time
	bets.clear()
	_clear_hands()
	winner = &""
	events.append(GameEvents.make(&"round_started", {"station": station_id}))


func _clear_hands() -> void:
	player_cards.clear()
	banker_cards.clear()
	order.clear()
	shown = 0
	_settled = false


## Bets close: both hands are drawn now by the tableau; the cards then turn over one by one.
func _start_deal() -> void:
	if shoe.needs_reshuffle():
		shoe.reshuffle()
	_clear_hands()
	deal_hands(shoe.draw)
	state = State.DEALING
	timer = balance.baccarat_card_time
	events.append(GameEvents.make(&"cards_dealt", {"station": station_id}))


## Deals both hands with `draw` (a Callable returning the next card) by the Punto Banco tableau:
## P B P B; a natural (8 or 9 on two cards) on either side stands both; else the Player draws on
## 0-5, and the Banker draws by its total and the Player's third card (or on 0-5 when the Player
## stood). Fills `player_cards`, `banker_cards` and `order`.
func deal_hands(draw: Callable) -> void:
	for side: StringName in [PLAYER, BANKER, PLAYER, BANKER]:
		_give(side, int(draw.call()))
	var p: int = hand_total(player_cards)
	var b: int = hand_total(banker_cards)
	if p >= 8 or b >= 8:
		return
	var third: int = -1
	if player_draws(p):
		_give(PLAYER, int(draw.call()))
		third = card_value(player_cards[2])
	if banker_draws(b, third):
		_give(BANKER, int(draw.call()))


func _give(side: StringName, card: int) -> void:
	if side == PLAYER:
		player_cards.append(card)
	else:
		banker_cards.append(card)
	order.append(side)


## The last card is up: every bet settles.
func _resolve() -> void:
	if _settled:
		return
	_settled = true
	shown = order.size()
	var p: int = hand_total(player_cards)
	var b: int = hand_total(banker_cards)
	winner = PLAYER if p > b else (BANKER if b > p else TIE)
	rounds_played += 1
	history.append(winner)
	while history.size() > HISTORY_SIZE:
		history.pop_front()
	events.append(GameEvents.make(&"baccarat_result", {"station": station_id, "winner": winner, "player_total": p, "banker_total": b,
		"natural": player_cards.size() == 2 and banker_cards.size() == 2 and (p >= 8 or b >= 8)}))
	results.clear()
	for bet: Dictionary in bets:
		var pid: int = int(bet["player"])
		results[pid] = int(results.get(pid, 0)) + _settle_bet(bet, p, b) - int(bet["amount"])
	for pid: int in results.keys():
		modifiers.consume_round(pid, game_id)
	bets.clear()
	state = State.RESULT
	timer = balance.baccarat_result_time


## Pays one bet; returns what it gave back (stake included).
func _settle_bet(bet: Dictionary, p: int, b: int) -> int:
	var pid: int = bet["player"]
	var stake: int = bet["amount"]
	var type: StringName = bet["type"]
	var details: Dictionary = {"type": type, "winner": winner, "player_total": p, "banker_total": b}
	var base_return: int = 0
	var ret: float = gross_return(type, winner, player_cards, banker_cards)
	if ret > 1.0:
		var lk: float = modifiers.get_luck(pid, game_id)
		if lk < 0 and (type == PLAYER or type == BANKER) and rng.chance(luck.reroll_chance(lk)):
			base_return = stake + int(floor(stake * (ret - 1.0) * JINX_SHARE))
			details["jinxed"] = true
			events.append(GameEvents.luck_flourish(pid, station_id, &"jinxed"))
		else:
			base_return = _stochastic_round(stake * ret * (1.0 + favour(type)))
	elif ret == 1.0:
		base_return = stake  # a tie: Player and Banker bets come back
	elif (type == PLAYER or type == BANKER) and absi(p - b) == 1 and modifiers.get_luck(pid, game_id) > 0 \
			and rng.chance(luck.reroll_chance(modifiers.get_luck(pid, game_id))):
		base_return = stake
		details["lucky"] = LUCKY_ONE_POINT
		events.append(GameEvents.luck_flourish(pid, station_id, &"lucky"))
	return _settle(pid, stake, base_return, details)


## What a bet of `type` returns per $1 staked by the printed pays (0 = lost, 1 = back).
func gross_return(type: StringName, win: StringName, pc: Array[int], bc: Array[int]) -> float:
	match type:
		PLAYER:
			return 2.0 if win == PLAYER else (1.0 if win == TIE else 0.0)
		BANKER:
			return 2.0 - balance.baccarat_banker_commission if win == BANKER else (1.0 if win == TIE else 0.0)
		TIE:
			return 1.0 + balance.baccarat_tie_pays if win == TIE else 0.0
		PLAYER_PAIR:
			return 1.0 + balance.baccarat_pair_pays if is_pair(pc) else 0.0
		BANKER_PAIR:
			return 1.0 + balance.baccarat_pair_pays if is_pair(bc) else 0.0
	return 0.0


## The quiet favour of a bet type (`BalanceConfig.baccarat_*_favour`).
func favour(type: StringName) -> float:
	match type:
		PLAYER:
			return balance.baccarat_player_favour
		BANKER:
			return balance.baccarat_banker_favour
		TIE:
			return balance.baccarat_tie_favour
	return balance.baccarat_pair_favour


## Rounds a non-negative amount down, plus one more dollar with probability equal to the fraction.
func _stochastic_round(x: float) -> int:
	var whole: int = int(floor(x + 0.000001))
	return whole + (1 if rng.chance(x - whole) else 0)


## Baccarat value of a card: A = 1, 2-9 face value, 10 and pictures 0.
static func card_value(card: int) -> int:
	var r: int = Card.rank(card)
	return r if r < 10 else 0


## A hand's total: the last digit of its card values.
static func hand_total(cards: Array) -> int:
	var t: int = 0
	for c: Variant in cards:
		t += card_value(int(c))
	return t % 10


## True if a hand's first two cards are the same rank.
static func is_pair(cards: Array) -> bool:
	return cards.size() >= 2 and Card.rank(int(cards[0])) == Card.rank(int(cards[1]))


## The Player draws a third card on 0-5 (no natural on the table).
static func player_draws(total: int) -> bool:
	return total <= 5


## The Banker's tableau: `third` is the value of the Player's third card, -1 when the Player stood.
static func banker_draws(total: int, third: int) -> bool:
	if third < 0:
		return total <= 5
	match total:
		0, 1, 2:
			return true
		3:
			return third != 8
		4:
			return third >= 2 and third <= 7
		5:
			return third >= 4 and third <= 7
		6:
			return third == 6 or third == 7
	return false
