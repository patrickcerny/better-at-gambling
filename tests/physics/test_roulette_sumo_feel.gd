extends GutTest
## Roulette Sumo with real bodies on the real wheel (Patrick 2026-10-16: "way too slow, it doesn't
## drag you enough outside and it's too easy. No bats, just pushing that gives you a little push,
## no knockout"): our bean standing still on its spawn is flung over the rim within a few seconds
## of the wheel starting, and a push slides it about a metre and leaves it standing. No bats on
## anybody.

var scene: MatchScene


func before_each() -> void:
	Net.stop()
	MatchScene.test_dummies = 2
	MatchScene.test_briefing = 0.0
	MatchScene.test_curtain_fast = true
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_process_frames(3)


func after_each() -> void:
	MatchScene.test_dummies = 0
	MatchScene.test_briefing = -1.0
	MatchScene.test_curtain_fast = false


func _wait_for(cond: Callable, seconds: float = 3.0) -> bool:
	var t: float = 0.0
	while not cond.call() and t < seconds:
		await wait_physics_frames(1)
		t += get_physics_process_delta_time()
	return cond.call()


## Opens the Roulette Sumo room as a client would see it (`hold` > 0: the rules card is still up,
## the wheel stands still).
func _open(hold: float) -> RouletteSumoStage:
	var ids: Array[int] = []
	for pid: int in scene.avatars:
		ids.append(pid)
	var logic := RouletteSumoLogic.new()
	logic.setup(ids, SeededRng.new(5), BalanceConfig.new(), {}, {})
	# The local server isn't running the game: let our bean walk in the room without being snapped
	# back as off the map.
	scene.server.sanity.open_room(logic.arena)
	var start: Dictionary = {"minigame": &"roulette_sumo", "players": ids, "room": logic.room_wire()}
	if hold > 0.0:
		start["briefing"] = hold
	scene._open_stage(start, {})
	assert_true(await _wait_for(func() -> bool: return scene.stage is RouletteSumoStage), "stage built")
	var st: RouletteSumoStage = scene.stage as RouletteSumoStage
	st.ball_node.visible = false
	st.ball_pos = Vector2(0.0, -RouletteSumoLogic.BALL_MIN_R)  # the ball is the server's business
	st.ball_vel = Vector2.ZERO
	return st


func test_standing_still_flings_you_off_within_seconds() -> void:
	var st: RouletteSumoStage = await _open(0.0)
	var me: PlayerAvatar = scene.local
	assert_true(await _wait_for(func() -> bool: return me.is_on_floor(), 2.0), "standing on the deck")
	await wait_physics_frames(2)
	var r0: float = RouletteSumoLogic.flat_radius(me.global_position)
	assert_almost_eq(r0, WheelRoom.SPAWN_RADIUS, 0.6, "on the spawn ring")
	assert_true(st.going, "the wheel turns")
	var t: float = 0.0
	var deck_y: float = WheelRoom.center().y + WheelRoom.WHEEL_TOP
	while t < 6.0:
		await wait_physics_frames(1)
		t += get_physics_process_delta_time()
		if RouletteSumoLogic.flat_radius(me.global_position) > RouletteSumoLogic.FALL_RADIUS or me.global_position.y < deck_y - RouletteSumoLogic.FALL_DEPTH:
			break
	# The wheel started when the room opened (no rules card): its clock is the time on the deck.
	gut.p("a bean standing still on the real wheel went over after %.2f s of wheel time" % st.clock)
	assert_lt(t, 6.0, "went over")
	assert_lt(st.clock, 4.0, "dragged off within a few seconds")
	assert_gt(st.clock, 1.5, "but not at once")
	assert_eq(st.get_node_or_null(^"SumoBat"), null)
	for a: PlayerAvatar in scene.avatars.values():
		assert_eq(a.visuals.find_child("SumoBat", true, false), null, "no bats")


func test_a_push_slides_you_about_a_metre_and_you_stay_up() -> void:
	var st: RouletteSumoStage = await _open(30.0)
	assert_false(st.going, "rules card up: the wheel stands still")
	var me: PlayerAvatar = scene.local
	assert_true(await _wait_for(func() -> bool: return me.is_on_floor(), 2.0), "standing on the deck")
	await wait_physics_frames(5)
	var other: int = -1
	for pid: int in scene.avatars:
		if pid != scene.local_id:
			other = pid
	var from: Vector3 = me.global_position
	# Pushed sideways along the ring (the deck is flat there for a good metre).
	var c: Vector3 = WheelRoom.center()
	var out := Vector3(from.x - c.x, 0.0, from.z - c.z).normalized()
	var side: Vector3 = out.cross(Vector3.UP).normalized()
	st.on_event({"type": &"roulette_sumo_push", "player": other, "target": scene.local_id, "dir": [side.x, side.z], "strength": RouletteSumoLogic.PUSH_STRENGTH})
	var worst: int = PlayerAvatar.State.STANDING
	var t: float = 0.0
	while t < 1.5:
		await wait_physics_frames(1)
		t += get_physics_process_delta_time()
		if me.state != PlayerAvatar.State.STANDING:
			worst = me.state
	var moved: Vector3 = me.global_position - from
	moved.y = 0.0
	gut.p("a push slid our bean %.2f m" % moved.length())
	assert_between(moved.length(), 0.5, 1.6, "a little push, about a metre")
	assert_gt(moved.normalized().dot(side), 0.9, "along the push")
	assert_eq(worst, PlayerAvatar.State.STANDING, "never down, never stunned, never a ragdoll")
