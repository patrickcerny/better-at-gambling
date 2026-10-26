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
## Its size class on the casino floor (docs/FLOOR_PLAN.md): &"table" (the default), &"cabinet",
## &"big", &"kiosk", or &"fixed": the game keeps a place of its own and is never on the drawn
## floor (the horse race in the Race Hall). The floor generator (`FloorGenerator`) puts `table`
## games in the pit rows, `cabinet` games in wall banks and islands, and `big` and `kiosk` games in
## the wall and island slots that take them (`FloorSite`), so a new game needs no layout edits.
@export var floor_footprint: StringName = &"table"
