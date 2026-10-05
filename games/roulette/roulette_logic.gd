class_name RouletteLogic
extends StationLogicBase
## European single-zero roulette table with a shared spin cycle (§2.5):
## BETTING (`roulette_betting_time`) → SPINNING (`roulette_spin_time`) → RESULT → BETTING.
## The table only cycles while someone stands at it.

enum State { IDLE, BETTING, SPINNING, RESULT }

const WHEEL_ORDER: Array[int] = [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]
const RED: Array[int] = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]
## Bet type → profit ratio (x:1).
const RATIOS: Dictionary = {
	&"straight": 35, &"red": 1, &"black": 1, &"odd": 1, &"even": 1, &"low": 1, &"high": 1, &"dozen": 2, &"column": 2,
}
const EVEN_MONEY: Array[StringName] = [&"red", &"black", &"odd", &"even", &"low", &"high"]

var spots: int = 6
var players: Array[int] = []
var state: State = State.IDLE
var timer: float = 0.0
## Bets this spin: {player, type, value, amount}.
var bets: Array[Dictionary] = []
## Last result number (-1 before the first spin; hidden while spinning).
var result: int = -1
var spins_played: int = 0

var _pending_result: int = -1


func _on_setup() -> void:
	game_id = &"roulette"


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
	return Vector2i(scaled(balance.roulette_min_bet), scaled(balance.roulette_max_total))


## Total staked by a player this spin.
func player_total(p: int) -> int:
	var sum: int = 0
	for b: Dictionary in bets:
		if b["player"] == p:
			sum += int(b["amount"])
	return sum


func place_bet(p: int, bet: Dictionary) -> Dictionary:
	if not p in players:
		return fail(&"not_seated")
	if state != State.BETTING:
		return fail(&"betting_closed")
	var type: StringName = StringName(bet.get("type", ""))
	var value: int = int(bet.get("value", 0))
	var amount: int = int(bet.get("amount", 0))
	if not RATIOS.has(type):
		return fail(&"invalid_bet_type")
	if not is_valid_value(type, value):
		return fail(&"invalid_bet_value")
	var lim: Vector2i = limits()
	if amount < lim.x:
		return fail(&"below_min")
	if player_total(p) + amount > lim.y:
		return fail(&"above_max")
	if not _take_stake(p, amount):
		return fail(&"insufficient_funds")
	bets.append({"player": p, "type": type, "value": value, "amount": amount})
	events.append(GameEvents.bet_placed(p, station_id, amount, {"game": game_id, "type": type, "value": value}))
	return OK_RESULT


func player_action(p: int, action: StringName, _params: Dictionary = {}) -> Dictionary:
	if action == &"clear_bets":
		if state != State.BETTING:
			return fail(&"betting_closed")
		for b: Dictionary in bets.duplicate():
			if b["player"] == p:
				bets.erase(b)
				economy.apply(p, int(b["amount"]), &"bet_cleared", station_id)
		return OK_RESULT
	return fail(&"unknown_action")


func tick(delta: float) -> void:
	match state:
		State.IDLE:
			if not players.is_empty():
				_start_betting()
		State.BETTING:
			timer -= delta
			if timer <= 0.0:
				_start_spin()
		State.SPINNING:
			timer -= delta
			if timer <= 0.0:
				_resolve()
		State.RESULT:
			timer -= delta
			if timer <= 0.0:
				if players.is_empty():
					state = State.IDLE
				else:
					_start_betting()


func round_seconds() -> float:
	return (timer if state == State.BETTING else balance.roulette_betting_time) + balance.roulette_spin_time


func has_stake(p: int) -> bool:
	return state != State.RESULT and player_total(p) > 0


func auto_resolve() -> void:
	if state == State.BETTING and not bets.is_empty():
		_start_spin()
	if state == State.SPINNING:
		_resolve()
	if state == State.BETTING and bets.is_empty():
		state = State.IDLE


func get_public_state() -> Dictionary:
	return {"game": game_id, "state": state, "timer": timer, "players": players.duplicate(), "bets": bets.duplicate(true), "result": result if state != State.SPINNING else -1}


func _start_betting() -> void:
	state = State.BETTING
	timer = balance.roulette_betting_time
	bets.clear()
	events.append(GameEvents.make(&"round_started", {"station": station_id}))


func _start_spin() -> void:
	state = State.SPINNING
	timer = balance.roulette_spin_time
	_pending_result = rng.range_int(0, 36)
	events.append(GameEvents.make(&"roulette_spin_started", {"station": station_id}))


func _resolve() -> void:
	result = _pending_result
	spins_played += 1
	events.append(GameEvents.make(&"roulette_result", {"station": station_id, "number": result}))
	var played: Dictionary[int, bool] = {}
	for b: Dictionary in bets:
		_settle_bet(b)
		played[int(b["player"])] = true
	for p: int in played.keys():
		modifiers.consume_round(p, game_id)
	bets.clear()
	state = State.RESULT
	timer = balance.roulette_result_time


func _settle_bet(b: Dictionary) -> void:
	var p: int = b["player"]
	var stake: int = b["amount"]
	var type: StringName = b["type"]
	var lk: int = modifiers.get_luck(p, game_id)
	var details: Dictionary = {"type": type, "value": b["value"], "number": result}
	var base_return: int = 0
	if wins(type, int(b["value"]), result):
		var ratio: float = RATIOS[type]
		if lk < 0 and type in EVEN_MONEY and rng.chance(luck.reroll_chance(lk)):
			base_return = int(floor(stake * (1.0 + balance.roulette_jinx_ratio)))
			details["jinxed"] = true
			events.append(GameEvents.luck_flourish(p, station_id, &"jinxed"))
		else:
			var gross: int = stake * int(ratio + 1)
			base_return = gross + _stochastic_round(gross * balance.roulette_generosity)
	elif type == &"straight" and lk > 0 and are_neighbors(int(b["value"]), result) and rng.chance(luck.reroll_chance(lk)):
		base_return = int(floor(stake * (1.0 + balance.roulette_lucky_neighbor_ratio)))
		details["lucky_neighbor"] = true
		events.append(GameEvents.luck_flourish(p, station_id, &"lucky"))
	_settle(p, stake, base_return, details)


## Rounds a non-negative amount down, plus one more dollar with probability equal to the
## fraction, so small bets keep the generosity bonus in expectation (DECISIONS.md).
func _stochastic_round(x: float) -> int:
	var whole: int = int(floor(x))
	return whole + (1 if rng.chance(x - whole) else 0)


## True if a bet value is valid for its type.
static func is_valid_value(type: StringName, value: int) -> bool:
	match type:
		&"straight":
			return value >= 0 and value <= 36
		&"dozen", &"column":
			return value >= 1 and value <= 3
	return true


## True if the bet wins on `number`.
static func wins(type: StringName, value: int, number: int) -> bool:
	if number == 0:
		return type == &"straight" and value == 0
	match type:
		&"straight":
			return value == number
		&"red":
			return number in RED
		&"black":
			return not number in RED
		&"odd":
			return number % 2 == 1
		&"even":
			return number % 2 == 0
		&"low":
			return number <= 18
		&"high":
			return number >= 19
		&"dozen":
			return (number - 1) / 12 + 1 == value
		&"column":
			return (number - 1) % 3 + 1 == value
	return false


## Colour name of a number: &"green", &"red" or &"black".
static func color_of(number: int) -> StringName:
	if number == 0:
		return &"green"
	return &"red" if number in RED else &"black"


## True if `a` and `b` sit next to each other on the wheel.
static func are_neighbors(a: int, b: int) -> bool:
	var ia: int = WHEEL_ORDER.find(a)
	var ib: int = WHEEL_ORDER.find(b)
	if ia < 0 or ib < 0 or ia == ib:
		return false
	var d: int = absi(ia - ib)
	return d == 1 or d == WHEEL_ORDER.size() - 1
