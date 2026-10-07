extends GutTest
## Match length as a number of minigames plus gambling time between them (Patrick's note #12).

var presets: MatchPresets = load("res://data/balance/match_presets.tres")


func test_default_match_is_five_minigames_three_minutes_apart() -> void:
	var s := MatchSchedule.new(presets.default_minigames, presets.default_gamble_minutes * 60.0)
	assert_eq(s.minigames, 5)
	assert_almost_eq(s.segment_s, 180.0, 0.001)
	assert_eq(s.segments(), 6, "a last gambling stretch follows the final minigame")
	assert_almost_eq(s.duration_s, 1080.0, 0.001)


func test_duration_is_gamble_time_times_segments() -> void:
	for mg: int in [1, 3, 10]:
		for gm: int in [1, 4, 6]:
			var s := MatchSchedule.new(mg, gm * 60.0)
			assert_almost_eq(s.duration_s, gm * 60.0 * (mg + 1), 0.001, "%d minigames, %d min" % [mg, gm])
			assert_eq(s.minigame_times().size(), mg)


func test_minigame_times_every_gambling_stretch() -> void:
	var s := MatchSchedule.new(2, 100.0)
	assert_eq(s.minigame_times(), [100.0, 200.0] as Array[float])
	var t: Array[float] = MatchSchedule.new(7, 225.0).minigame_times()
	assert_eq(t.size(), 7)
	for i: int in t.size():
		assert_almost_eq(t[i], 225.0 * (i + 1), 0.001)


func test_segment_index_and_last_call_in_the_final_stretch() -> void:
	var s := MatchSchedule.new(3, 150.0, 60.0)
	assert_eq(s.segment_index(0.0), 0)
	assert_eq(s.segment_index(149.9), 0)
	assert_eq(s.segment_index(150.0), 1)
	assert_eq(s.segment_index(599.0), 3)
	assert_false(s.is_last_call(539.9))
	assert_true(s.is_last_call(540.0), "Last Call is the final 60 s of the last stretch")
	assert_true(s.is_over(600.0))


func test_zero_minigames_for_dev_matches() -> void:
	var s := MatchSchedule.new(0, 60.0)
	assert_eq(s.minigames, 0)
	assert_eq(s.segments(), 1)
	assert_almost_eq(s.duration_s, 60.0, 0.001)


func test_limits_multiplier_growth_and_cap() -> void:
	var cfg := BalanceConfig.new()
	assert_almost_eq(cfg.limits_multiplier(0), 1.0, 0.0001)
	assert_almost_eq(cfg.limits_multiplier(2), 2.0, 0.0001)
	assert_almost_eq(cfg.limits_multiplier(7), 3.0, 0.0001)


func test_preset_bounds() -> void:
	assert_true(presets.is_valid_minigames(1))
	assert_true(presets.is_valid_minigames(10))
	assert_false(presets.is_valid_minigames(0))
	assert_false(presets.is_valid_minigames(11))
	assert_true(presets.is_valid_gamble_minutes(1))
	assert_true(presets.is_valid_gamble_minutes(6))
	assert_false(presets.is_valid_gamble_minutes(0))
	assert_false(presets.is_valid_gamble_minutes(7))


func test_house_comp_grows_with_minigames_played() -> void:
	# Patrick, 2026-10-07: $300 at the start, then $450, $600, $750, and $900 from then on.
	var cfg: BalanceConfig = load("res://data/balance/balance.tres")
	var expect: Array[int] = [300, 450, 600, 750, 900, 900, 900, 900, 900, 900, 900]
	for played: int in expect.size():
		assert_eq(cfg.comp_amount_for(played), expect[played], "after %d minigames" % played)
	assert_eq(cfg.comp_amount_for(-1), 300)
