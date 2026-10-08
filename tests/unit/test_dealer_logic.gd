extends GutTest
## Dealer spots and facing (0.8.14): the offset lives in the table's frame, so a turned table
## keeps its dealer at the wheel end, and the dealer faces the players.


func _logic(sid: StringName, game: StringName, table: Vector3, yaw: float) -> DealerLogic:
	var map := MapDefinition.new()
	map.station_positions = {sid: table}
	map.station_yaws = {sid: yaw}
	return DealerLogic.new(sid, {}, InteractionRules.new(BalanceConfig.new()), WorldQuery.new(), SeededRng.new(1), null, map, DealerLogic.OFFSETS[game])


func test_roulette_dealer_stands_past_the_wheel_end_and_turns_with_the_table() -> void:
	var d: DealerLogic = _logic(&"roulette_1", &"roulette", Vector3(-6, 0, -3), 0.0)
	assert_almost_eq(d.where(), Vector3(-8.5, 0.5, -3), Vector3.ONE * 0.001, "x −2.5: clear of the 4.2 m body and the wheel")
	assert_almost_eq(d.facing(&"roulette"), -PI * 0.5, 0.001, "looks along +x, down the layout")
	var mirrored: DealerLogic = _logic(&"roulette_2", &"roulette", Vector3(6, 0, -3), PI)
	assert_almost_eq(mirrored.where(), Vector3(8.5, 0.5, -3), Vector3.ONE * 0.001, "the 180° table has its wheel on +x")
	assert_almost_eq(absf(mirrored.facing(&"roulette")), PI * 0.5, 0.001)
	assert_lt(sin(mirrored.facing(&"roulette")) * -1.0, 0.0, "looks along −x, back towards the table")


func test_blackjack_dealer_on_the_straight_edge_facing_the_stools() -> void:
	var d: DealerLogic = _logic(&"blackjack_1", &"blackjack", Vector3(-16, 0, 4), 0.0)
	assert_almost_eq(d.where(), Vector3(-16, 0.5, 2.8), Vector3.ONE * 0.001)
	assert_almost_eq(absf(d.facing(&"blackjack")), PI, 0.001, "yaw PI looks down +z, where the stools fan out")


func test_scene_report_wins_over_the_map() -> void:
	var d: DealerLogic = _logic(&"blackjack_1", &"blackjack", Vector3(-16, 0, 4), 0.0)
	d.position = Vector3(1, 0.5, 1)
	assert_eq(d.where(), Vector3(1, 0.5, 1))
	d.map_def = null
	d.position = Vector3.INF
	assert_false(d.where().is_finite(), "no map, no report: unknown")
