class_name FloorPlanConfig
extends Resource
## The casino floor of each round (docs/FLOOR_PLAN.md, `FloorGenerator`, `FloorRotation`).
## Patrick (0.9.16): "Group the tablegames and make random layouts." Every round the server draws a
## fresh floor from the match seed: the table games grouped in the pit, the slot banks, Plinko and
## the kiosks along the walls; a draw that fails the checks is drawn again, and the canonical draw
## (the full floor) stands when none passes.

## Which matches draw a new floor every round: online rooms (dedicated and host-on-PC both run a
## room server) and Practice. Practice keeps the full floor.
@export var rotate_in_rooms: bool = true
@export var rotate_in_practice: bool = false
## How the generator fills a round's floor: extra copies of the table games beyond one of each
## (min, max; picked by `weights`), and for the canonical draw (the full floor) the extra copies
## by name; slot machines per cabinet game (min, max) in banks of (min, max); copies of each big
## game (Plinko; the canonical draw takes the max); and how many draws a round tries before it
## falls back to the canonical draw.
@export var extra_tables: Vector2i = Vector2i(1, 3)
@export var full_extras: Array[StringName] = []
@export var cabinets: Vector2i = Vector2i(9, 15)
@export var bank: Vector2i = Vector2i(2, 4)
@export var bigs: Vector2i = Vector2i(1, 2)
@export var draws: int = 6
## Game id → weight; 0 takes a game off the floor (the round's draws leave it out). Games not
## listed are on (weight 1). Practice's full floor has every game.
@export var weights: Dictionary = {}
## Least space between two games, chair to chair, metres (`FloorGeometry`). Every draw is checked
## against it, and against the walkway checks, before it is used.
@export var gap: float = 0.35


## Weight of a game (1 unless `weights` says otherwise; never negative).
func weight_of(game: StringName) -> float:
	return maxf(float(weights.get(game, 1.0)), 0.0)
