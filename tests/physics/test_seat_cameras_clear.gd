extends GutTest
## Patrick: "on roulette you can sit on each other". Every roulette seat shared one camera hanging
## 0.4 m behind stool 1, so whoever sat anywhere at the table looked out of stool 1's bean. For
## every table: no seat's view may start inside (or right against) the bean on another seat.

var stations: Array[Script] = [RouletteStation, BlackjackStation, HorseRaceStation, CrapsStation, WheelStation,
	HiLoStation, HoldemStation, BaccaratStation, PlinkoStation, SlotsStation, ScratchStation, SwordTapperStation]
## A seated bean: a body this tall above its seat, this wide, plus a little air for the near plane.
const BEAN_HEIGHT: float = AvatarVisuals.BODY_HEIGHT
const CLEARANCE: float = AvatarVisuals.BODY_RADIUS + 0.15


func _distance_to_bean(eye: Vector3, seat: Vector3) -> float:
	var y: float = clampf(eye.y, seat.y, seat.y + BEAN_HEIGHT)
	return eye.distance_to(Vector3(seat.x, y, seat.z))


func test_no_seat_view_starts_inside_another_seats_bean() -> void:
	for script: Script in stations:
		var st: StationBase = script.new()
		add_child_autofree(st)
		await wait_process_frames(1)
		for i: int in st.seats.size():
			var eye: Vector3 = st.camera_for_seat(i).global_position
			for j: int in st.seats.size():
				if j == i:
					continue
				var d: float = _distance_to_bean(eye, st.seat_position(j))
				assert_gt(d, CLEARANCE, "%s seat %d's view starts %.2f m from the bean on seat %d" % [st.game_id, i, d, j])


func test_every_roulette_seat_has_its_own_view() -> void:
	var rs := RouletteStation.new()
	add_child_autofree(rs)
	await wait_process_frames(1)
	assert_eq(rs.seat_cameras.size(), rs.seats.size())
	for i: int in rs.seats.size():
		var eye: Vector3 = rs.to_local(rs.camera_for_seat(i).global_position)
		var seat: Vector3 = rs.to_local(rs.seat_position(i))
		assert_eq(signf(eye.z), signf(seat.z), "seat %d looks from its own side of the table" % i)
		assert_almost_eq(eye.x, seat.x, 0.01, "seat %d's eye is over its own stool" % i)
