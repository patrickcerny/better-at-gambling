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
