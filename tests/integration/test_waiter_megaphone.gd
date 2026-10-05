extends GutTest
## Waiter NPC and Megaphone on the server (M7): trips are server decisions (on his own, bumped,
## shoved), the puddle he leaves knocks players down without touching money and dries up; the
## Megaphone is an E-intent at the stand, held for 10 s, and the snapshot/client mirror carry both.

var fx: ServerFixture
var a: int
var b: int
var w: WaiterLogic

const WAITER_POS: Vector3 = Vector3(0, 0, -10)


func before_each() -> void:
	fx = ServerFixture.new(2, {"duration": 5, "seed": 4})
	fx.server.start_match()
	fx.run(3.1)  # past the intro: casino
	a = fx.player_ids[0]
	b = fx.player_ids[1]
	fx.server.world.set_transform(a, Vector3(10, 0, 10), 0.0)
	fx.server.world.set_transform(b, Vector3(-10, 0, 10), 0.0)
	w = fx.server.waiter
	w.position = WAITER_POS
	w.yaw = 0.0  # facing −z


func after_each() -> void:
	fx.server.free()


func _money() -> Dictionary:
	return {a: fx.server.economy.balance(a), b: fx.server.economy.balance(b)}


func _trip_by_shove() -> Dictionary:
	fx.server.world.set_transform(a, WAITER_POS + Vector3(0, 0, 1.6), 0.0)
	var res: Dictionary = fx.intent(a, &"shove", {"aim": Serializer.vec3(Vector3(0, 0, -1))})
	assert_true(res["ok"], "a shove with nobody in front still lands on the waiter")
	var trips: Array[Dictionary] = fx.of_type(&"waiter_tripped")
	assert_eq(trips.size(), 1)
	fx.server.world.set_transform(a, Vector3(10, 0, 10), 0.0)
	return trips[0]


func test_no_body_no_trips() -> void:
	w.position = Vector3.INF
	fx.run(120.0)
	assert_eq(fx.of_type(&"waiter_tripped").size(), 0, "a server without a waiter body never spills")


func test_shove_trips_him_and_a_puddle_appears_ahead() -> void:
	var before: Dictionary = _money()
	var ev: Dictionary = _trip_by_shove()
	assert_eq(StringName(ev["cause"]), &"shove")
	assert_eq(int(ev["player"]), a)
	var pos: Vector3 = Serializer.to_vec3(ev["puddle_pos"])
	assert_almost_eq(pos.z, WAITER_POS.z - WaiterLogic.SPILL_AHEAD, 0.01, "the tray lands ahead of him")
	assert_eq(w.puddles.size(), 1)
	assert_true(w.is_down(fx.server.match_time))
	var snap: Dictionary = fx.server.get_snapshot()
	assert_eq((snap["floor"]["puddles"] as Array).size(), 1, "late joiners get the puddle in the snapshot")
	assert_eq(_money(), before, "tripping the waiter costs nobody anything")


func test_shove_away_from_him_does_nothing() -> void:
	fx.server.world.set_transform(a, WAITER_POS + Vector3(0, 0, 1.6), 0.0)
	var res: Dictionary = fx.intent(a, &"shove", {"aim": Serializer.vec3(Vector3(0, 0, 1))})
	assert_false(res["ok"])
	assert_eq(fx.of_type(&"waiter_tripped").size(), 0)


func test_bumping_into_him_trips_him() -> void:
	fx.server.world.set_transform(b, WAITER_POS + Vector3(0.5, 0, 0.3), 0.0)
	fx.run(0.2)
	var trips: Array[Dictionary] = fx.of_type(&"waiter_tripped")
	assert_eq(trips.size(), 1)
	assert_eq(StringName(trips[0]["cause"]), &"bump")
	assert_eq(int(trips[0]["player"]), b)
	fx.run(1.0)
	assert_eq(fx.of_type(&"waiter_tripped").size(), 1, "no chain-tripping while he is down or recovering")


func test_he_trips_on_his_own_now_and_then() -> void:
	fx.run(150.0)
	assert_gt(fx.of_type(&"waiter_tripped").size(), 0, "clumsy trips happen over a few minutes")
	for ev: Dictionary in fx.of_type(&"waiter_tripped"):
		assert_eq(StringName(ev["cause"]), &"clumsy")


func test_puddle_slips_a_player_without_touching_money() -> void:
	var ev: Dictionary = _trip_by_shove()
	var before: Dictionary = _money()
	var ledger: int = fx.server.economy.ledger.total()
	fx.events.clear()
	fx.server.world.set_transform(b, Serializer.to_vec3(ev["puddle_pos"]) + Vector3(0.3, 0, 0), 0.0)
	fx.run(0.2)
	var slips: Array[Dictionary] = fx.of_type(&"puddle_slip")
	assert_eq(slips.size(), 1)
	assert_eq(int(slips[0]["player"]), b)
	var downs: Array[Dictionary] = fx.of_type(&"player_knocked_down")
	assert_eq(downs.size(), 1)
	assert_eq(StringName(downs[0]["cause"]), &"puddle")
	assert_true(fx.server.rules.is_knocked_down(b, fx.server.match_time), "slipped: on the floor")
	assert_eq(fx.of_type(&"chips_dropped").size(), 0, "unlike a banana, a puddle drops no chips")
	assert_eq(_money(), before)
	assert_eq(fx.server.economy.ledger.total(), ledger)
	# Still standing in it after getting up: a short grace, then it gets them again.
	fx.run(WaiterLogic.SLIP_SECONDS + 0.2)
	assert_eq(fx.of_type(&"puddle_slip").size(), 1, "grace after getting up")
	fx.run(WaiterLogic.SLIP_GRACE + 0.2)
	assert_eq(fx.of_type(&"puddle_slip").size(), 2, "the puddle stays slippery for a while")
	assert_eq(_money(), before)


func test_seated_and_far_players_dont_slip() -> void:
	var ev: Dictionary = _trip_by_shove()
	fx.events.clear()
	fx.server.rules.status(b).seated = true
	fx.server.world.set_transform(b, Serializer.to_vec3(ev["puddle_pos"]), 0.0)
	fx.run(0.5)
	assert_eq(fx.of_type(&"puddle_slip").size(), 0)


func test_puddle_dries_up() -> void:
	var ev: Dictionary = _trip_by_shove()
	fx.run(WaiterLogic.PUDDLE_SECONDS + 0.2)
	var removed: Array[Dictionary] = fx.of_type(&"puddle_removed")
	assert_eq(removed.size(), 1)
	assert_eq(StringName(removed[0]["reason"]), &"dried")
	assert_true(w.puddles.is_empty())
	fx.events.clear()
	fx.server.world.set_transform(b, Serializer.to_vec3(ev["puddle_pos"]), 0.0)
	fx.run(0.5)
	assert_eq(fx.of_type(&"puddle_slip").size(), 0, "dry floor")


func test_client_mirror_tracks_puddles_and_megaphone() -> void:
	var st := ClientMatchState.new()
	st.apply_snapshot(fx.server.get_snapshot())
	_trip_by_shove()
	fx.server.world.set_transform(a, MegaphoneLogic.STAND_POS, 0.0)
	assert_true(fx.intent(a, &"megaphone")["ok"])
	for ev: Dictionary in fx.events:
		st.apply_event(ev)
	assert_eq(st.puddles.size(), 1)
	assert_eq(st.megaphone_holder, a)
	var st2 := ClientMatchState.new()
	st2.apply_snapshot(fx.server.get_snapshot())
	assert_eq(st2.puddles.size(), 1, "snapshot")
	assert_eq(st2.megaphone_holder, a, "snapshot")
	fx.events.clear()
	fx.run(WaiterLogic.PUDDLE_SECONDS + 0.5)
	for ev: Dictionary in fx.events:
		st.apply_event(ev)
	assert_true(st.puddles.is_empty())
	assert_eq(st.megaphone_holder, -1)


func test_megaphone_pickup_rules() -> void:
	var res: Dictionary = fx.intent(a, &"megaphone")
	assert_false(res["ok"])
	assert_eq(res["error"], &"too_far")
	fx.server.world.set_transform(a, MegaphoneLogic.STAND_POS + Vector3(1, 0, 0), 0.0)
	fx.server.world.set_transform(b, MegaphoneLogic.STAND_POS + Vector3(-1, 0, 0), 0.0)
	var before: Dictionary = _money()
	assert_true(fx.intent(a, &"megaphone")["ok"])
	assert_true(fx.server.megaphone.is_holder(a))
	assert_eq(fx.intent(b, &"megaphone")["error"], &"megaphone_taken")
	fx.run(MegaphoneLogic.SECONDS + 0.1)
	assert_false(fx.server.megaphone.is_holder(a), "10 s, then back on the stand")
	assert_eq(fx.of_type(&"megaphone_dropped").size(), 1)
	assert_eq(fx.intent(b, &"megaphone")["error"], &"megaphone_cooldown")
	fx.run(MegaphoneLogic.COOLDOWN)
	assert_true(fx.intent(b, &"megaphone")["ok"])
	assert_eq(_money(), before)


func test_megaphone_only_on_the_casino_floor() -> void:
	fx.server.world.set_transform(a, MegaphoneLogic.STAND_POS, 0.0)
	fx.server.phases.phase = Phase.Id.MINIGAME
	assert_eq(fx.intent(a, &"megaphone")["error"], &"wrong_phase")
