extends GutTest
## Odd Jobs cabinet rules (server/odd_jobs.gd): ONE bar shared by every player, each click adds the
## clicker's share (1 / presses needed at their money), the click that fills it is paid $50 and
## the bar starts over; idle decay, refusal at $500+, the per-player rate limit.

var economy: Economy
var jobs: OddJobs
var now: float = 0.0


func before_each() -> void:
	economy = Economy.new()
	economy.add_player(1, 0)
	economy.add_player(2, 0)
	jobs = OddJobs.new(economy)
	now = 0.0


## `player` clicks `n` times at a steady 10/s (under the limit).
func _press(n: int, player: int = 1) -> void:
	for i: int in n:
		now += 0.1
		assert_true(jobs.press(player, now)["ok"])


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
	assert_almost_eq(jobs.fill(), 0.9, 0.001)
	_press(1)
	assert_eq(economy.balance(1), 50)
	assert_eq(jobs.fill(), 0.0)
	var pay: Array[Dictionary] = _of(&"odd_jobs_payout")
	assert_eq(pay.size(), 1)
	assert_eq(int(pay[0]["player"]), 1)
	assert_eq(int(pay[0]["amount"]), 50)
	assert_eq(int(pay[0]["balance"]), 50)
	assert_eq(float(_of(&"odd_jobs_bar").back()["fill"]), 0.0, "the reset goes out at once")
	# At $50 the next bar takes more of this player's clicks (15).
	_press(14)
	assert_eq(economy.balance(1), 50)
	_press(1)
	assert_eq(economy.balance(1), 100)


func test_two_players_share_one_bar_and_the_last_click_wins() -> void:
	economy.apply(2, 250, &"test")  # 35 clicks a bar for player 2, 10 for player 1
	_press(5, 1)
	assert_almost_eq(jobs.fill(), 0.5, 0.001)
	_press(1, 2)
	assert_almost_eq(jobs.fill(), 0.5 + 1.0 / 35.0, 0.001, "player 2 adds their own (smaller) share")
	jobs.tick(0.05, now + 0.15)  # flush the throttled update
	assert_eq(int(_of(&"odd_jobs_bar").back()["player"]), 2, "bar events say who clicked")
	_press(4, 1)  # 0.5 + 0.029 + 0.4 = 0.929: not full yet
	assert_eq(economy.balance(1), 0)
	_press(3, 2)  # +0.086: player 2's click completes it
	assert_eq(economy.balance(2), 300, "the completing click is paid")
	assert_eq(economy.balance(1), 0, "the others' clicks earn nothing")
	assert_eq(jobs.fill(), 0.0, "and the bar starts over")
	var pay: Array[Dictionary] = _of(&"odd_jobs_payout")
	assert_eq(pay.size(), 1)
	assert_eq(int(pay[0]["player"]), 2)
	assert_eq(int(pay[0]["balance"]), 300)


func test_bar_decays_when_idle() -> void:
	_press(5)
	var f: float = jobs.fill()
	jobs.tick(0.3, now + 0.3)
	assert_eq(jobs.fill(), f, "no decay right after a press")
	for i: int in 20:
		jobs.tick(0.1, now + 0.4 + i * 0.1)
	assert_lt(jobs.fill(), f)
	assert_gt(jobs.fill(), 0.0, "slowly")
	assert_eq(int(_of(&"odd_jobs_bar").back()["player"]), -1, "a drain update has no clicker")
	for i: int in 100:
		jobs.tick(0.1, now + 3.0 + i * 0.1)
	assert_eq(jobs.fill(), 0.0)
	assert_eq(economy.balance(1), 0)


func test_anyones_click_holds_off_the_decay() -> void:
	_press(5, 1)
	var f: float = jobs.fill()
	jobs.tick(0.1, now + 0.4)
	now += 0.4
	_press(1, 2)  # player 2 keeps it going: no drain in between
	assert_almost_eq(jobs.fill(), f + 0.1, 0.001)


func test_refused_at_500() -> void:
	economy.apply(1, 500, &"test")
	_press(3, 2)
	var f: float = jobs.fill()
	var res: Dictionary = jobs.press(1, now + 0.1)
	assert_false(res["ok"])
	assert_eq(res["error"], &"enough_money")
	assert_eq(jobs.fill(), f, "a refused click adds nothing")
	assert_eq(economy.balance(1), 500)


func test_rich_player_cannot_snipe_the_last_click() -> void:
	economy.apply(1, 600, &"test")
	_press(9, 2)
	assert_eq(jobs.press(1, now + 0.1)["error"], &"enough_money")
	assert_eq(economy.balance(1), 600)
	_press(1, 2)
	assert_eq(economy.balance(2), 50)


func test_rate_limit_drops_extra_presses() -> void:
	# 40 presses in the same instant: only the burst (12) counts, the rest are dropped quietly.
	economy.apply(1, 499, &"test")  # 60 presses a bar: nothing pays out here
	for i: int in 40:
		assert_true(jobs.press(1, 5.0)["ok"])
	assert_almost_eq(jobs.fill(), 12.0 / 60.0, 0.001)
	# The limit is per player: someone else's clicks still count.
	economy.apply(2, 499, &"test")
	assert_true(jobs.press(2, 5.0)["ok"])
	assert_almost_eq(jobs.fill(), 13.0 / 60.0, 0.001)
	# A second later about 12 more are allowed.
	for i: int in 40:
		jobs.press(1, 6.0)
	assert_almost_eq(jobs.fill(), 25.0 / 60.0, 0.001)


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


func test_broke_line_is_the_house_comp_line() -> void:
	var cfg: BalanceConfig = Registry.balance
	assert_eq(OddJobsController.broke_line(cfg, 0), cfg.comp_threshold)
	assert_gte(OddJobsController.broke_line(cfg, 3), cfg.comp_threshold, "scales with the table limits")


func test_cabinet_aim_ray() -> void:
	var c := Vector3(1, 1, 0)
	assert_true(OddJobsCabinet.ray_hits(Vector3(0, 1.5, 0), (c - Vector3(0, 1.5, 0)), c, 0.2))
	assert_false(OddJobsCabinet.ray_hits(Vector3(0, 1.5, 0), Vector3(1, 0, 0), c, 0.2), "looking over it")
	assert_false(OddJobsCabinet.ray_hits(Vector3(0, 1.5, 0), Vector3(-1, -0.5, 0), c, 0.2), "behind you")
