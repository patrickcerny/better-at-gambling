class_name OddJobs
extends RefCounted
## The Odd Jobs cabinet next to the Gift Shop: broke players smash its button for a little money.
## Each `odd_jobs_press` fills the player's bar by 1/presses-needed; a full bar pays $50 through
## the normal balance path and starts over. The richer you are the more presses a bar takes
## (10 at $0 up to 60 at $499); at $500 or more the cabinet refuses and a half-filled bar freezes.
## Left alone, a bar drains slowly, so nobody fills one a press a minute. Presses beyond about 12
## a second are dropped (not punished). The server owns every number here.

const PAYOUT: int = 50
## At or above this balance the cabinet refuses ("You've got enough. Go gamble!").
const CAP: int = 500
const MIN_PRESSES: int = 10
const MAX_PRESSES: int = 60
const PRESSES_PER_SECOND: float = 12.0
## Seconds after the last press before the bar starts draining, and how fast it drains (bar/s).
const DECAY_DELAY: float = 0.5
const DECAY_PER_SECOND: float = 0.1
## At most one `odd_jobs_bar` per player per this many seconds (payouts send one at once).
const EVENT_INTERVAL: float = 0.1

var economy: Economy
var events: Array[Dictionary] = []
var _fill: Dictionary[int, float] = {}
var _last_press: Dictionary[int, float] = {}
var _last_sent: Dictionary[int, float] = {}
var _dirty: Dictionary[int, bool] = {}
var _limiter: RateLimiter = RateLimiter.new(PRESSES_PER_SECOND)


func _init(p_economy: Economy) -> void:
	economy = p_economy


## Presses one full bar takes at this balance (linear, 10 at $0 to 60 at $499; 0 = refused).
static func presses_needed(money: int) -> int:
	if money >= CAP:
		return 0
	var m: int = clampi(money, 0, CAP - 1)
	return MIN_PRESSES + roundi(float(MAX_PRESSES - MIN_PRESSES) * m / float(CAP - 1))


func fill(player: int) -> float:
	return _fill.get(player, 0.0)


## One press of the button at game time `now`. Returns {ok, error}; a press over the rate limit
## is ok but does nothing.
func press(player: int, now: float) -> Dictionary:
	if not economy.has_player(player):
		return StationLogicBase.fail(&"unknown_player")
	var needed: int = presses_needed(economy.balance(player))
	if needed == 0:
		_send(player, now, true)
		return StationLogicBase.fail(&"enough_money")
	if not _limiter.allow(player, now):
		return StationLogicBase.OK_RESULT
	_last_press[player] = now
	var f: float = fill(player) + 1.0 / needed
	if f >= 1.0 - 0.0001:
		_fill[player] = 0.0
		economy.apply(player, PAYOUT, &"odd_jobs", &"house")
		events.append(GameEvents.make(&"odd_jobs_payout", {"player": player, "amount": PAYOUT, "balance": economy.balance(player)}))
		_send(player, now, true)
	else:
		_fill[player] = f
		_send(player, now, false)
	return StationLogicBase.OK_RESULT


## Drains idle bars (frozen while the player has $500+) and sends throttled bar updates.
func tick(delta: float, now: float) -> void:
	for player: int in _fill.keys():
		var f: float = _fill[player]
		if f <= 0.0 or not economy.has_player(player) or economy.balance(player) >= CAP:
			continue
		if now - _last_press.get(player, -INF) < DECAY_DELAY:
			continue
		_fill[player] = maxf(0.0, f - DECAY_PER_SECOND * delta)
		_dirty[player] = true
	for player: int in _dirty.keys():
		_send(player, now, false)


func remove_player(player: int) -> void:
	for d: Dictionary in [_fill, _last_press, _last_sent, _dirty]:
		d.erase(player)


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	return out


func _send(player: int, now: float, force: bool) -> void:
	if not force and now - _last_sent.get(player, -INF) < EVENT_INTERVAL:
		_dirty[player] = true
		return
	_dirty.erase(player)
	_last_sent[player] = now
	var money: int = economy.balance(player) if economy.has_player(player) else 0
	events.append(GameEvents.make(&"odd_jobs_bar", {"player": player, "fill": snappedf(fill(player), 0.001), "presses_needed": presses_needed(money), "enough": money >= CAP}))
