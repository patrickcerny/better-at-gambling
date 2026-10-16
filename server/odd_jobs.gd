class_name OddJobs
extends RefCounted
## The Odd Jobs cabinet next to the Gift Shop: one big 3D button and ONE bar shared by everybody in
## the casino. Every `odd_jobs_press` adds the clicker's share, 1/presses-needed at their balance
## (10 presses at $0 up to 60 at $499), so a broke player fills it faster; whoever's click fills
## the bar is paid $50 through the normal balance path ("the last click wins") and the bar starts
## over. At $500 or more a player's clicks are refused. Left alone the bar drains slowly, so nobody
## fills one a press a minute. Clicks beyond about 12 a second per player are dropped (not
## punished). The server owns every number here.

const PAYOUT: int = 50
## At or above this balance the cabinet refuses ("You've got enough. Go gamble!").
const CAP: int = 500
const MIN_PRESSES: int = 10
const MAX_PRESSES: int = 60
const PRESSES_PER_SECOND: float = 12.0
## Seconds after the last click (anyone's) before the bar starts draining, and how fast (bar/s).
const DECAY_DELAY: float = 0.5
const DECAY_PER_SECOND: float = 0.1
## At most one `odd_jobs_bar` per this many seconds (a payout sends one at once).
const EVENT_INTERVAL: float = 0.1

var economy: Economy
var events: Array[Dictionary] = []
## The shared bar, 0..1.
var _fill: float = 0.0
var _last_press: float = -INF
var _last_sent: float = -INF
var _dirty: bool = false
## Who clicked last (the `player` of the next bar event; -1 = the bar only drained).
var _last_by: int = -1
var _limiter: RateLimiter = RateLimiter.new(PRESSES_PER_SECOND)


func _init(p_economy: Economy) -> void:
	economy = p_economy


## Presses one full bar takes at this balance (linear, 10 at $0 to 60 at $499; 0 = refused).
static func presses_needed(money: int) -> int:
	if money >= CAP:
		return 0
	var m: int = clampi(money, 0, CAP - 1)
	return MIN_PRESSES + roundi(float(MAX_PRESSES - MIN_PRESSES) * m / float(CAP - 1))


## The shared bar (0..1).
func fill() -> float:
	return _fill


## One click of the button by `player` at game time `now`. Returns {ok, error}; a click over the
## rate limit is ok but does nothing.
func press(player: int, now: float) -> Dictionary:
	if not economy.has_player(player):
		return StationLogicBase.fail(&"unknown_player")
	var needed: int = presses_needed(economy.balance(player))
	if needed == 0:
		return StationLogicBase.fail(&"enough_money")
	if not _limiter.allow(player, now):
		return StationLogicBase.OK_RESULT
	_last_press = now
	_last_by = player
	var f: float = _fill + 1.0 / needed
	if f >= 1.0 - 0.0001:
		_fill = 0.0
		economy.apply(player, PAYOUT, &"odd_jobs", &"house")
		events.append(GameEvents.make(&"odd_jobs_payout", {"player": player, "amount": PAYOUT, "balance": economy.balance(player)}))
		_send(now, true)
	else:
		_fill = f
		_send(now, false)
	return StationLogicBase.OK_RESULT


## Drains the idle bar and sends throttled bar updates.
func tick(delta: float, now: float) -> void:
	if _fill > 0.0 and now - _last_press >= DECAY_DELAY:
		_fill = maxf(0.0, _fill - DECAY_PER_SECOND * delta)
		_last_by = -1
		_dirty = true
	if _dirty:
		_send(now, false)


func remove_player(player: int) -> void:
	if _last_by == player:
		_last_by = -1


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	return out


func _send(now: float, force: bool) -> void:
	if not force and now - _last_sent < EVENT_INTERVAL:
		_dirty = true
		return
	_dirty = false
	_last_sent = now
	events.append(GameEvents.make(&"odd_jobs_bar", {"player": _last_by, "fill": snappedf(_fill, 0.001)}))
