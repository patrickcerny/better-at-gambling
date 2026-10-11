extends GutTest
## Bat Heist on the authoritative server: a swing decided from the server's own positions knocks
## the target down for real (the room's knockdown), a held steal moves coins, and the server
## telling the room the ragdoll got up starts the immunity.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(3, {"minigames": 1, "gamble_seconds": 20.0, "seed": 9, "minigame_pool": "bat_heist"})
	LuckyLounge.describe_rooms(fx.server.map_def)
	fx.server.map_def.lobby_spawns = LuckyLounge.LOBBY_SPAWNS.duplicate()


func after_each() -> void:
	fx.server.free()


func _to_game() -> BatHeistLogic:
	fx.server.start_match()
	fx.place_all(Vector3(0, 0, -4))
	var t: float = 0.0
	while fx.of_type(&"minigame_started").is_empty() and t < 200.0:
		fx.run(0.5)
		t += 0.5
	assert_eq(fx.of_type(&"minigame_started").size(), 1, "the minigame started")
	var g: BatHeistLogic = fx.server.minigame as BatHeistLogic
	assert_not_null(g, "Bat Heist is running")
	t = 0.0
	while fx.server.in_briefing() and t < 60.0:
		fx.run(0.5)
		t += 0.5
	fx.run(0.1)
	return g


func test_a_swing_knocks_down_and_a_steal_moves_a_coin() -> void:
	var g: BatHeistLogic = _to_game()
	assert_eq(fx.of_type(&"bat_heist_begin").size(), 1, "announced once the game ticks")
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	# The client claims a hit across the room: the server's positions say miss.
	var res: Dictionary = fx.intent(a, &"minigame_action", {"kind": "swing", "target": b})
	assert_true(res["ok"])
	assert_eq(res["result"], &"miss")
	assert_true(fx.of_type(&"player_knocked_down").is_empty())
	fx.run(BatHeistLogic.SWING_COOLDOWN + 0.1)
	# Face to face in reach: a hit, and the room knocks them down for real.
	var at: Vector3 = fx.server.world.get_position(b)
	fx.server.world.set_transform(a, at + Vector3(0, 0, 1.0), 0.0)  # yaw 0 faces -z: towards b
	res = fx.intent(a, &"minigame_action", {"kind": "swing"})
	assert_eq(res["result"], &"hit", "swing: %s" % res)
	fx.run(0.1)
	var down: Array[Dictionary] = fx.of_type(&"player_knocked_down")
	assert_eq(down.size(), 1)
	assert_eq(int(down[0]["target"]), b)
	assert_eq(int(down[0]["attacker"]), a)
	assert_eq(down[0]["cause"], &"bat")
	assert_true(fx.server.rules.is_knocked_down(b, fx.server.match_time), "down on the server")
	assert_false(fx.server.can_move(b), "a downed bean can't walk")
	# Hold the steal over the body.
	res = fx.intent(a, &"minigame_action", {"kind": "steal", "target": b})
	assert_true(res["ok"], "steal: %s" % res)
	fx.run(BatHeistLogic.STEAL_INTERVAL * 2.0 + 0.1)
	assert_eq(g.coins[a], BatHeistLogic.START_COINS + 2)
	assert_eq(g.coins[b], BatHeistLogic.START_COINS - 2)
	assert_eq(fx.of_type(&"bat_heist_stole").size(), 2)
	assert_eq(int(fx.server.get_snapshot()["minigame"]["coins"][a]), BatHeistLogic.START_COINS + 2, "late joiners see the coins")
	fx.intent(a, &"minigame_action", {"kind": "steal_stop"})
	fx.run(1.0)
	assert_eq(g.coins[a], BatHeistLogic.START_COINS + 2, "released: no more coins")
	# The scene reports the ragdoll standing up: immune from now.
	fx.run(BatHeistLogic.KNOCK_SECONDS)
	fx.server.report_got_up(b, fx.server.world.get_position(b))
	assert_true(g.is_immune(b))
	assert_false(g.is_down(b))


func test_the_game_runs_to_the_ranking() -> void:
	var g: BatHeistLogic = _to_game()
	var t: float = 0.0
	while fx.of_type(&"bat_heist_finished").is_empty() and t < 120.0:
		fx.run(0.5)
		t += 0.5
	assert_eq(fx.of_type(&"bat_heist_finished").size(), 1)
	assert_eq(g.ranking().size(), 3)
	for row: Dictionary in g.ranking():
		assert_eq(int(row["rank"]), 1, "nobody stole: everyone shares first")
