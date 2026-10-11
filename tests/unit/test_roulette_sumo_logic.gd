extends GutTest
## Roulette Sumo (MINIGAME_IDEAS #9): the wheel speeds up to a cap and drags beans round, falling
## off (past the rim or below the deck) is out, the seeded ball stays on the deck and knocks beans
## down, a bat hit freezes for 1.5 s and the frozen bean's moves are refused, no shove or grab,
## the last bean wins, the 90 s cap ranks by distance from the centre.

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


func _swing(g: RouletteSumoLogic, p: int, hint: int = -1) -> Dictionary:
	var intent: Dictionary = {"type": &"minigame_action", "kind": "swing"}
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
	assert_almost_eq(RouletteSumoLogic.omega_at(0.0), 0.25, 0.0001)
	assert_almost_eq(RouletteSumoLogic.omega_at(30.0), (0.25 + 1.2) * 0.5, 0.0001)
	assert_almost_eq(RouletteSumoLogic.omega_at(60.0), 1.2, 0.0001)
	assert_almost_eq(RouletteSumoLogic.omega_at(85.0), 1.2, 0.0001, "capped")
	assert_almost_eq(RouletteSumoLogic.speed_factor(1.2), 4.8, 0.0001)
	# The angle is the integral: a fine numeric sum agrees.
	var a: float = 0.0
	var t: float = 0.0
	while t < 70.0:
		a += RouletteSumoLogic.omega_at(t + 0.0005) * 0.001
		t += 0.001
	assert_almost_eq(RouletteSumoLogic.wheel_angle(70.0), a, 0.01)
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
	assert_eq(moved.y, at.y)
	var pit: Vector3 = c + Vector3(9.0, 0.0, 0.0)
	assert_eq(RouletteSumoLogic.drift(pit, 1.0, 0.1), pit, "off the deck nothing drags")


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


func test_ball_knocks_down_and_pushes() -> void:
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
	assert_almost_eq(float(dir[1]), 1.0, 0.05, "pushed along the ball's roll")
	assert_eq(g.pending_knockdowns.size(), 1)
	assert_eq(StringName(g.pending_knockdowns[0]["cause"]), &"ball")
	assert_almost_eq(float(g.pending_knockdowns[0]["seconds"]), 1.5, 0.001)
	assert_true(g.is_down(2))
	# No second hit while down and just after.
	g.ball_pos = Vector2(3.0, 0.0)
	assert_eq(_of(_run(g, STEP), &"roulette_sumo_ball_hit").size(), 0)
	_run(g, 1.6)
	assert_false(g.is_down(2), "up after 1.5 s")


func test_bat_freezes_for_a_moment_and_frozen_moves_are_refused() -> void:
	var g: RouletteSumoLogic = _game([1, 2, 3])
	_run(g, 0.2)
	_face(g, 1, 2, 1.2)
	var res: Dictionary = _swing(g, 1)
	assert_true(res["ok"], "swing: %s" % res)
	assert_eq(res["result"], &"hit")
	assert_true(g.is_frozen(2))
	assert_eq(g.pending_knockdowns.size(), 0, "a bat hit freezes, it doesn't knock down")
	assert_eq(_swing(g, 1)["error"], &"cooldown")
	assert_eq(_swing(g, 2)["error"], &"frozen", "a frozen bean can't swing")
	var pin: Vector3 = g.frozen_pin[2]
	assert_eq(g.clamp_position(2, pin + Vector3(3.0, 0, 0)), pin, "can't walk away")
	assert_eq(g.clamp_position(2, pin + Vector3(0.2, 0, 0)), pin + Vector3(0.2, 0, 0), "small lag is fine")
	_run(g, 0.5)
	var drifted: Vector3 = g.frozen_pin[2]
	assert_gt(drifted.distance_to(pin), 0.1, "the frozen bean still slides with the wheel")
	assert_gt(RouletteSumoLogic.flat_radius(drifted), RouletteSumoLogic.flat_radius(pin), "toward the edge")
	assert_eq(g.clamp_position(2, drifted), drifted, "the client's drifted report is accepted")
	var evs: Array[Dictionary] = _run(g, 1.1)
	assert_false(g.is_frozen(2), "thawed after 1.5 s")
	assert_eq(_of(evs, &"roulette_sumo_thawed").size(), 1)
	assert_eq(g.clamp_position(2, pin + Vector3(3.0, 0, 0)), pin + Vector3(3.0, 0, 0), "free to move again")
	# Just thawed: a fresh swing can't re-freeze them at once.
	_run(g, 0.5)
	_face(g, 1, 2, 1.2)
	assert_eq(_swing(g, 1)["result"], &"thawing")


func test_swing_miss_and_no_shove_or_grab() -> void:
	var g: RouletteSumoLogic = _game([1, 2])
	_run(g, 0.2)
	_face(g, 1, 2, 5.0)
	assert_eq(_swing(g, 1)["result"], &"miss")
	assert_true(g.blocks_intent(&"shove"))
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
	_face(g, 1, 2, 1.2)
	_swing(g, 1)
	var st: Dictionary = g.get_public_state()
	for k: String in ["clock", "angle", "omega", "ball", "frozen", "down", "alive", "room"]:
		assert_true(st.has(k), "state has %s" % k)
	assert_true((st["frozen"] as Dictionary).has(2))
	assert_eq(StringName(st["minigame"]), &"roulette_sumo")
