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

## Station id → seconds left on its "Out of Order" sign (item). Nobody new sits, no new bets;
## rounds already running finish normally.
var out_of_order: Dictionary[StringName, float] = {}
## Seconds until the casino closes (pre-minigame warning, end of match); INF while open.
var closing_in: float = INF
var _balance: BalanceConfig
var _limits_multiplier: float = 1.0
var _global_multiplier: float = 1.0
## What `setup` got, for the stations a new floor plan adds (`apply_stations`).
var _logic_scripts: Dictionary = {}
var _economy: Economy
var _modifiers: ModifierStack
var _rng: SeededRng
var _jackpot: ProgressiveJackpot


## Builds every station from `stations` (station id → game id) using the registry's logic scripts.
func setup(stations: Dictionary, logic_scripts: Dictionary, balance: BalanceConfig, economy: Economy, modifiers: ModifierStack, rng: SeededRng, jackpot: ProgressiveJackpot, vip_ids: Array = []) -> void:
	_balance = balance
	_logic_scripts = logic_scripts
	_economy = economy
	_modifiers = modifiers
	_rng = rng
	_jackpot = jackpot
	for sid: Variant in stations:
		_add(StringName(sid), StringName(stations[sid]), StringName(sid) in vip_ids)
	set_limits_multiplier(1.0)


func _add(station_id: StringName, game_id: StringName, is_vip: bool) -> void:
	var script: Script = _logic_scripts.get(game_id, null)
	if script == null:
		Log.error(&"stations", "no logic registered for game %s (station %s)" % [game_id, station_id])
		return
	var logic: StationLogicBase = script.new() as StationLogicBase
	logic.game_id = game_id
	logic.setup(station_id, _balance, _economy, _modifiers, _rng.fork(), _jackpot)
	logics[station_id] = logic
	game_of[station_id] = game_id
	if is_vip:
		vip[station_id] = true


## A new floor plan (docs/FLOOR_PLAN.md): `stations` (station id → game id) is every station from
## now on. Stations that keep their id and game keep their logic (a blackjack shoe carries on);
## the others close and the new ones open with the current limits. Nobody may be seated at a
## station that goes (the server stands them up first); open bets were refunded at the minigame.
## Returns the ids that closed.
func apply_stations(stations: Dictionary, vip_ids: Array) -> Array[StringName]:
	var closed: Array[StringName] = []
	for sid: StringName in logics.keys():
		if StringName(stations.get(sid, &"")) == game_of[sid] and (sid in vip_ids) == vip.get(sid, false):
			continue
		closed.append(sid)
		logics[sid].refund_all()
		logics.erase(sid)
		game_of.erase(sid)
		vip.erase(sid)
		hot.erase(sid)
		out_of_order.erase(sid)
		for p: int in seat_of.keys():
			if seat_of[p] == sid:
				seat_of.erase(p)
	for sid: Variant in stations:
		if not logics.has(StringName(sid)):
			_add(StringName(sid), StringName(stations[sid]), StringName(sid) in vip_ids)
	set_limits_multiplier(_limits_multiplier)
	set_global_multiplier(_global_multiplier)
	return closed


## Applies the segment limits multiplier (VIP stations get ×3 on top).
func set_limits_multiplier(m: float) -> void:
	_limits_multiplier = m
	for sid: StringName in logics:
		logics[sid].limits_multiplier = m * (3.0 if vip.get(sid, false) else 1.0)


## Applies the global winnings multiplier (Last Call).
func set_global_multiplier(m: float) -> void:
	_global_multiplier = m
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
	if out_of_order.has(station_id):
		return StationLogicBase.fail(&"out_of_order")
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
			if out_of_order.has(station_id):
				return StationLogicBase.fail(&"out_of_order")
			var bet: Variant = intent.get("bet", {})
			if typeof(bet) != TYPE_DICTIONARY:
				return StationLogicBase.fail(&"bad_bet")
			if logic.round_seconds() > closing_in:
				return StationLogicBase.fail(&"table_closing")
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
	for sid: StringName in out_of_order.keys():
		out_of_order[sid] -= delta
		if out_of_order[sid] <= 0.0:
			out_of_order.erase(sid)


## True while the player has money in play anywhere (an open hand, bet, spin or Plinko chip).
func has_stake(player: int) -> bool:
	for sid: StringName in logics:
		if logics[sid].has_stake(player):
			return true
	return false


## Resolves every open round (end of the match).
func auto_resolve_all() -> void:
	for sid: StringName in logics:
		logics[sid].auto_resolve()


## A minigame starts: every open bet everywhere goes back to its owner and the tables reset.
func refund_all() -> void:
	for sid: StringName in logics:
		logics[sid].refund_all()


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
		if out_of_order.has(sid):
			st["out_of_order"] = snappedf(out_of_order[sid], 0.1)
		out[sid] = st
	return out


## Private state of the player's own station (e.g. a peeked hole card).
func private_state(player: int) -> Dictionary:
	var sid: StringName = station_of(player)
	if sid == &"":
		return {}
	return logics[sid].get_private_state(player)
