extends GutTest
## The HUD money counter counts up/down to the new balance and flashes green/red (M7).


func test_counts_up_to_the_new_balance_and_lands_exactly() -> void:
	var c := MoneyCounter.new()
	c.snap(1000)
	assert_eq(c.step(0.016), 1000)
	c.set_target(1450)
	var first: int = c.step(0.05)
	assert_gt(first, 1000, "starts moving at once")
	assert_lt(first, 1450, "but does not jump")
	var last: int = first
	for i: int in 200:
		var v: int = c.step(0.016)
		assert_true(v >= last, "never counts backwards on the way up")
		last = v
	assert_eq(last, 1450)
	assert_false(c.is_counting())


func test_counts_down_and_flashes_red() -> void:
	var c := MoneyCounter.new()
	c.snap(500)
	c.set_target(450)
	c.step(0.016)
	assert_eq(c.direction, -1)
	var t: Color = c.tint(Palette.CREAM)
	assert_gt(t.r, t.g, "red tint while counting down")
	for i: int in 100:
		c.step(0.016)
	assert_eq(int(c.displayed), 450)
	assert_eq(c.tint(Palette.CREAM), Palette.CREAM, "flash fades out")
	assert_almost_eq(c.punch(), 1.0, 0.001)


func test_win_flashes_green_and_punches() -> void:
	var c := MoneyCounter.new()
	c.snap(100)
	c.set_target(400)
	c.step(0.016)
	var t: Color = c.tint(Palette.CREAM)
	assert_gt(t.g, t.b, "green tint")
	assert_gt(c.punch(), 1.05)


func test_bigger_changes_take_longer_but_stay_bounded() -> void:
	var small := MoneyCounter.new()
	small.snap(0)
	small.set_target(10)
	var big := MoneyCounter.new()
	big.snap(0)
	big.set_target(100000)
	assert_gt(big._duration, small._duration)
	assert_true(big._duration <= MoneyCounter.MAX_TIME)


func test_retargeting_mid_count_continues_from_the_shown_value() -> void:
	var c := MoneyCounter.new()
	c.snap(0)
	c.set_target(1000)
	var mid: int = c.step(0.2)
	c.set_target(500)
	var next: int = c.step(0.0)
	assert_eq(next, mid, "no jump when the target changes")
	for i: int in 100:
		c.step(0.016)
	assert_eq(int(c.displayed), 500)


func test_hud_counter_follows_the_balance() -> void:
	var state := ClientMatchState.new()
	state.balances[1] = 1000
	var hud: Hud = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate()
	add_child_autofree(hud)
	hud.bind(state, 1)
	await wait_process_frames(2)
	assert_eq(hud.money_label.text, "$1,000")
	state.balances[1] = 1200
	await wait_process_frames(3)
	assert_ne(hud.money_label.text, "$1,200", "counts rather than jumps")
	assert_true(hud.money_label.has_theme_color_override(&"font_color"), "flashes while counting")
	await wait_seconds(1.6)
	assert_eq(hud.money_label.text, "$1,200")
	assert_false(hud.money_label.has_theme_color_override(&"font_color"), "back to cream")
