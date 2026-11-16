extends GutTest
## The item bar (held slot, name + description flash, the two-button choice), the Rock Paper
## Scissors duel screen.

var root: Control
var bar: ItemBar


func before_each() -> void:
	root = Control.new()
	root.size = Vector2(1920, 1080)
	add_child_autofree(root)
	bar = ItemBar.new()
	bar.size = Vector2(1920, 600)
	root.add_child(bar)
	await wait_process_frames(2)


func test_nothing_is_held_until_a_slot_is_picked() -> void:
	bar.set_inventory([&"lucky_clover", &"black_cat"])
	assert_eq(bar.selected, -1)
	assert_eq(bar.selected_item(), &"")
	assert_false(bar.keys_label.visible, "no key line with empty hands")
	assert_false(bar.selection_panel.visible)


func test_picking_flashes_name_description_and_how_to_use() -> void:
	bar.set_inventory([&"lucky_clover", &"black_cat"])
	bar.set_held(1)
	assert_eq(bar.selected_item(), &"black_cat")
	assert_true(bar.selection_panel.visible)
	assert_eq(bar.selection_name.text, "Black Cat")
	assert_eq(bar.selection_desc.text, RewardPanel.item_description(&"black_cat"), "the whole description")
	assert_ne(bar.selection_desc.text, "")
	assert_string_contains(bar.selection_tag.text, "ON OTHERS")
	assert_string_contains(bar.selection_tag.text, "45 s")
	assert_string_contains(bar.selection_use.text, "look at a player")
	assert_true(bar.keys_label.visible, "use / put away keys over the slots")
	await wait_seconds(ItemBar.SELECTION_SECONDS + 0.3)
	assert_false(bar.selection_panel.visible, "gone after a moment")
	bar.set_held(-1)
	assert_eq(bar.selected, -1)
	assert_false(bar.keys_label.visible)


func test_slots_show_models_and_only_the_held_name() -> void:
	bar.set_inventory([&"lucky_clover", &"black_cat"])
	assert_eq(bar.slot_item(0), &"lucky_clover")
	assert_eq(bar.slot_item(1), &"black_cat")
	assert_eq(bar.slot_item(2), &"")
	assert_not_null(bar.slot_icons[0].texture, "a picture of the model, not a name")
	assert_null(bar.slot_icons[2].texture, "empty slot")
	for n: Label in bar.slot_names:
		assert_eq(n.text, "", "no names while nothing is held")
	bar.set_held(1)
	assert_eq(bar.slot_names[1].text, "Black Cat", "the held one shows its name")
	assert_eq(bar.slot_names[0].text, "")
	assert_gt(bar.slots[1].custom_minimum_size.x, bar.slots[0].custom_minimum_size.x, "the held slot is bigger")


func test_new_item_gets_its_own_card() -> void:
	bar.set_inventory([&"lucky_clover"])
	assert_true(bar.pickup_panel.visible, "NEW ITEM card")
	assert_eq(bar.pickup_name.text, "Lucky Clover")
	assert_eq(bar.pickup_desc.text, RewardPanel.item_description(&"lucky_clover"))
	assert_string_contains(bar.pickup_use.text, "[1]")
	bar.set_inventory([&"lucky_clover", &"mirror", &"black_cat"])
	assert_eq(bar.pickup_item, &"lucky_clover", "one card at a time")
	assert_eq(bar.pickup_queue, [&"mirror", &"black_cat"] as Array[StringName])
	bar.set_held(0)
	assert_eq(bar.pickup_item, &"mirror", "taking it out skips its card")
	await wait_seconds(ItemBar.SELECTION_SECONDS + 0.2)
	assert_true(bar.pickup_panel.visible, "the next card shows once the flash is gone")
	await wait_seconds(ItemBar.PICKUP_SECONDS + 0.2)
	assert_eq(bar.pickup_item, &"black_cat")
	bar.set_inventory([&"mirror", &"black_cat"])
	assert_eq(bar.pickup_queue.size(), 0, "using one is no new item")


func test_new_items_counts_copies() -> void:
	assert_eq(ItemBar.new_items([&"black_cat"], [&"black_cat", &"black_cat"]), [&"black_cat"] as Array[StringName])
	assert_eq(ItemBar.new_items([&"a", &"b"], [&"b"]), [] as Array[StringName])


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


func test_used_item_takes_its_cards_with_it() -> void:
	# Patrick: "The info of old items gets stuck on the screen".
	bar.set_inventory([&"lucky_clover", &"black_cat"])
	bar.set_held(0)
	assert_true(bar.selection_panel.visible)
	bar.set_inventory([&"black_cat"])  # the clover was used: the slots shift
	assert_false(bar.selection_panel.visible, "no card for an item that is gone")
	bar.set_held(0)
	bar.toggle_info()
	assert_true(bar.info_panel.visible)
	bar.set_inventory([])
	assert_false(bar.info_panel.visible, "the I card goes with its item")


func test_info_card_follows_the_hand_on_scroll() -> void:
	bar.set_inventory([&"lucky_clover", &"black_cat"])
	bar.set_held(0)
	bar.toggle_info()
	bar.set_held(1)
	assert_true(bar.info_panel.visible)
	assert_eq(bar.info_name.text, "Black Cat", "the card shows the item now in the hand")
	assert_false(bar.selection_panel.visible, "no second card on top")
	bar.set_held(-1)
	assert_false(bar.info_panel.visible, "put away: card gone")


func test_new_item_card_dropped_when_the_item_is_gone() -> void:
	bar.set_inventory([&"lucky_clover", &"mirror", &"black_cat"])
	assert_eq(bar.pickup_item, &"lucky_clover")
	bar.set_inventory([&"black_cat"])  # used / stolen before its card came up
	assert_eq(bar.pickup_item, &"black_cat", "the gone ones are skipped")
	assert_eq(bar.pickup_queue.size(), 0)
	bar.set_inventory([])
	assert_eq(bar.pickup_item, &"")
	assert_false(bar.pickup_panel.visible)


func test_hidden_hud_clears_the_cards() -> void:
	bar.set_inventory([&"lucky_clover", &"mirror"])
	bar.set_held(0)
	bar.toggle_info()
	root.visible = false  # a minigame / the rewards take the screen
	assert_false(bar.info_panel.visible)
	assert_false(bar.selection_panel.visible)
	assert_false(bar.pickup_panel.visible)
	assert_eq(bar.pickup_queue.size(), 0)
	root.visible = true
	await wait_process_frames(2)
	assert_false(bar.info_panel.visible, "nothing old comes back after the minigame")
	assert_false(bar.pickup_panel.visible)


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
	assert_true(flash.position.x >= bar.slots[2].get_global_rect().end.x, "the card sits right of the slots")
	assert_almost_eq(flash.end.y, bar.slots[2].get_global_rect().end.y, 2.0, "bottom level with the slots")
	bar.set_private({"luck": 2.0})
	await wait_process_frames(2)
	assert_true(bar.luck_panel.visible)
	assert_true(bar.selection_panel.get_global_rect().position.x >= bar.luck_panel.get_global_rect().end.x, "and right of the luck plaque")
	assert_true(bar.luck_panel.get_global_rect().position.x >= bar.slots[2].get_global_rect().end.x, "the plaque is right of the slots")


func test_luck_plaque_shows_percent_and_streak() -> void:
	bar.set_private({"luck": 0.0})
	assert_false(bar.luck_panel.visible, "no luck, no plaque")
	bar.set_private({"luck": 2.0})
	assert_true(bar.luck_panel.visible)
	assert_eq(bar.luck_value.text, "+24%")
	assert_eq(bar.luck_label.text, "LUCKY")
	assert_false(bar.luck_streak.visible)
	bar.set_private({"luck": 0.75, "streak": 0.75})
	assert_eq(bar.luck_value.text, "+9%")
	assert_string_contains(bar.luck_streak.text, "+9%")
	bar.set_private({"luck": -3.0})
	assert_eq(bar.luck_value.text, "−36%")
	assert_eq(bar.luck_label.text, "CURSED")


func test_duel_screen_picks_and_shows_the_result() -> void:
	var panel := RpsDuelPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	var got: Array[int] = []
	panel.picked.connect(func(c: int) -> void: got.append(c))
	panel.show_duel({"duel": 4, "a": 2, "b": 1, "stake": 120, "state": &"pick", "left": 7.2, "picked": false}, "Anna")
	assert_true(panel.is_open())
	assert_string_contains(panel.vs_label.text, "ANNA")
	assert_string_contains(panel.stake_label.text, "$120")
	assert_eq(panel.timer_label.text, "8")
	panel.buttons[0].pressed.emit()
	assert_eq(got, [0] as Array[int])
	panel.choose(1)
	assert_eq(got, [0] as Array[int], "one pick")
	assert_true(panel.buttons[2].disabled)
	panel.show_result("rock", "scissors", 1, 120, false, "Anna")
	assert_string_contains(panel.verdict_label.text, "WIN  $120")
	assert_true(panel.reveal_row.visible, "the face-off shows both hands")
	assert_eq(panel.reveal_mine.kind, RpsHandIcon.Kind.ROCK)
	assert_eq(panel.reveal_theirs.kind, RpsHandIcon.Kind.SCISSORS)
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
	assert_string_contains(panel.verdict_label.text, "TIE")
	assert_true(panel.cards_row.visible, "the cards stay up for the replay")
	assert_false(panel.buttons[0].disabled, "pick again")
	assert_true(panel.is_open())


func test_key_line_drops_e_while_e_belongs_to_something_in_reach() -> void:
	if InputGlyphs.gamepad:
		pass_test("keyboard only")
		return
	bar.set_inventory([&"scissors"])
	bar.set_held(0)
	assert_true(bar.keys_label.text.contains("E"), "E uses the item with nothing in reach")
	bar.set_e_taken(true)
	assert_false(bar.keys_label.text.contains("E]"), "the megaphone / table owns E now")
	assert_true(bar.keys_label.text.contains("LMB"))
	bar.set_e_taken(false)
	assert_true(bar.keys_label.text.contains("E"))
