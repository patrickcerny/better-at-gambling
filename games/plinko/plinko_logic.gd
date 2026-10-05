class_name PlinkoLogic
extends StationLogicBase
## A Plinko board with standing drop spots (§2.5). The server decides the landing slot first
## (weighted per risk row, luck-rerolled by multiplier); the physical chip is only steered to it.

const RISKS: Array[StringName] = [&"low", &"medium", &"high"]

var spots: int = 2
## Players standing at the board.
var players: Array[int] = []
## Chips in flight: {player, stake, risk, slot, time_left, drop_id}.
var drops: Array[Dictionary] = []
## Seconds until each player may drop again.
var cooldowns: Dictionary[int, float] = {}

var _next_drop_id: int = 1


func _on_setup() -> void:
	game_id = &"plinko"


func can_join(p: int) -> bool:
	return p in players or players.size() < spots


func join(p: int) -> Dictionary:
	if p in players:
		return OK_RESULT
	if players.size() >= spots:
		return fail(&"seat_taken")
	players.append(p)
	return OK_RESULT


func leave(p: int) -> void:
	players.erase(p)


## Allowed bet sizes after the limits multiplier.
func bet_sizes() -> Array[int]:
	var out: Array[int] = []
	for s: int in balance.plinko_bet_sizes:
		out.append(scaled(s))
	return out


func place_bet(p: int, bet: Dictionary) -> Dictionary:
	if not p in players:
		return fail(&"not_seated")
	if cooldowns.get(p, 0.0) > 0.0:
		return fail(&"cooldown")
	var risk: StringName = StringName(bet.get("risk", "low"))
	if not risk in RISKS:
		return fail(&"invalid_risk")
	var amount: int = int(bet.get("amount", 0))
	if not amount in bet_sizes():
		return fail(&"invalid_amount")
	if not _take_stake(p, amount):
		return fail(&"insufficient_funds")
	if jackpot != null:
		jackpot.feed(amount)
	var mults: PackedFloat32Array = balance.plinko_multipliers(risk)
	var weights: PackedInt32Array = balance.plinko_weights(risk)
	var lk: int = modifiers.get_luck(p, game_id)
	var d: LuckRng.Draw = luck.draw(lk, func() -> int: return rng.weighted_index(Array(weights)), func(s: int) -> float: return mults[s])
	var drop: Dictionary = {"drop_id": _next_drop_id, "player": p, "stake": amount, "risk": risk, "slot": int(d.value), "time_left": balance.plinko_flight_time}
	_next_drop_id += 1
	drops.append(drop)
	cooldowns[p] = balance.plinko_drop_cooldown
	events.append(GameEvents.bet_placed(p, station_id, amount, {"game": game_id, "risk": risk}))
	# The slot is public: clients need it to replay the server's steered path.
	events.append(GameEvents.make(&"plinko_dropped", {"station": station_id, "player": p, "drop_id": drop["drop_id"], "risk": risk, "slot": drop["slot"]}))
	if d.luck_changed:
		events.append(GameEvents.luck_flourish(p, station_id, &"lucky" if lk > 0 else &"jinxed"))
	return OK_RESULT


func tick(delta: float) -> void:
	for p: int in cooldowns.keys():
		cooldowns[p] = maxf(cooldowns[p] - delta, 0.0)
	for drop: Dictionary in drops.duplicate():
		drop["time_left"] = float(drop["time_left"]) - delta
		if drop["time_left"] <= 0.0:
			_land(drop)


func round_seconds() -> float:
	return balance.plinko_flight_time


func has_stake(p: int) -> bool:
	return drops.any(func(d: Dictionary) -> bool: return int(d.get("player", -1)) == p)


func auto_resolve() -> void:
	for drop: Dictionary in drops.duplicate():
		_land(drop)


func get_public_state() -> Dictionary:
	var flying: Array = []
	for d: Dictionary in drops:
		flying.append({"drop_id": d["drop_id"], "player": d["player"], "risk": d["risk"], "slot": d["slot"]})
	return {"game": game_id, "players": players.duplicate(), "drops": flying}


func _land(drop: Dictionary) -> void:
	drops.erase(drop)
	var p: int = drop["player"]
	var stake: int = drop["stake"]
	var risk: StringName = drop["risk"]
	var slot: int = drop["slot"]
	var mult: float = balance.plinko_multipliers(risk)[slot]
	var base_return: int = int(floor(stake * mult + 0.000001))
	_settle(p, stake, base_return, {"risk": risk, "slot": slot, "multiplier_base": mult, "drop_id": drop["drop_id"]})
	modifiers.consume_round(p, game_id)
	var edge: bool = slot == 0 or slot == balance.plinko_mult_high.size() - 1
	if jackpot != null and risk == &"high" and edge and rng.chance(balance.plinko_edge_jackpot_chance):
		var won: int = jackpot.award(economy, p, station_id, limits_multiplier)
		events.append(GameEvents.make(&"jackpot_won", {"player": p, "station": station_id, "amount": won}))


## Exact RTP of a risk row at neutral luck.
static func exact_rtp(cfg: BalanceConfig, risk: StringName) -> float:
	var w: PackedInt32Array = cfg.plinko_weights(risk)
	var m: PackedFloat32Array = cfg.plinko_multipliers(risk)
	var tw: float = 0.0
	var r: float = 0.0
	for i: int in w.size():
		tw += w[i]
		r += w[i] * m[i]
	return r / tw
