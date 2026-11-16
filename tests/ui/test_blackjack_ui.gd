extends GutTest
## Blackjack panel after a split: the big number and the buttons name the hand being played (the
## server's `active`), switch to hand 2 when play moves on, and the status shows your own
## (extended) decision clock.

var root: Control
var ui: BlackjackUi


func before_each() -> void:
	root = Control.new()
	root.size = Vector2(1920, 1080)
	add_child_autofree(root)
	ui = (load("res://ui/stations/blackjack_ui.tscn") as PackedScene).instantiate()
	root.add_child(ui)
	ui.open(&"blackjack_1", 1, null)
	await wait_process_frames(2)


func _split_state(active: int, done: bool = false, clock: float = 14.0) -> Dictionary:
	var h: Dictionary = {"stake": 50, "cards": [Card.make(8, 0), Card.make(6, 1)], "done": done, "total": 14, "active": active, "first_done": active == 1 or done,
		"split": {"stake": 50, "cards": [Card.make(8, 2)] if active == 0 else [Card.make(8, 2), Card.make(13, 3)], "done": done, "total": 8 if active == 0 else 18}}
	if not done:
		h["clock"] = clock
	return {"state": BlackjackLogic.State.ACTING, "timer": 4.0, "seats": [1, -1, -1, -1], "dealer": [Card.make(6, 1)], "dealer_revealed": false, "hands": {1: h}}


func test_unsplit_hand_has_plain_buttons() -> void:
	ui.update_state({"state": BlackjackLogic.State.ACTING, "timer": 6.0, "seats": [1, -1, -1, -1], "dealer": [Card.make(6, 1)], "dealer_revealed": false,
		"hands": {1: {"stake": 50, "cards": [Card.make(8, 0), Card.make(8, 1)], "done": false, "total": 16, "can_split": true, "clock": 6.0}}}, {})
	assert_true(ui.hit.text.begins_with("HIT  "), ui.hit.text)
	assert_false(ui.hit.text.contains("HAND"))
	assert_true(ui.split_btn.visible)
	assert_eq(ui.status_label.text, "Your move  (6 s)")


func test_split_labels_and_buttons_follow_the_active_hand() -> void:
	ui.update_state(_split_state(0), {})
	assert_eq(ui.total_label.text, "HAND 1: 14")
	assert_string_contains(ui.hit.text, "HIT HAND 1")
	assert_string_contains(ui.stand.text, "STAND HAND 1")
	assert_string_contains(ui.double_btn.text, "DOUBLE HAND 1")
	assert_false(ui.double_btn.disabled, "two cards on hand 1: double allowed")
	assert_false(ui.split_btn.visible, "one split per round")
	assert_eq(ui.status_label.text, "Your move: hand 1 of 2  (14 s)", "your own extended clock, not the table's")
	var lines: PackedStringArray = ui.hand_label.text.split("\n")
	assert_true(lines[0].begins_with("» HAND 1"), lines[0])
	assert_true(lines[1].begins_with("HAND 2"), lines[1])
	# Play moves on to the second hand.
	ui.update_state(_split_state(1, false, 9.0), {})
	assert_eq(ui.total_label.text, "HAND 2: 18")
	assert_string_contains(ui.hit.text, "HIT HAND 2")
	assert_string_contains(ui.stand.text, "STAND HAND 2")
	assert_eq(ui.status_label.text, "Your move: hand 2 of 2  (9 s)")
	lines = ui.hand_label.text.split("\n")
	assert_true(lines[0].begins_with("HAND 1"), lines[0])
	assert_true(lines[1].begins_with("» HAND 2"), lines[1])


func test_split_done_shows_both_stakes_and_plain_buttons() -> void:
	ui.update_state(_split_state(1), {})
	ui.update_state(_split_state(1, true), {})
	assert_eq(ui.total_label.text, "SPLIT  $50 + $50")
	assert_false(ui.actions.visible)
	assert_false(ui.hit.text.contains("HAND"), "the buttons drop the hand once you are done")
	assert_false(ui.hand_label.text.contains("»"))


func test_split_panel_fits_on_screen() -> void:
	ui.update_state(_split_state(1), {})
	await wait_process_frames(2)
	assert_true(ui.panel.get_global_rect().size.x <= root.size.x, "the panel still fits on screen")
	assert_true(root.get_global_rect().encloses(ui.panel.get_global_rect()), "inside the screen")


func test_soft_hand_shows_both_totals_until_done() -> void:
	var st: Dictionary = {"state": BlackjackLogic.State.ACTING, "timer": 6.0, "seats": [1, -1, -1, -1], "dealer": [Card.make(1, 1)], "dealer_revealed": false,
		"hands": {1: {"stake": 50, "cards": [Card.make(1, 0), Card.make(6, 1)], "done": false, "total": 17, "can_split": false, "clock": 6.0}}}
	ui.update_state(st, {})
	assert_eq(ui.total_label.text, "7 / 17", "soft 17 reads both ways while you play it")
	assert_string_contains(ui.seat_labels[0].text, "7 / 17")
	st["hands"][1]["done"] = true
	ui.update_state(st, {})
	assert_eq(ui.total_label.text, "17", "stood: the best total only")


func test_bust_with_scissors_offers_the_cut() -> void:
	var cards: Array = [Card.make(10, 0), Card.make(6, 1), Card.make(10, 2)]
	ui.update_state({"state": BlackjackLogic.State.ACTING, "timer": 4.0, "seats": [1, -1, -1, -1], "dealer": [Card.make(9, 1)], "dealer_revealed": false,
		"hands": {1: {"stake": 50, "cards": cards, "done": false, "total": 26, "clock": 4.0, "rescue": true}}}, {"scissors": true})
	assert_true(ui.actions.visible)
	assert_true(ui.cut_btn.visible and not ui.cut_btn.disabled, "the cut is on offer")
	assert_false(ui.hit.visible, "no hitting a bust")
	assert_false(ui.double_btn.visible)
	assert_string_contains(ui.stand.text, "TAKE BUST")
	assert_string_contains(ui.status_label.text, "BUST!")
	# Cut: back to a normal hand.
	ui.update_state({"state": BlackjackLogic.State.ACTING, "timer": 6.0, "seats": [1, -1, -1, -1], "dealer": [Card.make(9, 1)], "dealer_revealed": false,
		"hands": {1: {"stake": 50, "cards": cards.slice(0, 2), "done": false, "total": 16, "clock": 6.0}}}, {})
	assert_true(ui.hit.visible)
	assert_true(ui.stand.text.begins_with("STAND"), ui.stand.text)
