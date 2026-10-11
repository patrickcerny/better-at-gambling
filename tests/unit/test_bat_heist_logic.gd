extends GutTest
## Bat Heist (MINIGAME_IDEAS #10): everyone starts with 10 coins, a bat swing (1.2 s cooldown, a
## miss is fine) knocks the bean in front down, holding the steal over a downed bean in reach moves
## 1 coin per 0.4 s, 3 s of immunity after getting up, 60 s, most coins wins with shared ranks.

const STEP: float = 0.05

var cfg: BalanceConfig = BalanceConfig.new()


func _game(players: Array[int], seed_value: int = 7) -> BatHeistLogic:
	var g := BatHeistLogic.new()
	g.setup(players, SeededRng.new(seed_value), cfg, {}, {})
	g.world = WorldQuery.new()
	for p: int in players:
		g.world.set_transform(p, g.spawn_for(p), g.spawn_yaw_for(p))
	return g


## Puts `a` `dist` metres from `b` (in the middle of the arena), facing them (or away).
func _face(g: BatHeistLogic, a: int, b: int, dist: float, away: bool = false) -> void:
	var c: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	g.world.set_transform(b, c, 0.0)
	var pos: Vector3 = c + Vector3(0, 0, dist)  # b is at -z from a
	var dir: Vector3 = (c - pos).normalized()
	if away:
		dir = -dir
	g.world.set_transform(a, pos, atan2(-dir.x, -dir.z))


func _act(g: BatHeistLogic, p: int, kind: String, hint: int = -1) -> Dictionary:
	var intent: Dictionary = {"type": &"minigame_action", "kind": kind}
	if hint >= 0:
		intent["target"] = hint
	return g.submit(p, intent, 0.0)


func _run(g: BatHeistLogic, seconds: float) -> Array[Dictionary]:
	var seen: Array[Dictionary] = []
	var t: float = 0.0
	while t < seconds - 0.0001:
		g.tick(STEP, 0.0)
		t += STEP
		seen.append_array(g.drain_events())
	return seen


func _of(evs: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	return evs.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## 1 knocks 2 down (face to face, 1 m).
func _knock(g: BatHeistLogic, a: int = 1, b: int = 2) -> void:
	_face(g, a, b, 1.0)
	var res: Dictionary = _act(g, a, "swing")
	assert_true(res["ok"], "swing: %s" % res)
	assert_eq(res["result"], &"hit")


func test_setup_and_announce_from_the_first_tick() -> void:
	var g: BatHeistLogic = _game([1, 2, 3])
	assert_eq(g.id, &"bat_heist")
	for p: int in [1, 2, 3]:
		assert_eq(g.coins[p], BatHeistLogic.START_COINS)
		assert_true(g.arena.has_point(g.spawn_for(p)), "spawn in the vault arena")
	var evs: Array[Dictionary] = _run(g, STEP)
	assert_eq(_of(evs, &"bat_heist_begin").size(), 1, "announced on the first tick")
	var st: Dictionary = g.get_public_state()
	for key: String in ["coins", "down", "immune", "steals", "clock", "room", "alive"]:
		assert_true(st.has(key), "state carries %s for a late stage" % key)
	assert_eq(_of(_run(g, 1.0), &"bat_heist_begin").size(), 0, "only once")


func test_bad_kinds_and_strangers_are_refused() -> void:
	var g: BatHeistLogic = _game([1, 2])
	assert_eq(_act(g, 1, "tag")["error"], &"bad_value")
	assert_eq(_act(g, 9, "swing")["error"], &"unknown_player")
	assert_eq(g.submit(1, {"type": &"minigame_action", "kind": 5}, 0.0)["error"], &"bad_value")


func test_a_hit_knocks_the_target_down() -> void:
	var g: BatHeistLogic = _game([1, 2, 3])
	_knock(g)
	assert_true(g.is_down(2))
	assert_eq(g.pending_knockdowns.size(), 1)
	assert_eq(int(g.pending_knockdowns[0]["player"]), 2)
	assert_eq(g.pending_knockdowns[0]["cause"], &"bat")
	assert_eq(int(g.pending_knockdowns[0]["attacker"]), 1)
	assert_almost_eq(float(g.pending_knockdowns[0]["seconds"]), BatHeistLogic.KNOCK_SECONDS, 0.001)
	var evs: Array[Dictionary] = g.drain_events()
	assert_eq(_of(evs, &"bat_heist_swing").size(), 1)
	assert_eq(_of(evs, &"bat_heist_hit").size(), 1)


func test_a_miss_is_allowed_and_costs_the_cooldown() -> void:
	var g: BatHeistLogic = _game([1, 2])
	_face(g, 1, 2, 1.0, true)  # facing away
	var res: Dictionary = _act(g, 1, "swing", 2)
	assert_true(res["ok"], "a swing at the air is fine")
	assert_eq(res["result"], &"miss")
	assert_false(g.is_down(2))
	# Turning round right away: still on cooldown.
	_face(g, 1, 2, 1.0)
	assert_eq(_act(g, 1, "swing")["error"], &"cooldown")
	_run(g, BatHeistLogic.SWING_COOLDOWN - 0.2)
	assert_eq(_act(g, 1, "swing")["error"], &"cooldown", "1.2 s between swings")
	_run(g, 0.25)
	assert_eq(_act(g, 1, "swing")["result"], &"hit")


func test_out_of_reach_is_a_miss() -> void:
	var g: BatHeistLogic = _game([1, 2])
	_face(g, 1, 2, BatHeistLogic.BAT_REACH + 1.0)
	assert_eq(_act(g, 1, "swing", 2)["result"], &"miss", "the client's hint doesn't stretch the bat")


func test_steal_moves_one_coin_per_interval_while_down_and_in_reach() -> void:
	var g: BatHeistLogic = _game([1, 2, 3])
	_knock(g)
	assert_true(_act(g, 1, "steal", 2)["ok"])
	_run(g, BatHeistLogic.STEAL_INTERVAL - 0.1)
	assert_eq(g.coins[1], 10, "no coin before the first 0.4 s")
	_run(g, 0.15)
	assert_eq(g.coins[1], 11)
	assert_eq(g.coins[2], 9)
	_run(g, 0.8)
	assert_eq(g.coins[1], 13, "one more per 0.4 s")
	assert_eq(g.coins[2], 7)
	# Step away: the hold pauses.
	g.world.set_transform(1, g.world.get_position(2) + Vector3(0, 0, 4.0), 0.0)
	_run(g, 0.8)
	assert_eq(g.coins[1], 13, "out of reach: nothing")
	g.world.set_transform(1, g.world.get_position(2) + Vector3(0, 0, 1.0), 0.0)
	_run(g, 0.4)
	assert_eq(g.coins[1], 14, "back over the body: it goes on")
	# She gets up (3 s after the hit): the steal ends by itself.
	var evs: Array[Dictionary] = _run(g, BatHeistLogic.KNOCK_SECONDS)
	assert_false(g.is_down(2))
	assert_eq(_of(evs, &"bat_heist_steal_end").size(), 1)
	assert_true(g.steals.is_empty())
	var total: int = 0
	for p: int in g.coins:
		total += g.coins[p]
	assert_eq(total, 30, "coins only move between players")


func test_no_steal_from_a_standing_bean_or_out_of_reach() -> void:
	var g: BatHeistLogic = _game([1, 2, 3])
	_face(g, 1, 2, 1.0)
	assert_eq(_act(g, 1, "steal", 2)["error"], &"no_target", "standing beans keep their coins")
	_knock(g)
	g.world.set_transform(3, g.world.get_position(2) + Vector3(5, 0, 0), 0.0)
	assert_eq(_act(g, 3, "steal", 2)["error"], &"no_target", "too far")


func test_steal_stop_and_a_downed_thief_end_the_steal() -> void:
	var g: BatHeistLogic = _game([1, 2, 3])
	_knock(g)
	assert_true(_act(g, 1, "steal")["ok"], "no hint: the nearest downed bean")
	assert_true(_act(g, 1, "steal_stop")["ok"])
	_run(g, 1.0)
	assert_eq(g.coins[1], 10, "released: nothing taken")
	assert_true(_act(g, 1, "steal", 2)["ok"])
	# Player 3 bonks the thief mid-steal.
	g.world.set_transform(3, g.world.get_position(1) + Vector3(0, 0, 1.0), 0.0)
	assert_eq(_act(g, 3, "swing", 1)["result"], &"hit")
	_run(g, 1.0)
	assert_eq(g.coins[1], 10, "a downed thief steals nothing")
	assert_false(g.steals.has(1))
	assert_eq(_act(g, 1, "swing")["error"], &"down", "no swinging from the floor")


func test_coins_never_go_below_zero() -> void:
	var g: BatHeistLogic = _game([1, 2, 3])
	g.coins[2] = 2
	_knock(g)
	_act(g, 1, "steal", 2)
	g.world.set_transform(3, g.world.get_position(2) + Vector3(1, 0, 0), 0.0)
	_act(g, 3, "steal", 2)
	_run(g, 2.5)
	assert_eq(g.coins[2], 0)
	assert_eq(g.coins[1] + g.coins[3], 22, "only the 2 coins moved")


func test_immunity_after_getting_up() -> void:
	var g: BatHeistLogic = _game([1, 2])
	_knock(g)
	var evs: Array[Dictionary] = _run(g, BatHeistLogic.KNOCK_SECONDS + 0.1)
	assert_false(g.is_down(2))
	assert_true(g.is_immune(2))
	assert_eq(_of(evs, &"bat_heist_up").size(), 1)
	assert_true(g.get_public_state()["immune"].has(2), "the state shows it")
	_face(g, 1, 2, 1.0)
	var res: Dictionary = _act(g, 1, "swing", 2)
	assert_true(res["ok"])
	assert_eq(res["result"], &"immune", "the bat bounces off")
	assert_false(g.is_down(2))
	assert_eq(_act(g, 1, "steal", 2)["error"], &"no_target")
	_run(g, BatHeistLogic.IMMUNE_SECONDS)
	assert_false(g.is_immune(2))
	assert_eq(_act(g, 1, "swing", 2)["result"], &"hit", "fair game again")


func test_the_room_getting_up_late_restarts_the_immunity() -> void:
	var g: BatHeistLogic = _game([1, 2])
	_knock(g)
	_run(g, BatHeistLogic.KNOCK_SECONDS + 0.1)
	_run(g, 1.0)
	g.on_player_got_up(2)  # the ragdoll only stood up now
	_run(g, BatHeistLogic.IMMUNE_SECONDS - 0.2)
	assert_true(g.is_immune(2), "counted from the real get-up")
	# And a get-up before the logic's own timer ends the down early.
	_run(g, 0.5)
	_face(g, 1, 2, 1.0)
	_run(g, BatHeistLogic.SWING_COOLDOWN)
	assert_eq(_act(g, 1, "swing", 2)["result"], &"hit")
	g.on_player_got_up(2)
	assert_false(g.is_down(2))
	assert_true(g.is_immune(2))


func test_the_game_ends_after_60_s_with_the_ranking() -> void:
	var g: BatHeistLogic = _game([1, 2, 3])
	g.coins[1] = 14
	g.coins[2] = 8
	g.coins[3] = 8
	var evs: Array[Dictionary] = _run(g, BatHeistLogic.GAME_SECONDS - 0.5)
	assert_eq(g.state, BatHeistLogic.State.PLAYING)
	evs = _run(g, 0.6)
	assert_eq(g.state, BatHeistLogic.State.DONE)
	assert_eq(_of(evs, &"bat_heist_over").size(), 1)
	assert_eq(_act(g, 1, "swing")["error"], &"game_over")
	assert_false(g.is_finished(), "the scores stay up a moment")
	evs = _run(g, BatHeistLogic.END_HOLD + 0.1)
	assert_true(g.is_finished())
	assert_eq(_of(evs, &"bat_heist_finished").size(), 1)
	var r: Array[Dictionary] = g.ranking()
	assert_eq(r.size(), 3)
	assert_eq(int(r[0]["player"]), 1)
	assert_eq(int(r[0]["rank"]), 1)
	assert_eq(int(r[0]["points"]), 14)
	assert_eq(int(r[1]["rank"]), 2, "a tie shares the rank")
	assert_eq(int(r[2]["rank"]), 2)


func test_everyone_tied_shares_first() -> void:
	var g: BatHeistLogic = _game([1, 2, 3, 4])
	for row: Dictionary in g.ranking():
		assert_eq(int(row["rank"]), 1)
		assert_eq(int(row["points"]), 10)


func test_a_dropout_leaves_the_ranking_and_ends_its_steals() -> void:
	var g: BatHeistLogic = _game([1, 2, 3])
	_knock(g)
	_act(g, 1, "steal", 2)
	g.remove_player(2)
	assert_true(g.steals.is_empty(), "the victim left: the steal ends")
	assert_false(2 in g.players)
	assert_false(g.coins.has(2))
	for row: Dictionary in g.ranking():
		assert_ne(int(row["player"]), 2)
	assert_eq(g.state, BatHeistLogic.State.PLAYING, "two left: still on")
	g.remove_player(3)
	assert_eq(g.state, BatHeistLogic.State.DONE, "alone: over")
	assert_eq(g.ranking().size(), 1)


func test_two_player_game() -> void:
	var g: BatHeistLogic = _game([1, 2])
	_run(g, 1.0)
	_knock(g)
	_act(g, 1, "steal", 2)
	_run(g, 2.0)
	assert_eq(g.coins[1], 15)
	assert_eq(g.coins[2], 5)
	_run(g, BatHeistLogic.GAME_SECONDS)
	_run(g, BatHeistLogic.END_HOLD + 0.1)
	assert_true(g.is_finished())
	var r: Array[Dictionary] = g.ranking()
	assert_eq(int(r[0]["player"]), 1)
	assert_eq(int(r[0]["rank"]), 1)
	assert_eq(int(r[1]["rank"]), 2)
