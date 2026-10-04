class_name MapDefinition
extends Resource
## Registers a map: scene plus the gameplay markers the server needs (§2.3).

@export var id: StringName
@export var display_name: String = ""
@export var scene: PackedScene
## Station id → game id, e.g. {&"bj_1": &"blackjack"}.
@export var stations: Dictionary = {}
@export var hot_table_candidates: Array[StringName] = []
