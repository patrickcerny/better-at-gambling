extends GutTest
## The waiter holds his tray (Patrick: "The waiters carry a floating tablet"): it is a child of
## his right arm, lies level on top of the glove and stays there while he walks; a trip throws it
## off the hand and getting up puts a fresh one back on it.

var w: Waiter


func before_each() -> void:
	w = Waiter.new()
	add_child_autofree(w)
	w._build_visuals()  # headless runs skip the body; the tray needs it
	await wait_physics_frames(1)


## The glove's top in world space, and the tray's underside centre.
func _gap() -> Vector3:
	var hand: Node3D = w.visuals.hand_r
	var top: Vector3 = hand.global_position + Vector3.UP * AvatarVisuals.HAND_RADIUS
	return w.tray.global_position - top


func _assert_on_palm(why: String) -> void:
	assert_true(w.visuals.arm_r.is_ancestor_of(w.tray), "tray parented under the right arm (%s)" % why)
	var gap: Vector3 = _gap()
	assert_almost_eq(gap.y, 0.0, 0.04, "underside resting on the glove (%s)" % why)
	assert_lt(Vector2(gap.x, gap.z).length(), 0.15, "palm under the tray (%s)" % why)
	assert_gt(w.tray.global_basis.y.normalized().dot(Vector3.UP), 0.97, "tray level (%s)" % why)


func test_tray_rests_on_the_palm() -> void:
	assert_not_null(w.tray)
	w.visuals._animate(0.016)
	_assert_on_palm("standing")


func test_tray_stays_on_the_palm_while_walking() -> void:
	for i: int in 40:
		w.visuals.update_motion(Vector3(0, 0, -Waiter.SPEED), true, 0.016)
		w.visuals._animate(0.016)
		if i % 10 == 9:
			_assert_on_palm("walking, frame %d" % i)


func test_trip_throws_the_tray_and_getting_up_brings_a_new_one() -> void:
	w.trip()
	assert_false(w.visuals.arm_r.is_ancestor_of(w.tray), "off the hand while he falls")
	assert_eq(w.visuals.hold_arm_r, Vector3.INF, "the arm lets go")
	w.get_up()
	await wait_seconds(0.6)
	assert_true(is_instance_valid(w.tray))
	w.visuals._animate(0.016)
	_assert_on_palm("after getting up")
