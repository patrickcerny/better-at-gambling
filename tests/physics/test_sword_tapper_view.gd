extends GutTest
## The Sword Tapper seat view, close up (0.9.14, Patrick: "Even closer on crabs and sword tapper.
## Its still very far away. I just want to see the game ... almost the whole screen should be the
## game"): at the default field of view the pedestal's top fills most of the height, every gem
## and its prize label and the multiplier's slam spot sit in the left two thirds of the screen
## (the overlay is a column down the right third), with nothing between the eye and the ring.

var view: SubViewport
var st: SwordTapperStation


func before_each() -> void:
	view = SubViewport.new()
	view.size = Vector2i(1920, 1080)
	add_child_autofree(view)
	st = SwordTapperStation.new()
	st.station_id = &"sword_1"
	view.add_child(st)
	await wait_physics_frames(2)


func test_the_ring_fills_the_left_of_the_screen() -> void:
	var cam := Camera3D.new()
	cam.fov = 85.0  # the default (Settings "video/fov")
	view.add_child(cam)
	cam.global_transform = st.camera_for_seat(0).global_transform
	var left := Rect2(Vector2.ZERO, Vector2(view.size.x * 2.0 / 3.0, view.size.y))
	var span_x := Vector2(INF, -INF)
	var span_y := Vector2(INF, -INF)
	var pts: Array[Vector3] = [SwordTapperStation.MULT_SPOT]
	for i: int in SwordTapperLogic.RING_SIZE:
		pts.append(SwordTapperStation.gem_spot(i))
		pts.append(SwordTapperStation.gem_spot(i, SwordTapperStation.LABEL_R + 0.05))  # past the prize label
	for k: int in 16:  # the disc's edge
		pts.append(SwordTapperStation.gem_spot(0, SwordTapperStation.DISC_R).rotated(Vector3.UP, TAU * k / 16.0))
	for p: Vector3 in pts:
		var g: Vector3 = st.to_global(p)
		assert_false(cam.is_position_behind(g), "faces %s" % p)
		var at: Vector2 = cam.unproject_position(g)
		assert_true(left.has_point(at), "%s in the left two thirds: %s" % [p, at])
		if p != SwordTapperStation.MULT_SPOT:
			span_x = Vector2(minf(span_x.x, at.x), maxf(span_x.y, at.x))
			span_y = Vector2(minf(span_y.x, at.y), maxf(span_y.y, at.y))
	assert_gt(span_y.y - span_y.x, view.size.y * 0.6, "the ring is %.0f%% of the height (was about 35%%)" % [(span_y.y - span_y.x) / view.size.y * 100.0])
	assert_gt(span_x.y - span_x.x, view.size.x * 0.4, "and %.0f%% of the width" % [(span_x.y - span_x.x) / view.size.x * 100.0])
	# Nothing solid between the eye and the gems.
	var space: PhysicsDirectSpaceState3D = st.get_world_3d().direct_space_state
	for i: int in SwordTapperLogic.RING_SIZE:
		var to: Vector3 = st.to_global(SwordTapperStation.gem_spot(i) + Vector3(0, 0.05, 0))
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position, to))
		assert_true(hit.is_empty(), "gem %d in plain view" % i)
	cam.free()
