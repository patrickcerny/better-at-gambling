extends GutTest
## Patrick: "i want character animated Emotes in 3d person ... it actually animates your
## characters depending on the emote (should be real emotes so 67 does the 67 gesture)", and then
## "make them even better. add a 67 emote". Every emote (wheel and number keys) moves the bean away
## from its idle pose, keeps moving through its beats, never produces a NaN, and is back at rest
## when it ends; 6-7 holds both hands out in front palms up and weighs them up and down in turn
## (eight words, always in anti-phase) and ends in a shrug; the disco hops into a full twirl; the
## taunt turns its back and comes round; the faces play along (laugh squints, cry wails with tears,
## taunt winks); walking cancels an emote only after its first moment, and its sound stops with it;
## ragdolls, sitting down and new emotes cut one short; character skins act them out too (their own
## clip or driven arm bones), and an item held in the right hand keeps its arm.

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


## A fingerprint of the whole pose: both arms, the body's tilt and offset, the rig's lift and turn.
## Not the eyes: the bean blinks at random every few seconds, and a sample taken mid-blink is 0.2 off.
func _pose(v: AvatarVisuals) -> PackedFloat32Array:
	var a: Vector3 = _arm(v, 0)
	var b: Vector3 = _arm(v, 1)
	var r: Vector3 = v.body.rotation
	var o: Vector3 = v.body.position
	var rig: Node3D = v.get_node("Rig")
	var facing: Vector3 = rig.basis.z
	return PackedFloat32Array([a.x, a.y, a.z, b.x, b.y, b.z, r.x, r.y, r.z, o.x, o.y, o.z, rig.position.y, facing.x, facing.z])


## Every emote, wheel and number key.
func _ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for row: Array in Emotes.LIST:
		ids.append(row[0] as StringName)
	for id: StringName in Emotes.ANIMATED:
		if not ids.has(id):
			ids.append(id)
	return ids


## The glove's palm normal (the flat glove's thin axis) in rig space.
func _palm(v: AvatarVisuals, i: int) -> Vector3:
	var pivot: Node3D = v.arm_l if i == 0 else v.arm_r
	var glove: Node3D = v.hand_l if i == 0 else v.hand_r
	return ((pivot.basis * glove.basis) * Vector3.RIGHT).normalized()


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
	var ids: Array[StringName] = _ids()
	assert_eq(ids.size(), 10, "seven wheel emotes (6-7 among them) and three more on the number keys")
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
	await wait_seconds(Emotes.length(&"wave") - 1.0 + 0.2)
	assert_false(v.is_emoting(), "over after its length")
	await wait_process_frames(60)  # the arms ease down over frames, not seconds
	assert_lt(_distance(_pose(v), idle), 0.2, "arms down again")


## Every emote keeps moving through its beats (not one held pose), never goes NaN, and the bean is
## back in its idle pose once it has run its whole length on its own.
func test_each_emote_plays_through_its_beats_and_ends_at_rest() -> void:
	var v: AvatarVisuals = await _bean()
	await wait_process_frames(40)
	var idle: PackedFloat32Array = _pose(v)
	for id: StringName in _ids():
		assert_true(v.emote(id), String(id))
		var length: float = Emotes.length(id)
		assert_between(length, 2.0, 4.0, "%s: 2-4 s" % id)
		var samples: Array[PackedFloat32Array] = []
		var t: float = 0.05
		while t < length:
			await _at(v, t)
			var p: PackedFloat32Array = _pose(v)
			var finite: bool = true
			for x: float in p:
				finite = finite and is_finite(x)
			for n: Node3D in [v.hand_l, v.hand_r, v.get_node("Rig") as Node3D, v.body]:
				finite = finite and n.transform.origin.is_finite() and is_finite(n.transform.basis.determinant())
			assert_true(finite, "%s at %.2f s: no NaN anywhere in the pose" % [id, t])
			samples.append(p)
			t += 0.1
		var spread: float = 0.0
		var changes: int = 0
		for i: int in samples.size():
			spread = maxf(spread, _distance(samples[i], samples[0]))
			if i > 0 and _distance(samples[i], samples[i - 1]) > 0.05:
				changes += 1
		assert_gt(spread, 1.0, "%s: the pose travels over the emote (%.2f)" % [id, spread])
		assert_gt(changes, samples.size() / 2, "%s: it keeps moving, not one held pose (%d of %d)" % [id, changes, samples.size()])
		# Let it end on its own, then settle by frames (the springs step at most 1/30 s a frame).
		v.emote_time = length - 0.1
		await wait_until(func() -> bool: return not v.is_emoting(), 2.0)
		assert_false(v.is_emoting(), "%s ends on its own" % id)
		await wait_process_frames(60)
		assert_lt(_distance(_pose(v), idle), 0.2, "%s: back at rest" % id)


## Nothing pops: frame to frame (60 fps) no arm swings more than ~30 degrees and no glove turns over
## (the arcs ease in, and a thumb never flips round its arm).
func test_no_emote_pops_between_frames() -> void:
	for id: StringName in _ids():
		var prev: Dictionary = {}
		var t: float = 0.0
		while t < Emotes.length(id):
			var p: Dictionary = EmotePoses.pose(id, t)
			if not prev.is_empty():
				var a: Vector4 = p["arms"]
				var b: Vector4 = prev["arms"]
				var ra: Vector2 = p.get("rolls", Vector2.ZERO)
				var rb: Vector2 = prev.get("rolls", Vector2.ZERO)
				for i: int in 2:
					var side: float = -1.0 if i == 0 else 1.0
					var now: Basis = _glove_basis(Vector2(a.x, a.y) if i == 0 else Vector2(a.z, a.w), ra.x if i == 0 else ra.y, side)
					var before: Basis = _glove_basis(Vector2(b.x, b.y) if i == 0 else Vector2(b.z, b.w), rb.x if i == 0 else rb.y, side)
					var swing: float = (now * Vector3.FORWARD).angle_to(before * Vector3.FORWARD)
					assert_lt(swing, 0.55, "%s at %.2f s: arm %d jumps %.2f rad in a frame" % [id, t, i, swing])
					var turn: float = Quaternion(now).angle_to(Quaternion(before))
					assert_lt(turn, 1.0, "%s at %.2f s: glove %d turns %.2f rad in a frame" % [id, t, i, turn])
			prev = p
			t += 1.0 / 60.0


## A glove's orientation in rig space for an arm (pitch, splay) and glove roll (`_set_arm`).
func _glove_basis(arm: Vector2, roll: float, side: float) -> Basis:
	var splay: float = arm.y if side < 0.0 else -arm.y
	return (Basis(Vector3.BACK, splay) * Basis(Vector3.RIGHT, arm.x) * Basis(Vector3.BACK, -roll)).orthonormalized()


## The 6-7 meme: both hands out in front at chest height, palms up, weighing "six... seven" up and
## down in turn like scales, always one up and one down, eight words; then a shrug.
func test_six_seven_weighs_the_hands_in_turn_and_shrugs() -> void:
	var v: AvatarVisuals = await _bean()
	v.emote(&"six_seven")
	var cycle: float = EmotePoses.SIX_SEVEN_CYCLE
	var swaps: int = 0
	var words: int = 0
	var last: float = 0.0
	var t: float = EmotePoses.SIX_SEVEN_START + cycle * 0.25
	while t < EmotePoses.SIX_SEVEN_SHRUG:  # the ends of the see-saw, a word each
		await _at(v, t)
		var l: Vector3 = _arm(v, 0)
		var r: Vector3 = _arm(v, 1)
		assert_lt(l.z, -0.6, "left hand out in front at %.2f s (%s)" % [t, l])
		assert_lt(r.z, -0.6, "right hand out in front at %.2f s (%s)" % [t, r])
		assert_lt(l.y * r.y, 0.0, "one hand up, the other down at %.2f s" % t)
		assert_gt(absf(l.y - r.y), 0.9, "a big, readable see-saw at %.2f s" % t)
		for i: int in 2:
			assert_gt(absf(_palm(v, i).y), 0.7, "palm up at %.2f s (%s)" % [t, _palm(v, i)])
		var top: float = l.y - r.y
		if last != 0.0 and top * last < 0.0:
			swaps += 1
		last = top
		words += 1
		t += cycle * 0.5
	assert_eq(words, 8, "six, seven, six, seven...")
	assert_gte(swaps, 7, "the hands swap places on every word")
	# All the way through, not just at the ends, they move in anti-phase: as one rises the other
	# sinks by as much (a pair of scales), never both the same way.
	t = EmotePoses.SIX_SEVEN_START + 0.1
	while t < EmotePoses.SIX_SEVEN_SHRUG - 0.05:
		await _at(v, t)
		assert_lt(absf(_arm(v, 0).y + _arm(v, 1).y), 0.2, "mirror images at %.2f s" % t)
		t += 0.03
	# The shrug: hands out to the sides and up, palms up.
	await _at(v, EmotePoses.SIX_SEVEN_SHRUG + 0.35)
	var sl: Vector3 = _arm(v, 0)
	var sr: Vector3 = _arm(v, 1)
	assert_lt(sl.x, -0.6, "left hand out to the side (%s)" % sl)
	assert_gt(sr.x, 0.6, "right hand out to the side (%s)" % sr)
	assert_gt(sl.y, 0.2, "and raised")
	assert_gt(sr.y, 0.2)
	for i: int in 2:
		assert_gt(absf(_palm(v, i).y), 0.7, "shrug: palms up (%s)" % _palm(v, i))


## The disco: a hop that leaves the floor and a full twirl, landing facing front again.
func test_dance_hops_and_twirls() -> void:
	var v: AvatarVisuals = await _bean()
	v.emote(&"dance")
	var rig: Node3D = v.get_node("Rig")
	var high: float = 0.0
	var turned: bool = false
	var t: float = EmotePoses.DISCO_SPIN.x
	while t <= EmotePoses.DISCO_SPIN.y:
		await _at(v, t)
		high = maxf(high, rig.position.y)
		if rig.basis.z.z < -0.8:
			turned = true  # facing away mid-twirl
		t += 0.05
	assert_gt(high, 0.2, "the feet leave the floor (%.2f)" % high)
	assert_true(turned, "it spins right round")
	await _at(v, EmotePoses.DISCO_SPIN.y + 0.3)
	assert_gt(rig.basis.z.z, 0.95, "facing front again for the finish")
	assert_lt(rig.position.y, 0.05, "back on the floor")


## The taunt turns its back to wiggle and comes round again.
func test_taunt_turns_its_back_and_comes_round() -> void:
	var v: AvatarVisuals = await _bean()
	v.emote(&"taunt")
	var rig: Node3D = v.get_node("Rig")
	await _at(v, 1.7)
	assert_lt(rig.basis.z.z, -0.9, "back to the viewer")
	await _at(v, 2.5)
	assert_gt(rig.basis.z.z, 0.95, "facing front for the smug finish")


## The faces play along: laugh squeezes the eyes shut with the mouth wide, cry shows tears under
## worried brows and a wailing frown, the taunt winks.
func test_faces_play_along() -> void:
	var v: AvatarVisuals = await _bean()
	await wait_process_frames(30)
	var open_eye: float = v.eye_r.scale.y
	var mouth: ShaderMaterial = v.mouth.material_override as ShaderMaterial
	v.emote(&"laugh")
	for i: int in 20:
		await _at(v, 0.6)
	assert_lt(v.eye_r.scale.y, open_eye * 0.5, "laughing: eyes squeezed")
	assert_gt(float(mouth.get_shader_parameter(&"open")), 0.6, "mouth wide open")
	v.emote(&"cry")
	for i: int in 20:
		await _at(v, 1.2)
	assert_true((v.body.get_node("TearL") as Node3D).visible, "tears")
	assert_lt(float(mouth.get_shader_parameter(&"smile")), -0.5, "a wailing frown")
	assert_gt(v.brow_l.rotation.z, PI * 0.5 + 0.2, "brows up in the middle (worried)")
	v.emote(&"taunt")
	for i: int in 20:
		await _at(v, 0.7)
	assert_lt(v.eye_l.scale.y, v.eye_r.scale.y * 0.5, "a wink")


## Walking cancels an emote, but not in its first moment (the press itself can carry momentum), and
## the emote's sound stops with it.
func test_walking_cancels_after_the_first_moment_and_the_cue_stops() -> void:
	var v: AvatarVisuals = await _bean()
	v.emote(&"six_seven")
	v.update_motion(Vector3(4, 0, 0), true, STEP)
	await wait_process_frames(2)
	assert_true(v.is_emoting(), "still going in the first moment")
	v.emote_time = 0.35
	await wait_process_frames(2)
	assert_false(v.is_emoting(), "walking off ends it")
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
	var cue := AudioStreamPlayer3D.new()
	a.add_child(cue)
	a.set_emote_sound(cue)
	a.visuals.stop_emote()  # hit, walked off, sat down...
	await wait_physics_frames(2)
	assert_true(not is_instance_valid(cue) or cue.is_queued_for_deletion(), "the cue goes with the emote")


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
	assert_eq(a.bubble.text, Emotes.bubble_text(&"six_seven"), "6-7 keeps its bubble")
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
