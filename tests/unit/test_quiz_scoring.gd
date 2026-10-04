extends GutTest

var cfg: BalanceConfig = BalanceConfig.new()


func test_points_boundaries() -> void:
	assert_eq(QuizScoring.points(true, 0.0, cfg), 1000)
	assert_eq(QuizScoring.points(true, 12.0, cfg), 500)
	assert_eq(QuizScoring.points(true, 6.0, cfg), 750)
	assert_eq(QuizScoring.points(true, 20.0, cfg), 500)
	assert_eq(QuizScoring.points(false, 0.0, cfg), 0)
	assert_eq(QuizScoring.points(true, -1.0, cfg), 1000)


func test_latency_compensation() -> void:
	assert_almost_eq(QuizScoring.compensated_elapsed(10.0, 13.0, 0.1), 2.9, 0.0001)
	assert_eq(QuizScoring.compensated_elapsed(10.0, 10.05, 0.1), 0.0)


func test_ranking_with_ties() -> void:
	var pts: Dictionary = {1: 1800, 2: 2500, 3: 1800, 4: 1800, 5: 0}
	var times: Dictionary = {1: 5.0, 2: 9.0, 3: 4.0, 4: 5.0, 5: 0.0}
	var rows: Array[Dictionary] = QuizScoring.rank(pts, times)
	var order: Array = rows.map(func(r: Dictionary) -> int: return r["player"])
	assert_eq(order, [2, 3, 1, 4, 5])
	var ranks: Array = rows.map(func(r: Dictionary) -> int: return r["rank"])
	assert_eq(ranks, [1, 2, 3, 3, 5])
