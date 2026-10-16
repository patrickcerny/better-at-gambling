extends GutTest
## The craps throw (client presentation, pure): the same seed throws the same way everywhere, the
## dice tumble across the felt and rest inside the rails by `REST_TIME`, and whatever the throw,
## they rest showing exactly the faces the server rolled.

const FELT_Y: float = CrapsStation.FELT_Y


func _plan(seed_value: int, seat: int, faces: Array) -> Dictionary:
	return CrapsDice.simulate(seed_value, CrapsStation.throw_from(seat), CrapsStation.throw_target(seat), CrapsStation.felt_rect(), FELT_Y, faces)


func test_relabel_is_a_cube_rotation_carrying_one_face_to_another() -> void:
	for a: int in range(1, 7):
		for b: int in range(1, 7):
			var c: Basis = CrapsDice.relabel(a, b)
			assert_almost_eq(c.determinant(), 1.0, 0.0001, "%d→%d is a rotation" % [a, b])
			assert_eq(c * CrapsDice.FACE_NORMALS[a - 1], CrapsDice.FACE_NORMALS[b - 1], "%d lands where %d was" % [a, b])
			# It maps the cube's corners onto corners: the throw's geometry does not change.
			for cx: float in [-1.0, 1.0]:
				for cz: float in [-1.0, 1.0]:
					var v: Vector3 = c * Vector3(cx, 1.0, cz)
					assert_eq(v.abs(), Vector3.ONE)
	for v: int in range(1, 7):
		assert_eq(CrapsDice.face_up(Basis(CrapsStation._flat_showing(v, 0.7))), v, "a die laid flat on %d shows %d" % [v, v])
	assert_eq(CrapsDice.FACE_NORMALS[0], -CrapsDice.FACE_NORMALS[5], "1 opposite 6")
	assert_eq(CrapsDice.FACE_NORMALS[1], -CrapsDice.FACE_NORMALS[4], "2 opposite 5")
	assert_eq(CrapsDice.FACE_NORMALS[2], -CrapsDice.FACE_NORMALS[3], "3 opposite 4")


func test_the_same_seed_throws_the_same_way() -> void:
	var a: Dictionary = _plan(4242, 2, [3, 5])
	var b: Dictionary = _plan(4242, 2, [3, 5])
	for i: int in 2:
		assert_eq((a["pos"] as Array)[i], (b["pos"] as Array)[i])
		assert_eq((a["rot"] as Array)[i], (b["rot"] as Array)[i])
	var c: Dictionary = _plan(4243, 2, [3, 5])
	assert_ne((a["pos"] as Array)[0], (c["pos"] as Array)[0], "another seed, another throw")
	# Other faces relabel the same throw: the dice travel exactly the same path.
	var d: Dictionary = _plan(4242, 2, [6, 1])
	assert_eq((a["pos"] as Array)[0], (d["pos"] as Array)[0], "the path never depends on the faces")


func test_every_throw_rests_on_the_rolled_faces_inside_the_rails() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var walls: int = 0
	var n: int = 0
	var longest: float = 0.0
	var corner: float = CrapsDice.HALF * sqrt(3.0)
	var felt: Rect2 = CrapsStation.felt_rect()
	for s: int in 70:
		var seat: int = s % 7 - 1
		var faces: Array = [r.randi_range(1, 6), r.randi_range(1, 6)]
		var plan: Dictionary = _plan(1000 + s * 7919, seat, faces)
		n += 1
		if bool(plan["wall"]):
			walls += 1
		longest = maxf(longest, float(plan["rest"]))
		assert_lte(float(plan["rest"]), CrapsDice.REST_TIME, "seed %d rests in time" % s)
		assert_lt(CrapsDice.REST_TIME, Registry.balance.craps_throw_time, "before the server pays")
		var end: float = float(plan["duration"])
		for i: int in 2:
			var at_rest: Transform3D = CrapsDice.sample(plan, i, end)
			assert_eq(CrapsDice.face_up(at_rest.basis), int(faces[i]), "seed %d seat %d die %d shows the server's face" % [s, seat, i])
			# Lying flat on the felt, not tilted on an edge.
			var up_face: Vector3 = at_rest.basis * CrapsDice.FACE_NORMALS[int(faces[i]) - 1]
			assert_gt(up_face.normalized().y, 0.999, "seed %d die %d lies flat" % [s, i])
			assert_almost_eq(at_rest.origin.y, FELT_Y + CrapsDice.HALF, 0.002, "on the felt")
			# Never off the table: every frame inside the rails and above the felt.
			var t: float = 0.0
			while t <= end:
				var xf: Transform3D = CrapsDice.sample(plan, i, t)
				assert_true(felt.grow(0.002).has_point(Vector2(xf.origin.x, xf.origin.z)), "seed %d die %d at %.2f s inside the rails: %s" % [s, i, t, xf.origin])
				assert_gt(xf.origin.y, FELT_Y + CrapsDice.HALF - corner + CrapsDice.HALF - 0.01, "above the felt")
				t += 0.05
			# The rest is still: nothing moves in the last frames.
			assert_eq(CrapsDice.sample(plan, i, float(plan["rest"]) + 0.02).origin, at_rest.origin)
		var gap: float = CrapsDice.sample(plan, 0, end).origin.distance_to(CrapsDice.sample(plan, 1, end).origin)
		assert_gt(gap, CrapsDice.EDGE, "seed %d: the dice rest apart" % s)
	gut.p("%d throws: %d reached the far rail, slowest rest %.2f s" % [n, walls, longest])
	assert_gt(walls, n / 2, "most throws reach the far end like a real shooter's")


func test_the_dice_fly_and_tumble() -> void:
	for s: int in 10:
		var plan: Dictionary = _plan(77 + s, s % 6, [4, 4])
		var peak: float = 0.0
		var turned: float = 0.0
		var prev: Quaternion = (plan["rot"] as Array)[0][0]
		var t: float = 0.0
		while t < 0.8:
			var xf: Transform3D = CrapsDice.sample(plan, 0, t)
			peak = maxf(peak, xf.origin.y - FELT_Y)
			var q: Quaternion = xf.basis.get_rotation_quaternion()
			turned += prev.angle_to(q)
			prev = q
			t += 1.0 / 60.0
		assert_gt(peak, 0.3, "seed %d: thrown in an arc" % s)
		assert_gt(turned, TAU * 1.5, "seed %d: tumbling (%.1f turns in the first 0.8 s)" % [s, turned / TAU])
