extends Node
## `Settings` autoload: persistent user settings in `user://settings.cfg`.
##
## M0 stub: load/save of a flat section/key store. The full settings set (§2.17)
## lands in M9.

const PATH: String = "user://settings.cfg"

var _cfg: ConfigFile = ConfigFile.new()


func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var err: Error = _cfg.load(PATH)
		if err != OK:
			Log.warn(&"settings", "could not load %s (error %d), using defaults" % [PATH, err])


## Reads a setting, returning `default` when unset.
func get_value(section: String, key: String, default: Variant = null) -> Variant:
	return _cfg.get_value(section, key, default)


## Writes a setting in memory; call `save()` to persist.
func set_value(section: String, key: String, value: Variant) -> void:
	_cfg.set_value(section, key, value)


## Persists all settings to disk.
func save() -> void:
	var err: Error = _cfg.save(PATH)
	if err != OK:
		Log.error(&"settings", "could not save %s (error %d)" % [PATH, err])
