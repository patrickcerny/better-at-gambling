extends GutTest
## Jackpot Climb (MINIGAME_IDEAS #11): the chip-tower route is climbable within the jump envelope,
## height is progress up the jackpot stack from the server's positions, standing on the pad
## finishes in order (shared places on one tick), a bat swing knocks a climber in reach down with
## a cooldown, finishers and the just-got-up grace are safe, the 120 s cap ranks by height with
## ties, dropouts, two players, grab blocked and shove allowed.

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


func test_every_ledge_is_reachable_within_the_jump_envelope() -> void:
	var route: Array[Dictionary] = ChipTowers.route()
	assert_gt(route.size(), 12, "a real climb")
	var prev_y: float = 0.0  # the net floor
	for i: int in route.size():
		var p: Vector3 = route[i]["pos"]
		var rise: float = p.y - prev_y
		assert_between(rise, 0.3, ChipTowers.MAX_RISE, "step %d rises %.2f m" % [i, rise])
		if i > 0:
			var q: Vector3 = route[i - 1]["pos"]
			var gap: float = Vector2(p.x - q.x, p.z - q.z).length() - float(route[i]["r"]) - float(route[i - 1]["r"])
			assert_between(gap, 0.8, ChipTowers.MAX_GAP, "step %d leaves %.2f m of air" % [i, gap])
			if i < route.size() - 1:
				assert_gte(gap, 1.59, "stack to stack is a real jump (%d)" % i)
		prev_y = p.y
	assert_almost_eq(prev_y, ClimbRoom.TOWER_TOP_Y, 0.001, "the route ends on the pad")
	# No stack overlaps another, the pad or the walls, and the first is a walk from the apron.
	var stacks: Array[Dictionary] = ChipTowers.stacks()
	for i: int in stacks.size():
		var a: Vector3 = stacks[i]["pos"]
		var ra: float = stacks[i]["r"]
		assert_lt(absf(a.x) + ra, ClimbRoom.HALL_HALF_X - 0.5, "inside the hall (%d)" % i)
		assert_gt(Vector2(a.x, a.z - ChipTowers.CENTER_Z).length() - ra - ChipTowers.PAD_R, 0.8, "clear of the pad (%d)" % i)
		for j: int in range(i + 1, stacks.size()):
			var b: Vector3 = stacks[j]["pos"]
			var d: float = Vector2(a.x - b.x, a.z - b.z).length() - ra - float(stacks[j]["r"])
			assert_gt(d, 0.8, "stacks %d and %d don't touch" % [i, j])
			if j > i + 1:
				# Skipping ahead is out of the jump: too far, or too high for the 1.1 m jump.
				assert_true(d > ChipTowers.MAX_GAP + 0.5 or b.y - a.y > 1.3, "no shortcut from %d to %d (%.2f m apart, %.2f m up)" % [i, j, d, b.y - a.y])
	assert_lt((stacks[0]["pos"] as Vector3).z, -2.5, "the first stack stands off the apron")
	var layout: Dictionary = ClimbRoom.layout("towers")
	assert_true((layout["arena"] as AABB).has_point(_on_pad() + Vector3(0, 1, 0)), "the pad is in the arena")
	assert_true(ClimbRoom.on_top(_on_pad(), "towers"))
	assert_false(ClimbRoom.on_top(_on_stack(stacks.size() - 1), "towers"), "the last stack is not the top")


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
	for k: String in ["clock", "finish", "heights", "room", "down", "immune", "last_call"]:
		assert_true(st.has(k), "state has %s" % k)
