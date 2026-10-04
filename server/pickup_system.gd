class_name PickupSystem
extends RefCounted
## Dropped chip piles (§2.3): created by shakes, slips and robberies; anyone collects them by
## running over (the world reports contact); unclaimed piles expire after `lifetime`.

const DEFAULT_LIFETIME: float = 20.0

var economy: Economy
var lifetime: float
## pile id → {amount, pos, expires_at}
var piles: Dictionary[int, Dictionary] = {}
var events: Array[Dictionary] = []

var _next_id: int = 1


func _init(p_economy: Economy, p_lifetime: float = DEFAULT_LIFETIME) -> void:
	economy = p_economy
	lifetime = p_lifetime


## Takes `amount` from `victim` and scatters it as `count` piles around `origin`. Returns the pile ids.
func drop_from(victim: int, amount: int, origin: Vector3, count: int, rng: SeededRng, reason: StringName, now: float, radius: float = 1.5) -> Array[int]:
	var taken: int = economy.take_up_to(victim, amount, reason)
	if taken <= 0:
		return []
	return spawn(taken, origin, count, rng, now, radius, victim)


## Spawns piles summing exactly to `amount` (house money or already-deducted money).
func spawn(amount: int, origin: Vector3, count: int, rng: SeededRng, now: float, radius: float = 1.5, source: int = -1) -> Array[int]:
	count = clampi(count, 1, maxi(amount / 10, 1))
	var ids: Array[int] = []
	var left: int = amount
	for i: int in count:
		var part: int = left if i == count - 1 else amount / count
		left -= part
		var angle: float = rng.range_float(0.0, TAU)
		var dist: float = rng.range_float(0.3, radius)
		var pos: Vector3 = origin + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var id: int = _next_id
		_next_id += 1
		piles[id] = {"amount": part, "pos": pos, "expires_at": now + lifetime}
		ids.append(id)
		events.append(GameEvents.make(&"chips_dropped", {"pile": id, "amount": part, "pos": Serializer.vec3(pos), "source": source}))
	return ids


## A player touched a pile: pays it out. False if the pile is gone.
func collect(player: int, pile_id: int) -> bool:
	if not piles.has(pile_id) or not economy.has_player(player):
		return false
	var pile: Dictionary = piles[pile_id]
	piles.erase(pile_id)
	economy.apply(player, int(pile["amount"]), &"chips_picked_up")
	events.append(GameEvents.make(&"chips_collected", {"pile": pile_id, "player": player, "amount": pile["amount"]}))
	return true


## Expires old piles; the money is logged as lost to the house.
func tick(now: float) -> void:
	for id: int in piles.keys():
		if now >= float(piles[id]["expires_at"]):
			var amount: int = piles[id]["amount"]
			piles.erase(id)
			events.append(GameEvents.make(&"pickup_expired", {"pile": id, "amount": amount}))


## Total money lying on the floor.
func total_on_floor() -> int:
	var sum: int = 0
	for id: int in piles:
		sum += int(piles[id]["amount"])
	return sum


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	return out
