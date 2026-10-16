class_name MapDefinition
extends Resource
## Registers a map: scene plus the gameplay markers the server needs (§2.3).

@export var id: StringName
@export var display_name: String = ""
@export var scene: PackedScene
## Station id → game id, e.g. {&"bj_1": &"blackjack"}.
@export var stations: Dictionary = {}
@export var hot_table_candidates: Array[StringName] = []
## Station id → world position of its interaction point (filled by the map scene at load).
@export var station_positions: Dictionary = {}
## Station id → seat world positions in seat order (filled by the map scene at load). Seated
## players are moved here server-side so reach checks see them at the table.
@export var station_seats: Dictionary = {}
## Station id → the table's rotation about y in radians (dealers stand in the table's frame).
@export var station_yaws: Dictionary = {}
## Spawn points in the entrance hall.
@export var spawn_points: Array[Vector3] = []
## Where players stand in the entrance hall at the lobby and after each minigame (REGROUP), one
## per player id (filled by the map scene; empty = `spawn_points`).
@export var lobby_spawns: Array[Vector3] = []
## Gift Shop counter (filled by the map scene; INF = no distance check, e.g. in tests).
@export var shop_position: Vector3 = Vector3.INF
## Where players stand at the Odd Jobs cabinet (filled by the map scene; INF = no distance check).
@export var odd_jobs_position: Vector3 = Vector3.INF
## Max distance from a station's interaction point to sit down.
@export var interact_range: float = 3.5
## The line of the lobby doors between the start room (z above it) and the casino (z below it):
## while an online room waits in LOBBY, the server sends anyone found below it back to their
## start-room spot (filled by the map scene; INF = no doors, no check).
@export var lobby_door_z: float = INF
## The jail cell's inner volume (filled by the map scene; empty = no physical jail: jail is only
## a timer and a fine, nobody is moved).
@export var jail_area: AABB = AABB()
## Spots inside the cell and where players come out when their time is up, cycled by player id.
@export var jail_spots: Array[Vector3] = []
@export var jail_exits: Array[Vector3] = []
## The waiting room's play-money stations, station id → game id (filled by the map scene; empty = no
## waiting room). Never in `stations`: they run on the server's separate fun ledger (`FunRoom`).
@export var fun_stations: Dictionary = {}
## The waiting room's inner volume (filled by the map scene).
@export var waiting_area: AABB = AABB()
## The casino floor's spots for the per-round floor plan (docs/FLOOR_PLAN.md; filled by the map
## scene, empty = a fixed floor that never changes): [{id, footprint, vip, default, pos, yaw}] in
## map order, `default` being the game the spot has on the full floor, `yaw` in radians.
@export var floor_anchors: Array = []
## Game id → station id stem (slots → slot) so the drawn stations keep the usual names.
@export var floor_prefixes: Dictionary = {}
## Room for the draw (`FloorGeometry`): game id → its floor in its own frame (Rect2 over x, z;
## measured by the map scene, empty = no geometry check), world rects tables may stand in, and
## world rects they keep clear of.
@export var floor_rects: Dictionary = {}
@export var floor_areas: Array = []
@export var floor_keep_out: Array = []
## For the walkway check (measured by the map scene): game id → its chairs (Vector2 x, z) and
## what of it the navmesh walks round (Rect2s), both in its own frame; footprint → a closed spot's
## dressing the same way; everything else on the map the navmesh walks round (world Rect2s);
## where people come into each area, and points the guards and waiter walk to.
@export var floor_seats: Dictionary = {}
@export var floor_obstacles: Dictionary = {}
@export var floor_closed_obstacles: Dictionary = {}
@export var floor_blockers: Array = []
@export var floor_entries: Array = []
@export var floor_walk_points: Array = []


## Entrance-hall spot for a player id (Vector3.INF when the map has none).
func lobby_spawn(player_id: int) -> Vector3:
	var list: Array[Vector3] = lobby_spawns if not lobby_spawns.is_empty() else spawn_points
	if list.is_empty():
		return Vector3.INF
	return list[posmod(player_id - 1, list.size())]


## True when `pos` is on the casino side of the (shut) lobby doors.
func past_lobby_doors(pos: Vector3) -> bool:
	return lobby_door_z != INF and pos.z < lobby_door_z


## True when the map has a jail cell to lock people in.
func has_jail() -> bool:
	return jail_area.has_volume() and not jail_spots.is_empty()


## True when `pos` (feet) is inside the jail cell.
func in_jail(pos: Vector3) -> bool:
	var a: AABB = jail_area
	return pos.x >= a.position.x and pos.x <= a.end.x and pos.z >= a.position.z and pos.z <= a.end.z and pos.y >= a.position.y and pos.y <= a.end.y


## The nearest point to `pos` inside the cell, `margin` metres clear of the bars and walls.
func clamp_to_jail(pos: Vector3, margin: float = 0.35) -> Vector3:
	var a: AABB = jail_area
	return Vector3(clampf(pos.x, a.position.x + margin, a.end.x - margin), clampf(pos.y, 0.0, a.end.y - 1.0), clampf(pos.z, a.position.z + margin, a.end.z - margin))


## Where a player is locked up (one of the cell's spots).
func jail_spot(player_id: int) -> Vector3:
	return jail_spots[posmod(player_id - 1, jail_spots.size())] if not jail_spots.is_empty() else Vector3.INF


## Where a player comes out when their time is up (Vector3.INF when the map has none).
func jail_exit(player_id: int) -> Vector3:
	return jail_exits[posmod(player_id - 1, jail_exits.size())] if not jail_exits.is_empty() else Vector3.INF


## True when the map has a waiting room with play-money stations.
func has_waiting_room() -> bool:
	return not fun_stations.is_empty() and waiting_area.has_volume()


## True when the map has spots for a per-round floor plan.
func has_floor_plan() -> bool:
	return not floor_anchors.is_empty()


## A floor spot by id ({} when unknown).
func floor_anchor(anchor_id: StringName) -> Dictionary:
	for a: Dictionary in floor_anchors:
		if a["id"] == anchor_id:
			return a
	return {}
