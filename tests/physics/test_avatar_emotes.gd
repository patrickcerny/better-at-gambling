extends GutTest
## The new bean (AvatarVisuals) and its number-key emotes: an emote plays for its length
## (`Emotes.length`, 2-4 s) and ends on its own (or when the bean is hit or walks off), the right
## hand has a slot for held items that follows a character skin, and in the real match scene key 6
## sends `play_emote` for 6-7 and everyone's
## copy of our bean plays it (ours watched in third person), and a wheel emote from someone else
## plays on their bean without touching our camera. (Camera: test_emote_camera.gd; every emote's
## motion: test_emote_animations.gd.)

var scene: MatchScene


func after_each() -> void:
	MatchScene.test_dummies = 0


func _bean() -> AvatarVisuals:
	var v := AvatarVisuals.new()
	add_child_autofree(v)
	await wait_process_frames(1)
	return v


func test_new_bean_keeps_its_parts() -> void:
	var v: AvatarVisuals = await _bean()
	for part: Node in [v.body, v.eye_l, v.eye_r, v.brow_l, v.brow_r, v.mouth, v.arm_l, v.arm_r, v.hand_l, v.hand_r, v.hat_slot, v.stars]:
		assert_not_null(part)
	assert_true(v.body.mesh is ArrayMesh, "the jelly-bean body, not a capsule")
	assert_eq(v.mouth.get_parent(), v.body, "the face rides the body")
	assert_true(v.hand_r.is_ancestor_of(v.hand_node()), "hand slot sits in the right glove")


func test_emote_plays_and_ends() -> void:
	var v: AvatarVisuals = await _bean()
	assert_false(v.emote(&"moonwalk"), "unknown emotes are ignored")
	assert_true(v.emote(&"default_dance"))
	assert_true(v.is_emoting())
	assert_eq(v.emote_id, &"default_dance")
	await wait_seconds(1.0)
	assert_true(v.is_emoting(), "still dancing after a second")
	await wait_seconds(Emotes.length(&"default_dance") - 1.0 + 0.4)
	assert_false(v.is_emoting(), "over after its length")
	assert_eq(v.emote_id, &"")


func test_hits_and_walking_off_cut_an_emote_short() -> void:
	var v: AvatarVisuals = await _bean()
	v.emote(&"six_seven")
	v.hit(Vector3.FORWARD, 1.0)
	assert_false(v.is_emoting(), "a hit ends it")
	v.emote(&"thumbs_up")
	await wait_process_frames(2)
	v.emote_time = 0.4  # past the first moment, when walking may cancel it (no wall-clock race)
	v.update_motion(Vector3(4, 0, 0), true, 0.016)
	await wait_process_frames(2)
	assert_false(v.is_emoting(), "walking off ends it")
	v.set_knocked_out(true)
	assert_false(v.emote(&"thumbs_down"), "no emotes while knocked out")


func test_emotes_play_on_skins_and_the_hand_slot_follows() -> void:
	var v: AvatarVisuals = await _bean()
	var slot: Node3D = v.hand_node()
	v.set_skin(&"king")
	assert_eq(v.hand_node(), slot, "same slot, so a held item stays attached")
	assert_true(v.skin_root.is_ancestor_of(slot), "on the skin's right hand")
	assert_true(v.emote(&"thumbs_up"))
	v.update_motion(Vector3.ZERO, true, 0.016)
	await wait_seconds(Emotes.length(&"thumbs_up") + 0.3)
	assert_false(v.is_emoting())
	v.set_skin(&"wizard")
	assert_true(v.emote(&"six_seven"), "skins with arm bones but no clips emote too")
	v.set_skin(&"bean")
	assert_true(v.hand_r.is_ancestor_of(slot), "back in the glove")


func test_key_sends_the_emote_and_the_bean_plays_it() -> void:
	MatchScene.test_dummies = 1
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_seconds(3.3)
	assert_eq(scene.router.mode, InputRouter.Mode.WALK)
	assert_eq(scene.local.cam.mode, PlayerCamera.Mode.FIRST, "first person by default")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_6
	k.keycode = KEY_6
	k.pressed = true
	get_tree().root.push_input(k)
	await wait_physics_frames(3)
	assert_eq(scene.local.visuals.emote_id, &"six_seven", "key 6 = 6-7, through the server")
	assert_eq(scene.local.bubble.text, Emotes.bubble_text(&"six_seven"), "with its bubble")
	assert_true(scene.local.cam.emote_view, "our emote is watched in third person")
	assert_eq(scene.local.cam.mode, PlayerCamera.Mode.FIRST, "the player's own choice of view is kept underneath")
	await wait_physics_frames(30)
	assert_true(scene.local.visuals.visible, "we see our own bean do it")
	# A dummy's emote arrives as an event like anyone else's.
	var bot: int = -1
	for pid: int in scene.avatars:
		if pid != scene.local_id:
			bot = pid
	assert_true(scene.server.submit_intent(bot, Intents.make(&"play_emote", {"emote": &"default_dance"}))["ok"])
	await wait_physics_frames(3)
	assert_eq((scene.avatars[bot] as PlayerAvatar).visuals.emote_id, &"default_dance")
	await wait_seconds(Emotes.MAX_SECONDS + 0.3)
	assert_false(scene.local.visuals.is_emoting())
	assert_false((scene.avatars[bot] as PlayerAvatar).visuals.is_emoting())
	assert_false(scene.local.cam.emote_view, "the emote view ends with the emote")
	await wait_physics_frames(30)
	assert_eq(scene.local.cam.mode, PlayerCamera.Mode.FIRST, "back to first person after the emote")
	assert_false(scene.local.cam.in_emote_view())
	assert_false(scene.local.visuals.visible, "first person hides our bean again")
	# Someone else's wheel emote: their bean waves, our camera stays put.
	var r: Dictionary = {}
	for i: int in 40:  # the wheel shares the chat rate limit with everything else the bot sent
		r = scene.server.submit_intent(bot, Intents.make(&"emote", {"id": &"wave"}))
		if r["ok"]:
			break
		await wait_physics_frames(6)
	assert_true(r["ok"], str(r))
	await wait_physics_frames(3)
	assert_eq((scene.avatars[bot] as PlayerAvatar).visuals.emote_id, &"wave", "the wheel's wave is acted out")
	assert_eq((scene.avatars[bot] as PlayerAvatar).bubble.text, Emotes.bubble_text(&"wave"))
	assert_false(scene.local.cam.emote_view, "other players' emotes leave our camera alone")
