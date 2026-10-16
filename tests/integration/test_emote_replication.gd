extends GutTest
## Emotes across the wire: one player's emote (wheel or number key) reaches the server as an
## intent, comes back as an event every client gets, and another client's copy of that player acts
## it out while that client's own camera stays where it is. A player joining while it plays gets it
## in the snapshot and picks it up part-way through. Money never moves for any of it.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(2)
	fx.server.start_match()
	fx.run(3.1)


func after_each() -> void:
	fx.server.free()


## What client `me` has: its own local avatar (camera) and a puppet for everyone else.
func _client(me: int) -> Dictionary:
	var avatars: Dictionary = {}
	for pid: int in fx.player_ids:
		var a := PlayerAvatar.new()
		a.player_id = pid
		a.is_local = pid == me
		if pid != me:
			a.drive = PlayerAvatar.Drive.PUPPET
		add_child_autofree(a)
		a.teleport(Vector3(pid * 2.0, 0.0, 0.0), 0.0)
		avatars[pid] = a
	return avatars


## The event as another client receives it (through the wire encoding).
func _over_the_wire(ev: Dictionary) -> Dictionary:
	assert_true(Serializer.is_wire_safe(ev), str(ev))
	return bytes_to_var(var_to_bytes(ev)) as Dictionary


func test_another_client_sees_a_wheel_emote_and_a_key_emote() -> void:
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	var money: int = fx.server.economy.balance(a)
	var on_b: Dictionary = _client(b)
	await wait_physics_frames(2)
	assert_true(fx.intent(a, &"emote", {"id": &"laugh"})["ok"])
	var ev: Dictionary = _over_the_wire(fx.of_type(&"emote").back())
	assert_eq(int(ev["player"]), a)
	assert_true(EmoteWheel.apply_event(on_b, ev))
	var a_on_b: PlayerAvatar = on_b[a]
	assert_eq(a_on_b.visuals.emote_id, &"laugh", "B sees A laugh")
	assert_eq(a_on_b.bubble.text, Emotes.bubble_text(&"laugh"))
	var b_self: PlayerAvatar = on_b[b]
	assert_false(b_self.cam.emote_view, "B's camera ignores A's emote")
	assert_true(fx.intent(a, &"play_emote", {"emote": &"six_seven"})["ok"])
	ev = _over_the_wire(fx.of_type(&"player_emote").back())
	assert_true(EmoteWheel.apply_event(on_b, ev))
	assert_eq(a_on_b.visuals.emote_id, &"six_seven", "the new emote replaces the laugh")
	assert_eq(a_on_b.bubble.text, "6 7")
	# Emote time steps at most 1/30 s per frame, so wait on it rather than the wall clock.
	await wait_until(func() -> bool: return not a_on_b.visuals.is_emoting(), Emotes.SECONDS * 4.0)
	assert_false(a_on_b.visuals.is_emoting(), "and ends on B's screen too")
	assert_eq(fx.server.economy.balance(a), money, "emotes never touch money")
	assert_false(EmoteWheel.apply_event(on_b, {"type": &"money_changed"}), "other events are not emotes")


func test_the_emoter_watches_their_own_in_third_person() -> void:
	var a: int = fx.player_ids[0]
	var on_a: Dictionary = _client(a)
	await wait_physics_frames(2)
	assert_true(fx.intent(a, &"emote", {"id": &"wave"})["ok"])
	EmoteWheel.apply_event(on_a, _over_the_wire(fx.of_type(&"emote").back()))
	var me: PlayerAvatar = on_a[a]
	assert_true(me.cam.emote_view, "our own emote: third-person view")
	assert_eq(me.visuals.emote_id, &"wave")


func test_a_late_joiner_picks_up_an_emote_still_playing() -> void:
	var a: int = fx.player_ids[0]
	assert_true(fx.intent(a, &"emote", {"id": &"cry"})["ok"])
	fx.run(1.0)
	var snap: Dictionary = fx.server.get_snapshot()
	assert_true(Serializer.is_wire_safe(snap))
	var st := ClientMatchState.new()
	st.apply_snapshot(bytes_to_var(var_to_bytes(snap)) as Dictionary)
	assert_true(st.emotes.has(a), "the snapshot carries A's emote")
	assert_eq(StringName(st.emotes[a]["id"]), &"cry")
	assert_almost_eq(float(st.emotes[a]["t"]), 1.0, 0.11, "and how far in it is")
	var late: int = fx.server.add_player("dev:late", "Late")
	fx.player_ids.append(late)
	var on_late: Dictionary = _client(late)
	await wait_physics_frames(2)
	EmoteWheel.replay(on_late, st.emotes)
	var a_on_late: PlayerAvatar = on_late[a]
	assert_eq(a_on_late.visuals.emote_id, &"cry", "the late joiner sees A still crying")
	assert_gt(a_on_late.visuals.emote_time, 0.9, "part-way through, not from the start")
	assert_false((on_late[late] as PlayerAvatar).cam.emote_view, "a replay never moves a camera")
	fx.run(2.0)
	assert_false(fx.server.get_snapshot()["emotes"].has(a), "a finished emote leaves the snapshot")
