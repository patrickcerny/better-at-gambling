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
	## Voice chat: "push_to_talk", "open_mic" or "off" (see `VoiceChannel.MODE_KEYS`), the
	## microphone: a name from `AudioServer.get_input_device_list()` ("Default": the system's), and
	## `mic_gain`: how loud your own voice goes out (0..`MAX_MIC_GAIN`, 1 = as the mic hears it).
	## Open mic by default (0.9.12; §2.22 "proximity voice is on by default"): with push-to-talk
	## as the default almost nobody held T, and a whole casino round carried 15 frames of voice.
	"voice": {"mode": "open_mic", "input_device": "Default", "mic_gain": 1.0},
	## `stick_sensitivity` scales the gamepad's right-stick look.
	"controls": {"mouse_sensitivity": 1.0, "invert_y": false, "stick_sensitivity": 1.0},
	"video": {"fov": 85.0, "fullscreen": false, "vsync": true, "max_fps": 0},
}
## Frame limit choices (Settings > Video): 0 is off, `MATCH_MONITOR` follows the screen's refresh rate.
const MATCH_MONITOR: int = -1
const FPS_CAPS: Array[int] = [0, 30, 60, 90, 120, 144, 165, 240, MATCH_MONITOR]
## Mic volume goes up to 200 % (an amplifier for a quiet microphone).
const MAX_MIC_GAIN: float = 2.0
## Keys of the `video` section older versions saved that mean nothing any more (`drop_removed_keys`).
const REMOVED_VIDEO_KEYS: Array[String] = ["pixel_look", "pixel_scale"]
## Section of the settings file that holds remapped keys: action → "key:<physical keycode>" or
## "mouse:<button index>". Only actions the player changed are stored.
const KEYBIND_SECTION: String = "keybinds"
## Keyboard and mouse actions the Controls tab can remap, in the order it lists them.
const KEYBINDS: Dictionary[StringName, String] = {
	&"move_forward": "Move forward", &"move_back": "Move back", &"move_left": "Move left", &"move_right": "Move right",
	&"sprint": "Sprint", &"jump": "Jump", &"interact": "Interact", &"shove": "Shove", &"grab": "Grab / throw", &"shake": "Shake",
	&"item_1": "Item 1", &"item_2": "Item 2", &"item_3": "Item 3", &"emote_wheel": "Emote wheel",
	&"emote_1": "Emote: 67", &"emote_2": "Emote: thumbs up", &"emote_3": "Emote: thumbs down", &"emote_4": "Emote: default dance",
	&"leaderboard": "Leaderboard", &"ping": "Ping", &"toggle_camera": "Toggle camera",
	&"leave_station": "Leave station", &"pause": "Pause menu", &"push_to_talk": "Push to talk",
	&"toggle_fullscreen": "Toggle fullscreen",
}

var _cfg: ConfigFile = ConfigFile.new()
## Each remappable action's InputMap events as the project defines them (before any remap).
var _default_events: Dictionary[StringName, Array] = {}
## The microphone `apply()` last chose (listing devices is slow on Windows: only when it changes).
var _applied_input_device: String = ""


func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var err: Error = _cfg.load(PATH)
		if err != OK:
			Log.warn(&"settings", "could not load %s (error %d), using defaults" % [PATH, err])
	drop_removed_keys()
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


## F11 (`toggle_fullscreen`, remappable) flips fullscreen everywhere: the menus, a match, a
## minigame, the pause menu. Handled here in `_input`, before any focused control can take the key.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen") and not event.is_echo():
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


## Flips `video/fullscreen`, applies it (the window follows) and saves it; Settings > Video shows it.
func toggle_fullscreen() -> void:
	change("video", "fullscreen", not bool(get_value("video", "fullscreen")))
	save()
	Log.info(&"video", "fullscreen %s" % ("on" if bool(get_value("video", "fullscreen")) else "off"))


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


## Settings the game no longer has (the pixel look, removed in 0.9.15: `video/pixel_look` and the
## older `video/pixel_scale`): erased quietly from a loaded file and saved; true when any was found.
func drop_removed_keys() -> bool:
	var dropped: bool = false
	for key: String in REMOVED_VIDEO_KEYS:
		if _cfg.has_section_key("video", key):
			_cfg.erase_section_key("video", key)
			dropped = true
	if dropped:
		save()
	return dropped


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
	apply_input_device()
	Engine.max_fps = fps_limit(int(get_value("video", "max_fps")), DisplayServer.screen_get_refresh_rate())
	if DisplayServer.get_name() == "headless":
		return
	var want: int = window_mode_for(bool(get_value("video", "fullscreen")), DisplayServer.window_get_mode())
	if want >= 0:
		DisplayServer.window_set_mode(want as DisplayServer.WindowMode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(get_value("video", "vsync")) else DisplayServer.VSYNC_DISABLED)


## The window mode to switch to for the `fullscreen` setting from the `current` one, or −1 to leave
## it (already right; a maximized or minimized window stays as it is while windowed).
static func window_mode_for(fullscreen: bool, current: DisplayServer.WindowMode) -> int:
	if fullscreen and current != DisplayServer.WINDOW_MODE_FULLSCREEN:
		return DisplayServer.WINDOW_MODE_FULLSCREEN
	if not fullscreen and current == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return DisplayServer.WINDOW_MODE_WINDOWED
	return -1


## The `Engine.max_fps` for a frame limit choice (`FPS_CAPS`): `MATCH_MONITOR` rounds the screen's
## `refresh` rate (no limit when the screen will not say, as headless).
static func fps_limit(choice: int, refresh: float) -> int:
	if choice == MATCH_MONITOR:
		return roundi(refresh) if refresh > 0.0 else 0
	return maxi(choice, 0)


## The Video tab's name for a frame limit choice.
static func fps_label(choice: int) -> String:
	if choice == MATCH_MONITOR:
		return "Match monitor"
	return "Off" if choice <= 0 else "%d FPS" % choice


## The microphone gain the voice capture applies (the saved Mic volume, kept in 0..`MAX_MIC_GAIN`).
func mic_gain() -> float:
	return clampf(float(get_value("voice", "mic_gain")), 0.0, MAX_MIC_GAIN)


## The input device to use: the saved one while it is plugged in, else the system default.
static func pick_input_device(saved: String, available: PackedStringArray) -> String:
	return saved if saved != "" and saved in available else VoiceMicSource.DEFAULT_DEVICE


## Points the audio driver at the saved microphone (Default when it is gone; the choice stays
## saved, so it comes back when the device is plugged in again).
func apply_input_device(force: bool = false) -> void:
	var saved: String = str(get_value("voice", "input_device"))
	if saved == _applied_input_device and not force:
		return
	_applied_input_device = saved
	var device: String = pick_input_device(saved, AudioServer.get_input_device_list())
	if device != saved:
		Log.warn(&"settings", "microphone \"%s\" not found, using the default one" % saved)
	if AudioServer.input_device != device:
		AudioServer.input_device = device
		Log.info(&"settings", "microphone: %s" % device)
