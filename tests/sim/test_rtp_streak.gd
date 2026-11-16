extends GutTest
## What the losing-streak luck (0.9.57, `BalanceConfig.luck_streak_*`) adds to the tables' return
## for a player betting $100 a round without items: the same seeds with and without it. The lift
## must stay small, so the casino keeps its ~101% feel and a streak is a comeback nudge, not a
## money tap.

## Most the streak may lift a table's return, and the highest return it may reach.
const MAX_LIFT: float = 0.03
const MAX_RTP: float = 1.04


func after_each() -> void:
	SimHelpers.streak = false


func _both(run: Callable) -> Array[float]:
	SimHelpers.streak = false
	var base: float = float((run.call() as Dictionary)["rtp"])
	SimHelpers.streak = true
	var with: float = float((run.call() as Dictionary)["rtp"])
	SimHelpers.streak = false
	return [base, with]


func _check(label: String, r: Array[float], tol: float) -> void:
	gut.p("%s: base %.4f  with streak %.4f  lift %+.4f" % [label, r[0], r[1], r[1] - r[0]])
	assert_true(r[1] - r[0] > -tol, "%s: the streak never hurts (beyond noise)" % label)
	assert_lt(r[1] - r[0], MAX_LIFT + tol, "%s: small lift" % label)
	assert_lt(r[1], MAX_RTP + tol, "%s: stays a casino" % label)


func test_slots() -> void:
	_check("slots", _both(func() -> Dictionary: return SimHelpers.slots(300_000, 0, 5150)), 0.012)


func test_plinko() -> void:
	_check("plinko medium", _both(func() -> Dictionary: return SimHelpers.plinko(300_000, &"medium", 0, 5151)), 0.015)


func test_roulette() -> void:
	_check("roulette red", _both(func() -> Dictionary: return SimHelpers.roulette(300_000, &"red", 0, 0, 5152)), 0.006)
	_check("roulette straight", _both(func() -> Dictionary: return SimHelpers.roulette(300_000, &"straight", 17, 0, 5153)), 0.035)


func test_blackjack() -> void:
	_check("blackjack", _both(func() -> Dictionary: return SimHelpers.blackjack(150_000, 0, 5154)), 0.012)
