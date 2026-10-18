extends GutTest
## Jackpot Climb (MINIGAME_IDEAS #11): the chip cake is a run (0.9.11, Patrick: "its a run not a
## jump and run"): every lane is a walkway that winds up its ring from one flag to the next, the
## steady lanes without a single step, the bold ones shorter with a few hops onto chip tops; the
## rings are filled (nothing to fall into, nothing to crawl under, headroom under every slab), three
## checkpoint flags and two separate ways up, a fall after a flag puts you back on that flag (never
## the floor), height is progress up the jackpot stack from the server's positions, standing on the
## pad finishes in order (shared places on one tick), a bat swing knocks a climber in reach down
## with a cooldown, finishers and the just-got-up grace are safe, the time cap ranks by height with
## ties, dropouts, two players, grab blocked and shove allowed. (The real bean on the real
## collision: `tests/physics/test_jackpot_climb_course.gd`.)

const STEP: float = 0.05

var cfg: BalanceConfig = BalanceConfig.new()


func _game(players: Array[int], seed_value: int = 7) -> JackpotClimbLogic:
	var g := JackpotClimbLogic.new()
	g.setup(players, SeededRng.new(seed_value), cfg, {}, {})
	g.world = WorldQuery.new()
	for p: int in players:
		g.world.set_transform(p, g.spawn_for(p), g.spawn_yaw_for(p))
	return g


func _run(g: JackpotClimbLogic, seconds: float) -> Array[Dictionary]:
	var seen: Array[Dictionary] = []
	var t: float = 0.0
	while t < seconds - 0.0001:
		g.tick(STEP, 0.0)
		t += STEP
		seen.append_array(g.drain_events())
	return seen


func _of(evs: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	return evs.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## World position on segment `seg`'s `kind` lane, `f` of the way along it (offset `off`).
func _on_lane(seg: int, kind: StringName, f: float, off: Vector3 = Vector3.ZERO) -> Vector3:
	var l: Dictionary = ChipTowers.lane(seg, kind)
	return WalkableLogicBase.ROOM_ORIGIN + ChipTowers.point(l, f * float(l["theta"]), float(l["rc"])) + off


func _on_pad(x: float = 0.0) -> Vector3:
	return WalkableLogicBase.ROOM_ORIGIN + ChipTowers.pad_center() + Vector3(x, 0.0, 0.0)


## World position on the floor in the aisle round the first ring (the net).
func _on_net(a: float = 0.0) -> Vector3:
	var d: Vector3 = ChipTowers.dir(a) * (ChipTowers.ring_outer(0) + 0.7)
	return WalkableLogicBase.ROOM_ORIGIN + Vector3(d.x, 0.0, ChipTowers.CENTER_Z + d.z)


## Puts `a` `dist` metres from `b` at `at` (default: halfway up the steady lane round tier 2),
## facing them (yaw 0 faces -z).
func _face(g: JackpotClimbLogic, a: int, b: int, dist: float, at: Vector3 = Vector3.INF) -> void:
	if at == Vector3.INF:
		at = _on_lane(1, &"steady", 0.5)
	g.world.set_transform(b, at, 0.0)
	g.world.set_transform(a, at + Vector3(0, 0, dist), 0.0)


func _swing(g: JackpotClimbLogic, p: int, hint: int = -1) -> Dictionary:
	var intent: Dictionary = {"type": &"minigame_action", "kind": "swing"}
	if hint >= 0:
		intent["target"] = hint
	return g.submit(p, intent, 0.0)


## Flat distance of local `p` from the tower's axis.
func _flat(p: Vector3) -> float:
	return Vector2(p.x, p.z - ChipTowers.CENTER_Z).length()


## World position on checkpoint `k`'s flag spot `i`.
func _on_checkpoint(k: int, i: int = 0) -> Vector3:
	return WalkableLogicBase.ROOM_ORIGIN + ((ChipTowers.checkpoints()[k - 1]["spots"] as Array)[i] as Vector3)


func test_every_lane_is_a_run_up_its_ring() -> void:
	var hops: int = 0
	for seg: int in ChipTowers.SEGMENTS:
		var y0: float = ChipTowers.level_y(seg)
		var y1: float = ChipTowers.level_y(seg + 1)
		var steady: Dictionary = ChipTowers.lane(seg, &"steady")
		var bold: Dictionary = ChipTowers.lane(seg, &"bold")
		assert_false(steady.is_empty() or bold.is_empty(), "segment %d has both lanes" % seg)
		for l: Dictionary in [steady, bold]:
			var tag: String = "seg %d %s" % [seg, l["kind"]]
			assert_almost_eq(ChipTowers.height(l, 0.0), y0, 0.001, "%s starts on its tier" % tag)
			assert_almost_eq(ChipTowers.height(l, float(l["theta"])), y1, 0.001, "%s ends on the next level" % tag)
			assert_almost_eq(float(l["a0"]), ChipTowers.flag_angle(seg), 0.001, "%s starts at its flag" % tag)
			var end_a: float = float(l["a0"]) + float(l["dir"]) * float(l["theta"])
			assert_almost_eq(absf(wrapf(end_a - ChipTowers.flag_angle(seg + 1), -PI, PI)), 0.0, 0.001, "%s ends where the next segment starts" % tag)
			var kn: Array = l["knots"]
			for j: int in range(1, kn.size()):
				var a: Vector2 = kn[j - 1]
				var b: Vector2 = kn[j]
				assert_gte(b.x, a.x - 1e-6, "%s runs one way" % tag)
				assert_gte(b.y, a.y - 1e-6, "%s only ever climbs" % tag)
				if b.x - a.x > 1e-5:
					# The steepest line is the inner edge.
					var deg: float = rad_to_deg(atan2(b.y - a.y, (b.x - a.x) * float(l["r0"])))
					assert_lte(deg, ChipTowers.MAX_SLOPE_DEG, "%s: a ramp you run up (%.1f deg)" % [tag, deg])
			assert_lte(float(l["r1"]), ChipTowers.ring_outer(seg) + 0.001)
			assert_gte(float(l["r0"]), ChipTowers.ring_inner(seg) - 0.001)
			assert_gte(float(l["r1"]) - float(l["r0"]), 1.7, "%s is a walkway, not a ledge" % tag)
		assert_eq(ChipTowers.risers(steady).size(), 0, "seg %d: the steady lane never needs a jump" % seg)
		var rs: Array[float] = ChipTowers.risers(bold)
		assert_between(rs.size(), 1, 2, "seg %d: the bold lane has a hop or two" % seg)
		hops += rs.size()
		for rt: float in rs:
			var kn: Array = bold["knots"]
			var up: float = 0.0
			for j: int in range(1, kn.size()):
				if absf((kn[j] as Vector2).x - rt) < 1e-6 and absf((kn[j - 1] as Vector2).x - rt) < 1e-6:
					up = (kn[j] as Vector2).y - (kn[j - 1] as Vector2).y
			assert_between(up, 0.4, cfg.jump_height - 0.3, "seg %d: a short hop (%.2f m) onto a chip top" % [seg, up])
		assert_lt(ChipTowers.lane_length(bold), ChipTowers.lane_length(steady), "seg %d: the bold lane is the shorter way" % seg)
	assert_between(hops, 5, 8, "only a few hops in all (%d)" % hops)
	assert_almost_eq(ChipTowers.level_y(ChipTowers.SEGMENTS), ClimbRoom.TOWER_TOP_Y, 0.001, "the last level is the pad")
	assert_lt(ChipTowers.ring_outer(0) + 1.4, ChipTowers.HALL_HALF_X, "an aisle between the first ring and the side walls")
	assert_lt(ChipTowers.ring_outer(0) + 1.4, ChipTowers.CENTER_Z - ChipTowers.FAR_Z, "and the far wall")
	assert_lt(ChipTowers.CENTER_Z + ChipTowers.ring_outer(0), -0.5, "the cake stays off the apron")
	var layout: Dictionary = ClimbRoom.layout("towers")
	assert_true((layout["arena"] as AABB).has_point(_on_pad() + Vector3(0, 1, 0)), "the pad is in the arena")
	assert_true(ClimbRoom.on_top(_on_pad(), "towers"))
	assert_false(ClimbRoom.on_top(_on_lane(3, &"steady", 0.97), "towers"), "the end of the last lane is not the top")
	# The entry onto the pad faces the apron, both last lanes arrive inside the rail's opening.
	assert_almost_eq(ChipTowers.entry_dir().z, 1.0, 0.001)


func test_rings_are_filled_with_headroom_under_every_slab() -> void:
	var points: int = 0
	for seg: int in ChipTowers.SEGMENTS:
		var r0: float = ChipTowers.ring_inner(seg)
		var r1: float = ChipTowers.ring_outer(seg)
		var r: float = r0 + 0.1
		while r < r1 - 0.05:
			var a: float = -PI
			while a < PI:
				var d: Vector3 = ChipTowers.dir(a) * r
				var p := Vector3(d.x, 50.0, ChipTowers.CENTER_Z + d.z)
				var ys: Array[float] = []
				for s: Dictionary in ChipTowers.surfaces_at(p):
					ys.append(float(s["y"]))
				ys.sort()
				points += 1
				var tag: String = "ring %d at r %.1f, angle %.2f" % [seg, r, a]
				assert_gt(ys.size(), 0, "%s: a walkway (nothing to fall into)" % tag)
				if ys.is_empty():
					a += 0.05
					continue
				assert_gte(ys[0], ChipTowers.level_y(seg) - 0.001, "%s: on its tier" % tag)
				assert_lte(ys[ys.size() - 1], ChipTowers.level_y(seg + 1) + 0.001, "%s: no higher than the next" % tag)
				for i: int in range(1, ys.size()):
					if ys[i] - ys[i - 1] > 0.01:
						assert_gte(ys[i] - ChipTowers.SLAB_T - ys[i - 1], ChipTowers.MIN_HEADROOM, "%s: headroom under the slab" % tag)
				a += 0.05
			r += 0.4
	gut.p("%d points over the rings" % points)
	# The pieces: slabs only where a walkway runs underneath (so nothing to crawl under elsewhere).
	for pc: Dictionary in ChipTowers.pieces():
		if not bool(pc["slab"]):
			continue
		var l: Dictionary = ChipTowers.lanes()[int(pc["lane"])]
		var mid: float = (float(pc["t0"]) + float(pc["t1"])) * 0.5
		var p: Vector3 = ChipTowers.point(l, mid, float(l["rc"]))
		var below: float = -INF
		for s: Dictionary in ChipTowers.surfaces_at(p):
			if float(s["y"]) < p.y - 0.01:
				below = maxf(below, float(s["y"]))
		assert_gt(below, -INF, "a slab of seg %d %s has a walkway under it" % [int(l["seg"]), l["kind"]])
		assert_gte(p.y - ChipTowers.SLAB_T - below, ChipTowers.MIN_HEADROOM, "headroom under seg %d %s" % [int(l["seg"]), l["kind"]])


func test_taller_with_checkpoint_flags() -> void:
	assert_gte(ClimbRoom.TOWER_TOP_Y, 16.0 * 1.5, "at least half again the old 16 m tower")
	assert_lte(ClimbRoom.TOWER_TOP_Y, 16.0 * 2.0)
	var cps: Array[Dictionary] = ChipTowers.checkpoints()
	assert_eq(cps.size(), 3, "a flag on every tier")
	var prev: float = 0.0
	for cp: Dictionary in cps:
		var k: int = int(cp["index"])
		var y: float = float(cp["y"])
		assert_gt(y, prev, "flags climb")
		assert_between(y / ClimbRoom.TOWER_TOP_Y, 0.2 * float(k), 0.2 * float(k) + 0.3, "flag %d at %.0f%% of the height" % [k, 100.0 * y / ClimbRoom.TOWER_TOP_Y])
		prev = y
		assert_eq(ChipTowers.checkpoint_at(cp["flag"]), k, "flag %d stands on its tier" % k)
		for spot: Vector3 in cp["spots"]:
			assert_eq(ChipTowers.checkpoint_at(spot), k, "respawn spot on tier %d" % k)
			assert_lt(_flat(spot) + 0.45, ChipTowers.level_r(k), "the bean fits on the tier")
			# Level walkway all round the bean: no wall, no step, no edge within its reach.
			for off: Vector3 in [Vector3.ZERO, Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0), Vector3(0, 0, 0.5), Vector3(0, 0, -0.5)]:
				var under: Dictionary = ChipTowers.lane_under(spot + off + Vector3(0, 0.05, 0))
				assert_false(under.is_empty(), "flag %d: walkway round the spot" % k)
				if not under.is_empty():
					assert_almost_eq(float(under["y"]), y, 0.001, "flag %d: level round the spot" % k)
				for s: Dictionary in ChipTowers.surfaces_at(spot + off):
					var sy: float = float(s["y"])
					assert_true(sy <= y + 0.001 or sy - ChipTowers.SLAB_T > y + ChipTowers.MIN_HEADROOM, "flag %d: nothing at head height over the spot" % k)
	assert_eq(ChipTowers.checkpoint_at(Vector3(0, 0, ChipTowers.CENTER_Z + 14.0)), 0, "the floor is no checkpoint")
	var flags: Array[int] = []
	for cp: Dictionary in cps:
		flags.append(ChipTowers.checkpoint_at(Vector3(0, float(cp["y"]) + 0.6, ChipTowers.CENTER_Z) + ChipTowers.dir(float(cp["angle"])) * (ChipTowers.level_r(int(cp["index"])) - 0.3)))
	assert_eq(flags, [1, 2, 3], "anywhere on a tier's top counts, rim included")


func test_two_separate_ways_up() -> void:
	for seg: int in ChipTowers.SEGMENTS:
		var s: Dictionary = ChipTowers.lane(seg, &"steady")
		var b: Dictionary = ChipTowers.lane(seg, &"bold")
		# The fork: from the flag the two lanes wind round opposite ways...
		assert_eq(int(s["dir"]), -int(b["dir"]), "segment %d forks at its flag" % seg)
		var ps: Vector3 = ChipTowers.point(s, 3.0 / float(s["rc"]), float(s["rc"]))
		var pb: Vector3 = ChipTowers.point(b, 3.0 / float(b["rc"]), float(b["rc"]))
		assert_gt(Vector2(ps.x - pb.x, ps.z - pb.z).length(), 4.0, "segment %d: two ways from the flag" % seg)
		# ...and rejoin where they reach the next tier (the next flag, or the pad).
		var es: Vector3 = ChipTowers.point(s, float(s["theta"]), float(s["r0"]))
		var eb: Vector3 = ChipTowers.point(b, float(b["theta"]), float(b["r0"]))
		assert_almost_eq(es.y, eb.y, 0.001)
		assert_lt(Vector2(es.x - eb.x, es.z - eb.z).length(), 2.5, "segment %d: the lanes meet at the top" % seg)
	# The guide takes a bean from the apron to the pad on either way, lane by lane (pure data).
	for bold: bool in [false, true]:
		var p: Vector3 = (ClimbRoom.layout("towers")["spawns"] as Array)[0] - WalkableLogicBase.ROOM_ORIGIN
		var used: Dictionary = {}
		var steps: int = 0
		while not (_flat(p) < ChipTowers.PAD_R and p.y > ChipTowers.TOP_Y - 0.5) and steps < 4000:
			var g: Dictionary = ChipTowers.guide(p, bold)
			if int(g["lane"]) >= 0:
				used[ChipTowers.lanes()[int(g["lane"])]["kind"]] = true
			var to: Vector3 = g["to"]
			var flat := Vector3(to.x - p.x, 0.0, to.z - p.z)
			p += flat.limit_length(0.1)
			var on: Dictionary = ChipTowers.lane_under(p + Vector3(0, 1.0, 0))
			if _flat(p) < ChipTowers.PAD_R:
				p.y = ChipTowers.TOP_Y
			elif not on.is_empty():
				p.y = float(on["y"])
			steps += 1
		assert_lt(steps, 4000, "%s: the guide leads to the pad" % ("bold" if bold else "steady"))
		assert_true(used.has(&"bold") == bold, "%s way: %s" % ["bold" if bold else "steady", used.keys()])


func test_a_fall_after_a_flag_respawns_at_that_flag() -> void:
	var g: JackpotClimbLogic = _game([1, 2, 3])
	_run(g, STEP)
	# 1 climbs onto tier 1, then tier 2: two flags.
	g.world.set_transform(1, _on_checkpoint(1), 0.0)
	var evs: Array[Dictionary] = _run(g, 0.2)
	assert_eq(g.checkpoint.get(1, 0), 1)
	g.world.set_transform(1, _on_checkpoint(2, 1), 0.0)
	evs.append_array(_run(g, 0.2))
	assert_eq(g.checkpoint.get(1, 0), 2)
	var cps: Array[Dictionary] = _of(evs, &"jackpot_climb_checkpoint")
	assert_eq(cps.size(), 2)
	assert_eq(int(cps[1]["index"]), 2)
	assert_eq(int(g.get_public_state()["checkpoints"][1]), 2, "in the state for the HUD")
	# Knocked off from a stack over tier 2: they fall past tier 1 to the floor.
	g.world.set_transform(1, _on_lane(2, &"bold", 0.3), 0.0)
	_run(g, 0.2)
	assert_true(g.pending_moves.is_empty(), "up on the next ring: nothing to do")
	g.world.set_transform(1, _on_net(), 0.0)
	evs = _run(g, STEP)
	var res: Array[Dictionary] = _of(evs, &"jackpot_climb_respawn")
	assert_eq(res.size(), 1, "one respawn")
	assert_eq(int(res[0]["index"]), 2, "back to flag 2")
	assert_true(g.pending_moves.has(1), "the server moves the body")
	var to: Vector3 = g.pending_moves[1]
	assert_eq(ChipTowers.checkpoint_at(to - WalkableLogicBase.ROOM_ORIGIN), 2, "onto tier 2, not the floor: %s" % to)
	assert_almost_eq(to.y, WalkableLogicBase.ROOM_ORIGIN.y + ChipTowers.level_y(2), 0.001)
	assert_eq(to, g.respawn_spot(1, 2))
	assert_gte(g.height_of(1), ChipTowers.level_y(2) / ClimbRoom.TOWER_TOP_Y - 0.001, "a fall doesn't cost the height of the flag")
	# The move is in flight: no second respawn while the body still reads low.
	g.pending_moves.clear()
	evs = _run(g, JackpotClimbLogic.RESPAWN_GRACE - 0.2)
	assert_true(_of(evs, &"jackpot_climb_respawn").is_empty(), "one move at a time")
	# The flag only ever goes up: standing on tier 1 now is a fall below flag 2.
	g.world.set_transform(1, _on_checkpoint(1), 0.0)
	evs = _run(g, 0.4)
	assert_eq(g.checkpoint[1], 2)
	assert_eq(_of(evs, &"jackpot_climb_respawn").size(), 1, "tier 1 is below flag 2")
	# The server puts the body on the flag. A short drop onto the top of a lane below it is fine.
	g.world.set_transform(1, g.pending_moves[1], 0.0)
	g.pending_moves.clear()
	_run(g, JackpotClimbLogic.RESPAWN_GRACE)
	g.world.set_transform(1, _on_lane(1, &"steady", 0.92), 0.0)
	evs = _run(g, 0.2)
	assert_true(_of(evs, &"jackpot_climb_respawn").is_empty(), "near the top of the lane below is still climbing")
	assert_eq(g.private_state(1)["checkpoint"], 2)
	assert_eq(g.private_state(1)["respawns"], 2)


func test_before_the_first_flag_a_fall_is_just_physics() -> void:
	var g: JackpotClimbLogic = _game([1, 2])
	_run(g, STEP)
	g.world.set_transform(2, _on_lane(0, &"bold", 0.5), 0.0)
	_run(g, 0.2)
	g.world.set_transform(2, _on_net(0.3), 0.0)
	var evs: Array[Dictionary] = _run(g, 0.5)
	assert_true(_of(evs, &"jackpot_climb_respawn").is_empty(), "no flag yet: climb again from the net")
	assert_false(g.pending_moves.has(2))
	assert_false(g.checkpoint.has(2))
	assert_eq(g.private_state(2)["checkpoint"], 0)


func test_no_respawn_while_down() -> void:
	var g: JackpotClimbLogic = _game([1, 2])
	_run(g, STEP)
	g.world.set_transform(2, _on_checkpoint(1), 0.0)
	_run(g, 0.2)
	var at: Vector3 = _on_lane(1, &"bold", 0.2)
	g.world.set_transform(2, at, 0.0)
	g.world.set_transform(1, at + Vector3(0, 0, 1.0), 0.0)
	_run(g, JackpotClimbLogic.SWING_COOLDOWN)
	g.world.set_transform(1, g.world.get_position(2) + Vector3(0, 0, 1.0), 0.0)
	assert_eq(_swing(g, 1)["result"], &"hit")
	g.world.set_transform(2, _on_net(), 0.0)  # the ragdoll on the floor
	var evs: Array[Dictionary] = _run(g, 0.5)
	assert_true(_of(evs, &"jackpot_climb_respawn").is_empty(), "a ragdoll in flight is left alone")
	g.on_player_got_up(2)
	evs = _run(g, 0.1)
	assert_eq(_of(evs, &"jackpot_climb_respawn").size(), 1, "once up: back to flag 1")
	assert_eq(g.pending_moves[2], g.respawn_spot(2, 1))


func test_progress_from_positions() -> void:
	var g: JackpotClimbLogic = _game([1, 2, 3])
	for p: int in [1, 2, 3]:
		assert_true(g.arena.has_point(g.spawn_for(p)), "spawn %d in the arena" % p)
		assert_almost_eq(ClimbRoom.progress(g.spawn_for(p), "towers"), 0.0, 0.001, "spawns at the bottom")
	g.world.set_transform(1, _on_lane(1, &"steady", 0.5), 0.0)
	g.world.set_transform(2, _on_lane(0, &"steady", 0.5), 0.0)
	assert_almost_eq(g.height_of(1), (_on_lane(1, &"steady", 0.5) - WalkableLogicBase.ROOM_ORIGIN).y / ClimbRoom.TOWER_TOP_Y, 0.001)
	assert_gt(g.height_of(1), g.height_of(2), "higher up, more progress")
	assert_almost_eq(ClimbRoom.progress(_on_pad(), "towers"), 1.0, 0.001)
	var st: Dictionary = g.get_public_state()
	assert_almost_eq(float(st["heights"][1]), g.height_of(1), 0.002)


func test_finish_order_and_shared_places() -> void:
	var g: JackpotClimbLogic = _game([1, 2, 3, 4])
	var evs: Array[Dictionary] = _run(g, STEP)
	assert_eq(_of(evs, &"jackpot_climb_begin").size(), 1, "announced on the first tick")
	g.world.set_transform(2, _on_pad(), 0.0)
	evs = _run(g, 0.2)
	var tops: Array[Dictionary] = _of(evs, &"jackpot_climb_top")
	assert_eq(tops.size(), 1)
	assert_eq(tops[0]["players"], [2])
	assert_eq(int(tops[0]["place"]), 1)
	g.world.set_transform(3, _on_pad(0.8), 0.0)
	g.world.set_transform(4, _on_pad(-0.8), 0.0)
	evs = _run(g, 0.2)
	tops = _of(evs, &"jackpot_climb_top")
	assert_eq(tops[0]["players"], [3, 4], "same tick: one group")
	assert_eq(int(tops[0]["place"]), 2)
	var rank: Dictionary = {}
	for r: Dictionary in g.ranking():
		rank[int(r["player"])] = int(r["rank"])
	assert_eq(rank, {2: 1, 3: 2, 4: 2, 1: 4})
	assert_true(g.is_untouchable(2), "finishers can't be shoved")
	var held: Vector3 = g.clamp_position(2, _on_lane(0, &"steady", 0.2))
	assert_true(ClimbRoom.on_top(held, "towers"), "a finisher is held on the pad: %s" % held)


func test_a_swing_in_reach_knocks_the_climber_off() -> void:
	var g: JackpotClimbLogic = _game([1, 2, 3])
	_run(g, STEP)
	_face(g, 1, 2, 1.0)
	var res: Dictionary = _swing(g, 1)
	assert_true(res["ok"], "swing: %s" % res)
	assert_eq(res["result"], &"hit")
	assert_eq(int(res["target"]), 2)
	assert_true(g.is_down(2))
	assert_eq(g.pending_knockdowns.size(), 1)
	var kd: Dictionary = g.pending_knockdowns[0]
	assert_eq(int(kd["player"]), 2)
	assert_eq(int(kd["attacker"]), 1, "the ragdoll flies away from the attacker")
	assert_eq(kd["cause"], &"bat")
	assert_almost_eq(float(kd["seconds"]), JackpotClimbLogic.KNOCK_SECONDS, 0.001)
	var evs: Array[Dictionary] = g.drain_events()
	assert_eq(_of(evs, &"jackpot_climb_hit").size(), 1)
	# A downed bean can't swing, and the down ends on the server's clock.
	assert_eq(_swing(g, 2)["error"], &"down")
	evs = _run(g, JackpotClimbLogic.KNOCK_SECONDS + 0.1)
	assert_false(g.is_down(2))
	assert_eq(_of(evs, &"jackpot_climb_up").size(), 1)


func test_out_of_reach_and_behind_are_misses() -> void:
	var g: JackpotClimbLogic = _game([1, 2])
	_run(g, STEP)
	_face(g, 1, 2, JackpotClimbLogic.BAT_REACH + InteractionRules.LAG_SLACK + 0.2)
	var res: Dictionary = _swing(g, 1, 2)
	assert_eq(res["result"], &"miss", "the client's target is only a hint")
	assert_false(g.is_down(2))
	_run(g, JackpotClimbLogic.SWING_COOLDOWN + 0.05)
	g.world.set_transform(1, g.world.get_position(2) + Vector3(0, 0, 1.5), PI)  # facing away
	assert_eq(_swing(g, 1)["result"], &"miss")


func test_cooldown() -> void:
	var g: JackpotClimbLogic = _game([1, 2, 3])
	_run(g, STEP)
	_face(g, 1, 2, 3.5)
	assert_eq(_swing(g, 1)["result"], &"miss", "a miss is fine")
	_face(g, 1, 3, 1.0, _on_lane(2, &"steady", 0.4))
	assert_eq(_swing(g, 1)["error"], &"cooldown", "a miss costs the cooldown")
	_run(g, JackpotClimbLogic.SWING_COOLDOWN - 0.2)
	assert_eq(_swing(g, 1)["error"], &"cooldown")
	_run(g, 0.3)
	assert_eq(_swing(g, 1)["result"], &"hit")
	assert_eq(g.private_state(1)["hits"], 1)


func test_no_hit_on_finishers_or_in_the_get_up_grace() -> void:
	var g: JackpotClimbLogic = _game([1, 2, 3])
	_run(g, STEP)
	# A finisher on the pad is safe even in reach.
	g.world.set_transform(2, _on_pad(), 0.0)
	_run(g, 0.1)
	assert_true(g.is_up(2))
	g.world.set_transform(1, _on_pad() + Vector3(0, 0, 1.6), 0.0)  # on the pad's rim, outside the finish box
	assert_eq(_swing(g, 1)["result"], &"miss", "finishers can't be hit")
	assert_eq(_swing(g, 2)["error"], &"finished", "and don't swing")
	# Knock 3 down; once the room reports them up they are safe for IMMUNE_SECONDS only.
	_run(g, JackpotClimbLogic.SWING_COOLDOWN + 0.05)
	_face(g, 1, 3, 1.0)
	assert_eq(_swing(g, 1)["result"], &"hit")
	_run(g, 0.5)
	g.on_player_got_up(3)
	assert_false(g.is_down(3))
	assert_true(g.is_immune(3))
	_run(g, JackpotClimbLogic.SWING_COOLDOWN - 0.45)
	_face(g, 1, 3, 1.0)
	var res: Dictionary = _swing(g, 1)
	assert_eq(res["result"], &"immune", "inside the grace: %s" % res)
	assert_false(g.is_down(3))
	_run(g, JackpotClimbLogic.SWING_COOLDOWN + 0.05)
	assert_false(g.is_immune(3), "the grace is short")
	assert_eq(_swing(g, 1)["result"], &"hit", "no immunity after the grace")


func test_time_cap_ranks_by_height_with_ties() -> void:
	var g: JackpotClimbLogic = _game([1, 2, 3, 4])
	_run(g, STEP)
	g.world.set_transform(1, _on_lane(1, &"steady", 0.5), 0.0)
	g.world.set_transform(2, _on_lane(0, &"steady", 0.5), 0.0)
	g.world.set_transform(3, _on_lane(0, &"steady", 0.5, Vector3(0.3, 0, 0)), 0.0)
	var evs: Array[Dictionary] = _run(g, JackpotClimbLogic.GAME_SECONDS + 0.2)
	var over: Array[Dictionary] = _of(evs, &"jackpot_climb_over")
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
	g.world.set_transform(1, g.spawn_for(1), 0.0)
	assert_eq(int(g.ranking()[0]["player"]), 1, "frozen at the buzzer")
	_run(g, JackpotClimbLogic.END_HOLD + 0.2)
	assert_true(g.finished)


func test_last_call_after_all_but_one() -> void:
	var g: JackpotClimbLogic = _game([1, 2, 3])
	_run(g, STEP)
	g.world.set_transform(1, _on_pad(-0.8), 0.0)
	_run(g, 1.0)
	g.world.set_transform(3, _on_pad(0.8), 0.0)
	g.world.set_transform(2, _on_lane(2, &"steady", 0.3), 0.0)
	var evs: Array[Dictionary] = _run(g, 0.2)
	assert_eq(_of(evs, &"jackpot_climb_last_call").size(), 1)
	evs = _run(g, JackpotClimbLogic.LAST_CALL - 0.5)
	assert_true(_of(evs, &"jackpot_climb_over").is_empty(), "still climbing")
	evs = _run(g, 0.6)
	var over: Array[Dictionary] = _of(evs, &"jackpot_climb_over")
	assert_eq(over.size(), 1)
	assert_eq(StringName(over[0]["reason"]), &"last_call")
	var order: Array[int] = []
	for r: Dictionary in over[0]["ranking"]:
		order.append(int(r["player"]))
	assert_eq(order, [1, 3, 2])


func test_dropout() -> void:
	var g: JackpotClimbLogic = _game([1, 2, 3])
	_run(g, STEP)
	g.world.set_transform(1, _on_pad(), 0.0)
	_run(g, 0.2)
	g.world.set_transform(2, _on_pad(0.9), 0.0)
	_run(g, 0.2)
	g.remove_player(3)
	var evs: Array[Dictionary] = _run(g, 0.1)
	assert_eq(g.state, JackpotClimbLogic.State.DONE, "the last climber left: over")
	var ids: Array[int] = []
	for r: Dictionary in g.ranking():
		ids.append(int(r["player"]))
	assert_eq(ids, [1, 2], "the dropout leaves the ranking")
	assert_eq(_of(evs, &"jackpot_climb_over").size(), 1)
	assert_eq(StationLogicBase.fail(&"x")["ok"], false)
	assert_false(_swing(g, 3)["ok"], "a dropout can't swing")


func test_two_players() -> void:
	var g: JackpotClimbLogic = _game([1, 2])
	_run(g, 2.0)
	g.world.set_transform(2, _on_pad(), 0.0)
	var evs: Array[Dictionary] = _run(g, 0.2)
	assert_eq(_of(evs, &"jackpot_climb_last_call").size(), 1, "one up, one to go: last call")
	evs = _run(g, JackpotClimbLogic.LAST_CALL + 0.3)
	var over: Array[Dictionary] = _of(evs, &"jackpot_climb_over")
	assert_eq(over.size(), 1)
	assert_eq(int(over[0]["winner"]), 2)
	var rows: Array[Dictionary] = g.ranking()
	assert_eq(int(rows[0]["player"]), 2)
	assert_eq(int(rows[1]["player"]), 1)
	assert_eq(int(rows[1]["rank"]), 2)


func test_shove_allowed_grab_blocked() -> void:
	var g: JackpotClimbLogic = _game([1, 2])
	assert_true(g.blocks_intent(&"grab"))
	assert_false(g.blocks_intent(&"shove"), "shoving is part of the brawl")
	assert_true(g.blocks_intent(&"use_item"))
	assert_eq(g.submit(1, {"type": &"minigame_action", "kind": "steal"}, 0.0)["error"], &"bad_value")
	var st: Dictionary = g.get_public_state()
	for k: String in ["clock", "finish", "heights", "room", "down", "immune", "last_call", "checkpoints"]:
		assert_true(st.has(k), "state has %s" % k)
