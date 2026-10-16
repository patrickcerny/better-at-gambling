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
## Where the game stands on the casino floor (docs/FLOOR_PLAN.md): &"table" (blackjack- or
## roulette-sized, the default), &"cabinet" (slot-machine-sized), &"big" (Plinko-sized) or
## &"fixed" (never drawn: it has its own place, like the horse race in the Race Hall). Each round
## the floor plan puts a game only on spots of its own size.
@export var floor_footprint: StringName = &"table"
