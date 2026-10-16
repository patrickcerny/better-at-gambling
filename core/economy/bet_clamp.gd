class_name BetClamp
extends RefCounted
## All-in rule shared by the server (StationManager) and the bet UIs (BetPanel), Patrick:
## "when you try to bet more than you currently have, just bet the max amount (all you have)".
##
## A bet is clamped to the table room (max bet, or what is left of a per-round total) and then to
## what the player can pay. It is only refused when even the table minimum does not fit:
## `below_min` (asked for less than the minimum), `above_max` (no room left for a minimum bet) or
## `insufficient_funds` (the balance is under the minimum; House Comp / Odd Jobs help then).


## `{amount, error, all_in}`: the stake to take (0 when refused), the refusal (&"" when accepted)
## and whether the balance cut the bet down (the bet is everything the player has).
## `available` is what the player can pay, `room` the most the table takes for this bet.
static func resolve(requested: int, available: int, min_bet: int, room: int) -> Dictionary:
	if requested < min_bet or requested <= 0:
		return {"amount": 0, "error": &"below_min", "all_in": false}
	if room < min_bet or room <= 0:
		return {"amount": 0, "error": &"above_max", "all_in": false}
	if available < min_bet or available <= 0:
		return {"amount": 0, "error": &"insufficient_funds", "all_in": false}
	var capped: int = mini(requested, room)
	var amount: int = mini(capped, available)
	return {"amount": amount, "error": &"", "all_in": amount < capped}


## The stake for `requested`, or 0 when the bet would be refused.
static func clamp_amount(requested: int, available: int, min_bet: int, room: int) -> int:
	return int(resolve(requested, available, min_bet, room)["amount"])


## Smallest and largest of fixed bet sizes, `Vector2i(-1, -1)` for none.
static func size_range(sizes: Array[int]) -> Vector2i:
	if sizes.is_empty():
		return Vector2i(-1, -1)
	var lo: int = sizes[0]
	var hi: int = sizes[0]
	for s: int in sizes:
		lo = mini(lo, s)
		hi = maxi(hi, s)
	return Vector2i(lo, hi)


## Fixed bet sizes (slots, Plinko): a listed size the player can't cover goes all-in, as long as
## the balance still covers the smallest size. A size that isn't listed is refused.
static func resolve_sized(requested: int, sizes: Array[int], available: int) -> Dictionary:
	if not requested in sizes:
		return {"amount": 0, "error": &"invalid_amount", "all_in": false}
	var r: Vector2i = size_range(sizes)
	return resolve(requested, available, r.x, r.y)
