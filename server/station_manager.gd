class_name StationManager
extends RefCounted
## Owns one StationLogicBase per station in the map, tracks who sits where, routes station
## intents, ticks the games and collects their events (§3.6).

## Station id → logic.
var logics: Dictionary[StringName, StationLogicBase] = {}
## Station id → game id.
var game_of: Dictionary[StringName, StringName] = {}
## Player → station id ("" when standing).
var seat_of: Dictionary[int, StringName] = {}
## Station id → true while Hot.
var hot: Dictionary[StringName, bool] = {}
## Station ids that are VIP (limits ×3, entry check).
var vip: Dictionary[StringName, bool] = {}

var _balance: BalanceConfig
var _limits_multiplier: float = 1.0


## Builds every station from `stations` (station id → game id) using the registry's logic scripts.
func setup(stations: Dictionary, logic_scripts: Dictionary, balance: BalanceConfig, economy: Economy, modifiers: ModifierStack, rng: SeededRng, jackpot: ProgressiveJackpot, vip_ids: Array = []) -> void:
	_balance = balance
	for sid: Variant in stations:
		var station_id: StringName = StringName(sid)
		var game_id: StringName = StringName(stations[sid])
		var script: Script = logic_scripts.get(game_id, null)
		if script == null:
			Log.error(&"stations", "no logic registered for game %s (station %s)" % [game_id, station_id])
			continue
		var logic: StationLogicBase = script.new() as StationLogicBase
		logic.game_id = game_id
		logic.setup(station_id, balance, economy, modifiers, rng.fork(), jackpot)
		logics[station_id] = logic
		game_of[station_id] = game_id
		if station_id in vip_ids:
			vip[station_id] = true
	set_limits_multiplier(1.0)


## Applies the segment limits multiplier (VIP stations get ×3 on top).
func set_limits_multiplier(m: float) -> void:
	_limits_multiplier = m
	for sid: StringName in logics:
		logics[sid].limits_multiplier = m * (3.0 if vip.get(sid, false) else 1.0)


## Applies the global winnings multiplier (Last Call).
func set_global_multiplier(m: float) -> void:
	for sid: StringName in logics:
		logics[sid].global_multiplier = m


## Marks one station hot (or clears all with &"").
func set_hot(station_id: StringName, multiplier: float) -> void:
	for sid: StringName in hot.keys():
		logics[sid].hot_multiplier = 1.0
	hot.clear()
	if station_id != &"" and logics.has(station_id):
		hot[station_id] = true
		logics[station_id].hot_multiplier = multiplier


## Station the player is at, or &"".
func station_of(player: int) -> StringName:
	return seat_of.get(player, &"")


## True if the player is seated anywhere.
func is_seated(player: int) -> bool:
	return seat_of.get(player, &"") != &""


## Seats a player. Fails if unknown station, already seated elsewhere, or no free seat.
func sit(player: int, station_id: StringName) -> Dictionary:
	if not logics.has(station_id):
		return StationLogicBase.fail(&"unknown_station")
	var current: StringName = station_of(player)
	if current == station_id:
		return StationLogicBase.OK_RESULT
	if current != &"":
		return StationLogicBase.fail(&"already_seated")
	var logic: StationLogicBase = logics[station_id]
	if not logic.can_join(player):
		return StationLogicBase.fail(&"seat_taken")
	var res: Dictionary = logic.join(player)
	if res["ok"]:
		seat_of[player] = station_id
	return res


## Stands the player up (open bets stay in and auto-resolve by the game's rule).
func leave(player: int) -> Dictionary:
	var current: StringName = station_of(player)
	if current == &"":
		return StationLogicBase.fail(&"not_seated")
	logics[current].leave(player)
	seat_of.erase(player)
	return StationLogicBase.OK_RESULT


## Routes a station intent (place_bet / clear_bets / action) after checking the seat.
func route(player: int, intent: Dictionary) -> Dictionary:
	var station_id: StringName = StringName(intent.get("station", ""))
	if not logics.has(station_id):
		return StationLogicBase.fail(&"unknown_station")
	if station_of(player) != station_id:
		return StationLogicBase.fail(&"not_seated")
	var logic: StationLogicBase = logics[station_id]
	match intent["type"]:
		&"place_bet":
			var bet: Variant = intent.get("bet", {})
			if typeof(bet) != TYPE_DICTIONARY:
				return StationLogicBase.fail(&"bad_bet")
			return logic.place_bet(player, bet)
		&"clear_bets":
			return logic.player_action(player, &"clear_bets")
		&"action":
			var params: Variant = intent.get("params", {})
			return logic.player_action(player, StringName(intent["action"]), params if typeof(params) == TYPE_DICTIONARY else {})
	return StationLogicBase.fail(&"unknown_intent")


## Ticks every station.
func tick(delta: float) -> void:
	for sid: StringName in logics:
		logics[sid].tick(delta)


## Resolves every open round (phase end).
func auto_resolve_all() -> void:
	for sid: StringName in logics:
		logics[sid].auto_resolve()


## Collects events from all stations.
func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sid: StringName in logics:
		out.append_array(logics[sid].drain_events())
	return out


## Public state of every station.
func public_states() -> Dictionary:
	var out: Dictionary = {}
	for sid: StringName in logics:
		var st: Dictionary = logics[sid].get_public_state()
		st["hot"] = hot.get(sid, false)
		st["vip"] = vip.get(sid, false)
		out[sid] = st
	return out


## Private state of the player's own station (e.g. a peeked hole card).
func private_state(player: int) -> Dictionary:
	var sid: StringName = station_of(player)
	if sid == &"":
		return {}
	return logics[sid].get_private_state(player)
