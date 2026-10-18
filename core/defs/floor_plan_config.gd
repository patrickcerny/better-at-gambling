class_name FloorPlanConfig
extends Resource
## The casino floor's layouts and their rotation (docs/FLOOR_PLAN.md, `FloorLayout`,
## `FloorRotation`). Patrick (0.9.11): "have x amounts of rearrangements of the room (tested,
## with a good usefull layout) and then rotate between these layouts", and no closed spots: a
## layout that can't be used is skipped and another one is put in.

## Which matches rotate the layouts: online rooms (dedicated and host-on-PC both run a room
## server) and Practice. Practice keeps the first layout (the full floor).
@export var rotate_in_rooms: bool = true
@export var rotate_in_practice: bool = false
## The layouts, in order. The first is the full floor: Practice, the menu panorama and
## `LuckyLounge.STATIONS` stand on it, and it is the fallback when no other layout can be used.
## Adding a layout is a new `data/floor_layouts/*.tres` listed here; nothing in code changes.
@export var layouts: Array[FloorLayout] = []
## Game id → weight; 0 takes a game off the floor, and every layout that needs it is skipped.
## Games not listed are on (weight 1).
@export var weights: Dictionary = {}
## Least space between two games of a layout, chair to chair, metres (`FloorGeometry`). Every
## layout is checked against it, and against the walkway check, before it is used.
@export var gap: float = 0.35


## Weight of a game (1 unless `weights` says otherwise; never negative).
func weight_of(game: StringName) -> float:
	return maxf(float(weights.get(game, 1.0)), 0.0)


## A layout by id (null when unknown).
func layout(id: StringName) -> FloorLayout:
	for l: FloorLayout in layouts:
		if l != null and l.id == id:
			return l
	return null


## Ids of the layouts in the rotation (enabled ones, in order).
func enabled_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for l: FloorLayout in layouts:
		if l != null and l.enabled:
			out.append(l.id)
	return out
