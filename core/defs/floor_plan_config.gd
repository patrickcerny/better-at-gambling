class_name FloorPlanConfig
extends Resource
## Tuning for the per-round casino floor (docs/FLOOR_PLAN.md, `FloorPlan`). Patrick's rules
## (0.9.10): every spot is redrawn at every casino round start in online and host-on-PC matches,
## nothing is guaranteed, Practice keeps the full floor.

## Which matches draw a random floor: online rooms (dedicated and host-on-PC both run a room
## server) and Practice. Practice keeps the full floor (every spot with its usual game).
@export var draw_in_rooms: bool = true
@export var draw_in_practice: bool = false
## At least this share of the spots in each area (casino floor, VIP lounge) has a game, so the
## floor is never empty or silly. The rest may be closed (velvet rope or a plant).
@export_range(0.0, 1.0) var min_filled: float = 0.6
## Chance that a spot is closed tonight before the minimum above tops the floor back up.
@export_range(0.0, 1.0) var empty_chance: float = 0.15
## Soft cap: at most this many tables of one game per area (0 = no cap). Only broken when the
## minimum fill can't be reached otherwise.
@export var max_per_type: int = 2
## Footprints the cap above applies to (slot machines come in rows, so not to cabinets).
@export var capped_footprints: Array[StringName] = [&"table"]
## Draw weight of a game on a spot of its size. Every registered game that isn't `fixed` is in
## the pool with `default_weight` unless `weights` (game id → weight) says otherwise; 0 = never.
@export var default_weight: float = 1.0
@export var weights: Dictionary = {}
## Walkway kept between two drawn tables, metres (a game only goes on a spot where it fits the
## room and keeps this gap to its neighbours: `FloorGeometry`; chairs are already in the rects, so
## this is the space between two chairs. 0.35 is the tightest pair on the full floor: craps and Hi-Lo).
@export var gap: float = 0.35


## Draw weight of a game.
func weight_of(game: StringName) -> float:
	return maxf(float(weights.get(game, default_weight)), 0.0)
