extends GutTest
## The horse race table on a client: the four miniatures leave the gate together, run the seeded
## race the server ran, and the first nose over the painted line is the winner the server paid.
## Chips go on the backed horse's pad, and a seat's camera sees the whole track.

var view: SubViewport
var hr: HorseRaceStation


func before_each() -> void:
	Vfx.force_enabled = true
	view = SubViewport.new()
	view.size = Vector2i(1920, 1080)
	add_child_autofree(view)
	hr = HorseRaceStation.new()
	view.add_child(hr)
	await wait_process_frames(1)


func after_each() -> void:
	Vfx.force_enabled = false


func _nose_x(lane: int) -> float:
	return hr.horses[lane].position.x - HorseModel.NOSE_Z * HorseRaceStation.HORSE_SCALE


func test_four_horses_wait_in_their_lanes_at_the_gate() -> void:
	assert_eq(hr.horses.size(), 4)
	assert_eq(hr.gates.size(), 4)
	for i: int in 4:
		assert_almost_eq(_nose_x(i), HorseRaceStation.START_X, 0.001, "horse %d at the gate" % i)
		assert_almost_eq(hr.horses[i].position.z, HorseRaceStation.lane_z(i), 0.001)
		var z: float = HorseRaceStation.lane_z(i)
		assert_between(z, HorseRaceStation.TRACK_Z_FAR + 0.15, HorseRaceStation.TRACK_Z_NEAR - 0.15, "lane %d on the turf" % i)
	hr.set_names(["Neigh Sayer", "Hay Fever", "Oat Couture", "Mane Event"])
	assert_string_contains(hr.plate_labels[2].text.to_upper(), "OAT COUTURE", "the lane plate carries the name")


func test_the_race_runs_gate_to_finish_and_the_server_winner_crosses_first() -> void:
	for seed_value: int in [7, 4242, 98765]:
		hr.reset_table()
		hr.start_race(seed_value, 0.0)
		var plan: Dictionary = HorseRaceLogic.simulate(seed_value)
		var w: int = int(plan["winner"])
		var wait: float = hr.finish(w, seed_value)
		assert_almost_eq(wait, float(plan["finish"][w]), 0.1, "the result waits for the winner on screen")
		assert_false(hr.winner_shown())
		var lead_changes: int = 0
		var last_lead: int = -1
		var galloping: int = 0
		while hr.race_t < float(plan["finish"][w]) - 0.06:
			hr._tick_race(0.05)
			var lead: int = hr.shown_order()[0]
			if last_lead >= 0 and lead != last_lead:
				lead_changes += 1
			last_lead = lead
			for i: int in 4:
				assert_true(_nose_x(i) < HorseRaceStation.FINISH_X + 0.001, "nobody over the line before the winner")
			if absf(hr.race_t - 4.0) < 0.03:
				for h: HorseModel in hr.horses:
					if h.target_gallop > 0.1:
						galloping += 1
		assert_eq(galloping, 4, "every horse gallops mid-race")
		hr._tick_race(0.1)
		assert_true(hr.winner_shown())
		assert_eq(hr.shown_order()[0], w, "seed %d: the server's winner is first on the table" % seed_value)
		assert_gt(_nose_x(w), HorseRaceStation.FINISH_X - 0.001, "its nose is over the line")
		gut.p("seed %d: winner %d, %d lead changes on screen" % [seed_value, w, lead_changes])


func test_late_joiner_catches_up_from_the_state() -> void:
	var seed_value: int = 31337
	var plan: Dictionary = HorseRaceLogic.simulate(seed_value)
	hr.show_state({"state": HorseRaceLogic.State.RACING, "race_seed": seed_value, "race_time": 4.0, "names": ["A", "B", "C", "D"]})
	assert_eq(hr.race_seed, seed_value)
	var expect: Array[float] = HorseRaceLogic.sample(plan, 4.0)
	for i: int in 4:
		assert_almost_eq(_nose_x(i), HorseRaceStation.track_x(expect[i]), 0.01, "lane %d where the server has it" % i)
	hr.show_state({"state": HorseRaceLogic.State.BETTING, "names": ["E", "F", "G", "H"]})
	assert_eq(hr.race_seed, -1, "a new round puts the field back in the gate")
	assert_almost_eq(_nose_x(0), HorseRaceStation.START_X, 0.001)


func test_seat_camera_sees_gate_finish_and_pads() -> void:
	var cam := Camera3D.new()
	cam.fov = 75.0
	view.add_child(cam)
	var rect := Rect2(Vector2.ZERO, Vector2(view.size))
	for seat: int in [0, 5]:
		cam.global_transform = hr.camera_for_seat(seat).global_transform
		var points: Array[Vector3] = [
			Vector3(HorseRaceStation.START_X, HorseRaceStation.TURF_Y, 0.0),
			Vector3(HorseRaceStation.FINISH_X, HorseRaceStation.TURF_Y, 0.0),
			HorseRaceStation.bet_spot(0),
			HorseRaceStation.bet_spot(3),
		]
		for p: Vector3 in points:
			var g: Vector3 = hr.to_global(p)
			assert_false(cam.is_position_behind(g), "seat %d faces %s" % [seat, p])
			assert_true(rect.has_point(cam.unproject_position(g)), "seat %d sees %s" % [seat, p])
	cam.free()


func test_chips_land_on_the_backed_horse_pad() -> void:
	var w := Node3D.new()
	view.add_child(w)
	var fx := TableFx.new()
	add_child_autofree(fx)
	fx.setup({&"h": hr}, func(_p: int) -> PlayerAvatar: return null, 1, null, w,
		func(pid: int) -> Color: return Palette.player_color(pid - 1), func(_sid: StringName) -> int: return 10)
	fx.on_event({"type": &"bet_placed", "player": 1, "station": &"h", "amount": 50, "details": {"game": "horse_race", "type": &"horse", "value": 2, "horse": 2}})
	fx.on_event({"type": &"bet_placed", "player": 2, "station": &"h", "amount": 20, "details": {"game": "horse_race", "type": &"horse", "value": 0, "horse": 0}})
	await wait_seconds(0.8)
	var on_pad: Array[int] = []
	for c: Node in hr.get_children():
		if not c is ChipStack:
			continue
		var p: Vector3 = (c as ChipStack).position
		for h: int in 4:
			var spot: Vector3 = HorseRaceStation.bet_spot(h)
			if absf(p.x - spot.x) < 0.2 and absf(p.z - spot.z) < 0.2:
				on_pad.append(h)
	on_pad.sort()
	assert_eq(on_pad, [0, 2] as Array[int], "one stack on each backed pad")
