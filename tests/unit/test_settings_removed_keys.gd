extends GutTest
## The pixel look was removed in 0.9.15 (Patrick: "remove that filter overall"; the code lives on
## the branch `pixel-look-saved`): no video setting for it any more, and a settings file from an
## older version loses its `video/pixel_look` and `video/pixel_scale` keys quietly on load (saved
## back without them), keeping every other setting.

const SettingsScript = preload("res://services/settings_manager.gd")

## The player's settings file as it was (restored byte for byte), and whether there was one.
var _file: PackedByteArray = PackedByteArray()
var _had_file: bool = false


func before_each() -> void:
	_had_file = FileAccess.file_exists(Settings.PATH)
	_file = FileAccess.get_file_as_bytes(Settings.PATH) if _had_file else PackedByteArray()


func after_each() -> void:
	if _had_file:
		var f: FileAccess = FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_buffer(_file)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))


func test_no_pixel_setting_is_left() -> void:
	var video: Dictionary = SettingsScript.DEFAULTS["video"]
	assert_false(video.has("pixel_look"))
	assert_false(video.has("pixel_scale"))
	for m: String in ["pixel_look", "pixel_scale", "has_pixel_look_choice", "choose_pixel_look", "set_pixel_override"]:
		assert_false(Settings.has_method(m), "%s is gone" % m)
	assert_false("pixel_scale_override" in Settings)


func test_old_keys_are_dropped_and_the_rest_kept() -> void:
	var old := ConfigFile.new()  # a settings file written by 0.9.14
	old.set_value("video", "pixel_look", true)
	old.set_value("video", "pixel_scale", 3)
	old.set_value("video", "fov", 92.0)
	old.set_value("audio", "music", 0.25)
	assert_eq(old.save(Settings.PATH), OK)
	var s: SettingsScript = SettingsScript.new()
	assert_eq(s._cfg.load(Settings.PATH), OK)
	assert_true(s.drop_removed_keys(), "found the old keys")
	assert_false(s._cfg.has_section_key("video", "pixel_look"))
	assert_false(s._cfg.has_section_key("video", "pixel_scale"))
	assert_eq(float(s.get_value("video", "fov")), 92.0, "other video settings kept")
	assert_eq(float(s.get_value("audio", "music")), 0.25, "other sections kept")
	var saved := ConfigFile.new()
	assert_eq(saved.load(Settings.PATH), OK)
	assert_false(saved.has_section_key("video", "pixel_look"), "saved without them")
	assert_false(saved.has_section_key("video", "pixel_scale"))
	assert_eq(float(saved.get_value("video", "fov", 0.0)), 92.0)
	assert_false(s.drop_removed_keys(), "nothing left to drop the next time")
	s.free()
