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
## Other pads name some buttons differently (positions stay the same: SDL maps every pad to the
## Xbox layout). The Steam Deck calls bumpers and triggers L1/R1/L2/R2; PlayStation pads have
## shapes on the face buttons; Nintendo pads name the shoulders L/R/ZL/ZR. Missing entries keep
## the Xbox name.
const STYLE_NAMES: Dictionary[StringName, Dictionary] = {
	&"deck": {"LB": "L1", "RB": "R1", "LT": "L2", "RT": "R2"},
	&"playstation": {"A": "Cross", "B": "Circle", "X": "Square", "Y": "Triangle", "LB": "L1", "RB": "R1", "LT": "L2", "RT": "R2", "View": "Share", "Menu": "Options"},
	&"nintendo": {"LB": "L", "RB": "R", "LT": "ZL", "RT": "ZR", "View": "−", "Menu": "+"},
}
## Shorter names than the engine's for keys that appear in hints.
const KEY_NAMES: Dictionary[String, String] = {"Escape": "Esc", "CapsLock": "Caps", "BackSpace": "Backspace"}

## True after the last meaningful input came from a gamepad.
static var gamepad: bool = false
## Bumps every time `gamepad` flips (or the pad's naming style changes).
static var epoch: int = 0
## How the pad in use names its buttons: &"xbox", &"deck", &"playstation" or &"nintendo".
static var style: StringName = &"xbox"
## True on a Steam Deck (`on_steam_deck`): its own controls are named the Deck's way.
static var deck: bool = false
static var _token: RegEx


## Notes which device an input event came from (tiny stick drift and mouse jitter are ignored).
static func observe(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_pad_used(event.device)
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) >= 0.5:
			_pad_used(event.device)
	elif event is InputEventKey or event is InputEventMouseButton:
		set_gamepad(false)
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() >= 6.0:
			set_gamepad(false)


static func _pad_used(device: int) -> void:
	var st: StringName = style_for(Input.get_joy_name(device) if device >= 0 else "", deck)
	if st != style:
		style = st
		epoch += 1
	set_gamepad(true)


## The naming style for a pad called `joy_name` (Input.get_joy_name). On a Steam Deck every pad
## Steam passes through is the Deck's own controls unless it says otherwise.
static func style_for(joy_name: String, on_deck: bool = false) -> StringName:
	var n: String = joy_name.to_lower()
	for word: String in ["playstation", "dualshock", "dualsense", "ps3", "ps4", "ps5", "sony"]:
		if word in n:
			return &"playstation"
	for word: String in ["nintendo", "switch", "joy-con", "joycon", "pro controller"]:
		if word in n:
			return &"nintendo"
	if on_deck or "steam deck" in n:
		return &"deck"
	return &"xbox"


## True when the game runs on a Steam Deck: Steam sets `SteamDeck=1` for games it starts there,
## and the Deck's board names itself (Jupiter = LCD, Galileo = OLED).
static func on_steam_deck() -> bool:
	if OS.get_environment("SteamDeck") == "1":
		return true
	if OS.get_name() != "Linux":
		return false
	var f: FileAccess = FileAccess.open("/sys/devices/virtual/dmi/id/product_name", FileAccess.READ)
	if f == null:
		return false
	var product: String = f.get_as_text().strip_edges()
	return product in ["Jupiter", "Galileo"]


## Turns the Deck naming on (SteamSvc, Settings call this at start).
static func set_deck(on: bool) -> void:
	deck = on
	if on and style == &"xbox":
		style = &"deck"
		epoch += 1


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


## `fill` for a given device instead of the last one used (the minigame rules card shows both).
static func fill_for(text: String, pad: bool) -> String:
	if not "{" in text:
		return text
	if _token == null:
		_token = RegEx.create_from_string("\\{([a-z0-9_]+)\\}")
	var out: String = text
	for m: RegExMatch in _token.search_all(text):
		var action: StringName = StringName(m.get_string(1))
		if InputMap.has_action(action):
			var l: PackedStringArray = labels(action, pad)
			out = out.replace(m.get_string(0), l[0] if not l.is_empty() else "?")
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
		return pad_name(PAD_BUTTONS.get(int((ev as InputEventJoypadButton).button_index), "Button %d" % int((ev as InputEventJoypadButton).button_index)))
	if ev is InputEventJoypadMotion:
		return pad_name(PAD_AXES.get(int((ev as InputEventJoypadMotion).axis), "Stick"))
	return ""


## An Xbox-style pad button name ("A", "LB", "RT") in the style of the pad in use.
static func pad_name(xbox_name: String) -> String:
	var names: Dictionary = STYLE_NAMES.get(style, {})
	return str(names.get(xbox_name, xbox_name))


## Every Xbox button name written into `text` ("A / B / X / Y", "D-pad + A") in the pad's style.
static func pad_text(text: String) -> String:
	if style == &"xbox":
		return text
	var re := RegEx.create_from_string("\\b(A|B|X|Y|LB|RB|LT|RT|View|Menu)\\b")
	var out: String = ""
	var at: int = 0
	for m: RegExMatch in re.search_all(text):
		out += text.substr(at, m.get_start() - at) + pad_name(m.get_string())
		at = m.get_end()
	return out + text.substr(at)
