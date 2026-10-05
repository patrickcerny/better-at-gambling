class_name HotTableDirector
extends RefCounted
## Hot Table event (§2.3): every 45-60 s of casino time one random station turns HOT for 30 s and
## pays ×1.25 on winnings there. The next hot table is never announced early.

var stations: StationManager
var balance: BalanceConfig
var rng: SeededRng
var current: StringName = &""
## Seconds until the next hot table starts (counting only while the casino is open).
var next_in: float = 0.0
var time_left: float = 0.0
var events: Array[Dictionary] = []


func _init(p_stations: StationManager, p_balance: BalanceConfig, p_rng: SeededRng) -> void:
	stations = p_stations
	balance = p_balance
	rng = p_rng
	next_in = _interval()


## Casino time passed.
func tick(delta: float) -> void:
	if current != &"":
		time_left -= delta
		if time_left <= 0.0:
			stop()
	next_in -= delta
	if next_in <= 0.0:
		next_in += _interval()
		_start()


## Ends the current hot table (also at match end).
func stop() -> void:
	if current == &"":
		return
	events.append(GameEvents.make(&"hot_table_ended", {"station": current}))
	stations.set_hot(&"", 1.0)
	current = &""
	time_left = 0.0


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	return out


func _start() -> void:
	var ids: Array = stations.logics.keys()
	if ids.is_empty():
		return
	ids.sort()
	var previous: StringName = current
	stop()
	var pool: Array = ids.filter(func(s: StringName) -> bool: return s != previous)
	var pick: StringName = pool[rng.range_int(0, pool.size() - 1)] if not pool.is_empty() else ids[0]
	current = pick
	time_left = balance.hot_table_duration
	stations.set_hot(pick, balance.hot_table_multiplier)
	events.append(GameEvents.make(&"hot_table", {"station": pick, "seconds": balance.hot_table_duration, "multiplier": balance.hot_table_multiplier}))


func _interval() -> float:
	return rng.range_float(balance.hot_table_interval_min, balance.hot_table_interval_max)
