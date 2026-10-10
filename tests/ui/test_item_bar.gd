extends GutTest
## The item bar (held slot, name + description flash, the two-button choice), the Rock Paper
## Scissors duel screen and the dealer tip button on the station panels.

var root: Control
var bar: ItemBar


func before_each() -> void:
	root = Control.new()
	root.size = Vector2(1920, 1080)
	add_child_autofree(root)
	bar = ItemBar.new()
	bar.size = Vector2(680, 400)
	root.add_child(bar)
	await wait_process_frames(2)


func test_nothing_is_held_until_a_slot_is_picked() -> void:
	bar.set_inventory([&"lucky_clover", &"black_cat"])
	assert_eq(bar.selected, -1)
	assert_eq(bar.selected_item(), &"")
	assert_false(bar.info_hint.visible, "no key line with empty hands")
	assert_false(bar.selection_panel.visible)


func test_picking_flashes_name_and_one_line_description() -> void:
	bar.set_inventory([&"lucky_clover", &"black_cat"])
	bar.set_held(1)
	assert_eq(bar.selected_item(), &"black_cat")
	assert_true(bar.selection_panel.visible)
	assert_eq(bar.selection_name.text, "Black Cat")
	assert_eq(bar.selection_desc.text, ItemBar.short_description(&"black_cat"))
	assert_ne(bar.selection_desc.text, "")
	assert_true(bar.keys_label.visible, "use / put away keys over the slots")
	assert_true(bar.info_hint.visible, "i for info next to the slots")
	await wait_seconds(ItemBar.SELECTION_SECONDS + 0.3)
	assert_false(bar.selection_panel.visible, "gone after a moment")
	bar.set_held(-1)
	assert_eq(bar.selected, -1)
	assert_false(bar.info_hint.visible)
	assert_false(bar.keys_label.visible)


func test_short_description_is_the_first_sentence() -> void:
	assert_false(ItemBar.short_description(&"bouncer").contains(". "), "one line")
	assert_true(RewardPanel.item_description(&"bouncer").begins_with(ItemBar.short_description(&"bouncer").trim_suffix(".")))


func test_info_card_still_opens_on_the_held_item() -> void:
	bar.set_inventory([&"mirror"])
	bar.toggle_info()
	assert_false(bar.info_panel.visible, "empty hands: nothing to explain")
	bar.set_held(0)
	bar.toggle_info()
	assert_true(bar.info_panel.visible)
	assert_string_contains(bar.info_label.text, Registry.items[&"mirror"].description)
	assert_false(bar.selection_panel.visible, "the card replaces the flash")


func test_two_button_choice_reports_the_button() -> void:
	var got: Array[int] = []
	bar.choice_made.connect(func(i: int) -> void: got.append(i))
	bar.show_choice("Pickpocket: how deep?", ["SAFE", "GREEDY"] as Array[String])
	assert_true(bar.is_choice_open())
	assert_eq(bar.choice_buttons[1].text, "GREEDY")
	bar.choice_buttons[1].pressed.emit()
	assert_eq(got, [1] as Array[int])
	bar.hide_choice()
	assert_false(bar.is_choice_open())


func test_slots_do_not_overlap_the_flash() -> void:
	bar.set_inventory([&"lucky_clover", &"black_cat", &"bouncer"])
	bar.set_held(2)
	await wait_process_frames(3)
	var flash: Rect2 = bar.selection_panel.get_global_rect()
	assert_true(flash.end.y <= bar.slots[0].get_global_rect().position.y + 1.0, "flash sits above the slots")
	assert_true(flash.position.y >= bar.get_global_rect().position.y - 1.0, "inside the bar")


func test_tip_effect_reads_as_a_dealer_tip() -> void:
	assert_string_contains(ItemBar.effect_text({"item": ItemSystem.TIP_ID, "left": -1.0, "uses": 3}), "Dealer tip")


func test_duel_screen_picks_and_shows_the_result() -> void:
	var panel := RpsDuelPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	var got: Array[int] = []
	panel.picked.connect(func(c: int) -> void: got.append(c))
	panel.show_duel({"duel": 4, "a": 2, "b": 1, "stake": 120, "state": &"pick", "left": 7.2, "picked": false}, "Anna")
	assert_true(panel.is_open())
	assert_string_contains(panel.vs_label.text, "Anna")
	assert_string_contains(panel.vs_label.text, "$120")
	assert_eq(panel.timer_label.text, "8 s")
	panel.buttons[0].pressed.emit()
	assert_eq(got, [0] as Array[int])
	panel.choose(1)
	assert_eq(got, [0] as Array[int], "one pick")
	assert_true(panel.buttons[2].disabled)
	panel.show_result("rock", "scissors", 1, 120, false, "Anna")
	assert_string_contains(panel.status_label.text, "WIN $120")
	assert_true(panel.is_settling())
	await wait_seconds(RpsDuelPanel.RESULT_SECONDS + 0.3)
	assert_false(panel.is_open(), "closes by itself")


func test_duel_tie_lets_you_pick_again() -> void:
	var panel := RpsDuelPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	panel.show_duel({"duel": 1, "a": 1, "b": 2, "stake": 50, "left": 5.0, "picked": false}, "Bo")
	panel.choose(2)
	panel.show_result("scissors", "scissors", 0, 0, true, "Bo")
	assert_string_contains(panel.status_label.text, "Tie")
	assert_false(panel.buttons[0].disabled, "pick again")
	assert_true(panel.is_open())


func test_tip_button_only_at_tables_with_a_dealer() -> void:
	var st := ClientMatchState.new()
	st.stations[&"blackjack_1"] = {"game": &"blackjack", "state": 0, "seats": [1, -1, -1, -1], "hands": {}, "dealer": []}
	st.stations[&"slot_1"] = {"game": &"slots", "player": 1, "spinning": false, "line": [], "stake": 0}
	st.balances[1] = 1000
	var bj := BlackjackUi.new()
	root.add_child(bj)
	bj.open(&"blackjack_1", 1, st)
	var slots := SlotsUi.new()
	root.add_child(slots)
	slots.open(&"slot_1", 1, st)
	await wait_process_frames(2)
	assert_not_null(bj.tip_button, "blackjack has a tip jar")
	assert_string_contains(bj.tip_button.text, "$%d" % Registry.balance.tip_amount)
	assert_true(bj.tip_button.is_visible_in_tree())
	assert_null(slots.tip_button, "no dealer at a slot machine")
	var rl := RouletteUi.new()
	root.add_child(rl)
	await wait_process_frames(1)
	assert_not_null(rl.tip_button, "roulette has one too")
