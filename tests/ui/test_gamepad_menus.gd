extends GutTest
## Menus on a gamepad and the Steam Deck. Godot's own UI actions have no pad buttons, so before
## 0.9.63 A pressed nothing and B closed nothing in any menu: now A is ui_accept and B ui_cancel.
## Also: the name field opens a keyboard on A (Steam's on a Deck, else ours), the Deck names its
## shoulders L1/R1/L2/R2 and starts fullscreen, the Rock Paper Scissors duel takes the d-pad, the
## cosmetics shop's featured offers, outfit slots and Gold "+" are reachable, and Grab Your Hand
## picks a card with the d-pad.

var _old_seen: Variant


func before_each() -> void:
	_old_seen = Settings.get_value("tutorial", "seen", "unset")
	Settings.set_value("tutorial", "seen", true)


func after_each() -> void:
	PadKeyboard.close_current()
	InputGlyphs.set_gamepad(false)
	InputGlyphs.style = &"xbox"
	InputGlyphs.deck = false
	Settings.on_deck = false
	Settings.set_value("tutorial", "seen", null if typeof(_old_seen) == TYPE_STRING else _old_seen)
	Settings.save()


func _pad(button: JoyButton) -> void:
	for down: bool in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.pressed = down
		get_tree().root.push_input(ev)


func test_a_and_b_are_the_ui_buttons() -> void:
	assert_true(InputGlyphs.labels(&"ui_accept", true).has("A"), "A presses the focused button")
	assert_true(InputGlyphs.labels(&"ui_cancel", true).has("B"), "B goes back")
	assert_true(InputGlyphs.labels(&"ui_accept", false).has("Enter"), "Enter still does")
	assert_true(InputGlyphs.labels(&"ui_cancel", false).has("Esc"), "Esc still does")
	assert_true(InputGlyphs.labels(&"ping", true).has("LT"), "ping has a pad button now (LT)")


func test_a_presses_a_focused_button() -> void:
	var b := Button.new()
	add_child_autofree(b)
	var hits: Array[int] = [0]
	b.pressed.connect(func() -> void: hits[0] += 1)
	await wait_process_frames(1)
	b.grab_focus()
	_pad(JOY_BUTTON_A)
	assert_eq(hits[0], 1)


func test_b_cancels_a_confirm_dialog() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var said: Array[int] = [0]
	ConfirmDialog.ask(host, "QUIT THE GAME?", "", "QUIT", func() -> void: said[0] += 1)
	await wait_process_frames(1)
	_pad(JOY_BUTTON_B)
	await wait_process_frames(2)
	assert_null(ConfirmDialog.open_in(host), "B closes it")
	assert_eq(said[0], 0, "without quitting")


func test_main_menu_a_opens_play_online_and_b_comes_back() -> void:
	var menu: Control = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
	add_child_autofree(menu)
	await wait_process_frames(3)
	var online: Button = menu.get(&"_play_online")
	online.grab_focus()
	_pad(JOY_BUTTON_A)
	await wait_process_frames(1)
	assert_true((menu.get(&"online") as Control).visible, "A opened PLAY ONLINE")
	assert_not_null(get_viewport().gui_get_focus_owner(), "something in it has the focus")
	_pad(JOY_BUTTON_B)
	await wait_process_frames(1)
	assert_false((menu.get(&"online") as Control).visible, "B went back")
	assert_eq(get_viewport().gui_get_focus_owner(), online, "focus back on PLAY ONLINE")


func test_keyboard_keeps_max_length_and_word_capitals() -> void:
	var edit := LineEdit.new()
	edit.max_length = 6
	add_child_autofree(edit)
	await wait_process_frames(1)
	var kb: PadKeyboard = PadKeyboard.open_for(edit)
	await wait_process_frames(1)
	for ch: String in ["L", "U", "C", "K", " ", "Y", "O"]:
		kb.type_text(ch)
	assert_eq(edit.text, "Luck Y", "capital at each word start, cut at the max length")


func test_deck_names_and_styles() -> void:
	InputGlyphs.set_gamepad(true)
	assert_eq(InputGlyphs.key(&"bet_chip_next"), "RB")
	InputGlyphs.set_deck(true)
	assert_eq(InputGlyphs.style, &"deck")
	assert_eq(InputGlyphs.key(&"bet_chip_next"), "R1", "the Deck says R1")
	assert_eq(InputGlyphs.key(&"grab"), "R2")
	assert_eq(InputGlyphs.key(&"interact"), "X", "face buttons stay")
	assert_eq(InputGlyphs.pad_text("A / B / X / Y, LB"), "A / B / X / Y, L1")
	assert_eq(InputGlyphs.style_for("PS5 Controller"), &"playstation")
	assert_eq(InputGlyphs.style_for("DualSense Wireless Controller", true), &"playstation", "a PlayStation pad on a Deck keeps its names")
	assert_eq(InputGlyphs.style_for("Nintendo Switch Pro Controller"), &"nintendo")
	assert_eq(InputGlyphs.style_for("Xbox Series Controller"), &"xbox")
	assert_eq(InputGlyphs.style_for("Steam Virtual Gamepad", true), &"deck")
	InputGlyphs.style = &"playstation"
	assert_eq(InputGlyphs.key(&"jump"), "Cross")
	assert_eq(InputGlyphs.key(&"leaderboard"), "Triangle")


func test_minigame_controls_follow_the_pad_style() -> void:
	InputGlyphs.style = &"playstation"
	var rows: Array[Dictionary] = MinigameControls.rows(&"split_or_steal")
	assert_eq(rows[0]["pad"], "Cross")
	for id: StringName in [&"lonely_number", &"vote_race", &"spy", &"grab_your_hand"]:
		for r: Dictionary in MinigameControls.rows(id):
			if str(r["what"]).begins_with("Or type"):
				continue  # typing digits is an extra way, the grid is the pad's
			assert_ne(str(r["pad"]), "", "%s: '%s' works on a pad" % [id, r["what"]])


func test_deck_starts_fullscreen_unless_changed() -> void:
	Settings.on_deck = false
	var saved: Variant = Settings._cfg.get_value("video", "fullscreen") if Settings._cfg.has_section_key("video", "fullscreen") else null
	if Settings._cfg.has_section_key("video", "fullscreen"):
		Settings._cfg.erase_section_key("video", "fullscreen")
	assert_false(bool(Settings.get_value("video", "fullscreen")), "a PC starts windowed")
	Settings.on_deck = true
	assert_true(bool(Settings.get_value("video", "fullscreen")), "the Deck starts fullscreen (1280x800)")
	Settings._cfg.set_value("video", "fullscreen", false)
	assert_false(bool(Settings.get_value("video", "fullscreen")), "a choice in Settings wins")
	if saved == null:
		Settings._cfg.erase_section_key("video", "fullscreen")
	else:
		Settings._cfg.set_value("video", "fullscreen", saved)


func test_rps_duel_takes_the_dpad() -> void:
	var panel := RpsDuelPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	var picks: Array[int] = []
	panel.picked.connect(func(c: int) -> void: picks.append(c))
	InputGlyphs.set_gamepad(true)
	panel.show_duel({"duel": 1, "stake": 50, "left": 8.0}, "Bert")
	assert_true(panel.badges[1]._key_text().begins_with("D-pad"), "the cards show the d-pad")
	var ic := ItemController.new(null)
	ic.duel_panel = panel
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_DPAD_RIGHT
	ev.pressed = true
	assert_true(ic._duel_input(ev), "the d-pad picks in the duel (the router is in MENU mode then)")
	assert_eq(picks, [2] as Array[int], "right = scissors")
	ic.free()


func test_shop_offers_and_slots_take_focus() -> void:
	var b := GoldPlusButton.make()
	assert_eq(b.focus_mode, Control.FOCUS_ALL, "the Gold + is reachable")
	b.free()
	var src: String = FileAccess.get_file_as_string("res://ui/menus/cosmetics_panel.gd")
	assert_false("b.focus_mode = Control.FOCUS_NONE" in src, "no shop button is mouse-only")


func test_grab_your_hand_dpad_steps_through_the_hand() -> void:
	var stage := GrabYourHandStage.new()
	stage.hands = {1: [Card.make(2, 0), Card.make(9, 1), Card.make(12, 2)]}
	stage.local_id = 1
	stage.going = true
	add_child_autofree(stage)
	stage.selected = 0
	stage.step_slot(1)
	assert_eq(stage.selected, 1)
	stage.step_slot(-1)
	stage.step_slot(-1)
	assert_eq(stage.selected, 2, "wraps round")
