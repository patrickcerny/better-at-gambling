extends GutTest
## The table and minigame achievements of 0.9.30 (`AchievementTracker`): streaks over the server
## events a client sees in one match.

const ME: int = 1
const OTHER: int = 2


func _result(game_station: StringName, net: int, details: Dictionary, player: int = ME, stake: int = 100) -> Dictionary:
	return {"type": &"round_result", "station": game_station, "player": player, "stake": stake, "returned": stake + net, "net": net, "details": details}


func _bj(t: AchievementTracker, outcome: StringName, net: int, cards: Array = [10, 7]) -> Array[StringName]:
	return t.on_event(_result(&"blackjack_1", net, {"outcome": outcome, "cards": cards, "dealer": [10, 8]}), ME, &"blackjack")


## A blackjack card of this rank (2..10).
func _card(rank: int) -> int:
	return Card.make(rank)


func test_every_id_is_defined() -> void:
	for id: StringName in AchievementTracker.IDS:
		assert_true(Achievements.DEFS.has(id), "%s is in DEFS" % id)


func test_blackjack_natural_and_four_losses_in_a_row() -> void:
	var t := AchievementTracker.new()
	assert_true(&"ACH_BJ_NATURAL" in _bj(t, &"blackjack", 150))
	for i: int in 3:
		assert_false(&"ACH_BJ_COLD_STREAK" in _bj(t, &"lose", -100), "loss %d" % (i + 1))
	assert_true(&"ACH_BJ_COLD_STREAK" in _bj(t, &"bust", -100), "fourth loss in a row")


func test_a_push_breaks_the_blackjack_streak() -> void:
	var t := AchievementTracker.new()
	for i: int in 3:
		_bj(t, &"lose", -100)
	_bj(t, &"push", 0)
	assert_false(&"ACH_BJ_COLD_STREAK" in _bj(t, &"lose", -100))
	assert_eq(t.bj_losing, 1)


func test_other_tables_and_players_do_not_touch_the_blackjack_streak() -> void:
	var t := AchievementTracker.new()
	for i: int in 3:
		_bj(t, &"lose", -100)
	t.on_event(_result(&"slots_1", 300, {"line": [0, 0, 0]}), ME, &"slots")
	t.on_event(_result(&"blackjack_1", 100, {"outcome": &"win", "cards": [10, 9]}, OTHER), ME, &"blackjack")
	assert_true(&"ACH_BJ_COLD_STREAK" in _bj(t, &"lose", -100))


func test_greedy_and_five_card_trick() -> void:
	var t := AchievementTracker.new()
	var ten: int = _card(10)
	var two: int = _card(2)
	var three: int = _card(3)
	assert_true(&"ACH_BJ_GREEDY" in _bj(t, &"bust", -100, [ten, ten, two]), "hit on 20, bust")
	assert_false(&"ACH_BJ_GREEDY" in _bj(t, &"bust", -100, [ten, _card(6), ten]), "hit on 16 is just a bust")
	assert_true(&"ACH_BJ_FIVE_CARDS" in _bj(t, &"win", 100, [two, two, three, three, _card(9)]))
	assert_false(&"ACH_BJ_FIVE_CARDS" in _bj(t, &"lose", -100, [two, two, three, three, _card(9)]))


func _spin(t: AchievementTracker, sid: StringName, number: int) -> void:
	t.on_event({"type": &"roulette_result", "station": sid, "number": number}, ME)


func _roulette(t: AchievementTracker, sid: StringName, type: StringName, value: int, number: int, net: int) -> Array[StringName]:
	return t.on_event(_result(sid, net, {"type": type, "value": value, "number": number}), ME, &"roulette")


func test_roulette_single_numbers_back_to_back() -> void:
	var t := AchievementTracker.new()
	_spin(t, &"roulette_1", 17)
	var got: Array[StringName] = _roulette(t, &"roulette_1", &"straight", 17, 17, 3500)
	assert_true(&"ACH_ROULETTE_NUMBER" in got)
	assert_false(&"ACH_ROULETTE_PSYCHIC" in got)
	_spin(t, &"roulette_1", 0)
	_roulette(t, &"roulette_1", &"red", 0, 0, -100)  # several bets on one spin: order doesn't matter
	got = _roulette(t, &"roulette_1", &"straight", 0, 0, 3500)
	assert_true(&"ACH_ROULETTE_PSYCHIC" in got, "second spin in a row")
	assert_true(&"ACH_ROULETTE_ZERO" in got)


func test_roulette_streak_needs_consecutive_spins_at_one_table() -> void:
	var t := AchievementTracker.new()
	_spin(t, &"roulette_1", 5)
	_roulette(t, &"roulette_1", &"straight", 5, 5, 3500)
	_spin(t, &"roulette_1", 9)
	_roulette(t, &"roulette_1", &"straight", 4, 9, -100)  # missed
	_spin(t, &"roulette_1", 4)
	assert_false(&"ACH_ROULETTE_PSYCHIC" in _roulette(t, &"roulette_1", &"straight", 4, 4, 3500), "a miss in between")
	_spin(t, &"roulette_2", 8)
	assert_false(&"ACH_ROULETTE_PSYCHIC" in _roulette(t, &"roulette_2", &"straight", 8, 8, 3500), "another table")
	_spin(t, &"roulette_1", 1)
	_spin(t, &"roulette_1", 1)  # sat one spin out
	assert_false(&"ACH_ROULETTE_PSYCHIC" in _roulette(t, &"roulette_1", &"straight", 1, 1, 3500), "a skipped spin breaks it")


func test_lucky_neighbour_is_not_a_hit() -> void:
	var t := AchievementTracker.new()
	_spin(t, &"roulette_1", 3)
	var got: Array[StringName] = t.on_event(_result(&"roulette_1", 500, {"type": &"straight", "value": 26, "number": 3, "lucky_neighbor": true}), ME, &"roulette")
	assert_false(&"ACH_ROULETTE_NUMBER" in got)


func test_table_moments() -> void:
	var t := AchievementTracker.new()
	assert_true(&"ACH_SLOTS_SEVENS" in t.on_event(_result(&"slots_1", 900, {"line": [4, 4, 4]}), ME, &"slots"))
	assert_false(&"ACH_SLOTS_SEVENS" in t.on_event(_result(&"slots_1", 900, {"line": [4, 4, 6]}), ME, &"slots"))
	assert_true(&"ACH_PLINKO_EDGE" in t.on_event(_result(&"plinko_1", 1100, {"multiplier_base": 12.0}), ME, &"plinko"))
	assert_false(&"ACH_PLINKO_EDGE" in t.on_event(_result(&"plinko_1", 400, {"multiplier_base": 5.0}), ME, &"plinko"))
	assert_true(&"ACH_WHEEL_WILD" in t.on_event(_result(&"wheel_1", 4000, {"symbol": 5, "won": 5}), ME, &"wheel"))
	assert_false(&"ACH_WHEEL_WILD" in t.on_event(_result(&"wheel_1", -100, {"symbol": 5, "won": 0}), ME, &"wheel"))
	assert_true(&"ACH_HOLDEM_FULL_HOUSE" in t.on_event(_result(&"holdem_1", 300, {"type": &"ante", "rank": 6}), ME, &"holdem"))
	assert_false(&"ACH_HOLDEM_FULL_HOUSE" in t.on_event(_result(&"holdem_1", -300, {"type": &"ante", "rank": 7}), ME, &"holdem"), "lost anyway")
	assert_true(&"ACH_HOLDEM_ROYAL_FLUSH" in t.on_event(_result(&"holdem_1", 900, {"type": &"ante", "rank": 9}), ME, &"holdem"))
	assert_true(&"ACH_HOLDEM_ROYAL_FLUSH" in t.on_event(_result(&"holdem_1", 500, {"type": &"bonus", "rank": 9}), ME, &"holdem"), "bonus bet")
	assert_false(&"ACH_HOLDEM_ROYAL_FLUSH" in t.on_event(_result(&"holdem_1", 900, {"type": &"ante", "rank": 8}), ME, &"holdem"), "straight flush")
	assert_false(&"ACH_HOLDEM_ROYAL_FLUSH" in t.on_event(_result(&"holdem_1", -100, {"type": &"ante", "outcome": &"fold"}), ME, &"holdem"), "fold")
	assert_true(&"ACH_HILO_LADDER" in t.on_event({"type": &"hilo_call", "player": ME, "won": true, "rung": 5}, ME))
	assert_false(&"ACH_HILO_LADDER" in t.on_event({"type": &"hilo_call", "player": ME, "won": true, "rung": 4}, ME))


func test_on_tilt_and_ouch() -> void:
	var t := AchievementTracker.new()
	for i: int in 9:
		assert_false(&"ACH_ON_TILT" in t.on_event(_result(&"slots_1", -50, {"line": [0, 1, 2]}), ME, &"slots"))
	t.on_event(_result(&"plinko_1", 0, {"multiplier_base": 1.0}), ME, &"plinko")  # a push keeps the streak
	assert_true(&"ACH_ON_TILT" in t.on_event(_result(&"slots_1", -50, {"line": [0, 1, 2]}), ME, &"slots"))
	assert_false(&"ACH_OUCH" in t.on_event(_result(&"roulette_1", -999, {"type": &"red", "value": 0, "number": 2}, ME, 999), ME, &"roulette"))
	assert_true(&"ACH_OUCH" in t.on_event(_result(&"roulette_1", -1000, {"type": &"red", "value": 0, "number": 2}, ME, 1000), ME, &"roulette"))
	t.on_event(_result(&"slots_1", 50, {"line": [0, 0, 0]}), ME, &"slots")
	assert_eq(t.losing, 0, "a win resets it")


func test_fails_and_brawls() -> void:
	var t := AchievementTracker.new()
	assert_false(&"ACH_JAILBIRD" in t.on_event({"type": &"player_jailed", "player": ME}, ME))
	t.on_event({"type": &"player_jailed", "player": OTHER}, ME)
	assert_false(&"ACH_JAILBIRD" in t.on_event({"type": &"player_jailed", "player": ME}, ME))
	assert_true(&"ACH_JAILBIRD" in t.on_event({"type": &"player_jailed", "player": ME}, ME), "third time")
	assert_true(&"ACH_WET_FLOOR" in t.on_event({"type": &"puddle_slip", "player": ME}, ME))
	assert_true(&"ACH_TRIP_WAITER" in t.on_event({"type": &"waiter_tripped", "player": ME, "cause": &"shove"}, ME))
	assert_false(&"ACH_TRIP_WAITER" in t.on_event({"type": &"waiter_tripped", "player": -1, "cause": &"puddle"}, ME))
	assert_true(&"ACH_HOT_POTATO" in t.on_event({"type": &"pass_the_bomb_exploded", "player": ME}, ME))
	assert_true(&"ACH_COUNTERFEIT" in t.on_event({"type": &"fake_cash_caught", "player": ME, "fine": 50}, ME))
	assert_true(&"ACH_YEET" in t.on_event({"type": &"player_thrown", "attacker": ME, "target": OTHER}, ME))
	assert_false(&"ACH_YEET" in t.on_event({"type": &"player_thrown", "attacker": OTHER, "target": ME}, ME))


func test_backstabber() -> void:
	var t := AchievementTracker.new()
	var ev: Dictionary = {"type": &"split_or_steal_reveal", "a": OTHER, "b": ME, "house": -1, "choice_a": "SPLIT", "choice_b": "STEAL"}
	assert_true(&"ACH_BACKSTABBER" in t.on_event(ev, ME))
	ev["choice_a"] = "STEAL"
	assert_false(&"ACH_BACKSTABBER" in t.on_event(ev, ME), "both stole")
	ev["choice_a"] = "SPLIT"
	ev["house"] = ME
	assert_false(&"ACH_BACKSTABBER" in t.on_event(ev, ME), "the house seat scores nothing")


func test_participation_trophy() -> void:
	var rows: Array = [{"player": 3, "rank": 1}, {"player": OTHER, "rank": 2}, {"player": ME, "rank": 3}]
	var t := AchievementTracker.new()
	assert_true(&"ACH_LAST_PLACE" in t.on_event({"type": &"minigame_finished", "ranking": rows}, ME))
	assert_false(&"ACH_LAST_PLACE" in t.on_event({"type": &"minigame_finished", "ranking": rows.slice(1)}, ME), "a duel")
	var tied: Array = [{"player": 3, "rank": 1}, {"player": OTHER, "rank": 1}, {"player": ME, "rank": 1}]
	assert_false(&"ACH_LAST_PLACE" in t.on_event({"type": &"minigame_finished", "ranking": tied}, ME), "everyone tied")
	assert_false(&"ACH_LAST_PLACE" in t.on_event({"type": &"minigame_finished", "ranking": rows}, OTHER))


func test_server_has_no_local_player() -> void:
	var t := AchievementTracker.new()
	assert_true(t.on_event({"type": &"puddle_slip", "player": ME}, -1).is_empty())


func test_blackjack_suited_trips() -> void:
	var t := AchievementTracker.new()
	var q: int = Card.make(12, 1)  # queen of hearts
	var trips := func(cards: Array, up: int, extra: Dictionary = {}) -> Array[StringName]:
		var d: Dictionary = {"outcome": &"push", "cards": cards, "dealer": [up, Card.make(10, 2)]}
		d.merge(extra)
		return t.on_event(_result(&"blackjack_1", 0, d), ME, &"blackjack")
	assert_true(&"ACH_BJ_SUITED_TRIPS" in trips.call([q, q], q))
	assert_true(&"ACH_BJ_SUITED_TRIPS" in trips.call([q, q, Card.make(2)], q), "hit after the deal still counts")
	assert_false(&"ACH_BJ_SUITED_TRIPS" in trips.call([q, Card.make(12, 2)], q), "suits differ")
	assert_false(&"ACH_BJ_SUITED_TRIPS" in trips.call([q, q], Card.make(12, 0)), "dealer suit differs")
	assert_false(&"ACH_BJ_SUITED_TRIPS" in trips.call([q, q], q, {"split": true}), "split hand")
