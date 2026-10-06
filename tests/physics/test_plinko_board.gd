extends GutTest
## The Plinko machine: payouts written on the buckets match the payout table for every risk row,
## nothing visual is built on a headless server, and the dropped chip really lands (in the scene,
## frame by frame) in the slot the server picked, then clears itself away.


func after_each() -> void:
	Vfx.force_enabled = false


func _board() -> PlinkoStation:
	var st := PlinkoStation.new()
	st.station_id = &"plinko_t"
	add_child_autofree(st)
	await wait_process_frames(1)
	return st


func test_headless_server_builds_no_dressing() -> void:
	var st: PlinkoStation = await _board()
	assert_true(st.slot_labels.is_empty(), "no labels on a server")
	assert_null(st.pegs_parent, "no peg field on a server")
	assert_null(st.drop_chip(3, 1, Color.RED, 1.0), "no chips on a server")
	assert_eq(st.slot_xs.size(), PlinkoStation.SLOTS, "slot positions still exist for the fx")
	assert_not_null(st.get_node_or_null(^"Glass"), "the glass still keeps hands off the board")


func test_bucket_labels_match_the_payout_table() -> void:
	Vfx.force_enabled = true
	var st: PlinkoStation = await _board()
	assert_eq(st.slot_labels.size(), PlinkoStation.SLOTS)
	for risk: StringName in PlinkoLogic.RISKS:
		st.set_risk(risk)
		var mults: PackedFloat32Array = Registry.balance.plinko_multipliers(risk)
		for s: int in PlinkoStation.SLOTS:
			var l: Label3D = st.slot_labels[s]
			assert_eq(l.text, PlinkoStation.mult_text(mults[s]), "%s slot %d" % [risk, s])
			assert_almost_eq(l.position.x, st.slot_xs[s], 0.0001, "label sits under its slot")
		for t: Label3D in st.jackpot_tags:
			assert_eq(t.visible, risk == &"high", "jackpot chance marked on the High row only")
		assert_string_contains(st.risk_sign.text, String(risk).to_upper())
	assert_eq(PlinkoStation.mult_text(13.0), "×13")
	assert_eq(PlinkoStation.mult_text(0.5), "×0.5")


func test_dropped_chips_land_in_the_servers_slot_and_clear() -> void:
	Vfx.force_enabled = true
	var st: PlinkoStation = await _board()
	var chips: Array[PlinkoChip] = []
	var landed: Dictionary = {}
	for i: int in 6:
		var slot: int = [0, 12, 6, 3, 9, 1][i]
		var c: PlinkoChip = st.drop_chip(slot, 40 + i, Palette.CASINO_RED, 0.8, &"high")
		c.landed.connect(func(s: int) -> void: landed[i] = s)
		chips.append(c)
	var top: float = 0.0
	var max_x: float = 0.0
	for f: int in 40:
		await wait_physics_frames(1)
		for c: PlinkoChip in chips:
			if is_instance_valid(c):
				top = maxf(top, c.position.y)
				max_x = maxf(max_x, absf(c.position.x))
	await wait_seconds(0.9)
	for i: int in chips.size():
		assert_eq(landed.get(i, -1), chips[i].slot, "chip %d reported its landing" % i)
		assert_almost_eq(chips[i].position.x, st.slot_xs[chips[i].slot], 0.002, "chip %d in its slot" % i)
		assert_almost_eq(chips[i].position.y, PlinkoStation.FLOOR_Y + PlinkoStation.CHIP_R, 0.002)
	assert_lt(top, PlinkoStation.entry_y() + 0.001, "never above the funnel")
	assert_lt(max_x, PlinkoStation.BOARD_W * 0.5, "never outside the rails")
	await wait_seconds(PlinkoChip.LINGER + 0.8)
	for c: PlinkoChip in chips:
		assert_false(is_instance_valid(c), "chips fade away after resting")


func test_chip_touches_down_when_the_server_settles() -> void:
	Vfx.force_enabled = true
	var st: PlinkoStation = await _board()
	var c: PlinkoChip = st.drop_chip(4, 7, Palette.CASINO_RED, Registry.balance.plinko_flight_time, &"medium")
	assert_almost_eq(c.flight.land_time / c.rate, Registry.balance.plinko_flight_time, 0.01, "lands with the result")
	assert_eq(c.mult, Registry.balance.plinko_multipliers(&"medium")[4], "knows what it wins")
