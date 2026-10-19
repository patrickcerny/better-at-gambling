class_name MinigameStage
extends Node3D
## Client presentation of a minigame (§2.9): its own little set far from the casino floor, its
## own camera and a full-screen UI layer. The match scene creates it on `minigame_started`, feeds
## it every server event and frees it when the minigame is over. Everything it shows comes from
## events and snapshots; input goes out as intents.

## Where stages are built, well away from the casino geometry.
const STAGE_ORIGIN: Vector3 = Vector3(0, 0, 400)

var state: ClientMatchState
var local_id: int = -1
var camera: Camera3D
var ui: CanvasLayer
## Where the UI layer goes: the match scene points it outside the 3D world's sub viewport
## (`PixelView`) onto the window's canvas; null keeps it under the stage. The stage frees it either way.
var ui_host: Node = null


## Sets up for the minigame described by `start` (the `minigame_started` event) and, when joining
## late, the public state from the snapshot.
## The input mode the stage wants while it is up (the pause menu returns to it): a free cursor;
## walkable stages ask for WALK while their game runs.
func input_mode() -> InputRouter.Mode:
	return InputRouter.Mode.STAGE


func begin(p_state: ClientMatchState, p_local_id: int, start: Dictionary, snapshot_state: Dictionary) -> void:
	state = p_state
	local_id = p_local_id
	position = STAGE_ORIGIN
	ui = CanvasLayer.new()
	ui.name = "StageUI"
	ui.layer = 5
	(ui_host if ui_host != null else self).add_child(ui)
	_build(start)
	if not snapshot_state.is_empty():
		apply_state(snapshot_state)
	if camera != null:
		camera.make_current()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(ui) and ui.get_parent() != self:
		ui.queue_free()  # hosted outside the stage: goes with it


## Subclass: build the set and UI.
func _build(_start: Dictionary) -> void:
	pass


## Subclass: catch up from a snapshot.
func apply_state(_st: Dictionary) -> void:
	pass


## Subclass: a server event.
func on_event(_ev: Dictionary) -> void:
	pass


## Private data for the local player changed (e.g. our own answer).
func on_private(_priv: Dictionary) -> void:
	pass
