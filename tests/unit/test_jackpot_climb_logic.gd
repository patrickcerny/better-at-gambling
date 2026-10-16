extends GutTest
## Jackpot Climb (MINIGAME_IDEAS #11): the chip cake is a jump-and-run (every lane climbable
## within the jump envelope, mostly short hops and a few wide running jumps), taller than the old
## spiral with three checkpoint flags and two separate ways up, a fall after a flag puts you back on
## that flag (never the floor), height is progress up the jackpot stack from the server's
## positions, standing on the pad finishes in order (shared places on one tick), a bat swing knocks
## a climber in reach down with a cooldown, finishers and the just-got-up grace are safe, the time
## cap ranks by height with ties, dropouts, two players, grab blocked and shove allowed.

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


## World position standing on stack `i` (offset `off` from its centre).
func _on_stack(i: int, off: Vector3 = Vector3.ZERO) -> Vector3:
	return WalkableLogicBase.ROOM_ORIGIN + (ChipTowers.stacks()[i]["pos"] as Vector3) + off


func _on_pad(x: float = 0.0) -> Vector3:
	return WalkableLogicBase.ROOM_ORIGIN + ChipTowers.pad_center() + Vector3(x, 0.0, 0.0)


## Puts `a` `dist` metres from `b` on stack `i`, facing them (yaw 0 faces -z).
func _face(g: JackpotClimbLogic, a: int, b: int, dist: float, i: int = 5) -> void:
	var at: Vector3 = _on_stack(i)
	g.world.set_transform(b, at, 0.0)
	g.world.set_transform(a, at + Vector3(0, 0, dist), 0.0)


func _swing(g: JackpotClimbLogic, p: int, hint: int = -1) -> Dictionary:
	var intent: Dictionary = {"type": &"minigame_action", "kind": "swing"}
	if hint >= 0:
		intent["target"] = hint
	return g.submit(p, intent, 0.0)


## Air between the rims of stacks `a` and `b` (flat).
func _air(a: Dictionary, b: Dictionary) -> float:
	var p: Vector3 = a["pos"]
	var q: Vector3 = b["pos"]
	return Vector2(p.x - q.x, p.z - q.z).length() - float(a["r"]) - float(b["r"])


## Flat distance of local `p` from the tower's axis.
func _flat(p: Vector3) -> float:
	return Vector2(p.x, p.z - ChipTowers.CENTER_Z).length()


## World position on checkpoint `k`'s flag spot `i`.
func _on_checkpoint(k: int, i: int = 0) -> Vector3:
	return WalkableLogicBase.ROOM_ORIGIN + ((ChipTowers.checkpoints()[k - 1]["spots"] as Array)[i] as Vector3)


func test_every_lane_is_a_jump_and_run() -> void:
	var all: Array[Dictionary] = ChipTowers.stacks()
	assert_gt(all.size(), 50, "a real climb")
	for seg: int in ChipTowers.SEGMENTS:
		var y0: float = ChipTowers.level_y(seg)
		var y1: float = ChipTowers.level_y(seg + 1)
		var col_r: float = ChipTowers.level_r(seg + 1)
		for side: int in [-1, 1]:
			var ids: Array[int] = ChipTowers.lane(seg, side)
			assert_gte(ids.size(), 4, "lane %d/%d has stacks" % [seg, side])
			var prev_y: float = y0
			for j: int in ids.size():
				var s: Dictionary = all[ids[j]]
				var p: Vector3 = s["pos"]
				var tag: String = "seg %d side %d stack %d" % [seg, side, j]
				assert_between(p.y - prev_y, 0.25, ChipTowers.MAX_RISE, "%s rises %.2f m" % [tag, p.y - prev_y])
				if j > 0:
					var gap: float = _air(all[ids[j - 1]], s)
					assert_between(gap, 0.5, ChipTowers.MAX_GAP, "%s leaves %.2f m of air" % [tag, gap])
					assert_eq(gap > ChipTowers.NORMAL_JUMP, bool(s["wide"]), "%s: only the planned wide gaps are wide (%.2f m)" % [tag, gap])
					if j > 1:
						# Skipping a stack is out of the jump: too far or too high.
						var skip: float = _air(all[ids[j - 2]], s)
						var up: float = p.y - (all[ids[j - 2]]["pos"] as Vector3).y
						assert_true(skip > ChipTowers.MAX_GAP or up > 1.1, "%s: no skipping (%.2f m, %.2f up)" % [tag, skip, up])
				# It stands on its level, clear of the column it winds round.
				assert_almost_eq(float(s["base_y"]), y0, 0.001)
				assert_gt(_flat(p) - float(s["r"]), col_r + 0.3, "%s clear of the column" % tag)
				if seg > 0:
					assert_lt(_flat(p) + float(s["r"]), ChipTowers.level_r(seg) - 0.2, "%s stands on tier %d" % [tag, seg])
				assert_lt(absf(p.x) + float(s["r"]), ChipTowers.HALL_HALF_X - 0.5, "%s inside the hall" % tag)
				assert_gt(p.z - float(s["r"]), ChipTowers.FAR_Z + 0.5, "%s inside the hall" % tag)
				assert_lt(p.z + float(s["r"]), -1.0, "%s off the apron" % tag)
				prev_y = p.y
			var last: Dictionary = all[ids[ids.size() - 1]]
			var top_rise: float = y1 - (last["pos"] as Vector3).y
			assert_between(top_rise, 0.25, ChipTowers.MAX_RISE, "seg %d side %d: onto the next level (%.2f m)" % [seg, side, top_rise])
			assert_lt(_flat(last["pos"]) - float(last["r"]) - col_r, 0.8, "the last stack is a hop from the next level")
	# Stacks on one level never touch (lanes included).
	for i: int in all.size():
		for j: int in range(i + 1, all.size()):
			if int(all[i]["seg"]) == int(all[j]["seg"]):
				assert_gt(_air(all[i], all[j]), 0.4, "stacks %d and %d don't touch" % [i, j])
	assert_almost_eq(ChipTowers.level_y(ChipTowers.SEGMENTS), ClimbRoom.TOWER_TOP_Y, 0.001, "the last level is the pad")
	var layout: Dictionary = ClimbRoom.layout("towers")
	assert_true((layout["arena"] as AABB).has_point(_on_pad() + Vector3(0, 1, 0)), "the pad is in the arena")
	assert_true(ClimbRoom.on_top(_on_pad(), "towers"))
	assert_false(ClimbRoom.on_top(_on_stack(all.size() - 1), "towers"), "the last stack is not the top")


func test_stacks_are_close_with_only_a_few_wide_gaps() -> void:
	var all: Array[Dictionary] = ChipTowers.stacks()
	var gaps: Array[float] = []
	var wide: int = 0
	for seg: int in ChipTowers.SEGMENTS:
		for side: int in [-1, 1]:
			var ids: Array[int] = ChipTowers.lane(seg, side)
			for j: int in range(1, ids.size()):
				var gap: float = _air(all[ids[j - 1]], all[ids[j]])
				gaps.append(gap)
				if gap > ChipTowers.NORMAL_JUMP:
					wide += 1
					var rise: float = (all[ids[j]]["pos"] as Vector3).y - (all[ids[j - 1]]["pos"] as Vector3).y
					assert_lte(rise, 0.45, "a running jump barely rises (%.2f m)" % rise)
					assert_lte(gap, ChipTowers.MAX_GAP, "and stays in the walking jump's reach")
	assert_between(wide, 2, 6, "a few wide gaps, not many (%d)" % wide)
	var hops: int = gaps.filter(func(g: float) -> bool: return g <= 1.3).size()
	assert_gte(float(hops) / float(gaps.size()), 0.9, "almost every gap is a short hop (%d of %d)" % [hops, gaps.size()])
	var sum: float = 0.0
	for g: float in gaps:
		sum += g
	assert_lt(sum / float(gaps.size()), 1.3, "stacks stand close (mean air %.2f m)" % (sum / float(gaps.size())))


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
			for s: Dictionary in ChipTowers.stacks():
				var p: Vector3 = s["pos"]
				if int(s["seg"]) == k:
					assert_gt(Vector2(p.x - spot.x, p.z - spot.z).length(), float(s["r"]) + 0.4, "spot clear of the stacks")
	assert_eq(ChipTowers.checkpoint_at(Vector3(0, 0, ChipTowers.CENTER_Z + 10.0)), 0, "the floor is no checkpoint")
	var flags: Array[int] = []
	for cp: Dictionary in cps:
		flags.append(ChipTowers.checkpoint_at(Vector3(0, float(cp["y"]) + 0.6, ChipTowers.CENTER_Z) + ChipTowers.dir(float(cp["angle"])) * (ChipTowers.level_r(int(cp["index"])) - 0.3)))
	assert_eq(flags, [1, 2, 3], "anywhere on a tier's top counts, rim included")


## True if the pad can be reached from the floor jumping only between `allowed` stacks (and the
## tier tops), within the jump envelope.
func _reaches_top(allowed: Dictionary) -> bool:
	var all: Array[Dictionary] = ChipTowers.stacks()
	var level: int = 0
	var on: Array[int] = []
	var seen: Dictionary = {}
	while level < ChipTowers.SEGMENTS:
		on.clear()
		for i: int in allowed:
			var p: Vector3 = all[i]["pos"]
			if int(all[i]["seg"]) == level and p.y - ChipTowers.level_y(level) <= ChipTowers.MAX_RISE:
				on.append(i)  # a hop from the level's top
		var next_level: bool = false
		while not on.is_empty():
			var i: int = on.pop_back()
			if seen.has(i):
				continue
			seen[i] = true
			var p: Vector3 = all[i]["pos"]
			var col_r: float = ChipTowers.level_r(level + 1)
			if ChipTowers.level_y(level + 1) - p.y <= ChipTowers.MAX_RISE and _flat(p) - float(all[i]["r"]) - col_r <= ChipTowers.MAX_GAP:
				next_level = true
			for j: int in allowed:
				var q: Vector3 = all[j]["pos"]
				if not seen.has(j) and q.y - p.y <= ChipTowers.MAX_RISE and _air(all[i], all[j]) <= ChipTowers.MAX_GAP:
					on.append(j)
		if not next_level:
			return false
		level += 1
	return true


func test_two_separate_ways_up() -> void:
	var left: Dictionary = {}
	var right: Dictionary = {}
	for side: int in [-1, 1]:
		var route: Array[Dictionary] = ChipTowers.route([side, side, side, side])
		assert_eq(String(route[route.size() - 1]["kind"]), "pad", "the route ends on the pad")
		for seg: int in ChipTowers.SEGMENTS:
			for i: int in ChipTowers.lane(seg, side):
				(left if side < 0 else right)[i] = true
	assert_eq(left.keys().filter(func(i: int) -> bool: return right.has(i)).size(), 0, "the two chains share no stack")
	assert_true(_reaches_top(left), "the left chain alone reaches the jackpot")
	assert_true(_reaches_top(right), "the right chain alone reaches the jackpot")
	# Every tier forks: the lanes round each column go opposite ways from the flag.
	for seg: int in ChipTowers.SEGMENTS:
		var a: Vector3 = ChipTowers.stacks()[ChipTowers.lane(seg, -1)[1]]["pos"]
		var b: Vector3 = ChipTowers.stacks()[ChipTowers.lane(seg, 1)[1]]["pos"]
		assert_gt(Vector2(a.x - b.x, a.z - b.z).length(), 3.0, "segment %d forks at its flag" % seg)
	# And either lane of a segment may follow either lane of the one before (they rejoin on the tier).
	var mixed: Dictionary = {}
	for seg: int in ChipTowers.SEGMENTS:
		for i: int in ChipTowers.lane(seg, -1 if seg % 2 == 0 else 1):
			mixed[i] = true
	assert_true(_reaches_top(mixed), "a zig-zag of lanes reaches the jackpot too")


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
	var above: int = ChipTowers.lane(2, 1)[3]
	g.world.set_transform(1, _on_stack(above), 0.0)
	_run(g, 0.2)
	assert_true(g.pending_moves.is_empty(), "up on the next stacks: nothing to do")
	g.world.set_transform(1, WalkableLogicBase.ROOM_ORIGIN + Vector3(0, 0, ChipTowers.CENTER_Z + 10.5), 0.0)
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
	# The server puts the body on the flag. A short drop onto the last stacks under it is fine.
	g.world.set_transform(1, g.pending_moves[1], 0.0)
	g.pending_moves.clear()
	_run(g, JackpotClimbLogic.RESPAWN_GRACE)
	var under: Array[int] = ChipTowers.lane(1, -1)
	g.world.set_transform(1, _on_stack(under[under.size() - 1]), 0.0)
	evs = _run(g, 0.2)
	assert_true(_of(evs, &"jackpot_climb_respawn").is_empty(), "one stack down is still climbing")
	assert_eq(g.private_state(1)["checkpoint"], 2)
	assert_eq(g.private_state(1)["respawns"], 2)


func test_before_the_first_flag_a_fall_is_just_physics() -> void:
	var g: JackpotClimbLogic = _game([1, 2])
	_run(g, STEP)
	g.world.set_transform(2, _on_stack(ChipTowers.lane(0, -1)[8]), 0.0)
	_run(g, 0.2)
	g.world.set_transform(2, WalkableLogicBase.ROOM_ORIGIN + Vector3(3.0, 0.0, -2.0), 0.0)
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
	var at: Vector3 = _on_stack(ChipTowers.lane(1, 1)[2])
	g.world.set_transform(2, at, 0.0)
	g.world.set_transform(1, at + Vector3(0, 0, 1.0), 0.0)
	_run(g, JackpotClimbLogic.SWING_COOLDOWN)
	g.world.set_transform(1, g.world.get_position(2) + Vector3(0, 0, 1.0), 0.0)
	assert_eq(_swing(g, 1)["result"], &"hit")
	g.world.set_transform(2, WalkableLogicBase.ROOM_ORIGIN + Vector3(0, 0, -1.5), 0.0)  # the ragdoll on the floor
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
	g.world.set_transform(1, _on_stack(10), 0.0)
	g.world.set_transform(2, _on_stack(4), 0.0)
	assert_almost_eq(g.height_of(1), (ChipTowers.stacks()[10]["pos"] as Vector3).y / ClimbRoom.TOWER_TOP_Y, 0.001)
	assert_gt(g.height_of(1), g.height_of(2), "higher stack, more progress")
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
	var held: Vector3 = g.clamp_position(2, _on_stack(3))
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
	_face(g, 1, 3, 1.0, 8)
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
	g.world.set_transform(1, _on_stack(12), 0.0)
	g.world.set_transform(2, _on_stack(6), 0.0)
	g.world.set_transform(3, _on_stack(6, Vector3(0.3, 0, 0)), 0.0)
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
	g.world.set_transform(2, _on_stack(15), 0.0)
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
