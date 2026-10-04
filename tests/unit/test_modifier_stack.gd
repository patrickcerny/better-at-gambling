extends GutTest


func _mod(id: StringName, luck: int = 0, game: StringName = &"") -> Modifier:
	var m := Modifier.new()
	m.id = id
	m.luck = luck
	m.game_id = game
	return m


func test_luck_sum_clamped_and_game_specific() -> void:
	var s := ModifierStack.new(3)
	s.add(1, _mod(&"clover", 2))
	s.add(1, _mod(&"reels", 3, &"slots"))
	assert_eq(s.get_luck(1, &"blackjack"), 2)
	assert_eq(s.get_luck(1, &"slots"), 3)
	s.add(1, _mod(&"cat", -2))
	assert_eq(s.get_luck(1, &"slots"), 3)
	assert_eq(s.get_luck(1, &"roulette"), 0)


func test_expiry() -> void:
	var s := ModifierStack.new()
	var m := _mod(&"clover", 2)
	m.expires_at = 45.0
	s.add(1, m)
	s.expire(44.9)
	assert_eq(s.get_luck(1), 2)
	s.expire(45.0)
	assert_eq(s.get_luck(1), 0)


func test_consume_on_win_and_loss() -> void:
	var s := ModifierStack.new()
	var dbl := _mod(&"double_down")
	dbl.payout_multiplier = 2.0
	dbl.consume_on_win = true
	s.add(1, dbl)
	var gold := _mod(&"golden_chip")
	gold.refund_on_loss = true
	s.add(1, gold)
	assert_almost_eq(s.get_payout_multiplier(1, &"slots"), 2.0, 0.0001)
	s.consume_on_win(1, &"slots")
	assert_almost_eq(s.get_payout_multiplier(1, &"slots"), 1.0, 0.0001)
	assert_true(s.consume_on_loss(1, &"slots"))
	assert_false(s.consume_on_loss(1, &"slots"))


func test_rounds_left() -> void:
	var s := ModifierStack.new()
	var m := _mod(&"loaded_reels", 3, &"slots")
	m.rounds_left = 2
	s.add(1, m)
	s.consume_round(1, &"blackjack")
	assert_eq(s.get_luck(1, &"slots"), 3)
	s.consume_round(1, &"slots")
	s.consume_round(1, &"slots")
	assert_eq(s.get_luck(1, &"slots"), 0)
