extends GutTest
## Patrick: "When you emote, you go into thrid person": our own emote swings the camera round to
## a closer three-quarter view from the front for the emote's length, standing or seated (where it
## lifts off the station view, out across the table), and then goes back to the view we had:
## first person stays first person, third stays third. Other players' emotes leave it alone, a
## ragdoll takes over at once, and the camera toggle hands the view back to the player.

const STEP: float = 1.0 / 60.0

var _floor: StaticBody3D


func before_each() -> void:
	_floor = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	cs.shape = box
	cs.position.y = -0.5
	_floor.add_child(cs)
	add_child_autofree(_floor)


## A local player (with a camera) facing -Z at the origin.
func _local() -> PlayerAvatar:
	var a := PlayerAvatar.new()
	a.is_local = true
	add_child_autofree(a)
	a.teleport(Vector3.ZERO, 0.0)
	await wait_physics_frames(3)
	return a


func _cam_pos(a: PlayerAvatar) -> Vector3:
	return a.cam.camera.global_position


## True when the camera is in front of the body (on the side it faces) looking back at it.
func _faces_us(a: PlayerAvatar) -> bool:
	var to_cam: Vector3 = _cam_pos(a) - a.global_position
	to_cam.y = 0.0
	var fwd: Vector3 = -a.global_basis.z
	var look: Vector3 = -a.cam.camera.global_basis.z
	return to_cam.normalized().dot(fwd) > 0.6 and look.dot(-to_cam.normalized()) > 0.6


func test_first_person_swings_round_to_watch_the_emote_and_back() -> void:
	var a: PlayerAvatar = await _local()
	assert_eq(a.cam.mode, PlayerCamera.Mode.FIRST)
	var eye: Vector3 = _cam_pos(a)
	assert_almost_eq(eye.distance_to(a.global_position + Vector3(0, PlayerCamera.EYE_HEIGHT, 0)), 0.0, 0.05, "first person at the eyes")
	assert_false(a.visuals.visible, "first person: our bean is hidden")
	assert_true(a.play_emote(&"six_seven"))
	await wait_seconds(0.6)
	assert_true(a.cam.emote_view)
	assert_almost_eq(a.cam.emote_blend, 1.0, 0.001, "fully swung round")
	assert_true(_faces_us(a), "in front of us, looking back: %s" % _cam_pos(a))
	var dist: float = Vector2(_cam_pos(a).x, _cam_pos(a).z).distance_to(Vector2(a.global_position.x, a.global_position.z))
	assert_almost_eq(dist, PlayerCamera.EMOTE_DISTANCE, 0.05, "a little closer than third person")
	assert_lt(dist, PlayerCamera.THIRD_DISTANCE)
	assert_gt(absf(_cam_pos(a).x - a.global_position.x), 0.5, "three-quarter, not dead ahead")
	assert_true(a.visuals.visible, "we see ourselves do it")
	assert_eq(a.cam.mode, PlayerCamera.Mode.FIRST, "the player's choice is kept underneath")
	await wait_seconds(Emotes.length(&"six_seven") - 0.6 + 0.6)
	assert_false(a.visuals.is_emoting())
	assert_false(a.cam.emote_view)
	assert_almost_eq(a.cam.emote_blend, 0.0, 0.001)
	assert_almost_eq(_cam_pos(a).distance_to(eye), 0.0, 0.05, "back in first person at the eyes")
	assert_false(a.visuals.visible, "and the bean hidden again")


func test_third_person_gets_the_emote_view_and_stays_third() -> void:
	var a: PlayerAvatar = await _local()
	a.cam.toggle_mode()
	await wait_physics_frames(5)
	assert_eq(a.cam.mode, PlayerCamera.Mode.THIRD)
	var behind: Vector3 = _cam_pos(a)
	assert_gt(behind.z, a.global_position.z + 1.0, "third person sits behind us")
	a.play_emote(&"wave")
	await wait_seconds(0.6)
	assert_true(_faces_us(a), "swung round to the front")
	await wait_seconds(Emotes.length(&"wave"))
	assert_eq(a.cam.mode, PlayerCamera.Mode.THIRD, "still third person")
	assert_almost_eq(_cam_pos(a).distance_to(behind), 0.0, 0.1, "back behind us")


func test_seated_emote_lifts_off_the_station_view_and_returns() -> void:
	var a: PlayerAvatar = await _local()
	var seat := Node3D.new()
	add_child_autofree(seat)
	seat.global_position = Vector3(2, 0, 0)
	var anchor := Node3D.new()
	add_child_autofree(anchor)
	anchor.global_position = Vector3(2, 1.3, -0.4)
	anchor.rotation.x = -0.5
	a.sit(seat, anchor)
	await wait_seconds(0.6)
	var station: Vector3 = _cam_pos(a)
	assert_almost_eq(station.distance_to(anchor.global_position), 0.0, 0.02, "at the station view")
	assert_true(a.play_emote(&"laugh"), "emote in the seat")
	assert_eq(a.state, PlayerAvatar.State.SEATED, "still seated")
	await wait_seconds(0.6)
	assert_true(_faces_us(a), "looking back at us from across the table")
	assert_almost_eq(_cam_pos(a).y, PlayerCamera.EMOTE_SEATED_HEIGHT, 0.05, "up over the table")
	assert_gt(_cam_pos(a).distance_to(a.global_position), 2.0, "pulled back from the table to see the whole bean")
	assert_true(a.visuals.visible)
	await wait_seconds(Emotes.length(&"laugh"))
	assert_almost_eq(_cam_pos(a).distance_to(anchor.global_position), 0.0, 0.02, "back at the station view")
	assert_false(a.visuals.visible)


func test_other_players_emotes_leave_the_camera_alone() -> void:
	var a: PlayerAvatar = await _local()
	var other := PlayerAvatar.new()
	other.drive = PlayerAvatar.Drive.PUPPET
	add_child_autofree(other)
	other.teleport(Vector3(0, 0, -3), PI)
	await wait_physics_frames(2)
	var eye: Vector3 = _cam_pos(a)
	assert_true(other.play_emote(&"dance"))
	assert_null(other.cam, "only the local player has a camera")
	await wait_seconds(0.5)
	assert_false(a.cam.emote_view)
	assert_almost_eq(_cam_pos(a).distance_to(eye), 0.0, 0.01, "our view did not move")


func test_ragdoll_and_the_toggle_take_the_camera_back() -> void:
	var a: PlayerAvatar = await _local()
	a.play_emote(&"taunt")
	await wait_seconds(0.4)
	a.start_ragdoll(Vector3(0, 2, 2))
	await wait_physics_frames(2)
	assert_false(a.cam.emote_view, "knocked out of the emote")
	assert_eq(a.cam.emote_blend, 0.0, "the ragdoll camera takes over at once")
	a.end_ragdoll(Vector3.ZERO)
	await wait_physics_frames(2)
	a.play_emote(&"gg")
	await wait_seconds(0.4)
	a.cam.toggle_mode()  # the player wants their view back mid-emote
	assert_false(a.cam.emote_view)
	assert_eq(a.cam.mode, PlayerCamera.Mode.FIRST, "the toggle goes to the view you were not looking at")
	assert_true(a.visuals.is_emoting(), "the emote itself plays on")
	await wait_physics_frames(2)
	assert_false(a.visuals.visible, "first person again")
