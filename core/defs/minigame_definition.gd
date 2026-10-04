class_name MinigameDefinition
extends Resource
## Registers a minigame (§2.9).

@export var id: StringName
@export var display_name: String = ""
@export var scene: PackedScene
@export var weight: float = 1.0
@export var params: Dictionary = {}
