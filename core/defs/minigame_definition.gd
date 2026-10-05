class_name MinigameDefinition
extends Resource
## Registers a minigame (§2.9): server rules (a `MinigameLogicBase`) plus the client stage that
## shows it (a Node3D script built in code, or a scene).

@export var id: StringName
@export var display_name: String = ""
@export_multiline var rules_text: String = ""
@export var logic_script: Script
## Client presentation: a script extending `MinigameStage` (preferred) or a scene whose root does.
@export var stage_script: Script
@export var scene: PackedScene
@export var weight: float = 1.0
@export var params: Dictionary = {}
