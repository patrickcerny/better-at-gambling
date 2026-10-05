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
## Spawn points in the entrance hall.
@export var spawn_points: Array[Vector3] = []
## Gift Shop counter (filled by the map scene; INF = no distance check, e.g. in tests).
@export var shop_position: Vector3 = Vector3.INF
## Max distance from a station's interaction point to sit down.
@export var interact_range: float = 3.5
