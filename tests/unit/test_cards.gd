extends GutTest


func _h(ranks: Array) -> Array[int]:
	var out: Array[int] = []
	for r: int in ranks:
		out.append(Card.make(r))
	return out


func test_card_encoding() -> void:
	var c: int = Card.make(1, 3)
	assert_eq(Card.rank(c), 1)
	assert_eq(Card.suit(c), 3)
	assert_eq(Card.label(Card.make(10, 1)), "10H")
	assert_eq(Card.bj_value(Card.make(13)), 10)


func test_totals_soft_and_hard() -> void:
	assert_eq(HandEval.total(_h([1, 6])), 17)
	assert_true(HandEval.is_soft(_h([1, 6])))
	assert_eq(HandEval.total(_h([1, 6, 10])), 17)
	assert_false(HandEval.is_soft(_h([1, 6, 10])))
	assert_eq(HandEval.total(_h([1, 1, 9])), 21)
	assert_eq(HandEval.total(_h([1, 1, 1, 1])), 14)
	assert_eq(HandEval.total(_h([10, 6, 9])), 25)
	assert_true(HandEval.is_bust(_h([10, 6, 9])))


func test_blackjack_vs_21() -> void:
	assert_true(HandEval.is_blackjack(_h([1, 13])))
	assert_false(HandEval.is_blackjack(_h([7, 7, 7])))
	assert_eq(HandEval.quality(_h([1, 12])), 22.0)
	assert_eq(HandEval.quality(_h([7, 7, 7])), 21.0)
	assert_eq(HandEval.quality(_h([10, 10, 5])), -1.0)


func test_shoe_size_and_reshuffle_at_penetration() -> void:
	var s := Shoe.new(SeededRng.new(1), 6, 0.75)
	assert_eq(s.remaining(), 312)
	for i: int in 233:
		s.draw()
	assert_false(s.needs_reshuffle())
	s.draw()
	assert_true(s.needs_reshuffle())
	s.reshuffle()
	assert_eq(s.remaining(), 312)


func test_shoe_contents_are_six_decks() -> void:
	var s := Shoe.new(SeededRng.new(9), 6, 1.0)
	var counts: Dictionary = {}
	for i: int in 312:
		var c: int = s.draw()
		counts[c] = counts.get(c, 0) + 1
	assert_eq(counts.size(), 52)
	for c: int in counts:
		assert_eq(counts[c], 6)


func test_stack_top_order() -> void:
	var s := Shoe.new(SeededRng.new(1))
	s.stack_top(_h([1, 2, 3]))
	assert_eq(Card.rank(s.draw()), 1)
	assert_eq(Card.rank(s.draw()), 2)
	assert_eq(Card.rank(s.draw()), 3)


func test_return_card_keeps_count() -> void:
	var s := Shoe.new(SeededRng.new(1))
	var c: int = s.draw()
	s.return_card(c)
	assert_eq(s.remaining(), 312)
