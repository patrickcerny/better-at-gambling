extends GutTest
## Volume sliders really move their audio bus, on a curve the ear can hear (polish round 2026-10-06).

var _saved: Dictionary = {}


func before_each() -> void:
	for key: String in ["master", "music", "sfx", "ui", "voice"]:
		_saved[key] = Settings.get_value("audio", key)


func after_each() -> void:
	for key: String in _saved:
		Settings.set_value("audio", key, _saved[key])
	Settings.apply()


func test_each_slider_drives_its_bus() -> void:
	for pair: Array in [["Master", "master"], ["Music", "music"], ["SFX", "sfx"], ["UI", "ui"], ["Voice", "voice"]]:
		var idx: int = AudioServer.get_bus_index(pair[0])
		assert_true(idx >= 0, "bus %s exists" % pair[0])
		Settings.change("audio", pair[1], 0.5)
		assert_almost_eq(AudioServer.get_bus_volume_db(idx), Settings.slider_db(0.5), 0.01, pair[0])
		assert_false(AudioServer.is_bus_mute(idx))
		Settings.change("audio", pair[1], 0.0)
		assert_true(AudioServer.is_bus_mute(idx), "%s mutes at 0" % pair[0])


func test_curve_is_audible() -> void:
	assert_almost_eq(Settings.slider_db(1.0), 0.0, 0.01)
	assert_almost_eq(Settings.slider_db(0.5), -12.04, 0.05)
	assert_lt(Settings.slider_db(0.25), -24.0)
