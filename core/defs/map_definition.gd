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
