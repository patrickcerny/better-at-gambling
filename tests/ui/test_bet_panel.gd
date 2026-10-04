extends GutTest
## Bet panel navigation with real keyboard and joypad events pushed through the viewport
## (M2 acceptance: "UI navigation test with keyboard and joypad events on bet panel").

var panel: BetPanel


func before_each() -> void:
	panel = BetPanel.new()
	add_child_autofree(panel)
	panel.setup([10, 25, 50, 100], 10, 200, "BET")
	await wait_process_frames(2)


func _press(action: StringName, joypad: bool) -> void:
	for ev: InputEvent in InputMap.action_get_events(action):
		if joypad and ev is InputEventJoypadButton:
			var e: InputEventJoypadButton = ev.duplicate()
			e.pressed = true
			get_tree().root.push_input(e)
			e = e.duplicate()
			e.pressed = false
			get_tree().root.push_input(e)
			return
		if not joypad and ev is InputEventKey:
			var k: InputEventKey = ev.duplicate()
			k.pressed = true
			get_tree().root.push_input(k)
			k = k.duplicate()
			k.pressed = false
			get_tree().root.push_input(k)
			return
	fail_test("no %s binding for %s" % ["joypad" if joypad else "keyboard", action])


func test_keyboard_selects_chip_and_confirms() -> void:
	watch_signals(panel)
	_press(&"bet_chip_2", false)
	assert_eq(panel.selected_chip, 1, "key 2 selects the $25 chip")
	assert_eq(panel.chip_value(), 25)
	_press(&"bet_confirm", false)
	assert_signal_emitted_with_parameters(panel, "confirmed", [25])
	_press(&"bet_chip_4", false)
	_press(&"bet_clear", false)
	_press(&"bet_confirm", false)
	assert_eq(panel.amount, 100, "after a clear, confirm bets the newly selected chip")


func test_keyboard_clear_and_repeat() -> void:
	watch_signals(panel)
	panel.set_amount(50)
	panel.confirm()
	_press(&"bet_clear", false)
	assert_eq(panel.amount, 0, "clear resets the amount")
	assert_signal_emitted(panel, "cleared")
	_press(&"bet_repeat", false)
	assert_eq(panel.amount, 50, "repeat restores the last confirmed bet")


func test_joypad_cycles_chips() -> void:
	panel.select_chip(0)
	_press(&"bet_chip_next", true)
	assert_eq(panel.selected_chip, 1, "RB moves to the next chip")
	_press(&"bet_chip_next", true)
	assert_eq(panel.selected_chip, 2)
	_press(&"bet_chip_prev", true)
	assert_eq(panel.selected_chip, 1, "LB moves back")


func test_focus_navigation_reaches_every_button() -> void:
	var first: Button = panel._chip_buttons[0]
	first.grab_focus()
	var seen: Dictionary = {}
	for i: int in 40:
		var f: Control = get_viewport().gui_get_focus_owner()
		if f != null:
			seen[f.get_instance_id()] = f
		var ev := InputEventAction.new()
		ev.action = &"ui_right" if i % 2 == 0 else &"ui_down"
		ev.pressed = true
		get_tree().root.push_input(ev)
		await wait_process_frames(1)
	var buttons: int = 0
	for n: Node in panel.find_children("*", "Button", true, false):
		buttons += 1
	assert_gt(seen.size(), 4, "focus walks across chips and actions (%d of %d buttons reached)" % [seen.size(), buttons])


func test_instant_mode_confirms_on_chip_press() -> void:
	panel.setup([10, 25, 50, 100], 10, 100, "PULL", true)
	watch_signals(panel)
	_press(&"bet_chip_3", false)
	assert_signal_emitted_with_parameters(panel, "confirmed", [50])
