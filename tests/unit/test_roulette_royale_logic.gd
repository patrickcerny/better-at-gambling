extends GutTest
## Roulette Royale rules: players start with 3 hearts, pick red/black/green,
## last player with ≥1 heart wins.

var cfg: BalanceConfig = BalanceConfig.new()
var now: float = 0.0


func before_each() -> void:
	now = 0.0


func _royale(players: Array[int]) -> RouletteRoyaleLogic:
	var r := RouletteRoyaleLogic.new()
	r.setup(players, SeededRng.new(5), cfg, {}, {})
	return r


func test_players_start_with_three_hearts() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	var state: Dictionary = r.get_public_state()
	assert_eq(state["hearts"][1], 3)
	assert_eq(state["hearts"][2], 3)


func test_wrong_choice_loses_a_heart() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])

	# Play multiple rounds and check that hearts decrease
	for i: int in 5:
		r.submit(1, {"choice": "red"}, now)
		r.submit(2, {"choice": "black"}, now)
		r.tick(0.05, now)
		now += 0.05

		# Stop if game is finished
		if r.is_finished():
			break

	var state: Dictionary = r.get_public_state()
	# At least one player should have less than 3 hearts
	var total_hearts: int = state["hearts"][1] + state["hearts"][2]
	assert_lt(total_hearts, 6)


func test_game_ends_when_one_player_remains() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])

	# Simulate many rounds
	for i: int in 20:
		if r.active_players.size() > 1:
			for p: int in r.active_players:
				r.submit(p, {"choice": "red"}, now)
			r.tick(0.05, now)
			now += 0.05

		if r.is_finished():
			break

	# Game should be finished
	assert_true(r.is_finished())


func test_invalid_choice_rejected() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])

	var result: Dictionary = r.submit(1, {"choice": "blue"}, now)
	assert_eq(result["error"], &"invalid_choice")


func test_double_choice_rejected() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])

	assert_true(r.submit(1, {"choice": "red"}, now)["ok"])
	var result: Dictionary = r.submit(1, {"choice": "black"}, now)
	assert_eq(result["error"], &"already_chose")


func test_unknown_player_rejected() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])

	var result: Dictionary = r.submit(99, {"choice": "red"}, now)
	assert_eq(result["error"], &"unknown_player")


func test_ranking_by_hearts_remaining() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2, 3])

	# Manual setup: player 1 has 3 hearts, player 2 has 1, player 3 has 0
	r.hearts[1] = 3
	r.hearts[2] = 1
	r.hearts[3] = 0
	r.active_players = [1, 2]
	r.finished = true

	var ranking: Array[Dictionary] = r.ranking()
	assert_eq(ranking[0]["player"], 1, "Most hearts ranks first")
	assert_eq(ranking[1]["player"], 2)
	assert_eq(ranking[2]["player"], 3)


func test_events_emitted() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	var events: Array[Dictionary] = r.drain_events()

	# Should have started event
	var started: Array = events.filter(func(e: Dictionary) -> bool:
		return e["type"] == &"roulette_royale_started"
	)
	assert_eq(started.size(), 1)


func test_round_start_event() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	r.drain_events()

	r.submit(1, {"choice": "red"}, now)
	var events: Array[Dictionary] = r.drain_events()

	var round_start: Array = events.filter(func(e: Dictionary) -> bool:
		return e["type"] == &"roulette_royale_round_start"
	)
	assert_eq(round_start.size(), 1)


func test_spin_result_event() -> void:
	var r: RouletteRoyaleLogic = _royale([1, 2])
	r.drain_events()

	r.submit(1, {"choice": "red"}, now)
	r.submit(2, {"choice": "black"}, now)
	r.tick(0.05, now)

	var events: Array[Dictionary] = r.drain_events()
	var spin: Array = events.filter(func(e: Dictionary) -> bool:
		return e["type"] == &"roulette_royale_spin_result"
	)
	assert_eq(spin.size(), 1)
	assert_true(spin[0].has("number"))
	assert_true(spin[0].has("color"))
