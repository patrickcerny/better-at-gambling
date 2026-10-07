extends GutTest
## M6 hardening: 50 whole matches on the headless server (seeds 1–50, mixed match lengths and party
## sizes) with scripted players that play slots, roulette and Plinko, answer the quiz and use the
## items the rewards hand out, all through the normal intents. Every match must reach the results
## with no errors, valid events and money conserved (ledger = balances, dropped chips accounted
## for, every refunded bet in the ledger and nothing left in play when a minigame starts).

## [minigames, gambling seconds between them].
const LENGTHS: Array = [[2, 100.0], [3, 150.0], [2, 100.0], [4, 180.0], [2, 100.0], [7, 225.0], [2, 100.0], [3, 150.0]]
const GAMES: Array[StringName] = [&"slot_1", &"slot_2", &"slot_3", &"slot_7", &"roulette_1", &"roulette_2", &"plinko_1", &"plinko_2"]


func test_fifty_scripted_matches_end_cleanly_with_money_conserved() -> void:
	var errors_before: int = Log.error_count
	var summary: PackedStringArray = []
	for match_seed: int in range(1, 51):
		var players: int = 2 + match_seed % 7
		var length: Array = LENGTHS[match_seed % LENGTHS.size()]
		var fx := ServerFixture.new(players, {"minigames": int(length[0]), "gamble_seconds": float(length[1]), "seed": match_seed})
		var in_play_at_minigame: Array[int] = []
		fx.server.event_emitted.connect(func(ev: Dictionary) -> void:
			if ev["type"] == &"minigame_started":
				for id: int in fx.player_ids:
					if fx.server.stations.has_stake(id) or fx.server.stations.is_seated(id):
						in_play_at_minigame.append(id))
		var stats: Dictionary = _play(fx, match_seed)
		assert_eq(fx.server.phases.phase, Phase.Id.RESULTS, "seed %d reaches the results" % match_seed)
		_assert_conserved(fx, match_seed)
		assert_eq(in_play_at_minigame, [] as Array[int], "seed %d: minigames start with nothing in play and nobody seated" % match_seed)
		summary.append("seed %d: %d players %d minigames, bets=%d answers=%d items=%d refunds=%d" % [match_seed, players, int(length[0]), stats["bets"], stats["answers"], stats["items"], fx.of_type(&"bets_refunded").size()])
		assert_gt(int(stats["bets"]), 0, "seed %d: players bet" % match_seed)
		fx.server.free()
	gut.p("\n".join(summary))
	assert_eq(Log.error_count, errors_before, "no errors logged")


## Runs the match to the end with scripted players acting once per game second.
func _play(fx: ServerFixture, match_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed * 7919
	var stats: Dictionary = {"bets": 0, "answers": 0, "items": 0}
	fx.server.start_match()
	fx.run(3.1)
	fx.place_all()
	var answered: Dictionary = {}
	var guard: int = 0
	while fx.server.running and fx.server.phases.phase != Phase.Id.RESULTS and guard < 4000:
		guard += 1
		fx.server.run_to_end(1.0)
		var phase: Phase.Id = fx.server.phases.phase
		for id: int in fx.player_ids:
			if phase == Phase.Id.CASINO:
				_casino_turn(fx, id, rng, stats)
			elif phase == Phase.Id.MINIGAME and fx.server.minigame is QuizLogic:
				var q: QuizLogic = fx.server.minigame
				var key: String = "%d:%d:%d" % [id, fx.server.phases.segment_index(), q.index]
				if not answered.has(key) and rng.randf() < 0.5:
					answered[key] = true
					if fx.intent(id, &"submit_answer", {"question": q.index, "index": rng.randi_range(0, 3)})["ok"]:
						stats["answers"] += 1
			elif phase == Phase.Id.REWARDS and rng.randf() < 0.3:
				fx.intent(id, &"discard_item", {"slot": rng.randi_range(0, 3)})
	return stats


func _casino_turn(fx: ServerFixture, id: int, rng: RandomNumberGenerator, stats: Dictionary) -> void:
	var p: PlayerState = fx.server.state.players[id]
	if not p.inventory.is_empty() and rng.randf() < 0.05:
		var target: int = fx.player_ids[rng.randi_range(0, fx.player_ids.size() - 1)]
		if fx.intent(id, &"use_item", {"slot": 0, "target": target, "option": rng.randi_range(0, 2)})["ok"]:
			stats["items"] += 1
	if p.station == &"":
		if rng.randf() < 0.5:
			fx.intent(id, &"sit", {"station": GAMES[rng.randi_range(0, GAMES.size() - 1)]})
		return
	if rng.randf() < 0.08:
		fx.intent(id, &"leave")
		return
	var amount: int = [5, 10, 25, 50][rng.randi_range(0, 3)]
	var bet: Dictionary = {"amount": amount}
	if String(p.station).begins_with("roulette"):
		bet["type"] = [&"red", &"black", &"odd", &"even"][rng.randi_range(0, 3)]
	if fx.intent(id, &"place_bet", {"station": p.station, "bet": bet})["ok"]:
		stats["bets"] += 1


func _assert_conserved(fx: ServerFixture, match_seed: int) -> void:
	var balances: int = 0
	for id: int in fx.server.state.players:
		balances += fx.server.economy.balance(id)
	assert_eq(fx.server.economy.ledger.total(), balances, "seed %d: ledger matches balances" % match_seed)
	var refunded_events: int = 0
	var refunded_ledger: int = 0
	for e: Dictionary in fx.events:
		if e["type"] == &"bets_refunded":
			refunded_events += int(e["amount"])
		elif e["type"] == &"money_changed" and e["reason"] == &"bet_refunded":
			refunded_ledger += int(e["amount"])
	assert_eq(refunded_ledger, refunded_events, "seed %d: every refund is in the ledger" % match_seed)
	var dropped: int = 0
	var collected: int = 0
	var expired: int = 0
	for e: Dictionary in fx.events:
		match e["type"]:
			&"chips_dropped":
				dropped += int(e["amount"])
			&"chips_collected":
				collected += int(e["amount"])
			&"pickup_expired":
				expired += int(e["amount"])
	assert_eq(dropped, collected + expired + fx.server.pickups.total_on_floor(), "seed %d: dropped chips accounted for" % match_seed)
	var bad: int = 0
	for e: Dictionary in fx.events:
		if not GameEvents.validate(e).is_empty():
			bad += 1
	assert_eq(bad, 0, "seed %d: every event is valid" % match_seed)
