extends GutTest
## Roulette Sumo (MINIGAME_IDEAS #9): the wheel speeds up to a cap and drags beans round and hard
## toward the rim (a bean standing still is off within a few seconds; one walking has to work to
## stay on), falling off (past the rim or below the deck) is out, the seeded ball stays on the deck
## and bumps beans (no knockdown), no bats: a push nudges the bean in front (cooldown, never a
## knockdown, knockout or elimination by itself), the casino's shove and grab are off, the last
## bean wins, the time cap ranks by distance from the centre.

const STEP: float = 0.05

var cfg: BalanceConfig = BalanceConfig.new()


func _game(players: Array[int], seed_value: int = 7) -> RouletteSumoLogic:
	var g := RouletteSumoLogic.new()
	g.setup(players, SeededRng.new(seed_value), cfg, {}, {})
	g.world = WorldQuery.new()
	for p: int in players:
		g.world.set_transform(p, g.spawn_for(p), g.spawn_yaw_for(p))
	# Park the ball far from everyone unless a test moves it.
	g.ball_pos = Vector2(0, -RouletteSumoLogic.BALL_MIN_R)
	g.ball_vel = Vector2.ZERO
	g.ball_turn = 0.0
	g.seg_left = 1000.0
	return g


func _run(g: RouletteSumoLogic, seconds: float) -> Array[Dictionary]:
	var seen: Array[Dictionary] = []
	var t: float = 0.0
	while t < seconds - 0.0001:
		g.tick(STEP, 0.0)
		t += STEP
		seen.append_array(g.drain_events())
	return seen


func _of(evs: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	return evs.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## A deck position at radius `r` and angle `a` round the wheel.
func _deck(r: float, a: float = 0.0) -> Vector3:
	return WheelRoom.center() + Vector3(sin(a) * r, WheelRoom.WHEEL_TOP, cos(a) * r)


## `a` stands `dist` metres from `b` on the deck, facing them.
func _face(g: RouletteSumoLogic, a: int, b: int, dist: float) -> void:
	var bp: Vector3 = _deck(3.0, 0.0)
	g.world.set_transform(b, bp, 0.0)
	var ap: Vector3 = bp + Vector3(dist, 0, 0)
	var d: Vector3 = (bp - ap).normalized()
	g.world.set_transform(a, ap, atan2(-d.x, -d.z))


func _push(g: RouletteSumoLogic, p: int, hint: int = -1) -> Dictionary:
	var intent: Dictionary = {"type": &"minigame_action", "kind": "push"}
	if hint >= 0:
		intent["target"] = hint
	return g.submit(p, intent, 0.0)


func test_room_and_announce() -> void:
	var g: RouletteSumoLogic = _game([1, 2, 3])
	for p: int in [1, 2, 3]:
		assert_true(RouletteSumoLogic.on_deck(g.spawn_for(p)), "spawn %d is on the wheel" % p)
		assert_true(g.arena.has_point(g.spawn_for(p)))
	assert_true(g.arena.has_point(WheelRoom.center() + Vector3(RouletteSumoLogic.FALL_RADIUS + 1.0, 0.1, 0)), "the pit is in the arena")
	var evs: Array[Dictionary] = _run(g, STEP)
	assert_eq(_of(evs, &"roulette_sumo_begin").size(), 1)
	assert_eq(_of(evs, &"roulette_sumo_wheel").size(), 1, "the wheel is announced on the first tick")


func test_wheel_speeds_up_to_a_cap() -> void:
	assert_almost_eq(RouletteSumoLogic.omega_at(0.0), 0.55, 0.0001)
	assert_almost_eq(RouletteSumoLogic.omega_at(12.5), (0.55 + 1.4) * 0.5, 0.0001)
	assert_almost_eq(RouletteSumoLogic.omega_at(25.0), 1.4, 0.0001, "full speed after 25 s")
	assert_almost_eq(RouletteSumoLogic.omega_at(55.0), 1.4, 0.0001, "capped")
	assert_almost_eq(RouletteSumoLogic.speed_factor(1.4), 1.4 / 0.55, 0.0001)
	assert_almost_eq(RouletteSumoLogic.ramp_fraction(0.55), 0.0, 0.0001)
	assert_almost_eq(RouletteSumoLogic.ramp_fraction(1.4), 1.0, 0.0001)
	# The angle is the integral: a fine numeric sum agrees.
	var a: float = 0.0
	var t: float = 0.0
	while t < 40.0:
		a += RouletteSumoLogic.omega_at(t + 0.0005) * 0.001
		t += 0.001
	assert_almost_eq(RouletteSumoLogic.wheel_angle(40.0), a, 0.01)
	var g: RouletteSumoLogic = _game([1, 2])
	_run(g, 2.0)
	assert_almost_eq(g.get_public_state()["omega"], RouletteSumoLogic.omega_at(2.0), 0.001)
	assert_eq(_of(_run(g, 3.0), &"roulette_sumo_wheel").size(), 3, "re-sent once per second")


func test_standing_beans_turn_with_the_wheel() -> void:
	var at: Vector3 = _deck(4.0, 0.0)
	var moved: Vector3 = RouletteSumoLogic.drift(at, 1.0, 0.1)
	var c: Vector3 = WheelRoom.center()
	var a0: float = atan2(at.x - c.x, at.z - c.z)
	var a1: float = atan2(moved.x - c.x, moved.z - c.z)
	assert_almost_eq(wrapf(a1 - a0, -PI, PI), 0.1, 0.001, "turned by omega * dt")
	assert_gt(RouletteSumoLogic.flat_radius(moved), 4.0, "and flung outward a little")
	assert_almost_eq(RouletteSumoLogic.flat_radius(moved), 4.0 * (1.0 + RouletteSumoLogic.SLIDE * 0.1), 0.0001)
	assert_almost_eq(RouletteSumoLogic.outward_speed(4.0, 1.0), RouletteSumoLogic.SLIDE * 4.0, 0.0001)
	assert_eq(moved.y, at.y)
	var pit: Vector3 = c + Vector3(9.0, 0.0, 0.0)
	assert_eq(RouletteSumoLogic.drift(pit, 1.0, 0.1), pit, "off the deck nothing drags")


## Like a client: every step the wheel drags the bean (`drift`) and it walks `walk` m/s straight
## at the centre (0 = standing still); the server ticks on the reported position. Returns the
## seconds until the bean is out, or -1 if it stays on for `limit` seconds.
func _seconds_on(g: RouletteSumoLogic, p: int, walk: float, limit: float) -> float:
	var t: float = 0.0
	var c: Vector3 = WheelRoom.center()
	while t < limit:
		var omega: float = RouletteSumoLogic.omega_at(g.clock)
		var at: Vector3 = RouletteSumoLogic.drift(g.world.get_position(p), omega, STEP)
		var inward := Vector3(c.x - at.x, 0.0, c.z - at.z)
		if walk > 0.0 and inward.length() > WheelRoom.HUB_RADIUS + 0.4:
			at += inward.normalized() * walk * STEP
		g.world.set_transform(p, at, 0.0)
		g.tick(STEP, 0.0)
		g.drain_events()
		t += STEP
		if not g.is_alive(p):
			return t
	return -1.0


## Patrick 2026-10-16: "way too slow, it doesn't drag you enough outside". A bean that stands
## still on its spawn ring is flung off within a few seconds from the very start (it was 22 s),
## and within a second at full speed (it was 3 s).
func test_standing_still_gets_dragged_off_within_seconds() -> void:
	var g: RouletteSumoLogic = _game([1, 2])
	assert_almost_eq(RouletteSumoLogic.flat_radius(g.spawn_for(1)), WheelRoom.SPAWN_RADIUS, 0.01)
	g.world.set_transform(2, _deck(1.5), 0.0)  # the other bean stays on so the game runs on
	var t: float = _seconds_on(g, 1, 0.0, 10.0)
	gut.p("standing still from the spawn at the start: off after %.2f s" % t)
	assert_gt(t, 1.5, "a moment to react")
	assert_lt(t, 3.5, "off within a few seconds")
	var h: RouletteSumoLogic = _game([1, 2])
	h.world.set_transform(2, _deck(1.5), 0.0)
	h.world.set_transform(1, _deck(1.5, 2.0), 0.0)
	_run(h, RouletteSumoLogic.RAMP_SECONDS)
	h.world.set_transform(1, _deck(WheelRoom.SPAWN_RADIUS, 0.5), 0.0)
	t = _seconds_on(h, 1, 0.0, 10.0)
	gut.p("standing still from the spawn at full speed: off after %.2f s" % t)
	assert_gt(t, 0.0)
	assert_lt(t, 1.0, "at full speed it's quick")


## Walking keeps you on, but it is work: at full speed the pull at the spawn ring eats most of a
## walk, past about 5.6 m only a sprint gets you back, and a bean walking in holds on.
func test_walking_beans_have_to_work_to_stay_on() -> void:
	var walk: float = cfg.walk_speed
	var pull: float = RouletteSumoLogic.outward_speed(WheelRoom.SPAWN_RADIUS, RouletteSumoLogic.OMEGA_MAX)
	assert_gt(pull, walk * 0.6, "the pull at the spawn ring is most of a walk (%.2f m/s)" % pull)
	assert_lt(pull, walk, "but walking in still wins there")
	assert_gt(RouletteSumoLogic.outward_speed(6.0, RouletteSumoLogic.OMEGA_MAX), walk, "near the rim walking isn't enough")
	assert_lt(RouletteSumoLogic.outward_speed(6.0, RouletteSumoLogic.OMEGA_MAX), cfg.sprint_speed, "a sprint is")
	assert_gt(RouletteSumoLogic.outward_speed(WheelRoom.SPAWN_RADIUS, RouletteSumoLogic.OMEGA_START), 0.5, "even at the start the pull is felt")
	var g: RouletteSumoLogic = _game([1, 2])
	g.world.set_transform(2, _deck(1.5), 0.0)
	g.world.set_transform(1, _deck(1.5, 2.0), 0.0)
	_run(g, RouletteSumoLogic.RAMP_SECONDS)
	g.world.set_transform(1, _deck(WheelRoom.SPAWN_RADIUS, 0.5), 0.0)
	assert_eq(_seconds_on(g, 1, walk, 10.0), -1.0, "a bean walking in at full speed stays on")
	var h: RouletteSumoLogic = _game([1, 2])
	h.world.set_transform(2, _deck(1.5), 0.0)
	h.world.set_transform(1, _deck(1.5, 2.0), 0.0)
	_run(h, RouletteSumoLogic.RAMP_SECONDS)
	h.world.set_transform(1, _deck(6.0, 0.5), 0.0)
	assert_gt(_seconds_on(h, 1, walk, 10.0), 0.0, "caught near the rim at full speed, walking in loses")


func test_falling_off_eliminates_past_the_rim_and_below_the_deck() -> void:
	var g: RouletteSumoLogic = _game([1, 2, 3, 4])
	_run(g, 0.5)
	g.world.set_transform(1, _deck(RouletteSumoLogic.FALL_RADIUS + 0.2, 1.0), 0.0)
	var evs: Array[Dictionary] = _run(g, STEP)
	var out: Array[Dictionary] = _of(evs, &"minigame_eliminated")
	assert_eq(out.size(), 1)
	assert_eq(out[0]["players"], [1])
	assert_eq(StringName(out[0]["cause"]), &"fell")
	assert_eq(int(out[0]["place"]), 4)
	assert_true(g.pending_moves.has(1), "off to the gallery")
	assert_eq(g.pending_knockdowns.filter(func(k: Dictionary) -> bool: return int(k["player"]) == 1).size(), 1, "tumbles first")
	# Inside the radius but dropped below the deck (a hole is still a fall).
	g.world.set_transform(2, _deck(3.0) - Vector3(0, RouletteSumoLogic.FALL_DEPTH + 0.2, 0), 0.0)
	out = _of(_run(g, STEP), &"minigame_eliminated")
	assert_eq(out.size(), 1)
	assert_eq(out[0]["players"], [2])
	# Standing on the edge but on the deck is fine.
	g.world.set_transform(3, _deck(WheelRoom.RIM_RADIUS - 0.1), 0.0)
	assert_eq(_of(_run(g, 0.2), &"minigame_eliminated").size(), 0)


func test_ball_path_stays_on_the_deck_and_is_deterministic() -> void:
	var paths: Array = []
	for run: int in 2:
		var g := RouletteSumoLogic.new()
		g.setup([1, 2] as Array[int], SeededRng.new(42), cfg, {}, {})
		g.world = WorldQuery.new()
		var path: Array[Vector2] = []
		var turns: int = 0
		for i: int in 1200:  # 60 s
			g.tick(STEP, 0.0)
			turns += _of(g.drain_events(), &"roulette_sumo_ball").size()
			var r: float = g.ball_pos.length()
			assert_true(r <= RouletteSumoLogic.BALL_MAX_R + 0.001 and r >= RouletteSumoLogic.BALL_MIN_R - 0.001, "ball on the deck (r %.2f)" % r)
			var speed: float = g.ball_vel.length()
			assert_true(speed >= RouletteSumoLogic.BALL_MIN_SPEED - 0.01 and speed <= RouletteSumoLogic.BALL_MAX_SPEED + 0.01, "speed %.2f" % speed)
			path.append(g.ball_pos)
		assert_gt(turns, 60, "segment changes and the 1 s re-sync go out")
		paths.append(path)
	assert_eq(paths[0], paths[1], "same seed, same path")
	var other := RouletteSumoLogic.new()
	other.setup([1, 2] as Array[int], SeededRng.new(43), cfg, {}, {})
	assert_ne(other.ball_pos, (paths[0] as Array)[0], "another seed rolls elsewhere")
	# The client predicts with the same step: it matches the server between updates.
	var p := Vector2(5.5, 0.0)
	var v := Vector2(0.0, 6.0)
	var res: Array[Vector2] = RouletteSumoLogic.step_ball(p, v, 0.4, 0.05)
	assert_almost_eq(res[1].length(), 6.0, 0.001)


func test_ball_bumps_without_knocking_down() -> void:
	var g: RouletteSumoLogic = _game([1, 2, 3])
	_run(g, 0.2)
	var c: Vector3 = WheelRoom.center()
	g.ball_pos = Vector2(3.0, 0.0)
	g.ball_vel = Vector2(0.0, 5.0)
	g.world.set_transform(2, c + Vector3(3.6, WheelRoom.WHEEL_TOP, 0.0), 0.0)
	g.pending_knockdowns.clear()
	var evs: Array[Dictionary] = _run(g, STEP)
	var hits: Array[Dictionary] = _of(evs, &"roulette_sumo_ball_hit")
	assert_eq(hits.size(), 1)
	assert_eq(int(hits[0]["player"]), 2)
	var dir: Array = hits[0]["dir"]
	assert_gt(float(dir[1]), 0.5, "pushed along the ball's roll")
	assert_gt(float(dir[0]), 0.0, "and away from it")
	assert_almost_eq(float(hits[0]["strength"]), RouletteSumoLogic.BALL_PUSH, 0.001)
	assert_eq(g.pending_knockdowns.size(), 0, "a bump, not a knockdown")
	assert_true(g.is_alive(2))
	# Not again straight away.
	g.ball_pos = Vector2(3.0, 0.0)
	assert_eq(_of(_run(g, STEP), &"roulette_sumo_ball_hit").size(), 0)
	_run(g, RouletteSumoLogic.BALL_GRACE)
	g.ball_pos = Vector2(3.0, 0.0)
	assert_eq(_of(_run(g, STEP), &"roulette_sumo_ball_hit").size(), 1, "the ball can bump again later")


## Patrick 2026-10-16: "no bats, just pushing that gives you a little push (no knockout)".
func test_push_nudges_the_bean_in_front() -> void:
	var g: RouletteSumoLogic = _game([1, 2, 3])
	_run(g, 0.2)
	_face(g, 1, 2, 1.2)
	var res: Dictionary = _push(g, 1)
	assert_true(res["ok"], "push: %s" % res)
	assert_eq(int(res["target"]), 2)
	assert_eq(res["result"], &"push")
	var evs: Array[Dictionary] = g.drain_events()
	var pushes: Array[Dictionary] = _of(evs, &"roulette_sumo_push")
	assert_eq(pushes.size(), 1)
	assert_eq(int(pushes[0]["player"]), 1)
	assert_eq(int(pushes[0]["target"]), 2)
	var dir: Array = pushes[0]["dir"]
	assert_almost_eq(float(dir[0]), -1.0, 0.01, "away from the pusher (who stands at +x)")
	assert_almost_eq(float(pushes[0]["strength"]), RouletteSumoLogic.PUSH_STRENGTH, 0.001)
	# A little push: at the avatar's 8 m/s^2 push decay it slides v^2 / 16, about a metre.
	var slide: float = RouletteSumoLogic.PUSH_STRENGTH * RouletteSumoLogic.PUSH_STRENGTH / 16.0
	assert_between(slide, 0.5, 1.5, "about a metre (%.2f m)" % slide)
	assert_lt(RouletteSumoLogic.PUSH_STRENGTH, InteractionResolver.SHOVE_KNOCKBACK * MatchScene.SHOVE_PUSH_SCALE, "gentler than the casino shove")
	assert_eq(g.pending_knockdowns.size(), 0, "no knockdown")
	assert_eq(_of(evs, &"minigame_eliminated").size(), 0, "no elimination")
	assert_eq(g.pushes[1], 1)
	_run(g, 0.2)
	assert_true(g.is_alive(2), "still on the wheel")
	assert_false(g.has_method(&"is_frozen"), "no freezing any more")


func test_push_cooldown_and_miss() -> void:
	var g: RouletteSumoLogic = _game([1, 2])
	_run(g, 0.2)
	_face(g, 1, 2, 1.2)
	assert_true(_push(g, 1)["ok"])
	assert_eq(_push(g, 1)["error"], &"cooldown", "a short cooldown")
	assert_gt(float(g.private_state(1)["cooldown"]), 0.0)
	_run(g, RouletteSumoLogic.PUSH_COOLDOWN * 0.5)
	assert_eq(_push(g, 1)["error"], &"cooldown")
	_run(g, RouletteSumoLogic.PUSH_COOLDOWN * 0.5 + STEP)
	assert_true(_push(g, 1)["ok"], "and again")
	assert_lt(RouletteSumoLogic.PUSH_COOLDOWN, 1.5, "short")
	assert_true(_push(g, 2)["ok"], "each bean has its own cooldown")
	_run(g, RouletteSumoLogic.PUSH_COOLDOWN + STEP)
	_face(g, 1, 2, 5.0)
	var res: Dictionary = _push(g, 1)
	assert_true(res["ok"], "a miss is fine")
	assert_eq(res["result"], &"miss")
	assert_eq(int(res["target"]), -1)
	assert_eq(_push(g, 1)["error"], &"cooldown", "a miss costs the cooldown too")
	assert_eq(g.submit(1, {"type": &"minigame_action", "kind": "swing"}, 0.0)["error"], &"bad_value", "no bats")


## However often a bean is pushed, the push itself never knocks it down, out or off: only leaving
## the wheel does.
func test_pushes_never_knock_down_or_eliminate() -> void:
	var g: RouletteSumoLogic = _game([1, 2, 3])
	_run(g, 0.2)
	for i: int in 12:
		_face(g, 1 + i % 2, 3, 1.0)
		assert_true(_push(g, 1 + i % 2)["ok"])
		_run(g, RouletteSumoLogic.PUSH_COOLDOWN * 0.5 + STEP)
	assert_eq(g.pushes[1] + g.pushes[2], 12)
	assert_eq(g.pending_knockdowns.size(), 0)
	assert_true(g.is_alive(3))
	assert_eq(g.alive.size(), 3)


func test_no_shove_or_grab() -> void:
	var g: RouletteSumoLogic = _game([1, 2])
	assert_true(g.blocks_intent(&"shove"), "the casino shove (knockdowns, knockouts) is off")
	assert_true(g.blocks_intent(&"grab"))
	assert_true(g.blocks_intent(&"release"))
	assert_false(g.blocks_intent(&"move"))
	assert_false(g.blocks_intent(&"minigame_action"))


func test_last_bean_wins() -> void:
	var g: RouletteSumoLogic = _game([1, 2, 3])
	_run(g, 0.5)
	g.world.set_transform(3, _deck(9.0), 0.0)
	_run(g, 0.5)
	g.world.set_transform(1, _deck(9.0, 2.0), 0.0)
	var evs: Array[Dictionary] = _run(g, STEP)
	var over: Array[Dictionary] = _of(evs, &"roulette_sumo_over")
	assert_eq(over.size(), 1)
	assert_eq(int(over[0]["winner"]), 2)
	assert_eq(g.state, RouletteSumoLogic.State.DONE)
	_run(g, RouletteSumoLogic.END_HOLD + 0.1)
	assert_true(g.is_finished())
	var r: Array[Dictionary] = g.ranking()
	assert_eq(r.map(func(row: Dictionary) -> int: return int(row["player"])), [2, 1, 3])
	assert_eq(r.map(func(row: Dictionary) -> int: return int(row["rank"])), [1, 2, 3])
	assert_eq(int(r[0]["points"]), 2)


func test_time_cap_ranks_by_distance_from_the_centre() -> void:
	var g: RouletteSumoLogic = _game([1, 2, 3, 4])
	_run(g, 0.5)
	g.world.set_transform(4, _deck(9.0), 0.0)
	_run(g, 0.1)
	g.world.set_transform(1, _deck(5.5, 0.3), 0.0)
	g.world.set_transform(2, _deck(2.0, 1.3), 0.0)
	g.world.set_transform(3, _deck(4.0, 2.3), 0.0)
	var evs: Array[Dictionary] = _run(g, RouletteSumoLogic.GAME_SECONDS)
	var over: Array[Dictionary] = _of(evs, &"roulette_sumo_over")
	assert_eq(over.size(), 1)
	assert_eq(StringName(over[0]["reason"]), &"time")
	assert_eq(int(over[0]["winner"]), 2)
	var r: Array[Dictionary] = g.ranking()
	assert_eq(r.map(func(row: Dictionary) -> int: return int(row["player"])), [2, 3, 1, 4])
	assert_eq(r.map(func(row: Dictionary) -> int: return int(row["rank"])), [1, 2, 3, 4])


func test_dropout_and_two_players() -> void:
	var g: RouletteSumoLogic = _game([1, 2])
	_run(g, 0.5)
	g.remove_player(2)
	var evs: Array[Dictionary] = _run(g, STEP)
	assert_eq(g.state, RouletteSumoLogic.State.DONE, "one bean left: the game is over")
	_run(g, RouletteSumoLogic.END_HOLD + 0.1)
	assert_true(g.is_finished())
	var r: Array[Dictionary] = g.ranking()
	assert_eq(r.size(), 1, "the dropout leaves the ranking")
	assert_eq(int(r[0]["player"]), 1)
	# A plain 2-player game: one falls, the other wins.
	var h: RouletteSumoLogic = _game([5, 6], 3)
	_run(h, 1.0)
	h.world.set_transform(5, _deck(9.0), 0.0)
	_run(h, STEP)
	assert_eq(h.winner, 6)
	assert_eq(h.ranking()[0]["player"], 6)


func test_public_state_carries_the_catch_up() -> void:
	var g: RouletteSumoLogic = _game([1, 2])
	_run(g, 1.0)
	var st: Dictionary = g.get_public_state()
	for k: String in ["clock", "angle", "omega", "ball", "alive", "room"]:
		assert_true(st.has(k), "state has %s" % k)
	assert_false(st.has("frozen"), "no bats, nothing frozen")
	assert_eq(StringName(st["minigame"]), &"roulette_sumo")
