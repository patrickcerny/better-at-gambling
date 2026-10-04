class_name SeededRng
extends RefCounted
## Deterministic RNG wrapper. Every random decision in the simulation goes through one of these,
## so a match replays exactly from its seed.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value


## Current seed (as set at construction or by `reseed`).
func get_seed() -> int:
	return _rng.seed


## Restarts the sequence from a new seed.
func reseed(seed_value: int) -> void:
	_rng.seed = seed_value


## Uniform integer in [from, to] inclusive.
func range_int(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


## Uniform float in [0, 1).
func unit() -> float:
	return _rng.randf()


## Uniform float in [from, to].
func range_float(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


## True with probability `p` (clamped to [0, 1]).
func chance(p: float) -> bool:
	if p <= 0.0:
		return false
	if p >= 1.0:
		return true
	return _rng.randf() < p


## Index into `weights` chosen proportionally to its weight. Returns -1 if all weights are <= 0.
func weighted_index(weights: Array) -> int:
	var total: float = 0.0
	for w: Variant in weights:
		total += maxf(float(w), 0.0)
	if total <= 0.0:
		return -1
	var roll: float = _rng.randf() * total
	for i: int in weights.size():
		var w: float = maxf(float(weights[i]), 0.0)
		if roll < w:
			return i
		roll -= w
	return weights.size() - 1


## In-place Fisher–Yates shuffle.
func shuffle(arr: Array) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## A child RNG with a seed derived from this one, so subsystems don't disturb each other's streams.
func fork() -> SeededRng:
	return SeededRng.new(int(_rng.randi()) << 31 ^ int(_rng.randi()))
