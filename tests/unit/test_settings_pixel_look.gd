extends GutTest
## `video/pixel_look` (0.9.14, Patrick: "leave an option to make the noise filter on the texture
## ... to disable it ... Then its saved in the settings"): on (1/3, `PIXEL_SCALE`) until the player
## picks, unset until then (the first-launch question asks), saved in user://settings.cfg by the
## choice and read back on the next start; the developer override still wins.

const SettingsScript = preload("res://services/settings_manager.gd")

## The player's settings file as it was (restored byte for byte), and whether there was one.
var _file: PackedByteArray = PackedByteArray()
var _had_file: bool = false
var _old_look: Variant
var _old_scale: int


func before_each() -> void:
	_had_file = FileAccess.file_exists(Settings.PATH)
	_file = FileAccess.get_file_as_bytes(Settings.PATH) if _had_file else PackedByteArray()
	_old_look = Settings._cfg.get_value("video", "pixel_look", "unset")
	_old_scale = Settings.pixel_scale_override
	Settings.set_pixel_override(0)


func after_each() -> void:
	if _had_file:
		var f: FileAccess = FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_buffer(_file)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	if typeof(_old_look) == TYPE_STRING:
		if Settings.has_pixel_look_choice():
			Settings._cfg.erase_section_key("video", "pixel_look")
	else:
		Settings.set_value("video", "pixel_look", _old_look)
	Settings.set_pixel_override(_old_scale)


func test_default_is_the_pixel_look_and_unchosen() -> void:
	var fresh: SettingsScript = SettingsScript.new()  # a first launch: nothing loaded
	assert_true((SettingsScript.DEFAULTS["video"] as Dictionary)["pixel_look"], "on by default")
	assert_true(fresh.pixel_look())
	assert_false(fresh.has_pixel_look_choice(), "not chosen yet: the first launch asks")
	assert_eq(fresh.pixel_scale(), SettingsScript.PIXEL_SCALE, "1/3 until the player picks")
	fresh.free()


func test_choice_is_saved_and_read_back() -> void:
	for on: bool in [false, true]:
		Settings.choose_pixel_look(on)
		assert_true(Settings.has_pixel_look_choice())
		assert_eq(Settings.pixel_look(), on)
		assert_eq(Settings.pixel_scale(), SettingsScript.PIXEL_SCALE if on else 1, "applied at once")
		var cfg := ConfigFile.new()
		assert_eq(cfg.load(Settings.PATH), OK, "written to the settings file")
		assert_eq(cfg.get_value("video", "pixel_look", null), on, "saved")
		var next_start: SettingsScript = SettingsScript.new()  # the next launch reads the same file
		next_start._cfg.load(Settings.PATH)
		assert_true(next_start.has_pixel_look_choice(), "never asked again")
		assert_eq(next_start.pixel_look(), on)
		assert_eq(next_start.pixel_scale(), SettingsScript.PIXEL_SCALE if on else 1)
		next_start.free()


func test_choosing_announces_the_change() -> void:
	watch_signals(Settings)
	Settings.choose_pixel_look(false)
	assert_signal_emitted(Settings, "changed", "the pixel view and menus switch live")


func test_developer_override_beats_the_choice() -> void:
	Settings.set_value("video", "pixel_look", false)
	Settings.set_pixel_override(4)
	assert_eq(Settings.pixel_scale(), 4)
	Settings.set_pixel_override(0)
	assert_eq(Settings.pixel_scale(), 1, "back to the player's choice")
