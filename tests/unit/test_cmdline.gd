extends GutTest


func test_flags_and_values() -> void:
	var c: Cmdline = Cmdline.parse(PackedStringArray(["--server", "--port", "24680", "--bots=3", "--autostart"]))
	assert_true(c.has_flag("server"))
	assert_true(c.has_flag("autostart"))
	assert_eq(c.get_int("port"), 24680)
	assert_eq(c.get_int("bots"), 3)
	assert_false(c.has("connect"))


func test_bool_flag_does_not_swallow_next_value() -> void:
	var c: Cmdline = Cmdline.parse(PackedStringArray(["--server", "pos1", "--name", "P2"]))
	assert_true(c.has_flag("server"))
	assert_eq(c.get_string("name"), "P2")
	assert_eq(c.positional(), ["pos1"] as Array[String])


func test_trailing_option_is_flag() -> void:
	var c: Cmdline = Cmdline.parse(PackedStringArray(["--timescale", "4", "--verbose"]))
	assert_almost_eq(c.get_float("timescale"), 4.0, 0.0001)
	assert_true(c.has_flag("verbose"))


func test_defaults_for_missing_or_invalid() -> void:
	var c: Cmdline = Cmdline.parse(PackedStringArray(["--port", "abc"]))
	assert_eq(c.get_int("port", 7), 7)
	assert_eq(c.get_int("missing", 9), 9)
	assert_eq(c.get_string("missing", "x"), "x")


func test_truthy_value_counts_as_flag() -> void:
	var c: Cmdline = Cmdline.parse(PackedStringArray(["--autoplay=true", "--skip-intro=0"]))
	assert_true(c.has_flag("autoplay"))
	assert_false(c.has_flag("skip-intro"))
