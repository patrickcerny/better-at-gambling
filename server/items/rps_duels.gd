class_name RpsDuels
extends RefCounted
## Rock Paper Scissors wagers (item): the user challenges a player for a stake; the target has
## `ANSWER_TIME` s to accept (silence = decline), then both pick within `PICK_TIME` s (no pick = a
## random one). The loser pays the stake (as far as they can); one tie is replayed, a second tie
## calls it off. Money only moves between the two players.

const ANSWER_TIME: float = 6.0
const PICK_TIME: float = 6.0
## Stake tiers (share of the poorer player's money) and the bounds.
const STAKES: Array[float] = [0.05, 0.10, 0.15]
const MIN_STAKE: int = 10
const PICKS: Array[StringName] = [&"rock", &"paper", &"scissors"]

## duel id → {duel, a, b, stake, state: &"invite"|&"pick", deadline, picks: {player: int}, ties}
var duels: Dictionary[int, Dictionary] = {}
var economy: Economy
var rng: SeededRng
var events: Array[Dictionary] = []
var _next: int = 1


func _init(p_economy: Economy, p_rng: SeededRng) -> void:
	economy = p_economy
	rng = p_rng


## True if the player is in an open duel (one at a time).
func busy(player: int) -> bool:
	for d: Dictionary in duels.values():
		if int(d["a"]) == player or int(d["b"]) == player:
			return true
	return false


## Starting stake for tier 0–2: a share of the poorer player's money (at least MIN_STAKE).
func stake_for(a: int, b: int, tier: int) -> int:
	var poorer: int = mini(economy.balance(a), economy.balance(b))
	return maxi(int(floor(poorer * STAKES[clampi(tier, 0, STAKES.size() - 1)])), MIN_STAKE)


## Opens a challenge. Returns the duel id.
func challenge(a: int, b: int, tier: int, now: float) -> int:
	var id: int = _next
	_next += 1
	var stake: int = stake_for(a, b, tier)
	duels[id] = {"duel": id, "a": a, "b": b, "stake": stake, "state": &"invite", "deadline": now + ANSWER_TIME, "picks": {}, "ties": 0}
	events.append(GameEvents.make(&"rps_invite", {"duel": id, "from": a, "to": b, "stake": stake, "seconds": ANSWER_TIME}))
	return id


func answer(player: int, duel: int, accept: bool, now: float) -> Dictionary:
	var d: Dictionary = duels.get(duel, {})
	if d.is_empty() or int(d["b"]) != player or d["state"] != &"invite":
		return StationLogicBase.fail(&"no_duel")
	if not accept:
		_cancel(duel, &"declined")
		return StationLogicBase.OK_RESULT
	_start_round(d, now)
	return StationLogicBase.OK_RESULT


func pick(player: int, duel: int, choice: int, now: float) -> Dictionary:
	var d: Dictionary = duels.get(duel, {})
	if d.is_empty() or d["state"] != &"pick" or not (int(d["a"]) == player or int(d["b"]) == player):
		return StationLogicBase.fail(&"no_duel")
	if choice < 0 or choice >= PICKS.size():
		return StationLogicBase.fail(&"bad_value")
	if (d["picks"] as Dictionary).has(player):
		return StationLogicBase.fail(&"already_picked")
	d["picks"][player] = choice
	events.append(GameEvents.make(&"rps_picked", {"duel": duel, "player": player}))
	if (d["picks"] as Dictionary).size() == 2:
		_resolve(d, now)
	return StationLogicBase.OK_RESULT


## Timeouts; `bots` pick (and accept) on their own.
func tick(now: float, bots: Dictionary) -> void:
	for id: int in duels.keys():
		var d: Dictionary = duels.get(id, {})
		if d.is_empty():
			continue
		if d["state"] == &"invite":
			if bots.has(int(d["b"])):
				if rng.chance(0.7):
					_start_round(d, now)
				else:
					_cancel(id, &"declined")
			elif now >= float(d["deadline"]):
				_cancel(id, &"no_answer")
			continue
		for p: int in [int(d["a"]), int(d["b"])]:
			if bots.has(p) and not (d["picks"] as Dictionary).has(p):
				pick(p, id, rng.range_int(0, 2), now)
		if duels.has(id) and now >= float(d["deadline"]):
			for p: int in [int(d["a"]), int(d["b"])]:
				if not (d["picks"] as Dictionary).has(p):
					d["picks"][p] = rng.range_int(0, 2)
			_resolve(d, now)


## The casino closed: open duels are called off.
func cancel_all() -> void:
	for id: int in duels.keys():
		_cancel(id, &"closed")


## Winner of a vs b (0 = tie, 1 = a, 2 = b).
static func outcome(pick_a: int, pick_b: int) -> int:
	if pick_a == pick_b:
		return 0
	return 1 if (pick_a - pick_b + 3) % 3 == 1 else 2


func _start_round(d: Dictionary, now: float) -> void:
	d["state"] = &"pick"
	d["picks"] = {}
	d["deadline"] = now + PICK_TIME
	events.append(GameEvents.make(&"rps_start", {"duel": d["duel"], "a": d["a"], "b": d["b"], "stake": d["stake"], "seconds": PICK_TIME, "replay": int(d["ties"]) > 0}))


func _resolve(d: Dictionary, now: float) -> void:
	var a: int = d["a"]
	var b: int = d["b"]
	var pa: int = int(d["picks"][a])
	var pb: int = int(d["picks"][b])
	var o: int = outcome(pa, pb)
	if o == 0 and int(d["ties"]) == 0:
		d["ties"] = 1
		events.append(GameEvents.make(&"rps_result", {"duel": d["duel"], "a": a, "b": b, "pick_a": PICKS[pa], "pick_b": PICKS[pb], "winner": -1, "amount": 0, "replay": true}))
		_start_round(d, now)
		return
	var winner: int = -1
	var paid: int = 0
	if o != 0:
		winner = a if o == 1 else b
		var loser: int = b if o == 1 else a
		paid = economy.take_up_to(loser, int(d["stake"]), &"item_rps")
		if paid > 0:
			economy.apply(winner, paid, &"item_rps")
	duels.erase(int(d["duel"]))
	events.append(GameEvents.make(&"rps_result", {"duel": d["duel"], "a": a, "b": b, "pick_a": PICKS[pa], "pick_b": PICKS[pb], "winner": winner, "amount": paid, "replay": false}))


func _cancel(id: int, reason: StringName) -> void:
	var d: Dictionary = duels.get(id, {})
	if d.is_empty():
		return
	duels.erase(id)
	events.append(GameEvents.make(&"rps_cancelled", {"duel": id, "a": d["a"], "b": d["b"], "reason": reason}))


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	return out
