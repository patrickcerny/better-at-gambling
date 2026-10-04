class_name InputRouter
extends Node
## Turns raw input into gameplay signals and owns the input mode (walking, seated at a station,
## in a menu, emote wheel open). Mouse capture follows the mode. Movement/look vectors are polled
## by the avatar; discrete actions arrive as signals. Keyboard+mouse and gamepad are equivalent.

signal look(relative: Vector2)
signal interact
signal leave_station
signal grab_pressed
signal grab_released
signal shove
signal shake
signal jump
signal toggle_camera
signal emote_wheel_toggled(open: bool)
signal item_used(slot: int)
signal leaderboard_toggled(shown: bool)
signal pause
signal ping

enum Mode { WALK, SEATED, MENU, EMOTE }

const STICK_LOOK_SPEED: float = 3.2

var mode: Mode = Mode.WALK
## True while the process has focus and should capture the mouse in WALK mode.
var capture_mouse: bool = true
## Mouse look sensitivity (radians per pixel).
var mouse_sensitivity: float = 0.0025
var invert_y: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_mode(Mode.WALK)


## Switches input mode and the mouse capture that goes with it.
func set_mode(m: Mode) -> void:
	mode = m
	if DisplayServer.get_name() == "headless":
		return
	match m:
		Mode.WALK:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture_mouse else Input.MOUSE_MODE_VISIBLE
		_:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## WASD / left stick, as a 2D vector (x right, y forward) in [-1, 1].
func move_vector() -> Vector2:
	if mode != Mode.WALK:
		return Vector2.ZERO
	var v: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	return Vector2(v.x, -v.y)


## Right stick look, radians per second.
func stick_look() -> Vector2:
	if mode == Mode.MENU:
		return Vector2.ZERO
	var v: Vector2 = Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	return v * STICK_LOOK_SPEED


func sprint_held() -> bool:
	return mode == Mode.WALK and Input.is_action_pressed(&"sprint")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (mode == Mode.WALK or mode == Mode.SEATED) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = (event as InputEventMouseMotion).relative * mouse_sensitivity
		if invert_y:
			rel.y = -rel.y
		look.emit(rel)
		return
	if event.is_action_pressed(&"pause"):
		pause.emit()
		get_viewport().set_input_as_handled()
		return
	if mode == Mode.MENU:
		return
	if event.is_action_pressed(&"leaderboard"):
		leaderboard_toggled.emit(true)
	elif event.is_action_released(&"leaderboard"):
		leaderboard_toggled.emit(false)
	elif event.is_action_pressed(&"toggle_camera"):
		toggle_camera.emit()
	elif event.is_action_pressed(&"leave_station"):
		leave_station.emit()
	elif event.is_action_pressed(&"ping"):
		ping.emit()
	elif event.is_action_pressed(&"item_1"):
		item_used.emit(0)
	elif event.is_action_pressed(&"item_2"):
		item_used.emit(1)
	elif event.is_action_pressed(&"item_3"):
		item_used.emit(2)
	elif event.is_action_pressed(&"emote_wheel"):
		if mode == Mode.WALK:
			set_mode(Mode.EMOTE)
			emote_wheel_toggled.emit(true)
	elif event.is_action_released(&"emote_wheel"):
		if mode == Mode.EMOTE:
			set_mode(Mode.WALK)
			emote_wheel_toggled.emit(false)
	elif mode == Mode.WALK:
		if event.is_action_pressed(&"interact"):
			interact.emit()
		elif event.is_action_pressed(&"grab"):
			grab_pressed.emit()
		elif event.is_action_released(&"grab"):
			grab_released.emit()
		elif event.is_action_pressed(&"shove"):
			shove.emit()
		elif event.is_action_pressed(&"shake"):
			shake.emit()
		elif event.is_action_pressed(&"jump") or event.is_action_pressed(&"break_free"):
			jump.emit()
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and capture_mouse:
			set_mode(Mode.WALK)  # click to recapture after alt-tab


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
