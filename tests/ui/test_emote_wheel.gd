extends GutTest
## The emote wheel (G / D-pad down): seven pills with 6-7 at the top (Patrick: "add a 67 emote"),
## none overlapping its neighbours even when lit up, and pointing up on the stick then letting go
## sends 6-7 (the stick used to fall inside the mouse's 40 px dead zone and never picked anything).


func test_six_seven_tops_the_wheel_and_is_picked_by_pointing_up() -> void:
	var w := EmoteWheel.new()
	add_child_autofree(w)
	await wait_process_frames(1)
	assert_eq(w._pills.size(), Emotes.LIST.size())
	assert_eq(w._pills.size(), 7, "seven emotes")
	var top: Label = w._pills[0].get_child(0) as Label
	assert_string_contains(top.text, "6-7")
	assert_lt(w._pills[0].position.y, w._pills[1].position.y, "6-7 is the top pill")
	# Lit up, a pill grows by 12%: it still clears both neighbours.
	for i: int in w._pills.size():
		var a: PanelContainer = w._pills[i]
		var b: PanelContainer = w._pills[(i + 1) % w._pills.size()]
		var ra: Rect2 = Rect2(a.position - a.size * 0.06, a.size * 1.12)
		var rb: Rect2 = Rect2(b.position, b.size)
		assert_false(ra.intersects(rb), "pill %d clears pill %d" % [i, (i + 1) % w._pills.size()])
	var got: Array[StringName] = []
	w.picked.connect(func(id: StringName) -> void: got.append(id))
	w.open()
	Input.action_press(&"look_up", 1.0)
	await wait_process_frames(2)
	Input.action_release(&"look_up")
	assert_eq(w.selected, 0, "the stick pointing up picks the top pill")
	w.close_and_pick()
	assert_eq(got, [&"six_seven"] as Array[StringName], "and letting go sends 6-7")
