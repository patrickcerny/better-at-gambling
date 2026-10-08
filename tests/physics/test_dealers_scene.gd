extends GutTest
## Dealers in the real casino (0.8.14): one per blackjack and roulette table, standing outside
## the table body and facing the players (Patrick: roulette dealers were inside the table and
## blackjack dealers looked away).

var scene: MatchScene


func before_each() -> void:
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_seconds(3.3)


func test_every_dealer_stands_clear_of_its_table_and_faces_it() -> void:
	var dealers: Dictionary = scene.casino_floor.dealers
	assert_gt(dealers.size(), 3, "blackjack and roulette tables all have a dealer")
	for sid: StringName in dealers:
		var dealer: Dealer = dealers[sid]
		var station: StationBase = scene.map.stations[sid]
		var local: Vector3 = station.to_local(dealer.global_position)
		match station.game_id:
			&"roulette":
				assert_lt(local.x, -2.2, "%s: past the wheel end (body ends at x −1.5, wheel at −2.1)" % sid)
				assert_almost_eq(local.z, 0.0, 0.05, "%s: centred on the short side" % sid)
			&"blackjack":
				assert_almost_eq(local.z, -1.2, 0.05, "%s: on the straight north edge" % sid)
				assert_almost_eq(local.x, 0.0, 0.05)
		# Facing: the dealer's forward points at the table (the players sit on the far side).
		var to_table: Vector3 = station.global_position - dealer.global_position
		to_table.y = 0.0
		assert_gt(dealer.forward().dot(to_table.normalized()), 0.9, "%s faces the table, not away from it" % sid)
		assert_almost_eq(dealer.rotation.y, dealer.yaw, 0.001)
	# The host reports every dealer spot to the server, where the shove/bat reach is judged.
	for sid: StringName in dealers:
		var logic: DealerLogic = scene.server.dealers[sid]
		assert_almost_eq(logic.where(), (dealers[sid] as Dealer).global_position, Vector3.ONE * 0.05, "%s: server and scene agree" % sid)
		assert_almost_eq(DealerLogic.new(sid, {}, scene.server.rules, scene.server.world, SeededRng.new(1), null, scene.server.map_def, logic.offset).where(), (dealers[sid] as Dealer).global_position, Vector3.ONE * 0.05, "%s: a headless server derives the same spot from the map" % sid)
