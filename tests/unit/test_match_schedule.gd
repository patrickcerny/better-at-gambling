extends GutTest

var presets: MatchPresets = load("res://data/balance/match_presets.tres")


func test_schedule_table_exact() -> void:
	var expect: Dictionary = {5: [2, 100.0], 10: [3, 150.0], 15: [4, 180.0], 30: [7, 225.0]}
	for d: int in expect:
		var s := MatchSchedule.new(d, presets)
		assert_eq(s.minigames, expect[d][0], "minigames for %d" % d)
		assert_almost_eq(s.segment_s, float(expect[d][1]), 0.001, "segment for %d" % d)
		assert_eq(s.segments(), int(expect[d][0]) + 1)


func test_quiz_times_5_minutes() -> void:
	var s := MatchSchedule.new(5, presets)
	assert_eq(s.minigame_times(), [100.0, 200.0] as Array[float])


func test_quiz_times_30_minutes_every_3_45() -> void:
	var t: Array[float] = MatchSchedule.new(30, presets).minigame_times()
	assert_eq(t.size(), 7)
	for i: int in t.size():
		assert_almost_eq(t[i], 225.0 * (i + 1), 0.001)


func test_segment_index_and_last_call() -> void:
	var s := MatchSchedule.new(10, presets)
	assert_eq(s.segment_index(0.0), 0)
	assert_eq(s.segment_index(149.9), 0)
	assert_eq(s.segment_index(150.0), 1)
	assert_eq(s.segment_index(599.0), 3)
	assert_false(s.is_last_call(539.9))
	assert_true(s.is_last_call(540.0))
	assert_true(s.is_over(600.0))


func test_limits_multiplier_growth_and_cap() -> void:
	var cfg := BalanceConfig.new()
	assert_almost_eq(cfg.limits_multiplier(0), 1.0, 0.0001)
	assert_almost_eq(cfg.limits_multiplier(2), 2.0, 0.0001)
	assert_almost_eq(cfg.limits_multiplier(7), 3.0, 0.0001)


func test_invalid_duration() -> void:
	assert_false(MatchSchedule.is_valid_duration(7, presets))
	assert_true(MatchSchedule.is_valid_duration(15, presets))
