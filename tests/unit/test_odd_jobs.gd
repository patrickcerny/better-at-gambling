extends GutTest
## Odd Jobs cabinet rules (server/odd_jobs.gd): presses per bar by money, $50 per full bar,
## idle decay, refusal and freeze at $500+, the press rate limit.

var economy: Economy
var jobs: OddJobs
var now: float = 0.0


func before_each() -> void:
	economy = Economy.new()
	economy.add_player(1, 0)
	jobs = OddJobs.new(economy)
	now = 0.0


## Presses at a steady 10/s (under the limit).
func _press(n: int) -> void:
	for i: int in n:
		now += 0.1
		assert_true(jobs.press(1, now)["ok"])


func _of(type: StringName) -> Array[Dictionary]:
	return jobs.events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func test_presses_needed_scale_with_money() -> void:
	assert_eq(OddJobs.presses_needed(0), 10)
	assert_eq(OddJobs.presses_needed(-20), 10)
	assert_eq(OddJobs.presses_needed(250), 35)
	assert_eq(OddJobs.presses_needed(499), 60)
	assert_eq(OddJobs.presses_needed(500), 0, "refused")
	assert_true(OddJobs.presses_needed(100) < OddJobs.presses_needed(300))


func test_full_bar_pays_exactly_50_and_resets() -> void:
	_press(9)
	assert_eq(economy.balance(1), 0)
	assert_almost_eq(jobs.fill(1), 0.9, 0.001)
	_press(1)
	assert_eq(economy.balance(1), 50)
	assert_eq(jobs.fill(1), 0.0)
	var pay: Array[Dictionary] = _of(&"odd_jobs_payout")
	assert_eq(pay.size(), 1)
	assert_eq(int(pay[0]["amount"]), 50)
	assert_eq(int(pay[0]["balance"]), 50)
	# At $50 the next bar takes more presses (15).
	assert_eq(int(_of(&"odd_jobs_bar").back()["presses_needed"]), 15)
	_press(14)
	assert_eq(economy.balance(1), 50)
	_press(1)
	assert_eq(economy.balance(1), 100)


func test_bar_decays_when_idle() -> void:
	_press(5)
	var f: float = jobs.fill(1)
	jobs.tick(0.3, now + 0.3)
	assert_eq(jobs.fill(1), f, "no decay right after a press")
	for i: int in 20:
		jobs.tick(0.1, now + 0.4 + i * 0.1)
	assert_lt(jobs.fill(1), f)
	assert_gt(jobs.fill(1), 0.0, "slowly")
	for i: int in 100:
		jobs.tick(0.1, now + 3.0 + i * 0.1)
	assert_eq(jobs.fill(1), 0.0)
	assert_eq(economy.balance(1), 0)


func test_refused_at_500() -> void:
	economy.apply(1, 500, &"test")
	var res: Dictionary = jobs.press(1, 1.0)
	assert_false(res["ok"])
	assert_eq(res["error"], &"enough_money")
	assert_eq(jobs.fill(1), 0.0)
	assert_true(bool(_of(&"odd_jobs_bar").back()["enough"]))
	assert_eq(economy.balance(1), 500)


func test_bar_freezes_when_crossing_500() -> void:
	economy.apply(1, 480, &"test")
	_press(10)
	var f: float = jobs.fill(1)
	assert_gt(f, 0.0)
	economy.apply(1, 30, &"test")  # won something elsewhere: $510
	assert_eq(jobs.press(1, now + 0.1)["error"], &"enough_money")
	for i: int in 50:
		jobs.tick(0.1, now + 1.0 + i * 0.1)
	assert_eq(jobs.fill(1), f, "frozen, not draining")
	assert_eq(economy.balance(1), 510)


func test_rate_limit_drops_extra_presses() -> void:
	# 40 presses in the same instant: only the burst (12) counts, the rest are dropped quietly.
	economy.apply(1, 499, &"test")  # 60 presses a bar: nothing pays out here
	for i: int in 40:
		assert_true(jobs.press(1, 5.0)["ok"])
	assert_almost_eq(jobs.fill(1), 12.0 / 60.0, 0.001)
	# A second later about 12 more are allowed.
	for i: int in 40:
		jobs.press(1, 6.0)
	assert_almost_eq(jobs.fill(1), 24.0 / 60.0, 0.001)


func test_bar_events_are_throttled() -> void:
	economy.apply(1, 499, &"test")
	for i: int in 10:
		jobs.press(1, 1.0 + i * 0.01)  # 10 presses in 0.1 s
	assert_eq(_of(&"odd_jobs_bar").size(), 1)
	jobs.tick(0.05, 1.2)
	assert_eq(_of(&"odd_jobs_bar").size(), 2, "the newest value follows on the next tick")


func test_money_never_goes_negative() -> void:
	_press(45)  # 10 + 15 + 20 presses
	assert_eq(economy.balance(1), 150)
	for i: int in 200:
		jobs.tick(0.1, now + 1.0 + i * 0.1)
	assert_eq(economy.balance(1), 150)
	assert_true(economy.balance(1) >= 0)
	assert_false(jobs.press(99, now)["ok"], "unknown player")
