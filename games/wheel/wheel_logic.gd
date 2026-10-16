class_name WheelLogic
extends StationLogicBase
## The Wheel of Fortune (Big Six money wheel): 54 segments on a vertical wheel, $1 ×24, $2 ×15,
## $5 ×7, $10 ×4, $20 ×2, Joker ×1 and Logo ×1. Players put chips on a symbol on the layout; a
## symbol pays its face value to one ($1 pays 1:1 … $20 pays 20:1), Joker and Logo pay 40:1.
## Round: BETTING (the countdown starts with the first bet) → SPINNING (the dealer spins,
## `wheel_spin_time` at full speed, the result is drawn but not told) → the result is announced
## (`wheel_result`) and the wheel slows onto it for `LAND_TIME` → every bet settles once the
## pointer rests on it → RESULT → BETTING. The server decides the segment; clients only animate
## the wheel onto it (never physics), so the money never depends on anything a client shows.

enum State { IDLE, BETTING, SPINNING, RESULT }

## Symbols, in layout order: what the bet value (`symbol`) indexes.
const SYMBOLS: Array[StringName] = [&"1", &"2", &"5", &"10", &"20", &"joker", &"logo"]
## How each symbol reads on the wheel, the layout and the panel.
const LABELS: Array[String] = ["$1", "$2", "$5", "$10", "$20", "JOKER", "LOGO"]
## Segments per symbol (54 in all) and what a winning bet pays to one (the table shows exactly this).
const COUNTS: Array[int] = [24, 15, 7, 4, 2, 1, 1]
const PAYS: Array[int] = [1, 2, 5, 10, 20, 40, 40]
const SEGMENTS: int = 54
## The wheel, segment by segment clockwise from the top (segment 0 is under the pointer when the
## wheel is at rest at angle 0): Joker and Logo opposite each other, the rarer symbols spread out.
const LAYOUT: Array[int] = [
	5, 1, 0, 2, 0, 1, 0, 3, 1, 0, 0, 2, 1, 0, 4, 1, 0, 0, 2, 1, 3, 0, 0, 1, 0, 1, 2,
	6, 0, 0, 1, 0, 0, 1, 3, 2, 0, 1, 0, 0, 4, 1, 2, 0, 1, 0, 0, 3, 1, 2, 0, 1, 0, 0,
]
## Seconds from `wheel_result` (the wheel starts slowing onto the result) until it rests and the
## bets pay: the clicker's slow-down on every client (`WheelStation.land`).
const LAND_TIME: float = 4.5
## Results kept for the board ("last spins").
const HISTORY: int = 10

var spots: int = 5
var players: Array[int] = []
var state: State = State.IDLE
## Countdown to the spin (BETTING, once someone has bet), the spin / slow-down (SPINNING) or the
## next round (RESULT).
var timer: float = 0.0
## True once the countdown runs (the first bet of the round is in).
var counting: bool = false
## Bets this spin: {player, symbol, amount, covered}.
var bets: Array[Dictionary] = []
## Segment of the last spin (−1 before the first; hidden until the slow-down starts).
var segment: int = -1
## Symbols of the last spins, newest first.
var history: Array[int] = []
var spins_played: int = 0

var _pending: int = -1
## True while the wheel slows onto `segment` (announced, not paid yet).
var _landing: bool = false


func _on_setup() -> void:
	game_id = &"wheel"


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


## Minimum per bet and maximum total per spin for one player, after the limits multiplier.
func limits() -> Vector2i:
	return Vector2i(scaled(balance.wheel_min_bet), scaled(balance.wheel_max_total))


## Total staked by a player this spin.
func player_total(p: int) -> int:
	var sum: int = 0
	for b: Dictionary in bets:
		if b["player"] == p:
			sum += int(b["amount"])
	return sum


## Bet shape: `{symbol: 0..6, amount}`. Any number of symbols, up to the table maximum in all.
func place_bet(p: int, bet: Dictionary) -> Dictionary:
	if not p in players:
		return fail(&"not_seated")
	if state != State.BETTING:
		return fail(&"betting_closed")
	var symbol: int = int(bet.get("symbol", -1))
	var amount: int = int(bet.get("amount", 0))
	if symbol < 0 or symbol >= SYMBOLS.size():
		return fail(&"invalid_symbol")
	var lim: Vector2i = limits()
	if amount < lim.x:
		return fail(&"below_min")
	if player_total(p) + amount > lim.y:
		return fail(&"above_max")
	if not _take_stake(p, amount):
		return fail(&"insufficient_funds")
	bets.append({"player": p, "symbol": symbol, "amount": amount, "covered": last_covered})
	events.append(GameEvents.bet_placed(p, station_id, amount, {"game": game_id, "type": &"wheel", "value": symbol, "symbol": symbol}))
	if not counting:
		counting = true
		timer = balance.wheel_countdown
	return OK_RESULT


func player_action(p: int, action: StringName, _params: Dictionary = {}) -> Dictionary:
	if action == &"clear_bets":
		if state != State.BETTING:
			return fail(&"betting_closed")
		for b: Dictionary in bets.duplicate():
			if b["player"] == p:
				bets.erase(b)
				# Only what the player paid comes back: Fake Cash never turns into real money.
				var back: int = int(b["amount"]) - int(b.get("covered", 0))
				if back > 0:
					economy.apply(p, back, &"bet_cleared", station_id)
		if bets.is_empty():
			counting = false  # nobody is in any more: wait for the next first bet
			timer = 0.0
		return OK_RESULT
	return fail(&"unknown_action")


func tick(delta: float) -> void:
	# Energy Drink (alone at the wheel) hurries the dealer, never the wheel itself: every client
	# slows it down at its real pace.
	var wait: float = delta * (2.0 if _fast_for(players) else 1.0)
	match state:
		State.IDLE:
			if not players.is_empty():
				_start_betting()
		State.BETTING:
			if counting:
				timer -= wait
				if timer <= 0.0:
					_start_spin()
			elif players.is_empty():
				state = State.IDLE
		State.SPINNING:
			timer -= delta if _landing else wait
			if timer <= 0.0:
				if _landing:
					_resolve()
				else:
					_announce()
		State.RESULT:
			timer -= wait
			if timer <= 0.0:
				if players.is_empty():
					_go_idle()
				else:
					_start_betting()


func round_seconds() -> float:
	return (timer if state == State.BETTING and counting else balance.wheel_countdown) + balance.wheel_spin_time + LAND_TIME


func has_stake(p: int) -> bool:
	return (state == State.BETTING or state == State.SPINNING) and player_total(p) > 0


func auto_resolve() -> void:
	if state == State.BETTING and not bets.is_empty():
		_start_spin()
	if state == State.SPINNING:
		_resolve()
	if state == State.BETTING and bets.is_empty():
		_go_idle()


func refund_all() -> void:
	if state == State.IDLE:
		return
	var totals: Dictionary = {}
	if state == State.BETTING or state == State.SPINNING:
		for b: Dictionary in bets:
			_refund(int(b["player"]), int(b["amount"]), int(b.get("covered", 0)), totals)
	bets.clear()
	_pending = -1
	_landing = false
	_go_idle()
	_emit_refunds(totals)


func get_public_state() -> Dictionary:
	var shown: bool = state == State.RESULT or (state == State.SPINNING and _landing)
	return {
		"game": game_id, "state": state, "timer": timer, "counting": counting, "players": players.duplicate(),
		"bets": bets.duplicate(true), "segment": segment if shown else -1, "landing": state == State.SPINNING and _landing,
		"history": history.duplicate(),
	}


func _start_betting() -> void:
	state = State.BETTING
	counting = false
	timer = 0.0
	bets.clear()
	_pending = -1
	_landing = false
	events.append(GameEvents.make(&"round_started", {"station": station_id}))


func _go_idle() -> void:
	state = State.IDLE
	counting = false
	timer = 0.0
	_landing = false


## Bets close and the dealer spins: the segment is drawn now and told when the wheel slows down.
func _start_spin() -> void:
	state = State.SPINNING
	counting = false
	timer = balance.wheel_spin_time
	_landing = false
	_pending = _draw_segment()
	events.append(GameEvents.make(&"wheel_spin_started", {"station": station_id}))


## The wheel starts slowing onto the drawn segment; the bets pay in `_resolve` once it rests.
func _announce() -> void:
	segment = _pending
	_landing = true
	timer = LAND_TIME
	events.append(GameEvents.make(&"wheel_result", {"station": station_id, "segment": segment, "symbol": symbol_at(segment), "seconds": LAND_TIME}))


## The pointer rests on the segment: every bet settles at the odds printed on the layout.
func _resolve() -> void:
	if not _landing:
		_announce()  # resolved at once (match end): announce the segment first
	_landing = false
	spins_played += 1
	var won: int = symbol_at(segment)
	history.push_front(won)
	if history.size() > HISTORY:
		history.resize(HISTORY)
	var played: Dictionary[int, bool] = {}
	for b: Dictionary in bets:
		var p: int = int(b["player"])
		var stake: int = int(b["amount"])
		var symbol: int = int(b["symbol"])
		var base_return: int = stake * (PAYS[symbol] + 1) if symbol == won else 0
		_settle(p, stake, base_return, {"type": &"wheel", "value": symbol, "symbol": symbol, "segment": segment, "won": won})
		played[p] = true
	for p: int in played.keys():
		modifiers.consume_round(p, game_id)
	bets.clear()
	state = State.RESULT
	timer = balance.wheel_result_time


## The segment is drawn with the house rule's quiet thumb on the scale (Patrick, 0.9.6: "always
## favoured to win for you, by a bit, like the other games, but dont show it"): a spin that no bet
## at the wheel would win is redrawn once with `balance.wheel_favour` chance, then every bettor's
## luck rerolls it the way the other tables reroll a card or a pocket (keeping the segment that
## pays them more, or less when jinxed). Nothing of it reaches the clients: they only ever get the
## final segment, and the wheel slows onto it like any honest spin.
func _draw_segment() -> int:
	var current: Array[int] = [rng.range_int(0, SEGMENTS - 1)]
	if not bets.is_empty() and not _anyone_wins(current[0]) and rng.chance(balance.wheel_favour):
		current[0] = rng.range_int(0, SEGMENTS - 1)
	var seen: Dictionary[int, bool] = {}
	for b: Dictionary in bets:
		var p: int = int(b["player"])
		if seen.has(p):
			continue
		seen[p] = true
		var lk: int = modifiers.get_luck(p, game_id)
		if lk == 0:
			continue
		var d: LuckRng.Draw = luck.draw(lk, func() -> int:
			var out: int = current[0]
			current[0] = rng.range_int(0, SEGMENTS - 1)
			return out, func(seg: int) -> float: return float(return_for(p, seg)))
		current[0] = int(d.value)
		if d.luck_changed:
			events.append(GameEvents.luck_flourish(p, station_id, &"lucky" if lk > 0 else &"jinxed"))
	return current[0]


func _anyone_wins(seg: int) -> bool:
	var won: int = symbol_at(seg)
	for b: Dictionary in bets:
		if int(b["symbol"]) == won:
			return true
	return false


## What player `p`'s bets this spin would return (before multipliers) on segment `seg`.
func return_for(p: int, seg: int) -> int:
	var won: int = symbol_at(seg)
	var sum: int = 0
	for b: Dictionary in bets:
		if int(b["player"]) == p and int(b["symbol"]) == won:
			sum += int(b["amount"]) * (PAYS[won] + 1)
	return sum


## The symbol on segment `seg`.
static func symbol_at(seg: int) -> int:
	return LAYOUT[posmod(seg, SEGMENTS)]


## Honest chance of `symbol` on one spin.
static func chance_of(symbol: int) -> float:
	return COUNTS[symbol] / float(SEGMENTS)


## Exact return per unit staked for one player alone at the wheel with one bet on `symbol`, at
## neutral luck, with the favour redraw `favour`: the symbol comes up honestly, or on the redraw
## of a spin it missed.
static func exact_rtp(symbol: int, favour: float) -> float:
	var p: float = chance_of(symbol)
	return (PAYS[symbol] + 1) * (p + (1.0 - p) * favour * p)


## Odds as printed on the layout ("5:1").
static func odds_text(symbol: int) -> String:
	return "%d:1" % PAYS[symbol]
