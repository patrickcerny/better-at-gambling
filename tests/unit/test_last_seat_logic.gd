extends GutTest
## Last Seat at the Table (MINIGAME_IDEAS #5): musical chairs in the parlor. The music stops at a
## server-picked time (6..14 s from the seeded rng), one stool fewer than beans comes out, the
## server decides every claim (action button in reach, or touching a stool), seated beans can't be
## shoved and stay pinned, whoever is left standing at the end of the round (all stools taken or
## the 10 s grace) is out together, the last bean seated wins.

const STEP: float = 0.05

var cfg: BalanceConfig = BalanceConfig.new()


func _game(players: Array[int], seed_value: int = 7) -> LastSeatLogic:
	var g := LastSeatLogic.new()
	g.setup(players, SeededRng.new(seed_value), cfg, {}, {})
	g.world = WorldQuery.new()
	for p: int in players:
		g.world.set_transform(p, g.spawn_for(p), g.spawn_yaw_for(p))
	return g


func _run(g: LastSeatLogic, seconds: float) -> Array[Dictionary]:
	var seen: Array[Dictionary] = []
	var t: float = 0.0
	while t < seconds - 0.0001:
		g.tick(STEP, 0.0)
		t += STEP
		seen.append_array(g.drain_events())
	return seen


## Ticks until the music stops (the scramble starts).
func _to_scramble(g: LastSeatLogic) -> Array[Dictionary]:
	var seen: Array[Dictionary] = []
	var t: float = 0.0
	while g.state != LastSeatLogic.State.SCRAMBLE and t < 60.0:
		seen.append_array(_run(g, STEP))
		t += STEP
	assert_eq(g.state, LastSeatLogic.State.SCRAMBLE, "the music stopped")
	return seen


func _of(evs: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	return evs.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _sit(g: LastSeatLogic, p: int, stool: int = -1) -> Dictionary:
	var intent: Dictionary = {"type": &"minigame_action", "kind": "sit"}
	if stool >= 0:
		intent["target"] = stool
	return g.submit(p, intent, 0.0)


## Puts `p` `dist` metres out from stool `i` (away from the table).
func _near(g: LastSeatLogic, p: int, i: int, dist: float = 0.9) -> void:
	var out: Vector3 = (g.stools[i] - ParlorRoom.table_center()).normalized()
	g.world.set_transform(p, g.stools[i] + out * dist, 0.0)


## Keeps everyone far from every stool (in the corners) so nobody sits by touching.
func _park(g: LastSeatLogic) -> void:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var corners: Array[Vector3] = [o + Vector3(-6, 0, -5), o + Vector3(6, 0, -5), o + Vector3(-6, 0, 4), o + Vector3(6, 0, 4), o + Vector3(0, 0, 5)]
	for i: int in g.players.size():
		g.world.set_transform(g.players[i], corners[i % corners.size()], 0.0)


func test_setup_spawns_in_the_parlor_and_announce_from_the_first_tick() -> void:
	var g: LastSeatLogic = _game([1, 2, 3, 4])
	assert_eq(g.id, &"last_seat")
	for p: int in [1, 2, 3, 4]:
		assert_true(g.arena.has_point(g.spawn_for(p)), "spawn in the parlor")
	var evs: Array[Dictionary] = _run(g, STEP)
	assert_eq(_of(evs, &"last_seat_begin").size(), 1, "announced on the first tick")
	var rounds: Array[Dictionary] = _of(evs, &"last_seat_round")
	assert_eq(rounds.size(), 1)
	assert_eq(int(rounds[0]["stools"]), 3, "one stool fewer than players")
	var st: Dictionary = g.get_public_state()
	for key: String in ["round", "music", "stool_count", "stools", "seated", "alive", "out", "room", "state"]:
		assert_true(st.has(key), "state carries %s for a late stage" % key)
	assert_true(st["music"])
	assert_eq((st["stools"] as Array).size(), 0, "the stools stay hidden while the music plays")
	assert_false(st.has("music_left"), "the stop time is never sent")
	assert_true(g.blocks_intent(&"grab"), "grab is off")
	assert_false(g.blocks_intent(&"shove"), "shoving is allowed")


func test_music_stop_time_comes_from_the_seeded_rng() -> void:
	var a: LastSeatLogic = _game([1, 2, 3], 11)
	var b: LastSeatLogic = _game([1, 2, 3], 11)
	_run(a, STEP)
	_run(b, STEP)
	assert_eq(a.music_length, b.music_length, "same seed, same stop")
	assert_between(a.music_length, LastSeatLogic.MUSIC_MIN, LastSeatLogic.MUSIC_MAX)
	var lengths: Dictionary = {}
	for s: int in 8:
		var g: LastSeatLogic = _game([1, 2, 3], 100 + s)
		_run(g, STEP)
		assert_between(g.music_length, LastSeatLogic.MUSIC_MIN, LastSeatLogic.MUSIC_MAX)
		lengths[snappedf(g.music_length, 0.01)] = true
	assert_gt(lengths.size(), 4, "the stop moves around")
	# It stops right on time, not before.
	_park(a)
	_run(a, a.music_length - 0.2)
	assert_eq(a.state, LastSeatLogic.State.MUSIC)
	var evs: Array[Dictionary] = _run(a, 0.4)
	assert_eq(a.state, LastSeatLogic.State.SCRAMBLE)
	var stop: Array[Dictionary] = _of(evs, &"last_seat_stop")
	assert_eq(stop.size(), 1)
	assert_eq((stop[0]["stools"] as Array).size(), 2)


func test_claim_refused_while_the_music_plays() -> void:
	var g: LastSeatLogic = _game([1, 2, 3])
	_run(g, STEP)
	assert_eq(_sit(g, 1)["error"], &"music_playing")
	assert_eq(g.submit(1, {"type": &"minigame_action", "kind": "tag"}, 0.0)["error"], &"bad_value")


func test_claims_need_reach_and_the_first_claim_wins() -> void:
	var g: LastSeatLogic = _game([1, 2, 3])
	_run(g, STEP)
	_park(g)
	_to_scramble(g)
	assert_eq(g.stools.size(), 2)
	# Far away: no stool in reach, even with a hint.
	assert_eq(_sit(g, 1, 0)["error"], &"no_stool")
	# Next to stool 0: claimed.
	_near(g, 1, 0)
	var res: Dictionary = _sit(g, 1, 0)
	assert_true(res["ok"], "sit: %s" % res)
	assert_eq(int(res["stool"]), 0)
	assert_true(g.is_seated(1))
	# A second claimant at the same stool is refused; claiming twice is refused.
	_near(g, 2, 0, 1.0)
	assert_eq(_sit(g, 2, 0)["error"], &"taken")
	assert_eq(_sit(g, 1, 1)["error"], &"seated")
	assert_eq(g.sitter[0], 1, "the stool stays with the first")
	var st: Dictionary = g.get_public_state()
	assert_eq(int(st["seated"][1]), 0)


func test_touching_a_stool_sits_the_nearest_bean() -> void:
	var g: LastSeatLogic = _game([1, 2, 3])
	_run(g, STEP)
	_park(g)
	_to_scramble(g)
	_near(g, 2, 1, 0.5)
	_near(g, 3, 1, LastSeatLogic.SIT_TOUCH - 0.02)
	var evs: Array[Dictionary] = _run(g, STEP)
	var sat: Array[Dictionary] = _of(evs, &"last_seat_sat")
	assert_eq(sat.size(), 1)
	assert_eq(int(sat[0]["player"]), 2, "the closer bean gets it")
	assert_eq(sat[0]["how"], &"touch")
	assert_false(g.is_seated(3))


func test_seated_bean_cannot_be_shoved_off_and_stays_pinned() -> void:
	var g: LastSeatLogic = _game([1, 2, 3])
	_run(g, STEP)
	_park(g)
	_to_scramble(g)
	_near(g, 1, 0)
	assert_true(_sit(g, 1)["ok"])
	assert_true(g.is_untouchable(1), "the server makes a seated bean immune to shoves")
	assert_false(g.is_untouchable(2))
	var seat: Vector3 = g.seat_position(0)
	assert_eq(g.clamp_position(1, seat + Vector3(3, 0, 0)), seat, "a shove (or a walk) off the stool snaps back")
	assert_eq(g.clamp_position(1, seat + Vector3(0.1, 0, 0)), seat + Vector3(0.1, 0, 0), "small drift is fine")
	var far: Vector3 = WalkableLogicBase.ROOM_ORIGIN + Vector3(1, 0, 3.8)
	assert_eq(g.clamp_position(2, far), far, "standing beans walk freely")


func test_round_end_eliminates_the_one_left_standing() -> void:
	var g: LastSeatLogic = _game([1, 2, 3, 4])
	_run(g, STEP)
	_park(g)
	_to_scramble(g)
	assert_eq(g.stools.size(), 3)
	for i: int in 3:
		_near(g, i + 1, i)
		assert_true(_sit(g, i + 1)["ok"])
	var evs: Array[Dictionary] = _run(g, STEP)
	var over: Array[Dictionary] = _of(evs, &"last_seat_round_over")
	assert_eq(over.size(), 1, "all stools taken: the round ends at once")
	assert_eq(over[0]["out"], [4])
	var elim: Array[Dictionary] = _of(evs, &"minigame_eliminated")
	assert_eq(elim.size(), 1)
	assert_eq(elim[0]["players"], [4])
	assert_eq(elim[0]["cause"], &"no_seat")
	assert_false(g.is_alive(4))
	assert_true(g.pending_moves.has(4), "off to the gallery")
	assert_true(g.gallery.has_point(g.pending_moves[4]))
	# Next round: the seated get up next to their stool, one stool fewer.
	evs = _run(g, LastSeatLogic.RESULT_HOLD + STEP)
	var rounds: Array[Dictionary] = _of(evs, &"last_seat_round")
	assert_eq(rounds.size(), 1)
	assert_eq(int(rounds[0]["round"]), 2)
	assert_eq(int(rounds[0]["stools"]), 2)
	assert_eq(g.state, LastSeatLogic.State.MUSIC)
	assert_true(g.seat_of.is_empty())
	for p: int in [1, 2, 3]:
		assert_true(g.pending_moves.has(p), "released from the stool")
		assert_almost_eq(g.pending_moves[p].y, 0.0, 0.001)
		assert_false(g.is_untouchable(p))


func test_grace_end_puts_everyone_standing_out_together() -> void:
	var g: LastSeatLogic = _game([1, 2, 3, 4, 5])
	_run(g, STEP)
	_park(g)
	_to_scramble(g)
	assert_eq(g.stools.size(), 4)
	_near(g, 1, 0)
	assert_true(_sit(g, 1)["ok"])
	_near(g, 2, 1)
	assert_true(_sit(g, 2)["ok"])
	_park(g)  # 3, 4 and 5 dither in the corners (1 and 2 stay pinned on the server anyway)
	var evs: Array[Dictionary] = _run(g, LastSeatLogic.GRACE - 0.5)
	assert_true(_of(evs, &"last_seat_round_over").is_empty(), "still in grace")
	evs = _run(g, 1.0)
	var elim: Array[Dictionary] = _of(evs, &"minigame_eliminated")
	assert_eq(elim.size(), 1, "one shared group")
	assert_eq(elim[0]["players"], [3, 4, 5])
	var rank: Dictionary = {}
	for row: Dictionary in g.ranking():
		rank[row["player"]] = row["rank"]
	assert_eq(rank[3], 3)
	assert_eq(rank[4], 3)
	assert_eq(rank[5], 3)
	assert_eq(rank[1], 1)
	assert_eq(rank[2], 1)


func test_full_game_ranks_by_elimination_and_ends_with_one_seated_winner() -> void:
	var g: LastSeatLogic = _game([1, 2, 3])
	_run(g, STEP)
	# Round 1: 1 and 2 sit, 3 is out.
	_park(g)
	_to_scramble(g)
	_near(g, 1, 0)
	_sit(g, 1)
	_near(g, 2, 1)
	_sit(g, 2)
	_run(g, STEP)
	assert_false(g.is_alive(3))
	_run(g, LastSeatLogic.RESULT_HOLD + STEP)
	# Round 2: one stool, 2 gets it.
	_park(g)
	_to_scramble(g)
	assert_eq(g.stools.size(), 1)
	_near(g, 2, 0)
	assert_true(_sit(g, 2)["ok"])
	var evs: Array[Dictionary] = _run(g, STEP)
	var win: Array[Dictionary] = _of(evs, &"last_seat_winner")
	assert_eq(win.size(), 1)
	assert_eq(int(win[0]["player"]), 2)
	assert_true(g.is_seated(2), "the winner stays on the last seat for the reveal")
	assert_false(g.is_finished())
	evs = _run(g, LastSeatLogic.END_HOLD + STEP)
	assert_true(g.is_finished())
	assert_eq(_of(evs, &"last_seat_finished").size(), 1)
	var r: Array[Dictionary] = g.ranking()
	assert_eq(r.size(), 3)
	assert_eq([r[0]["player"], r[0]["rank"]], [2, 1])
	assert_eq([r[1]["player"], r[1]["rank"]], [1, 2])
	assert_eq([r[2]["player"], r[2]["rank"]], [3, 3])
	assert_false(g.is_untouchable(2), "unpinned once the game is over")


func test_two_players_is_one_round_with_one_stool() -> void:
	var g: LastSeatLogic = _game([1, 2])
	var evs: Array[Dictionary] = _run(g, STEP)
	assert_eq(int(_of(evs, &"last_seat_round")[0]["stools"]), 1)
	_park(g)
	_to_scramble(g)
	assert_eq(g.stools.size(), 1)
	_near(g, 1, 0, 0.3)
	evs = _run(g, STEP)
	assert_eq(_of(evs, &"last_seat_sat").size(), 1, "ran onto it")
	assert_eq(int(_of(evs, &"last_seat_winner")[0]["player"]), 1)
	_run(g, LastSeatLogic.END_HOLD + STEP)
	assert_true(g.is_finished())
	assert_eq(g.round_no, 1)
	assert_eq(g.ranking()[0]["player"], 1)


func test_a_dropout_mid_round() -> void:
	var g: LastSeatLogic = _game([1, 2, 3, 4])
	_run(g, STEP)
	_park(g)
	_to_scramble(g)
	_near(g, 1, 0)
	assert_true(_sit(g, 1)["ok"])
	# A seated bean leaves: the stool is free again and they are out (dropout).
	var evs: Array[Dictionary] = []
	g.remove_player(1)
	evs.append_array(g.drain_events())
	assert_false(g.sitter.has(0), "their stool is free")
	assert_eq(_of(evs, &"minigame_eliminated")[0]["cause"], &"dropout")
	# 3 left, 3 stools: everyone can sit, nobody is out this round.
	for i: int in 3:
		_near(g, i + 2, i)
		assert_true(_sit(g, i + 2)["ok"])
	evs = _run(g, STEP)
	assert_eq(_of(evs, &"last_seat_round_over")[0]["out"], [])
	evs = _run(g, LastSeatLogic.RESULT_HOLD + STEP)
	assert_eq(int(_of(evs, &"last_seat_round")[0]["stools"]), 2, "next round: 3 left, 2 stools")
	# Down to one bean by dropouts: that bean wins.
	g.remove_player(2)
	g.remove_player(3)
	evs = g.drain_events()
	assert_eq(int(_of(evs, &"last_seat_winner")[0]["player"]), 4)
	_run(g, LastSeatLogic.END_HOLD + STEP)
	assert_true(g.is_finished())
	assert_eq(g.ranking().size(), 1, "dropouts leave the ranking")
	assert_eq(g.ranking()[0]["player"], 4)
