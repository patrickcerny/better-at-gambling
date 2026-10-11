extends GutTest
## Bat Heist (MINIGAME_IDEAS #10): everyone starts with 10 coins, a bat swing (1.2 s cooldown, a
## miss is fine) knocks the bean in front down, so does the casino's throw; every steal click over
## a downed bean in reach takes 1 coin (at most 6 per second), 3 s of immunity after getting up,
## 60 s, most coins wins with shared ranks. The vault is bigger than Pass the Bomb's.

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
	for key: String in ["coins", "down", "immune", "clock", "room", "alive"]:
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


## Clicks `n` steals of `p` on `hint`; returns how many came back ok.
func _clicks(g: BatHeistLogic, p: int, n: int, hint: int = -1) -> int:
	var ok: int = 0
	for i: int in n:
		if _act(g, p, "steal", hint)["ok"]:
			ok += 1
	return ok


func test_every_steal_click_takes_one_coin_while_down_and_in_reach() -> void:
	var g: BatHeistLogic = _game([1, 2, 3])
	_knock(g)
	g.drain_events()
	var res: Dictionary = _act(g, 1, "steal", 2)
	assert_true(res["ok"])
	assert_eq(int(res["target"]), 2)
	assert_eq(int(res["stolen"]), 1)
	assert_eq(g.coins[1], 11, "one click, one coin")
	assert_eq(g.coins[2], 9)
	assert_eq(_of(g.drain_events(), &"bat_heist_stole").size(), 1, "every coin is an event (coin pop + cha-ching)")
	_run(g, 0.3)
	assert_eq(g.coins[1], 11, "holding does nothing: it's the clicks")
	assert_eq(_clicks(g, 1, 2, 2), 2)
	assert_eq(g.coins[1], 13)
	# Step away: clicks find nobody.
	g.world.set_transform(1, g.world.get_position(2) + Vector3(0, 0, 4.0), 0.0)
	assert_eq(_act(g, 1, "steal", 2)["error"], &"no_target", "out of reach: nothing")
	g.world.set_transform(1, g.world.get_position(2) + Vector3(0, 0, 1.0), 0.0)
	_run(g, 1.0)
	assert_eq(_clicks(g, 1, 1), 1, "back over the body (no hint: the nearest downed bean)")
	assert_eq(g.coins[1], 14)
	# She gets up (3 s after the hit): no more coins.
	_run(g, BatHeistLogic.KNOCK_SECONDS)
	assert_false(g.is_down(2))
	assert_eq(_act(g, 1, "steal", 2)["error"], &"no_target")
	var total: int = 0
	for p: int in g.coins:
		total += g.coins[p]
	assert_eq(total, 30, "coins only move between players")


func test_steal_clicks_are_rate_limited_to_6_per_second() -> void:
	var g: BatHeistLogic = _game([1, 2])
	_knock(g)
	assert_eq(_clicks(g, 1, 10, 2), BatHeistLogic.STEAL_RATE, "a burst: 6 land")
	assert_eq(_act(g, 1, "steal", 2)["error"], &"too_fast")
	assert_eq(g.coins[1], 16)
	_run(g, 0.5)
	assert_eq(_act(g, 1, "steal", 2)["error"], &"too_fast", "still inside the second")
	_run(g, 0.55)
	assert_eq(_clicks(g, 1, 10, 2), BatHeistLogic.STEAL_RATE, "a second later: 6 more")
	assert_eq(g.coins[1], 20)
	assert_eq(g.coins[2], 0)
	# Steady clicking at 6/s keeps going (here: on another bean's coins).
	var h: BatHeistLogic = _game([1, 2])
	_knock(h)
	var took: int = 0
	for i: int in 13:  # one click per 0.2 s for 2.6 s (the down lasts 3 s)
		var r: Dictionary = _act(h, 1, "steal", 2)
		assert_true(r["ok"], "paced click %d lands" % i)
		took += int(r.get("stolen", 0))
		_run(h, 0.2)
	assert_eq(took, 10, "her 10 coins, then nothing left")


func test_no_steal_from_a_standing_bean_or_out_of_reach() -> void:
	var g: BatHeistLogic = _game([1, 2, 3])
	_face(g, 1, 2, 1.0)
	assert_eq(_act(g, 1, "steal", 2)["error"], &"no_target", "standing beans keep their coins")
	_knock(g)
	g.world.set_transform(3, g.world.get_position(2) + Vector3(5, 0, 0), 0.0)
	assert_eq(_act(g, 3, "steal", 2)["error"], &"no_target", "too far")


func test_a_downed_thief_steals_nothing() -> void:
	var g: BatHeistLogic = _game([1, 2, 3])
	_knock(g)
	# Player 3 bonks the thief.
	g.world.set_transform(3, g.world.get_position(1) + Vector3(0, 0, 1.0), 0.0)
	assert_eq(_act(g, 3, "swing", 1)["result"], &"hit")
	assert_eq(_act(g, 1, "steal", 2)["error"], &"down")
	assert_eq(g.coins[1], 10, "a downed thief steals nothing")
	assert_eq(_act(g, 1, "swing")["error"], &"down", "no swinging from the floor")


func test_a_throw_knocks_down_like_a_hit() -> void:
	var g: BatHeistLogic = _game([1, 2, 3])
	g.on_thrown(2, 1)
	assert_true(g.is_down(2))
	assert_eq(g.pending_knockdowns.size(), 1)
	assert_eq(g.pending_knockdowns[0]["cause"], &"throw")
	assert_eq(int(g.pending_knockdowns[0]["attacker"]), 1)
	assert_almost_eq(float(g.pending_knockdowns[0]["seconds"]), BatHeistLogic.THROWN_SECONDS, 0.001)
	assert_eq(_of(g.drain_events(), &"bat_heist_hit").size(), 1, "the feed counts it as a hit")
	assert_eq(g.hits[1], 1)
	_face(g, 1, 2, 1.0)
	assert_eq(_clicks(g, 1, 3, 2), 3, "a thrown bean is robbed like a bonked one")
	assert_eq(g.coins[1], 13)
	# Getting up gives the immunity; an immune bean thrown again stays up.
	g.on_player_got_up(2)
	assert_true(g.is_immune(2))
	g.pending_knockdowns.clear()
	g.on_thrown(2, 3)
	assert_false(g.is_down(2))
	assert_true(g.pending_knockdowns.is_empty())


func test_grab_and_throw_are_allowed_and_only_immune_beans_are_untouchable() -> void:
	var g: BatHeistLogic = _game([1, 2])
	for t: StringName in [&"grab", &"release", &"shove"]:
		assert_false(g.blocks_intent(t), "%s works in Bat Heist" % t)
	assert_true(g.blocks_intent(&"shake"), "no shaking real chips out of a bean here")
	assert_true(g.blocks_intent(&"use_item"))
	assert_false(g.is_untouchable(2))
	_knock(g)
	_run(g, BatHeistLogic.KNOCK_SECONDS + 0.1)
	assert_true(g.is_untouchable(2), "immune after getting up: no grab")
	_run(g, BatHeistLogic.IMMUNE_SECONDS)
	assert_false(g.is_untouchable(2))


func test_the_vault_is_half_again_as_big_as_pass_the_bombs() -> void:
	var g: BatHeistLogic = _game([1, 2])
	var small: AABB = VaultArena.layout()["arena"]
	var ratio: float = (g.arena.size.x * g.arena.size.z) / (small.size.x * small.size.z)
	assert_between(ratio, 1.4, 1.6, "about 1.5× the floor")
	var far: float = 0.0
	for p: int in [1, 2]:
		far = maxf(far, (g.spawn_for(p) - WalkableLogicBase.ROOM_ORIGIN).length())
	assert_gt(far, VaultArena.SPAWN_RADIUS + 0.5, "the spawn ring spreads with it")


func test_coins_never_go_below_zero() -> void:
	var g: BatHeistLogic = _game([1, 2, 3])
	g.coins[2] = 2
	_knock(g)
	assert_eq(_clicks(g, 1, 2, 2), 2)
	g.world.set_transform(3, g.world.get_position(2) + Vector3(1, 0, 0), 0.0)
	var res: Dictionary = _act(g, 3, "steal", 2)
	assert_true(res["ok"])
	assert_eq(int(res["stolen"]), 0, "nothing left")
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


func test_a_dropout_leaves_the_ranking() -> void:
	var g: BatHeistLogic = _game([1, 2, 3])
	_knock(g)
	_act(g, 1, "steal", 2)
	g.remove_player(2)
	assert_eq(_act(g, 1, "steal", 2)["error"], &"no_target", "the victim left")
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
	_clicks(g, 1, 5, 2)
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
