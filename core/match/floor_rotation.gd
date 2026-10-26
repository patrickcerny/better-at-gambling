class_name FloorRotation
extends RefCounted
## Which floor comes next (docs/FLOOR_PLAN.md): every casino round a fresh floor is drawn
## (`FloorGenerator.draw`), and this hands out the seeds of those draws, one per round, from the
## server's floor stream (its own seed, so the floor never shifts the match's other random draws
## and a match replays exactly). Never the same seed twice in a row. A generated floor's id names
## its seed (`floor_123`), so any round's floor can be put in again with `--floor floor_123`.

## Seeds stay below this (six digits read well in logs and on the command line).
const SEED_RANGE: int = 1000000

var _rng: SeededRng
var _last: int = -1


func _init(rng: SeededRng) -> void:
	_rng = rng


## The seed of the next round's floor.
func next_seed() -> int:
	var s: int = _rng.range_int(0, SEED_RANGE - 1)
	if s == _last:
		s = (s + 1) % SEED_RANGE
	_last = s
	return s


## The seed handed out last (-1 before the first).
func current() -> int:
	return _last
