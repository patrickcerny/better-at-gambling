extends GutTest
## Key hints follow the last device used and come from the InputMap.


func after_each() -> void:
	InputGlyphs.set_gamepad(false)


func test_keyboard_and_gamepad_names() -> void:
	InputGlyphs.set_gamepad(false)
	assert_eq(InputGlyphs.key(&"interact"), "E")
	assert_eq(InputGlyphs.key(&"grab"), "LMB")
	assert_eq(InputGlyphs.key(&"bj_split"), "P")
	assert_eq(InputGlyphs.key(&"leave_station"), "Q")
	assert_eq(InputGlyphs.keys(&"bet_confirm"), "Space / Enter")
	assert_eq(InputGlyphs.hint(&"pause"), "[Esc]")
	InputGlyphs.set_gamepad(true)
	assert_eq(InputGlyphs.key(&"interact"), "X")
	assert_eq(InputGlyphs.key(&"grab"), "RT")
	assert_eq(InputGlyphs.key(&"bj_split"), "RB")
	assert_eq(InputGlyphs.key(&"leave_station"), "B")
	assert_eq(InputGlyphs.key(&"emote_wheel"), "D-pad Down")
	assert_eq(InputGlyphs.keys(&"bet_confirm"), "A")


func test_unbound_or_unknown_action() -> void:
	InputGlyphs.set_gamepad(true)
	assert_eq(InputGlyphs.key(&"bet_chip_1"), "?", "number chips have no pad binding")
	assert_eq(InputGlyphs.key(&"no_such_action"), "?")


func test_fill_replaces_action_tokens_only() -> void:
	InputGlyphs.set_gamepad(false)
	assert_eq(InputGlyphs.fill("[{interact}] Play {nothing} {}"), "[E] Play {nothing} {}")
	InputGlyphs.set_gamepad(true)
	assert_eq(InputGlyphs.fill("[{interact} / {grab}] Grab %s"), "[X / RT] Grab %s")
	assert_eq(InputGlyphs.fill("no tokens"), "no tokens")


func test_observe_switches_device_and_bumps_epoch() -> void:
	InputGlyphs.set_gamepad(false)
	var e0: int = InputGlyphs.epoch
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	InputGlyphs.observe(pad)
	assert_true(InputGlyphs.gamepad)
	assert_eq(InputGlyphs.epoch, e0 + 1)
	InputGlyphs.observe(pad)
	assert_eq(InputGlyphs.epoch, e0 + 1, "no bump without a switch")
	# Stick drift and tiny mouse jitter do not switch.
	var drift := InputEventJoypadMotion.new()
	drift.axis_value = 0.1
	var jitter := InputEventMouseMotion.new()
	jitter.relative = Vector2(1, 1)
	InputGlyphs.observe(jitter)
	assert_true(InputGlyphs.gamepad)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	InputGlyphs.observe(key)
	assert_false(InputGlyphs.gamepad)
	InputGlyphs.observe(drift)
	assert_false(InputGlyphs.gamepad)
	assert_eq(InputGlyphs.epoch, e0 + 2)
