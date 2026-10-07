extends GutTest
## Bust or Bank minigame logic tests.

var cfg: BalanceConfig
var now: float = 0.0


func before_each() -> void:
	cfg = BalanceConfig.new()
	now = 0.0


func _bust_or_bank(players: Array[int]) -> BustOrBankLogic:
	var logic := BustOrBankLogic.new()
	logic.setup(players, SeededRng.new(5), cfg, {}, {})
	return logic


func _run(logic: BustOrBankLogic, seconds: float, events: Array) -> void:
	var t: float = 0.0
	while t < seconds - 0.0001 and not logic.is_finished():
		logic.tick(0.05, now)
		now += 0.05
		t += 0.05
		events.append_array(logic.drain_events())


func test_game_initialization() -> void:
	var logic: BustOrBankLogic = _bust_or_bank([1, 2, 3])
	assert_false(logic.is_finished())
	assert_eq(logic.round, 0)


func test_single_round_hit_and_stand() -> void:
	var events: Array[Dictionary] = []
	var logic: BustOrBankLogic = _bust_or_bank([1, 2])
	events.append_array(logic.drain_events())

	# Player 1 hits
	logic.submit(1, {"action": "hit"}, now)
	events.append_array(logic.drain_events())

	# Player 2 stands
	logic.submit(2, {"action": "stand"}, now)
	events.append_array(logic.drain_events())

	# Both players have acted, round should end
	_run(logic, 0.1, events)

	var round_end_events: Array = events.filter(func(e: Dictionary) -> bool: return e["type"] == &"bust_or_bank_round_end")
	assert_eq(round_end_events.size(), 1)


func test_bust_detection() -> void:
	var events: Array[Dictionary] = []
	var logic: BustOrBankLogic = _bust_or_bank([1, 2])
	events.append_array(logic.drain_events())

	# Keep hitting player 1 until bust
	var busted: bool = false
	for i: int in 20:
		var result: Dictionary = logic.submit(1, {"action": "hit"}, now)
		events.append_array(logic.drain_events())

		var bust_events: Array = events.filter(func(e: Dictionary) -> bool: return e["type"] == &"bust_or_bank_player_bust")
		if bust_events.size() > 0:
			busted = true
			break

	assert_true(busted, "Player should eventually bust")


func test_five_rounds_then_finish() -> void:
	var events: Array[Dictionary] = []
	var logic: BustOrBankLogic = _bust_or_bank([1, 2])
	events.append_array(logic.drain_events())

	# Run for a long time to ensure 5 rounds complete
	_run(logic, 100.0, events)

	var round_end_events: Array = events.filter(func(e: Dictionary) -> bool: return e["type"] == &"bust_or_bank_round_end")
	assert_eq(round_end_events.size(), 5)
	assert_true(logic.is_finished())


func test_ranking_by_points() -> void:
	var events: Array[Dictionary] = []
	var logic: BustOrBankLogic = _bust_or_bank([1, 2])
	events.append_array(logic.drain_events())

	_run(logic, 100.0, events)

	var ranking: Array = logic.ranking()
	assert_eq(ranking.size(), 2)
	# First player should have better points
	if ranking[0]["points"] != ranking[1]["points"]:
		assert_gt(ranking[0]["points"], ranking[1]["points"])


func test_cannot_submit_after_stood() -> void:
	var logic: BustOrBankLogic = _bust_or_bank([1, 2])
	logic.drain_events()

	logic.submit(1, {"action": "stand"}, now)
	var result: Dictionary = logic.submit(1, {"action": "hit"}, now)

	assert_false(result.get("ok", false))
	assert_eq(result.get("error", ""), &"already_stood")


func test_cannot_submit_after_bust() -> void:
	var logic: BustOrBankLogic = _bust_or_bank([1, 2])
	logic.drain_events()

	# Force player to bust by hitting many times
	for i: int in 20:
		var result: Dictionary = logic.submit(1, {"action": "hit"}, now)
		if not result.get("ok", false):
			break

	# Try to hit after bust
	var result2: Dictionary = logic.submit(1, {"action": "hit"}, now)
	assert_false(result2.get("ok", false))
