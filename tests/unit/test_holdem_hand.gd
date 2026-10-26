extends GutTest
## Casino Hold'em hand evaluation (`HoldemHand`): all ten categories (royal flush named apart from
## the other straight flushes), kickers, the best five of seven, the wheel, the names the overlay
## shows, the dealer's qualifying rule and the draws the simple strategy calls with.

const S: int = 0
const H: int = 1
const D: int = 2
const C: int = 3


## A card from a short name: "AS", "10H", "7D", "KC".
func _c(name: String) -> int:
	var suit: int = "SHDC".find(name.right(1))
	var r: String = name.left(name.length() - 1)
	var rank: int = {"A": 1, "J": 11, "Q": 12, "K": 13}.get(r, 0) if not r.is_valid_int() else int(r)
	return Card.make(rank, suit)


func _h(names: String) -> Array[int]:
	var out: Array[int] = []
	for n: String in names.split(" ", false):
		out.append(_c(n))
	return out


func _score(names: String) -> int:
	return HoldemHand.evaluate(_h(names))


func _cat(names: String) -> int:
	return HoldemHand.category(_score(names))


func test_every_category_from_seven_cards() -> void:
	assert_eq(_cat("AS KD 9H 7C 4S 3D 2H"), HoldemHand.Rank.HIGH_CARD)
	assert_eq(_cat("AS AD 9H 7C 4S 3D 2H"), HoldemHand.Rank.PAIR)
	assert_eq(_cat("AS AD 9H 9C 4S 3D 2H"), HoldemHand.Rank.TWO_PAIR)
	assert_eq(_cat("AS AD AH 9C 4S 3D 2H"), HoldemHand.Rank.THREE_OF_A_KIND)
	assert_eq(_cat("6S 5D 4H 3C 2S KD QH"), HoldemHand.Rank.STRAIGHT)
	assert_eq(_cat("AH 9H 7H 4H 2H KD QS"), HoldemHand.Rank.FLUSH)
	assert_eq(_cat("AS AD AH 9C 9S 3D 2H"), HoldemHand.Rank.FULL_HOUSE)
	assert_eq(_cat("AS AD AH AC 9S 3D 2H"), HoldemHand.Rank.FOUR_OF_A_KIND)
	assert_eq(_cat("9H 8H 7H 6H 5H KD QS"), HoldemHand.Rank.STRAIGHT_FLUSH)
	assert_eq(_cat("AH KH QH JH 10H 2D 3S"), HoldemHand.Rank.ROYAL_FLUSH)
	# Every category beats the one under it.
	var ladder: Array[String] = ["AS KD 9H 7C 4S 3D 2H", "2S 2D 9H 7C 4S 3D KH", "3S 3D 2H 2C 5S 7D 9H", "2S 2D 2H 7C 4S 9D KH",
		"5S 4D 3H 2C AS 9D 9H", "7H 5H 4H 3H 2H 2D 2S", "2S 2D 2H 3C 3S 9D KH", "2S 2D 2H 2C 3S 9D KH", "5H 4H 3H 2H AH KD KS", "AH KH QH JH 10H 2D 3S"]
	for i: int in range(1, ladder.size()):
		assert_gt(_score(ladder[i]), _score(ladder[i - 1]), "%s beats %s" % [HoldemHand.category_name(i), HoldemHand.category_name(i - 1)])


func test_kickers_decide_inside_a_category() -> void:
	assert_gt(_score("AS AD KH 7C 4S 3D 2H"), _score("AS AD QH 7C 4S 3D 2H"), "pair of aces, king kicker beats queen")
	assert_gt(_score("KS KD 9H 9C AS 3D 2H"), _score("KS KD 9H 9C QS 3D 2H"), "two pair: the fifth card")
	assert_gt(_score("KS KD 9H 9C 2S 3D 2H"), _score("KS KD 8H 8C AS 3D 2H"), "two pair: the second pair before any kicker")
	assert_gt(_score("7S 7D 7H AC 4S 3D 2H"), _score("7S 7D 7H KC QS 3D 2H"))
	assert_gt(_score("AH 9H 7H 4H 3H"), _score("AH 9H 7H 4H 2H"), "flush: the fifth card counts")
	assert_gt(_score("3S 3D 3H 2C 2S"), _score("2S 2D 2H AC AS"), "full house: the three decide first")
	assert_gt(_score("9S 9D 9H 9C AS"), _score("9S 9D 9H 9C KS"), "quads: the kicker")
	assert_eq(_score("AS AD KH 7C 4S 3D 2H"), _score("AH AC KS 7D 4H 3S 2C"), "same ranks in other suits tie")
	# Only five cards play: a sixth and seventh kicker never count.
	assert_eq(_score("AS AD KH QC JS 3D 2H"), _score("AH AC KS QD JH 5S 4C"), "two low cards that don't play")


func test_best_five_of_seven() -> void:
	# Three pairs: the best two and the best card left (the third pair's rank) as the kicker.
	var s: int = _score("KS KD 9H 9C 5S 5D 2H")
	assert_eq(HoldemHand.category(s), HoldemHand.Rank.TWO_PAIR)
	assert_eq([HoldemHand.kicker(s, 0), HoldemHand.kicker(s, 1), HoldemHand.kicker(s, 2)], [13, 9, 5])
	# Two sets make a full house of the higher over the lower.
	s = _score("8S 8D 8H 3C 3S 3D KH")
	assert_eq(HoldemHand.category(s), HoldemHand.Rank.FULL_HOUSE)
	assert_eq([HoldemHand.kicker(s, 0), HoldemHand.kicker(s, 1)], [8, 3])
	# Six to a straight: the top five.
	s = _score("9S 8D 7H 6C 5S 4D KH")
	assert_eq(HoldemHand.kicker(s, 0), 9)
	# Six of a suit: the top five of them.
	s = _score("AH QH 9H 7H 4H 2H KS")
	assert_eq(HoldemHand.category(s), HoldemHand.Rank.FLUSH)
	assert_eq(HoldemHand.kicker(s, 4), 4, "the deuce of hearts does not play")
	# A straight flush inside a flush beats the plain flush's higher cards.
	assert_eq(_cat("AH 9H 8H 7H 6H 5H 2D"), HoldemHand.Rank.STRAIGHT_FLUSH)
	# The cards that play.
	var five: Array[int] = HoldemHand.best_five(_h("KS KD 9H 9C 5S 5D 2H"))
	assert_eq(five.size(), 5)
	assert_eq(HoldemHand.evaluate(five), _score("KS KD 9H 9C 5S 5D 2H"))
	assert_false(_c("2H") in five)


func test_the_wheel_and_the_ace() -> void:
	var wheel: int = _score("AS 2D 3H 4C 5S KD KH")
	assert_eq(HoldemHand.category(wheel), HoldemHand.Rank.STRAIGHT, "A-2-3-4-5")
	assert_eq(HoldemHand.kicker(wheel, 0), 5, "five high")
	assert_lt(wheel, _score("2S 3D 4H 5C 6S KD KH"), "the six-high straight beats the wheel")
	assert_eq(_cat("QS KD AH 2C 3S 9D 7H"), HoldemHand.Rank.HIGH_CARD, "no wrap-around straight")
	assert_eq(_cat("5H 4H 3H 2H AH KD KS"), HoldemHand.Rank.STRAIGHT_FLUSH, "the steel wheel")


func test_names() -> void:
	assert_eq(HoldemHand.describe(_score("KS KD 9H 7C 4S 3D 2H")), "Pair of Kings")
	assert_eq(HoldemHand.describe(_score("KS KD 5H 5C 4S 3D 2H")), "Two Pair, Kings and Fives")
	assert_eq(HoldemHand.describe(_score("7S 7D 7H KC 4S")), "Three Sevens")
	assert_eq(HoldemHand.describe(_score("9S 8D 7H 6C 5S")), "Straight, Nine High")
	assert_eq(HoldemHand.describe(_score("AH 9H 7H 4H 2H")), "Flush, Ace High")
	assert_eq(HoldemHand.describe(_score("8S 8D 8H 3C 3S")), "Full House, Eights over Threes")
	assert_eq(HoldemHand.describe(_score("QS QD QH QC 3S")), "Four Queens")
	assert_eq(HoldemHand.describe(_score("9H 8H 7H 6H 5H")), "Straight Flush, Nine High")
	assert_eq(HoldemHand.describe(_score("AH KH QH JH 10H")), "Royal Flush")
	assert_eq(HoldemHand.describe(_score("AS JD 9H 7C 4S")), "Ace High")
	assert_eq(HoldemHand.describe(_score("6S 6D")), "Pair of Sixes", "two hole cards alone")


func test_dealer_qualifies_with_fours_or_better() -> void:
	assert_false(HoldemHand.dealer_qualifies(_score("AS KD 9H 7C 4S 3D 2H")), "ace high does not")
	assert_false(HoldemHand.dealer_qualifies(_score("3S 3D 9H 7C AS KD 2H")), "a pair of threes does not")
	assert_false(HoldemHand.dealer_qualifies(_score("2S 2D 9H 7C AS KD 5H")))
	assert_true(HoldemHand.dealer_qualifies(_score("4S 4D 9H 7C AS KD 2H")), "a pair of fours does")
	assert_true(HoldemHand.dealer_qualifies(_score("AS AD 9H 7C 5S KD 2H")), "aces are the best pair")
	assert_true(HoldemHand.dealer_qualifies(_score("3S 3D 2H 2C AS KD 9H")), "two low pairs do")
	assert_true(HoldemHand.dealer_qualifies(_score("6S 5D 4H 3C 2S KD QH")))


func test_draws() -> void:
	assert_true(HoldemHand.has_flush_draw(_h("AH 9H 7H 4H 2S")))
	assert_false(HoldemHand.has_flush_draw(_h("AH 9H 7H 4S 2S")))
	assert_true(HoldemHand.has_straight_draw(_h("9S 8D 7H 6C 2S")), "open ended")
	assert_true(HoldemHand.has_straight_draw(_h("9S 8D 6H 5C 2S")), "inside")
	assert_true(HoldemHand.has_straight_draw(_h("AS 2D 3H 4C 9S")), "to the wheel")
	assert_true(HoldemHand.has_straight_draw(_h("AS KD QH JC 2S")), "to broadway")
	assert_false(HoldemHand.has_straight_draw(_h("AS KD 9H 7C 2S")))
	assert_true(HoldemLogic.simple_call(_h("2S 7D"), _h("7H 9C KS")), "a pair calls")
	assert_true(HoldemLogic.simple_call(_h("AH 9H"), _h("7H 4H KS")), "a flush draw calls")
	assert_false(HoldemLogic.simple_call(_h("AS JD"), _h("9H 6C 2S")), "nothing folds")


func test_matches_a_brute_force_count_over_random_hands() -> void:
	# Five cards dealt from a deck land in each category at the textbook rate (2,598,960 hands).
	var expect: Array[float] = [1302540, 1098240, 123552, 54912, 10200, 5108, 3744, 624, 36, 4]
	var r := SeededRng.new(77)
	var n: int = 60_000
	var seen: Array[int] = []
	seen.resize(10)
	seen.fill(0)
	var deck: Array[int] = []
	for c: int in 52:
		deck.append(c)
	for i: int in n:
		r.shuffle(deck)
		seen[HoldemHand.category(HoldemHand.evaluate(deck.slice(0, 5)))] += 1
	for cat: int in 5:
		var p: float = expect[cat] / 2598960.0
		var sd: float = sqrt(p * (1.0 - p) / n)
		assert_almost_eq(seen[cat] / float(n), p, 5.0 * sd + 0.0002, "%s rate" % HoldemHand.category_name(cat))
