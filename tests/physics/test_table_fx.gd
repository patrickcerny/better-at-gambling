extends GutTest
## M7 table animations and win/lose VFX: nothing is built headless, effects free themselves when
## they finish, chips slide on and off the felt, the roulette ball lands in the server's number,
## slot reels stop one by one, hit-stop never sticks, Last Call dims the room and restores it.


func after_each() -> void:
	Vfx.force_enabled = false
	Engine.time_scale = 1.0


func _station(st: StationBase) -> StationBase:
	add_child_autofree(st)
	await wait_process_frames(1)
	return st


func _fx_world() -> Node3D:
	var w := Node3D.new()
	add_child_autofree(w)
	return w


func test_nothing_is_built_headless() -> void:
	assert_false(Vfx.enabled(), "the test runner is headless")
	var w: Node3D = _fx_world()
	assert_null(WinFx.coin_burst(w, Vector3.ZERO))
	assert_null(WinFx.gold_burst(w, Vector3.ZERO))
	assert_null(WinFx.sad_puff(w, Vector3.ZERO))
	assert_null(WinFx.money_delta(w, Vector3.ZERO, 120))
	assert_eq(w.get_child_count(), 0)
	var rs: RouletteStation = await _station(RouletteStation.new()) as RouletteStation
	assert_null(rs.wheel_fx, "no wheel animation on a server")
	assert_null(rs.get_node_or_null(^"LayoutPrint"))
	var ss: SlotsStation = await _station(SlotsStation.new()) as SlotsStation
	assert_null(ss.reels_fx)
	rs.set_hot(true)
	assert_null(rs.hot_fx, "hot table fire is client only")
	assert_true(rs.hot_marker.visible, "the arrow still shows")
	var fx := TableFx.new()
	add_child_autofree(fx)
	fx.setup({&"r": rs}, func(_p: int) -> PlayerAvatar: return null, 1, null, w)
	fx.on_event({"type": &"bet_placed", "player": 1, "station": &"r", "amount": 50, "details": {"type": &"red", "value": 0}})
	assert_eq(_stacks(rs), 0)


func test_effects_free_themselves_when_done() -> void:
	Vfx.force_enabled = true
	var w: Node3D = _fx_world()
	assert_not_null(WinFx.coin_burst(w, Vector3.ZERO))
	assert_not_null(WinFx.gold_burst(w, Vector3(1, 0, 0)))
	assert_not_null(WinFx.sad_puff(w, Vector3(2, 0, 0)))
	assert_not_null(WinFx.money_delta(w, Vector3(0, 2, 0), -50))
	assert_eq(WinFx.money_delta(w, Vector3.ZERO, 0), null, "no delta for a push")
	assert_eq(w.get_child_count(), 4)
	await wait_seconds(2.4)
	assert_eq(w.get_child_count(), 0, "every effect freed itself")


func test_floating_delta_is_green_for_wins_red_for_losses() -> void:
	Vfx.force_enabled = true
	var w: Node3D = _fx_world()
	var win: Label3D = WinFx.money_delta(w, Vector3.ZERO, 1200)
	var loss: Label3D = WinFx.money_delta(w, Vector3.ZERO, -50)
	assert_eq(win.text, "+$1,200")
	assert_eq(loss.text, "-$50")
	assert_eq(win.modulate, Palette.MONEY_GREEN)
	assert_eq(loss.modulate, Palette.LOSS_RED)


func test_chips_slide_on_and_off_the_felt() -> void:
	Vfx.force_enabled = true
	var w: Node3D = _fx_world()
	var rs: RouletteStation = await _station(RouletteStation.new()) as RouletteStation
	var fx := TableFx.new()
	add_child_autofree(fx)
	fx.setup({&"r": rs}, func(_p: int) -> PlayerAvatar: return null, 1, null, w)
	fx.on_event({"type": &"bet_placed", "player": 1, "station": &"r", "amount": 50, "details": {"game": "roulette", "type": &"straight", "value": 17}})
	fx.on_event({"type": &"bet_placed", "player": 2, "station": &"r", "amount": 100, "details": {"game": "roulette", "type": &"red", "value": 0}})
	assert_eq(_stacks(rs), 2, "a stack per bet")
	await wait_seconds(0.6)
	var spot: Vector3 = rs.to_global(RouletteStation.bet_spot(&"straight", 17))
	var on_spot: bool = false
	for c: Node in rs.get_children():
		if c is ChipStack and (c as Node3D).global_position.distance_to(spot) < 0.1:
			on_spot = true
	assert_true(on_spot, "the straight bet sits on its number")
	fx.on_event({"type": &"roulette_spin_started", "station": &"r"})
	fx.on_event({"type": &"roulette_result", "station": &"r", "number": 17})
	fx.on_event({"type": &"round_result", "station": &"r", "player": 1, "stake": 50, "returned": 1800, "net": 1750, "details": {"type": &"straight", "value": 17, "number": 17}})
	fx.on_event({"type": &"round_result", "station": &"r", "player": 2, "stake": 100, "returned": 0, "net": -100, "details": {"type": &"red", "value": 0, "number": 17}})
	assert_eq(_stacks(rs), 2, "chips wait for the ball")
	await wait_seconds(RouletteWheelFx.DROP_TIME + 1.6)
	assert_eq(_stacks(rs), 0, "paid out and raked in, then freed")
	assert_eq(rs.wheel_fx.number_under_ball(), 17, "the ball rests in the server's pocket")
	await wait_seconds(1.6)
	assert_eq(w.get_child_count(), 0, "win and loss effects freed")


func test_ball_lands_in_every_pocket() -> void:
	Vfx.force_enabled = true
	var rs: RouletteStation = await _station(RouletteStation.new()) as RouletteStation
	for n: int in [0, 32, 26, 5, 36]:
		rs.start_spin(0.3)
		await wait_seconds(0.1)
		var t: float = rs.land(n)
		assert_almost_eq(t, RouletteWheelFx.DROP_TIME, 0.001)
		assert_eq(rs.wheel_fx.number_under_ball(), -1, "still rolling")
		await wait_seconds(t + 0.1)
		assert_eq(rs.wheel_fx.number_under_ball(), n)
		var ball: Vector3 = rs.wheel_fx.ball.position
		assert_almost_eq(Vector2(ball.x, ball.z).length(), RouletteWheelFx.POCKET_R, 0.01, "in the pocket ring")


func test_slot_reels_stop_one_after_another() -> void:
	Vfx.force_enabled = true
	var ss: SlotsStation = await _station(SlotsStation.new()) as SlotsStation
	ss.start_spin()
	await wait_process_frames(2)
	assert_true(ss.reels_fx.is_spinning())
	var t: float = ss.stop_on([4, 4, 4])
	assert_gt(t, SlotReelsFx.STAGGER * 2.0)
	await wait_seconds(0.12 + SlotReelsFx.STAGGER * 0.5)
	assert_false(ss.reels_fx._spinning[0], "left reel stopped")
	assert_true(ss.reels_fx._spinning[2], "right reel still turning")
	await wait_seconds(t)
	assert_false(ss.reels_fx.is_spinning())
	for l: Label3D in ss.reels_fx.reels:
		assert_eq(l.text, SlotReelsFx.SYMBOL_TEXT[&"seven"])


func test_hot_table_fire_turns_on_and_off() -> void:
	Vfx.force_enabled = true
	var st: StationBase = await _station(BlackjackStation.new())
	st.set_hot(true)
	assert_not_null(st.hot_fx)
	assert_true(st.hot_fx.embers.emitting)
	await wait_seconds(0.7)
	assert_gt(st.hot_fx.spot.light_energy, 5.0, "warm spotlight on")
	st.set_hot(false)
	assert_false(st.hot_fx.embers.emitting)
	await wait_seconds(0.7)
	assert_false(st.hot_fx.visible)
	assert_false(st.hot_marker.visible)


func test_hit_stop_slows_then_restores_time() -> void:
	Vfx.force_enabled = true
	var j := ScreenJuice.new()
	add_child_autofree(j)
	j.hit_stop(0.05, 0.1)
	assert_almost_eq(Engine.time_scale, 0.1, 0.001)
	assert_almost_eq(ScreenJuice.unscaled(0.01), 0.1, 0.0001, "the practice server keeps real time")
	var until: int = Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < until and Engine.time_scale < 1.0:
		await wait_process_frames(1)
	assert_eq(Engine.time_scale, 1.0)
	assert_false(j.hit_stopping())


func test_hit_stop_and_shake_do_nothing_headless() -> void:
	var j := ScreenJuice.new()
	add_child_autofree(j)
	j.hit_stop()
	j.shake(1.0)
	assert_eq(Engine.time_scale, 1.0)
	assert_eq(j.trauma, 0.0)


func test_freed_juice_never_leaves_time_slowed() -> void:
	Vfx.force_enabled = true
	var j := ScreenJuice.new()
	add_child(j)
	j.hit_stop(5.0)
	j.free()
	assert_eq(Engine.time_scale, 1.0)


func test_last_call_dims_the_room_and_restores_it() -> void:
	Vfx.force_enabled = true
	var map := Node3D.new()
	add_child_autofree(map)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.ambient_light_energy = 0.4
	map.add_child(we)
	var lamp := OmniLight3D.new()
	lamp.light_energy = 3.0
	map.add_child(lamp)
	var st: StationBase = await _station(SlotsStation.new())
	var state := ClientMatchState.new()
	var lc := LastCallLighting.new()
	lc.setup(state, map, {&"s": st})
	add_child_autofree(lc)
	state.last_call = true
	await wait_seconds(LastCallLighting.FADE + 0.3)
	assert_almost_eq(lamp.light_energy, 3.0 * LastCallLighting.DIM, 0.01)
	assert_almost_eq(we.environment.ambient_light_energy, 0.4 * LastCallLighting.DIM, 0.01)
	assert_eq(lc.spots.size(), 1)
	assert_gt(lc.spots[0].light_energy, 1.0)
	assert_eq(Audio.mood, &"last_call")
	state.last_call = false
	await wait_seconds(LastCallLighting.FADE + 0.3)
	assert_almost_eq(lamp.light_energy, 3.0, 0.01)
	assert_almost_eq(we.environment.ambient_light_energy, 0.4, 0.01)
	assert_eq(Audio.mood, &"")


func _stacks(parent: Node) -> int:
	var n: int = 0
	for c: Node in parent.get_children():
		if c is ChipStack and not c.is_queued_for_deletion():
			n += 1
	return n
