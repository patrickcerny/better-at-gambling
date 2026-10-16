class_name CrapsLogic
extends StationLogicBase
## The craps table (Patrick: "Craps but only with 2 dices (actual dices thrown)"): two dice, four
## bets, everyone at the table bets on the same rolls.
##
## Bets:
## - Pass line: on the come-out roll 7 or 11 wins, 2, 3 or 12 loses, any other total becomes the
##   point; then the dice roll until the point comes again (wins) or a 7 (loses). Pays 1:1.
## - Don't Pass: the other side. Come-out 2 or 3 wins, 7 or 11 loses, 12 is a push (bar 12); once
##   a point is on, a 7 wins and the point loses. Pays 1:1.
## - Field (one roll): 3, 4, 9, 10, 11 pay 1:1, 2 and 12 pay 2:1, 5 to 8 lose.
## - Any Seven (one roll): a 7 pays 4:1.
## Line bets go down only on a come-out roll and ride until they are decided; the one-roll bets go
## down before any roll. No come or odds bets.
##
## Round: BETTING (the countdown starts with the first chip on the table; the shooter may throw
## with SHOOT once `craps_shoot_lock` has passed, the stickman throws for a shooter who waits it
## out) → ROLLING (the server has drawn the roll and sent it; the dice are in the air on every
## client, `craps_throw_time`) → RESULT (every decided bet settles) → BETTING. The shooter is the
## player who has sat at the table longest and keeps the dice until a seven-out, then they pass to
## the next player in sitting order. The money never depends on the dice on screen: clients only
## steer their thrown dice onto the faces the server already settled on.

enum State { IDLE, BETTING, ROLLING, RESULT }

const BET_TYPES: Array[StringName] = [&"pass", &"dont_pass", &"field", &"any_seven"]
const LINE_BETS: Array[StringName] = [&"pass", &"dont_pass"]
## Totals that become the point on a come-out roll.
const POINTS: Array[int] = [4, 5, 6, 8, 9, 10]
## Totals the Field pays on (2 and 12 double).
const FIELD: Array[int] = [2, 3, 4, 9, 10, 11, 12]
## The odds printed on the felt and the panel (what the table says; BalanceConfig has what pays).
const TABLE_ODDS: Dictionary = {&"pass": "1:1", &"dont_pass": "1:1", &"field": "1:1", &"any_seven": "4:1"}
const NAMES: Dictionary = {&"pass": "Pass Line", &"dont_pass": "Don't Pass", &"field": "Field", &"any_seven": "Any Seven"}

var spots: int = 6
## Seated players in the order they sat down: the first has sat longest.
var players: Array[int] = []
## Who throws the next roll (−1 = nobody seated: the stickman throws).
var shooter: int = -1
var state: State = State.IDLE
## BETTING: seconds until the stickman throws (only while `counting`). ROLLING: seconds until the
## dice rest. RESULT: seconds until the next betting window.
var timer: float = 0.0
## True while chips are on the table and the throw countdown runs.
var counting: bool = false
## The point (0 = the next roll is a come-out roll).
var point: int = 0
## Open bets: {player, type, amount, covered}.
var bets: Array[Dictionary] = []
## The last roll's two faces ([] before the first roll and between rounds of a fresh table).
var dice: Array[int] = []
## Seed of the throw clients animate for the current roll (−1 = none).
var throw_seed: int = -1
## Seconds since the dice left the shooter's hand (ROLLING).
var roll_time: float = 0.0
## What the last roll decided: &"natural", &"craps", &"point_set", &"point_made", &"seven_out",
## &"roll" (nothing on the line) or &"" (no roll yet).
var outcome: StringName = &""
var rolls_played: int = 0
## Seconds the current betting window has been open (SHOOT waits for `craps_shoot_lock`).
var open_for: float = 0.0
## Who threw the roll in the air (−1 = the stickman).
var thrown_by: int = -1


func _on_setup() -> void:
	game_id = &"craps"


func can_join(p: int) -> bool:
	return p in players or players.size() < spots


func join(p: int) -> Dictionary:
	if p in players:
		return OK_RESULT
	if players.size() >= spots:
		return fail(&"seat_taken")
	players.append(p)
	if shooter < 0:
		shooter = p
	if state == State.IDLE:
		_start_betting()
	return OK_RESULT


## The player stands up: their bets stay on the felt and are decided by the coming rolls (the
## stickman throws when nobody is left). A shooter who leaves passes the dice to the next player.
func leave(p: int) -> void:
	var i: int = players.find(p)
	if i < 0:
		return
	players.remove_at(i)
	if p == shooter:
		shooter = players[i % players.size()] if not players.is_empty() else -1
		events.append(GameEvents.make(&"craps_new_shooter", {"station": station_id, "shooter": shooter}))


## Minimum per bet and the most one player may have on the table at once, after the limits
## multiplier.
func limits() -> Vector2i:
	return Vector2i(scaled(balance.craps_min_bet), scaled(balance.craps_max_total))


## Total a player has on the table.
func player_total(p: int) -> int:
	var sum: int = 0
	for b: Dictionary in bets:
		if b["player"] == p:
			sum += int(b["amount"])
	return sum


## True when `p` has a bet of `type` down.
func has_bet(p: int, type: StringName) -> bool:
	for b: Dictionary in bets:
		if b["player"] == p and b["type"] == type:
			return true
	return false


## Bet shape: `{type: pass|dont_pass|field|any_seven, amount}`. More chips on a bet you already
## have go onto it (one entry per player and type).
func place_bet(p: int, bet: Dictionary) -> Dictionary:
	if not p in players:
		return fail(&"not_seated")
	if state != State.BETTING:
		return fail(&"betting_closed")
	var type: StringName = StringName(bet.get("type", ""))
	var amount: int = int(bet.get("amount", 0))
	if not type in BET_TYPES:
		return fail(&"invalid_bet_type")
	if type in LINE_BETS:
		if point != 0:
			return fail(&"point_is_on")
		if has_bet(p, &"dont_pass" if type == &"pass" else &"pass"):
			return fail(&"one_side_only")
	var lim: Vector2i = limits()
	if amount < lim.x:
		return fail(&"below_min")
	if player_total(p) + amount > lim.y:
		return fail(&"above_max")
	if not _take_stake(p, amount):
		return fail(&"insufficient_funds")
	var merged: bool = false
	for b: Dictionary in bets:
		if b["player"] == p and b["type"] == type:
			b["amount"] = int(b["amount"]) + amount
			b["covered"] = int(b.get("covered", 0)) + last_covered
			merged = true
			break
	if not merged:
		bets.append({"player": p, "type": type, "amount": amount, "covered": last_covered})
	events.append(GameEvents.bet_placed(p, station_id, amount, {"game": game_id, "type": type, "value": 0}))
	if not counting:
		counting = true
		timer = balance.craps_shoot_time
	return OK_RESULT


## `shoot` (the shooter throws now) and `clear_bets` (take back what may still come down: every
## bet on a come-out roll, only the one-roll bets once a point is on).
func player_action(p: int, action: StringName, _params: Dictionary = {}) -> Dictionary:
	match action:
		&"shoot":
			if state != State.BETTING:
				return fail(&"betting_closed")
			if p != shooter:
				return fail(&"not_shooter")
			if bets.is_empty():
				return fail(&"no_bets")
			if open_for < balance.craps_shoot_lock:
				return fail(&"wait_for_bets")
			_throw(p)
			return OK_RESULT
		&"clear_bets":
			if state != State.BETTING:
				return fail(&"betting_closed")
			for b: Dictionary in bets.duplicate():
				if b["player"] != p or (b["type"] in LINE_BETS and point != 0):
					continue
				bets.erase(b)
				# Only what the player paid comes back: Fake Cash never turns into real money.
				var back: int = int(b["amount"]) - int(b.get("covered", 0))
				if back > 0:
					economy.apply(p, back, &"bet_cleared", station_id)
			if bets.is_empty():
				counting = false  # nothing on the felt: wait for the next first chip
				timer = 0.0
			return OK_RESULT
	return fail(&"unknown_action")


func tick(delta: float) -> void:
	# Energy Drink (alone at the table) speeds up the waiting, never the dice in the air.
	var wait: float = delta * (2.0 if _fast_for(players) else 1.0)
	match state:
		State.IDLE:
			if not players.is_empty():
				_start_betting()
		State.BETTING:
			open_for += wait
			if counting:
				timer -= wait
				if timer <= 0.0:
					_throw(-1)  # the stickman throws for a shooter who waited it out
			elif players.is_empty():
				_go_idle()
		State.ROLLING:
			roll_time += delta
			timer -= delta
			if timer <= 0.0:
				_resolve()
		State.RESULT:
			timer -= wait
			if timer <= 0.0:
				if players.is_empty() and bets.is_empty():
					_go_idle()
				else:
					_start_betting()


## Seconds until a bet placed now is first decided (a one-roll bet; a line bet can ride longer and
## the match end settles it with `auto_resolve`).
func round_seconds() -> float:
	return (timer if state == State.BETTING and counting else balance.craps_shoot_time) + balance.craps_throw_time


func has_stake(p: int) -> bool:
	return state != State.IDLE and player_total(p) > 0


## The match ends: the dice in the air land, then the stickman keeps throwing (at once) until
## every bet on the felt is decided.
func auto_resolve() -> void:
	if state == State.ROLLING:
		_resolve()
	var guard: int = 0
	while not bets.is_empty() and guard < 1000:
		_throw(-1)
		_resolve()
		guard += 1
	if state == State.BETTING and bets.is_empty():
		_go_idle()


## A minigame starts (or the stickman was attacked): every bet comes back, the point goes off, the
## dice come off the felt.
func refund_all() -> void:
	if state == State.IDLE and bets.is_empty():
		return
	var totals: Dictionary = {}
	for b: Dictionary in bets:
		_refund(int(b["player"]), int(b["amount"]), int(b.get("covered", 0)), totals)
	bets.clear()
	point = 0
	_go_idle()
	_emit_refunds(totals)


func get_public_state() -> Dictionary:
	return {
		"game": game_id, "state": state, "timer": timer, "counting": counting, "players": players.duplicate(),
		"shooter": shooter, "point": point, "bets": bets.duplicate(true), "dice": dice.duplicate(),
		"throw_seed": throw_seed, "roll_time": snappedf(roll_time, 0.01), "outcome": outcome,
		"thrown_by": thrown_by, "shoot_in": maxf(balance.craps_shoot_lock - open_for, 0.0) if state == State.BETTING else 0.0,
	}


## A new betting window (after a roll, or for the first player at a resting table).
func _start_betting() -> void:
	state = State.BETTING
	open_for = 0.0
	roll_time = 0.0
	throw_seed = -1
	if shooter < 0 or not shooter in players:
		shooter = players[0] if not players.is_empty() else -1
	counting = not bets.is_empty()  # line bets riding a point: the countdown runs at once
	timer = balance.craps_shoot_time if counting else 0.0
	events.append(GameEvents.make(&"craps_betting", {"station": station_id, "point": point, "shooter": shooter}))


func _go_idle() -> void:
	state = State.IDLE
	counting = false
	timer = 0.0
	roll_time = 0.0
	throw_seed = -1
	dice = []
	outcome = &""


## The dice leave the shooter's hand (`by`; −1 = the stickman): the roll is drawn now and sent
## with the throw's seed; the bets settle once the dice rest (`_resolve`).
func _throw(by: int) -> void:
	var roll: Vector2i = _draw_roll()
	dice = [roll.x, roll.y]
	throw_seed = rng.range_int(1, 2_000_000_000)
	thrown_by = by
	state = State.ROLLING
	counting = false
	roll_time = 0.0
	timer = balance.craps_throw_time
	events.append(GameEvents.make(&"craps_rolled", {"station": station_id, "shooter": by, "dice": dice.duplicate(), "seed": throw_seed, "seconds": timer, "point": point}))


## The dice rest: every bet the roll decides settles, the point moves, the dice pass on a seven-out.
func _resolve() -> void:
	var total: int = int(dice[0]) + int(dice[1]) if dice.size() == 2 else 7
	var before: int = point
	outcome = outcome_of(before, total)
	rolls_played += 1
	var played: Dictionary[int, bool] = {}
	for b: Dictionary in bets.duplicate():
		var ratio: float = decide(StringName(b["type"]), before, total)
		if is_nan(ratio):
			continue  # rides on to the next roll
		var p: int = int(b["player"])
		var stake: int = int(b["amount"])
		var base_return: int = 0
		if ratio == 0.0:
			base_return = stake  # push (bar 12)
		elif ratio > 0.0:
			base_return = stake + _stochastic_round(stake * pay_ratio(StringName(b["type"]), total, balance))
		_settle(p, stake, base_return, {"type": b["type"], "value": 0, "dice": dice.duplicate(), "total": total, "point": before})
		bets.erase(b)
		played[p] = true
	for p: int in played.keys():
		modifiers.consume_round(p, game_id)
	match outcome:
		&"point_set":
			point = total
		&"point_made":
			point = 0
		&"seven_out":
			point = 0
			_pass_dice()
	events.append(GameEvents.make(&"craps_result", {"station": station_id, "dice": dice.duplicate(), "total": total, "outcome": outcome, "point": point, "shooter": shooter}))
	state = State.RESULT
	timer = balance.craps_result_time


## Seven-out: the dice go to the next player in sitting order.
func _pass_dice() -> void:
	if players.is_empty():
		shooter = -1
		return
	var i: int = players.find(shooter)
	shooter = players[(i + 1) % players.size()] if i >= 0 else players[0]
	events.append(GameEvents.make(&"craps_new_shooter", {"station": station_id, "shooter": shooter}))


## The roll, with a quiet thumb on the scale (Patrick, 0.9.6: "always favoured to win for you, by
## a bit, like the other games, but dont show it"): with `balance.craps_favour` chance a roll on
## which no bet on the table would win and at least one would lose is redrawn once (a roll that
## decides nothing stands: redrawing it would favour nobody), then every bettor's luck rerolls it
## the way the other tables reroll a card or a wheel. Nothing of it reaches the clients: they get
## the final faces only.
func _draw_roll() -> Vector2i:
	var current: Array[Vector2i] = [_random_roll()]
	if not bets.is_empty() and _nobody_wins_somebody_loses(current[0].x + current[0].y) and rng.chance(balance.craps_favour):
		current[0] = _random_roll()
	var seen: Dictionary[int, bool] = {}
	for b: Dictionary in bets:
		var p: int = int(b["player"])
		if seen.has(p):
			continue
		seen[p] = true
		var lk: int = modifiers.get_luck(p, game_id)
		if lk == 0:
			continue
		var d: LuckRng.Draw = luck.draw(lk, func() -> Vector2i:
			var out: Vector2i = current[0]
			current[0] = _random_roll()
			return out, func(r: Vector2i) -> float: return _quality_for(p, r.x + r.y))
		current[0] = d.value
		if d.luck_changed:
			events.append(GameEvents.luck_flourish(p, station_id, &"lucky" if lk > 0 else &"jinxed"))
	return current[0]


func _random_roll() -> Vector2i:
	return Vector2i(rng.range_int(1, 6), rng.range_int(1, 6))


## True when `total` would make no bet on the table win and at least one lose.
func _nobody_wins_somebody_loses(total: int) -> bool:
	var loses: bool = false
	for b: Dictionary in bets:
		var r: float = decide(StringName(b["type"]), point, total)
		if is_nan(r):
			continue
		if r > 0.0:
			return false
		if r < 0.0:
			loses = true
	return loses


## How good `total` is for player `p` (their bets' winnings minus losses on it, at the table's
## printed odds): what luck compares.
func _quality_for(p: int, total: int) -> float:
	var q: float = 0.0
	for b: Dictionary in bets:
		if int(b["player"]) != p:
			continue
		var r: float = decide(StringName(b["type"]), point, total)
		if is_nan(r) or r == 0.0:
			continue
		q += float(b["amount"]) * (pay_ratio(StringName(b["type"]), total, balance) if r > 0.0 else -1.0)
	return q


## Rounds a non-negative amount down, plus one more dollar with probability equal to the
## fraction, so small bets keep the exact payout ratio in expectation (as roulette does).
func _stochastic_round(x: float) -> int:
	var whole: int = int(floor(x + 0.000001))
	return whole + (1 if rng.chance(x - whole) else 0)


## What `total` does to a bet of `type` with the point at `p` (0 = come-out): 1.0 wins, −1.0
## loses, 0.0 is a push, NAN means undecided (the bet rides).
static func decide(type: StringName, p: int, total: int) -> float:
	match type:
		&"pass":
			if p == 0:
				if total == 7 or total == 11:
					return 1.0
				if total == 2 or total == 3 or total == 12:
					return -1.0
				return NAN
			if total == p:
				return 1.0
			return -1.0 if total == 7 else NAN
		&"dont_pass":
			if p == 0:
				if total == 2 or total == 3:
					return 1.0
				if total == 12:
					return 0.0
				if total == 7 or total == 11:
					return -1.0
				return NAN
			if total == 7:
				return 1.0
			return -1.0 if total == p else NAN
		&"field":
			return 1.0 if total in FIELD else -1.0
		&"any_seven":
			return 1.0 if total == 7 else -1.0
	return -1.0


## Profit ratio a winning bet of `type` is paid on `total`. The felt says 1:1, 2:1 and 4:1; the
## house pays the one-roll bets a little better (like the horse race), in BalanceConfig.
static func pay_ratio(type: StringName, total: int, cfg: BalanceConfig) -> float:
	match type:
		&"field":
			return cfg.craps_field_double_ratio if total == 2 or total == 12 else cfg.craps_field_ratio
		&"any_seven":
			return cfg.craps_any_seven_ratio
	return cfg.craps_line_ratio


## What a roll means on the line: come-out &"natural" (7, 11), &"craps" (2, 3, 12) or
## &"point_set"; with a point on &"point_made", &"seven_out" or &"roll".
static func outcome_of(p: int, total: int) -> StringName:
	if p == 0:
		if total == 7 or total == 11:
			return &"natural"
		if total == 2 or total == 3 or total == 12:
			return &"craps"
		return &"point_set"
	if total == p:
		return &"point_made"
	return &"seven_out" if total == 7 else &"roll"


## Chance of each total with two fair dice.
static func total_chance(total: int) -> float:
	return float(6 - absi(total - 7)) / 36.0 if total >= 2 and total <= 12 else 0.0


## Exact return per unit staked for one player alone at the table with one bet of `type`, neutral
## luck, the favour redraw included (what tests/sim checks the table against).
static func exact_rtp(cfg: BalanceConfig, type: StringName) -> float:
	var f: float = cfg.craps_favour
	if type == &"field" or type == &"any_seven":
		var lose: float = 0.0
		var ret: float = 0.0
		for t: int in range(2, 13):
			if decide(type, 0, t) > 0.0:
				ret += total_chance(t) * (1.0 + pay_ratio(type, t, cfg))
			else:
				lose += total_chance(t)
		return ret * (1.0 + f * lose)
	# Come-out: a losing total is redrawn with chance f (the redraw stands).
	var lose_co: float = 0.0
	for t: int in range(2, 13):
		if decide(type, 0, t) < 0.0:
			lose_co += total_chance(t)
	var win: float = 0.0
	var push: float = 0.0
	for t: int in range(2, 13):
		var q: float = total_chance(t)
		var r: float = decide(type, 0, t)
		var final: float = q * (1.0 - f) + f * lose_co * q if r < 0.0 else q * (1.0 + f * lose_co)
		if r > 0.0:
			win += final
		elif r == 0.0:
			push += final
		elif is_nan(r):
			# The point is on: each roll wins with w, loses with l (a losing roll redrawn with f).
			var hit: float = total_chance(t)
			var seven: float = total_chance(7)
			var good: float = hit if type == &"pass" else seven
			var bad: float = seven if type == &"pass" else hit
			var w: float = good * (1.0 + f * bad)
			var l: float = bad * (1.0 - f) + f * bad * bad
			win += final * w / (w + l)
	return win * (1.0 + cfg.craps_line_ratio) + push
