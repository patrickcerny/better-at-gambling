extends GutTest
## Patrick: "When you go 3d person, its at an angle, it should be directly in front (still turnable
## like now)". The third-person camera sits straight behind the bean, on the line it faces, not
## over a shoulder, and the mouse still turns it round the bean.

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


func _local() -> PlayerAvatar:
	var a := PlayerAvatar.new()
	a.is_local = true
	add_child_autofree(a)
	a.teleport(Vector3.ZERO, 0.0)
	await wait_physics_frames(3)
	return a


## The camera's sideways offset from the line the view faces, in metres (0 = dead centre).
func _side_offset(a: PlayerAvatar) -> float:
	var to_cam: Vector3 = a.cam.camera.global_position - a.global_position
	to_cam.y = 0.0
	var right: Vector3 = a.cam.camera.global_basis.x
	right.y = 0.0
	return absf(to_cam.dot(right.normalized()))


func test_third_person_is_straight_behind_and_still_turns() -> void:
	var a: PlayerAvatar = await _local()
	a.cam.toggle_mode()
	await wait_physics_frames(3)
	assert_eq(a.cam.mode, PlayerCamera.Mode.THIRD)
	var to_cam: Vector3 = a.cam.camera.global_position - a.global_position
	assert_gt(to_cam.z, 2.0, "behind the bean (it faces -Z): %s" % to_cam)
	assert_almost_eq(_side_offset(a), 0.0, 0.05, "dead centre, not over a shoulder")
	var look: Vector3 = -a.cam.camera.global_basis.z
	assert_lt(absf(look.x), 0.05, "looking straight ahead along the bean's line")
	# Turning the mouse orbits the camera round the bean: it stays centred on the new line.
	a.cam.look(deg_to_rad(90.0), 0.0)
	await wait_physics_frames(3)
	var turned: Vector3 = a.cam.camera.global_position - a.global_position
	assert_gt(absf(turned.x), 2.0, "swung round to the side: %s" % turned)
	assert_almost_eq(_side_offset(a), 0.0, 0.05, "still dead centre after the turn")
