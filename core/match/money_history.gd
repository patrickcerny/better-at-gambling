class_name MoneyHistory
extends RefCounted
## Per-player balance samples over the casino time of a match, for the results screen's
## money-over-time graph (§2.11). Sample 0 is the start money, then one sample every `interval`
## casino seconds, and `finish` appends the final balance. The interval grows with the match
## length so a series never has more than about `MAX_SAMPLES` points (small match_ended payload).

const BASE_INTERVAL: float = 10.0
const MAX_SAMPLES: int = 60

## Casino seconds between two samples.
var interval: float = BASE_INTERVAL
## player → balances (plain ints, oldest first).
var series: Dictionary[int, Array] = {}
var _next_at: float = 0.0
var _count: int = 0
var _finished: bool = false


## Starts a fresh history for a match of `duration_s` casino seconds; `balances` is player → money.
func start(duration_s: float, balances: Dictionary) -> void:
	interval = interval_for(duration_s)
	series.clear()
	_count = 0
	_finished = false
	_next_at = interval
	for id: Variant in balances:
		series[int(id)] = []
	_record(balances)


## Seconds between samples for a match of `duration_s` casino seconds (clients use it for the
## graph's time axis, so it is not sent).
static func interval_for(duration_s: float) -> float:
	return maxf(BASE_INTERVAL, ceilf(duration_s / float(MAX_SAMPLES)))


## A player who joined mid-match: their line starts flat at `money` up to now.
func add_player(id: int, money: int) -> void:
	if series.has(id) or _count == 0:
		return
	var line: Array = []
	for i: int in _count:
		line.append(money)
	series[id] = line


## Call every casino tick; records a sample whenever `casino_time` passed the next sample time.
func tick(casino_time: float, balances: Dictionary) -> void:
	if _finished or _count == 0:
		return
	while casino_time + 0.0001 >= _next_at:
		_record(balances)
		_next_at += interval


## The final balances, once (the last point of every line).
func finish(balances: Dictionary) -> void:
	if _finished or _count == 0:
		return
	_record(balances)
	_finished = true


func samples() -> int:
	return _count


## The series of one player (empty if unknown), as plain ints.
func of(id: int) -> Array:
	return (series.get(id, []) as Array).duplicate()


func _record(balances: Dictionary) -> void:
	for id: int in series:
		var line: Array = series[id]
		line.append(int(balances.get(id, line[-1] if not line.is_empty() else 0)))
	_count += 1
