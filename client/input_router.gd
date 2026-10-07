class_name InputRouter
extends Node
## Turns raw input into gameplay signals and owns the input mode (walking, seated at a station,
## in a menu, emote wheel open, on a minigame stage). Mouse capture follows the mode: captured while
## walking, a free cursor kept inside the window everywhere else (released when the window loses focus). Seated, the cursor's offset from the middle of the screen (or the right
## stick) turns the head a little (`seated_look`) so the overlay stays clickable. Movement/look
## vectors are polled by the avatar; discrete actions arrive as signals. Keyboard+mouse and
## gamepad are equivalent.

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

## STAGE: a minigame owns the screen. Only the stage opening/closing changes it (`set_play_mode`
## leaves it alone), so standing up or closing a panel mid-minigame never grabs the cursor.
enum Mode { WALK, SEATED, MENU, EMOTE, STAGE }

const STICK_LOOK_SPEED: float = 3.2

var mode: Mode = Mode.WALK
## True while the process has focus and should capture the mouse in WALK mode.
var capture_mouse: bool = true
## Mouse look sensitivity (radians per pixel).
var mouse_sensitivity: float = 0.0025
var invert_y: bool = false
## Seated look: the cursor sits in a dead zone this big (fraction of half the screen) before the head turns.
const SEATED_DEAD_ZONE: float = 0.12
## Last cursor position seen (viewport pixels); NAN until the mouse moves.
var _cursor: Vector2 = Vector2(NAN, NAN)
## Beer: look is inverted on both axes and walking drifts a little.
var drunk: bool = false
## Mode to return to when the emote wheel closes (you can emote while seated too).
var _mode_before_emote: Mode = Mode.WALK
## False while the window is in the background: the cursor is then free to leave it.
var _focused: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_mode(Mode.WALK)
	_apply_settings()
	Settings.changed.connect(_apply_settings)


func _apply_settings() -> void:
	mouse_sensitivity = Settings.mouse_look()
	invert_y = bool(Settings.get_value("controls", "invert_y"))


## Switches input mode and the mouse capture that goes with it.
func set_mode(m: Mode) -> void:
	var sitting_down: bool = m == Mode.SEATED and mode == Mode.WALK
	mode = m
	if sitting_down:
		_cursor = Vector2(NAN, NAN)  # sit facing the table; the head only turns once the mouse moves
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = desired_mouse_mode()
	if sitting_down:
		Input.warp_mouse(Vector2(get_window().size) * 0.5)


## Mode change from gameplay (sitting, standing, menus closing): ignored while a minigame stage is
## up, so the stage keeps its cursor until `_back_to_casino` / results switch the mode themselves.
func set_play_mode(m: Mode) -> void:
	if mode == Mode.STAGE:
		return
	set_mode(m)


## The mouse mode that goes with the current input mode: only walking captures the mouse.
## Seated, in menus, on the emote wheel and on a minigame stage the cursor is visible so every
## button can be clicked, but confined to the window (fullscreen on two monitors included).
## In the background (focus lost) it is free.
func desired_mouse_mode() -> Input.MouseMode:
	if not _focused:
		return Input.MOUSE_MODE_VISIBLE
	if mode == Mode.WALK:
		return Input.MOUSE_MODE_CAPTURED if capture_mouse else Input.MOUSE_MODE_VISIBLE
	return Input.MOUSE_MODE_CONFINED


## Seated head turn in [-1, 1] per axis (x right, y down): the right stick while it is pushed,
## otherwise where the cursor sits relative to the middle of the screen (with a small dead zone).
func seated_look() -> Vector2:
	if mode != Mode.SEATED:
		return Vector2.ZERO
	var stick: Vector2 = Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if stick.length() > 0.2:
		return stick * (-1.0 if drunk else 1.0)
	if InputGlyphs.gamepad or is_nan(_cursor.x):
		return Vector2.ZERO
	var half: Vector2 = get_viewport().get_visible_rect().size * 0.5
	if half.x <= 0.0 or half.y <= 0.0:
		return Vector2.ZERO
	var n: Vector2 = ((_cursor - half) / half).clampf(-1.0, 1.0)
	var out := Vector2(_dead_zone(n.x), _dead_zone(n.y))
	if invert_y:
		out.y = -out.y
	return -out if drunk else out


static func _dead_zone(v: float) -> float:
	if absf(v) <= SEATED_DEAD_ZONE:
		return 0.0
	return signf(v) * (absf(v) - SEATED_DEAD_ZONE) / (1.0 - SEATED_DEAD_ZONE)


## WASD / left stick, as a 2D vector (x right, y forward) in [-1, 1].
func move_vector() -> Vector2:
	if mode != Mode.WALK:
		return Vector2.ZERO
	var v: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var out := Vector2(v.x, -v.y)
	if drunk and out.length() > 0.1:
		var t: float = Time.get_ticks_msec() / 1000.0
		out.x += sin(t * 1.3) * 0.35
	return out


## Right stick look, radians per second.
func stick_look() -> Vector2:
	if mode == Mode.MENU or mode == Mode.STAGE:
		return Vector2.ZERO
	var v: Vector2 = Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	return v * STICK_LOOK_SPEED * (-1.0 if drunk else 1.0)


func sprint_held() -> bool:
	return mode == Mode.WALK and Input.is_action_pressed(&"sprint")


## Sees every event first (even ones a UI consumes) so key hints follow the device in use.
func _input(event: InputEvent) -> void:
	InputGlyphs.observe(event)
	if event is InputEventMouse:
		_cursor = (event as InputEventMouse).position


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (mode == Mode.WALK or mode == Mode.SEATED) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = (event as InputEventMouseMotion).relative * mouse_sensitivity
		if invert_y:
			rel.y = -rel.y
		if drunk:
			rel = -rel
		look.emit(rel)
		return
	if event.is_action_pressed(&"pause"):
		pause.emit()
		get_viewport().set_input_as_handled()
		return
	if mode == Mode.MENU or mode == Mode.STAGE:
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
	elif _item_slot(event) >= 0:
		item_used.emit(_item_slot(event))
	elif event.is_action_pressed(&"emote_wheel"):
		if mode == Mode.WALK or mode == Mode.SEATED:
			_mode_before_emote = mode
			set_mode(Mode.EMOTE)
			emote_wheel_toggled.emit(true)
	elif event.is_action_released(&"emote_wheel"):
		if mode == Mode.EMOTE:
			set_mode(_mode_before_emote)
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


## Item key slot (0–2) for an event, -1 if none. Seated players' plain number keys pick chips,
## so on the keyboard items need Shift there; the d-pad always works.
func _item_slot(event: InputEvent) -> int:
	var slot: int = -1
	for i: int in 3:
		if event.is_action_pressed(StringName("item_%d" % (i + 1))):
			slot = i
	if slot >= 0 and mode == Mode.SEATED and event is InputEventKey and not (event as InputEventKey).shift_pressed:
		return -1
	return slot


func _notification(what: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
		if mode != Mode.WALK:
			Input.mouse_mode = desired_mouse_mode()  # walking recaptures on the next click
	elif what == NOTIFICATION_EXIT_TREE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # leaving the match: menus get a free cursor
