class_name InputGlyphs
extends RefCounted
## On-screen names for input actions that follow the device you used last: keyboard + mouse or
## gamepad. `InputGlyphs.key(&"interact")` is "E" after a key press and "X" after a pad press.
## Names come from the live InputMap, so rebinding shows up. The InputRouter feeds every input
## event to `observe`; UIs that print keys redraw when `epoch` changes (it bumps on each switch).

const PAD_BUTTONS: Dictionary[int, String] = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Menu",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad Up", JOY_BUTTON_DPAD_DOWN: "D-pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-pad Left", JOY_BUTTON_DPAD_RIGHT: "D-pad Right",
}
const PAD_AXES: Dictionary[int, String] = {
	JOY_AXIS_LEFT_X: "Left stick", JOY_AXIS_LEFT_Y: "Left stick",
	JOY_AXIS_RIGHT_X: "Right stick", JOY_AXIS_RIGHT_Y: "Right stick",
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
}
const MOUSE_BUTTONS: Dictionary[int, String] = {
	MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "Wheel", MOUSE_BUTTON_WHEEL_DOWN: "Wheel",
}
## Shorter names than the engine's for keys that appear in hints.
const KEY_NAMES: Dictionary[String, String] = {"Escape": "Esc", "CapsLock": "Caps", "BackSpace": "Backspace"}

## True after the last meaningful input came from a gamepad.
static var gamepad: bool = false
## Bumps every time `gamepad` flips.
static var epoch: int = 0
static var _token: RegEx


## Notes which device an input event came from (tiny stick drift and mouse jitter are ignored).
static func observe(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		set_gamepad(true)
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) >= 0.5:
			set_gamepad(true)
	elif event is InputEventKey or event is InputEventMouseButton:
		set_gamepad(false)
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() >= 6.0:
			set_gamepad(false)


static func set_gamepad(on: bool) -> void:
	if on != gamepad:
		gamepad = on
		epoch += 1


## Main name of an action's binding on the current device ("E", "LMB", "X", "RT"); "?" if unbound.
static func key(action: StringName) -> String:
	var l: PackedStringArray = labels(action, gamepad)
	return l[0] if not l.is_empty() else "?"


## Up to `count` names of an action's bindings on the current device, joined: "Space / Enter".
static func keys(action: StringName, count: int = 2) -> String:
	var l: PackedStringArray = labels(action, gamepad)
	if l.is_empty():
		return "?"
	return " / ".join(l.slice(0, count))


## "[E]" style hint for an action.
static func hint(action: StringName) -> String:
	return "[%s]" % key(action)


## Replaces every `{action}` in `text` with that action's key name:
## `fill("[{interact}] Sit")` → "[E] Sit" or "[X] Sit". Unknown actions are left as written.
static func fill(text: String) -> String:
	if not "{" in text:
		return text
	if _token == null:
		_token = RegEx.create_from_string("\\{([a-z0-9_]+)\\}")
	var out: String = text
	for m: RegExMatch in _token.search_all(text):
		var action: StringName = StringName(m.get_string(1))
		if InputMap.has_action(action):
			out = out.replace(m.get_string(0), key(action))
	return out


## Names of an action's bindings for one device (deduplicated, in InputMap order).
static func labels(action: StringName, pad: bool) -> PackedStringArray:
	var out: PackedStringArray = []
	if not InputMap.has_action(action):
		return out
	for ev: InputEvent in InputMap.action_get_events(action):
		var is_pad: bool = ev is InputEventJoypadButton or ev is InputEventJoypadMotion
		if is_pad != pad:
			continue
		var l: String = event_label(ev)
		if l != "" and not l in out:
			out.append(l)
	return out


## Display name of one bound event ("" for kinds we don't name).
static func event_label(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k: InputEventKey = ev
		var code: Key = k.keycode
		if code == KEY_NONE:
			code = k.physical_keycode
			if DisplayServer.get_name() != "headless":
				code = DisplayServer.keyboard_get_keycode_from_physical(code)  # the user's layout
		var s: String = OS.get_keycode_string(code)
		return KEY_NAMES.get(s, s)
	if ev is InputEventMouseButton:
		return MOUSE_BUTTONS.get(int((ev as InputEventMouseButton).button_index), "Mouse")
	if ev is InputEventJoypadButton:
		return PAD_BUTTONS.get(int((ev as InputEventJoypadButton).button_index), "Button %d" % int((ev as InputEventJoypadButton).button_index))
	if ev is InputEventJoypadMotion:
		return PAD_AXES.get(int((ev as InputEventJoypadMotion).axis), "Stick")
	return ""
