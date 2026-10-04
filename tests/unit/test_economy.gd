extends GutTest


func test_start_money_recorded() -> void:
	var e := Economy.new()
	e.add_player(1, 1000)
	assert_eq(e.balance(1), 1000)
	assert_eq(e.ledger.entries.size(), 1)
	assert_eq(e.ledger.entries[0]["reason"], &"start")


func test_cannot_go_negative() -> void:
	var e := Economy.new()
	e.add_player(1, 100)
	assert_false(e.apply(1, -101, &"bet_slots"))
	assert_eq(e.balance(1), 100)
	assert_true(e.apply(1, -100, &"bet_slots"))
	assert_eq(e.balance(1), 0)


func test_every_change_needs_reason_and_known_player() -> void:
	var e := Economy.new()
	e.add_player(1, 100)
	assert_false(e.apply(1, 10, &""))
	assert_false(e.apply(2, 10, &"win"))


func test_take_up_to_never_takes_more_than_balance() -> void:
	var e := Economy.new()
	e.add_player(1, 30)
	assert_eq(e.take_up_to(1, 50, &"pickpocket"), 30)
	assert_eq(e.balance(1), 0)


func test_events_and_conservation() -> void:
	var e := Economy.new()
	e.add_player(1, 1000)
	e.add_player(2, 1000)
	e.apply(1, -100, &"bet_blackjack")
	e.apply(1, 200, &"win_blackjack")
	e.apply(2, -50, &"bet_roulette")
	var evs: Array[Dictionary] = e.drain_events()
	assert_eq(evs.size(), 5)
	for ev: Dictionary in evs:
		assert_eq(GameEvents.validate(ev), [] as Array[String])
	assert_eq(e.ledger.total(), e.balance(1) + e.balance(2))
	assert_eq(e.ledger.by_reason()[&"win_blackjack"], 200)
	assert_eq(e.drain_events().size(), 0)
