class_name InteractionResolver
extends RefCounted
## Server-side resolution of grab / release / throw / shove / shake / break-free requests using
## server-side positions (§2.4.1, §2.20). Physics in the world only animates what is decided here.

## Reach the client aims with; the server allows `InteractionRules.LAG_SLACK` more for a target
## the client picked, since it saw everyone a little in the past.
const GRAB_RANGE: float = InteractionRules.REACH
const SHOVE_RANGE: float = InteractionRules.REACH
const SHAKE_RANGE: float = 2.5
const THROW_SPEED: float = 6.0
const THROW_UP: float = 3.0
const SHOVE_KNOCKBACK: float = 2.0
## How far behind a shoved player we look for a wall/table/fountain to slam them into (about the
## distance the knockback slides them).
const SLAM_DISTANCE: float = 1.5

var rules: InteractionRules
var world: WorldQuery
var economy: Economy
var pickups: PickupSystem
var rng: SeededRng
var cfg: BalanceConfig
## holder → held player
var holding: Dictionary[int, int] = {}
## held → {holder, since, presses}
var held_by: Dictionary[int, Dictionary] = {}
## Recent offences for guards: [{attacker, victim, time, kind}].
var offences: Array[Dictionary] = []
var events: Array[Dictionary] = []
var limits_multiplier: float = 1.0
## Callable(target: int, attacker: int, now: float) -> bool: true cancels a knockout (Bodyguard).
var ko_shield: Callable


func _init(p_rules: InteractionRules, p_world: WorldQuery, p_economy: Economy, p_pickups: PickupSystem, p_rng: SeededRng) -> void:
	rules = p_rules
	world = p_world
	economy = p_economy
	pickups = p_pickups
	rng = p_rng
	cfg = rules.cfg


## True if `holder` currently holds someone.
func is_holding(holder: int) -> bool:
	return holding.has(holder)


## True if `player` is being held.
func is_held(player: int) -> bool:
	return held_by.has(player)


## Grab request. Target must be standing (not seated), in range, not already held.
func grab(holder: int, target: int, now: float) -> Dictionary:
	if holder == target or holding.has(holder) or held_by.has(target):
		return StationLogicBase.fail(&"invalid_target")
	# The client already checked its reach cone; the server only checks distance, with lag slack.
	if not world.positions.has(target) or world.distance(holder, target) > GRAB_RANGE + InteractionRules.LAG_SLACK:
		return StationLogicBase.fail(&"out_of_range")
	var why: StringName = rules.immunity_reason(target, now)
	if why != &"":
		return StationLogicBase.fail(why)
	if held_by.has(holder):
		return StationLogicBase.fail(&"held")
	holding[holder] = target
	held_by[target] = {"holder": holder, "since": now, "presses": 0}
	events.append(GameEvents.make(&"player_grabbed", {"attacker": holder, "target": target}))
	return StationLogicBase.OK_RESULT


## Release request. With `throw`, the target is launched along `aim` (horizontal) and ragdolls.
func release(holder: int, throw: bool, aim: Vector3, now: float) -> Dictionary:
	if not holding.has(holder):
		return StationLogicBase.fail(&"not_holding")
	var target: int = holding[holder]
	_end_hold(holder, target)
	if throw:
		var dir: Vector3 = Vector3(aim.x, 0.0, aim.z)
		if dir.length() < 0.01:
			dir = world.get_facing(holder)
		var velocity: Vector3 = dir.normalized() * THROW_SPEED + Vector3.UP * THROW_UP
		events.append(GameEvents.make(&"player_thrown", {"attacker": holder, "target": target, "velocity": Serializer.vec3(velocity)}))
		_offence(holder, target, now, &"throw")
	else:
		events.append(GameEvents.make(&"player_released", {"attacker": holder, "target": target}))
	return StationLogicBase.OK_RESULT


## Victim mashes jump: 6 presses or 3 s frees them.
func break_free(player: int, now: float) -> Dictionary:
	if not held_by.has(player):
		return StationLogicBase.fail(&"not_held")
	var h: Dictionary = held_by[player]
	h["presses"] = int(h["presses"]) + 1
	if int(h["presses"]) >= cfg.grab_break_presses or now - float(h["since"]) >= cfg.grab_max_time:
		var holder: int = h["holder"]
		_end_hold(holder, player)
		events.append(GameEvents.make(&"player_broke_free", {"target": player, "attacker": holder}))
	return StationLogicBase.OK_RESULT


## Shove request: the player the client swung at (`hint`, if still in reach give or take lag), else
## the best touchable player in the reach cone of `aim`.
func shove(attacker: int, aim: Vector3, now: float, spring_glove: bool = false, hint: int = -1) -> Dictionary:
	var target: int = _shove_target(attacker, aim, hint, now)
	if target < 0:
		return StationLogicBase.fail(&"no_target")
	var res: Dictionary = rules.shove(attacker, target, now, world.is_airborne(target), spring_glove)
	if not res["ok"]:
		return StationLogicBase.fail(res["error"])
	if res["knockout"] and ko_shield.is_valid() and ko_shield.call(target, attacker, now):
		rules.cancel_knockout(target, now)
		res["knockout"] = false
		res["knockdown"] = true
	var dir: Vector3 = (world.get_position(target) - world.get_position(attacker))
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else world.get_facing(attacker)
	var cause: StringName = &"shove"
	if not res["knockout"] and not res["knockdown"]:
		# Shoved into a wall, a table or the fountain: down they go.
		var at: Vector3 = world.get_position(target)
		if world.obstacle_between(at, at + dir * SLAM_DISTANCE) and rules.knock_down(target, now):
			res["knockdown"] = true
			cause = &"wall"
	events.append(GameEvents.make(&"player_shoved", {"attacker": attacker, "target": target, "dir": Serializer.vec3(dir), "knockback": SHOVE_KNOCKBACK, "spring_glove": spring_glove}))
	if held_by.has(target):
		var holder: int = int(held_by[target]["holder"])
		_end_hold(holder, target)
		events.append(GameEvents.make(&"player_released", {"attacker": holder, "target": target}))
	if res["knockout"]:
		_knocked_out(target, attacker, now, &"shoves")
	elif res["knockdown"]:
		events.append(GameEvents.make(&"player_knocked_down", {"target": target, "attacker": attacker, "cause": cause}))
	return {"ok": true, "error": &"", "target": target}


## The world reports a hard landing / wall hit / fall / stool hit that knocks a player out.
func report_knockout(target: int, attacker: int, now: float, cause: StringName) -> bool:
	if rules.status(target).away:
		return false
	if rules.is_knocked_out(target, now) or now < rules.status(target).ko_immune_until:
		return false
	if ko_shield.is_valid() and ko_shield.call(target, attacker, now):
		return false
	var money: int = economy.balance(target)
	if not rules.knock_out(target, now, money, limits_multiplier):
		return false
	if held_by.has(target):
		_end_hold(int(held_by[target]["holder"]), target)
	if holding.has(target):
		_end_hold(target, holding[target])
	events.append(GameEvents.make(&"player_knocked_out", {"target": target, "attacker": attacker, "cause": cause}))
	if attacker >= 0 and attacker != target:
		_offence(attacker, target, now, &"knockout")
	return true


## Shake request: attacker must be within range of a knocked-out target it is grabbing or next to.
func shake(attacker: int, now: float) -> Dictionary:
	var target: int = holding.get(attacker, -1)
	if target < 0:
		target = _nearest_knocked_out(attacker, now, SHAKE_RANGE)
	if target < 0:
		return StationLogicBase.fail(&"no_target")
	var money: int = economy.balance(target)
	var res: Dictionary = rules.shake(attacker, target, now, money, limits_multiplier)
	if not res["ok"]:
		return StationLogicBase.fail(res["error"])
	var amount: int = res["amount"]
	var ids: Array[int] = pickups.drop_from(target, amount, world.get_position(target), 3, rng, &"shaken_out", now, 1.5)
	events.append(GameEvents.make(&"chips_shaken_out", {"attacker": attacker, "target": target, "amount": amount, "piles": ids}))
	_offence(attacker, target, now, &"shake")
	return StationLogicBase.OK_RESULT


## Offences (knockouts, shakes, throws) in the last `window` seconds, newest first.
func recent_offences(now: float, window: float = 3.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o: Dictionary in offences:
		if now - float(o["time"]) <= window:
			out.append(o)
	out.reverse()
	return out


## A guard caught the attacker: thrown out through the revolving door (no money loss).
func report_thrown_out(attacker: int, guard: StringName, now: float) -> void:
	if holding.has(attacker):
		_end_hold(attacker, holding[attacker])
	if held_by.has(attacker):
		_end_hold(int(held_by[attacker]["holder"]), attacker)
	offences = offences.filter(func(o: Dictionary) -> bool: return int(o["attacker"]) != attacker)
	events.append(GameEvents.make(&"player_thrown_out", {"target": attacker, "guard": guard}))
	rules.protect(attacker, now + 4.0)


## Regroup after the rewards (Patrick's note #10): every hold ends (`player_released`), knockouts and
## knockdowns are over and pending guard offences are forgotten. Everyone gets back up in the hall.
func regroup() -> void:
	for holder: int in holding.keys():
		var target: int = holding[holder]
		_end_hold(holder, target)
		events.append(GameEvents.make(&"player_released", {"attacker": holder, "target": target}))
	offences.clear()
	rules.clear_downs()


## Forgets offences older than 10 s and breaks holds that timed out.
func tick(now: float) -> void:
	offences = offences.filter(func(o: Dictionary) -> bool: return now - float(o["time"]) <= 10.0)
	for target: int in held_by.keys():
		var h: Dictionary = held_by[target]
		if now - float(h["since"]) >= cfg.grab_max_time:
			var holder: int = h["holder"]
			_end_hold(holder, target)
			events.append(GameEvents.make(&"player_broke_free", {"target": target, "attacker": holder}))


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	return out


func _knocked_out(target: int, attacker: int, now: float, cause: StringName) -> void:
	# rules.shove already set the knockout state; record money cap and emit.
	var t: InteractionRules.Status = rules.status(target)
	t.shake_cap_this_ko = rules.shake_cap(economy.balance(target), limits_multiplier)
	t.shaken_this_ko = 0
	if holding.has(target):
		_end_hold(target, holding[target])
	events.append(GameEvents.make(&"player_knocked_out", {"target": target, "attacker": attacker, "cause": cause}))
	_offence(attacker, target, now, &"knockout")


func _offence(attacker: int, victim: int, now: float, kind: StringName) -> void:
	offences.append({"attacker": attacker, "victim": victim, "time": now, "kind": kind})


func _end_hold(holder: int, target: int) -> void:
	holding.erase(holder)
	held_by.erase(target)


func _shove_target(attacker: int, aim: Vector3, hint: int, now: float) -> int:
	var origin: Vector3 = world.get_position(attacker)
	var dir: Vector3 = Vector3(aim.x, 0.0, aim.z)
	dir = dir.normalized() if dir.length() > 0.01 else world.get_facing(attacker)
	if hint >= 0 and hint != attacker and world.positions.has(hint):
		if InteractionRules.reach_score(origin, dir, world.get_position(hint), SHOVE_RANGE + InteractionRules.LAG_SLACK) < INF:
			return hint
	# Prefer someone who can actually be shoved: a seated player next to you shouldn't eat the
	# swing meant for the one standing behind them. If only untouchables are in reach, pick one so
	# the rejection says why (seated, protected).
	var touchable: Dictionary = {}
	var anyone: Dictionary = {}
	for p: int in world.positions:
		if p == attacker:
			continue
		anyone[p] = world.positions[p]
		if rules.immunity_reason(p, now) == &"":
			touchable[p] = world.positions[p]
	var best: int = InteractionRules.pick_in_reach(origin, dir, touchable, attacker, SHOVE_RANGE)
	if best < 0:
		best = InteractionRules.pick_in_reach(origin, dir, anyone, attacker, SHOVE_RANGE)
	return best


func _nearest_knocked_out(attacker: int, now: float, range_m: float) -> int:
	var best: int = -1
	var best_d: float = INF
	for p: int in world.positions:
		if p == attacker or not rules.is_knocked_out(p, now):
			continue
		var d: float = world.distance(attacker, p)
		if d <= range_m and d < best_d:
			best_d = d
			best = p
	return best
