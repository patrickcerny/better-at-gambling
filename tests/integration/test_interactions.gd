extends GutTest
## Physical interaction rules through the server: shove ×3 → knockout, throw, shake drops exactly
## the capped amount and chip piles sum to it, seated players immune, guards, pickups.

var fx: ServerFixture
var a: int
var b: int


func before_each() -> void:
	fx = ServerFixture.new(3)
	fx.server.start_match()
	fx.run(3.1)
	a = fx.player_ids[0]
	b = fx.player_ids[1]
	fx.server.world.set_transform(a, Vector3.ZERO, 0.0)  # faces -Z
	fx.server.world.set_transform(b, Vector3(0, 0, -1.5), 0.0)
	fx.server.world.set_transform(fx.player_ids[2], Vector3(20, 0, 20), 0.0)
	fx.run(3.0)  # spawn protection over


func after_each() -> void:
	fx.server.free()


func test_three_shoves_knock_out_and_then_shake_drops_capped_amount() -> void:
	for i: int in 3:
		var r: Dictionary = fx.intent(a, &"shove", {"aim": [0, 0, -1]})
		assert_true(r["ok"], "shove %d: %s" % [i, r])
		fx.run(1.3)
	assert_eq(fx.of_type(&"player_shoved").size(), 3)
	assert_eq(fx.of_type(&"player_knocked_out").size(), 1)
	assert_true(fx.server.rules.is_knocked_out(b, fx.server.match_time))
	var before: int = fx.server.economy.balance(b)
	var total: int = 0
	for i: int in 10:
		var r: Dictionary = fx.intent(a, &"shake")
		if not r["ok"]:
			assert_eq(r["error"], &"cap_reached")
			break
	for ev: Dictionary in fx.of_type(&"chips_shaken_out"):
		total += int(ev["amount"])
	assert_eq(total, int(floor(before * 0.08)))
	assert_eq(fx.server.economy.balance(b), before - total)
	assert_eq(fx.server.pickups.total_on_floor(), total, "chip piles sum to the shaken amount")
	var dropped: int = 0
	for ev: Dictionary in fx.of_type(&"chips_dropped"):
		dropped += int(ev["amount"])
	assert_eq(dropped, total)
	# Anyone (including the victim) can pick them up.
	for pile: int in fx.server.pickups.piles.keys():
		assert_true(fx.server.report_pickup(b, pile))
	assert_eq(fx.server.economy.balance(b), before)
	assert_eq(fx.server.pickups.total_on_floor(), 0)


func test_shove_needs_a_target_in_front() -> void:
	assert_eq(fx.intent(a, &"shove", {"aim": [0, 0, 1]})["error"], &"no_target")
	fx.server.world.set_transform(b, Vector3(0, 0, -5), 0.0)
	assert_eq(fx.intent(a, &"shove", {"aim": [0, 0, -1]})["error"], &"no_target")


func test_seated_player_is_immune() -> void:
	fx.server.world.set_transform(b, Vector3.ZERO, 0.0)
	assert_true(fx.intent(b, &"sit", {"station": &"blackjack_1"})["ok"])
	assert_eq(fx.intent(a, &"shove", {"aim": [0, 0, -1]})["error"], &"seated")
	assert_eq(fx.intent(a, &"grab", {"target": b})["error"], &"seated")


func test_grab_hold_throw_and_break_free() -> void:
	assert_true(fx.intent(a, &"grab", {"target": b})["ok"])
	assert_true(fx.server.interactions.is_held(b))
	assert_eq(fx.intent(b, &"move", {"pos": [5, 0, 5], "yaw": 0})["error"], &"not_standing")
	assert_eq(fx.intent(b, &"shove", {"aim": [0, 0, 1]})["error"], &"not_standing")
	for i: int in 5:
		fx.intent(b, &"break_free")
	assert_true(fx.server.interactions.is_held(b), "5 presses not enough")
	fx.intent(b, &"break_free")
	assert_false(fx.server.interactions.is_held(b))
	assert_eq(fx.of_type(&"player_broke_free").size(), 1)
	fx.run(1.3)
	assert_true(fx.intent(a, &"grab", {"target": b})["ok"])
	assert_true(fx.intent(a, &"release", {"throw": true, "aim": [1, 0, 0]})["ok"])
	var thrown: Array[Dictionary] = fx.of_type(&"player_thrown")
	assert_eq(thrown.size(), 1)
	assert_almost_eq(float(thrown[0]["velocity"][0]), 6.0, 0.01)
	assert_almost_eq(float(thrown[0]["velocity"][1]), 3.0, 0.01)
	# The world reports the landing knockout.
	assert_true(fx.server.report_knockout(b, a, &"wall"))
	assert_false(fx.server.report_knockout(b, a, &"wall"), "already out / immune")


func test_hold_times_out_after_3_seconds() -> void:
	fx.intent(a, &"grab", {"target": b})
	fx.run(3.1)
	assert_false(fx.server.interactions.is_held(b))


func test_guard_offence_tracking_and_throw_out() -> void:
	assert_true(fx.server.report_knockout(b, a, &"stool"))
	var off: Array[Dictionary] = fx.server.interactions.recent_offences(fx.server.match_time)
	assert_eq(off.size(), 1)
	assert_eq(off[0]["attacker"], a)
	var r: InteractionRules = fx.server.rules
	assert_true(r.guard_sees(Vector3(0, 0, 5), Vector3(0, 0, -1), Vector3.ZERO, true), "guard 5 m away looking at the attacker")
	assert_false(r.guard_sees(Vector3(0, 0, 12), Vector3(0, 0, -1), Vector3.ZERO, true), "guard out of range")
	fx.server.report_thrown_out(a, &"guard_1")
	assert_eq(fx.of_type(&"player_thrown_out").size(), 1)
	assert_eq(fx.server.interactions.recent_offences(fx.server.match_time).size(), 0)


func test_pickups_expire_with_reason() -> void:
	fx.server.pickups.spawn(100, Vector3.ZERO, 2, fx.server.rng, fx.server.match_time)
	assert_eq(fx.server.pickups.total_on_floor(), 100)
	fx.run(20.1)
	assert_eq(fx.server.pickups.total_on_floor(), 0)
	var expired: int = 0
	for ev: Dictionary in fx.of_type(&"pickup_expired"):
		expired += int(ev["amount"])
	assert_eq(expired, 100)


# --- Feel pass: reach, lag slack, wall slams, items on seated players ---------------------------

func test_shove_reach_cone_and_the_clients_target_within_lag_slack() -> void:
	fx.server.world.set_transform(b, Vector3(2.0, 0, 0), 0.0)
	assert_eq(fx.intent(a, &"shove", {"aim": [0, 0, -1]})["error"], &"no_target", "90° to the side")
	# The client saw b in reach but b has moved on to 2.6 m: the client's pick still lands.
	fx.server.world.set_transform(b, Vector3(0, 0, -2.6), 0.0)
	assert_eq(fx.intent(a, &"shove", {"aim": [0, 0, -1]})["error"], &"no_target", "without a hint 2.6 m is too far")
	var r: Dictionary = fx.intent(a, &"shove", {"aim": [0, 0, -1], "target": b})
	assert_true(r["ok"], "hinted target within reach + lag slack: %s" % r)
	fx.run(1.3)
	fx.server.world.set_transform(b, Vector3(0, 0, -InteractionRules.REACH - InteractionRules.LAG_SLACK - 0.2), 0.0)
	assert_eq(fx.intent(a, &"shove", {"aim": [0, 0, -1], "target": b})["error"], &"no_target", "but not beyond it")


func test_a_seated_player_in_front_does_not_eat_the_swing() -> void:
	var c: int = fx.player_ids[2]
	fx.server.world.set_transform(b, Vector3(0, 0, -0.9), 0.0)
	assert_true(fx.intent(b, &"sit", {"station": &"blackjack_1"})["ok"])
	fx.server.world.set_transform(c, Vector3(0.3, 0, -1.8), 0.0)
	var r: Dictionary = fx.intent(a, &"shove", {"aim": [0, 0, -1]})
	assert_true(r["ok"], str(r))
	assert_eq(int(r["target"]), c, "the standing player behind gets shoved")
	# Bare hands still can't touch the seated one, hint or not.
	fx.run(1.3)
	fx.server.world.set_transform(c, Vector3(20, 0, 20), 0.0)
	assert_eq(fx.intent(a, &"shove", {"aim": [0, 0, -1], "target": b})["error"], &"seated")
	assert_eq(fx.intent(a, &"grab", {"target": b})["error"], &"seated")


func test_grab_allows_lag_slack_but_not_more() -> void:
	fx.server.world.set_transform(b, Vector3(0, 0, -2.5), 0.0)
	assert_true(fx.intent(a, &"grab", {"target": b})["ok"], "client saw them in reach a moment ago")
	fx.intent(a, &"release", {"throw": false})
	fx.server.world.set_transform(b, Vector3(0, 0, -3.2), 0.0)
	assert_eq(fx.intent(a, &"grab", {"target": b})["error"], &"out_of_range")


func test_shove_into_a_wall_knocks_down_and_a_held_victim_is_released() -> void:
	fx.server.world.obstacle_callback = func(_from: Vector3, _to: Vector3) -> bool: return true
	assert_true(fx.intent(a, &"shove", {"aim": [0, 0, -1]})["ok"])
	var downs: Array[Dictionary] = fx.of_type(&"player_knocked_down")
	assert_eq(downs.size(), 1, "slammed into the wall: down on the first shove")
	assert_eq(downs[0]["cause"], &"wall")
	assert_true(fx.server.rules.is_knocked_down(b, fx.server.match_time))
	fx.server.world.obstacle_callback = Callable()
	fx.run(Registry.balance.knockdown_time + 0.2)
	# Shoving someone out of a third player's arms frees them (and says so).
	var c: int = fx.player_ids[2]
	fx.server.world.set_transform(c, Vector3(0, 0, -2.0), 0.0)
	assert_true(fx.intent(c, &"grab", {"target": b})["ok"])
	fx.run(1.3)
	assert_true(fx.intent(a, &"shove", {"aim": [0, 0, -1], "target": b})["ok"])
	assert_false(fx.server.interactions.is_held(b))
	assert_eq(fx.of_type(&"player_released").size(), 1)


func test_items_knock_a_seated_player_off_their_seat_with_the_bet_settled() -> void:
	var sid: StringName = &"blackjack_1"
	var before: int = fx.server.economy.balance(b)
	# Sitting moves the player onto the seat on the server too (0.8.13): b walks up from 3.5 m away
	# (out of the bat's 2 m), the seat itself is 1.5 m from a, so the swing only lands if the
	# server put b on the seat like the client does.
	fx.server.map_def.station_seats[sid] = [Vector3(0, 0, -1.5), Vector3(0.8, 0, -1.5), Vector3(-0.8, 0, -1.5)]
	fx.server.world.set_transform(a, Vector3.ZERO, 0.0)
	fx.server.world.set_transform(b, Vector3(0, 0, -3.5), 0.0)
	assert_true(fx.intent(b, &"sit", {"station": sid})["ok"])
	assert_almost_eq(fx.server.world.get_position(b).distance_to(Vector3(0, 0, -1.5)), 0.0, 0.01, "on the seat server-side")
	assert_almost_eq(Vector3(fx.server.state.players[b].position).z, -1.5, 0.01)
	assert_true(fx.intent(b, &"place_bet", {"station": sid, "bet": {"amount": 50}})["ok"])
	fx.run(0.5)
	var floor_before: int = fx.server.pickups.total_on_floor()
	fx.server.items.give(a, &"baseball_bat", fx.server.match_time)
	var r: Dictionary = fx.intent(a, &"use_item", {"slot": 0, "target": b})
	assert_true(r["ok"], "the bat reaches people at tables: %s" % r)
	assert_eq(fx.of_type(&"player_stood").size(), 1, "knocked off the seat")
	assert_false(fx.server.stations.is_seated(b))
	assert_false(fx.server.rules.status(b).seated)
	assert_true(fx.server.rules.is_knocked_out(b, fx.server.match_time))
	var spilled: int = fx.server.pickups.total_on_floor() - floor_before
	fx.run(40.0)  # the open hand stays in and plays out (auto-stand), as when anyone stands up
	var net: int = 0
	var stakes: int = 0
	for ev: Dictionary in fx.of_type(&"round_result"):
		if int(ev["player"]) == b:
			net += int(ev["net"])
			stakes += 1
	assert_gt(spilled, 0)
	assert_eq(fx.server.economy.balance(b) + spilled, before + net, "the bet settled like a normal stand-up (%d results); nothing lost to physics" % stakes)
	# The empty bottle works on seated players too; bare hands never do.
	assert_eq(stakes, 1, "one round result for the hand")
	var c: int = fx.player_ids[2]
	fx.server.world.set_transform(c, Vector3(0, 0, -1.2), 0.0)
	assert_true(fx.intent(c, &"sit", {"station": &"blackjack_2"})["ok"])
	assert_eq(fx.intent(a, &"shove", {"aim": [0, 0, -1], "target": c})["error"], &"seated")
	fx.run(Registry.balance.item_cooldown + 0.1)
	fx.server.items.give(a, &"empty_bottle", fx.server.match_time)
	var r2: Dictionary = fx.intent(a, &"use_item", {"slot": 0, "target": c})
	assert_true(r2["ok"], str(r2))
	assert_false(fx.server.stations.is_seated(c))
	assert_true(fx.server.rules.is_knocked_down(c, fx.server.match_time))
