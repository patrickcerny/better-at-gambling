extends GutTest
## Patrick: "i want character animated Emotes in 3d person ... it actually animates your
## characters depending on the emote (should be real emotes so 67 does the 67 gesture)". Every
## emote (wheel and number keys) moves the bean away from its idle pose while it plays and lets go
## afterwards; 67 holds both hands out in front and weighs them up and down in turn; ragdolls,
## sitting down and new emotes cut one short; character skins act them out too (their own clip or
## driven arm bones), and an item held in the right hand keeps its arm.

const STEP: float = 1.0 / 60.0


func _bean(skin: StringName = &"bean") -> AvatarVisuals:
	var v := AvatarVisuals.new()
	v.animate_headless = true
	add_child_autofree(v)
	if skin != &"bean":
		v.set_skin(skin)
	await wait_process_frames(2)
	return v


## Where an arm points now (rig space): bean arms point along their pivot's -Z.
func _arm(v: AvatarVisuals, i: int) -> Vector3:
	var pivot: Node3D = v.arm_l if i == 0 else v.arm_r
	return (pivot.basis * Vector3.FORWARD).normalized()


## A fingerprint of the whole pose: both arms, the body's tilt and offset, the rig's lift. Not the
## eyes: the bean blinks at random every few seconds, and a sample taken mid-blink is 0.2 off.
func _pose(v: AvatarVisuals) -> PackedFloat32Array:
	var a: Vector3 = _arm(v, 0)
	var b: Vector3 = _arm(v, 1)
	var r: Vector3 = v.body.rotation
	var o: Vector3 = v.body.position
	return PackedFloat32Array([a.x, a.y, a.z, b.x, b.y, b.z, r.x, r.y, r.z, o.x, o.y, o.z, v.get_node("Rig").position.y])


func _distance(p: PackedFloat32Array, q: PackedFloat32Array) -> float:
	var d: float = 0.0
	for i: int in p.size():
		d += absf(p[i] - q[i])
	return d


## Jumps the emote to `t` seconds in and lets one frame draw it.
func _at(v: AvatarVisuals, t: float) -> void:
	v.emote_time = t
	await wait_process_frames(1)


func test_every_emote_moves_the_bean_and_lets_go_after() -> void:
	var ids: Array[StringName] = []
	for row: Array in Emotes.LIST:
		ids.append(row[0] as StringName)
	ids.append_array(Emotes.ANIMATED)
	assert_eq(ids.size(), 10, "six wheel emotes and four on the number keys")
	var v: AvatarVisuals = await _bean()
	await wait_process_frames(40)  # the springs settle by frames (1/30 s cap), not by the clock
	var idle: PackedFloat32Array = _pose(v)
	var poses: Dictionary = {}
	for id: StringName in ids:
		assert_true(Emotes.has_animation(id), String(id))
		assert_true(v.emote(id), "%s starts" % id)
		await _at(v, 1.05)
		var mid: PackedFloat32Array = _pose(v)
		assert_gt(_distance(mid, idle), 0.6, "%s: mid-emote the bean is clearly out of its idle pose" % id)
		poses[id] = mid
		v.stop_emote()
		# The springs step at most 1/30 s per frame, so settling is a number of frames, not a
		# wall-clock wait: under a loaded suite 0.8 s is too few frames and the lean is still easing.
		await wait_process_frames(60)
		assert_false(v.is_emoting())
		assert_lt(_distance(_pose(v), idle), 0.2, "%s: back to idle afterwards" % id)
	# Each emote is its own motion, not one shared wiggle.
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			assert_gt(_distance(poses[ids[i]], poses[ids[j]]), 0.25, "%s and %s look different" % [ids[i], ids[j]])


func test_an_emote_ends_on_its_own_and_the_pose_returns() -> void:
	var v: AvatarVisuals = await _bean()
	await wait_process_frames(40)
	var idle: PackedFloat32Array = _pose(v)
	v.emote(&"wave")
	await wait_seconds(1.0)
	assert_gt(_distance(_pose(v), idle), 0.6, "waving")
	await wait_seconds(Emotes.SECONDS - 1.0 + 0.2)
	assert_false(v.is_emoting(), "over after Emotes.SECONDS")
	await wait_process_frames(60)  # the arms ease down over frames, not seconds
	assert_lt(_distance(_pose(v), idle), 0.2, "arms down again")


## The 67 gesture: both hands out in front at chest height, palms up, see-sawing like scales.
func test_six_seven_is_both_hands_forward_weighing_in_turn() -> void:
	var v: AvatarVisuals = await _bean()
	v.emote(&"six_seven")
	var tops: Array[float] = []
	for t: float in [0.625, 0.875, 1.125, 1.375]:  # quarter beats: hands at the ends of the see-saw
		await _at(v, t)
		var l: Vector3 = _arm(v, 0)
		var r: Vector3 = _arm(v, 1)
		assert_lt(l.z, -0.75, "left hand out in front at %.2f s (%s)" % [t, l])
		assert_lt(r.z, -0.75, "right hand out in front at %.2f s (%s)" % [t, r])
		assert_gt(absf(l.y - r.y), 0.5, "one hand up, the other down at %.2f s" % t)
		assert_lt(l.y * r.y, 0.0, "on opposite sides of level at %.2f s" % t)
		tops.append(l.y - r.y)
		assert_almost_eq(absf(v.hand_l.rotation.z), PI * 0.5, 0.05, "palms up (thumbs out)")
	assert_lt(tops[0] * tops[1], 0.0, "the hands swap: left up, then right up")
	assert_lt(tops[1] * tops[2], 0.0)
	assert_lt(tops[2] * tops[3], 0.0)


func test_ragdoll_sitting_and_a_new_emote_cut_it_short() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	cs.shape = box
	cs.position.y = -0.5
	floor_body.add_child(cs)
	add_child_autofree(floor_body)
	var a := PlayerAvatar.new()
	add_child_autofree(a)
	await wait_physics_frames(2)
	assert_true(a.play_emote(&"dance"))
	assert_eq(a.bubble.text, Emotes.bubble_text(&"dance"), "the wheel's bubble stays")
	assert_true(a.play_emote(&"cry"), "a new emote replaces the old one")
	assert_eq(a.visuals.emote_id, &"cry")
	assert_almost_eq(a.visuals.emote_time, 0.0, 0.05, "from the start")
	a.start_ragdoll(Vector3(0, 2, 3))
	assert_false(a.visuals.is_emoting(), "the ragdoll ends it")
	assert_false(a.play_emote(&"wave"), "no emotes while ragdolled")
	assert_eq(a.bubble.text, Emotes.bubble_text(&"wave"), "the bubble still shows")
	a.end_ragdoll(Vector3.ZERO)
	assert_true(a.play_emote(&"six_seven"))
	assert_eq(a.bubble.text, "6 7", "67 keeps its bubble")
	var seat := Node3D.new()
	add_child_autofree(seat)
	a.sit(seat, seat)
	assert_false(a.visuals.is_emoting(), "sitting down ends it")
	assert_true(a.play_emote(&"laugh"), "and you can emote again in the seat")
	a.stand()
	assert_false(a.visuals.is_emoting(), "standing up ends that one")
	a.visuals.set_knocked_out(true)
	assert_false(a.play_emote(&"gg"), "knocked out: no emote")


func test_skins_act_emotes_out_too() -> void:
	for skin: StringName in SkinLibrary.SKINS:
		var v: AvatarVisuals = await _bean(skin)
		assert_not_null(v.skin_root, String(skin))
		await wait_seconds(0.3)
		var rest_twist: float = v.skin_root.rotation.y
		var rest_dirs: Array[Vector3] = []
		if v.arm_driver != null:
			rest_dirs = [v.arm_driver.measured_forearm[0], v.arm_driver.measured_forearm[1]]
		assert_true(v.emote(&"six_seven"), "%s emotes" % skin)
		await _at(v, 0.875)
		await wait_process_frames(2)
		if v.arm_driver == null:
			# No arm bones (the warrior): the whole body still sways with the gesture.
			assert_eq(skin, &"warrior", "only the boneless skin has no arm driver")
			assert_gt(absf(v.skin_root.rotation.y - rest_twist) + absf(v.skin_root.position.y), 0.03, "%s moves with the emote" % skin)
		else:
			assert_gt(v.arm_driver.weight[0], 0.9, "%s: arms driven" % skin)
			# Elbows at the sides, forearms out in front doing the weighing.
			var l: Vector3 = v.arm_driver.measured_forearm[0]
			var r: Vector3 = v.arm_driver.measured_forearm[1]
			assert_lt(l.z, -0.5, "%s: left forearm out in front (%s)" % [skin, l])
			assert_lt(r.z, -0.5, "%s: right forearm out in front (%s)" % [skin, r])
			assert_lt(v.arm_driver.measured[0].y, -0.3, "%s: elbows down by the sides" % skin)
			assert_gt(absf(l.y - r.y), 0.3, "%s: one hand up, one down" % skin)
			assert_gt(l.distance_to(rest_dirs[0]) + r.distance_to(rest_dirs[1]), 1.0, "%s: away from the idle arms" % skin)
			v.stop_emote()
			await wait_process_frames(3)
			assert_lt(v.arm_driver.weight[0], 0.01, "%s: arms let go after" % skin)
			assert_lt(v.arm_driver.measured_forearm[0].distance_to(rest_dirs[0]), 0.35, "%s: left arm back down" % skin)
		v.queue_free()


func test_skins_with_a_fitting_clip_play_it() -> void:
	var v: AvatarVisuals = await _bean(&"business")  # has a Wave clip
	v.emote(&"wave")
	v.update_motion(Vector3.ZERO, true, STEP)
	await wait_process_frames(2)
	var ap: AnimationPlayer = SkinLibrary.animation_player(v.skin_root)
	assert_true(String(ap.current_animation).ends_with("|Wave"), "its own wave clip: %s" % ap.current_animation)
	assert_lt(v.arm_driver.weight[1], 0.01, "the clip moves the arms, not the driver")
	v.emote(&"laugh")  # no laugh clip: driven arms over the idle clip
	v.update_motion(Vector3.ZERO, true, STEP)
	await _at(v, 1.0)
	assert_true(String(ap.current_animation).ends_with("|Idle"), "idle underneath: %s" % ap.current_animation)
	assert_gt(v.arm_driver.weight[0], 0.9)


## Megaphone, tray, any held item: the right arm keeps its pose through an emote (bean and skin).
func test_held_item_arm_wins_over_the_emote() -> void:
	var v: AvatarVisuals = await _bean()
	v.hold_right_arm(CasinoFloor.HOLD_ARM)
	v.emote(&"wave")
	await _at(v, 1.0)
	var want: Vector3 = AvatarVisuals.arm_direction(CasinoFloor.HOLD_ARM.x, CasinoFloor.HOLD_ARM.y, 1.0)
	assert_almost_eq(_arm(v, 1).distance_to(want), 0.0, 0.01, "right arm stays on the item")
	assert_gt(_arm(v, 0).distance_to(AvatarVisuals.arm_direction(AvatarVisuals.ARM_REST, -0.38, -1.0)), 0.05, "the left arm still waves along")
	var slot: Node3D = v.hand_node()
	assert_true(v.hand_r.is_ancestor_of(slot), "the item rides in the right glove")
	v.set_skin(&"king")
	v.emote(&"six_seven")
	await _at(v, 0.875)
	await wait_process_frames(2)
	assert_almost_eq(v.arm_driver.weight[1], 1.0, 0.001)
	assert_almost_eq(v.arm_driver.upper_dir[1].distance_to(want), 0.0, 0.01, "skin: the holding arm keeps its pose")
	assert_true(v.skin_root.is_ancestor_of(slot), "and the item follows the skin's hand")


func test_arm_pose_round_trips() -> void:
	for side: float in [-1.0, 1.0]:
		for d: Vector3 in [Vector3(0.3, 0.8, -0.2), Vector3(-0.5, -0.6, -0.6), Vector3(0.0, -1.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(-0.9, 0.1, 0.4)]:
			var p: Vector2 = AvatarVisuals.arm_pose(d, side)
			assert_almost_eq(AvatarVisuals.arm_direction(p.x, p.y, side).distance_to(d.normalized()), 0.0, 0.001, "%s side %d" % [d, side])
