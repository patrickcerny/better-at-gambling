extends Node
## `Settings` autoload: persistent user settings in `user://settings.cfg`, with defaults and
## `apply()` for the ones the engine owns (bus volumes, window mode, vsync, frame cap). Game code
## reads the rest (mouse sensitivity, invert Y, field of view) and listens to `changed`.

signal changed

const PATH: String = "user://settings.cfg"
## Base mouse look in radians per pixel at sensitivity 1.0.
const BASE_MOUSE: float = 0.0025
const DEFAULTS: Dictionary = {
	"audio": {"master": 0.8, "music": 0.6, "sfx": 0.8, "ui": 0.7, "voice": 0.9},
	## Voice chat: "push_to_talk", "open_mic" or "off" (see `VoiceChannel.MODE_KEYS`).
	"voice": {"mode": "push_to_talk"},
	"controls": {"mouse_sensitivity": 1.0, "invert_y": false},
	## `pixel_scale`: the pixel look's shrink factor 1 (off), 2, 3 or 4 (see `PixelView`).
	"video": {"fov": 85.0, "fullscreen": false, "vsync": true, "max_fps": 0, "pixel_scale": 3},
}
const FPS_CAPS: Array[int] = [0, 60, 120, 144, 240]

var _cfg: ConfigFile = ConfigFile.new()


func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var err: Error = _cfg.load(PATH)
		if err != OK:
			Log.warn(&"settings", "could not load %s (error %d), using defaults" % [PATH, err])
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


## The pixel look's shrink factor, clamped to the offered steps (1 = off).
func pixel_scale() -> int:
	return clampi(int(get_value("video", "pixel_scale")), PixelView.SCALES[0], PixelView.SCALES[-1])


## Pushes engine-owned settings: bus volumes, window mode, vsync, frame cap.
func apply() -> void:
	for pair: Array in [["Master", "master"], ["Music", "music"], ["SFX", "sfx"], ["UI", "ui"], ["Voice", "voice"]]:
		var idx: int = AudioServer.get_bus_index(pair[0])
		if idx >= 0:
			var v: float = clampf(float(get_value("audio", pair[1])), 0.0, 1.0)
			AudioServer.set_bus_mute(idx, v <= 0.001)
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))
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
