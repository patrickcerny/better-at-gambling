class_name GameDefinition
extends Resource
## Registers a casino game: logic script + station/UI scenes (§5 extensibility contract).

@export var id: StringName
@export var display_name: String = ""
@export_multiline var rules_text: String = ""
@export var logic_script: Script
@export var station_scene: PackedScene
@export var ui_scene: PackedScene
@export var rug_color: Color = Color.WHITE
