extends GutTest
## Patrick's poly.pizza props on the stations: stools under every seat, cones while out of order,
## money piles beside Plinko once the jackpot is big, and skins replacing the bean.


func _station(st: StationBase) -> StationBase:
	add_child_autofree(st)
	await wait_process_frames(1)
	return st


func test_every_seat_has_a_stool_under_it() -> void:
	for st: StationBase in [BlackjackStation.new(), RouletteStation.new(), PlinkoStation.new(), SlotsStation.new()]:
		await _station(st)
		for seat: Node3D in st.seats:
			assert_almost_eq(seat.position.y, 0.5, 0.01, "%s seat sits on a stool" % st.game_id)
		var stools: int = 0
		for c: Node in st.get_children():
			if String(c.name).begins_with("Stool"):
				stools += 1
		assert_eq(stools, st.seats.size(), "%s has one stool per seat" % st.game_id)


func test_out_of_order_puts_cones_on_the_seats() -> void:
	var st: StationBase = await _station(BlackjackStation.new())
	st.set_out_of_order(30.0)
	assert_true(st.out_of_order_cones.visible)
	assert_eq(st.out_of_order_cones.get_child_count(), st.seats.size())
	st.set_out_of_order(0.0)
	assert_false(st.out_of_order_cones.visible)


func test_money_piles_grow_with_the_jackpot() -> void:
	var st: PlinkoStation = await _station(PlinkoStation.new()) as PlinkoStation
	st.set_jackpot(500, 500)
	assert_false(st._money_piles[0].visible, "seed jackpot: no money")
	st.set_jackpot(1600, 500)
	assert_true(st._money_piles[0].visible)
	assert_false(st._money_piles[1].visible)
	st.set_jackpot(6000, 500)
	assert_true(st._money_piles[1].visible)
	assert_gt(st._money_piles[0].scale.x, 1.0)


func test_skin_replaces_the_bean_and_back() -> void:
	var v := AvatarVisuals.new()
	add_child_autofree(v)
	await wait_process_frames(1)
	v.set_skin(&"king")
	assert_not_null(v.skin_root)
	assert_false(v.body.visible)
	v.update_motion(Vector3(2, 0, 0), true, 0.016)
	v.set_skin(&"bean")
	assert_null(v.skin_root)
	assert_true(v.body.visible)
