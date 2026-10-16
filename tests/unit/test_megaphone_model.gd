extends GutTest
## The Megaphone the right way round (Patrick: "the microphone is the wrong way around"): the
## wide bell points forward and a little up, away from the holder's face, with the narrow
## mouthpiece and the grip at the fist; in first person the bell points away from the camera.


## The horn's vertices in the megaphone's own space.
func _horn_points(mega: Node3D) -> PackedVector3Array:
	var horn: MeshInstance3D = mega.get_node(^"Horn")
	var out := PackedVector3Array()
	for v: Vector3 in horn.mesh.get_faces():
		out.append(horn.transform * v)
	return out


## [bell centre, mouthpiece centre] of the horn after `xf`: of the two ends along its axis, the
## bell is the one whose cross-section spreads widest.
func _ends(points: PackedVector3Array, xf: Transform3D) -> Array[Vector3]:
	# The horn's axis in its own space is z; split the vertices at each end of it.
	var lo: float = INF
	var hi: float = -INF
	for p: Vector3 in points:
		lo = minf(lo, p.z)
		hi = maxf(hi, p.z)
	var ends: Array[Vector3] = []
	var spreads: Array[float] = []
	for z: float in [lo, hi]:
		var sum: Vector3 = Vector3.ZERO
		var n: int = 0
		var spread: float = 0.0
		for p: Vector3 in points:
			if absf(p.z - z) < 0.01:
				sum += p
				n += 1
				spread = maxf(spread, Vector2(p.x, p.y).length())
		ends.append(xf * (sum / maxf(n, 1)))
		spreads.append(spread)
	if spreads[0] >= spreads[1]:
		return [ends[0], ends[1]]
	return [ends[1], ends[0]]


func test_model_bell_and_rim_at_minus_z() -> void:
	var mega: Node3D = autofree(CasinoFloor.make_megaphone())
	var e: Array[Vector3] = _ends(_horn_points(mega), Transform3D.IDENTITY)
	assert_lt(e[0].z, e[1].z, "the wide bell is at -z, the mouthpiece at +z")
	var rim: Node3D = mega.get_node(^"Rim")
	assert_almost_eq(rim.position.z, e[0].z, 0.03, "the red rim sits on the bell")


func test_held_bell_points_forward_and_up_with_the_grip_in_the_fist() -> void:
	var v := AvatarVisuals.new()
	add_child_autofree(v)
	v.hold_right_arm(CasinoFloor.HOLD_ARM)
	v._animate_arms(0.0, {})  # headless runs don't animate on their own
	var hand: Node3D = ItemModels.hand_node(v)
	var mega: Node3D = autofree(CasinoFloor.make_megaphone())
	var held: Transform3D = hand.global_transform.orthonormalized() * CasinoFloor.hand_grip()
	var e: Array[Vector3] = _ends(_horn_points(mega), held)
	var bell: Vector3 = e[0]
	var mouthpiece: Vector3 = e[1]
	assert_lt(bell.z, mouthpiece.z - 0.25, "bell ahead of the mouthpiece (the bean faces -z)")
	assert_gt(bell.y, mouthpiece.y, "bell tipped a little up")
	assert_lt(bell.y - mouthpiece.y, 0.25, "...but not pointing at the ceiling")
	var grip: Vector3 = held * CasinoFloor.GRIP_POS
	assert_lt(grip.distance_to(hand.global_position), 0.03, "grip in the fist")
	assert_gt(hand.global_position.y, 0.6, "the arm is raised, not hanging")


func test_first_person_bell_points_away_from_the_camera() -> void:
	var mega: Node3D = autofree(CasinoFloor.make_megaphone())
	var e: Array[Vector3] = _ends(_horn_points(mega), CasinoFloor.view_grip())
	assert_lt(e[0].z, e[1].z - 0.25, "bell further from the eye than the mouthpiece")
	assert_lt(e[1].z, -0.1, "in front of the camera")
