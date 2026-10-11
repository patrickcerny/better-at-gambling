extends GutTest
## PokerHand: 1–5 cards → [category, tie-breakers...]. Every category, the wheel straight,
## partial hands (pairs/trips/quads count with fewer than 5, straights and flushes need 5),
## kickers, ties (suits never break one) and the default drop pick.

const S: int = 0
const H: int = 1
const D: int = 2
const C: int = 3
const Cat = PokerHand.Category


## Cards from [rank, suit] pairs (rank 1 = ace).
func _h(pairs: Array) -> Array[int]:
	var out: Array[int] = []
	for p: Array in pairs:
		out.append(Card.make(int(p[0]), int(p[1])))
	return out


func _cat(pairs: Array) -> int:
	return PokerHand.evaluate(_h(pairs))[0]


func test_every_category_with_five_cards() -> void:
	assert_eq(_cat([[2, S], [5, H], [9, D], [11, C], [13, S]]), Cat.HIGH_CARD)
	assert_eq(_cat([[2, S], [2, H], [9, D], [11, C], [13, S]]), Cat.PAIR)
	assert_eq(_cat([[2, S], [2, H], [9, D], [9, C], [13, S]]), Cat.TWO_PAIR)
	assert_eq(_cat([[2, S], [2, H], [2, D], [9, C], [13, S]]), Cat.THREE_OF_A_KIND)
	assert_eq(_cat([[5, S], [6, H], [7, D], [8, C], [9, S]]), Cat.STRAIGHT)
	assert_eq(_cat([[2, H], [6, H], [9, H], [11, H], [13, H]]), Cat.FLUSH)
	assert_eq(_cat([[4, S], [4, H], [4, D], [9, C], [9, S]]), Cat.FULL_HOUSE)
	assert_eq(_cat([[4, S], [4, H], [4, D], [4, C], [9, S]]), Cat.FOUR_OF_A_KIND)
	assert_eq(_cat([[5, C], [6, C], [7, C], [8, C], [9, C]]), Cat.STRAIGHT_FLUSH)
	var royal: Array[int] = PokerHand.evaluate(_h([[10, D], [11, D], [12, D], [13, D], [1, D]]))
	assert_eq(royal, [Cat.STRAIGHT_FLUSH, 14] as Array[int])
	assert_eq(PokerHand.name_of(royal), "ROYAL FLUSH")


func test_category_order_beats_kickers() -> void:
	var ladder: Array = [
		[[2, S], [5, H], [9, D], [11, C], [1, S]],
		[[2, S], [2, H], [3, D], [4, C], [6, S]],
		[[2, S], [2, H], [3, D], [3, C], [5, S]],
		[[2, S], [2, H], [2, D], [3, C], [4, S]],
		[[1, S], [2, H], [3, D], [4, C], [5, S]],
		[[2, H], [3, H], [4, H], [5, H], [7, H]],
		[[2, S], [2, H], [2, D], [3, C], [3, S]],
		[[2, S], [2, H], [2, D], [2, C], [3, S]],
		[[1, C], [2, C], [3, C], [4, C], [5, C]],
	]
	for i: int in range(1, ladder.size()):
		assert_eq(PokerHand.compare_cards(_h(ladder[i]), _h(ladder[i - 1])), 1, "category %d beats %d" % [i, i - 1])


func test_wheel_straight_is_five_high() -> void:
	var wheel: Array[int] = PokerHand.evaluate(_h([[1, S], [2, H], [3, D], [4, C], [5, S]]))
	assert_eq(wheel, [Cat.STRAIGHT, 5] as Array[int])
	var six: Array[int] = PokerHand.evaluate(_h([[2, S], [3, H], [4, D], [5, C], [6, S]]))
	assert_eq(PokerHand.compare(six, wheel), 1, "6-high straight beats the wheel")
	var broadway: Array[int] = PokerHand.evaluate(_h([[10, S], [11, H], [12, D], [13, C], [1, S]]))
	assert_eq(broadway, [Cat.STRAIGHT, 14] as Array[int])
	assert_eq(_cat([[12, S], [13, H], [1, D], [2, C], [3, S]]), Cat.HIGH_CARD, "no wrap-around straight")
	var steel: Array[int] = PokerHand.evaluate(_h([[1, H], [2, H], [3, H], [4, H], [5, H]]))
	assert_eq(steel, [Cat.STRAIGHT_FLUSH, 5] as Array[int], "steel wheel")
	assert_eq(PokerHand.name_of(steel), "STRAIGHT FLUSH")


func test_partial_hands() -> void:
	assert_eq(PokerHand.evaluate([]), [PokerHand.NO_HAND] as Array[int])
	assert_eq(PokerHand.name_of(PokerHand.evaluate([])), "NO CARDS")
	assert_eq(PokerHand.evaluate(_h([[1, S]])), [Cat.HIGH_CARD, 14] as Array[int])
	assert_eq(PokerHand.evaluate(_h([[7, S], [7, H]])), [Cat.PAIR, 7] as Array[int])
	assert_eq(PokerHand.evaluate(_h([[7, S], [7, H], [7, D]])), [Cat.THREE_OF_A_KIND, 7] as Array[int])
	assert_eq(PokerHand.evaluate(_h([[7, S], [7, H], [3, D], [3, C]])), [Cat.TWO_PAIR, 7, 3] as Array[int])
	assert_eq(PokerHand.evaluate(_h([[9, S], [9, H], [9, D], [9, C]])), [Cat.FOUR_OF_A_KIND, 9] as Array[int])
	assert_eq(_cat([[2, H], [5, H], [9, H], [12, H]]), Cat.HIGH_CARD, "four of a suit is no flush")
	assert_eq(_cat([[5, S], [6, H], [7, D], [8, C]]), Cat.HIGH_CARD, "four in a row is no straight")
	assert_eq(_cat([[4, S], [4, H], [4, D], [9, C]]), Cat.THREE_OF_A_KIND, "a full house needs 5")
	assert_eq(PokerHand.compare_cards(_h([[2, S]]), []), 1, "one card beats none")
	assert_eq(PokerHand.compare_cards(_h([[2, S], [2, H]]), _h([[1, S], [13, H], [12, D], [10, C], [8, S]])), 1, "a pair of twos beats ace high")


func test_kickers() -> void:
	# Same pair, the kickers decide in order.
	assert_eq(PokerHand.compare_cards(_h([[13, S], [13, H], [9, D]]), _h([[13, D], [13, C], [8, S]])), 1)
	assert_eq(PokerHand.compare_cards(_h([[13, S], [13, H], [9, D], [4, C]]), _h([[13, D], [13, C], [9, S], [3, H]])), 1)
	# The higher pair beats more kickers; more kickers win on the same pair.
	assert_eq(PokerHand.compare_cards(_h([[1, S], [1, H]]), _h([[13, D], [13, C], [12, S], [11, H], [10, D]])), 1)
	assert_eq(PokerHand.compare_cards(_h([[13, S], [13, H], [2, D]]), _h([[13, D], [13, C]])), 1, "then the highest card")
	# Two pair: the top pair, then the low pair, then the kicker.
	assert_eq(PokerHand.compare_cards(_h([[10, S], [10, H], [3, D], [3, C], [2, S]]), _h([[9, S], [9, H], [8, D], [8, C], [1, S]])), 1)
	assert_eq(PokerHand.compare_cards(_h([[10, S], [10, H], [4, D], [4, C], [2, S]]), _h([[10, D], [10, C], [3, D], [3, C], [1, S]])), 1)
	assert_eq(PokerHand.compare_cards(_h([[10, S], [10, H], [4, D], [4, C], [6, S]]), _h([[10, D], [10, C], [4, S], [4, H], [5, S]])), 1)
	# Full house: the trips first.
	assert_eq(PokerHand.compare_cards(_h([[3, S], [3, H], [3, D], [2, C], [2, S]]), _h([[2, D], [2, H], [2, C], [1, S], [1, H]])), 1)
	# Flush: card by card; high card: card by card.
	assert_eq(PokerHand.compare_cards(_h([[1, H], [9, H], [7, H], [4, H], [2, H]]), _h([[1, S], [9, S], [7, S], [3, S], [2, S]])), 1)
	assert_eq(PokerHand.compare_cards(_h([[1, H], [9, D], [7, H], [4, C], [2, H]]), _h([[1, S], [9, S], [6, D], [4, S], [2, D]])), 1)
	assert_eq(PokerHand.evaluate(_h([[4, S], [13, H], [4, D], [9, C], [13, S]])), [Cat.TWO_PAIR, 13, 4, 9] as Array[int])


func test_ties_ignore_suits() -> void:
	assert_eq(PokerHand.compare_cards(_h([[13, S], [13, H], [9, D]]), _h([[13, D], [13, C], [9, S]])), 0)
	assert_eq(PokerHand.compare_cards(_h([[5, S], [6, S], [7, S], [8, S], [9, S]]), _h([[5, H], [6, H], [7, H], [8, H], [9, H]])), 0)
	assert_eq(PokerHand.compare_cards(_h([[5, S], [6, H], [7, D], [8, C], [9, S]]), _h([[9, H], [8, H], [7, S], [6, D], [5, C]])), 0, "order does not matter")
	assert_eq(PokerHand.compare_cards([], []), 0)


func test_names_and_descriptions() -> void:
	assert_eq(PokerHand.name_of(PokerHand.evaluate(_h([[2, S], [2, H], [9, D], [9, C]]))), "TWO PAIR")
	assert_eq(PokerHand.describe(PokerHand.evaluate(_h([[13, S], [13, H]]))), "PAIR OF KINGS")
	assert_eq(PokerHand.describe(PokerHand.evaluate(_h([[1, S], [4, H]]))), "ACE HIGH")
	assert_eq(PokerHand.describe(PokerHand.evaluate(_h([[7, S], [7, H], [7, D], [3, C], [3, S]]))), "FULL HOUSE, SEVENS OVER THREES")
	assert_eq(PokerHand.card_name(Card.make(13, H)), "KING OF HEARTS")


func test_worst_index_keeps_the_best_hand() -> void:
	# Pair of nines plus 2, K: the 2 goes (the pair and the king stay).
	assert_eq(PokerHand.worst_index(_h([[9, S], [2, H], [9, D], [13, C]])), 1)
	# Four to a flush and an odd card: the odd one goes only if it doesn't break a pair.
	assert_eq(PokerHand.worst_index(_h([[5, H], [8, H], [3, S], [11, H], [12, H]])), 2)
	assert_eq(PokerHand.worst_index(_h([[1, S]])), 0)
	assert_eq(PokerHand.worst_index([]), -1)
