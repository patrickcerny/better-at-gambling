extends GutTest
## BetClamp, the all-in rule the server and the bet UIs share (Patrick: "when you try to bet more
## than you currently have, just bet the max amount (all you have)").


func test_within_balance_and_limits_is_unchanged() -> void:
	var r: Dictionary = BetClamp.resolve(50, 1000, 10, 200)
	assert_eq(int(r["amount"]), 50)
	assert_eq(r["error"], &"")
	assert_false(bool(r["all_in"]))


func test_over_the_balance_bets_the_balance() -> void:
	var r: Dictionary = BetClamp.resolve(150, 37, 10, 200)
	assert_eq(int(r["amount"]), 37)
	assert_eq(r["error"], &"")
	assert_true(bool(r["all_in"]))


func test_exactly_the_balance_is_not_flagged() -> void:
	var r: Dictionary = BetClamp.resolve(37, 37, 10, 200)
	assert_eq(int(r["amount"]), 37)
	assert_false(bool(r["all_in"]))


func test_over_the_max_bets_the_max() -> void:
	var r: Dictionary = BetClamp.resolve(900, 1000, 10, 200)
	assert_eq(int(r["amount"]), 200)
	assert_false(bool(r["all_in"]), "the table cut it, not the balance")


func test_over_max_and_balance_takes_the_smaller() -> void:
	var r: Dictionary = BetClamp.resolve(900, 120, 10, 200)
	assert_eq(int(r["amount"]), 120)
	assert_true(bool(r["all_in"]))
	assert_eq(BetClamp.clamp_amount(900, 500, 10, 200), 200)


func test_refusals() -> void:
	assert_eq(BetClamp.resolve(5, 1000, 10, 200)["error"], &"below_min")
	assert_eq(BetClamp.resolve(0, 1000, 10, 200)["error"], &"below_min")
	assert_eq(BetClamp.resolve(50, 9, 10, 200)["error"], &"insufficient_funds", "a balance under the minimum is refused")
	assert_eq(BetClamp.resolve(50, 0, 10, 200)["error"], &"insufficient_funds")
	assert_eq(BetClamp.resolve(50, 1000, 10, 9)["error"], &"above_max", "no room left for even a minimum bet")
	assert_eq(BetClamp.clamp_amount(50, 9, 10, 200), 0)


func test_balance_exactly_the_minimum_goes_all_in() -> void:
	var r: Dictionary = BetClamp.resolve(100, 10, 10, 200)
	assert_eq(int(r["amount"]), 10)
	assert_true(bool(r["all_in"]))


func test_fixed_sizes() -> void:
	var sizes: Array[int] = [10, 25, 50, 100]
	assert_eq(BetClamp.size_range(sizes), Vector2i(10, 100))
	assert_eq(BetClamp.size_range([] as Array[int]), Vector2i(-1, -1))
	var r: Dictionary = BetClamp.resolve_sized(100, sizes, 42)
	assert_eq(int(r["amount"]), 42)
	assert_true(bool(r["all_in"]))
	assert_eq(int(BetClamp.resolve_sized(25, sizes, 42)["amount"]), 25)
	assert_eq(BetClamp.resolve_sized(37, sizes, 1000)["error"], &"invalid_amount", "only listed sizes")
	assert_eq(BetClamp.resolve_sized(50, sizes, 9)["error"], &"insufficient_funds")


func test_station_logic_size_allowed() -> void:
	var sizes: Array[int] = [10, 25, 50, 100]
	assert_true(StationLogicBase.size_allowed(25, {}, sizes))
	assert_false(StationLogicBase.size_allowed(37, {}, sizes), "unlisted without the server's all-in")
	assert_true(StationLogicBase.size_allowed(37, {"all_in": true}, sizes))
	assert_false(StationLogicBase.size_allowed(7, {"all_in": true}, sizes), "never under the smallest size")
	assert_false(StationLogicBase.size_allowed(170, {"all_in": true}, sizes), "never over the largest size")
