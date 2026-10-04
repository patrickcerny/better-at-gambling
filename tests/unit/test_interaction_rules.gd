extends GutTest

var cfg: BalanceConfig
var r: InteractionRules


func before_each() -> void:
	cfg = BalanceConfig.new()
	r = InteractionRules.new(cfg)


func test_single_shove_only_pushes() -> void:
	var res: Dictionary = r.shove(1, 2, 0.0)
	assert_true(res["ok"])
	assert_false(res["knockdown"])
	assert_false(res["knockout"])


func test_shove_cooldown() -> void:
	r.shove(1, 2, 0.0)
	assert_eq(r.shove(1, 2, 1.0)["error"], &"cooldown")
	assert_true(r.shove(1, 2, 1.2)["ok"])


func test_second_hit_within_window_knocks_down() -> void:
	r.shove(1, 2, 0.0)
	var res: Dictionary = r.shove(3, 2, 1.0)
	assert_true(res["knockdown"])
	assert_true(r.is_knocked_down(2, 1.5))
	assert_false(r.is_knocked_down(2, 2.6))


func test_second_hit_outside_window_does_not() -> void:
	r.shove(1, 2, 0.0)
	assert_false(r.shove(1, 2, 1.6)["knockdown"])


func test_airborne_shove_knocks_down() -> void:
	assert_true(r.shove(1, 2, 0.0, true)["knockdown"])


func test_three_shoves_in_four_seconds_knock_out() -> void:
	r.shove(1, 2, 0.0)
	r.shove(1, 2, 2.0)
	var res: Dictionary = r.shove(1, 2, 3.9)
	assert_true(res["knockout"])
	assert_true(r.is_knocked_out(2, 4.0))
	assert_false(r.is_knocked_out(2, 6.5))


func test_three_shoves_spread_out_do_not_knock_out() -> void:
	r.shove(1, 2, 0.0)
	r.shove(1, 2, 2.0)
	assert_false(r.shove(1, 2, 4.1)["knockout"])


func test_knockout_immunity_after_waking() -> void:
	assert_true(r.knock_out(2, 0.0))
	assert_false(r.knock_out(2, 3.0), "immune 4 s after waking at 2.5")
	assert_false(r.knock_out(2, 6.4))
	assert_true(r.knock_out(2, 6.5))


func test_seated_away_and_spawn_protection() -> void:
	r.status(2).seated = true
	assert_eq(r.shove(1, 2, 0.0)["error"], &"seated")
	assert_eq(r.immunity_reason(2, 0.0, true), &"")
	r.status(2).seated = false
	r.status(2).away = true
	assert_eq(r.shove(1, 2, 0.0)["error"], &"away")
	r.status(2).away = false
	r.protect(2, 10.0)
	assert_eq(r.shove(1, 2, 12.9)["error"], &"spawn_protected")
	assert_true(r.shove(1, 2, 13.0)["ok"])


func test_shake_requires_knockout() -> void:
	assert_eq(r.shake(1, 2, 0.0, 1000)["error"], &"not_knocked_out")


func test_shake_amounts_and_cap_8_percent() -> void:
	r.knock_out(2, 0.0, 1000)
	var total: int = 0
	var shakes: int = 0
	while true:
		var res: Dictionary = r.shake(1, 2, 0.5, 1000 - total)
		if not res["ok"]:
			assert_eq(res["error"], &"cap_reached")
			break
		total += int(res["amount"])
		shakes += 1
	assert_eq(total, 80)  # 8% of $1,000
	assert_eq(shakes, 5)  # 2% of the shrinking balance: 20, 19, 19, 18, then the last 4


func test_shake_cap_400_times_multiplier() -> void:
	r.knock_out(2, 0.0, 100000, 1.5)
	var total: int = 0
	for i: int in 100:
		var res: Dictionary = r.shake(1, 2, 0.5, 100000 - total, 1.5)
		if not res["ok"]:
			break
		total += int(res["amount"])
	assert_eq(total, 600)


func test_shake_minimum_10_and_never_more_than_money() -> void:
	r.knock_out(2, 0.0)
	assert_eq(r.shake(1, 2, 0.1, 5)["amount"], 0, "cap 8% of $5 rounds to 0")
	var r2 := InteractionRules.new(cfg)
	r2.knock_out(2, 0.0, 300)
	assert_eq(r2.shake(1, 2, 0.1, 300)["amount"], 10)


func test_same_attacker_cannot_shake_again_within_20s() -> void:
	r.knock_out(2, 0.0, 1000)
	assert_true(r.shake(1, 2, 0.5, 1000)["ok"])
	r.knock_out(2, 10.0, 1000)
	assert_eq(r.shake(1, 2, 10.5, 1000)["error"], &"same_attacker_cooldown")
	assert_true(r.shake(3, 2, 10.5, 1000)["ok"])
	r.knock_out(2, 21.0, 1000)
	assert_true(r.shake(1, 2, 21.5, 1000)["ok"])


func test_guard_sight() -> void:
	var g: Vector3 = Vector3.ZERO
	var fwd: Vector3 = Vector3(0, 0, -1)
	assert_true(r.guard_sees(g, fwd, Vector3(0, 0, -5), true))
	assert_false(r.guard_sees(g, fwd, Vector3(0, 0, -5), false), "blocked line of sight")
	assert_false(r.guard_sees(g, fwd, Vector3(0, 0, -9), true), "out of range")
	assert_false(r.guard_sees(g, fwd, Vector3(0, 0, 5), true), "behind")
	assert_true(r.guard_sees(g, fwd, Vector3(3, 0, -3), true), "45 degrees")
	assert_false(r.guard_sees(g, fwd, Vector3(5, 0, -1), true), "outside 60 degree cone")
