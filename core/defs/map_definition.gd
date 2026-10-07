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
## Spawn points in the entrance hall.
@export var spawn_points: Array[Vector3] = []
## Where players stand in the entrance hall at the lobby and after each minigame (REGROUP), one
## per player id (filled by the map scene; empty = `spawn_points`).
@export var lobby_spawns: Array[Vector3] = []
## Gift Shop counter (filled by the map scene; INF = no distance check, e.g. in tests).
@export var shop_position: Vector3 = Vector3.INF
## Max distance from a station's interaction point to sit down.
@export var interact_range: float = 3.5


## Entrance-hall spot for a player id (Vector3.INF when the map has none).
func lobby_spawn(player_id: int) -> Vector3:
	var list: Array[Vector3] = lobby_spawns if not lobby_spawns.is_empty() else spawn_points
	if list.is_empty():
		return Vector3.INF
	return list[posmod(player_id - 1, list.size())]
