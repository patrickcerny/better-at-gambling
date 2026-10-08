extends Node
## `Settings` autoload: persistent user settings in `user://settings.cfg`, with defaults and
## `apply()` for the ones the engine owns (bus volumes, window mode, vsync, frame cap). Game code
## reads the rest (mouse sensitivity, invert Y, field of view) and listens to `changed`.
## Key bindings the player remaps in the Controls tab live here too (section `keybinds`), so they
## stay on this machine for this user (never synced to a profile or cloud); `apply_keybinds`
## writes them into the InputMap at startup and after every change.

signal changed

const PATH: String = "user://settings.cfg"
## Base mouse look in radians per pixel at sensitivity 1.0.
const BASE_MOUSE: float = 0.0025
const DEFAULTS: Dictionary = {
	"audio": {"master": 0.8, "music": 0.6, "sfx": 0.8, "ui": 0.7, "voice": 0.9},
	## Voice chat: "push_to_talk", "open_mic" or "off" (see `VoiceChannel.MODE_KEYS`).
	"voice": {"mode": "push_to_talk"},
	"controls": {"mouse_sensitivity": 1.0, "invert_y": false},
	"video": {"fov": 85.0, "fullscreen": false, "vsync": true, "max_fps": 0},
}
const FPS_CAPS: Array[int] = [0, 60, 120, 144, 240]
## The pixel look is the same for everyone (Patrick: "pixel look cannot be set, let it be for all
## users 1/3"): the world renders at a third of the window's resolution.
const PIXEL_SCALE: int = 3
## Section of the settings file that holds remapped keys: action → "key:<physical keycode>" or
## "mouse:<button index>". Only actions the player changed are stored.
const KEYBIND_SECTION: String = "keybinds"
## Keyboard and mouse actions the Controls tab can remap, in the order it lists them.
const KEYBINDS: Dictionary[StringName, String] = {
	&"move_forward": "Move forward", &"move_back": "Move back", &"move_left": "Move left", &"move_right": "Move right",
	&"jump": "Jump", &"interact": "Interact", &"shove": "Shove", &"grab": "Grab / throw", &"shake": "Shake",
	&"item_1": "Item 1", &"item_2": "Item 2", &"item_3": "Item 3", &"emote_wheel": "Emote wheel",
	&"leaderboard": "Leaderboard", &"ping": "Ping", &"toggle_camera": "Toggle camera",
	&"leave_station": "Leave station", &"pause": "Pause menu",
}

## Developer override for the pixel look (screenshot tool, pixel tests); 0 = the fixed look. Never saved.
var pixel_scale_override: int = 0
var _cfg: ConfigFile = ConfigFile.new()
## Each remappable action's InputMap events as the project defines them (before any remap).
var _default_events: Dictionary[StringName, Array] = {}


func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var err: Error = _cfg.load(PATH)
		if err != OK:
			Log.warn(&"settings", "could not load %s (error %d), using defaults" % [PATH, err])
	if _cfg.has_section_key("video", "pixel_scale"):
		# The pixel look used to be a setting; it is fixed now, so drop the old choice quietly.
		_cfg.erase_section_key("video", "pixel_scale")
		save()
	for action: StringName in KEYBINDS:
		if InputMap.has_action(action):
			_default_events[action] = InputMap.action_get_events(action).duplicate()
	apply_keybinds()
	apply.call_deferred()


## Reads a setting, returning `default` (or the built-in default) when unset.
func get_value(section: String, key: String, default: Variant = null) -> Variant:
	if default == null and DEFAULTS.has(section):
		default = (DEFAULTS[section] as Dictionary).get(key, null)
	return _cfg.get_value(section, key, default)


## Writes a setting in memory; call `save()` to persist.
func set_value(section: String, key: String, value: Variant) -> void:
	_cfg.set_value(section, key, value)


## Writes, applies and announces a player-facing setting (the settings panel).
func change(section: String, key: String, value: Variant) -> void:
	set_value(section, key, value)
	apply()
	changed.emit()


## Persists all settings to disk.
func save() -> void:
	var err: Error = _cfg.save(PATH)
	if err != OK:
		Log.error(&"settings", "could not save %s (error %d)" % [PATH, err])


## Mouse look in radians per pixel.
func mouse_look() -> float:
	return BASE_MOUSE * float(get_value("controls", "mouse_sensitivity"))


## The pixel look's shrink factor: `PIXEL_SCALE` for everyone, whatever an old settings file says.
func pixel_scale() -> int:
	if pixel_scale_override > 0:
		return clampi(pixel_scale_override, PixelView.SCALES[0], PixelView.SCALES[-1])
	return PIXEL_SCALE


## Developer-only: renders the pixel look at `s` (0 = back to the fixed look) and announces it.
func set_pixel_override(s: int) -> void:
	pixel_scale_override = s
	changed.emit()


# --- Key bindings -----------------------------------------------------------------------------

## The player's own key or mouse button for `action`, or null when it uses the default.
func keybind(action: StringName) -> InputEvent:
	return decode_binding(str(_cfg.get_value(KEYBIND_SECTION, String(action), "")))


## True when the player has remapped `action`.
func is_rebound(action: StringName) -> bool:
	return keybind(action) != null


## Remaps `action`'s main keyboard/mouse binding to `event` (a key or mouse button press), updates
## the InputMap at once and announces it. Call `save()` to persist.
func bind_key(action: StringName, event: InputEvent) -> void:
	var code: String = encode_binding(event)
	if code == "" or not KEYBINDS.has(action):
		return
	_cfg.set_value(KEYBIND_SECTION, String(action), code)
	apply_keybinds()
	changed.emit()


## Puts every remappable action back on the project's default keys.
func reset_keybinds() -> void:
	if _cfg.has_section(KEYBIND_SECTION):
		_cfg.erase_section(KEYBIND_SECTION)
	apply_keybinds()
	changed.emit()


## Rebuilds each remappable action in the InputMap: the project's events, with the first
## keyboard/mouse one swapped for the player's binding (gamepad events and secondary keys such as
## the arrow keys stay).
func apply_keybinds() -> void:
	for action: StringName in _default_events:
		var events: Array = (_default_events[action] as Array).duplicate()
		var custom: InputEvent = keybind(action)
		if custom != null:
			var slot: int = -1
			for i: int in events.size():
				if events[i] is InputEventKey or events[i] is InputEventMouseButton:
					slot = i
					break
			if slot >= 0:
				events[slot] = custom
			else:
				events.push_front(custom)
		InputMap.action_erase_events(action)
		for ev: InputEvent in events:
			InputMap.action_add_event(action, ev)


## The name of `action`'s main keyboard/mouse binding ("E", "LMB"), "?" when it has none.
func binding_label(action: StringName) -> String:
	if InputMap.has_action(action):
		for ev: InputEvent in InputMap.action_get_events(action):
			if ev is InputEventKey or ev is InputEventMouseButton:
				return InputGlyphs.event_label(ev)
	return "?"


## True for an input the Controls tab accepts as a binding: a key (not Escape, which cancels) or a
## mouse button press (not the wheel).
static func is_bindable(event: InputEvent) -> bool:
	if event is InputEventKey:
		var k: InputEventKey = event
		if not k.pressed or k.echo or k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE:
			return false
		return k.physical_keycode != KEY_NONE or k.keycode != KEY_NONE
	if event is InputEventMouseButton:
		var m: InputEventMouseButton = event
		return m.pressed and not m.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
	return false


## "key:<physical keycode>" / "mouse:<button>" for a key or mouse button ("" for anything else).
static func encode_binding(event: InputEvent) -> String:
	if event is InputEventKey:
		var k: InputEventKey = event
		var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return "key:%d" % code if code != KEY_NONE else ""
	if event is InputEventMouseButton:
		return "mouse:%d" % int((event as InputEventMouseButton).button_index)
	return ""


## The InputMap event for a stored binding (any device, physical key), or null.
static func decode_binding(code: String) -> InputEvent:
	var parts: PackedStringArray = code.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int() or int(parts[1]) <= 0:
		return null
	match parts[0]:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(parts[1]) as Key
			k.device = -1
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(parts[1]) as MouseButton
			m.device = -1
			return m
	return null


## Bus gain for a 0..1 volume slider. Squared amplitude so the slider feels even to the ear
## (50% ≈ -12 dB, 25% ≈ -24 dB); a plain linear mapping only reaches -6 dB at 50% and the
## sliders seemed to do nothing.
static func slider_db(v: float) -> float:
	return linear_to_db(maxf(v * v, 0.00001))


## Pushes engine-owned settings: bus volumes, window mode, vsync, frame cap.
func apply() -> void:
	for pair: Array in [["Master", "master"], ["Music", "music"], ["SFX", "sfx"], ["UI", "ui"], ["Voice", "voice"]]:
		var idx: int = AudioServer.get_bus_index(pair[0])
		if idx >= 0:
			var v: float = clampf(float(get_value("audio", pair[1])), 0.0, 1.0)
			AudioServer.set_bus_mute(idx, v <= 0.001)
			AudioServer.set_bus_volume_db(idx, slider_db(v))
	Engine.max_fps = int(get_value("video", "max_fps"))
	if DisplayServer.get_name() == "headless":
		return
	var fs: bool = bool(get_value("video", "fullscreen"))
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	if fs and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fs and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(get_value("video", "vsync")) else DisplayServer.VSYNC_DISABLED)
