extends GutTest
## Pass the Bomb (MINIGAME_IDEAS #14, the first walkable minigame): the holder tags the player in
## front of them in reach to pass the bomb (0.5 s no-return), a hidden 8-20 s fuse blows the holder
## out, a new bomb starts 2 s later, the last one standing wins, ranking is reverse elimination
## order, dropouts are out at that moment, the game is capped at 150 s.

const STEP: float = 0.05

var cfg: BalanceConfig = BalanceConfig.new()


func _game(players: Array[int], seed_value: int = 7) -> PassTheBombLogic:
	var g := PassTheBombLogic.new()
	g.setup(players, SeededRng.new(seed_value), cfg, {}, {})
	g.world = WorldQuery.new()
	for p: int in players:
		g.world.set_transform(p, g.spawn_for(p), g.spawn_yaw_for(p))
	return g


## Ticks until the first bomb is lit; returns its holder.
func _light(g: PassTheBombLogic) -> int:
	g.tick(PassTheBombLogic.FIRST_BOMB_DELAY + 0.01, 0.0)
	assert_eq(g.state, PassTheBombLogic.State.LIVE, "a bomb is lit after the first delay")
	return g.holder


## Puts `a` `dist` metres from `b` (in the middle of the arena), facing them (or away).
func _face(g: PassTheBombLogic, a: int, b: int, dist: float, away: bool = false) -> void:
	var c: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	g.world.set_transform(b, c, 0.0)
	var pos: Vector3 = c + Vector3(0, 0, dist)  # b is at -z from a
	var dir: Vector3 = (c - pos).normalized()
	if away:
		dir = -dir
	g.world.set_transform(a, pos, atan2(-dir.x, -dir.z))


func _tag(g: PassTheBombLogic, p: int, hint: int = -1) -> Dictionary:
	var intent: Dictionary = {"type": &"minigame_action", "kind": "tag"}
	if hint >= 0:
		intent["target"] = hint
	return g.submit(p, intent, 0.0)


func _events_of(evs: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	return evs.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## Ticks until an event of `type` shows up (or `max_s` pass); returns it ({} if none). Every event
## drained on the way is appended to `seen`.
func _run_until(g: PassTheBombLogic, type: StringName, max_s: float, seen: Array[Dictionary] = []) -> Dictionary:
	var t: float = 0.0
	while t < max_s:
		g.tick(STEP, 0.0)
		t += STEP
		var evs: Array[Dictionary] = g.drain_events()
		seen.append_array(evs)
		var hits: Array[Dictionary] = _events_of(evs, type)
		if not hits.is_empty():
			return hits[0]
	return {}


func _row(ranking: Array[Dictionary], player: int) -> Dictionary:
	for r: Dictionary in ranking:
		if int(r["player"]) == player:
			return r
	return {}


func test_the_first_bomb_goes_to_a_random_player() -> void:
	var holders: Dictionary = {}
	for s: int in 12:
		var g: PassTheBombLogic = _game([1, 2, 3, 4], s)
		assert_eq(g.holder, -1, "no bomb before the game goes")
		var h: int = _light(g)
		assert_true(h in [1, 2, 3, 4])
		assert_eq(_events_of(g.drain_events(), &"pass_the_bomb_new").size(), 1)
		holders[h] = true
	assert_gt(holders.size(), 1, "the starting holder varies with the seed")


func test_a_tag_passes_the_bomb_to_the_player_in_front_in_reach() -> void:
	var g: PassTheBombLogic = _game([1, 2, 3])
	var h: int = _light(g)
	var other: int = 2 if h != 2 else 3
	_face(g, h, other, 1.2)
	g.drain_events()
	var res: Dictionary = _tag(g, h)
	assert_true(res["ok"], "tag in reach accepted: %s" % res)
	assert_eq(g.holder, other, "the bomb jumped")
	var passed: Array[Dictionary] = _events_of(g.drain_events(), &"pass_the_bomb_passed")
	assert_eq(passed.size(), 1)
	assert_eq(int(passed[0]["from"]), h)
	assert_eq(int(passed[0]["to"]), other)


func test_reach_and_facing_decide_not_the_client() -> void:
	var g: PassTheBombLogic = _game([1, 2])
	var h: int = _light(g)
	var other: int = 3 - h
	_face(g, h, other, 2.4)
	assert_eq(_tag(g, h, other)["error"], &"no_target", "too far, even with a hint")
	_face(g, h, other, 1.3, true)
	assert_eq(_tag(g, h, other)["error"], &"no_target", "behind the holder")
	assert_eq(_tag(g, other)["error"], &"not_holder", "only the holder tags")
	_face(g, h, other, 1.5)
	assert_true(_tag(g, h)["ok"], "in front within 1.6 m")
	assert_eq(g.submit(other, {"type": &"minigame_action", "kind": "steal"}, 0.0)["error"], &"bad_value", "unknown action kinds refused")


func test_the_bomb_cannot_go_straight_back() -> void:
	var g: PassTheBombLogic = _game([1, 2, 3])
	var a: int = _light(g)
	var b: int = 2 if a != 2 else 3
	var c: int = 6 - a - b
	g.world.set_transform(c, WalkableLogicBase.ROOM_ORIGIN + Vector3(6, 0, 6), 0.0)
	_face(g, a, b, 1.0)
	assert_true(_tag(g, a)["ok"])
	_face(g, b, a, 1.0)
	assert_eq(_tag(g, b, a)["error"], &"no_return", "no instant ping-pong")
	assert_eq(g.holder, b)
	# Someone else in reach is fair game at once, even when the client hinted the giver.
	g.world.set_transform(c, g.world.get_position(a) + Vector3(0.6, 0, 0), 0.0)
	var res: Dictionary = _tag(g, b, a)
	assert_true(res["ok"], "another target in reach: %s" % res)
	assert_eq(g.holder, c)
	# And after the cooldown it can go back.
	_face(g, c, b, 1.0)
	g.world.set_transform(a, WalkableLogicBase.ROOM_ORIGIN + Vector3(-6, 0, -6), 0.0)
	assert_eq(_tag(g, c, b)["error"], &"no_return")
	g.tick(PassTheBombLogic.NO_RETURN_SECONDS + 0.01, 0.0)
	assert_true(_tag(g, c, b)["ok"], "after 0.5 s the giver can be tagged back")
	assert_eq(g.holder, b)


func test_the_fuse_is_never_public() -> void:
	var g: PassTheBombLogic = _game([1, 2, 3, 4], 3)
	var seen: Array[Dictionary] = []
	var fuses: Array[float] = []
	for bomb: int in 3:
		var ev: Dictionary = _run_until(g, &"pass_the_bomb_new", 5.0, seen)
		assert_false(ev.is_empty(), "bomb %d lit" % bomb)
		fuses.append(g._fuse_left)
		assert_between(g._fuse_left, PassTheBombLogic.FUSE_MIN, PassTheBombLogic.FUSE_MAX)
		for i: int in 40:
			g.tick(0.1, 0.0)
			seen.append_array(g.drain_events())
			var now_fuses: Array[float] = fuses.duplicate()
			now_fuses.append(g._fuse_left)
			_assert_no_fuse(g.get_public_state(), now_fuses, "public state")
			for p: int in [1, 2, 3, 4]:
				_assert_no_fuse(g.private_state(p), now_fuses, "private state")
		_run_until(g, &"pass_the_bomb_exploded", 25.0, seen)
	for e: Dictionary in seen:
		_assert_no_fuse(e, fuses, "event %s" % e["type"])


func _assert_no_fuse(v: Variant, fuses: Array[float], where: String) -> void:
	if v is Dictionary:
		for k: Variant in v:
			assert_false(str(k).to_lower().contains("fuse"), "%s has no fuse key (%s)" % [where, k])
			_assert_no_fuse(v[k], fuses, where)
	elif v is Array:
		for x: Variant in v:
			_assert_no_fuse(x, fuses, where)
	elif v is float:
		for f: float in fuses:
			assert_false(absf(float(v) - f) < 0.000001 and f > 0.0, "%s carries the fuse value %.3f" % [where, f])


func test_the_fuse_runs_8_to_20_seconds() -> void:
	for s: int in 8:
		var g: PassTheBombLogic = _game([1, 2], s * 11 + 1)
		_light(g)
		g.drain_events()
		var t: float = 0.0
		while g.state == PassTheBombLogic.State.LIVE and t < 30.0:
			g.tick(STEP, 0.0)
			t += STEP
		assert_between(t, PassTheBombLogic.FUSE_MIN - STEP, PassTheBombLogic.FUSE_MAX + STEP, "seed %d fuse" % s)


func test_a_bang_takes_the_holder_out_and_a_new_bomb_follows() -> void:
	var g: PassTheBombLogic = _game([1, 2, 3])
	var h: int = _light(g)
	var seen: Array[Dictionary] = []
	var boom: Dictionary = _run_until(g, &"pass_the_bomb_exploded", 25.0, seen)
	assert_eq(int(boom["player"]), h, "the holder blows up")
	assert_false(g.is_alive(h))
	assert_eq(g.alive.size(), 2)
	assert_eq(g.holder, -1)
	var out: Array[Dictionary] = _events_of(seen, &"minigame_eliminated")
	assert_eq(out.size(), 1)
	assert_eq(int(out[0]["place"]), 3)
	assert_eq(g.pending_knockdowns.size(), 1, "the server knocks them down (ragdoll)")
	assert_eq(int(g.pending_knockdowns[0]["player"]), h)
	assert_eq(g.pending_moves.get(h, Vector3.INF), g.gallery_spot_for(h), "then off to the gallery")
	assert_true(g.gallery.has_point(g.gallery_spot_for(h)))
	assert_eq(_tag(g, h)["error"], &"eliminated")
	g.tick(PassTheBombLogic.NEXT_BOMB_DELAY - 0.1, 0.0)
	assert_eq(g.holder, -1, "a short breather first")
	g.tick(0.2, 0.0)
	assert_true(g.holder in g.alive, "new bomb with the rest")


func test_last_one_standing_wins_and_the_ranking_is_reverse_elimination() -> void:
	var g: PassTheBombLogic = _game([1, 2, 3, 4], 5)
	var order: Array[int] = []
	var t: float = 0.0
	while not g.finished and t < 120.0:
		g.tick(STEP, 0.0)
		t += STEP
		for e: Dictionary in _events_of(g.drain_events(), &"pass_the_bomb_exploded"):
			order.append(int(e["player"]))
	assert_true(g.finished)
	assert_eq(order.size(), 3, "three bangs for four players")
	var winner: int = g.alive[0]
	var r: Array[Dictionary] = g.ranking()
	assert_eq(r.size(), 4)
	assert_eq(int(r[0]["player"]), winner)
	assert_eq(int(_row(r, winner)["rank"]), 1)
	assert_eq(int(_row(r, order[2])["rank"]), 2)
	assert_eq(int(_row(r, order[1])["rank"]), 3)
	assert_eq(int(_row(r, order[0])["rank"]), 4)
	assert_gt(int(_row(r, winner)["points"]), int(_row(r, order[0])["points"]))


func test_the_game_ends_after_the_last_bang_is_shown() -> void:
	var g: PassTheBombLogic = _game([1, 2])
	_light(g)
	_run_until(g, &"pass_the_bomb_exploded", 25.0)
	assert_false(g.finished, "the bang stays on screen a moment")
	assert_eq(g.state, PassTheBombLogic.State.DONE)
	g.tick(PassTheBombLogic.END_HOLD + 0.1, 0.0)
	assert_true(g.finished)
	assert_eq(_events_of(g.drain_events(), &"pass_the_bomb_finished").size(), 1)


func test_two_players() -> void:
	var g: PassTheBombLogic = _game([10, 20])
	var h: int = _light(g)
	var seen: Array[Dictionary] = []
	_run_until(g, &"pass_the_bomb_exploded", 25.0, seen)
	var over: Dictionary = _run_until(g, &"pass_the_bomb_finished", 5.0, seen)
	assert_false(over.is_empty())
	var r: Array[Dictionary] = g.ranking()
	assert_eq(int(_row(r, 30 - h)["rank"]), 1)
	assert_eq(int(_row(r, h)["rank"]), 2)


func test_a_holder_dropping_out_is_out_and_a_new_bomb_comes() -> void:
	var g: PassTheBombLogic = _game([1, 2, 3])
	var h: int = _light(g)
	g.drain_events()
	g.remove_player(h)
	var evs: Array[Dictionary] = g.drain_events()
	assert_eq(_events_of(evs, &"pass_the_bomb_fizzled").size(), 1)
	assert_eq(_events_of(evs, &"pass_the_bomb_exploded").size(), 0, "no bang")
	assert_eq(_events_of(evs, &"minigame_eliminated")[0]["cause"], &"dropout")
	assert_eq(g.alive.size(), 2)
	assert_eq(g.holder, -1)
	g.tick(PassTheBombLogic.NEXT_BOMB_DELAY + 0.05, 0.0)
	assert_true(g.holder in g.alive)
	assert_true(_row(g.ranking(), h).is_empty(), "dropouts leave the ranking like in every minigame")


func test_a_dropout_down_to_one_ends_the_game() -> void:
	var g: PassTheBombLogic = _game([1, 2])
	var h: int = _light(g)
	g.remove_player(3 - h)
	assert_eq(g.state, PassTheBombLogic.State.DONE)
	g.tick(PassTheBombLogic.END_HOLD + 0.1, 0.0)
	assert_true(g.finished)
	assert_eq(int(g.ranking()[0]["player"]), h)
	assert_eq(g.ranking().size(), 1)


func test_the_cap_lets_the_survivors_share_first() -> void:
	var g: PassTheBombLogic = _game([1, 2, 3])
	_light(g)
	g._fuse_left = 10000.0  # a dud: nobody blows up before the cap
	var seen: Array[Dictionary] = []
	var over: Dictionary = _run_until(g, &"pass_the_bomb_over", PassTheBombLogic.CAP_SECONDS + 1.0, seen)
	assert_eq(over["reason"], &"time")
	assert_almost_eq(g.clock, PassTheBombLogic.CAP_SECONDS, 0.001)
	g.tick(PassTheBombLogic.END_HOLD + 0.1, 0.0)
	assert_true(g.finished)
	for r: Dictionary in g.ranking():
		assert_eq(int(r["rank"]), 1, "every survivor shares first")


func test_positions_are_clamped_to_the_arena_and_the_gallery() -> void:
	var g: PassTheBombLogic = _game([1, 2, 3])
	var inside: Vector3 = WalkableLogicBase.ROOM_ORIGIN + Vector3(1, 0, 1)
	assert_eq(g.clamp_position(1, inside), inside, "inside: untouched")
	var step_out: Vector3 = Vector3(g.arena.end.x + 0.4, 0.0, inside.z)
	var held: Vector3 = g.clamp_position(1, step_out)
	assert_true(g.arena.has_point(held) or is_equal_approx(held.x, g.arena.end.x), "a step out is held at the bound")
	assert_almost_eq(held.x, g.arena.end.x, 0.001)
	assert_eq(g.clamp_position(1, Vector3(0, 0, 0)), g.spawn_for(1), "the casino floor: back to the spawn")
	g.eliminate([2], &"bomb")
	assert_eq(g.clamp_position(2, inside), g.gallery_spot_for(2), "out players can't walk back in")
	var gal: Vector3 = g.gallery_spot_for(2)
	assert_eq(g.clamp_position(2, gal), gal)
	assert_eq(g.clamp_position(99, Vector3.ZERO), Vector3.ZERO, "non-participants are left alone")
	for p: int in [1, 2, 3]:
		assert_true(g.arena.has_point(g.spawn_for(p)), "spawn %d in the arena" % p)
	assert_false(g.arena.intersects(g.gallery), "arena and gallery apart")
