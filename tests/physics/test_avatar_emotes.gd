extends GutTest
## The new bean (AvatarVisuals) and its number-key emotes: an emote plays for ~2.5 s and ends on
## its own (or when the bean is hit or walks off), the right hand has a slot for held items that
## follows a character skin, and in the real match scene key 5 sends `play_emote` and everyone's
## copy of our bean plays it.

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
	await wait_seconds(AvatarVisuals.EMOTE_SECONDS - 1.0 + 0.4)
	assert_false(v.is_emoting(), "over after ~2.5 s")
	assert_eq(v.emote_id, &"")


func test_hits_and_walking_off_cut_an_emote_short() -> void:
	var v: AvatarVisuals = await _bean()
	v.emote(&"six_seven")
	v.hit(Vector3.FORWARD, 1.0)
	assert_false(v.is_emoting(), "a hit ends it")
	v.emote(&"thumbs_up")
	await wait_seconds(0.4)
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
	await wait_seconds(AvatarVisuals.EMOTE_SECONDS + 0.3)
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
	var k := InputEventKey.new()
	k.physical_keycode = KEY_5
	k.keycode = KEY_5
	k.pressed = true
	get_tree().root.push_input(k)
	await wait_physics_frames(3)
	assert_eq(scene.local.visuals.emote_id, &"thumbs_up", "key 5 = thumbs up, through the server")
	# A dummy's emote arrives as an event like anyone else's.
	var bot: int = -1
	for pid: int in scene.avatars:
		if pid != scene.local_id:
			bot = pid
	assert_true(scene.server.submit_intent(bot, Intents.make(&"play_emote", {"emote": &"default_dance"}))["ok"])
	await wait_physics_frames(3)
	assert_eq((scene.avatars[bot] as PlayerAvatar).visuals.emote_id, &"default_dance")
	await wait_seconds(AvatarVisuals.EMOTE_SECONDS + 0.3)
	assert_false(scene.local.visuals.is_emoting())
	assert_false((scene.avatars[bot] as PlayerAvatar).visuals.is_emoting())
