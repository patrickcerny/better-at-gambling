extends GutTest
## Dodge the Dice (MINIGAME_IDEAS #15): height is progress up the tilted board from the server's
## positions, standing on the landing finishes in order, the hazard rate grows, the seeded paths
## stay on the board and match on every machine, a hit knocks down and slides back, immunity after
## getting up, the landing is safe, the 90 s cap ranks by height with shared ties, last call,
## dropouts and two players.

const STEP: float = 0.05

var cfg: BalanceConfig = BalanceConfig.new()


func _game(players: Array[int], seed_value: int = 7) -> DodgeTheDiceLogic:
	var g := DodgeTheDiceLogic.new()
	g.setup(players, SeededRng.new(seed_value), cfg, {}, {})
	g.world = WorldQuery.new()
	for p: int in players:
		g.world.set_transform(p, g.spawn_for(p), g.spawn_yaw_for(p))
	g.next_spawn = INF  # no hazards unless a test wants them
	return g


func _run(g: DodgeTheDiceLogic, seconds: float) -> Array[Dictionary]:
	var seen: Array[Dictionary] = []
	var t: float = 0.0
	while t < seconds - 0.0001:
		g.tick(STEP, 0.0)
		t += STEP
		seen.append_array(g.drain_events())
	return seen


func _of(evs: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	return evs.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## World position standing on `row` at local x `x`, `frac` of the way up its tread.
func _on_row(row: int, x: float = 0.0, frac: float = 0.5) -> Vector3:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var z: float = o.z - (float(row) + frac) * ClimbRoom.ROW_D
	return Vector3(o.x + x, ClimbRoom.surface_y(z), z)


func _landing(x: float = 0.0) -> Vector3:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	return Vector3(o.x + x, ClimbRoom.top_y(), ClimbRoom.top_z() - 2.0)


## A hazard of `kind` that is at `at` (flat) at game clock `t`.
func _hazard_at(kind: StringName, at: Vector3, t: float, id: int = 900) -> Dictionary:
	var speed: float = 8.0
	var s: float = at.z - DodgeTheDiceLogic.start_z()
	return {"id": id, "kind": String(kind), "lane": at.x - WalkableLogicBase.ROOM_ORIGIN.x, "speed": speed, "t0": t - DodgeTheDiceLogic.DROP_TIME - s / speed, "seed": 1}


func test_progress_from_positions() -> void:
	var g: DodgeTheDiceLogic = _game([1, 2, 3])
	for p: int in [1, 2, 3]:
		assert_true(g.arena.has_point(g.spawn_for(p)), "spawn %d in the arena" % p)
		assert_almost_eq(ClimbRoom.progress(g.spawn_for(p)), 0.0, 0.001, "spawns at the bottom")
		assert_false(ClimbRoom.on_top(g.spawn_for(p)))
	var last: float = 0.0
	for row: int in ClimbRoom.ROWS:
		var h: float = ClimbRoom.progress(_on_row(row))
		assert_gt(h, last, "row %d is higher than the one below" % row)
		assert_lt(h, 1.0, "row %d is not the top" % row)
		last = h
	assert_almost_eq(ClimbRoom.progress(_on_row(6)), 0.5, 0.06, "the middle row is about halfway")
	assert_eq(ClimbRoom.progress(_landing()), 1.0, "the landing is the top")
	assert_true(ClimbRoom.on_top(_landing()))
	assert_true(g.arena.has_point(_landing()) and g.arena.has_point(_on_row(12, 6.5)), "the whole climb is in the arena")
	assert_almost_eq(rad_to_deg(ClimbKit.slope_angle(ClimbRoom.flight())), 35.0, 1.5, "tilted ~35 degrees")


func test_finish_order() -> void:
	var g: DodgeTheDiceLogic = _game([1, 2, 3])
	var evs: Array[Dictionary] = _run(g, STEP)
	assert_eq(_of(evs, &"dodge_the_dice_begin").size(), 1, "announced on the first tick")
	g.world.set_transform(2, _on_row(12, 0.0, 0.95), 0.0)
	evs = _run(g, 0.2)
	assert_true(_of(evs, &"dodge_the_dice_top").is_empty(), "the top row is not the top")
	g.world.set_transform(2, _landing(), 0.0)
	evs = _run(g, 0.2)
	var tops: Array[Dictionary] = _of(evs, &"dodge_the_dice_top")
	assert_eq(tops.size(), 1)
	assert_eq(tops[0]["players"], [2])
	assert_eq(int(tops[0]["place"]), 1)
	g.world.set_transform(3, _landing(2.0), 0.0)
	evs = _run(g, 0.2)
	assert_eq(int(_of(evs, &"dodge_the_dice_top")[0]["place"]), 2)
	assert_true(g.is_up(2) and g.is_up(3) and not g.is_up(1))
	var rows: Array[Dictionary] = g.ranking()
	assert_eq([int(rows[0]["player"]), int(rows[1]["player"]), int(rows[2]["player"])], [2, 3, 1])
	assert_true(g.is_untouchable(2), "finishers can't be shoved")
	# A finisher walking back down the board is held on the landing.
	var held: Vector3 = g.clamp_position(2, _on_row(10))
	assert_true(ClimbRoom.on_top(held), "held on the landing: %s" % held)


func test_hazard_rate_grows() -> void:
	assert_almost_eq(DodgeTheDiceLogic.spawn_interval(0.0), 1.6, 0.001)
	assert_almost_eq(DodgeTheDiceLogic.spawn_interval(60.0), 0.7, 0.001)
	assert_almost_eq(DodgeTheDiceLogic.spawn_interval(85.0), 0.7, 0.001)
	assert_lt(DodgeTheDiceLogic.spawn_interval(30.0), 1.6)
	assert_gt(DodgeTheDiceLogic.spawn_interval(30.0), 0.7)
	var g: DodgeTheDiceLogic = _game([1, 2])
	g.next_spawn = DodgeTheDiceLogic.FIRST_SPAWN
	var early: int = _of(_run(g, 10.0), &"dodge_the_dice_hazard").size()
	_run(g, 50.0)
	var late_evs: Array[Dictionary] = _of(_run(g, 10.0), &"dodge_the_dice_hazard")
	var late: int = late_evs.size()
	assert_gt(early, 4)
	assert_gt(late, early + 4, "more hazards later (%d vs %d)" % [late, early])
	var kinds: Dictionary = {}
	for e: Dictionary in late_evs:
		kinds[str(e["kind"])] = true
		for k: String in ["id", "kind", "lane", "speed", "t0", "seed"]:
			assert_true(e.has(k), "hazard event has %s" % k)
	assert_true(g.get_public_state().has("hazards"), "late joiners get the hazards")


func test_paths_are_deterministic_and_stay_on_the_board() -> void:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var g: DodgeTheDiceLogic = _game([1, 2])
	g.next_spawn = DodgeTheDiceLogic.FIRST_SPAWN
	var evs: Array[Dictionary] = _of(_run(g, 40.0), &"dodge_the_dice_hazard")
	assert_gt(evs.size(), 20)
	for ev: Dictionary in evs:
		var h: Dictionary = {"id": ev["id"], "kind": ev["kind"], "lane": ev["lane"], "speed": ev["speed"], "t0": ev["t0"], "seed": ev["seed"]}
		var r: float = DodgeTheDiceLogic.radius_of(StringName(h["kind"]))
		var t0: float = float(h["t0"])
		var t1: float = DodgeTheDiceLogic.end_time(h)
		var prev_z: float = -INF
		var t: float = t0
		while t <= t1:
			var p: Vector3 = DodgeTheDiceLogic.path_at(h, t)
			assert_eq(p, DodgeTheDiceLogic.path_at(h.duplicate(), t), "same path from the same wire")
			if absf(p.x - o.x) > ClimbRoom.HALF_W - r + 0.001 or p.y < ClimbRoom.surface_y(p.z) + r - 0.001 or p.z < prev_z - 0.001:
				fail_test("%s %d left the board or rolled uphill at t=%.2f: %s" % [h["kind"], h["id"], t, p])
				return
			prev_z = p.z
			t += 0.1
		assert_almost_eq(DodgeTheDiceLogic.path_at(h, t0 + DodgeTheDiceLogic.DROP_TIME).z, DodgeTheDiceLogic.start_z(), 0.01, "lands on the top row")
		assert_gt(DodgeTheDiceLogic.path_at(h, t1).z, o.z, "ends past the bottom edge")
	# Coins wobble and dice change lanes; balls run straight.
	var coin: Dictionary = {"id": 1, "kind": "coin", "lane": 0.0, "speed": 5.0, "t0": 0.0, "seed": 4242}
	var dice: Dictionary = {"id": 2, "kind": "dice", "lane": 0.0, "speed": 6.0, "t0": 0.0, "seed": 777}
	var ball: Dictionary = {"id": 3, "kind": "ball", "lane": 1.5, "speed": 9.0, "t0": 0.0, "seed": 5}
	var spread_c: float = 0.0
	var spread_d: float = 0.0
	for i: int in 30:
		var t: float = 0.5 + float(i) * 0.2
		spread_c = maxf(spread_c, absf(DodgeTheDiceLogic.path_at(coin, t).x - o.x))
		spread_d = maxf(spread_d, absf(DodgeTheDiceLogic.path_at(dice, t).x - o.x))
		assert_almost_eq(DodgeTheDiceLogic.path_at(ball, minf(t, 3.0)).x - o.x, 1.5, 0.001)
	assert_gt(spread_c, 0.5, "the coin wobbles")
	assert_gt(spread_d, 0.3, "the die changes lanes")


func test_hit_knocks_down_and_slides_back() -> void:
	var g: DodgeTheDiceLogic = _game([1, 2])
	_run(g, 1.0)
	var at: Vector3 = _on_row(5, 1.0)
	g.world.set_transform(1, at, 0.0)
	g.hazards.append(_hazard_at(&"ball", at, g.clock + STEP))
	var evs: Array[Dictionary] = _run(g, STEP)
	var hit: Array[Dictionary] = _of(evs, &"dodge_the_dice_hit")
	assert_eq(hit.size(), 1, "the ball hits")
	assert_eq(int(hit[0]["player"]), 1)
	assert_eq(StringName(hit[0]["kind"]), &"ball")
	assert_true(g.is_down(1))
	assert_eq(g.pending_knockdowns.size(), 1)
	assert_eq(StringName(g.pending_knockdowns[0]["cause"]), &"ball")
	assert_almost_eq(float(g.pending_knockdowns[0]["seconds"]), 1.5, 0.001)
	assert_true(g.pending_moves.has(1), "slid back")
	var to: Vector3 = g.pending_moves[1]
	assert_between(to.z - at.z, DodgeTheDiceLogic.SLIDE_MIN - 0.01, DodgeTheDiceLogic.SLIDE_MAX + 0.01, "3-5 m downhill")
	assert_almost_eq(to.y, ClimbRoom.surface_y(to.z) + 0.05, 0.01, "on the board")
	assert_lt(ClimbRoom.progress(to), ClimbRoom.progress(at), "lower than before")
	assert_eq(g.hits[1], 1)
	# Down: the next ball rolls through.
	g.hazards.append(_hazard_at(&"coin", at, g.clock + STEP, 901))
	assert_true(_of(_run(g, STEP), &"dodge_the_dice_hit").is_empty(), "no hit while down")


func test_immunity_after_getting_up() -> void:
	var g: DodgeTheDiceLogic = _game([1, 2])
	_run(g, 1.0)
	var at: Vector3 = _on_row(4, -2.0)
	g.world.set_transform(1, at, 0.0)
	g.hazards.append(_hazard_at(&"ball", at, g.clock + STEP))
	_run(g, STEP)
	assert_true(g.is_down(1))
	_run(g, 1.6)
	var up_at: Vector3 = g.pending_moves[1]
	g.world.set_transform(1, up_at + Vector3(0, 0, -1.0), 0.0)  # got up a bit above the slide's end
	g.on_player_got_up(1)
	assert_false(g.is_down(1))
	assert_true(g.pending_moves.has(1), "still moved to the slide's end")
	g.world.set_transform(1, up_at, 0.0)
	g.pending_moves.clear()
	g.hazards.clear()
	g.hazards.append(_hazard_at(&"ball", up_at, g.clock + STEP, 902))
	assert_true(_of(_run(g, STEP), &"dodge_the_dice_hit").is_empty(), "immune right after getting up")
	_run(g, DodgeTheDiceLogic.IMMUNE_SECONDS)
	g.hazards.clear()
	g.hazards.append(_hazard_at(&"ball", up_at, g.clock + STEP, 903))
	assert_eq(_of(_run(g, STEP), &"dodge_the_dice_hit").size(), 1, "hit again once immunity ends")
	# A tumble that carried the bean further down keeps it there.
	_run(g, 1.6)
	var deeper: Vector3 = g.planned_slide[1] + Vector3(0, 0, 1.0)
	g.world.set_transform(1, deeper, 0.0)
	g.on_player_got_up(1)
	assert_false(g.pending_moves.has(1), "no move back up the board")


func test_no_hits_in_the_top_safe_zone_and_over_a_jump() -> void:
	var g: DodgeTheDiceLogic = _game([1, 2])
	_run(g, 1.0)
	var top: Vector3 = Vector3(WalkableLogicBase.ROOM_ORIGIN.x, ClimbRoom.top_y(), ClimbRoom.top_z() - 0.2)
	g.world.set_transform(1, top, 0.0)
	_run(g, STEP)
	assert_true(g.is_up(1))
	var h: Dictionary = {"id": 5, "kind": "coin", "lane": 0.0, "speed": 5.0, "t0": g.clock, "seed": 3}
	g.hazards.append(h)
	assert_true(_of(_run(g, 0.6), &"dodge_the_dice_hit").is_empty(), "the landing is safe")
	# A bean in the air over a ball isn't hit.
	var at: Vector3 = _on_row(3, 2.0)
	g.world.set_transform(2, at + Vector3(0, 1.0, 0), 0.0, true)
	g.hazards.append(_hazard_at(&"ball", at, g.clock + STEP, 6))
	assert_true(_of(_run(g, STEP), &"dodge_the_dice_hit").is_empty(), "jumped the ball")


func test_time_cap_ranks_by_height_with_ties() -> void:
	var g: DodgeTheDiceLogic = _game([1, 2, 3, 4])
	_run(g, STEP)
	g.world.set_transform(1, _on_row(8), 0.0)
	g.world.set_transform(2, _on_row(4, -3.0), 0.0)
	g.world.set_transform(3, _on_row(4, 3.0), 0.0)
	var evs: Array[Dictionary] = _run(g, DodgeTheDiceLogic.GAME_SECONDS + 0.2)
	var over: Array[Dictionary] = _of(evs, &"dodge_the_dice_over")
	assert_eq(over.size(), 1)
	assert_eq(StringName(over[0]["reason"]), &"time")
	assert_eq(int(over[0]["winner"]), 1, "highest wins")
	var rank: Dictionary = {}
	var pts: Dictionary = {}
	for r: Dictionary in g.ranking():
		rank[int(r["player"])] = int(r["rank"])
		pts[int(r["player"])] = int(r["points"])
	assert_eq(rank, {1: 1, 2: 2, 3: 2, 4: 4})
	assert_eq(pts, {1: 3, 2: 1, 3: 1, 4: 0})
	# The ranking is frozen at the buzzer: a slide afterwards changes nothing.
	g.world.set_transform(1, g.spawn_for(1), 0.0)
	assert_eq(int(g.ranking()[0]["player"]), 1)
	_run(g, DodgeTheDiceLogic.END_HOLD + 0.2)
	assert_true(g.finished)


func test_last_call_after_all_but_one() -> void:
	var g: DodgeTheDiceLogic = _game([1, 2, 3])
	_run(g, STEP)
	g.world.set_transform(1, _landing(-2.0), 0.0)
	_run(g, 1.0)
	g.world.set_transform(3, _landing(2.0), 0.0)
	g.world.set_transform(2, _on_row(11), 0.0)
	var evs: Array[Dictionary] = _run(g, 0.2)
	assert_eq(_of(evs, &"dodge_the_dice_last_call").size(), 1)
	evs = _run(g, DodgeTheDiceLogic.LAST_CALL - 0.5)
	assert_true(_of(evs, &"dodge_the_dice_over").is_empty(), "still climbing")
	evs = _run(g, 0.6)
	var over: Array[Dictionary] = _of(evs, &"dodge_the_dice_over")
	assert_eq(over.size(), 1)
	assert_eq(StringName(over[0]["reason"]), &"last_call")
	var order: Array[int] = []
	for r: Dictionary in over[0]["ranking"]:
		order.append(int(r["player"]))
	assert_eq(order, [1, 3, 2])


func test_everyone_up_ends_it() -> void:
	var g: DodgeTheDiceLogic = _game([1, 2])
	_run(g, STEP)
	g.world.set_transform(1, _landing(-1.0), 0.0)
	g.world.set_transform(2, _landing(1.0), 0.0)
	var evs: Array[Dictionary] = _run(g, 0.2)
	var over: Array[Dictionary] = _of(evs, &"dodge_the_dice_over")
	assert_eq(over.size(), 1)
	assert_eq(StringName(over[0]["reason"]), &"all_up")
	assert_eq(int(over[0]["winner"]), -1, "finished on the same tick: shared first")
	for r: Dictionary in g.ranking():
		assert_eq(int(r["rank"]), 1)


func test_dropout() -> void:
	var g: DodgeTheDiceLogic = _game([1, 2, 3])
	_run(g, STEP)
	g.world.set_transform(1, _landing(), 0.0)
	_run(g, 0.2)
	g.world.set_transform(2, _landing(1.5), 0.0)
	_run(g, 0.2)
	g.remove_player(3)
	var evs: Array[Dictionary] = _run(g, 0.1)
	assert_eq(g.state, DodgeTheDiceLogic.State.DONE, "the last climber left: over")
	var ids: Array[int] = []
	for r: Dictionary in g.ranking():
		ids.append(int(r["player"]))
	assert_eq(ids, [1, 2], "the dropout leaves the ranking")
	assert_eq(_of(evs, &"dodge_the_dice_over").size(), 1)


func test_two_players() -> void:
	var g: DodgeTheDiceLogic = _game([1, 2])
	g.next_spawn = DodgeTheDiceLogic.FIRST_SPAWN
	_run(g, 5.0)
	g.world.set_transform(2, _landing(), 0.0)
	var evs: Array[Dictionary] = _run(g, 0.2)
	assert_eq(_of(evs, &"dodge_the_dice_last_call").size(), 1, "one up, one to go: last call")
	evs = _run(g, DodgeTheDiceLogic.LAST_CALL + 0.3)
	var over: Array[Dictionary] = _of(evs, &"dodge_the_dice_over")
	assert_eq(over.size(), 1)
	assert_eq(int(over[0]["winner"]), 2)
	var rows: Array[Dictionary] = g.ranking()
	assert_eq(int(rows[0]["player"]), 2)
	assert_eq(int(rows[1]["player"]), 1)
	assert_eq(int(rows[1]["rank"]), 2)


func test_shove_allowed_grab_blocked() -> void:
	var g: DodgeTheDiceLogic = _game([1, 2])
	assert_true(g.blocks_intent(&"grab"))
	assert_false(g.blocks_intent(&"shove"), "shoving is part of the fun")
	assert_true(g.blocks_intent(&"use_item"))
	var st: Dictionary = g.get_public_state()
	for k: String in ["clock", "hazards", "finish", "heights", "room", "down", "last_call"]:
		assert_true(st.has(k), "state has %s" % k)
