class_name FloorLayout
extends Resource
## One hand-made arrangement of the casino floor (docs/FLOOR_PLAN.md): which games stand where and
## which way they face. The room itself (walls, doors, jail, shop, Odd Jobs, Race Hall, VIP lounge)
## never changes; a layout only moves and turns the games. The match rotates through the layouts
## in `FloorPlanConfig.layouts`, the first of which is the full floor (Practice, the menu).

## Stable id (the wire and the logs name the layout by it) and the name people read.
@export var id: StringName = &""
@export var title: String = ""
## False takes the layout out of the rotation (it stays loadable for tests and renders).
@export var enabled: bool = true
## Station id → [game id, position (Vector3, floor level), yaw degrees], like `LuckyLounge.STATIONS`.
## Yaw 0 puts the players on the south side (+z) and the dealer or cabinet north; 90 puts the
## players east, -90 west, 180 north.
@export var stations: Dictionary = {}


## The games this layout needs (each once, sorted).
func games() -> Array[StringName]:
	var out: Array[StringName] = []
	for sid: Variant in stations:
		var g: StringName = StringName((stations[sid] as Array)[0])
		if not g in out:
			out.append(g)
	out.sort()
	return out


## The layout's stations in wire form (`FloorPlan`): station id → [game, [x, y, z], yaw degrees].
func wire_stations() -> Dictionary:
	var out: Dictionary = {}
	for sid: Variant in stations:
		var row: Array = stations[sid]
		out[StringName(sid)] = FloorPlan.entry(StringName(row[0]), row[1] as Vector3, float(row[2]))
	return out
