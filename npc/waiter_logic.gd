class_name WaiterLogic
extends RefCounted
## Server side of the waiter NPC (M7): decides when he trips (now and then on his own, when a
## player bumps into him or shoves him) and owns the drink puddles he leaves. A puddle makes
## anyone who walks through it slip and fall for a moment, like a banana peel, but it never
## costs money and it stays wet until it dries. The body walking the route is a scene node
## (`Waiter`) on whatever process simulates the world; it reports where it is through `position`
## and stands still while `is_down`. Clients only see events (`waiter_tripped`, `puddle_slip`,
## `puddle_removed`) and the snapshot (`wire`).

## Chance per second of tripping over nothing while walking.
const TRIP_CHANCE_PER_SECOND: float = 1.0 / 40.0
## A standing player this close to him (centre to centre) bumps him over.
const BUMP_RADIUS: float = 0.95
## A shove reaches him within this range in front of the shover.
const SHOVE_RANGE: float = 2.2
## Seconds on the floor before he gets up with a fresh tray.
const DOWN_SECONDS: float = 3.5
## No new trip this long after getting up (nobody can chain-trip him).
const TRIP_COOLDOWN: float = 10.0
## Puddles dry after this long.
const PUDDLE_SECONDS: float = 20.0
const PUDDLE_RADIUS: float = 1.1
## How far ahead of him the tray lands.
const SPILL_AHEAD: float = 1.8
const MAX_PUDDLES: int = 3
## Slipping knocks you down this long; after getting up the same puddle leaves you alone briefly.
const SLIP_SECONDS: float = 1.3
const SLIP_GRACE: float = 2.0

var players: Dictionary
var rules: InteractionRules
var world: WorldQuery
var rng: SeededRng

## Where the waiter's body is (Vector3.INF until a world reports one: no body, no trips).
var position: Vector3 = Vector3.INF
var yaw: float = 0.0
var down_until: float = -INF
var trips: int = 0
## puddle id → {pos: Vector3, expires_at: float}
var puddles: Dictionary[int, Dictionary] = {}

var events: Array[Dictionary] = []
var _next_puddle: int = 1
var _calm_until: float = 0.0
var _slip_free_until: Dictionary[int, float] = {}
var _now: float = 0.0


func _init(p_players: Dictionary, p_rules: InteractionRules, p_world: WorldQuery, p_rng: SeededRng) -> void:
	players = p_players
	rules = p_rules
	world = p_world
	rng = p_rng


## On the floor (he stands still and has no tray).
func is_down(now: float) -> bool:
	return now < down_until


## Server step. Trips and slips happen only while the casino is open; puddles always dry.
func tick(now: float, casino_open: bool) -> void:
	_now = now
	_dry(now)
	if not casino_open:
		return
	_check_slips(now)
	if not position.is_finite() or is_down(now) or now < _calm_until:
		return
	var ids: Array = players.keys()
	ids.sort()
	for pid: int in ids:
		if _can_bump(pid, now):
			trip(now, &"bump", pid)
			return
	if rng.chance(TRIP_CHANCE_PER_SECOND * MatchServer.TICK):
		trip(now, &"clumsy", -1)


## A player's shove: trips him if he is in front of them and in reach. Returns true if it did.
func shove(player: int, aim: Vector3, now: float) -> bool:
	if not position.is_finite() or is_down(now) or now < _calm_until or not players.has(player):
		return false
	var origin: Vector3 = world.get_position(player)
	var to: Vector3 = position - origin
	to.y = 0.0
	var dir: Vector3 = Vector3(aim.x, 0.0, aim.z)
	dir = dir.normalized() if dir.length() > 0.01 else world.get_facing(player)
	if to.length() > SHOVE_RANGE or absf(position.y - origin.y) > 1.2 or (to.length() > 0.3 and dir.dot(to.normalized()) < 0.5):
		return false
	trip(now, &"shove", player)
	return true


## He goes down: the tray flies ahead of him and leaves a puddle there.
func trip(now: float, cause: StringName, player: int) -> void:
	if not position.is_finite():
		return
	trips += 1
	down_until = now + DOWN_SECONDS
	_calm_until = down_until + TRIP_COOLDOWN
	var fwd: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	var pos: Vector3 = position + fwd * SPILL_AHEAD
	pos.y = position.y
	if puddles.size() >= MAX_PUDDLES:
		var oldest: int = puddles.keys().min()
		puddles.erase(oldest)
		events.append(GameEvents.make(&"puddle_removed", {"puddle": oldest, "reason": &"mopped"}))
	var id: int = _next_puddle
	_next_puddle += 1
	puddles[id] = {"pos": pos, "expires_at": now + PUDDLE_SECONDS}
	events.append(GameEvents.make(&"waiter_tripped", {"cause": cause, "player": player, "pos": Serializer.vec3(position), "yaw": snappedf(yaw, 0.001), "puddle": id, "puddle_pos": Serializer.vec3(pos), "seconds": PUDDLE_SECONDS, "down": DOWN_SECONDS}))


## Everything wet is gone (new match, back to the lobby).
func reset() -> void:
	for id: int in puddles:
		events.append(GameEvents.make(&"puddle_removed", {"puddle": id, "reason": &"mopped"}))
	puddles.clear()
	down_until = -INF
	_calm_until = 0.0
	_slip_free_until.clear()


## Puddles for the join/reconnect snapshot.
func wire() -> Array:
	var out: Array = []
	for id: int in puddles:
		out.append({"puddle": id, "pos": Serializer.vec3(puddles[id]["pos"]), "seconds": snappedf(maxf(float(puddles[id]["expires_at"]) - _now, 0.0), 0.1)})
	return out


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	return out


func _dry(now: float) -> void:
	var ids: Array = puddles.keys()
	ids.sort()
	for id: int in ids:
		if now >= float(puddles[id]["expires_at"]):
			puddles.erase(id)
			events.append(GameEvents.make(&"puddle_removed", {"puddle": id, "reason": &"dried"}))


func _standing(pid: int, now: float) -> bool:
	var st: InteractionRules.Status = rules.status(pid)
	return not (st.away or st.seated or rules.is_knocked_down(pid, now) or world.is_airborne(pid))


func _can_bump(pid: int, now: float) -> bool:
	if not _standing(pid, now):
		return false
	var d: Vector3 = world.get_position(pid) - position
	return Vector2(d.x, d.z).length() <= BUMP_RADIUS and absf(d.y) < 1.2


func _check_slips(now: float) -> void:
	if puddles.is_empty():
		return
	var ids: Array = puddles.keys()
	ids.sort()
	var who: Array = players.keys()
	who.sort()
	for pid: int in who:
		if now < _slip_free_until.get(pid, -INF) or not _standing(pid, now) or now < rules.status(pid).protected_until:
			continue
		var p: Vector3 = world.get_position(pid)
		for id: int in ids:
			var d: Vector3 = p - Vector3(puddles[id]["pos"])
			if Vector2(d.x, d.z).length() <= PUDDLE_RADIUS and absf(d.y) < 1.2:
				_slip(pid, id, now)
				break


func _slip(pid: int, puddle: int, now: float) -> void:
	rules.status(pid).knocked_down_until = maxf(rules.status(pid).knocked_down_until, now + SLIP_SECONDS)
	_slip_free_until[pid] = now + SLIP_SECONDS + SLIP_GRACE
	events.append(GameEvents.make(&"puddle_slip", {"player": pid, "puddle": puddle, "pos": Serializer.vec3(world.get_position(pid))}))
	events.append(GameEvents.make(&"player_knocked_down", {"target": pid, "attacker": -1, "seconds": SLIP_SECONDS, "cause": &"puddle"}))
